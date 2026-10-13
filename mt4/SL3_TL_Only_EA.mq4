//+------------------------------------------------------------------+
//|  SL3_TL_Only_EA.mq4                                              |
//|  Session-trendline breakout EA (port of the Pine module ⑩)      |
//|  - Trendlines per session (Asia / London / New York, NY time),   |
//|    each from the 2 latest pivots of the session; an unbroken     |
//|    line is carried into the next session until a new pivot.      |
//|  - Signal = confirmed close beyond the line by TlBufAtr x ATR.   |
//|    ONE trade per break. TL is the only signal source.            |
//|  - SL = SlAtrMult x ATR(14, Wilder), TP = same distance (1:1).   |
//|  - At BePct % of the way to TP -> stop to entry.                 |
//|  - From TrailStartPct % -> stop trails TrailDist ($) behind price|
//|  - Risk RiskPercent % of equity per trade.                       |
//+------------------------------------------------------------------+
#property strict

input string  s0 = "==== General ====";
input int     Magic          = 31338;
input int     ServerMinusNY  = 7;       // broker server time minus New York time (hours)
input double  RiskPercent    = 1.0;     // % of equity risked per trade (0 = FixedLot)
input double  FixedLot       = 0.01;
input int     MaxOpenTrades  = 1;       // a new break is skipped while this many trades are open
input bool    CloseOnOpposite = false;  // close an open trade when the opposite TL breaks
input int     SlippagePts    = 30;
input bool    ShowPanel      = true;
input bool    DrawTrendlines = true;

input string  s1 = "==== Trendlines (same as Pine) ====";
input int     TlPivot        = 3;       // pivot bars each side
input double  TlBufAtr       = 0.1;     // close beyond the line by x ATR
input int     AtrLen         = 14;
input string  TlAsia         = "19:00-03:00"; // NY time
input string  TlLondon       = "03:00-08:00";
input string  TlNewYork      = "08:00-17:00";

input string  s2 = "==== Stop / target / trailing ====";
input double  SlAtrMult      = 1.5;     // stop distance = x ATR ; TP = same distance (1:1)
input double  BePct          = 30.0;    // % of the way to TP -> stop to entry
input double  BeOffset       = 0.0;     // $ beyond entry when moving to break-even
input double  TrailStartPct  = 40.0;    // % of the way to TP -> start trailing
input double  TrailDist      = 1.0;     // trailing distance in price ($)

input string  s3 = "==== Trading hours (server time) ====";
input bool    UseTradeHours  = false;
input string  TradeWindow    = "00:00-23:59";

//==================== state ====================
#define NA EMPTY_VALUE
double rY0 = NA, rY1 = NA, sY0 = NA, sY1 = NA;
int    rX0 = 0, rX1 = 0, sX0 = 0, sX1 = 0;     // absolute bar numbers (left = small)
bool   rBrk = false, sBrk = false, carryR = false, carryS = false;
datetime sessT = 0; int sessNow = 0;
double atrR = 0;
datetime lastDone = 0;                         // open time of the last processed closed bar
bool   warm = false;
int    lastSig = 0; datetime lastSigT = 0; double lastSigLvl = 0;
string lastMsg = "—";

