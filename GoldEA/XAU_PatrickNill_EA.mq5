//+------------------------------------------------------------------+
//|                                     XAU_PatrickNill_EA.mq5       |
//|        Patrick Nill PBD Impulse-Range EA for GOLD (XAUUSD)       |
//|        Fully automatic: impulse-range + weekly Value Area +      |
//|        ping-pong & breakout-pullback, ATR risk management.       |
//|        Version 1.00 - MQL5                                       |
//+------------------------------------------------------------------+
#property copyright "GoldEA - Patrick Nill PBD style"
#property link      "https://github.com/EA31337/EA31337"
#property version   "1.00"
#property description "Fully automatic GOLD EA: Impulse->Range (PBD), Weekly Value Area filter, Ping-Pong + Breakout-Pullback, ATR stops, risk% sizing."

#include <Trade\Trade.mqh>

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
input int              InpMaxSpreadPoints  = 450;      // Max spread (points, gold ~ 20-50 cents)
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
input int              InpBreakevenOffsetPoints = 100; // Breakeven offset (points above/below entry)
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
CTrade             g_trade;
int                g_atrHandle = INVALID_HANDLE;
int                g_rsiHandle = INVALID_HANDLE;
datetime           g_lastBarTime = 0;
datetime           g_lastEntryBarTime = 0;

// Range state
bool               g_rangeValid = false;
int                g_impulseDir = 0;   // +1 P (bull), -1 B (bear), 0 none
double             g_rangeHigh = 0.0;
double             g_rangeLow = 0.0;
double             g_impulseStart = 0.0;
double             g_impulseEnd = 0.0;
datetime           g_rangeTime = 0;

// Value area state
double             g_vah = 0.0, g_val = 0.0, g_poc = 0.0;
bool               g_vaValid = false;

// Breakout state
int                g_breakoutDir = 0;  // +1 bull, -1 bear
double             g_breakoutLevel = 0.0;
int                g_breakoutBarsLeft = 0;

// Daily guard
int                g_dayKey = -1;
double             g_dayStartBalance = 0.0;

//+------------------------------------------------------------------+
//| Helper: is gold symbol                                           |
//+------------------------------------------------------------------+
bool IsGoldSymbol()
  {
   string s = _Symbol;
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
      Alert("XAU_PatrickNill_EA: attach to a GOLD symbol (XAUUSD/GOLD). Current: ", _Symbol);
      Print("Not a gold symbol: ", _Symbol);
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

   g_trade.SetExpertMagicNumber((long)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);

   g_atrHandle = iATR(_Symbol, InpSignalTF, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("Failed to create ATR handle.");
      return(INIT_FAILED);
     }
   g_rsiHandle = iRSI(_Symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);
   if(g_rsiHandle == INVALID_HANDLE)
     {
      Print("Failed to create RSI handle.");
      return(INIT_FAILED);
     }

   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   g_dayKey = dt.year * 1000 + dt.day_of_year;

   Print("XAU_PatrickNill_EA v1.00 initialized on ", _Symbol, " TF=", EnumToString(InpSignalTF));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
  }

//+------------------------------------------------------------------+
//| New bar detection on signal TF                                   |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, InpSignalTF, 0);
   if(t == 0) return false;
   if(t != g_lastBarTime)
     {
      g_lastBarTime = t;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Get ATR value (closed bar shift, 1 = last closed)                |
//+------------------------------------------------------------------+
double GetATR(int shift = 1)
  {
   double buf[];
   if(CopyBuffer(g_atrHandle, 0, shift, 1, buf) != 1) return 0.0;
   return buf[0];
  }

//+------------------------------------------------------------------+
//| Get RSI value                                                    |
//+------------------------------------------------------------------+
double GetRSI(int shift = 1)
  {
   double buf[];
   if(CopyBuffer(g_rsiHandle, 0, shift, 1, buf) != 1) return 50.0;
   return buf[0];
  }

//+------------------------------------------------------------------+
//| Count our positions                                              |
//+------------------------------------------------------------------+
int CountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      c++;
     }
   return c;
  }

