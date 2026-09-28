//+------------------------------------------------------------------+
//|                                     AlgoX_SuperTrend_Pro_EA.mq4  |
//|  Automatic trading Expert Advisor for MetaTrader 4.              |
//|                                                                  |
//|  Algorithmic conversion of the TradingView indicator:            |
//|  "XAU AlgoX SuperTrend Pro v2 [1min Scalper] + TSI Filters       |
//|   (Fixed) - OPTIMIZED" (Pine Script v6).                         |
//|                                                                  |
//|  All indicator maths is re-implemented natively (no iCustom),    |
//|  so the EA is self-contained and works in the strategy tester.   |
//|                                                                  |
//|  Every piece of logic of the original script - including the     |
//|  blocks that are calculated but never used for trading - is      |
//|  exposed as an input parameter.                                  |
//|    [PINE DEFAULT] = default reproduces the original behaviour.   |
//|    [EXTRA]        = not present in the original, disabled by     |
//|                     default (never changes Pine behaviour).      |
//|                                                                  |
//|  Positions: exactly one at a time, sized from account risk.      |
//+------------------------------------------------------------------+
#property copyright "EA31337 conversion"
#property link      "https://ea31337.github.io/"
#property version   "1.00"
#property strict
#property description "Auto-trading EA converted from 'XAU AlgoX SuperTrend Pro v2 + TSI Filters' (Pine Script v6)."
#property description "Fib(233) + RSI + EMA + structure-break score engine, ADX dynamic SL/TP, risk based lot sizing."

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
//--- Generic switch used by the optional indicator blocks of the original
enum ENUM_AX_MODE
{
   AX_MODE_OFF     = 0,  // Off - value is calculated but not used for trading (Pine behaviour)
   AX_MODE_SCORE   = 1,  // Add / remove score points
   AX_MODE_REQUIRE = 2,  // Hard filter - the signal must agree with this indicator
   AX_MODE_BONUS   = 3   // Bonus score only (used by the higher timeframe trend filter)
};

enum ENUM_AX_ENTRY_MODE
{
   AX_ENTRY_MARKET = 0,  // Market at the open of the next candle (Pine behaviour)
   AX_ENTRY_LIMIT  = 1,  // BuyLimit / SellLimit at the computed level (pullback entry)
   AX_ENTRY_STOP   = 2   // BuyStop / SellStop at the computed level (breakout entry)
};

enum ENUM_AX_ANCHOR
{
   AX_ANCHOR_RECENTER  = 0,  // Re-centre SL/TP around the real fill (keeps the planned risk exactly)
   AX_ANCHOR_REFERENCE = 1   // Keep the signal-candle reference levels (exactly like the indicator)
};

enum ENUM_AX_EXIT
{
   AX_EXIT_SPLIT_BE        = 0,  // Part at TP1, stop to break-even, rest at TP2
   AX_EXIT_TP1_ONLY        = 1,  // Whole position at TP1 (Pine behaviour)
   AX_EXIT_TP2_ONLY        = 2,  // Whole position at TP2
   AX_EXIT_TRAIL_AFTER_TP1 = 3,  // Part at TP1, stop to break-even, then trailing stop
   AX_EXIT_TP2_BE          = 4   // Whole position at TP2, stop to break-even at the TP1 distance (research default)
};

enum ENUM_AX_REGIME
{
   AX_REGIME_ANY    = 0,  // Any regime (weak included)
   AX_REGIME_MEDIUM = 1,  // Medium and strong only (ADX >= weak threshold)
   AX_REGIME_STRONG = 2   // Strong only (ADX >= strong threshold) - recommended for M1
};

enum ENUM_AX_SENS
{
   AX_SENS_CONSERVATIVE = 0,  // Thresholds 90 / 70
   AX_SENS_BALANCED     = 1,  // Thresholds 85 / 55   (Pine default)
   AX_SENS_AGGRESSIVE   = 2,  // Thresholds 80 / 50
   AX_SENS_CUSTOM       = 3   // Use the two manual thresholds below
};

enum ENUM_AX_STRONG
{
   AX_STRONG_OFF        = 0,  // Off - only logged (Pine default)
   AX_STRONG_ONLY       = 1,  // Trade only signals whose score >= strong threshold
   AX_STRONG_BOOST_RISK = 2   // Multiply the risk percent on strong signals
};

enum ENUM_AX_RSI
{
   AX_RSI_SCORE_50       = 0,  // Score: RSI > 50 / < 50 (Pine default)
   AX_RSI_SCORE_LEVELS   = 1,  // Score: RSI > buy level / < sell level
   AX_RSI_REQUIRE_LEVELS = 2   // Require RSI > buy level (buy) / < sell level (sell)
};

enum ENUM_AX_REENTRY
{
   AX_REENTRY_ALLOWED        = 0,  // Allowed - Pine allowReEntry stays true (Pine default)
   AX_REENTRY_BLOCK_SAME_DIR = 1,  // Block further entries in the direction that just traded
   AX_REENTRY_BLOCK_SAME_DAY = 2   // Block further entries for the rest of the day after a trade
};

enum ENUM_AX_STRUCT
{
   AX_STRUCT_OFF           = 0,  // Off (Pine default)
   AX_STRUCT_COMPUTE       = 1,  // Calculate BOS/CHoCH only (like the indicator labels)
   AX_STRUCT_FILTER        = 2,  // Block signals against the current structure bias
   AX_STRUCT_REQUIRE_FRESH = 3   // Require a fresh aligned structure (last break <= freshness bars)
};

enum ENUM_AX_FIBEXTRA
{
   AX_FIBEXTRA_OFF  = 0,  // Off (Pine default - 50% / 78.6% levels are unused in the original)
   AX_FIBEXTRA_50   = 1,  // Require close beyond the 50% level
   AX_FIBEXTRA_786  = 2,  // Require close beyond the 78.6% level
   AX_FIBEXTRA_BOTH = 3   // Require both
};

enum ENUM_AX_SESSION
{
   AX_SESSION_ALL     = 0,  // All (Pine default)
   AX_SESSION_ASIA    = 1,  // Asia      UTC 00:00-09:00 and 22:00-24:00
   AX_SESSION_LONDON  = 2,  // London    UTC 09:01-16:00
   AX_SESSION_NEWYORK = 3   // New York  UTC 16:01-21:59
};

enum ENUM_AX_SIZING
{
   AX_SIZING_BROKER       = 0,  // Live balance + broker tick value (recommended)
   AX_SIZING_MANUAL_VALUE = 1,  // Live balance + manual value per 1$ move per lot
   AX_SIZING_PINE_FIXED   = 2,  // Fixed balance + manual value (exactly the indicator formula)
   AX_SIZING_FIXED_LOT    = 3   // Fixed lot below
};

enum ENUM_AX_TRAIL
{
   AX_TRAIL_BY_R   = 0,  // Trail distance = R multiple of the initial risk
   AX_TRAIL_BY_ATR = 1   // Trail distance = ATR multiple
};

enum ENUM_AX_TFTF
{
   AX_TF_5   = 5,    // M5
   AX_TF_15  = 15,   // M15
   AX_TF_30  = 30,   // M30
   AX_TF_60  = 60,   // H1  (Pine default)
   AX_TF_120 = 120,  // H2
   AX_TF_240 = 240   // H4
};

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
//--- General ---------------------------------------------------------
input int                InpMagicNumber         = 20260928;  // Magic number
input int                InpSlippage            = 30;        // Max slippage (points)
input double             InpMaxSpreadPoints     = 0;         // [EXTRA] Max spread in points (0 = off)
input bool               InpVerboseLog          = true;      // Verbose log in the Experts tab
input bool               InpAlertOnSignal       = false;     // Popup alert on every new signal
input bool               InpDeletePendingsOnExit= true;      // Delete own pending orders on deinit

//--- SuperTrend core (only used by the optional filter / alert) ------
input int                InpSTPeriods           = 5;         // SuperTrend ATR period          [PINE DEFAULT]
input double             InpSTMultiplier        = 3.0;       // SuperTrend multiplier          [PINE DEFAULT]
input ENUM_AX_MODE       InpSTUse               = AX_MODE_OFF;// SuperTrend usage - unused by the original
input bool               InpSTUseRMA            = true;      // Use RMA-based ATR (else SMA of TR)
input double             InpSTWeight            = 10;        // Score weight in SCORE mode
input bool               InpSTAlertOnFlip       = false;     // Alert when the SuperTrend flips
input int                InpSTWarmupBars        = 500;       // Bars used to warm up the recursive SuperTrend

//--- ADX based dynamic SL/TP -----------------------------------------
input bool               InpUseDynamicSLTP      = true;      // Dynamic SL/TP based on ADX     [PINE DEFAULT]
input int                InpADXLen              = 14;        // ADX length                     [PINE DEFAULT]
input int                InpADXWeakThresh       = 20;        // ADX weak threshold (<)         [PINE DEFAULT]
input int                InpADXStrongThresh     = 40;        // ADX strong threshold (>=)      [PINE DEFAULT]
input double             InpBaseSLMult          = 2.0;       // Base SL multiplier (ATR)       [PINE DEFAULT]
input double             InpBaseTPRR            = 1.0;       // Base TP risk:reward            [PINE DEFAULT]
input double             InpSLFactorWeak        = 0.8;       // SL factor (weak)               [PINE DEFAULT]
input double             InpSLFactorMed         = 0.5;       // SL factor (medium)             [PINE DEFAULT]
input double             InpSLFactorStrong      = 0.8;       // SL factor (strong)             [PINE DEFAULT]
input double             InpTPFactorWeak        = 0.65;      // TP factor (weak)               [PINE DEFAULT]
input double             InpTPFactorMed         = 0.75;      // TP factor (medium)             [PINE DEFAULT]
input double             InpTPFactorStrong      = 1.5;       // TP factor (strong)             [PINE DEFAULT]
input double             InpTP2Multiplier       = 1.5;       // TP2 = TP1 distance * this      [PINE DEFAULT]

//--- Entry and trade levels ------------------------------------------
input int                InpEntryPercent        = 30;        // Entry candle percentage (5-95)     [PINE DEFAULT]
input ENUM_AX_ENTRY_MODE InpEntryMode           = AX_ENTRY_MARKET; // Entry method                 [PINE DEFAULT]
input int                InpPendingExpiryBars   = 1;         // Pending order life in bars (1 = next candle)
input bool               InpPendingFallbackMkt  = true;      // [EXTRA] Use market when a pending cannot be used
input ENUM_AX_ANCHOR     InpSLAnchor            = AX_ANCHOR_RECENTER; // SL/TP anchor            [PINE DEFAULT]
input bool               InpUsePineCancelRule   = false;     // [EXTRA] Apply the odd 0.50 activation window
input double             InpPineCancelWindow    = 0.50;      // Width of that window (price units, gold specific)

//--- Cost gates (research based, built for XAUUSD M1 with a 0.47 USD spread)
input bool               InpUseCostFilters      = true;      // [RESEARCH] Enable the cost / regime gates
input int                InpFixedSpreadPoints   = 47;        // [RESEARCH] Assumed spread in points (47 pts = 0.47 USD on 2-digit gold)
input double             InpMinATR              = 1.0;       // [RESEARCH] Minimum ATR(5) in price units (0 = off)
input ENUM_AX_REGIME     InpMinADXRegime        = AX_REGIME_STRONG; // [RESEARCH] Minimum ADX regime
input double             InpMinSLSpreadMult     = 2.0;       // [RESEARCH] Require SL >= this x spread (0 = off)
input double             InpMinTargetSpreadMult = 3.0;       // [RESEARCH] Require TP >= this x spread (0 = off)
input bool               InpSkipTP1IfUneconomic = true;      // [RESEARCH] Skip the TP1 exit when it is smaller than the TP requirement

//--- Account safety limits (hard guards, they sit above every filter)
input bool               InpUseSafetyLimits      = true;  // [SAFETY] Enable the account level guards
input double             InpRiskPercentCap       = 2.0;   // [SAFETY] Hard cap on the risk % per trade (0 = off)
input double             InpMaxMarginPercent     = 10.0;  // [SAFETY] Max % of equity used as margin per trade (0 = off)
input int                InpMaxTradesPerDay      = 0;     // [SAFETY] Max entries per day (0 = off)
input double             InpMaxDailyLossPercent  = 0.0;   // [SAFETY] Stop for the day after this loss % of the day start equity (0 = off)
input int                InpMaxConsecutiveLosses = 0;     // [SAFETY] Stop for the day after N losing trades in a row (0 = off)
input double             InpEquityStopPercent    = 0.0;   // [SAFETY] Close and halt trading after this equity drop % (needs a reload to reset, 0 = off)
input bool               InpCloseOnEquityStop    = true;  // [SAFETY] Close the open position when the equity stop fires

