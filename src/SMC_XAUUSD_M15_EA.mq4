//+------------------------------------------------------------------+
//| SMC_XAUUSD_M15_EA.mq4                                           |
//| Standalone MT4 companion for SMC_XAUUSD_M15_Strategy.pine       |
//|                                                                  |
//| Mechanical sequence:                                             |
//| H1/H4 bias -> M15 liquidity sweep -> confirmed M15 MSS -> FVG   |
//| -> first consequent-encroachment retest.                         |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "XAUUSD M15 SMC sweep-MSS-FVG expert advisor"
#property description "Use a demo account and broker-specific testing before live use."

// --- Symbol and execution ----------------------------------------------------
// Leave empty to trade the chart/tester symbol. Set a value only when the EA
// must deliberately trade a different broker symbol, e.g. XAUUSDm or GOLD.
input string            InpSymbol                    = "";
input ENUM_TIMEFRAMES   InpSignalTimeframe           = PERIOD_M15;
input int               InpMagicNumber               = 260115;
input string            InpOrderComment              = "SMC XAU M15";
input int               InpSlippagePoints            = 50;
input double            InpMaxSpreadPrice            = 0.80;
input bool              InpOnePositionPerSymbol      = true;

// --- Risk and exits ----------------------------------------------------------
input double            InpRiskPercent               = 1.00;
input double            InpRewardRisk                = 2.00;
input double            InpBreakEvenAtR              = 1.00;
input double            InpBreakEvenLockR            = 0.00;

// --- Time filter (disabled by default because all-day trading was selected) --
input bool              InpUseSessionFilter          = false;
input int               InpSessionStartServerHour    = 0;
input int               InpSessionEndServerHour      = 23;
input bool              InpAvoidFridayClose          = false;
input int               InpFridayCutoffServerHour    = 20;

// --- H1/H4 directional bias --------------------------------------------------
input ENUM_TIMEFRAMES   InpH1Timeframe               = PERIOD_H1;
input ENUM_TIMEFRAMES   InpH4Timeframe               = PERIOD_H4;
input int               InpHTFFastEMA                = 50;
input int               InpHTFSlowEMA                = 200;

// --- M15 trend and regime filters -------------------------------------------
input int               InpM15EMALength              = 200;
input int               InpRangePeriod               = 14;
input int               InpRangeSmoothPeriod         = 21;
input double            InpRangeMultiplier           = 1.30;
input int               InpRangeHistoryBars          = 600;
input int               InpChoppinessLength          = 14;
input double            InpMaximumChoppiness         = 58.0;

// --- Sweep and MSS -----------------------------------------------------------
input int               InpATRPeriod                 = 14;
input int               InpLiquidityLookback         = 12;
input double            InpMinimumSweepATR           = 0.10;
input int               InpSwingLength               = 5;
input int               InpSweepToMssBars            = 8;
input int               InpStateHistoryBars          = 500;

// --- FVG and POI -------------------------------------------------------------
input double            InpMinimumFvgATR             = 0.20;
input int               InpMssToFvgBars              = 3;
input int               InpFvgMaxAgeBars             = 12;
input bool              InpRequireOrderBlockOverlap  = false;
input int               InpOrderBlockLookback        = 12;
input bool              InpUseOrderBlockWicks        = false;

// --- Stop validation ---------------------------------------------------------
input double            InpStopBufferATR             = 0.10;
input double            InpMinimumStopATR            = 0.50;
input double            InpMaximumStopATR            = 3.00;

// --- Internal state ----------------------------------------------------------
struct SMCState {
  bool   hasLastSwingHigh;
  bool   hasLastSwingLow;
  double lastSwingHigh;
  double lastSwingLow;

  int    bullSweepStep;
  int    bearSweepStep;
  double bullSweepLow;
  double bearSweepHigh;

  int    bullMssStep;
  int    bearMssStep;
  double bullMssSweepLow;
  double bearMssSweepHigh;
  double bullObLow;
  double bullObHigh;
  double bearObLow;
  double bearObHigh;
  bool   hasBullOrderBlock;
  bool   hasBearOrderBlock;

  bool   bullFvgActive;
  bool   bearFvgActive;
  int    bullFvgStep;
  int    bearFvgStep;
  double bullFvgLow;
  double bullFvgHigh;
  double bullFvgMid;
  double bearFvgLow;
  double bearFvgHigh;
  double bearFvgMid;
  double bullFvgSweepLow;
  double bearFvgSweepHigh;
  bool   bullFvgObOK;
  bool   bearFvgObOK;
};

struct SignalResult {
  int      direction;       // 1 = buy, -1 = sell, 0 = no action
  double   rawStop;
  double   atr;
  datetime signalBarTime;
};