//==================== helpers ====================
int NyMin(datetime t) { datetime ny = t - ServerMinusNY * 3600; return (int)((ny % 86400) / 60); }
int ParseHM(string s) { return (int)StringToInteger(StringSubstr(s, 0, 2)) * 60 + (int)StringToInteger(StringSubstr(s, 3, 2)); }
bool InSess(datetime t, string ss)
{
   int a = ParseHM(StringSubstr(ss, 0, 5)), b = ParseHM(StringSubstr(ss, 6, 5)), m = NyMin(t);
   if (b == 0) b = 1440;
   return a < b ? (m >= a && m < b) : (m >= a || m < b);
}
int SessId(datetime t) { return InSess(t, TlAsia) ? 1 : InSess(t, TlLondon) ? 2 : InSess(t, TlNewYork) ? 3 : 0; }
string SessName(int id) { return id == 1 ? "Asia" : id == 2 ? "London" : id == 3 ? "New York" : "-"; }
bool TradeTimeOK(datetime t)
{
   if (!UseTradeHours) return true;
   int a = ParseHM(StringSubstr(TradeWindow, 0, 5)), b = ParseHM(StringSubstr(TradeWindow, 6, 5)), m = (int)((t % 86400) / 60);
   return a <= b ? (m >= a && m <= b) : (m >= a || m <= b);
}
int AbsX(int shift) { return Bars - 1 - shift; }
int ShiftOf(int x) { return Bars - 1 - x; }
double LineY(double y0, int x0, double y1, int x1, int x) { return x1 == x0 ? y1 : y1 + (y1 - y0) / (x1 - x0) * (x - x1); }
// pivot like ta.pivothigh/low(len, len)
bool IsPH(int s, int n) { if (s + n >= Bars || s - n < 1) return false; for (int j = 1; j <= n; j++) { if (High[s + j] >= High[s]) return false; if (High[s - j] > High[s]) return false; } return true; }
bool IsPL(int s, int n) { if (s + n >= Bars || s - n < 1) return false; for (int j = 1; j <= n; j++) { if (Low[s + j] <= Low[s]) return false; if (Low[s - j] < Low[s]) return false; } return true; }

//==================== trendline engine (one closed bar) ====================
// returns +1 resistance broken, -1 support broken, 0 nothing
int ProcessBar(int c)
{
   double tr = MathMax(High[c] - Low[c], MathMax(MathAbs(High[c] - Close[c + 1]), MathAbs(Low[c] - Close[c + 1])));
   atrR = atrR == 0 ? tr : atrR + (tr - atrR) / AtrLen;

   int id = SessId(Time[c]);
   if (id != 0 && id != SessId(Time[c + 1]))
   {
      sessT = Time[c]; sessNow = id;
      if (rY0 == NA || rBrk) { rY0 = NA; rY1 = NA; carryR = false; } else carryR = true;
      if (sY0 == NA || sBrk) { sY0 = NA; sY1 = NA; carryS = false; } else carryS = true;
      rBrk = false; sBrk = false;
   }
   int s = c + TlPivot, x = AbsX(c), px = AbsX(s);
   if (IsPH(s, TlPivot) && Time[s] >= sessT)
   {
      if (carryR) { rY0 = NA; rY1 = NA; carryR = false; rBrk = false; }
      rY0 = rY1; rX0 = rX1; rY1 = High[s]; rX1 = px;
      if (rY0 != NA) rBrk = false;
   }
   if (IsPL(s, TlPivot) && Time[s] >= sessT)
   {
      if (carryS) { sY0 = NA; sY1 = NA; carryS = false; sBrk = false; }
      sY0 = sY1; sX0 = sX1; sY1 = Low[s]; sX1 = px;
      if (sY0 != NA) sBrk = false;
   }
   int sig = 0;
   if (rY0 != NA && !rBrk && x > rX1)
   {
      double y = LineY(rY0, rX0, rY1, rX1, x);
      if (Close[c] > y + TlBufAtr * atrR) { rBrk = true; sig = 1; lastSigLvl = y; Mark(c, true); }
   }
   if (sY0 != NA && !sBrk && x > sX1)
   {
      double y = LineY(sY0, sX0, sY1, sX1, x);
      if (Close[c] < y - TlBufAtr * atrR) { sBrk = true; sig = sig == 1 ? 0 : -1; lastSigLvl = y; Mark(c, false); }
   }
   if (sig != 0) { lastSig = sig; lastSigT = Time[c]; }
   return sig;
}