//--- Score engine -----------------------------------------------------
input double             InpWeightFib           = 10;        // [RESEARCH] Score weight: Fibonacci (Pine used 25)
input double             InpWeightRSI           = 20;        // Score weight: RSI (Pine 20)
input double             InpWeightEMA           = 20;        // Score weight: EMA (Pine 25)
input double             InpWeightStruct        = 10;        // [RESEARCH] Score weight: structure break (Pine 30)
input double             InpWeightMACD          = 20;        // [RESEARCH] Score weight: MACD histogram (Pine 0)
input double             InpWeightVolume        = 20;        // [RESEARCH] Score weight: relative volume (Pine 0)
input double             InpWeightHTF           = 0;         // [RESEARCH] HTF trend bonus weight (0 = use InpTrendBonus)
input ENUM_AX_SENS       InpSensitivity         = AX_SENS_BALANCED; // Signal sensitivity       [PINE DEFAULT]
input double             InpMinThreshold        = 55;        // Min score to enter (CUSTOM sensitivity)
input double             InpStrongThreshold     = 85;        // Strong score threshold (CUSTOM sensitivity)
input ENUM_AX_STRONG     InpStrongMode          = AX_STRONG_OFF; // Strong threshold usage  [PINE DEFAULT]
input double             InpStrongRiskMult      = 1.5;       // Risk multiplier in BOOST_RISK mode

//--- Higher timeframe trend filter ------------------------------------
input ENUM_AX_MODE       InpTrendFilterMode     = AX_MODE_OFF;// Higher TF trend filter         [PINE DEFAULT]
input ENUM_AX_TFTF       InpTrendTF             = AX_TF_60;  // Trend filter timeframe            [PINE DEFAULT]
input int                InpTrendEMA            = 50;        // Trend filter EMA period           [PINE DEFAULT]
input double             InpTrendBonus          = 5;         // Bonus score if aligned            [PINE DEFAULT]

//--- Confirmation indicators (calculated by the original, unused) -----
input ENUM_AX_RSI        InpRSIMode             = AX_RSI_SCORE_50; // RSI usage                 [PINE DEFAULT]
input int                InpRSILen              = 5;         // RSI length                        [PINE DEFAULT]
input double             InpRSIBuy              = 55;        // RSI buy level                     [PINE DEFAULT]
input double             InpRSISell             = 45;        // RSI sell level                    [PINE DEFAULT]
input ENUM_AX_MODE       InpMACDMode            = AX_MODE_OFF;// MACD usage (unused by original)
input int                InpMACDFast            = 5;         // MACD fast                         [PINE DEFAULT]
input int                InpMACDSlow            = 13;        // MACD slow                         [PINE DEFAULT]
input int                InpMACDSignal          = 5;         // MACD signal                       [PINE DEFAULT]
input ENUM_AX_MODE       InpVWAPMode            = AX_MODE_OFF;// VWAP usage (unused by original)
input ENUM_AX_MODE       InpVolAvgMode          = AX_MODE_OFF;// Volume > SMA(volume) (unused by original)
input int                InpVolAvgLen           = 20;        // Volume average length             [PINE DEFAULT]
input ENUM_AX_FIBEXTRA   InpExtraFibMode        = AX_FIBEXTRA_OFF; // 50% / 78.6% fib levels       [PINE DEFAULT]
input ENUM_AX_MODE       InpRange200Mode        = AX_MODE_OFF;// 200-bar close extremes (unused by original)
input ENUM_AX_MODE       InpRegimeMode          = AX_MODE_OFF;// Market regime / counter-trend risk (unused)
input double             InpExtraWeight         = 10;        // Score weight for the extra filters (SCORE mode)

//--- TSI style filters ------------------------------------------------
input ENUM_AX_MODE       InpVolFilterMode       = AX_MODE_OFF;// Relative volume filter           [PINE DEFAULT]
input int                InpVolRelPeriod        = 20;        // Volume SMA period                 [PINE DEFAULT]
input double             InpVolRelBullish       = 1.2;       // Strong volume threshold (x SMA)   [PINE DEFAULT]
input double             InpVolRelWeak          = 0.5;       // Weak volume threshold (x SMA)     [PINE DEFAULT]
input double             InpVolBonusMax         = 0.5;       // Max strong volume bonus           [PINE DEFAULT]
input double             InpVolMalusMax         = 0.5;       // Max weak volume penalty           [PINE DEFAULT]
input bool               InpUseAntiWhipsaw      = false;     // Anti-whipsaw (Bollinger consolidation) [PINE DEFAULT]
input int                InpBBPeriod            = 20;        // Bollinger period                  [PINE DEFAULT]
input double             InpBBStdDev            = 2.0;       // Bollinger std dev                 [PINE DEFAULT]
input double             InpConsolThreshold     = 0.0;       // Consolidation threshold % (0 = auto 25th pct)
input double             InpConsolMultiplier    = 0.9;       // Score multiplier in consolidation [PINE DEFAULT]
input double             InpConsolCDMultiplier  = 1.1;       // Cooldown multiplier in consolidation [PINE DEFAULT]
input bool               InpUseSlopeFilter      = false;     // Filter weak SuperTrend flips (slope) [PINE DEFAULT]
input double             InpSlopeMin            = 0.1;       // Minimum absolute price slope (%)  [PINE DEFAULT]
input ENUM_AX_STRUCT     InpStructMode          = AX_STRUCT_OFF; // Advanced structure BOS/CHoCH  [PINE DEFAULT]
input int                InpSwingLookback       = 5;         // Swing high/low lookback           [PINE DEFAULT]
input int                InpStructFreshBars     = 10;        // Structure freshness (bars)        [PINE DEFAULT]

//--- Cooldown and re-entry --------------------------------------------
input bool               InpEnableCooldown      = true;      // Enable signal cooldown            [PINE DEFAULT]
input int                InpCooldownBars        = 10;        // Cooldown bars                     [PINE DEFAULT]
input bool               InpOneSignalPerMove    = false;     // One signal per move               [PINE DEFAULT]
input ENUM_AX_REENTRY    InpReEntryMode         = AX_REENTRY_ALLOWED; // Re-entry handling       [PINE DEFAULT]

//--- Session filter ---------------------------------------------------
input bool               InpUseSessionFilter    = false;     // Filter by session                 [PINE DEFAULT]
input ENUM_AX_SESSION    InpTradingSession      = AX_SESSION_ALL; // Session                     [PINE DEFAULT]
input bool               InpUseManualGMTOffset  = false;     // [EXTRA] Use the manual GMT offset below
input int                InpBrokerGMTOffsetHrs  = 0;         // [EXTRA] Broker server offset from GMT (hours)

//--- Position sizing ---------------------------------------------------
input ENUM_AX_SIZING     InpSizingMode          = AX_SIZING_BROKER; // Position sizing mode
input double             InpRiskPercent         = 1.5;       // Risk % per trade                  [PINE DEFAULT]
input double             InpPineBalance         = 100;       // Fixed balance ($) for PINE_FIXED  [PINE DEFAULT]
input double             InpPineLotValue        = 10;        // $ per 1$ move per lot (manual modes) [PINE DEFAULT]
input double             InpFixedLot            = 0.01;      // Fixed lot (FIXED_LOT mode only)

//--- Exit management ---------------------------------------------------
input ENUM_AX_EXIT       InpExitMode            = AX_EXIT_SPLIT_BE; // Exit management
input double             InpTP1Portion          = 0.5;       // Portion closed at TP1 (0.05 - 1.0)
input bool               InpMoveToBEAtTP1       = true;      // Move the stop to break-even after TP1
input double             InpBEPlusPoints        = 0;         // Break-even offset (points)
input bool               InpKeepTP2OnOrder      = true;      // Keep TP2 attached to the order as a server target
input ENUM_AX_TRAIL      InpTrailMode           = AX_TRAIL_BY_R; // Trailing mode
input double             InpTrailDistR          = 0.5;       // Trail distance (R multiple)
input double             InpTrailATRMult        = 1.5;       // Trail distance (ATR multiple)
input int                InpMaxBarsInTrade      = 0;         // [EXTRA] Close after N bars (0 = off)

//+------------------------------------------------------------------+
//| Indicator snapshot structure                                     |
//+------------------------------------------------------------------+
struct AlgoXInd
{
   double  atr;              // ATR(stPeriods) on the signal bar
   double  adx;              // ADX(adxLen)
   int     adxLevel;         // 0 = weak, 1 = medium, 2 = strong
   double  rsi;              // RSI(rsiLen)
   double  ema5;
   double  ema10;
   double  ema20;
   double  macdHist;         // MACD main - signal
   double  fib618;
   double  fib382;
   double  fib50;
   double  fib786;
   double  bbWidth;
   double  bbP25;
   double  volRelative;
   double  vwap;
   double  volAvg;
   bool    volAboveAvg;
   bool    bullBreak;
   bool    bearBreak;
   double  lastPivotHigh;
   double  lastPivotLow;
   double  priceSlope;
   bool    slopeOK;
   bool    consol;
   int     structBias;       // -1 / 0 / +1
   int     structEvent;      // 1 BOS up, 2 BOS down, 3 CHoCH up, 4 CHoCH down
   bool    structFresh;
   bool    structBull;
   bool    structBear;
   bool    stUp;             // SuperTrend direction (true = up)
   bool    higherTFUp;
   bool    higherTFDown;
   bool    trendUp;
   bool    trendDown;
   bool    rangeMarket;
   double  buyScore;
   double  sellScore;
   double  minThresh;
   double  strongThresh;
   bool    rawBuy;
   bool    rawSell;
   string  adxLevelName;
};

//+------------------------------------------------------------------+
//| Global state                                                     |
//+------------------------------------------------------------------+
AlgoXInd g_ind;

datetime g_lastBarTime       = 0;
datetime g_lastSignalBarTime = 0;   // Pine: lastSignalBar
int      g_lastDir           = 0;   // Pine: lastDir (1 = BUY, -1 = SELL)
int      g_blockedDir        = 0;   // re-entry blocking direction
int      g_blockedDay        = 0;   // day_of_year when the re-entry block was set

int      g_ticket            = 0;   // our open position ticket
int      g_tradeDir          = 0;
double   g_entryPrice        = 0.0;
double   g_riskDist          = 0.0;
double   g_rr                = 0.0;
double   g_tp1               = 0.0;
double   g_tp2               = 0.0;
bool     g_tp1Done           = false;

datetime g_pendingBarTime    = 0;
ENUM_AX_EXIT g_effExit       = AX_EXIT_SPLIT_BE;  // exit mode actually used for this trade
double   g_beTrigger         = 0.0;               // price that moves the stop to break-even (0 = off)

//--- account safety state -------------------------------------------------
int      g_safetyDay        = -1;    // day of year of the counters below
int      g_tradesToday      = 0;     // entries taken today
int      g_lossStreak       = 0;     // consecutive losing trades today
double   g_dayStartEquity   = 0.0;   // equity at the start of the day
bool     g_dayHalted        = false; // no more trades today
bool     g_haltLogged       = false;
bool     g_hardHalted       = false; // equity stop: needs an EA reload

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
int IMin(const int a, const int b) { return((a < b) ? a : b); }
int IMax(const int a, const int b) { return((a > b) ? a : b); }

void LogMsg(string msg)
{
   if(InpVerboseLog) Print("[AlgoX] ", msg);
}

//--- Number of decimals used to normalize a lot size -------------------
int LotDigits()
{
   double step = MarketInfo(_Symbol, MODE_LOTSTEP);
   if(step <= 0.0) step = 0.01;
   if(step >= 1.0)  return(0);
   if(step >= 0.1)  return(1);
   if(step >= 0.01) return(2);
   return(3);
}

//--- Normalize a lot size to the broker constraints --------------------
double NormalizeLot(double lots)
{
   double minLot = MarketInfo(_Symbol, MODE_MINLOT);
   double maxLot = MarketInfo(_Symbol, MODE_MAXLOT);
   double step   = MarketInfo(_Symbol, MODE_LOTSTEP);
   if(step <= 0.0)   step = 0.01;
   if(minLot <= 0.0) minLot = step;
   if(maxLot <= 0.0) maxLot = 100.0;

   lots = MathFloor(lots / step + 0.0000001) * step;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   return(NormalizeDouble(lots, LotDigits()));
}

//+------------------------------------------------------------------+
//| Math helpers (replicas of the Pine built-ins used by the script)  |
//+------------------------------------------------------------------+
double SmaClose(const int period, const int shift)
{
   double sum = 0.0;
   for(int i = 0; i < period; i++) sum += iClose(_Symbol, _Period, shift + i);
   return(sum / (double)period);
}

double SmaVolume(const int period, const int shift)
{
   double sum = 0.0;
   for(int i = 0; i < period; i++) sum += iVolume(_Symbol, _Period, shift + i);
   return(sum / (double)period);
}

//--- Population standard deviation (Pine ta.stdev, biased = true) -------
double StdDevClose(const int period, const int shift)
{
   double mean = SmaClose(period, shift);
   double sum  = 0.0;
   for(int i = 0; i < period; i++)
   {
      double d = iClose(_Symbol, _Period, shift + i) - mean;
      sum += d * d;
   }
   return(MathSqrt(sum / (double)period));
}

