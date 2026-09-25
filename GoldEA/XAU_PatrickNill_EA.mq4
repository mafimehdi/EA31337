//+------------------------------------------------------------------+
//|                                     XAU_PatrickNill_EA.mq4       |
//|        Patrick Nill PBD Impulse-Range EA for GOLD (XAUUSD)       |
//|        Fully automatic: impulse-range + weekly Value Area +      |
//|        ping-pong & breakout-pullback, ATR risk management.       |
//|        Version 1.00 - MQL4                                       |
//+------------------------------------------------------------------+
#property copyright "GoldEA - Patrick Nill PBD style"
#property link      "https://github.com/EA31337/EA31337"
#property version   "1.00"
#property description "Fully automatic GOLD EA: Impulse->Range (PBD), Weekly Value Area filter, Ping-Pong + Breakout-Pullback, ATR stops, risk% sizing."
#property strict

//--- TP mode
enum ENUM_TP_MODE
  {
   TP_RANGE_EDGE = 0, // TP = opposite range edge (ping-pong)
   TP_RR         = 1, // TP = R:R multiple of SL
   TP_ATR        = 2  // TP = ATR multiple
  };

//=== Inputs: General ===
input long             InpMagic            = 20260925; // Magic number
input int              InpSlippage         = 20;       // Slippage (points)
input int              InpMaxSpreadPoints  = 450;      // Max spread (points, gold)
input bool             InpOnlyGold         = true;     // Trade GOLD symbols only (XAU/GOLD)
input string           InpTradeComment     = "XAU-NillPBD"; // Trade comment
input int              InpMaxPositions     = 1;        // Max positions (this EA)

//=== Inputs: Timeframes ===
input ENUM_TIMEFRAMES  InpSignalTF         = PERIOD_M15; // Signal timeframe (Nill uses M15)
input ENUM_TIMEFRAMES  InpValueAreaTF      = PERIOD_H1;  // Value Area timeframe
input int              InpATRPeriod        = 14;       // ATR period
input int              InpRSIPeriod        = 14;       // RSI period (confirmation)
input bool             InpUseRSIFilter     = true;     // Use RSI confirmation

//=== Inputs: Impulse (P/B leg) ===
input int              InpImpulseBars      = 20;       // Impulse lookback bars
input double           InpImpulseMinATR    = 2.0;      // Min impulse size (x ATR)
input double           InpImpulseDirPct    = 60.0;     // Min directional bars in impulse (%)

//=== Inputs: Range (consolidation) ===
input int              InpRangeBars        = 15;       // Range bars (last N closed bars)
input double           InpRangeMaxATR      = 1.2;      // Max range size (x ATR)
input double           InpRangeMinATR      = 0.25;     // Min range size (x ATR)

//=== Inputs: Weekly Value Area (VAH/VAL) ===
input bool             InpUseVAFilter      = true;     // Use weekly Value Area filter
input int              InpVAWeeks          = 1;        // Weeks for Value Area calc
input double           InpVAPct            = 70.0;     // Value Area volume % (70 = standard)
input int              InpVABins           = 50;       // VA histogram bins
input double           InpVAToleranceATR   = 0.5;      // VA alignment tolerance (x ATR)

//=== Inputs: Entries ===
input bool             InpUsePingPong      = true;     // Allow ping-pong (range edges)
input bool             InpUseBreakout      = true;     // Allow breakout-pullback (continuation)
input bool             InpBreakoutWithImpulseOnly = true; // Breakout only in impulse direction
input double           InpBreakoutConfirmATR = 0.20;   // Breakout confirm distance (x ATR)
input int              InpPullbackBars     = 10;       // Max bars to wait for pullback
input double           InpRejectionBufferATR = 0.10;   // Edge touch buffer (x ATR)