//==================== drawing ====================
void DrawLine(string nm, double y0, int x0, double y1, int x1, color col, bool broken)
{
   ObjectDelete(0, nm);
   if (!DrawTrendlines || y0 == NA || y1 == NA) return;
   int s0 = ShiftOf(x0), s1 = ShiftOf(x1);
   if (s0 < 0 || s0 >= Bars || s1 < 0 || s1 >= Bars) return;
   ObjectCreate(0, nm, OBJ_TREND, 0, Time[s0], y0, Time[s1], y1);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, broken ? STYLE_DASH : STYLE_SOLID);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, true);
}
void Mark(int c, bool up)
{
   if (!DrawTrendlines) return;
   string nm = "TLO_B_" + IntegerToString((long)Time[c]) + (up ? "U" : "D");
   if (ObjectFind(0, nm) >= 0) return;
   ObjectCreate(0, nm, OBJ_ARROW, 0, Time[c], up ? Low[c] - atrR * 0.6 : High[c] + atrR * 0.6);
   ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, up ? 233 : 234);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, up ? clrRed : clrDodgerBlue);
}

//==================== trading ====================
int CountOpen(int &dir)
{
   int n = 0; dir = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
      if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() <= OP_SELL) { n++; dir = OrderType() == OP_BUY ? 1 : -1; }
   return n;
}
double LotFor(double slDist)
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP), mn = MarketInfo(Symbol(), MODE_MINLOT), mx = MarketInfo(Symbol(), MODE_MAXLOT);
   double lots = FixedLot;
   if (RiskPercent > 0)
   {
      double tv = MarketInfo(Symbol(), MODE_TICKVALUE), ts = MarketInfo(Symbol(), MODE_TICKSIZE);
      if (tv > 0 && ts > 0 && slDist > 0) lots = AccountEquity() * RiskPercent / 100.0 / (slDist / ts * tv);
   }
   if (step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   return NormalizeDouble(MathMax(mn, MathMin(mx, lots)), 2);
}
void CloseDir(int dir)
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
      if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() <= OP_SELL)
         if ((dir == 1 && OrderType() == OP_BUY) || (dir == -1 && OrderType() == OP_SELL))
            if (!OrderClose(OrderTicket(), OrderLots(), OrderType() == OP_BUY ? Bid : Ask, SlippagePts)) Print("close err ", GetLastError());
}
void Enter(int dir)
{
   int od; int n = CountOpen(od);
   if (CloseOnOpposite && n > 0 && od == -dir) { CloseDir(od); n = CountOpen(od); }
   if (n >= MaxOpenTrades) { lastMsg = "TL " + (dir == 1 ? "UP" : "DOWN") + " skipped: trade already open"; return; }
   if (!TradeTimeOK(TimeCurrent())) { lastMsg = "TL " + (dir == 1 ? "UP" : "DOWN") + " skipped: outside hours"; return; }
   RefreshRates();
   double dist = SlAtrMult * atrR;
   double minD = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if (dist < minD) dist = minD + Point;
   double px = dir == 1 ? Ask : Bid;
   double sl = NormalizeDouble(dir == 1 ? px - dist : px + dist, Digits);
   double tp = NormalizeDouble(dir == 1 ? px + dist : px - dist, Digits);
   double lots = LotFor(dist);
   int t = OrderSend(Symbol(), dir == 1 ? OP_BUY : OP_SELL, lots, px, SlippagePts, sl, tp, "TL " + (dir == 1 ? "UP" : "DN"), Magic, 0, dir == 1 ? clrLime : clrRed);
   lastMsg = t > 0 ? (dir == 1 ? "BUY " : "SELL ") + DoubleToString(lots, 2) + " @ " + DoubleToString(px, Digits) + "  SL " + DoubleToString(sl, Digits) + "  TP " + DoubleToString(tp, Digits)
                   : "OrderSend error " + IntegerToString(GetLastError());
   Print("SL3 TL: ", lastMsg);
}
void Manage()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS) || OrderSymbol() != Symbol() || OrderMagicNumber() != Magic || OrderType() > OP_SELL) continue;
      bool buy = OrderType() == OP_BUY;
      double op = OrderOpenPrice(), tp = OrderTakeProfit(), sl = OrderStopLoss();
      double full = MathAbs(tp - op);
      if (tp == 0 || full <= 0) continue;
      double px = buy ? Bid : Ask;
      double prog = (buy ? px - op : op - px) / full * 100.0;
      double nsl = sl;
      if (prog >= BePct)
      {
         double be = buy ? op + BeOffset : op - BeOffset;
         if (buy ? (sl < be) : (sl > be || sl == 0)) nsl = be;
      }
      if (prog >= TrailStartPct)
      {
         double tr = buy ? px - TrailDist : px + TrailDist;
         if (buy ? tr > nsl : tr < nsl) nsl = tr;
      }
      nsl = NormalizeDouble(nsl, Digits);
      double minD = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
      if (MathAbs(nsl - sl) >= Point && (buy ? px - nsl >= minD : nsl - px >= minD))
         if (!OrderModify(OrderTicket(), op, nsl, tp, 0, clrYellow)) Print("modify err ", GetLastError());
   }
}