//--- True range of a single bar ----------------------------------------
double TrueRange(const int shift)
{
   double h  = iHigh(_Symbol, _Period, shift);
   double l  = iLow(_Symbol, _Period, shift);
   double pc = iClose(_Symbol, _Period, shift + 1);
   double v1 = h - l;
   double v2 = MathAbs(h - pc);
   double v3 = MathAbs(l - pc);
   double r  = v1;
   if(v2 > r) r = v2;
   if(v3 > r) r = v3;
   return(r);
}

//--- SMA of true range (when the SuperTrend ATR source is SMA) ----------
double AtrSma(const int period, const int shift)
{
   double sum = 0.0;
   for(int i = 0; i < period; i++) sum += TrueRange(shift + i);
   return(sum / (double)period);
}

//--- Pine ta.percentile_linear_interpolation ---------------------------
double PercentileLinear(double &src[], const int n, const double pct)
{
   if(n <= 0) return(0.0);
   double tmp[];
   ArrayResize(tmp, n);
   for(int i = 0; i < n; i++) tmp[i] = src[i];
   ArraySort(tmp);
   if(n == 1) return(tmp[0]);
   double idx = ((double)n - 1.0) * pct / 100.0;
   int lo = (int)MathFloor(idx);
   int hi = (int)MathCeil(idx);
   if(lo < 0)      lo = 0;
   if(hi > n - 1)  hi = n - 1;
   double frac = idx - (double)lo;
   return(tmp[lo] + (tmp[hi] - tmp[lo]) * frac);
}

//--- Pivot detection (Pine ta.pivothigh / ta.pivotlow - strict) ---------
bool IsPivotHigh(const int pivotShift, const int lb, double &value)
{
   if(pivotShift - lb < 1)          return(false);
   if(pivotShift + lb > Bars - 1)   return(false);
   double p = iHigh(_Symbol, _Period, pivotShift);
   for(int i = 1; i <= lb; i++)
   {
      if(iHigh(_Symbol, _Period, pivotShift + i) >= p) return(false);
      if(iHigh(_Symbol, _Period, pivotShift - i) >= p) return(false);
   }
   value = p;
   return(true);
}

bool IsPivotLow(const int pivotShift, const int lb, double &value)
{
   if(pivotShift - lb < 1)          return(false);
   if(pivotShift + lb > Bars - 1)   return(false);
   double p = iLow(_Symbol, _Period, pivotShift);
   for(int i = 1; i <= lb; i++)
   {
      if(iLow(_Symbol, _Period, pivotShift + i) <= p) return(false);
      if(iLow(_Symbol, _Period, pivotShift - i) <= p) return(false);
   }
   value = p;
   return(true);
}

//--- Most recent confirmed pivot (Pine lastPivotHigh / lastPivotLow) ----
double FindLastPivotHigh(const int lb, const int maxScan)
{
   double v = 0.0;
   for(int s = lb + 1; s <= maxScan; s++)
      if(IsPivotHigh(s, lb, v)) return(v);
   return(0.0);
}

double FindLastPivotLow(const int lb, const int maxScan)
{
   double v = 0.0;
   for(int s = lb + 1; s <= maxScan; s++)
      if(IsPivotLow(s, lb, v)) return(v);
   return(0.0);
}