//+------------------------------------------------------------------+
//| Spread filter                                                    |
//+------------------------------------------------------------------+
bool CheckSpread()
  {
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread < 0) return false;
   if(spread > InpMaxSpreadPoints)
     {
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Time filter (server time)                                        |
//+------------------------------------------------------------------+
bool CheckTimeFilter()
  {
   if(!InpUseTimeFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(InpStartHour <= InpEndHour)
     {
      if(h < InpStartHour || h >= InpEndHour) return false;
     }
   else
     {
      // overnight window e.g. 21..7
      if(h < InpStartHour && h >= InpEndHour) return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Daily loss guard                                                 |
//+------------------------------------------------------------------+
bool CheckDailyLoss()
  {
   if(InpMaxDailyLossPct <= 0) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int key = dt.year * 1000 + dt.day_of_year;
   if(key != g_dayKey)
     {
      g_dayKey = key;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      return true;
     }
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double maxLoss = g_dayStartBalance * InpMaxDailyLossPct / 100.0;
   if(equity < g_dayStartBalance - maxLoss)
     {
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Close all our positions                                          |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      g_trade.PositionClose(ticket);
      Print("Close #", ticket, " reason=", reason);
     }
  }

//+------------------------------------------------------------------+
//| Friday close                                                     |
//+------------------------------------------------------------------+
void CheckFridayClose()
  {
   if(!InpFridayClose) return;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour)
     {
      CloseAllPositions("FridayClose");
     }
  }

bool IsFridayBlocked()
  {
   if(!InpFridayClose) return false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Normalize lot                                                    |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0) stepLot = 0.01;
   if(minLot <= 0) minLot = 0.01;
   if(maxLot <= 0) maxLot = 100.0;
   lot = MathFloor(lot / stepLot + 1e-8) * stepLot;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathMin(lot, InpMaxLot);
   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
//| Lot by risk%                                                     |
//+------------------------------------------------------------------+
double CalcLot(double slDistPrice)
  {
   if(InpFixedLot > 0) return NormalizeLot(InpFixedLot);
   if(slDistPrice <= 0) return 0.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return 0.0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return 0.0;
   double riskMoney = balance * InpRiskPercent / 100.0;
   double lossPerLot = slDistPrice / tickSize * tickValue;
   if(lossPerLot <= 0) return 0.0;
   double lot = riskMoney / lossPerLot;
   lot = NormalizeLot(lot);
   // margin check: shrink if not enough free margin
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double margin = 0.0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, price, margin))
     {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin && margin > 0)
        {
         double ratio = freeMargin / margin * 0.9;
         lot = NormalizeLot(lot * ratio);
        }
     }
   return lot;
  }

//+------------------------------------------------------------------+
//| Ensure SL/TP respect stops level                                 |
//+------------------------------------------------------------------+
double StopsLevelPrice()
  {
   long lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(lvl < 0) lvl = 0;
   return (double)lvl * _Point;
  }

bool OpenBuyPos(double slPrice, double tpPrice)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask <= 0) return false;
   double slDist = ask - slPrice;
   if(slDist <= 0) return false;
   double minDist = StopsLevelPrice() + 2 * _Point;
   if(slDist < minDist) slPrice = NormalizeDouble(ask - minDist, _Digits);
   if(tpPrice > 0 && tpPrice - ask < minDist) tpPrice = NormalizeDouble(ask + minDist, _Digits);
   slPrice = NormalizeDouble(slPrice, _Digits);
   tpPrice = NormalizeDouble(tpPrice, _Digits);
   double lot = CalcLot(ask - slPrice);
   if(lot <= 0) return false;
   bool ok = g_trade.Buy(lot, _Symbol, 0.0, slPrice, tpPrice, InpTradeComment);
   if(!ok) Print("Buy failed: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
   return ok;
  }

bool OpenSellPos(double slPrice, double tpPrice)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0) return false;
   double slDist = slPrice - bid;
   if(slDist <= 0) return false;
   double minDist = StopsLevelPrice() + 2 * _Point;
   if(slDist < minDist) slPrice = NormalizeDouble(bid + minDist, _Digits);
   if(tpPrice > 0 && bid - tpPrice < minDist) tpPrice = NormalizeDouble(bid - minDist, _Digits);
   slPrice = NormalizeDouble(slPrice, _Digits);
   tpPrice = NormalizeDouble(tpPrice, _Digits);
   double lot = CalcLot(slPrice - bid);
   if(lot <= 0) return false;
   bool ok = g_trade.Sell(lot, _Symbol, 0.0, slPrice, tpPrice, InpTradeComment);
   if(!ok) Print("Sell failed: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
   return ok;
  }