//==================== panel ====================
void Panel()
{
   if (!ShowPanel) return;
   int x = AbsX(0);
   string t = "SL3 TL-only EA  |  " + Symbol() + " M" + IntegerToString(Period()) + "\n";
   t += "Session   : " + SessName(sessNow) + "\n";
   t += "Resistance: " + (rY0 != NA ? DoubleToString(LineY(rY0, rX0, rY1, rX1, x), Digits) + (rBrk ? " (broken)" : "") + (carryR ? " (carried)" : "") : "forming") + "\n";
   t += "Support   : " + (sY0 != NA ? DoubleToString(LineY(sY0, sX0, sY1, sX1, x), Digits) + (sBrk ? " (broken)" : "") + (carryS ? " (carried)" : "") : "forming") + "\n";
   t += "Last break: " + (lastSig == 1 ? "UP" : lastSig == -1 ? "DOWN" : "none") + (lastSigT > 0 ? " @ " + DoubleToString(lastSigLvl, Digits) + "  " + TimeToString(lastSigT, TIME_DATE | TIME_MINUTES) : "") + "\n";
   t += "ATR       : " + DoubleToString(atrR, 2) + "  -> SL/TP " + DoubleToString(atrR * SlAtrMult, 2) + "\n";
   t += "Last      : " + lastMsg;
   Comment(t);
}

//==================== events ====================
int OnInit()
{
   if (Period() != PERIOD_M15) Print("SL3 TL EA: designed for M15");
   warm = false; lastDone = 0; atrR = 0;
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r)
{
   Comment("");
   ObjectDelete(0, "TLO_R"); ObjectDelete(0, "TLO_S");
}
void OnTick()
{
   if (Bars < 300) return;
   if (!warm)
   {
      // replay history silently (no trades) up to the last closed bar
      int from = MathMin(Bars - TlPivot - 3, 1500);
      for (int c = from; c >= 1; c--) ProcessBar(c);
      lastDone = Time[1]; warm = true;
   }
   else if (Time[1] != lastDone)
   {
      // process any closed bars not yet handled; trade only on the newest
      int k = 1; while (k < Bars - TlPivot - 3 && Time[k] != lastDone) k++;
      for (int c = k - 1; c >= 1; c--)
      {
         int sig = ProcessBar(c);
         if (c == 1 && sig != 0) Enter(sig);
      }
      lastDone = Time[1];
   }
   DrawLine("TLO_R", rY0, rX0, rY1, rX1, clrRed, rBrk);
   DrawLine("TLO_S", sY0, sX0, sY1, sX1, clrDodgerBlue, sBrk);
   Manage();
   Panel();
}