//+------------------------------------------------------------------+
//| SuperTrend - recursive replica of the Pine implementation        |
//|  up = src - mult*atr ; up := close[1] > up1 ? max(up, up1) : up  |
//|  dn = src + mult*atr ; dn := close[1] < dn1 ? min(dn, dn1) : dn  |
//|  trend flips when the close breaks the opposite band             |
//+------------------------------------------------------------------+
bool ComputeSuperTrend(const int shift, bool &isUp)
{
   int start = IMin(Bars - 2, IMax(InpSTWarmupBars, 60));
   if(start < shift + 2) return(false);

   double prevUp = 0.0, prevDn = 0.0;
   int    prevTrend = 1;
   bool   havePrev  = false;

   for(int s = start; s >= shift; s--)
   {
      double atrVal = InpSTUseRMA ? iATR(_Symbol, _Period, InpSTPeriods, s)
                                  : AtrSma(InpSTPeriods, s);
      double src   = (iHigh(_Symbol, _Period, s) + iLow(_Symbol, _Period, s)) / 2.0;
      double rawUp = src - InpSTMultiplier * atrVal;
      double rawDn = src + InpSTMultiplier * atrVal;
      double c     = iClose(_Symbol, _Period, s);
      double cP    = iClose(_Symbol, _Period, s + 1);

      double upFinal = rawUp;
      double dnFinal = rawDn;
      int    trend   = 1;

      if(havePrev)
      {
         upFinal = (cP > prevUp) ? MathMax(rawUp, prevUp) : rawUp;
         dnFinal = (cP < prevDn) ? MathMin(rawDn, prevDn) : rawDn;

         if(prevTrend == -1 && c > prevDn)     trend = 1;
         else if(prevTrend == 1 && c < prevUp) trend = -1;
         else                                  trend = prevTrend;
      }

      if(s == shift)
      {
         isUp = (trend == 1);
         return(true);
      }

      prevUp    = upFinal;
      prevDn    = dnFinal;
      prevTrend = trend;
      havePrev  = true;
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Advanced structure (BOS / CHoCH) - sequential walk over history   |
//+------------------------------------------------------------------+
void ComputeAdvancedStructure(AlgoXInd &ind)
{
   ind.structBias  = 0;
   ind.structEvent = 0;
   ind.structFresh = false;
   ind.structBull  = false;
   ind.structBear  = false;

   if(InpStructMode == AX_STRUCT_OFF) return;

   int lb      = InpSwingLookback;
   int maxScan = IMin(Bars - lb - 5, 2000);
   if(maxScan < lb + 5) return;

   double lastSH = 0.0, lastSL = 0.0;
   int    bias           = 0;
   int    lastBreakShift = -1;
   int    lastEvent      = 0;

   for(int s = maxScan; s >= 1; s--)
   {
      double pv = 0.0;
      if(IsPivotHigh(s + lb, lb, pv)) lastSH = pv;
      if(IsPivotLow(s + lb, lb, pv))  lastSL = pv;

      double c  = iClose(_Symbol, _Period, s);
      double cP = iClose(_Symbol, _Period, s + 1);

      bool breakAbove = (lastSH > 0.0) && (c > lastSH) && (cP <= lastSH);
      bool breakBelow = (lastSL > 0.0) && (c < lastSL) && (cP >= lastSL);

      if(breakAbove)
      {
         lastEvent      = (bias >= 0) ? 1 : 3;
         bias           = 1;
         lastBreakShift = s;
      }
      if(breakBelow)
      {
         lastEvent      = (bias <= 0) ? 2 : 4;
         bias           = -1;
         lastBreakShift = s;
      }
   }

   ind.structBias  = bias;
   ind.structEvent = lastEvent;
   ind.structBull  = (bias > 0);
   ind.structBear  = (bias < 0);
   ind.structFresh = (lastBreakShift > 0) && ((lastBreakShift - 1) <= InpStructFreshBars);
}

//+------------------------------------------------------------------+
//| Session helpers (UTC windows identical to the original script)    |
//+------------------------------------------------------------------+
datetime CurrentUTC()
{
   if(InpUseManualGMTOffset)
      return(TimeCurrent() - InpBrokerGMTOffsetHrs * 3600);
   return(TimeGMT());
}

bool InTradingSession()
{
   if(!InpUseSessionFilter) return(true);

   int secsOfDay   = ((int)CurrentUTC()) % 86400;
   int minutesUTC  = secsOfDay / 60;

   switch(InpTradingSession)
   {
      case AX_SESSION_ASIA:
         return((minutesUTC >= 0 && minutesUTC <= 540) || (minutesUTC >= 1320));
      case AX_SESSION_LONDON:
         return(minutesUTC >= 541 && minutesUTC <= 960);
      case AX_SESSION_NEWYORK:
         return(minutesUTC >= 961 && minutesUTC <= 1319);
   }
   return(true);
}

//+------------------------------------------------------------------+
//| VWAP anchored to the current broker day (ta.vwap approximation)   |
//+------------------------------------------------------------------+
double SessionVWAP(const int lastShift)
{
   int    limit = IMin(Bars - 2, 5000);
   datetime t1  = iTime(_Symbol, _Period, 1);
   MqlDateTime dt;
   TimeToStruct(t1, dt);
   int dayOfYear = dt.day_of_year;

   datetime dayStart = t1;
   for(int s = 1; s <= limit; s++)
   {
      datetime t = iTime(_Symbol, _Period, s);
      MqlDateTime d2;
      TimeToStruct(t, d2);
      if(d2.day_of_year != dayOfYear)
      {
         dayStart = iTime(_Symbol, _Period, s - 1);
         break;
      }
      dayStart = t;
   }

   double sumPV = 0.0, sumV = 0.0;
   for(int s = lastShift; s <= limit; s++)
   {
      if(iTime(_Symbol, _Period, s) < dayStart) break;
      double vol = iVolume(_Symbol, _Period, s);
      if(vol <= 0.0) vol = 1.0;
      sumPV += iClose(_Symbol, _Period, s) * vol;
      sumV  += vol;
   }
   if(sumV <= 0.0) return(0.0);
   return(sumPV / sumV);
}

//+------------------------------------------------------------------+
//| Compute every indicator value for the signal bar (shift = 1)      |
//+------------------------------------------------------------------+
bool ComputeIndicators(AlgoXInd &ind)
{
   if(Bars < 60) return(false);

   //--- ATR -----------------------------------------------------------
   ind.atr = InpSTUseRMA ? iATR(_Symbol, _Period, InpSTPeriods, 1)
                         : AtrSma(InpSTPeriods, 1);

   //--- ADX -----------------------------------------------------------
   ind.adx = iADX(_Symbol, _Period, InpADXLen, PRICE_CLOSE, MODE_MAIN, 1);
   if(ind.adx >= (double)InpADXStrongThresh)     ind.adxLevel = 2;
   else if(ind.adx >= (double)InpADXWeakThresh)  ind.adxLevel = 1;
   else                                          ind.adxLevel = 0;
   ind.adxLevelName = (ind.adxLevel == 2) ? "Strong" : ((ind.adxLevel == 1) ? "Medium" : "Weak");

   //--- EMAs ----------------------------------------------------------
   ind.ema5  = iMA(_Symbol, _Period, 5,  0, MODE_EMA, PRICE_CLOSE, 1);
   ind.ema10 = iMA(_Symbol, _Period, 10, 0, MODE_EMA, PRICE_CLOSE, 1);
   ind.ema20 = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE, 1);

   //--- RSI -----------------------------------------------------------
   ind.rsi = iRSI(_Symbol, _Period, InpRSILen, PRICE_CLOSE, 1);

   //--- MACD ----------------------------------------------------------
   double macdMain = iMACD(_Symbol, _Period, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN,   1);
   double macdSig  = iMACD(_Symbol, _Period, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, 1);
   ind.macdHist = macdMain - macdSig;

   //--- Volume average (calculated but unused by the original) --------
   ind.volAvg      = SmaVolume(InpVolAvgLen, 1);
   ind.volAboveAvg = (iVolume(_Symbol, _Period, 1) > ind.volAvg);

   //--- Fibonacci ladder over 233 bars --------------------------------
   int    fibLen = 233;
   if(Bars < fibLen + 5) fibLen = Bars - 5;
   double fibTop = -1e18, fibBot = 1e18;
   int    topOff = 0, botOff = 0;
   for(int j = 0; j < fibLen; j++)
   {
      double hh = iHigh(_Symbol, _Period, 1 + j);
      double ll = iLow(_Symbol, _Period, 1 + j);
      if(hh > fibTop) { fibTop = hh; topOff = j; }
      if(ll < fibBot) { fibBot = ll; botOff = j; }
   }
   double rng = fibTop - fibBot;
   bool   fromTop = (botOff > topOff);
   ind.fib618 = fromTop ? (fibTop - rng * 0.618) : (fibBot + rng * 0.618);
   ind.fib50  = fromTop ? (fibTop - rng * 0.500) : (fibBot + rng * 0.500);
   ind.fib382 = fromTop ? (fibTop - rng * 0.382) : (fibBot + rng * 0.382);
   ind.fib786 = fromTop ? (fibTop - rng * 0.786) : (fibBot + rng * 0.786);

   //--- Simple market structure (pivot 10/10) --------------------------
   ind.lastPivotHigh = FindLastPivotHigh(10, IMin(Bars - 15, 300));
   ind.lastPivotLow  = FindLastPivotLow(10,  IMin(Bars - 15, 300));

   double c1 = iClose(_Symbol, _Period, 1);
   double c2 = iClose(_Symbol, _Period, 2);

   ind.bullBreak = (ind.lastPivotHigh > 0.0) && (c1 > ind.lastPivotHigh) && (c2 <= ind.lastPivotHigh);
   ind.bearBreak = (ind.lastPivotLow  > 0.0) && (c1 < ind.lastPivotLow)  && (c2 >= ind.lastPivotLow);

   //--- TSI style: relative volume -------------------------------------
   double volSmaRel = SmaVolume(InpVolRelPeriod, 1);
   double volNow    = iVolume(_Symbol, _Period, 1);
   ind.volRelative  = (volSmaRel > 0.0) ? (volNow / volSmaRel) : 1.0;

   //--- TSI style: anti-whipsaw (Bollinger width percentile) -----------
   ind.bbWidth = 0.0;
   ind.bbP25   = 0.0;
   if(InpUseAntiWhipsaw)
   {
      double bbBasis = SmaClose(InpBBPeriod, 1);
      double bbStd   = StdDevClose(InpBBPeriod, 1);
      double bbUpper = bbBasis + InpBBStdDev * bbStd;
      double bbLower = bbBasis - InpBBStdDev * bbStd;
      ind.bbWidth    = (bbBasis != 0.0) ? ((bbUpper - bbLower) / bbBasis * 100.0) : 0.0;

      int pctLen = IMin(100, Bars - InpBBPeriod - 2);
      if(pctLen > 1)
      {
         double widths[];
         ArrayResize(widths, pctLen);
         for(int k = 0; k < pctLen; k++)
         {
            double b  = SmaClose(InpBBPeriod, 1 + k);
            double sd = StdDevClose(InpBBPeriod, 1 + k);
            double up = b + InpBBStdDev * sd;
            double lo = b - InpBBStdDev * sd;
            widths[k] = (b != 0.0) ? ((up - lo) / b * 100.0) : 0.0;
         }
         ind.bbP25 = PercentileLinear(widths, pctLen, 25.0);
      }
   }
   double consolThr = (InpConsolThreshold > 0.0) ? InpConsolThreshold : ind.bbP25;
   ind.consol = (InpUseAntiWhipsaw && ind.bbWidth < consolThr);

   //--- Slope filter ----------------------------------------------------
   double c6 = iClose(_Symbol, _Period, 6);
   ind.priceSlope = (c6 != 0.0) ? ((c1 - c6) / c6 * 100.0) : 0.0;
   ind.slopeOK    = InpUseSlopeFilter ? (MathAbs(ind.priceSlope) >= InpSlopeMin) : true;

   //--- SuperTrend -------------------------------------------------------
   ind.stUp = true;
   if(InpSTUse != AX_MODE_OFF || InpSTAlertOnFlip)
   {
      bool up = true;
      if(ComputeSuperTrend(1, up)) ind.stUp = up;
   }

   //--- Advanced structure -----------------------------------------------
   ComputeAdvancedStructure(ind);

   //--- Higher timeframe trend -------------------------------------------
   int    tf     = (int)InpTrendTF;
   double htfEma = iMA(_Symbol, tf, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   ind.higherTFUp   = (htfEma > 0.0) && (c1 >= htfEma);
   ind.higherTFDown = (htfEma > 0.0) && (c1 <  htfEma);

   //--- VWAP ---------------------------------------------------------------
   ind.vwap = (InpVWAPMode != AX_MODE_OFF) ? SessionVWAP(1) : 0.0;

   //--- EMA regime (the original only prints this) --------------------------
   ind.trendUp     = (c1 > ind.ema20) && (ind.ema5 > ind.ema10);
   ind.trendDown   = (c1 < ind.ema20) && (ind.ema5 < ind.ema10);
   double emaDist  = (c1 != 0.0) ? (MathAbs(ind.ema5 - ind.ema20) / c1 * 100.0) : 0.0;
   ind.rangeMarket = (emaDist < 0.15) && (!ind.trendUp) && (!ind.trendDown);

   return(true);
}

//+------------------------------------------------------------------+
//| Thresholds                                                       |
//+------------------------------------------------------------------+
void GetThresholds(AlgoXInd &ind)
{
   switch(InpSensitivity)
   {
      case AX_SENS_CONSERVATIVE: ind.strongThresh = 90; ind.minThresh = 70; break;
      case AX_SENS_AGGRESSIVE:   ind.strongThresh = 80; ind.minThresh = 50; break;
      case AX_SENS_CUSTOM:       ind.strongThresh = InpStrongThreshold; ind.minThresh = InpMinThreshold; break;
      default:                   ind.strongThresh = 85; ind.minThresh = 55; break;
   }
}

//+------------------------------------------------------------------+
//| Relative volume score adjustment (Pine volScoreAdj)               |
//+------------------------------------------------------------------+
double VolumeScoreAdjustment(AlgoXInd &ind)
{
   if(InpVolFilterMode != AX_MODE_SCORE) return(0.0);

   bool volIsStrong = (ind.volRelative >= InpVolRelBullish);
   bool volIsWeak   = (ind.volRelative <= InpVolRelWeak);
   double adj = 0.0;

   if(volIsStrong)
   {
      adj = MathMin(InpVolBonusMax, (ind.volRelative - InpVolRelBullish) / (InpVolRelBullish * 0.5) * InpVolBonusMax);
      adj = MathMax(0.25, adj);
   }
   else if(volIsWeak)
   {
      adj = -MathMin(InpVolMalusMax, (InpVolRelWeak - ind.volRelative) / InpVolRelWeak * InpVolMalusMax);
      adj = MathMin(-0.25, adj);
   }
   return(adj);
}

//+------------------------------------------------------------------+
//| 200 bar close extremes (calculated but unused by the original)     |
//+------------------------------------------------------------------+
void Range200Extremes(double &hi200, double &lo200)
{
   int len = IMin(200, Bars - 3);
   hi200 = -1e18;
   lo200 = 1e18;
   for(int i = 1; i <= len; i++)
   {
      double cc = iClose(_Symbol, _Period, i);
      if(cc > hi200) hi200 = cc;
      if(cc < lo200) lo200 = cc;
   }
}

//+------------------------------------------------------------------+
//| Hard filters coming from the extra / unused indicator blocks       |
//| Returns true when the signal must be blocked.                      |
//+------------------------------------------------------------------+
bool ExtraFilterBlocked(AlgoXInd &ind, const bool buySide)
{
   double c1 = iClose(_Symbol, _Period, 1);

   //--- MACD -----------------------------------------------------------
   if(InpMACDMode == AX_MODE_REQUIRE)
   {
      if(buySide  && !(ind.macdHist > 0.0)) return(true);
      if(!buySide && !(ind.macdHist < 0.0)) return(true);
   }
   //--- VWAP -------------------------------------------------------------
   if(InpVWAPMode == AX_MODE_REQUIRE && ind.vwap > 0.0)
   {
      if(buySide  && !(c1 > ind.vwap)) return(true);
      if(!buySide && !(c1 < ind.vwap)) return(true);
   }
   //--- Volume above average ---------------------------------------------
   if(InpVolAvgMode == AX_MODE_REQUIRE && !ind.volAboveAvg) return(true);

   //--- SuperTrend --------------------------------------------------------
   if(InpSTUse == AX_MODE_REQUIRE)
   {
      if(buySide  && !ind.stUp) return(true);
      if(!buySide &&  ind.stUp) return(true);
   }
   //--- Extra Fibonacci levels ---------------------------------------------
   if(InpExtraFibMode == AX_FIBEXTRA_50 || InpExtraFibMode == AX_FIBEXTRA_BOTH)
   {
      if(buySide  && !(c1 > ind.fib50))  return(true);
      if(!buySide && !(c1 < ind.fib50))  return(true);
   }
   if(InpExtraFibMode == AX_FIBEXTRA_786 || InpExtraFibMode == AX_FIBEXTRA_BOTH)
   {
      if(buySide  && !(c1 > ind.fib786)) return(true);
      if(!buySide && !(c1 < ind.fib786)) return(true);
   }
   //--- 200 bar close extremes -----------------------------------------------
   if(InpRange200Mode == AX_MODE_REQUIRE)
   {
      double hi200, lo200;
      Range200Extremes(hi200, lo200);
      if(buySide  && !(c1 >= hi200)) return(true);
      if(!buySide && !(c1 <= lo200)) return(true);
   }
   //--- Higher timeframe trend (require mode) ---------------------------------
   if(InpTrendFilterMode == AX_MODE_REQUIRE)
   {
      if(buySide  && !ind.higherTFUp)    return(true);
      if(!buySide && !ind.higherTFDown)  return(true);
   }
   //--- Market regime / counter trend risk (unused by the original) ------------
   if(InpRegimeMode == AX_MODE_REQUIRE)
   {
      if(buySide  && ind.trendDown) return(true);
      if(!buySide && ind.trendUp)   return(true);
   }
   //--- Advanced structure -----------------------------------------------------
   if(InpStructMode == AX_STRUCT_FILTER)
   {
      if(buySide  && ind.structBias < 0) return(true);
      if(!buySide && ind.structBias > 0) return(true);
   }
   if(InpStructMode == AX_STRUCT_REQUIRE_FRESH)
   {
      if(!ind.structFresh)                       return(true);
      if(buySide  && !ind.structBull)             return(true);
      if(!buySide && !ind.structBear)             return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Score adjustments of the extra / unused indicator blocks            |
//+------------------------------------------------------------------+
double ExtraScoreAdjust(AlgoXInd &ind, const bool buySide)
{
   double c1  = iClose(_Symbol, _Period, 1);
   double adj = 0.0;

   if(InpMACDMode == AX_MODE_SCORE && InpWeightMACD <= 0.0)
   {
      if(buySide  && ind.macdHist > 0.0) adj += InpExtraWeight;
      if(!buySide && ind.macdHist < 0.0) adj += InpExtraWeight;
   }
   //--- higher timeframe trend as a score component ---------------------
   if(InpTrendFilterMode == AX_MODE_SCORE)
   {
      double htfWeight = (InpWeightHTF > 0.0) ? InpWeightHTF : InpExtraWeight;
      if(buySide  && ind.higherTFUp)   adj += htfWeight;
      if(!buySide && ind.higherTFDown) adj += htfWeight;
   }
   if(InpVWAPMode == AX_MODE_SCORE && ind.vwap > 0.0)
   {
      if(buySide  && c1 > ind.vwap) adj += InpExtraWeight;
      if(!buySide && c1 < ind.vwap) adj += InpExtraWeight;
   }
   if(InpVolAvgMode == AX_MODE_SCORE && ind.volAboveAvg) adj += InpExtraWeight;

   if(InpSTUse == AX_MODE_SCORE)
   {
      if(buySide  &&  ind.stUp) adj += InpSTWeight;
      if(!buySide && !ind.stUp) adj += InpSTWeight;
   }
   if(InpRange200Mode == AX_MODE_SCORE)
   {
      double hi200, lo200;
      Range200Extremes(hi200, lo200);
      if(buySide  && c1 >= hi200) adj += InpExtraWeight;
      if(!buySide && c1 <= lo200) adj += InpExtraWeight;
   }
   if(InpRegimeMode == AX_MODE_SCORE)
   {
      if(buySide  && ind.trendUp)   adj += InpExtraWeight;
      if(!buySide && ind.trendDown) adj += InpExtraWeight;
   }
   return(adj);
}

//+------------------------------------------------------------------+
//| Build both scores in exactly the order of the original script      |
//+------------------------------------------------------------------+
void BuildScores(AlgoXInd &ind)
{
   double c1 = iClose(_Symbol, _Period, 1);

   //--- binary components ------------------------------------------------
   bool buyFib     = (c1 > ind.fib618);
   bool sellFib    = (c1 < ind.fib382);
   bool buyEma     = (c1 > ind.ema20);
   bool sellEma    = (c1 < ind.ema20);
   bool buyStruct  = ind.bullBreak;
   bool sellStruct = ind.bearBreak;

   bool buyRsi, sellRsi;
   if(InpRSIMode == AX_RSI_SCORE_LEVELS)
   {
      buyRsi  = (ind.rsi > InpRSIBuy);
      sellRsi = (ind.rsi < InpRSISell);
   }
   else
   {
      buyRsi  = (ind.rsi > 50.0);
      sellRsi = (ind.rsi < 50.0);
   }

   //--- macd histogram (component with its own weight) --------------------
   bool macdScores = ComponentScores(InpMACDMode, InpWeightMACD);
   bool buyMacd    = macdScores && (ind.macdHist > 0.0);
   bool sellMacd   = macdScores && (ind.macdHist < 0.0);

   //--- relative volume (component with its own weight) -------------------
   bool volScores  = ComponentScores(InpVolFilterMode, InpWeightVolume);
   bool volumeOk   = volScores && (ind.volRelative >= InpVolRelBullish);

   //--- weighted sum ------------------------------------------------------
   double buy  = 0.0;
   double sell = 0.0;
   if(buyFib)     buy  += InpWeightFib;
   if(buyRsi)     buy  += InpWeightRSI;
   if(buyEma)     buy  += InpWeightEMA;
   if(buyStruct)  buy  += InpWeightStruct;
   if(buyMacd)    buy  += InpWeightMACD;
   if(volumeOk)   buy  += InpWeightVolume;

   if(sellFib)    sell += InpWeightFib;
   if(sellRsi)    sell += InpWeightRSI;
   if(sellEma)    sell += InpWeightEMA;
   if(sellStruct) sell += InpWeightStruct;
   if(sellMacd)   sell += InpWeightMACD;
   if(volumeOk)   sell += InpWeightVolume;

   //--- extra score filters of the other optional blocks ------------------
   buy  += ExtraScoreAdjust(ind, true);
   sell += ExtraScoreAdjust(ind, false);

   //--- Pine style relative volume bonus / penalty (kept for compatibility)
   double volAdj = VolumeScoreAdjustment(ind);
   buy  += volAdj;
   sell += volAdj;

   //--- consolidation multiplier -----------------------------------------
   double consolMult = ind.consol ? InpConsolMultiplier : 1.0;
   buy  *= consolMult;
   sell *= consolMult;

   //--- higher timeframe trend bonus --------------------------------------
   if(InpTrendFilterMode == AX_MODE_BONUS)
   {
      double bonus = (InpWeightHTF > 0.0) ? InpWeightHTF : InpTrendBonus;
      if(ind.higherTFUp)   buy  += bonus;
      if(ind.higherTFDown) sell += bonus;
   }

   ind.buyScore  = buy;
   ind.sellScore = sell;

   GetThresholds(ind);

   ind.rawBuy  = (ind.buyScore  >= ind.minThresh) && ind.slopeOK;
   ind.rawSell = (ind.sellScore >= ind.minThresh) && ind.slopeOK;
}

//+------------------------------------------------------------------+
//| Order pool helpers                                                |
//+------------------------------------------------------------------+
int FindMyPosition()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) return(OrderTicket());
   }
   return(0);
}

int FindMyPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() > OP_SELL) return(OrderTicket());
   }
   return(0);
}