//+------------------------------------------------------------------+
//| Weekly Value Area calculation (volume profile approximation)     |
//+------------------------------------------------------------------+
bool CalcValueArea(double &vah, double &val, double &poc)
  {
   vah = 0; val = 0; poc = 0;
   int barsPerWeek = 120; // H1 default
   if(InpValueAreaTF == PERIOD_M15) barsPerWeek = 480;
   else if(InpValueAreaTF == PERIOD_M30) barsPerWeek = 240;
   else if(InpValueAreaTF == PERIOD_H1) barsPerWeek = 120;
   else if(InpValueAreaTF == PERIOD_H4) barsPerWeek = 30;
   else if(InpValueAreaTF == PERIOD_D1) barsPerWeek = 5;
   int need = barsPerWeek * InpVAWeeks;
   need = MathMax(30, MathMin(1500, need));

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpValueAreaTF, 0, need, rates);
   if(copied < 30) return false;

   double hi = rates[0].high, lo = rates[0].low;
   for(int i = 1; i < copied; i++)
     {
      if(rates[i].high > hi) hi = rates[i].high;
      if(rates[i].low < lo) lo = rates[i].low;
     }
   double range = hi - lo;
   if(range <= 0) return false;

   int bins = MathMax(20, MathMin(200, InpVABins));
   double binSize = range / bins;
   double vols[];
   ArrayResize(vols, bins);
   ArrayInitialize(vols, 0.0);

   double total = 0.0;
   for(int i = 0; i < copied; i++)
     {
      double px = rates[i].close;
      long v = rates[i].tick_volume;
      if(v <= 0) v = 1;
      int b = (int)((px - lo) / binSize);
      if(b < 0) b = 0;
      if(b >= bins) b = bins - 1;
      vols[b] += (double)v;
      total += (double)v;
     }
   if(total <= 0) return false;

   int poci = 0;
   double mx = vols[0];
   for(int i = 1; i < bins; i++)
     {
      if(vols[i] > mx) { mx = vols[i]; poci = i; }
     }
   double target = total * InpVAPct / 100.0;
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
//| Value Area filter: range must align with VAH/VAL                 |
//+------------------------------------------------------------------+
bool VAFilterOK(double atr)
  {
   if(!InpUseVAFilter) return true;
   if(!g_vaValid) return false;
   double tol = InpVAToleranceATR * atr;
   // inside?
   if(g_vah >= g_rangeLow && g_vah <= g_rangeHigh) return true;
   if(g_val >= g_rangeLow && g_val <= g_rangeHigh) return true;
   if(g_poc >= g_rangeLow && g_poc <= g_rangeHigh) return true;
   // near edges?
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
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, InpSignalTF, 0, need, r);
   if(copied < need) return false;

   // Range = last InpRangeBars closed bars: index 1..RangeBars
   double rh = r[1].high, rl = r[1].low;
   for(int i = 2; i <= InpRangeBars; i++)
     {
      if(r[i].high > rh) rh = r[i].high;
      if(r[i].low < rl) rl = r[i].low;
     }
   double rsize = rh - rl;
   if(rsize < InpRangeMinATR * atr || rsize > InpRangeMaxATR * atr) return false;

   // Impulse = next InpImpulseBars bars: RangeBars+1 .. RangeBars+ImpulseBars
   int i0 = InpRangeBars + 1;                       // newest impulse bar
   int i1 = InpRangeBars + InpImpulseBars;          // oldest impulse bar
   double startPx = r[i1].close;
   double endPx = r[i0].close;
   double net = endPx - startPx;
   if(MathAbs(net) < InpImpulseMinATR * atr) return false;

   int dir = (net > 0) ? 1 : -1;
   int cntDir = 0;
   for(int i = i0; i <= i1; i++)
     {
      if(dir > 0 && r[i].close > r[i].open) cntDir++;
      if(dir < 0 && r[i].close < r[i].open) cntDir++;
     }
   double pct = 100.0 * cntDir / InpImpulseBars;
   if(pct < InpImpulseDirPct) return false;

   // Range must sit above/below impulse origin (P/B structure)
   if(dir > 0)
     {
      if(rl <= startPx) return false;                 // P: range above origin
      if(endPx < rl - 0.5 * atr) return false;        // impulse must reach range
      if(endPx > rh + 1.0 * atr) return false;
     }
   else
     {
      if(rh >= startPx) return false;                 // B: range below origin
      if(endPx > rh + 0.5 * atr) return false;
      if(endPx < rl - 1.0 * atr) return false;
     }

   g_rangeValid = true;
   g_impulseDir = dir;
   g_rangeHigh = rh;
   g_rangeLow = rl;
   g_impulseStart = startPx;
   g_impulseEnd = endPx;
   g_rangeTime = r[1].time;
   return true;
  }