//=== Inputs: Stops & Targets ===
input double           InpStopBufferATR    = 0.30;     // SL buffer beyond edge/level (x ATR)
input ENUM_TP_MODE     InpTPMode           = TP_RR;    // Take-profit mode
input double           InpRR               = 2.0;      // Reward:Risk (if TP_RR)
input double           InpTP_ATRmult       = 2.0;      // TP size (x ATR, if TP_ATR)
input bool             InpUseBreakeven     = true;     // Use breakeven
input double           InpBreakevenStartATR = 1.0;     // Breakeven start (x ATR profit)
input int              InpBreakevenOffsetPoints = 100; // Breakeven offset (points)
input bool             InpUseTrailing      = true;     // Use trailing stop
input double           InpTrailingStartATR = 1.5;      // Trailing start (x ATR profit)
input double           InpTrailingDistATR  = 1.0;      // Trailing distance (x ATR)
input int              InpMaxHoldHours     = 72;       // Max holding hours (0 = off)
input bool             InpCloseOnOpposite  = false;    // Close on opposite signal

//=== Inputs: Risk ===
input double           InpRiskPercent      = 1.0;      // Risk per trade (% of balance)
input double           InpFixedLot         = 0.0;      // Fixed lot (0 = auto by risk%)
input double           InpMaxLot           = 5.0;      // Max lot
input double           InpMaxDailyLossPct  = 3.0;      // Max daily loss % (0 = off)

//=== Inputs: Time filter (server time) ===
input bool             InpUseTimeFilter    = true;     // Use trading hours filter
input int              InpStartHour        = 7;        // Start hour (server time)
input int              InpEndHour          = 21;       // End hour (server time, exclusive)
input bool             InpFridayClose      = true;     // Close all on Friday
input int              InpFridayCloseHour  = 21;       // Friday close hour (server time)

//--- Globals
datetime           g_lastBarTime = 0;
datetime           g_lastEntryBarTime = 0;

bool               g_rangeValid = false;
int                g_impulseDir = 0;
double             g_rangeHigh = 0.0;
double             g_rangeLow = 0.0;
double             g_impulseStart = 0.0;
double             g_impulseEnd = 0.0;
datetime           g_rangeTime = 0;

double             g_vah = 0.0, g_val = 0.0, g_poc = 0.0;
bool               g_vaValid = false;

int                g_breakoutDir = 0;
double             g_breakoutLevel = 0.0;
int                g_breakoutBarsLeft = 0;

int                g_dayKey = -1;
double             g_dayStartBalance = 0.0;