string   g_symbol = "";
datetime g_lastSignalBar = 0;
int      g_digits = 0;
double   g_point = 0.0;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() {
  if (InpRiskPercent <= 0.0 || InpRewardRisk < 1.0 || InpATRPeriod < 1 ||
      InpLiquidityLookback < 3 || InpSwingLength < 2 ||
      InpRangePeriod < 1 || InpRangeSmoothPeriod < 1) {
    Print("Invalid EA input values. Check risk and period inputs.");
    return(INIT_PARAMETERS_INCORRECT);
  }

  // Strategy Tester can reject SymbolSelect() for the tester's own symbol,
  // even though its quotes/history are already available. Use the chart symbol
  // directly unless the user explicitly requests a different symbol.
  g_symbol = StringLen(InpSymbol) == 0 ? Symbol() : InpSymbol;
  if (g_symbol != Symbol() && !SymbolSelect(g_symbol, true)) {
    Print("Unable to select requested symbol ", g_symbol,
          ". Leave InpSymbol empty to use the tester/chart symbol, or use the broker's exact symbol name.");
    return(INIT_FAILED);
  }

  g_digits = (int)MarketInfo(g_symbol, MODE_DIGITS);
  g_point = MarketInfo(g_symbol, MODE_POINT);
  if (g_point <= 0.0) {
    Print("Invalid point value for ", g_symbol);
    return(INIT_FAILED);
  }

  if (InpSignalTimeframe != PERIOD_M15) {
    Print("Warning: this EA is designed and calibrated for M15. Current signal timeframe: ", InpSignalTimeframe);
  }

  g_lastSignalBar = iTime(g_symbol, InpSignalTimeframe, 0);
  Print("SMC XAU M15 EA initialized for ", g_symbol, ". Waiting for the next closed M15 candle.");
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
  Print("SMC XAU M15 EA stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Main event                                                       |
//+------------------------------------------------------------------+
void OnTick() {
  ManageOpenPositions();

  if (!IsNewSignalBar()) {
    return;
  }

  if (!CanOpenNewTrades()) {
    return;
  }

  SignalResult signal;
  ResetSignal(signal);
  if (!EvaluateClosedBar(signal) || signal.direction == 0) {
    return;
  }

  OpenSignalTrade(signal);
}

//+------------------------------------------------------------------+
//| New-bar detection                                                |
//+------------------------------------------------------------------+
bool IsNewSignalBar() {
  datetime currentBar = iTime(g_symbol, InpSignalTimeframe, 0);
  if (currentBar <= 0) {
    return(false);
  }

  if (g_lastSignalBar == 0) {
    g_lastSignalBar = currentBar;
    return(false);
  }

  if (currentBar != g_lastSignalBar) {
    g_lastSignalBar = currentBar;
    return(true);
  }
  return(false);
}

//+------------------------------------------------------------------+
//| Trading permissions                                              |
//+------------------------------------------------------------------+
bool CanOpenNewTrades() {
  if (!IsTradeAllowed()) {
    Print("Trade context is unavailable; no new entry.");
    return(false);
  }

  if (InpOnePositionPerSymbol && HasOpenPosition()) {
    return(false);
  }

  double spread = MarketInfo(g_symbol, MODE_ASK) - MarketInfo(g_symbol, MODE_BID);
  if (InpMaxSpreadPrice > 0.0 && spread > InpMaxSpreadPrice) {
    Print("Spread filter blocked entry. Spread=", DoubleToString(spread, g_digits), " max=", DoubleToString(InpMaxSpreadPrice, g_digits));
    return(false);
  }

  if (!IsWithinTradingWindow()) {
    return(false);
  }

  return(true);
}

//+------------------------------------------------------------------+
bool IsWithinTradingWindow() {
  datetime serverTime = TimeCurrent();
  int serverHour = TimeHour(serverTime);

  if (InpAvoidFridayClose && TimeDayOfWeek(serverTime) == 5 && serverHour >= InpFridayCutoffServerHour) {
    return(false);
  }

  if (!InpUseSessionFilter) {
    return(true);
  }

  int startHour = InpSessionStartServerHour;
  int endHour = InpSessionEndServerHour;
  if (startHour == endHour) {
    return(true);
  }
  if (startHour < endHour) {
    return(serverHour >= startHour && serverHour < endHour);
  }
  // Overnight session, e.g. 22 -> 06.
  return(serverHour >= startHour || serverHour < endHour);
}

//+------------------------------------------------------------------+
//| Scan closed M15 history and evaluate the current completed bar. |
//| This makes attaching/restarting the EA deterministic: it rebuilds|
//| sweep/MSS/FVG state from history rather than waiting for a new    |
//| sweep after every restart.                                       |
//+------------------------------------------------------------------+
bool EvaluateClosedBar(SignalResult &result) {
  ResetSignal(result);

  int bars = iBars(g_symbol, InpSignalTimeframe);
  int structuralRequirement = MathMax(InpLiquidityLookback, InpSwingLength * 2) + 10;
  int startShift = MathMin(InpStateHistoryBars, bars - structuralRequirement);
  if (startShift <= 3) {
    Print("Not enough ", g_symbol, " M15 history for SMC scan.");
    return(false);
  }

  int rangeDirection = GetRangeDirection();
  if (rangeDirection == 0) {
    return(false);
  }

  SMCState state;
  ResetState(state);

  int step = 0;
  for (int shift = startShift; shift >= 1; shift--) {
    step++;
    double openPrice = iOpen(g_symbol, InpSignalTimeframe, shift);
    double highPrice = iHigh(g_symbol, InpSignalTimeframe, shift);
    double lowPrice = iLow(g_symbol, InpSignalTimeframe, shift);
    double closePrice = iClose(g_symbol, InpSignalTimeframe, shift);
    double atr = iATR(g_symbol, InpSignalTimeframe, InpATRPeriod, shift);
    if (atr <= 0.0 || openPrice == 0.0 || closePrice == 0.0) {
      continue;
    }

    ExpireState(state, step);
    UpdateConfirmedSwings(state, shift, bars);

    double priorLow = LowestLowBefore(shift, InpLiquidityLookback, bars);
    double priorHigh = HighestHighBefore(shift, InpLiquidityLookback, bars);
    bool bullSweep = priorLow > 0.0 && lowPrice < priorLow - atr * InpMinimumSweepATR && closePrice > priorLow && closePrice > openPrice;
    bool bearSweep = priorHigh > 0.0 && highPrice > priorHigh + atr * InpMinimumSweepATR && closePrice < priorHigh && closePrice < openPrice;

    if (bullSweep) {
      state.bullSweepStep = step;
      state.bullSweepLow = lowPrice;
    }
    if (bearSweep) {
      state.bearSweepStep = step;
      state.bearSweepHigh = highPrice;
    }

    bool bullMss = state.bullSweepStep >= 0 && step > state.bullSweepStep &&
                   step - state.bullSweepStep <= InpSweepToMssBars && state.hasLastSwingHigh &&
                   closePrice > state.lastSwingHigh && iClose(g_symbol, InpSignalTimeframe, shift + 1) <= state.lastSwingHigh;
    bool bearMss = state.bearSweepStep >= 0 && step > state.bearSweepStep &&
                   step - state.bearSweepStep <= InpSweepToMssBars && state.hasLastSwingLow &&
                   closePrice < state.lastSwingLow && iClose(g_symbol, InpSignalTimeframe, shift + 1) >= state.lastSwingLow;

    if (bullMss) {
      state.bullMssStep = step;
      state.bullMssSweepLow = state.bullSweepLow;
      state.hasBullOrderBlock = FindOppositeOrderBlock(shift + 1, true, state.bullObLow, state.bullObHigh);
    }
    if (bearMss) {
      state.bearMssStep = step;
      state.bearMssSweepHigh = state.bearSweepHigh;
      state.hasBearOrderBlock = FindOppositeOrderBlock(shift + 1, false, state.bearObLow, state.bearObHigh);
    }

    double highTwoBarsBack = iHigh(g_symbol, InpSignalTimeframe, shift + 2);
    double lowTwoBarsBack = iLow(g_symbol, InpSignalTimeframe, shift + 2);
    bool bullFvgNew = state.bullMssStep >= 0 && step - state.bullMssStep <= InpMssToFvgBars &&
                      lowPrice > highTwoBarsBack && lowPrice - highTwoBarsBack >= atr * InpMinimumFvgATR;
    bool bearFvgNew = state.bearMssStep >= 0 && step - state.bearMssStep <= InpMssToFvgBars &&
                      highPrice < lowTwoBarsBack && lowTwoBarsBack - highPrice >= atr * InpMinimumFvgATR;

    if (bullFvgNew) {
      state.bullFvgActive = true;
      state.bullFvgStep = step;
      state.bullFvgLow = highTwoBarsBack;
      state.bullFvgHigh = lowPrice;
      state.bullFvgMid = (state.bullFvgLow + state.bullFvgHigh) / 2.0;
      state.bullFvgSweepLow = state.bullMssSweepLow;
      state.bullFvgObOK = !InpRequireOrderBlockOverlap ||
                           (state.hasBullOrderBlock && ZonesOverlap(state.bullFvgLow, state.bullFvgHigh, state.bullObLow, state.bullObHigh));
      // Only the first FVG after the MSS is the POI for this setup.
      state.bullMssStep = -1;
      state.bullMssSweepLow = 0.0;
    }
    if (bearFvgNew) {
      state.bearFvgActive = true;
      state.bearFvgStep = step;
      state.bearFvgLow = highPrice;
      state.bearFvgHigh = lowTwoBarsBack;
      state.bearFvgMid = (state.bearFvgLow + state.bearFvgHigh) / 2.0;
      state.bearFvgSweepHigh = state.bearMssSweepHigh;
      state.bearFvgObOK = !InpRequireOrderBlockOverlap ||
                           (state.hasBearOrderBlock && ZonesOverlap(state.bearFvgLow, state.bearFvgHigh, state.bearObLow, state.bearObHigh));
      state.bearMssStep = -1;
      state.bearMssSweepHigh = 0.0;
    }

    bool bullExpired = state.bullFvgActive && step - state.bullFvgStep > InpFvgMaxAgeBars;
    bool bearExpired = state.bearFvgActive && step - state.bearFvgStep > InpFvgMaxAgeBars;
    bool bullInvalidated = state.bullFvgActive && lowPrice <= state.bullFvgLow;
    bool bearInvalidated = state.bearFvgActive && highPrice >= state.bearFvgHigh;
    bool bullRetest = state.bullFvgActive && step > state.bullFvgStep &&
                      step - state.bullFvgStep <= InpFvgMaxAgeBars && !bullInvalidated &&
                      lowPrice <= state.bullFvgMid && closePrice > state.bullFvgMid && closePrice > openPrice;
    bool bearRetest = state.bearFvgActive && step > state.bearFvgStep &&
                      step - state.bearFvgStep <= InpFvgMaxAgeBars && !bearInvalidated &&
                      highPrice >= state.bearFvgMid && closePrice < state.bearFvgMid && closePrice < openPrice;

    // Only evaluate entries on the newest completed M15 candle (shift 1).
    if (shift == 1) {
      bool htfBull = HasHigherTimeframeBias(true, iTime(g_symbol, InpSignalTimeframe, shift));
      bool htfBear = HasHigherTimeframeBias(false, iTime(g_symbol, InpSignalTimeframe, shift));
      double m15Ema = iMA(g_symbol, InpSignalTimeframe, InpM15EMALength, 0, MODE_EMA, PRICE_CLOSE, shift);
      double chop = ChoppinessAt(shift, bars);
      bool regimeOK = chop >= 0.0 && chop < InpMaximumChoppiness;

      bool longStopValid = state.bullFvgSweepLow > 0.0;
      bool shortStopValid = state.bearFvgSweepHigh > 0.0;
      double longRisk = longStopValid ? closePrice - (state.bullFvgSweepLow - atr * InpStopBufferATR) : 0.0;
      double shortRisk = shortStopValid ? (state.bearFvgSweepHigh + atr * InpStopBufferATR) - closePrice : 0.0;
      if (longStopValid) {
        // Tight stops are expanded to the minimum ATR distance at execution,
        // matching the Pine strategy. Wide stops are rejected here.
        longStopValid = longRisk > 0.0 && longRisk <= atr * InpMaximumStopATR;
      }
      if (shortStopValid) {
        shortStopValid = shortRisk > 0.0 && shortRisk <= atr * InpMaximumStopATR;
      }

      bool longSetup = htfBull && closePrice > m15Ema && rangeDirection == 1 && regimeOK &&
                       state.bullFvgObOK && bullRetest && longStopValid;
      bool shortSetup = htfBear && closePrice < m15Ema && rangeDirection == -1 && regimeOK &&
                        state.bearFvgObOK && bearRetest && shortStopValid;

      // Never send two opposing orders from a single closed candle.
      if (longSetup && !shortSetup) {
        result.direction = 1;
        result.rawStop = state.bullFvgSweepLow - atr * InpStopBufferATR;
        result.atr = atr;
        result.signalBarTime = iTime(g_symbol, InpSignalTimeframe, shift);
      } else if (shortSetup && !longSetup) {
        result.direction = -1;
        result.rawStop = state.bearFvgSweepHigh + atr * InpStopBufferATR;
        result.atr = atr;
        result.signalBarTime = iTime(g_symbol, InpSignalTimeframe, shift);
      }
    }

    // A first CE retest consumes the POI even when an EMA, range or regime
    // filter rejects that candle. A full fill and expiry invalidate it too.
    if (bullExpired || bullInvalidated || bullRetest) {
      ClearBullFvg(state);
    }
    if (bearExpired || bearInvalidated || bearRetest) {
      ClearBearFvg(state);
    }
  }

  return(result.direction != 0);
}

//+------------------------------------------------------------------+
//| State initialization and lifecycle                               |
//+------------------------------------------------------------------+
void ResetState(SMCState &state) {
  state.hasLastSwingHigh = false;
  state.hasLastSwingLow = false;
  state.lastSwingHigh = 0.0;
  state.lastSwingLow = 0.0;

  state.bullSweepStep = -1;
  state.bearSweepStep = -1;
  state.bullSweepLow = 0.0;
  state.bearSweepHigh = 0.0;

  state.bullMssStep = -1;
  state.bearMssStep = -1;
  state.bullMssSweepLow = 0.0;
  state.bearMssSweepHigh = 0.0;
  state.bullObLow = 0.0;
  state.bullObHigh = 0.0;
  state.bearObLow = 0.0;
  state.bearObHigh = 0.0;
  state.hasBullOrderBlock = false;
  state.hasBearOrderBlock = false;

  state.bullFvgActive = false;
  state.bearFvgActive = false;
  state.bullFvgStep = -1;
  state.bearFvgStep = -1;
  state.bullFvgLow = 0.0;
  state.bullFvgHigh = 0.0;
  state.bullFvgMid = 0.0;
  state.bearFvgLow = 0.0;
  state.bearFvgHigh = 0.0;
  state.bearFvgMid = 0.0;
  state.bullFvgSweepLow = 0.0;
  state.bearFvgSweepHigh = 0.0;
  state.bullFvgObOK = false;
  state.bearFvgObOK = false;
}

//+------------------------------------------------------------------+
void ResetSignal(SignalResult &result) {
  result.direction = 0;
  result.rawStop = 0.0;
  result.atr = 0.0;
  result.signalBarTime = 0;
}

//+------------------------------------------------------------------+
void ExpireState(SMCState &state, int step) {
  if (state.bullSweepStep >= 0 && step - state.bullSweepStep > InpSweepToMssBars) {
    state.bullSweepStep = -1;
    state.bullSweepLow = 0.0;
  }
  if (state.bearSweepStep >= 0 && step - state.bearSweepStep > InpSweepToMssBars) {
    state.bearSweepStep = -1;
    state.bearSweepHigh = 0.0;
  }
  if (state.bullMssStep >= 0 && step - state.bullMssStep > InpMssToFvgBars) {
    state.bullMssStep = -1;
    state.bullMssSweepLow = 0.0;
  }
  if (state.bearMssStep >= 0 && step - state.bearMssStep > InpMssToFvgBars) {
    state.bearMssStep = -1;
    state.bearMssSweepHigh = 0.0;
  }
}

//+------------------------------------------------------------------+
void ClearBullFvg(SMCState &state) {
  state.bullFvgActive = false;
  state.bullFvgStep = -1;
  state.bullFvgLow = 0.0;
  state.bullFvgHigh = 0.0;
  state.bullFvgMid = 0.0;
  state.bullFvgSweepLow = 0.0;
  state.bullFvgObOK = false;
}

//+------------------------------------------------------------------+
void ClearBearFvg(SMCState &state) {
  state.bearFvgActive = false;
  state.bearFvgStep = -1;
  state.bearFvgLow = 0.0;
  state.bearFvgHigh = 0.0;
  state.bearFvgMid = 0.0;
  state.bearFvgSweepHigh = 0.0;
  state.bearFvgObOK = false;
}

//+------------------------------------------------------------------+
//| Swing, liquidity and POI helpers                                 |
//+------------------------------------------------------------------+
void UpdateConfirmedSwings(SMCState &state, int currentShift, int bars) {
  int candidateShift = currentShift + InpSwingLength;
  if (candidateShift + InpSwingLength >= bars || candidateShift - InpSwingLength < 1) {
    return;
  }

  if (IsPivotHigh(candidateShift)) {
    state.lastSwingHigh = iHigh(g_symbol, InpSignalTimeframe, candidateShift);
    state.hasLastSwingHigh = true;
  }
  if (IsPivotLow(candidateShift)) {
    state.lastSwingLow = iLow(g_symbol, InpSignalTimeframe, candidateShift);
    state.hasLastSwingLow = true;
  }
}

//+------------------------------------------------------------------+
bool IsPivotHigh(int pivotShift) {
  double pivot = iHigh(g_symbol, InpSignalTimeframe, pivotShift);
  if (pivot <= 0.0) {
    return(false);
  }
  for (int i = 1; i <= InpSwingLength; i++) {
    if (iHigh(g_symbol, InpSignalTimeframe, pivotShift - i) >= pivot ||
        iHigh(g_symbol, InpSignalTimeframe, pivotShift + i) >= pivot) {
      return(false);
    }
  }
  return(true);
}

//+------------------------------------------------------------------+
bool IsPivotLow(int pivotShift) {
  double pivot = iLow(g_symbol, InpSignalTimeframe, pivotShift);
  if (pivot <= 0.0) {
    return(false);
  }
  for (int i = 1; i <= InpSwingLength; i++) {
    if (iLow(g_symbol, InpSignalTimeframe, pivotShift - i) <= pivot ||
        iLow(g_symbol, InpSignalTimeframe, pivotShift + i) <= pivot) {
      return(false);
    }
  }
  return(true);
}

//+------------------------------------------------------------------+
double LowestLowBefore(int shift, int lookback, int bars) {
  if (shift + lookback >= bars) {
    return(0.0);
  }
  double result = 1.0e100;
  for (int i = shift + 1; i <= shift + lookback; i++) {
    double value = iLow(g_symbol, InpSignalTimeframe, i);
    if (value < result) {
      result = value;
    }
  }
  return(result == 1.0e100 ? 0.0 : result);
}

//+------------------------------------------------------------------+
double HighestHighBefore(int shift, int lookback, int bars) {
  if (shift + lookback >= bars) {
    return(0.0);
  }
  double result = -1.0e100;
  for (int i = shift + 1; i <= shift + lookback; i++) {
    double value = iHigh(g_symbol, InpSignalTimeframe, i);
    if (value > result) {
      result = value;
    }
  }
  return(result == -1.0e100 ? 0.0 : result);
}

//+------------------------------------------------------------------+
bool FindOppositeOrderBlock(int startShift, bool wantBearishCandle, double &obLow, double &obHigh) {
  int bars = iBars(g_symbol, InpSignalTimeframe);
  obLow = 0.0;
  obHigh = 0.0;
  for (int shift = startShift; shift < startShift + InpOrderBlockLookback && shift < bars; shift++) {
    double openPrice = iOpen(g_symbol, InpSignalTimeframe, shift);
    double closePrice = iClose(g_symbol, InpSignalTimeframe, shift);
    bool match = wantBearishCandle ? closePrice < openPrice : closePrice > openPrice;
    if (!match) {
      continue;
    }

    if (InpUseOrderBlockWicks) {
      obLow = iLow(g_symbol, InpSignalTimeframe, shift);
      obHigh = iHigh(g_symbol, InpSignalTimeframe, shift);
    } else if (wantBearishCandle) {
      obLow = closePrice;
      obHigh = openPrice;
    } else {
      obLow = openPrice;
      obHigh = closePrice;
    }
    return(obHigh > obLow);
  }
  return(false);
}

//+------------------------------------------------------------------+
bool ZonesOverlap(double lowA, double highA, double lowB, double highB) {
  return(lowA <= highA && lowB <= highB && MathMax(lowA, lowB) <= MathMin(highA, highB));
}

//+------------------------------------------------------------------+
//| Filters                                                          |
//+------------------------------------------------------------------+
int GetRangeDirection() {
  int bars = iBars(g_symbol, InpSignalTimeframe);
  int minimumBars = MathMax(InpRangePeriod, InpRangeSmoothPeriod) * 5 + 10;
  int startShift = MathMin(InpRangeHistoryBars, bars - 2);
  if (startShift < minimumBars) {
    return(0);
  }

  double alphaRange = 2.0 / (InpRangePeriod + 1.0);
  double alphaSmooth = 2.0 / (InpRangeSmoothPeriod + 1.0);
  bool initialized = false;
  double trEma = 0.0;
  double smoothRange = 0.0;
  double rangeFilter = 0.0;
  int direction = 0;

  for (int shift = startShift; shift >= 1; shift--) {
    double highPrice = iHigh(g_symbol, InpSignalTimeframe, shift);
    double lowPrice = iLow(g_symbol, InpSignalTimeframe, shift);
    double previousClose = iClose(g_symbol, InpSignalTimeframe, shift + 1);
    double closePrice = iClose(g_symbol, InpSignalTimeframe, shift);
    double trueRange = MathMax(highPrice - lowPrice, MathMax(MathAbs(highPrice - previousClose), MathAbs(lowPrice - previousClose)));

    if (!initialized) {
      trEma = trueRange;
      smoothRange = trueRange;
      rangeFilter = closePrice;
      initialized = true;
      continue;
    }

    trEma += alphaRange * (trueRange - trEma);
    smoothRange += alphaSmooth * (trEma - smoothRange);
    double filterDistance = smoothRange * InpRangeMultiplier;
    double previousFilter = rangeFilter;
    if (closePrice - filterDistance > previousFilter) {
      rangeFilter = closePrice - filterDistance;
    } else if (closePrice + filterDistance < previousFilter) {
      rangeFilter = closePrice + filterDistance;
    }

    if (rangeFilter > previousFilter) {
      direction = 1;
    } else if (rangeFilter < previousFilter) {
      direction = -1;
    }
  }
  return(direction);
}

//+------------------------------------------------------------------+
double ChoppinessAt(int shift, int bars) {
  if (shift + InpChoppinessLength >= bars) {
    return(-1.0);
  }

  double sumTrueRange = 0.0;
  double highest = -1.0e100;
  double lowest = 1.0e100;
  for (int i = shift; i < shift + InpChoppinessLength; i++) {
    double highPrice = iHigh(g_symbol, InpSignalTimeframe, i);
    double lowPrice = iLow(g_symbol, InpSignalTimeframe, i);
    double previousClose = iClose(g_symbol, InpSignalTimeframe, i + 1);
    double trueRange = MathMax(highPrice - lowPrice, MathMax(MathAbs(highPrice - previousClose), MathAbs(lowPrice - previousClose)));
    sumTrueRange += trueRange;
    if (highPrice > highest) {
      highest = highPrice;
    }
    if (lowPrice < lowest) {
      lowest = lowPrice;
    }
  }

  double priceRange = highest - lowest;
  if (sumTrueRange <= 0.0 || priceRange <= 0.0 || InpChoppinessLength <= 1) {
    return(-1.0);
  }
  return(100.0 * MathLog10(sumTrueRange / priceRange) / MathLog10(InpChoppinessLength));
}

//+------------------------------------------------------------------+
//| Last-completed H1/H4 condition. The bar containing signalTime   |
//| is intentionally skipped so intrabar HTF values cannot repaint. |
//+------------------------------------------------------------------+
bool HasHigherTimeframeBias(bool wantBull, datetime signalTime) {
  int h1ContainingShift = iBarShift(g_symbol, InpH1Timeframe, signalTime, false);
  int h4ContainingShift = iBarShift(g_symbol, InpH4Timeframe, signalTime, false);
  if (h1ContainingShift < 0 || h4ContainingShift < 0) {
    return(false);
  }

  int h1Shift = h1ContainingShift + 1;
  int h4Shift = h4ContainingShift + 1;
  if (iBars(g_symbol, InpH1Timeframe) <= h1Shift || iBars(g_symbol, InpH4Timeframe) <= h4Shift) {
    return(false);
  }

  double h1Close = iClose(g_symbol, InpH1Timeframe, h1Shift);
  double h1Fast = iMA(g_symbol, InpH1Timeframe, InpHTFFastEMA, 0, MODE_EMA, PRICE_CLOSE, h1Shift);
  double h1Slow = iMA(g_symbol, InpH1Timeframe, InpHTFSlowEMA, 0, MODE_EMA, PRICE_CLOSE, h1Shift);
  double h4Close = iClose(g_symbol, InpH4Timeframe, h4Shift);
  double h4Fast = iMA(g_symbol, InpH4Timeframe, InpHTFFastEMA, 0, MODE_EMA, PRICE_CLOSE, h4Shift);
  double h4Slow = iMA(g_symbol, InpH4Timeframe, InpHTFSlowEMA, 0, MODE_EMA, PRICE_CLOSE, h4Shift);

  if (wantBull) {
    return(h1Close > h1Fast && h1Fast > h1Slow && h4Close > h4Fast && h4Fast > h4Slow);
  }
  return(h1Close < h1Fast && h1Fast < h1Slow && h4Close < h4Fast && h4Fast < h4Slow);
}

//+------------------------------------------------------------------+
//| Order execution                                                  |
//+------------------------------------------------------------------+
void OpenSignalTrade(SignalResult &signal) {
  RefreshRates();
  double bid = MarketInfo(g_symbol, MODE_BID);
  double ask = MarketInfo(g_symbol, MODE_ASK);
  if (bid <= 0.0 || ask <= 0.0 || signal.atr <= 0.0) {
    Print("No valid market price for ", g_symbol);
    return;
  }

  int command = signal.direction > 0 ? OP_BUY : OP_SELL;
  double entryPrice = signal.direction > 0 ? ask : bid;
  double stop = signal.rawStop;

  // Enforce the ATR risk range relative to the actual executable price.
  if (signal.direction > 0) {
    if (entryPrice - stop < signal.atr * InpMinimumStopATR) {
      stop = entryPrice - signal.atr * InpMinimumStopATR;
    }
  } else {
    if (stop - entryPrice < signal.atr * InpMinimumStopATR) {
      stop = entryPrice + signal.atr * InpMinimumStopATR;
    }
  }

  double brokerStopDistance = (MarketInfo(g_symbol, MODE_STOPLEVEL) + 2.0) * g_point;
  if (signal.direction > 0 && entryPrice - stop < brokerStopDistance) {
    stop = entryPrice - brokerStopDistance;
  }
  if (signal.direction < 0 && stop - entryPrice < brokerStopDistance) {
    stop = entryPrice + brokerStopDistance;
  }

  double riskDistance = signal.direction > 0 ? entryPrice - stop : stop - entryPrice;
  if (riskDistance <= 0.0 || riskDistance > signal.atr * InpMaximumStopATR) {
    Print("Stop validation rejected signal. Risk distance=", DoubleToString(riskDistance, g_digits));
    return;
  }

  double takeProfit = signal.direction > 0 ? entryPrice + riskDistance * InpRewardRisk : entryPrice - riskDistance * InpRewardRisk;
  stop = NormalizePrice(stop);
  takeProfit = NormalizePrice(takeProfit);
  entryPrice = NormalizePrice(entryPrice);

  double lots = CalculateLots(riskDistance);
  if (lots <= 0.0) {
    Print("Risk model produced a lot size below broker minimum; signal skipped.");
    return;
  }

  ResetLastError();
  // ECN-safe workflow: open first, then attach SL/TP with OrderModify.
  int ticket = OrderSend(g_symbol, command, lots, entryPrice, InpSlippagePoints, 0.0, 0.0,
                         InpOrderComment, InpMagicNumber, 0,
                         signal.direction > 0 ? clrLime : clrTomato);
  if (ticket < 0) {
    Print("OrderSend failed. Error=", GetLastError(), " direction=", signal.direction);
    return;
  }

  if (!OrderSelect(ticket, SELECT_BY_TICKET)) {
    Print("Unable to select newly opened ticket ", ticket, ". Closing it for safety.");
    CloseTicketImmediately(ticket);
    return;
  }

  // Recalculate TP from the actual fill price. Slippage can otherwise change
  // the intended 2R multiple even if the requested market price was valid.
  double actualEntry = OrderOpenPrice();
  double actualRisk = signal.direction > 0 ? actualEntry - stop : stop - actualEntry;
  if (actualRisk <= 0.0) {
    Print("Fill price invalidated the protective stop for ticket ", ticket, ". Closing it for safety.");
    CloseTicketImmediately(ticket);
    return;
  }
  takeProfit = signal.direction > 0 ? actualEntry + actualRisk * InpRewardRisk : actualEntry - actualRisk * InpRewardRisk;
  takeProfit = NormalizePrice(takeProfit);

  ResetLastError();
  if (!OrderModify(ticket, actualEntry, stop, takeProfit, 0, clrNONE)) {
    int error = GetLastError();
    Print("OrderModify failed for ticket ", ticket, ". Error=", error, ". Closing unprotected order.");
    CloseTicketImmediately(ticket);
    return;
  }

  GlobalVariableSet(InitialRiskKey(ticket), actualRisk);
  Print("Opened ", signal.direction > 0 ? "BUY" : "SELL", " ticket=", ticket,
        " lots=", DoubleToString(lots, 2), " SL=", DoubleToString(stop, g_digits),
        " TP=", DoubleToString(takeProfit, g_digits), " risk=", DoubleToString(actualRisk, g_digits));
}

//+------------------------------------------------------------------+
double CalculateLots(double riskDistance) {
  double tickSize = MarketInfo(g_symbol, MODE_TICKSIZE);
  double tickValue = MarketInfo(g_symbol, MODE_TICKVALUE);
  if (riskDistance <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0) {
    Print("Cannot calculate risk-based lots. tickSize=", tickSize, " tickValue=", tickValue);
    return(0.0);
  }

  double riskMoney = AccountEquity() * InpRiskPercent / 100.0;
  double lossPerLot = riskDistance / tickSize * tickValue;
  if (lossPerLot <= 0.0) {
    return(0.0);
  }
  return(NormalizeLots(riskMoney / lossPerLot));
}

//+------------------------------------------------------------------+
double NormalizeLots(double lots) {
  double minLot = MarketInfo(g_symbol, MODE_MINLOT);
  double maxLot = MarketInfo(g_symbol, MODE_MAXLOT);
  double lotStep = MarketInfo(g_symbol, MODE_LOTSTEP);
  if (minLot <= 0.0 || maxLot <= 0.0 || lotStep <= 0.0) {
    return(0.0);
  }

  lots = MathMin(lots, maxLot);
  lots = MathFloor(lots / lotStep + 1.0e-8) * lotStep;
  if (lots < minLot) {
    return(0.0);
  }
  int lotDigits = LotDigits(lotStep);
  return(NormalizeDouble(lots, lotDigits));
}

//+------------------------------------------------------------------+
int LotDigits(double lotStep) {
  int digits = 0;
  while (digits < 8 && MathAbs(lotStep - NormalizeDouble(lotStep, digits)) > 1.0e-10) {
    digits++;
  }
  return(digits);
}

//+------------------------------------------------------------------+
double NormalizePrice(double price) {
  return(NormalizeDouble(price, g_digits));
}

//+------------------------------------------------------------------+
void CloseTicketImmediately(int ticket) {
  if (!OrderSelect(ticket, SELECT_BY_TICKET)) {
    return;
  }
  RefreshRates();
  int type = OrderType();
  double closePrice = type == OP_BUY ? MarketInfo(g_symbol, MODE_BID) : MarketInfo(g_symbol, MODE_ASK);
  ResetLastError();
  if (!OrderClose(ticket, OrderLots(), closePrice, InpSlippagePoints, clrNONE)) {
    Print("Emergency OrderClose failed for ticket ", ticket, ". Error=", GetLastError());
  }
}

//+------------------------------------------------------------------+
//| Position management: static 2R TP and BE at 1R.                 |
//+------------------------------------------------------------------+
void ManageOpenPositions() {
  for (int i = OrdersTotal() - 1; i >= 0; i--) {
    if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
      continue;
    }
    if (OrderSymbol() != g_symbol || OrderMagicNumber() != InpMagicNumber) {
      continue;
    }
    int type = OrderType();
    if (type != OP_BUY && type != OP_SELL) {
      continue;
    }

    double initialRisk = GetInitialRisk(OrderTicket());
    if (initialRisk <= 0.0) {
      continue;
    }

    double bid = MarketInfo(g_symbol, MODE_BID);
    double ask = MarketInfo(g_symbol, MODE_ASK);
    bool reachedBreakEven = type == OP_BUY ?
                            bid >= OrderOpenPrice() + initialRisk * InpBreakEvenAtR :
                            ask <= OrderOpenPrice() - initialRisk * InpBreakEvenAtR;
    if (!reachedBreakEven) {
      continue;
    }

    double proposedStop = type == OP_BUY ?
                          OrderOpenPrice() + initialRisk * InpBreakEvenLockR :
                          OrderOpenPrice() - initialRisk * InpBreakEvenLockR;
    proposedStop = NormalizePrice(proposedStop);

    bool improvesStop = type == OP_BUY ?
                        (OrderStopLoss() == 0.0 || proposedStop > OrderStopLoss() + g_point * 0.5) :
                        (OrderStopLoss() == 0.0 || proposedStop < OrderStopLoss() - g_point * 0.5);
    if (!improvesStop) {
      continue;
    }

    double minDistance = (MathMax(MarketInfo(g_symbol, MODE_STOPLEVEL), MarketInfo(g_symbol, MODE_FREEZELEVEL)) + 2.0) * g_point;
    bool farEnough = type == OP_BUY ? bid - proposedStop >= minDistance : proposedStop - ask >= minDistance;
    if (!farEnough) {
      continue;
    }

    ResetLastError();
    if (!OrderModify(OrderTicket(), OrderOpenPrice(), proposedStop, OrderTakeProfit(), 0, clrNONE)) {
      Print("Breakeven modification failed for ticket ", OrderTicket(), ". Error=", GetLastError());
    } else {
      Print("Moved ticket ", OrderTicket(), " to breakeven stop ", DoubleToString(proposedStop, g_digits));
    }
  }
}

//+------------------------------------------------------------------+
bool HasOpenPosition() {
  for (int i = OrdersTotal() - 1; i >= 0; i--) {
    if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
      continue;
    }
    if (OrderSymbol() == g_symbol && OrderMagicNumber() == InpMagicNumber &&
        (OrderType() == OP_BUY || OrderType() == OP_SELL)) {
      return(true);
    }
  }
  return(false);
}

//+------------------------------------------------------------------+
string InitialRiskKey(int ticket) {
  return("SMC_XAU_M15_R_" + IntegerToString(AccountNumber()) + "_" + IntegerToString(ticket));
}

//+------------------------------------------------------------------+
double GetInitialRisk(int ticket) {
  string key = InitialRiskKey(ticket);
  if (GlobalVariableCheck(key)) {
    return(GlobalVariableGet(key));
  }

  // Recovery path after terminal data cleanup/restart. It derives R from TP,
  // which is exact while the configured reward/risk has not been changed.
  if (OrderTakeProfit() > 0.0 && InpRewardRisk > 0.0) {
    return(MathAbs(OrderTakeProfit() - OrderOpenPrice()) / InpRewardRisk);
  }
  return(0.0);
}
//+------------------------------------------------------------------+