bool HasPositionOrPending()
{
   if(FindMyPosition() > 0) return(true);
   if(FindMyPending()  > 0) return(true);
   return(false);
}

//+------------------------------------------------------------------+
//| Trade state stored in terminal global variables (survives restart) |
//+------------------------------------------------------------------+
string GvName(const int ticket, const string key)
{
   return("AX_" + IntegerToString(InpMagicNumber) + "_" + IntegerToString(ticket) + "_" + key);
}

void SaveTradeState(const int ticket, const double riskDist, const double rr,
                    const double tp1, const double tp2, const int stage)
{
   GlobalVariableSet(GvName(ticket, "risk"),  riskDist);
   GlobalVariableSet(GvName(ticket, "rr"),    rr);
   GlobalVariableSet(GvName(ticket, "tp1"),   tp1);
   GlobalVariableSet(GvName(ticket, "tp2"),   tp2);
   GlobalVariableSet(GvName(ticket, "stage"), (double)stage);
   GlobalVariableSet(GvName(ticket, "mode"),  (double)g_effExit);
   GlobalVariableSet(GvName(ticket, "betrig"), g_beTrigger);
}

bool LoadTradeState(const int ticket)
{
   if(!GlobalVariableCheck(GvName(ticket, "risk"))) return(false);
   g_riskDist = GlobalVariableGet(GvName(ticket, "risk"));
   g_rr       = GlobalVariableCheck(GvName(ticket, "rr")) ? GlobalVariableGet(GvName(ticket, "rr")) : 0.0;
   g_tp1      = GlobalVariableCheck(GvName(ticket, "tp1")) ? GlobalVariableGet(GvName(ticket, "tp1")) : 0.0;
   g_tp2      = GlobalVariableCheck(GvName(ticket, "tp2")) ? GlobalVariableGet(GvName(ticket, "tp2")) : 0.0;
   g_tp1Done  = (GlobalVariableCheck(GvName(ticket, "stage")) && GlobalVariableGet(GvName(ticket, "stage")) >= 1.0);
   g_effExit  = GlobalVariableCheck(GvName(ticket, "mode"))
                ? (ENUM_AX_EXIT)(int)GlobalVariableGet(GvName(ticket, "mode")) : InpExitMode;
   g_beTrigger= GlobalVariableCheck(GvName(ticket, "betrig")) ? GlobalVariableGet(GvName(ticket, "betrig")) : 0.0;
   return(true);
}

void DeleteTradeState(const int ticket)
{
   GlobalVariableDel(GvName(ticket, "risk"));
   GlobalVariableDel(GvName(ticket, "rr"));
   GlobalVariableDel(GvName(ticket, "tp1"));
   GlobalVariableDel(GvName(ticket, "tp2"));
   GlobalVariableDel(GvName(ticket, "stage"));
   GlobalVariableDel(GvName(ticket, "mode"));
   GlobalVariableDel(GvName(ticket, "betrig"));
}

//+------------------------------------------------------------------+
//| Risk distance and lot sizing                                      |
//+------------------------------------------------------------------+
double ComputeRiskDistance(const double atrVal, const double score, double &rrOut)
{
   double a = (atrVal > 0.0) ? atrVal : 1.0;
   double slFactor, tpFactor;

   switch(g_ind.adxLevel)
   {
      case 2:  slFactor = InpSLFactorStrong; tpFactor = InpTPFactorStrong; break;
      case 1:  slFactor = InpSLFactorMed;    tpFactor = InpTPFactorMed;    break;
      default: slFactor = InpSLFactorWeak;   tpFactor = InpTPFactorWeak;   break;
   }

   double dynSLMult = InpUseDynamicSLTP ? (InpBaseSLMult * slFactor) : InpBaseSLMult;
   double dynRR     = InpUseDynamicSLTP ? (InpBaseTPRR * tpFactor)   : InpBaseTPRR;

   //--- Pine calcSLMultiplier(score) = clamp(1.35 - score * 0.005, 0.75, 1.25)
   double slAdj = 1.35 - score * 0.005;
   slAdj = MathMax(0.75, MathMin(1.25, slAdj));

   rrOut = dynRR;
   return(a * dynSLMult * slAdj);
}

double ComputeLots(const double riskDist, const int dir)
{
   if(InpSizingMode == AX_SIZING_FIXED_LOT) return(NormalizeLot(InpFixedLot));
   if(riskDist <= 0.0)                      return(NormalizeLot(InpFixedLot));

   double balance = AccountBalance();
   double riskPct = InpRiskPercent;

   //--- hard cap on the risk percentage (the presets stay well below it) --
   if(InpUseSafetyLimits && InpRiskPercentCap > 0.0 && riskPct > InpRiskPercentCap)
   {
      LogMsg("SAFETY: risk " + DoubleToString(riskPct, 2) + "% capped to " +
             DoubleToString(InpRiskPercentCap, 2) + "%");
      riskPct = InpRiskPercentCap;
   }

   //--- optional risk boost on strong signals --------------------------
   if(InpStrongMode == AX_STRONG_BOOST_RISK)
   {
      double sc = (dir > 0) ? g_ind.buyScore : g_ind.sellScore;
      if(sc >= g_ind.strongThresh) riskPct *= InpStrongRiskMult;
   }

   double riskMoney = balance * riskPct / 100.0;
   double perUnit   = 0.0;

   switch(InpSizingMode)
   {
      case AX_SIZING_BROKER:
      {
         double tickValue = MarketInfo(_Symbol, MODE_TICKVALUE);
         double tickSize  = MarketInfo(_Symbol, MODE_TICKSIZE);
         if(tickSize <= 0.0) tickSize = Point;
         if(tickSize > 0.0)  perUnit = tickValue / tickSize;   // account currency per 1.0 price move per lot
         break;
      }
      case AX_SIZING_MANUAL_VALUE:
         perUnit = InpPineLotValue;
         break;
      default: // AX_SIZING_PINE_FIXED - exactly the indicator formula
         riskMoney = InpPineBalance * InpRiskPercent / 100.0;
         perUnit   = InpPineLotValue;
         break;
   }

   if(perUnit <= 0.0) return(NormalizeLot(InpFixedLot));

   double lots = riskMoney / (riskDist * perUnit);

   //--- margin cap: never take more than InpMaxMarginPercent of the equity -
   double stepC  = MarketInfo(_Symbol, MODE_LOTSTEP);
   double minLotC = MarketInfo(_Symbol, MODE_MINLOT);
   if(stepC   <= 0.0) stepC   = 0.01;
   if(minLotC <= 0.0) minLotC = stepC;

   if(InpUseSafetyLimits && InpMaxMarginPercent > 0.0)
   {
      double marginPerLot = MarketInfo(_Symbol, MODE_MARGINREQUIRED);
      double equity       = AccountEquity();
      if(marginPerLot > 0.0 && equity > 0.0)
      {
         double maxLots = equity * InpMaxMarginPercent / 100.0 / marginPerLot;
         if(lots > maxLots)
         {
            lots = MathFloor(maxLots / stepC + 0.0000001) * stepC;
            if(lots < minLotC)
            {
               LogMsg("SAFETY: trade rejected - the margin cap of " +
                      DoubleToString(InpMaxMarginPercent, 1) + "% of equity (" +
                      DoubleToString(equity * InpMaxMarginPercent / 100.0, 2) + ") is below one lot");
               return(0.0);
            }
            LogMsg("SAFETY: position size reduced to " + DoubleToString(lots, LotDigits()) +
                   " lots by the margin cap (" + DoubleToString(InpMaxMarginPercent, 1) + "% of equity)");
         }
      }
   }

   lots = NormalizeLot(lots);

   //--- margin safety ---------------------------------------------------
   double step   = MarketInfo(_Symbol, MODE_LOTSTEP);
   double minLot = MarketInfo(_Symbol, MODE_MINLOT);
   if(step   <= 0.0) step   = 0.01;
   if(minLot <= 0.0) minLot = step;

   int guard = 0;
   while(lots >= minLot && guard < 500)
   {
      ResetLastError();
      double freeMargin = AccountFreeMarginCheck(_Symbol, (dir > 0) ? OP_BUY : OP_SELL, lots);
      if(freeMargin > 0.0) break;
      if(GetLastError() != ERR_NOT_ENOUGH_MONEY) break;
      lots = NormalizeDouble(lots - step, LotDigits());
      guard++;
   }
   if(lots < minLot)
   {
      if(InpUseSafetyLimits)
      {
         LogMsg("SAFETY: trade rejected - the free margin does not allow the minimum lot");
         return(0.0);
      }
      lots = minLot;
   }
   return(lots);
}

//+------------------------------------------------------------------+
//| Price helpers                                                     |
//+------------------------------------------------------------------+
double MinStopDistance()
{
   double stopLevel = MarketInfo(_Symbol, MODE_STOPLEVEL) * Point;
   double freeze    = MarketInfo(_Symbol, MODE_FREEZELEVEL) * Point;
   double d = MathMax(stopLevel, freeze);
   if(d < 3.0 * Point) d = 3.0 * Point;
   return(d);
}

//--- account currency value of a 1.0 price move per lot ------------------
double AccountPerUnit()
{
   if(InpSizingMode == AX_SIZING_PINE_FIXED || InpSizingMode == AX_SIZING_MANUAL_VALUE)
      return(InpPineLotValue);

   double tickValue = MarketInfo(_Symbol, MODE_TICKVALUE);
   double tickSize  = MarketInfo(_Symbol, MODE_TICKSIZE);
   if(tickSize <= 0.0) tickSize = Point;
   if(tickValue <= 0.0 || tickSize <= 0.0) return(0.0);
   return(tickValue / tickSize);
}

//--- daily counters ------------------------------------------------------
void UpdateDailyState()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(g_safetyDay == dt.day_of_year) return;

   g_safetyDay      = dt.day_of_year;
   g_tradesToday    = 0;
   g_lossStreak     = 0;
   g_dayHalted      = false;
   g_haltLogged     = false;
   g_dayStartEquity = (AccountEquity() > 0.0) ? AccountEquity() : AccountBalance();
   LogMsg("New trading day: equity at day start " + DoubleToString(g_dayStartEquity, 2));
}

//--- profit of a closed trade (history lookup) ---------------------------
double ClosedTradeProfit(const int ticket)
{
   if(OrderSelect(ticket, SELECT_BY_TICKET))
      return(OrderProfit() + OrderSwap() + OrderCommission());

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderTicket() != ticket) continue;
      return(OrderProfit() + OrderSwap() + OrderCommission());
   }
   return(0.0);
}