//+------------------------------------------------------------------+
//| Helper: is gold symbol                                           |
//+------------------------------------------------------------------+
bool IsGoldSymbol()
  {
   string s = Symbol();
   StringToUpper(s);
   if(StringFind(s, "XAU") >= 0) return true;
   if(StringFind(s, "GOLD") >= 0) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpOnlyGold && !IsGoldSymbol())
     {
      Alert("XAU_PatrickNill_EA: attach to a GOLD symbol (XAUUSD/GOLD). Current: ", Symbol());
      Print("Not a gold symbol: ", Symbol());
      return(INIT_FAILED);
     }
   if(InpImpulseBars < 5 || InpRangeBars < 5)
     {
      Print("Impulse/Range bars too small.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRiskPercent <= 0 && InpFixedLot <= 0)
     {
      Print("Set InpRiskPercent > 0 or InpFixedLot > 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpVAPct <= 10 || InpVAPct >= 100)
     {
      Print("InpVAPct must be 10..99.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   g_dayStartBalance = AccountBalance();
   g_dayKey = Year() * 1000 + DayOfYear();
   Print("XAU_PatrickNill_EA v1.00 (MQL4) initialized on ", Symbol());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { }

//+------------------------------------------------------------------+
//| New bar detection                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = iTime(NULL, InpSignalTF, 0);
   if(t == 0) return false;
   if(t != g_lastBarTime) { g_lastBarTime = t; return true; }
   return false;
  }

//+------------------------------------------------------------------+
double GetATR(int shift = 1)
  {
   double v = iATR(NULL, InpSignalTF, InpATRPeriod, shift);
   return v;
  }

double GetRSI(int shift = 1)
  {
   double v = iRSI(NULL, InpSignalTF, InpRSIPeriod, PRICE_CLOSE, shift);
   return v;
  }

//+------------------------------------------------------------------+
int CountPositions()
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) c++;
     }
   return c;
  }

//+------------------------------------------------------------------+
bool CheckSpread()
  {
   RefreshRates();
   double spread = MarketInfo(Symbol(), MODE_SPREAD);
   if(spread > InpMaxSpreadPoints) return false;
   return true;
  }

//+------------------------------------------------------------------+
bool CheckTimeFilter()
  {
   if(!InpUseTimeFilter) return true;
   int h = Hour();
   if(InpStartHour <= InpEndHour)
     {
      if(h < InpStartHour || h >= InpEndHour) return false;
     }
   else
     {
      if(h < InpStartHour && h >= InpEndHour) return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
bool CheckDailyLoss()
  {
   if(InpMaxDailyLossPct <= 0) return true;
   int key = Year() * 1000 + DayOfYear();
   if(key != g_dayKey)
     {
      g_dayKey = key;
      g_dayStartBalance = AccountBalance();
      return true;
     }
   double equity = AccountEquity();
   double maxLoss = g_dayStartBalance * InpMaxDailyLossPct / 100.0;
   if(equity < g_dayStartBalance - maxLoss) return false;
   return true;
  }

//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      RefreshRates();
      double px = (type == OP_BUY) ? MarketInfo(Symbol(), MODE_BID) : MarketInfo(Symbol(), MODE_ASK);
      px = NormalizeDouble(px, Digits);
      bool ok = OrderClose(OrderTicket(), OrderLots(), px, InpSlippage, clrNONE);
      if(ok) Print("Close #", OrderTicket(), " reason=", reason);
      else Print("Close failed #", OrderTicket(), " err=", GetLastError());
     }
  }

void CheckFridayClose()
  {
   if(!InpFridayClose) return;
   if(DayOfWeek() == 5 && Hour() >= InpFridayCloseHour) CloseAllPositions("FridayClose");
  }

bool IsFridayBlocked()
  {
   if(!InpFridayClose) return false;
   if(DayOfWeek() == 5 && Hour() >= InpFridayCloseHour) return true;
   return false;
  }

//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double stepLot = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(stepLot <= 0) stepLot = 0.01;
   if(minLot <= 0) minLot = 0.01;
   if(maxLot <= 0) maxLot = 100.0;
   lot = MathFloor(lot / stepLot + 1e-8) * stepLot;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathMin(lot, InpMaxLot);
   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
double CalcLot(double slDistPrice)
  {
   if(InpFixedLot > 0) return NormalizeLot(InpFixedLot);
   if(slDistPrice <= 0) return 0.0;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickValue <= 0 || tickSize <= 0) return 0.0;
   double balance = AccountBalance();
   if(balance <= 0) return 0.0;
   double riskMoney = balance * InpRiskPercent / 100.0;
   double lossPerLot = slDistPrice / tickSize * tickValue;
   if(lossPerLot <= 0) return 0.0;
   double lot = riskMoney / lossPerLot;
   lot = NormalizeLot(lot);
   return lot;
  }

//+------------------------------------------------------------------+
double StopsLevelPrice()
  {
   double lvl = MarketInfo(Symbol(), MODE_STOPLEVEL);
   return lvl * Point;
  }

//+------------------------------------------------------------------+
bool OpenBuyPos(double slPrice, double tpPrice)
  {
   RefreshRates();
   double ask = MarketInfo(Symbol(), MODE_ASK);
   if(ask <= 0) return false;
   double minDist = StopsLevelPrice() + 2 * Point;
   if(ask - slPrice < minDist) slPrice = ask - minDist;
   if(tpPrice > 0 && tpPrice - ask < minDist) tpPrice = ask + minDist;
   slPrice = NormalizeDouble(slPrice, Digits);
   tpPrice = NormalizeDouble(tpPrice, Digits);
   if(slPrice >= ask) return false;
   double lot = CalcLot(ask - slPrice);
   if(lot <= 0) return false;
   int ticket = OrderSend(Symbol(), OP_BUY, lot, ask, InpSlippage, slPrice, tpPrice, InpTradeComment, (int)InpMagic, 0, clrDodgerBlue);
   if(ticket < 0) { Print("Buy failed err=", GetLastError()); return false; }
   return true;
  }

bool OpenSellPos(double slPrice, double tpPrice)
  {
   RefreshRates();
   double bid = MarketInfo(Symbol(), MODE_BID);
   if(bid <= 0) return false;
   double minDist = StopsLevelPrice() + 2 * Point;
   if(slPrice - bid < minDist) slPrice = bid + minDist;
   if(tpPrice > 0 && bid - tpPrice < minDist) tpPrice = bid - minDist;
   slPrice = NormalizeDouble(slPrice, Digits);
   tpPrice = NormalizeDouble(tpPrice, Digits);
   if(slPrice <= bid) return false;
   double lot = CalcLot(slPrice - bid);
   if(lot <= 0) return false;
   int ticket = OrderSend(Symbol(), OP_SELL, lot, bid, InpSlippage, slPrice, tpPrice, InpTradeComment, (int)InpMagic, 0, clrTomato);
   if(ticket < 0) { Print("Sell failed err=", GetLastError()); return false; }
   return true;
  }

//+------------------------------------------------------------------+
//| Weekly Value Area (volume profile approximation)                 |
//+------------------------------------------------------------------+
bool CalcValueArea(double &vah, double &val, double &poc)
  {
   vah = 0; val = 0; poc = 0;
   int barsPerWeek = 120;
   if(InpValueAreaTF == PERIOD_M15) barsPerWeek = 480;
   else if(InpValueAreaTF == PERIOD_M30) barsPerWeek = 240;
   else if(InpValueAreaTF == PERIOD_H1) barsPerWeek = 120;
   else if(InpValueAreaTF == PERIOD_H4) barsPerWeek = 30;
   else if(InpValueAreaTF == PERIOD_D1) barsPerWeek = 5;
   int need = barsPerWeek * InpVAWeeks;
   if(need < 30) need = 30;
   if(need > 1500) need = 1500;
   int total = iBars(NULL, InpValueAreaTF);
   if(total < need + 2) need = total - 2;
   if(need < 30) return false;

   double hi = iHigh(NULL, InpValueAreaTF, 1);
   double lo = iLow(NULL, InpValueAreaTF, 1);
   for(int i = 2; i <= need; i++)
     {
      double h = iHigh(NULL, InpValueAreaTF, i);
      double l = iLow(NULL, InpValueAreaTF, i);
      if(h > hi) hi = h;
      if(l < lo) lo = l;
     }
   double range = hi - lo;
   if(range <= 0) return false;

   int bins = InpVABins;
   if(bins < 20) bins = 20;
   if(bins > 200) bins = 200;
   double binSize = range / bins;
   double vols[];
   ArrayResize(vols, bins);
   ArrayInitialize(vols, 0.0);

   double totalV = 0.0;
   for(int i = 1; i <= need; i++)
     {
      double px = iClose(NULL, InpValueAreaTF, i);
      double v = (double)iVolume(NULL, InpValueAreaTF, i);
      if(v <= 0) v = 1.0;
      int b = (int)((px - lo) / binSize);
      if(b < 0) b = 0;
      if(b >= bins) b = bins - 1;
      vols[b] += v;
      totalV += v;
     }
   if(totalV <= 0) return false;

   int poci = 0;
   double mx = vols[0];
   for(int i = 1; i < bins; i++) { if(vols[i] > mx) { mx = vols[i]; poci = i; } }

   double target = totalV * InpVAPct / 100.0;
   double acc = vols[poci];
   int up = poci + 1, dn = poci - 1;
   int topBin = poci, botBin = poci;
   while(acc < target && (up < bins || dn >= 0))
     {
      double vUp = (up < bins) ? vols[up] : -1.0;
      double vDn = (dn >= 0) ? vols[dn] : -1.0;
      if(vUp >= vDn && up < bins) { acc += vUp; topBin = up; up++; }
      else if(dn >= 0) { acc += vDn; botBin = dn; dn--; }
      else break;
     }
   vah = lo + (topBin + 1) * binSize;
   val = lo + botBin * binSize;
   poc = lo + (poci + 0.5) * binSize;
   return (vah > val && vah > 0 && val > 0);
  }

//+------------------------------------------------------------------+
bool VAFilterOK(double atr)
  {
   if(!InpUseVAFilter) return true;
   if(!g_vaValid) return false;
   double tol = InpVAToleranceATR * atr;
   if(g_vah >= g_rangeLow && g_vah <= g_rangeHigh) return true;
   if(g_val >= g_rangeLow && g_val <= g_rangeHigh) return true;
   if(g_poc >= g_rangeLow && g_poc <= g_rangeHigh) return true;
   if(MathAbs(g_rangeHigh - g_vah) <= tol) return true;
   if(MathAbs(g_rangeLow - g_vah) <= tol) return true;
   if(MathAbs(g_rangeHigh - g_val) <= tol) return true;
   if(MathAbs(g_rangeLow - g_val) <= tol) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Detect Impulse -> Range (PBD)                                    |
//+------------------------------------------------------------------+
bool DetectImpulseRange(double atr)
  {
   g_rangeValid = false;
   g_impulseDir = 0;
   if(atr <= 0) return false;
   int need = InpImpulseBars + InpRangeBars + 3;
   if(iBars(NULL, InpSignalTF) < need + 2) return false;

   double rh = iHigh(NULL, InpSignalTF, 1);
   double rl = iLow(NULL, InpSignalTF, 1);
   for(int i = 2; i <= InpRangeBars; i++)
     {
      double h = iHigh(NULL, InpSignalTF, i);
      double l = iLow(NULL, InpSignalTF, i);
      if(h > rh) rh = h;
      if(l < rl) rl = l;
     }
   double rsize = rh - rl;
   if(rsize < InpRangeMinATR * atr || rsize > InpRangeMaxATR * atr) return false;

   int i0 = InpRangeBars + 1;
   int i1 = InpRangeBars + InpImpulseBars;
   double startPx = iClose(NULL, InpSignalTF, i1);
   double endPx = iClose(NULL, InpSignalTF, i0);
   double net = endPx - startPx;
   if(MathAbs(net) < InpImpulseMinATR * atr) return false;

   int dir = (net > 0) ? 1 : -1;
   int cntDir = 0;
   for(int i = i0; i <= i1; i++)
     {
      double o = iOpen(NULL, InpSignalTF, i);
      double c = iClose(NULL, InpSignalTF, i);
      if(dir > 0 && c > o) cntDir++;
      if(dir < 0 && c < o) cntDir++;
     }
   double pct = 100.0 * cntDir / InpImpulseBars;
   if(pct < InpImpulseDirPct) return false;

   if(dir > 0)
     {
      if(rl <= startPx) return false;
      if(endPx < rl - 0.5 * atr) return false;
      if(endPx > rh + 1.0 * atr) return false;
     }
   else
     {
      if(rh >= startPx) return false;
      if(endPx > rh + 0.5 * atr) return false;
      if(endPx < rl - 1.0 * atr) return false;
     }

   g_rangeValid = true;
   g_impulseDir = dir;
   g_rangeHigh = rh;
   g_rangeLow = rl;
   g_impulseStart = startPx;
   g_impulseEnd = endPx;
   g_rangeTime = iTime(NULL, InpSignalTF, 1);
   return true;
  }

//+------------------------------------------------------------------+
void UpdateMarketState()
  {
   double atr = GetATR(1);
   if(atr <= 0) { g_rangeValid = false; g_vaValid = false; return; }
   DetectImpulseRange(atr);
   double vah, val, poc;
   g_vaValid = CalcValueArea(vah, val, poc);
   if(g_vaValid) { g_vah = vah; g_val = val; g_poc = poc; }
   if(g_breakoutBarsLeft > 0)
     {
      g_breakoutBarsLeft--;
      if(g_breakoutBarsLeft <= 0) { g_breakoutDir = 0; g_breakoutLevel = 0.0; }
     }
  }

//+------------------------------------------------------------------+
void ManagePositions(double atrLive)
  {
   double atr = (atrLive > 0) ? atrLive : GetATR(1);
   if(atr <= 0) atr = 10 * Point;
   double minDist = StopsLevelPrice();
   RefreshRates();
   double bid = MarketInfo(Symbol(), MODE_BID);
   double ask = MarketInfo(Symbol(), MODE_ASK);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      double open = OrderOpenPrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      datetime ot = OrderOpenTime();

      if(InpMaxHoldHours > 0 && TimeCurrent() - ot >= InpMaxHoldHours * 3600)
        {
         RefreshRates();
         double px = (type == OP_BUY) ? MarketInfo(Symbol(), MODE_BID) : MarketInfo(Symbol(), MODE_ASK);
         px = NormalizeDouble(px, Digits);
         if(OrderClose(OrderTicket(), OrderLots(), px, InpSlippage, clrNONE))
            Print("Time exit #", OrderTicket());
         continue;
        }

      if(type == OP_BUY)
        {
         double profit = bid - open;
         double newSL = sl;
         if(InpUseBreakeven && profit >= InpBreakevenStartATR * atr)
           {
            double be = NormalizeDouble(open + InpBreakevenOffsetPoints * Point, Digits);
            if(be > newSL + Point) newSL = be;
           }
         if(InpUseTrailing && profit >= InpTrailingStartATR * atr)
           {
            double tr = NormalizeDouble(bid - InpTrailingDistATR * atr, Digits);
            if(tr > newSL + Point) newSL = tr;
           }
         if(newSL > 0 && bid - newSL >= minDist + Point && MathAbs(newSL - sl) >= Point)
           {
            if(newSL > sl || sl <= 0)
              {
               bool ok = OrderModify(OrderTicket(), open, NormalizeDouble(newSL, Digits), tp, 0, clrNONE);
               if(!ok) Print("Modify Buy failed err=", GetLastError());
              }
           }
        }
      else if(type == OP_SELL)
        {
         double profit = open - ask;
         double newSL = sl;
         if(InpUseBreakeven && profit >= InpBreakevenStartATR * atr)
           {
            double be = NormalizeDouble(open - InpBreakevenOffsetPoints * Point, Digits);
            if(be < newSL - Point || sl <= 0) newSL = be;
           }
         if(InpUseTrailing && profit >= InpTrailingStartATR * atr)
           {
            double tr = NormalizeDouble(ask + InpTrailingDistATR * atr, Digits);
            if(sl <= 0 || tr < newSL - Point) newSL = tr;
           }
         if(newSL > 0 && newSL - ask >= minDist + Point && MathAbs(newSL - sl) >= Point)
           {
            if(sl <= 0 || newSL < sl)
              {
               bool ok = OrderModify(OrderTicket(), open, NormalizeDouble(newSL, Digits), tp, 0, clrNONE);
               if(!ok) Print("Modify Sell failed err=", GetLastError());
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
void TryPingPongEntry(double atr)
  {
   if(!InpUsePingPong) return;
   if(!g_rangeValid) return;
   if(!VAFilterOK(atr)) return;
   if(g_lastEntryBarTime == g_rangeTime && CountPositions() > 0) return;

   double o = iOpen(NULL, InpSignalTF, 1);
   double c = iClose(NULL, InpSignalTF, 1);
   double h = iHigh(NULL, InpSignalTF, 1);
   double l = iLow(NULL, InpSignalTF, 1);
   double buffer = InpRejectionBufferATR * atr;
   double rsi = GetRSI(1);

   bool touchLow = (l <= g_rangeLow + buffer);
   bool insideLow = (c > g_rangeLow && c < g_rangeHigh);
   bool bullRej = (c > o);
   bool rsiBuyOK = (!InpUseRSIFilter) || (rsi < 65.0);
   if(touchLow && insideLow && bullRej && rsiBuyOK)
     {
      RefreshRates();
      double entryRef = MarketInfo(Symbol(), MODE_ASK);
      double sl = g_rangeLow - InpStopBufferATR * atr;
      double tp = 0;
      if(InpTPMode == TP_RANGE_EDGE) tp = g_rangeHigh - buffer * 0.5;
      else if(InpTPMode == TP_RR) tp = entryRef + InpRR * (entryRef - sl);
      else tp = entryRef + InpTP_ATRmult * atr;
      if(sl < entryRef && (tp <= 0 || tp > entryRef))
        {
         if(OpenBuyPos(sl, tp))
           {
            g_lastEntryBarTime = g_rangeTime;
            g_breakoutDir = 0; g_breakoutBarsLeft = 0;
            return;
           }
        }
     }

   bool touchHigh = (h >= g_rangeHigh - buffer);
   bool insideHigh = (c < g_rangeHigh && c > g_rangeLow);
   bool bearRej = (c < o);
   bool rsiSellOK = (!InpUseRSIFilter) || (rsi > 35.0);
   if(touchHigh && insideHigh && bearRej && rsiSellOK)
     {
      RefreshRates();
      double entryRef = MarketInfo(Symbol(), MODE_BID);
      double sl = g_rangeHigh + InpStopBufferATR * atr;
      double tp = 0;
      if(InpTPMode == TP_RANGE_EDGE) tp = g_rangeLow + buffer * 0.5;
      else if(InpTPMode == TP_RR) tp = entryRef - InpRR * (sl - entryRef);
      else tp = entryRef - InpTP_ATRmult * atr;
      if(sl > entryRef && (tp <= 0 || tp < entryRef))
        {
         if(OpenSellPos(sl, tp))
           {
            g_lastEntryBarTime = g_rangeTime;
            g_breakoutDir = 0; g_breakoutBarsLeft = 0;
            return;
           }
        }
     }
  }

//+------------------------------------------------------------------+
void TryBreakoutEntry(double atr)
  {
   if(!InpUseBreakout) return;
   double o = iOpen(NULL, InpSignalTF, 1);
   double c = iClose(NULL, InpSignalTF, 1);
   double h = iHigh(NULL, InpSignalTF, 1);
   double l = iLow(NULL, InpSignalTF, 1);
   double confirm = InpBreakoutConfirmATR * atr;
   double buffer = InpRejectionBufferATR * atr;

   if(g_breakoutDir == 0 && g_rangeValid && VAFilterOK(atr))
     {
      bool bullBreak = (c > g_rangeHigh + confirm);
      bool bearBreak = (c < g_rangeLow - confirm);
      if(InpBreakoutWithImpulseOnly)
        {
         bullBreak = bullBreak && (g_impulseDir > 0);
         bearBreak = bearBreak && (g_impulseDir < 0);
        }
      if(bullBreak)
        {
         g_breakoutDir = 1; g_breakoutLevel = g_rangeHigh;
         g_breakoutBarsLeft = InpPullbackBars;
         Print("Bull breakout detected at ", DoubleToString(g_breakoutLevel, Digits));
         return;
        }
      if(bearBreak)
        {
         g_breakoutDir = -1; g_breakoutLevel = g_rangeLow;
         g_breakoutBarsLeft = InpPullbackBars;
         Print("Bear breakout detected at ", DoubleToString(g_breakoutLevel, Digits));
         return;
        }
     }

   if(g_breakoutDir != 0 && g_breakoutBarsLeft > 0 && VAFilterOK(atr))
     {
      double rsi = GetRSI(1);
      if(g_breakoutDir > 0)
        {
         bool retest = (l <= g_breakoutLevel + buffer && l >= g_breakoutLevel - InpStopBufferATR * atr - confirm);
         bool holdAbove = (c > g_breakoutLevel);
         bool bull = (c > o);
         bool rsiOK = (!InpUseRSIFilter) || (rsi > 45.0);
         if(retest && holdAbove && bull && rsiOK)
           {
            RefreshRates();
            double entryRef = MarketInfo(Symbol(), MODE_ASK);
            double sl = g_breakoutLevel - InpStopBufferATR * atr;
            double tp;
            if(InpTPMode == TP_ATR) tp = entryRef + InpTP_ATRmult * atr;
            else tp = entryRef + InpRR * (entryRef - sl);
            if(sl < entryRef)
              {
               if(OpenBuyPos(sl, tp))
                 {
                  g_breakoutDir = 0; g_breakoutBarsLeft = 0;
                  g_lastEntryBarTime = iTime(NULL, InpSignalTF, 1);
                 }
              }
           }
        }
      else
        {
         bool retest = (h >= g_breakoutLevel - buffer && h <= g_breakoutLevel + InpStopBufferATR * atr + confirm);
         bool holdBelow = (c < g_breakoutLevel);
         bool bear = (c < o);
         bool rsiOK = (!InpUseRSIFilter) || (rsi < 55.0);
         if(retest && holdBelow && bear && rsiOK)
           {
            RefreshRates();
            double entryRef = MarketInfo(Symbol(), MODE_BID);
            double sl = g_breakoutLevel + InpStopBufferATR * atr;
            double tp;
            if(InpTPMode == TP_ATR) tp = entryRef - InpTP_ATRmult * atr;
            else tp = entryRef - InpRR * (sl - entryRef);
            if(sl > entryRef)
              {
               if(OpenSellPos(sl, tp))
                 {
                  g_breakoutDir = 0; g_breakoutBarsLeft = 0;
                  g_lastEntryBarTime = iTime(NULL, InpSignalTF, 1);
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
void CheckOppositeClose()
  {
   if(!InpCloseOnOpposite) return;
   if(!g_rangeValid) return;
   double o = iOpen(NULL, InpSignalTF, 1);
   double c = iClose(NULL, InpSignalTF, 1);
   double h = iHigh(NULL, InpSignalTF, 1);
   double l = iLow(NULL, InpSignalTF, 1);
   double buffer = InpRejectionBufferATR * GetATR(1);
   bool buySig = (l <= g_rangeLow + buffer && c > g_rangeLow && c > o);
   bool sellSig = (h >= g_rangeHigh - buffer && c < g_rangeHigh && c < o);
   if(!buySig && !sellSig) return;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      int type = OrderType();
      bool doClose = ((type == OP_BUY && sellSig) || (type == OP_SELL && buySig));
      if(doClose)
        {
         RefreshRates();
         double px = (type == OP_BUY) ? MarketInfo(Symbol(), MODE_BID) : MarketInfo(Symbol(), MODE_ASK);
         px = NormalizeDouble(px, Digits);
         OrderClose(OrderTicket(), OrderLots(), px, InpSlippage, clrNONE);
        }
     }
  }

//+------------------------------------------------------------------+
//| Main tick                                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(InpOnlyGold && !IsGoldSymbol()) return;

   CheckFridayClose();
   if(IsFridayBlocked()) return;
   if(!CheckDailyLoss()) return;

   double atrLive = GetATR(1);
   ManagePositions(atrLive);

   bool newBar = IsNewBar();
   if(newBar)
     {
      UpdateMarketState();
      CheckOppositeClose();
     }

   if(CountPositions() >= InpMaxPositions) return;
   if(!CheckSpread()) return;
   if(!CheckTimeFilter()) return;
   if(!newBar) return;

   double atr = GetATR(1);
   if(atr <= 0) return;

   if(g_breakoutDir != 0 && g_breakoutBarsLeft > 0)
     {
      TryBreakoutEntry(atr);
      if(CountPositions() >= InpMaxPositions) return;
     }
   TryPingPongEntry(atr);
   if(CountPositions() >= InpMaxPositions) return;
   TryBreakoutEntry(atr);
  }
//+------------------------------------------------------------------+