//+------------------------------------------------------------------+
//| Update market state on new bar                                   |
//+------------------------------------------------------------------+
void UpdateMarketState()
  {
   double atr = GetATR(1);
   if(atr <= 0) { g_rangeValid = false; g_vaValid = false; return; }
   DetectImpulseRange(atr);
   double vah, val, poc;
   g_vaValid = CalcValueArea(vah, val, poc);
   if(g_vaValid) { g_vah = vah; g_val = val; g_poc = poc; }

   // decay breakout wait counter each new bar
   if(g_breakoutBarsLeft > 0)
     {
      g_breakoutBarsLeft--;
      if(g_breakoutBarsLeft <= 0) { g_breakoutDir = 0; g_breakoutLevel = 0.0; }
     }
  }

//+------------------------------------------------------------------+
//| Manage open positions: breakeven, trailing, time exit            |
//+------------------------------------------------------------------+
void ManagePositions(double atrLive)
  {
   double atr = (atrLive > 0) ? atrLive : GetATR(1);
   if(atr <= 0) atr = 10 * _Point;
   double minDist = StopsLevelPrice();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;

      long ptype = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);

      // time exit
      if(InpMaxHoldHours > 0 && TimeCurrent() - ot >= InpMaxHoldHours * 3600)
        {
         g_trade.PositionClose(ticket);
         Print("Time exit #", ticket);
         continue;
        }

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(ptype == POSITION_TYPE_BUY)
        {
         double profit = bid - open;
         double newSL = sl;
         // breakeven
         if(InpUseBreakeven && profit >= InpBreakevenStartATR * atr)
           {
            double be = NormalizeDouble(open + InpBreakevenOffsetPoints * _Point, _Digits);
            if(be > newSL + _Point) newSL = be;
           }
         // trailing
         if(InpUseTrailing && profit >= InpTrailingStartATR * atr)
           {
            double tr = NormalizeDouble(bid - InpTrailingDistATR * atr, _Digits);
            if(tr > newSL + _Point) newSL = tr;
           }
         // respect stops level
         if(newSL > 0 && bid - newSL >= minDist + _Point && MathAbs(newSL - sl) >= _Point)
           {
            if(newSL > sl || sl <= 0)
               g_trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tp);
           }
        }
      else if(ptype == POSITION_TYPE_SELL)
        {
         double profit = open - ask;
         double newSL = sl;
         if(InpUseBreakeven && profit >= InpBreakevenStartATR * atr)
           {
            double be = NormalizeDouble(open - InpBreakevenOffsetPoints * _Point, _Digits);
            if(be < newSL - _Point || sl <= 0) newSL = be;
           }
         if(InpUseTrailing && profit >= InpTrailingStartATR * atr)
           {
            double tr = NormalizeDouble(ask + InpTrailingDistATR * atr, _Digits);
            if(sl <= 0 || tr < newSL - _Point) newSL = tr;
           }
         if(newSL > 0 && newSL - ask >= minDist + _Point && MathAbs(newSL - sl) >= _Point)
           {
            if(sl <= 0 || newSL < sl)
               g_trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tp);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Ping-pong entry (range edges + rejection)                        |
//+------------------------------------------------------------------+
void TryPingPongEntry(double atr)
  {
   if(!InpUsePingPong) return;
   if(!g_rangeValid) return;
   if(!VAFilterOK(atr)) return;
   if(g_lastEntryBarTime == g_rangeTime && CountPositions() > 0) return;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpSignalTF, 0, 3, r) < 3) return;
   double o = r[1].open, c = r[1].close, h = r[1].high, l = r[1].low;
   double buffer = InpRejectionBufferATR * atr;
   double rsi = GetRSI(1);

   // BUY at range low: touch + bullish rejection + inside range
   bool touchLow = (l <= g_rangeLow + buffer);
   bool insideLow = (c > g_rangeLow && c < g_rangeHigh);
   bool bullRej = (c > o);
   bool rsiBuyOK = (!InpUseRSIFilter) || (rsi < 65.0);
   if(touchLow && insideLow && bullRej && rsiBuyOK)
     {
      double entryRef = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
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

   // SELL at range high
   bool touchHigh = (h >= g_rangeHigh - buffer);
   bool insideHigh = (c < g_rangeHigh && c > g_rangeLow);
   bool bearRej = (c < o);
   bool rsiSellOK = (!InpUseRSIFilter) || (rsi > 35.0);
   if(touchHigh && insideHigh && bearRej && rsiSellOK)
     {
      double entryRef = SymbolInfoDouble(_Symbol, SYMBOL_BID);
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
//| Breakout detection + pullback entry                              |
//+------------------------------------------------------------------+
void TryBreakoutEntry(double atr)
  {
   if(!InpUseBreakout) return;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpSignalTF, 0, 4, r) < 4) return;
   double o = r[1].open, c = r[1].close, h = r[1].high, l = r[1].low;
   double confirm = InpBreakoutConfirmATR * atr;
   double buffer = InpRejectionBufferATR * atr;

   // Stage 1: detect fresh breakout from current valid range
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
         Print("Bull breakout detected at ", DoubleToString(g_breakoutLevel, _Digits));
         return; // wait for pullback next bars
        }
      if(bearBreak)
        {
         g_breakoutDir = -1; g_breakoutLevel = g_rangeLow;
         g_breakoutBarsLeft = InpPullbackBars;
         Print("Bear breakout detected at ", DoubleToString(g_breakoutLevel, _Digits));
         return;
        }
     }

   // Stage 2: pullback retest entry
   if(g_breakoutDir != 0 && g_breakoutBarsLeft > 0 && VAFilterOK(atr))
     {
      double rsi = GetRSI(1);
      if(g_breakoutDir > 0)
        {
         // retest: low touches level zone, close back above, bullish
         bool retest = (l <= g_breakoutLevel + buffer && l >= g_breakoutLevel - InpStopBufferATR * atr - confirm);
         bool holdAbove = (c > g_breakoutLevel);
         bool bull = (c > o);
         bool rsiOK = (!InpUseRSIFilter) || (rsi > 45.0);
         if(retest && holdAbove && bull && rsiOK)
           {
            double entryRef = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl = g_breakoutLevel - InpStopBufferATR * atr;
            double tp;
            if(InpTPMode == TP_ATR) tp = entryRef + InpTP_ATRmult * atr;
            else tp = entryRef + InpRR * (entryRef - sl); // RR for breakouts
            if(sl < entryRef)
              {
               if(OpenBuyPos(sl, tp))
                 {
                  g_breakoutDir = 0; g_breakoutBarsLeft = 0;
                  g_lastEntryBarTime = iTime(_Symbol, InpSignalTF, 1);
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
            double entryRef = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double sl = g_breakoutLevel + InpStopBufferATR * atr;
            double tp;
            if(InpTPMode == TP_ATR) tp = entryRef - InpTP_ATRmult * atr;
            else tp = entryRef - InpRR * (sl - entryRef);
            if(sl > entryRef)
              {
               if(OpenSellPos(sl, tp))
                 {
                  g_breakoutDir = 0; g_breakoutBarsLeft = 0;
                  g_lastEntryBarTime = iTime(_Symbol, InpSignalTF, 1);
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Opposite signal close (optional)                                 |
//+------------------------------------------------------------------+
void CheckOppositeClose()
  {
   if(!InpCloseOnOpposite) return;
   if(!g_rangeValid) return;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpSignalTF, 0, 3, r) < 3) return;
   double o = r[1].open, c = r[1].close, h = r[1].high, l = r[1].low;
   double buffer = InpRejectionBufferATR * GetATR(1);
   bool buySig = (l <= g_rangeLow + buffer && c > g_rangeLow && c > o);
   bool sellSig = (h >= g_rangeHigh - buffer && c < g_rangeHigh && c < o);
   if(!buySig && !sellSig) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      long pt = PositionGetInteger(POSITION_TYPE);
      if(pt == POSITION_TYPE_BUY && sellSig) g_trade.PositionClose(ticket);
      if(pt == POSITION_TYPE_SELL && buySig) g_trade.PositionClose(ticket);
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
   if(!newBar) return; // entries on new bar only (closed-candle logic)

   double atr = GetATR(1);
   if(atr <= 0) return;

   // Priority: pullback entry if breakout armed, else ping-pong + breakout detect
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