//--- the guards that sit above every filter ------------------------------
bool SafetyAllowsTrading()
{
   if(!InpUseSafetyLimits) return(true);
   if(g_hardHalted)        return(false);
   if(g_dayHalted)         return(false);

   double equity = (AccountEquity() > 0.0) ? AccountEquity() : AccountBalance();
   double ref    = (g_dayStartEquity > 0.0) ? g_dayStartEquity : equity;
   double dropPct = (ref > 0.0) ? (ref - equity) / ref * 100.0 : 0.0;

   //--- permanent circuit breaker ---------------------------------------
   if(InpEquityStopPercent > 0.0 && dropPct >= InpEquityStopPercent)
   {
      g_hardHalted = true;
      g_dayHalted  = true;
      LogMsg("EQUITY STOP: equity dropped " + DoubleToString(dropPct, 2) +
             "% from the day start. Trading is halted until the EA is reloaded.");
      return(false);
   }

   //--- stop for the rest of the day -------------------------------------
   string reason = "";
   if(InpMaxDailyLossPercent > 0.0 && dropPct >= InpMaxDailyLossPercent)
      reason = "daily loss limit reached (" + DoubleToString(dropPct, 2) + "%)";
   else if(InpMaxConsecutiveLosses > 0 && g_lossStreak >= InpMaxConsecutiveLosses)
      reason = "consecutive losses: " + IntegerToString(g_lossStreak);
   else if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
      reason = "daily trade limit reached (" + IntegerToString(g_tradesToday) + ")";

   if(reason != "")
   {
      g_dayHalted = true;
      if(!g_haltLogged)
      {
         g_haltLogged = true;
         LogMsg("SAFETY: no more entries today - " + reason);
      }
      return(false);
   }
   return(true);
}

bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0.0) return(true);
   double spread = (MarketInfo(_Symbol, MODE_ASK) - MarketInfo(_Symbol, MODE_BID)) / Point;
   return(spread <= InpMaxSpreadPoints);
}

//--- Spread used by the cost gates. The fixed value is what the research
//--- assumed (47 points = 0.47 USD on a 2-digit gold quote); without it the
//--- live spread of the symbol is used.
double EffectiveSpread()
{
   if(InpUseCostFilters && InpFixedSpreadPoints > 0)
      return(InpFixedSpreadPoints * Point);
   return(MarketInfo(_Symbol, MODE_ASK) - MarketInfo(_Symbol, MODE_BID));
}

//--- A component contributes score when its mode is SCORE, or when the mode
//--- is OFF but a positive weight was configured for it (auto-score mode).
bool ComponentScores(const ENUM_AX_MODE mode, const double weight)
{
   if(mode == AX_MODE_REQUIRE) return(false);
   if(mode == AX_MODE_SCORE)   return(true);
   return(mode == AX_MODE_OFF && weight > 0.0);
}

//+------------------------------------------------------------------+
//| Trade execution                                                   |
//+------------------------------------------------------------------+
bool SendMarketOrder(const int dir, const double lots, const double sl, const double tp,
                     const string cmt, int &ticketOut)
{
   RefreshRates();
   double price = (dir > 0) ? MarketInfo(_Symbol, MODE_ASK) : MarketInfo(_Symbol, MODE_BID);
   color  clr   = (dir > 0) ? clrBlue : clrRed;
   int    type  = (dir > 0) ? OP_BUY : OP_SELL;

   ticketOut = OrderSend(_Symbol, type, lots, NormalizeDouble(price, Digits), InpSlippage,
                         NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits),
                         cmt, InpMagicNumber, 0, clr);
   if(ticketOut > 0) return(true);

   LogMsg("OrderSend failed (err=" + IntegerToString(GetLastError()) + ") - retrying without SL/TP");
   ticketOut = OrderSend(_Symbol, type, lots, NormalizeDouble(price, Digits), InpSlippage,
                         0.0, 0.0, cmt, InpMagicNumber, 0, clr);
   if(ticketOut <= 0)
   {
      LogMsg("OrderSend retry failed (err=" + IntegerToString(GetLastError()) + ")");
      return(false);
   }
   if(sl > 0.0 || tp > 0.0)
      ApplyStopLossTakeProfit(ticketOut, sl, tp);
   return(true);
}

bool SendPendingOrder(const int dir, const ENUM_AX_ENTRY_MODE mode, const double lots,
                      const double level, const double sl, const double tp,
                      const string cmt, int &ticketOut)
{
   int type;
   if(dir > 0) type = (mode == AX_ENTRY_LIMIT) ? OP_BUYLIMIT : OP_BUYSTOP;
   else        type = (mode == AX_ENTRY_LIMIT) ? OP_SELLLIMIT : OP_SELLSTOP;

   RefreshRates();
   ticketOut = OrderSend(_Symbol, type, lots, NormalizeDouble(level, Digits), InpSlippage,
                         NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits),
                         cmt, InpMagicNumber, 0, clrGray);
   if(ticketOut > 0) return(true);

   LogMsg("Pending OrderSend failed (err=" + IntegerToString(GetLastError()) + ")");
   return(false);
}

//--- Sets the SL/TP of an existing order.                            --
//---   sl < 0 keeps the current value, sl = 0 removes it, sl > 0 sets it. --
void ApplyStopLossTakeProfit(const int ticket, const double sl, const double tp)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;

   double curSL = OrderStopLoss();
   double curTP = OrderTakeProfit();
   double nsl = (sl < 0.0) ? curSL : NormalizeDouble(sl, Digits);
   double ntp = (tp < 0.0) ? curTP : NormalizeDouble(tp, Digits);

   if(MathAbs(nsl - curSL) < Point / 2.0 && MathAbs(ntp - curTP) < Point / 2.0) return;

   if(!OrderModify(ticket, OrderOpenPrice(), nsl, ntp, 0, clrYellow))
      LogMsg("OrderModify (SL/TP) failed on #" + IntegerToString(ticket) +
             " err=" + IntegerToString(GetLastError()));
}

//+------------------------------------------------------------------+
//| Re-anchor the SL/TP around the real fill price                    |
//+------------------------------------------------------------------+
void ApplyAnchorOnAdopt(const int ticket)
{
   if(InpSLAnchor != AX_ANCHOR_RECENTER) return;
   if(g_tp1Done)                         return;
   if(g_riskDist <= 0.0 || g_rr <= 0.0)  return;
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;

   int    dir  = (OrderType() == OP_BUY) ? 1 : -1;
   double fill = OrderOpenPrice();

   g_tp1 = (dir > 0) ? (fill + g_riskDist * g_rr) : (fill - g_riskDist * g_rr);
   g_tp2 = (dir > 0) ? (fill + g_riskDist * g_rr * InpTP2Multiplier)
                     : (fill - g_riskDist * g_rr * InpTP2Multiplier);
   double nsl = (dir > 0) ? (fill - g_riskDist) : (fill + g_riskDist);
   double ntp;
   if(g_effExit == AX_EXIT_TP1_ONLY)      ntp = g_tp1;
   else if(g_effExit == AX_EXIT_TP2_ONLY) ntp = g_tp2;
   else                                   ntp = InpKeepTP2OnOrder ? g_tp2 : 0.0;

   ApplyStopLossTakeProfit(ticket, nsl, ntp);
}

//+------------------------------------------------------------------+
//| Position bookkeeping                                              |
//+------------------------------------------------------------------+
void AdoptPosition(const int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;

   g_ticket     = ticket;
   g_tradeDir   = (OrderType() == OP_BUY) ? 1 : -1;
   g_entryPrice = OrderOpenPrice();
   g_tp1Done    = false;

   if(!LoadTradeState(ticket))
   {
      //--- state lost (e.g. restart on another terminal): derive from the order
      g_riskDist = (OrderStopLoss() > 0.0) ? MathAbs(OrderOpenPrice() - OrderStopLoss()) : 0.0;
      g_rr       = 0.0;
      g_tp1      = OrderTakeProfit();
      g_tp2      = OrderTakeProfit();
      g_effExit  = InpExitMode;
      g_beTrigger= 0.0;
      SaveTradeState(ticket, g_riskDist, 0.0, g_tp1, g_tp2, 0);
   }
   if(g_riskDist <= 0.0 && OrderStopLoss() > 0.0)
      g_riskDist = MathAbs(OrderOpenPrice() - OrderStopLoss());

   ApplyAnchorOnAdopt(ticket);

   LogMsg("Trading position #" + IntegerToString(ticket) + " dir=" + IntegerToString(g_tradeDir) +
          " lots=" + DoubleToString(OrderLots(), 2) +
          " entry=" + DoubleToString(g_entryPrice, Digits) +
          " SL=" + DoubleToString(OrderStopLoss(), Digits) +
          " TP=" + DoubleToString(OrderTakeProfit(), Digits) +
          " risk=" + DoubleToString(g_riskDist, Digits));
}

void OnTradeClosed()
{
   int closedTicket = g_ticket;
   int closedDir    = g_tradeDir;
   if(closedTicket > 0) DeleteTradeState(closedTicket);

   double closedProfit = (closedTicket > 0) ? ClosedTradeProfit(closedTicket) : 0.0;
   if(closedTicket > 0)
   {
      if(closedProfit < 0.0)
      {
         g_lossStreak++;
         LogMsg("Closed #" + IntegerToString(closedTicket) + " with " +
                DoubleToString(closedProfit, 2) + " | consecutive losses today: " +
                IntegerToString(g_lossStreak));
      }
      else
      {
         if(g_lossStreak > 0)
            LogMsg("Losing streak of " + IntegerToString(g_lossStreak) + " ended.");
         g_lossStreak = 0;
      }
   }

   LogMsg("Position #" + IntegerToString(closedTicket) + " is closed. Balance=" +
          DoubleToString(AccountBalance(), 2));

   g_ticket     = 0;
   g_tradeDir   = 0;
   g_entryPrice = 0.0;
   g_tp1Done    = false;
   g_riskDist   = 0.0;
   g_beTrigger  = 0.0;
   g_effExit    = InpExitMode;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(InpReEntryMode == AX_REENTRY_BLOCK_SAME_DIR ||
      InpReEntryMode == AX_REENTRY_BLOCK_SAME_DAY)
   {
      g_blockedDir = closedDir;
      g_blockedDay = dt.day_of_year;
   }
   else
   {
      g_blockedDir = 0;
      g_blockedDay = 0;
   }
}

//+------------------------------------------------------------------+
//| Close helpers                                                     |
//+------------------------------------------------------------------+
bool ClosePosition(const int ticket, const double lots)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return(false);
   double price = (OrderType() == OP_BUY) ? MarketInfo(_Symbol, MODE_BID) : MarketInfo(_Symbol, MODE_ASK);
   if(!OrderClose(ticket, lots, NormalizeDouble(price, Digits), InpSlippage, clrOrange))
   {
      LogMsg("OrderClose failed on #" + IntegerToString(ticket) + " err=" + IntegerToString(GetLastError()));
      return(false);
   }
   LogMsg("Closed " + DoubleToString(lots, 2) + " lots on #" + IntegerToString(ticket));
   return(true);
}

//+------------------------------------------------------------------+
//| Move the stop to break-even (shared by the TP1 and the cost paths) |
//+------------------------------------------------------------------+
bool MoveStopToBreakEven(const int dir, const double bid, const double ask, const double stopDist)
{
   if(!OrderSelect(g_ticket, SELECT_BY_TICKET)) return(false);
   if(!InpMoveToBEAtTP1) return(false);

   double be     = OrderOpenPrice() + dir * InpBEPlusPoints * Point;
   bool   ok     = (dir > 0) ? (be <= bid - stopDist) : (be >= ask + stopDist);
   double cur    = OrderStopLoss();
   bool   better = (dir > 0) ? (be > cur) : (cur == 0.0 || be < cur);
   if(!ok || !better) return(false);

   if(!OrderModify(g_ticket, OrderOpenPrice(), NormalizeDouble(be, Digits),
                   OrderTakeProfit(), 0, clrYellow))
   {
      LogMsg("Break-even OrderModify failed err=" + IntegerToString(GetLastError()));
      return(false);
   }
   LogMsg("Stop moved to break-even at " + DoubleToString(be, Digits));
   return(true);
}

//+------------------------------------------------------------------+
//| Manage the open position (TP1 partial, break-even, trailing)      |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   //--- circuit breaker: close everything when the equity stop fired -------
   if(g_hardHalted && InpCloseOnEquityStop)
   {
      int pos = FindMyPosition();
      if(pos > 0 && OrderSelect(pos, SELECT_BY_TICKET))
      {
         LogMsg("Equity stop: closing position #" + IntegerToString(pos));
         ClosePosition(pos, OrderLots());
      }
      int pend = FindMyPending();
      if(pend > 0 && OrderSelect(pend, SELECT_BY_TICKET))
         OrderDelete(pend);
      return;
   }

   if(g_ticket <= 0) return;
   if(!OrderSelect(g_ticket, SELECT_BY_TICKET)) { OnTradeClosed(); return; }
   if(OrderCloseTime() != 0 || (OrderType() != OP_BUY && OrderType() != OP_SELL))
   {
      OnTradeClosed();
      return;
   }

   int    dir      = (OrderType() == OP_BUY) ? 1 : -1;
   double bid      = MarketInfo(_Symbol, MODE_BID);
   double ask      = MarketInfo(_Symbol, MODE_ASK);
   double px       = (dir > 0) ? bid : ask;
   double stopDist = MinStopDistance();

   //--- optional time based exit ---------------------------------------
   if(InpMaxBarsInTrade > 0)
   {
      int barsHeld = iBarShift(_Symbol, _Period, OrderOpenTime());
      if(barsHeld >= InpMaxBarsInTrade)
      {
         LogMsg("Time exit after " + IntegerToString(barsHeld) + " bars");
         if(ClosePosition(g_ticket, OrderLots()))
         {
            OnTradeClosed();
            return;
         }
      }
   }

   bool splitMode = (g_effExit == AX_EXIT_SPLIT_BE || g_effExit == AX_EXIT_TRAIL_AFTER_TP1);
   //--- (AX_EXIT_TP2_BE trades use a single TP plus the break-even trigger)

   //--- TP1 partial close ------------------------------------------------
   if(splitMode && !g_tp1Done && g_tp1 > 0.0)
   {
      bool hit = (dir > 0) ? (px >= g_tp1) : (px <= g_tp1);
      if(hit)
      {
         double lots   = OrderLots();
         double minLot = MarketInfo(_Symbol, MODE_MINLOT);
         if(minLot <= 0.0) minLot = 0.01;

         double portion = MathMax(0.05, MathMin(1.0, InpTP1Portion));
         double part    = NormalizeLot(lots * portion);

         if(part < minLot || (lots - part) < minLot) part = lots;   // cannot split

         if(part >= lots)
         {
            LogMsg("TP1 reached - closing the whole position (cannot split " +
                   DoubleToString(lots, 2) + " lots)");
            if(ClosePosition(g_ticket, lots))
            {
               OnTradeClosed();
               return;
            }
            return;   // closing failed - retry on the next tick
         }

         if(!ClosePosition(g_ticket, part))
            return;   // partial close failed - retry on the next tick

         //--- move the stop to break-even ---------------------------------
         MoveStopToBreakEven(dir, bid, ask, stopDist);
         g_tp1Done = true;
         SaveTradeState(g_ticket, g_riskDist, g_rr, g_tp1, g_tp2, 1);
         return;
      }
   }

   //--- break-even move triggered by price (cost-gated trades without TP1) --
   if(!g_tp1Done && g_beTrigger > 0.0)
   {
      bool reached = (dir > 0) ? (px >= g_beTrigger) : (px <= g_beTrigger);
      if(reached)
      {
         if(MoveStopToBreakEven(dir, bid, ask, stopDist))
         {
            g_tp1Done = true;
            SaveTradeState(g_ticket, g_riskDist, g_rr, g_tp1, g_tp2, 1);
            return;
         }
         if(!InpMoveToBEAtTP1)
         {
            //--- break-even is disabled: there is nothing left to wait for ------
            g_tp1Done = true;
            SaveTradeState(g_ticket, g_riskDist, g_rr, g_tp1, g_tp2, 1);
            return;
         }
         //--- otherwise retry on the next tick: the stop is simply not far
         //--- enough below/above the entry yet.
      }
   }

   //--- TP2 exit for the remaining part when no server side TP is used -----
   bool tp2Armed = (g_effExit == AX_EXIT_TP2_ONLY) || g_tp1Done;
   if(tp2Armed && !InpKeepTP2OnOrder && g_tp2 > 0.0)
   {
      bool hitTP2 = (dir > 0) ? (px >= g_tp2) : (px <= g_tp2);
      if(hitTP2)
      {
         LogMsg("TP2 reached - closing the remaining position");
         if(ClosePosition(g_ticket, OrderLots()))
         {
            OnTradeClosed();
            return;
         }
      }
   }

   //--- trailing stop ------------------------------------------------------
   if(g_effExit == AX_EXIT_TRAIL_AFTER_TP1 && g_tp1Done)
   {
      double dist = 0.0;
      if(InpTrailMode == AX_TRAIL_BY_ATR)
         dist = iATR(_Symbol, _Period, InpSTPeriods, 1) * InpTrailATRMult;
      else
         dist = g_riskDist * InpTrailDistR;

      if(dist > 0.0)
      {
         double newSL  = (dir > 0) ? (px - dist) : (px + dist);
         bool   ok     = (dir > 0) ? (newSL <= bid - stopDist) : (newSL >= ask + stopDist);
         double curSL  = OrderStopLoss();
         bool   better = (dir > 0) ? (newSL > curSL + Point / 2.0)
                                   : (curSL == 0.0 || newSL < curSL - Point / 2.0);
         if(ok && better)
         {
            if(!OrderModify(g_ticket, OrderOpenPrice(), NormalizeDouble(newSL, Digits),
                            OrderTakeProfit(), 0, clrYellow))
               LogMsg("Trailing OrderModify failed err=" + IntegerToString(GetLastError()));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Pending order life cycle (fill detection and manual expiry)       |
//+------------------------------------------------------------------+
void ManagePendingOrders()
{
   int pend = FindMyPending();

   if(pend == 0)
   {
      //--- a tracked pending order may have been filled -----------------
      if(g_ticket <= 0)
      {
         int pos = FindMyPosition();
         if(pos > 0)
         {
            AdoptPosition(pos);
            g_pendingBarTime = 0;
         }
      }
      return;
   }

   if(!OrderSelect(pend, SELECT_BY_TICKET)) return;

   datetime placed    = (g_pendingBarTime > 0) ? g_pendingBarTime : OrderOpenTime();
   int      barsAlive = iBarShift(_Symbol, _Period, placed);
   if(barsAlive < 0) barsAlive = 0;
   int      expiry    = IMax(1, InpPendingExpiryBars);

   if(barsAlive >= expiry)
   {
      if(OrderDelete(pend, clrGray))
      {
         LogMsg("Pending #" + IntegerToString(pend) + " expired after " +
                IntegerToString(barsAlive) + " bar(s) - deleted");
         DeleteTradeState(pend);
         g_pendingBarTime = 0;
      }
      else
         LogMsg("OrderDelete failed err=" + IntegerToString(GetLastError()));
   }
}

//+------------------------------------------------------------------+
//| Signal helpers                                                    |
//+------------------------------------------------------------------+
double ReferenceEntryPrice(const int dir)
{
   double h   = iHigh(_Symbol, _Period, 1);
   double l   = iLow(_Symbol, _Period, 1);
   double rng = h - l;
   double pct = (double)InpEntryPercent / 100.0;
   if(dir > 0) return(l + rng * pct);   // BUY  level = low  + pct * range
   return(h - rng * pct);               // SELL level = high - pct * range
}

//--- The odd activation window of the original (cancel inside 0.50) ---
bool PineActivationCancel(const int dir, const double refEntry)
{
   if(!InpUsePineCancelRule) return(false);
   double op = iOpen(_Symbol, _Period, 0);

   if(dir > 0)
   {
      if(op == refEntry)                       return(false);
      if(op >= refEntry + InpPineCancelWindow) return(false);
      if(op < refEntry)                        return(false);
      return(true);
   }
   if(op == refEntry)                          return(false);
   if(op <= refEntry - InpPineCancelWindow)    return(false);
   if(op > refEntry)                           return(false);
   return(true);
}

//+------------------------------------------------------------------+
//| Execute a signal (entry, SL, TP, sizing)                          |
//+------------------------------------------------------------------+
void ExecuteSignal(const int dir, const double refEntry)
{
   double score    = (dir > 0) ? g_ind.buyScore : g_ind.sellScore;
   double rr       = 0.0;
   double riskDist = ComputeRiskDistance(g_ind.atr, score, rr);
   if(riskDist <= 0.0 || rr <= 0.0)
   {
      LogMsg("Signal skipped: invalid risk distance or R:R");
      return;
   }

   double tp2Mult = InpTP2Multiplier;
   double slRef, tp1Ref, tp2Ref;
   if(dir > 0)
   {
      slRef  = refEntry - riskDist;
      tp1Ref = refEntry + riskDist * rr;
      tp2Ref = refEntry + riskDist * rr * tp2Mult;
   }
   else
   {
      slRef  = refEntry + riskDist;
      tp1Ref = refEntry - riskDist * rr;
      tp2Ref = refEntry - riskDist * rr * tp2Mult;
   }

   //--- cost gates: the trade geometry must be large enough for the spread --
   double spread    = EffectiveSpread();
   double tp1Dist   = riskDist * rr;
   double tp2Dist   = tp1Dist * tp2Mult;
   bool   skipTP1   = false;
   g_beTrigger      = 0.0;
   g_effExit        = InpExitMode;

   if(InpUseCostFilters)
   {
      if(InpMinSLSpreadMult > 0.0 && riskDist < InpMinSLSpreadMult * spread)
      {
         LogMsg("Signal skipped: SL " + DoubleToString(riskDist, Digits) +
                " is smaller than " + DoubleToString(InpMinSLSpreadMult, 1) +
                " x spread (" + DoubleToString(spread, Digits) + ")");
         return;
      }
      if(InpMinTargetSpreadMult > 0.0 && tp2Dist < InpMinTargetSpreadMult * spread)
      {
         LogMsg("Signal skipped: TP2 " + DoubleToString(tp2Dist, Digits) +
                " is smaller than " + DoubleToString(InpMinTargetSpreadMult, 1) +
                " x spread (" + DoubleToString(spread, Digits) + ")");
         return;
      }
      if(InpSkipTP1IfUneconomic && tp1Dist < InpMinTargetSpreadMult * spread)
      {
         skipTP1 = true;
         LogMsg("TP1 (" + DoubleToString(tp1Dist, Digits) +
                ") is too small against the spread - the trade targets TP2 instead");
      }
   }

   //--- effective exit plan for this trade --------------------------------
   if(InpExitMode == AX_EXIT_TP2_BE)
   {
      g_effExit   = AX_EXIT_TP2_ONLY;   // single target, no partial close
      g_beTrigger = tp1Ref;             // stop moves to break-even at the TP1 distance
   }

   if(skipTP1)
   {
      switch(InpExitMode)
      {
         case AX_EXIT_TP1_ONLY:
            g_effExit = AX_EXIT_TP2_ONLY;
            break;
         case AX_EXIT_SPLIT_BE:
            g_effExit   = AX_EXIT_TP2_ONLY;      // no partial close, TP2 only
            g_beTrigger = tp1Ref;                // but the stop still moves to BE at TP1
            break;
         case AX_EXIT_TRAIL_AFTER_TP1:
            g_effExit   = AX_EXIT_TP2_ONLY;      // trailing starts after the BE move
            g_beTrigger = tp1Ref;
            break;
         default: // AX_EXIT_TP2_ONLY stays as it is
            break;
      }
   }
   else if(InpExitMode == AX_EXIT_TRAIL_AFTER_TP1)
      g_beTrigger = 0.0;

   double lots    = ComputeLots(riskDist, dir);
   if(lots <= 0.0)
   {
      LogMsg("Signal skipped: the position size was rejected by the safety limits");
      return;
   }
   double orderTP = 0.0;
   if(g_effExit == AX_EXIT_TP1_ONLY)      orderTP = tp1Ref;
   else if(g_effExit == AX_EXIT_TP2_ONLY) orderTP = tp2Ref;
   else                                   orderTP = InpKeepTP2OnOrder ? tp2Ref : 0.0;

   string cmt = (dir > 0) ? "AlgoX-BUY" : "AlgoX-SELL";

   LogMsg("SIGNAL " + cmt + " score=" + DoubleToString(score, 1) +
          " ref=" + DoubleToString(refEntry, Digits) +
          " SL=" + DoubleToString(slRef, Digits) +
          " TP1=" + DoubleToString(tp1Ref, Digits) +
          " TP2=" + DoubleToString(tp2Ref, Digits) +
          " lots=" + DoubleToString(lots, 2) +
          " risk=" + DoubleToString(lots * riskDist * AccountPerUnit(), 2) + " (" +
          DoubleToString((AccountBalance() > 0.0)
                         ? lots * riskDist * AccountPerUnit() / AccountBalance() * 100.0 : 0.0, 2) +
          "% of balance)" +
          " ATR=" + DoubleToString(g_ind.atr, Digits) +
          " ADX=" + DoubleToString(g_ind.adx, 1) + "(" + g_ind.adxLevelName + ")" +
          " spread=" + DoubleToString(spread, Digits) +
          " exit=" + IntegerToString((int)g_effExit) +
          (g_beTrigger > 0.0 ? " BE@" + DoubleToString(g_beTrigger, Digits) : "") +
          (g_ind.consol ? " [CONSOLIDATION]" : ""));

   //--- register the signal (Pine: lastSignalBar / lastDir) -------------
   g_lastSignalBarTime = iTime(_Symbol, _Period, 1);
   g_lastDir           = dir;

   if(InpAlertOnSignal)
      Alert("AlgoX " + cmt + " | score " + DoubleToString(score, 1) +
            " | entry " + DoubleToString(refEntry, Digits));

   //--- market entry ----------------------------------------------------
   if(InpEntryMode == AX_ENTRY_MARKET)
   {
      if(PineActivationCancel(dir, refEntry))
      {
         LogMsg("Signal cancelled by the original 0.50 activation window rule");
         return;
      }

      int tk = 0;
      if(!SendMarketOrder(dir, lots, slRef, orderTP, cmt, tk)) return;

      g_tradesToday++;
      SaveTradeState(tk, riskDist, rr, tp1Ref, tp2Ref, 0);
      AdoptPosition(tk);
      return;
   }

   //--- limit / stop entry ----------------------------------------------
   RefreshRates();
   double ask  = MarketInfo(_Symbol, MODE_ASK);
   double bid  = MarketInfo(_Symbol, MODE_BID);
   double minD = MinStopDistance();

   bool valid = true;
   if(dir > 0)
   {
      if(InpEntryMode == AX_ENTRY_LIMIT) { if(refEntry > ask - minD) valid = false; }
      else                               { if(refEntry < ask + minD) valid = false; }
   }
   else
   {
      if(InpEntryMode == AX_ENTRY_LIMIT) { if(refEntry < bid + minD) valid = false; }
      else                               { if(refEntry > bid - minD) valid = false; }
   }

   if(!valid)
   {
      if(!InpPendingFallbackMkt)
      {
         LogMsg("Signal skipped: level invalid for a pending order and the market fallback is disabled");
         return;
      }
      LogMsg("Level too close to the market for a pending order - market entry instead");
      if(PineActivationCancel(dir, refEntry)) return;

      int tk = 0;
      if(!SendMarketOrder(dir, lots, slRef, orderTP, cmt, tk)) return;
      g_tradesToday++;
      SaveTradeState(tk, riskDist, rr, tp1Ref, tp2Ref, 0);
      AdoptPosition(tk);
      return;
   }

   int ticket = 0;
   if(!SendPendingOrder(dir, InpEntryMode, lots, refEntry, slRef, orderTP, cmt, ticket))
      return;

   g_pendingBarTime = iTime(_Symbol, _Period, 0);
   g_tradesToday++;
   SaveTradeState(ticket, riskDist, rr, tp1Ref, tp2Ref, 0);
   LogMsg("Pending #" + IntegerToString(ticket) + " placed at " + DoubleToString(refEntry, Digits) +
          " (valid " + IntegerToString(InpPendingExpiryBars) + " bar(s))");
}

//+------------------------------------------------------------------+
//| Signal evaluation, once per new bar (on the closed bar)           |
//+------------------------------------------------------------------+
void OnNewBarUpdate()
{
   //--- adopt a position opened while the EA was offline ----------------
   if(g_ticket <= 0)
   {
      int pos = FindMyPosition();
      if(pos > 0) AdoptPosition(pos);
   }

   //--- account safety state (refreshed once per day) --------------------
   UpdateDailyState();

   //--- only one position / pending order at a time ----------------------
   if(HasPositionOrPending()) return;

   //--- account level guards (they listen to no filter) ------------------
   if(!SafetyAllowsTrading()) return;

   if(!SpreadOK())
   {
      LogMsg("Signal check skipped: spread above the limit");
      return;
   }

   if(!ComputeIndicators(g_ind)) return;

   //--- cost / regime gates (research based) ------------------------------
   if(InpUseCostFilters)
   {
      //--- the trade must be big enough for the spread not to eat the edge
      if(InpMinATR > 0.0 && g_ind.atr < InpMinATR)
      {
         LogMsg("Signal check skipped: ATR " + DoubleToString(g_ind.atr, Digits) +
                " below the minimum " + DoubleToString(InpMinATR, Digits));
         return;
      }
      if(g_ind.adxLevel < (int)InpMinADXRegime)
      {
         LogMsg("Signal check skipped: ADX regime " + g_ind.adxLevelName +
                " below the required minimum");
         return;
      }
   }

   BuildScores(g_ind);

   //--- strong signal handling -------------------------------------------
   if(InpStrongMode == AX_STRONG_ONLY)
   {
      if(g_ind.buyScore  < g_ind.strongThresh) g_ind.rawBuy  = false;
      if(g_ind.sellScore < g_ind.strongThresh) g_ind.rawSell = false;
   }

   //--- cooldown (Pine: barsSinceSignal >= effectiveCooldown) -------------
   int barsSinceSignal = 999;
   if(g_lastSignalBarTime > 0)
   {
      barsSinceSignal = iBarShift(_Symbol, _Period, g_lastSignalBarTime);
      if(barsSinceSignal < 0) barsSinceSignal = 999;
   }
   double consolCDFactor  = g_ind.consol ? InpConsolCDMultiplier : 1.0;
   int    effectiveCooldown = (int)MathRound((double)InpCooldownBars * consolCDFactor);
   bool   cooldownOK = (!InpEnableCooldown) || (barsSinceSignal >= effectiveCooldown);

   //--- one signal per move ------------------------------------------------
   bool newBuyMove  = (g_lastDir != 1);
   bool newSellMove = (g_lastDir != -1);

   //--- session -------------------------------------------------------------
   bool inSession = InTradingSession();

   //--- re-entry handling (per direction) ------------------------------------
   bool allowBuyReEntry  = true;
   bool allowSellReEntry = true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(InpReEntryMode == AX_REENTRY_BLOCK_SAME_DIR)
   {
      if(g_blockedDir > 0) allowBuyReEntry  = false;
      if(g_blockedDir < 0) allowSellReEntry = false;
   }
   else if(InpReEntryMode == AX_REENTRY_BLOCK_SAME_DAY)
   {
      if(g_blockedDay == dt.day_of_year)
      {
         if(g_blockedDir > 0) allowBuyReEntry  = false;
         if(g_blockedDir < 0) allowSellReEntry = false;
      }
   }

   //--- final signal expression (mirrors the original) -----------------------
   bool buySignal  = g_ind.rawBuy  && cooldownOK && ((!InpOneSignalPerMove) || newBuyMove)  && allowBuyReEntry  && inSession;
   bool sellSignal = g_ind.rawSell && cooldownOK && ((!InpOneSignalPerMove) || newSellMove) && allowSellReEntry && inSession;

   //--- RSI 'require levels' mode --------------------------------------------
   if(InpRSIMode == AX_RSI_REQUIRE_LEVELS)
   {
      if(!(g_ind.rsi > InpRSIBuy))  buySignal  = false;
      if(!(g_ind.rsi < InpRSISell)) sellSignal = false;
   }

   //--- hard filters of the extra / unused blocks ------------------------------
   if(buySignal  && ExtraFilterBlocked(g_ind, true))  buySignal  = false;
   if(sellSignal && ExtraFilterBlocked(g_ind, false)) sellSignal = false;

   if(!buySignal && !sellSignal) return;

   //--- both sides firing (rare): take the stronger score ------------------------
   int dir;
   if(buySignal && sellSignal) dir = (g_ind.buyScore >= g_ind.sellScore) ? 1 : -1;
   else if(buySignal)          dir = 1;
   else                        dir = -1;

   //--- clear the blocked direction when the opposite signal appears --------------
   if(InpReEntryMode == AX_REENTRY_BLOCK_SAME_DIR && g_blockedDir != 0 && g_blockedDir != dir)
      g_blockedDir = 0;

   double refEntry = ReferenceEntryPrice(dir);
   ExecuteSignal(dir, refEntry);
}

//+------------------------------------------------------------------+
//| Init / Deinit                                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   g_lastBarTime = iTime(_Symbol, _Period, 0);

   if(InpADXWeakThresh >= InpADXStrongThresh)
      Print("[AlgoX] WARNING: ADX weak threshold >= strong threshold, the Medium band will never be used.");
   if(InpEntryPercent < 5 || InpEntryPercent > 95)
      Print("[AlgoX] WARNING: Entry candle percentage should stay between 5 and 95.");
   if(InpUsePineCancelRule && StringFind(_Symbol, "XAU") < 0)
      Print("[AlgoX] WARNING: the original 0.50 activation window is gold specific - disable it on other symbols.");
   if(InpUseSessionFilter && !InpUseManualGMTOffset)
      Print("[AlgoX] NOTE: the session filter uses TimeGMT(). In the strategy tester use the manual GMT offset.");
   if(InpSizingMode == AX_SIZING_PINE_FIXED)
      Print("[AlgoX] NOTE: PINE_FIXED sizing uses the fixed balance of " +
            DoubleToString(InpPineBalance, 2) + " account currency.");
   if(InpUseCostFilters)
   {
      Print("[AlgoX] COST GATES ON | spread assumption=", IntegerToString(InpFixedSpreadPoints),
            " points | min ATR=", DoubleToString(InpMinATR, Digits),
            " | min ADX regime=", IntegerToString((int)InpMinADXRegime),
            " | SL>=", DoubleToString(InpMinSLSpreadMult, 1), "x spread",
            " | TP>=", DoubleToString(InpMinTargetSpreadMult, 1), "x spread",
            InpSkipTP1IfUneconomic ? " | skip TP1" : "");
      if(InpFixedSpreadPoints == 47)
         Print("[AlgoX] NOTE: the 47 point spread is the research assumption for XAUUSD M1 " +
               "(0.47 USD on a 2 digit quote).");
   }
   //--- contract size / sizing sanity (the broker contract is not the
   //--- indicator's assumed lot value - this is what blew up the first round)
   double perUnit = AccountPerUnit();
   Print("[AlgoX] Contract check | 1.0 price move per lot = ", DoubleToString(perUnit, 2), " ",
         AccountCurrency(), " | tick value=", DoubleToString(MarketInfo(_Symbol, MODE_TICKVALUE), 2),
         " tick size=", DoubleToString(MarketInfo(_Symbol, MODE_TICKSIZE), Digits),
         " | min lot=", DoubleToString(MarketInfo(_Symbol, MODE_MINLOT), 2),
         " step=", DoubleToString(MarketInfo(_Symbol, MODE_LOTSTEP), 2),
         " | margin per lot=", DoubleToString(MarketInfo(_Symbol, MODE_MARGINREQUIRED), 2));
   if(InpSizingMode == AX_SIZING_PINE_FIXED || InpSizingMode == AX_SIZING_MANUAL_VALUE)
      Print("[AlgoX] WARNING: fixed sizing uses the manual value " +
            DoubleToString(InpPineLotValue, 2) + " and the fixed balance " +
            DoubleToString(InpPineBalance, 2) + ", while the broker's real value is " +
            DoubleToString(perUnit, 2) + " per 1.0 move per lot. The effective risk can be " +
            "several times larger than intended - use AX_SIZING_BROKER on a live account.");
   else
      Print("[AlgoX] Sizing: " + DoubleToString(InpRiskPercent, 2) +
            "% of the real balance per trade | margin cap " +
            DoubleToString(InpMaxMarginPercent, 1) + "% of equity | risk cap " +
            DoubleToString(InpRiskPercentCap, 2) + "%");

   if(InpExitMode == AX_EXIT_TP2_BE)
      Print("[AlgoX] NOTE: AX_EXIT_TP2_BE closes the whole position at TP2 and moves the stop " +
            "to break-even once the TP1 distance is reached.");

   Print("[AlgoX] SuperTrend Pro EA initialized | ", _Symbol, " TF=", IntegerToString(_Period),
         " | magic=", IntegerToString(InpMagicNumber),
         " | entry=", IntegerToString((int)InpEntryMode),
         " | exit=", IntegerToString((int)InpExitMode));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(InpDeletePendingsOnExit)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderSymbol() != _Symbol) continue;
         if(OrderMagicNumber() != InpMagicNumber) continue;
         if(OrderType() > OP_SELL)
         {
            int tk = OrderTicket();
            if(OrderDelete(tk, clrGray)) DeleteTradeState(tk);
         }
      }
   }
   Print("[AlgoX] Deinitialized, reason=", IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| Main tick handler                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 1) pending orders: fill detection / manual expiry ---------------
   ManagePendingOrders();

   //--- 2) open position: TP1 partial, break-even, trailing --------------
   ManageOpenPosition();

   //--- 3) new bar => signal evaluation ----------------------------------
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime != g_lastBarTime)
   {
      g_lastBarTime = barTime;

      //--- optional SuperTrend flip alert (evaluated once per bar) -------
      if(InpSTAlertOnFlip)
      {
         static datetime lastFlipAlertBar = 0;
         bool upNow = true, upPrev = true;
         if(ComputeSuperTrend(1, upNow) && ComputeSuperTrend(2, upPrev))
         {
            if(upNow != upPrev && lastFlipAlertBar != barTime)
            {
               lastFlipAlertBar = barTime;
               Alert("AlgoX SuperTrend flip: ", (upNow ? "UP" : "DOWN"));
            }
         }
      }

      OnNewBarUpdate();
   }
}
//+------------------------------------------------------------------+
