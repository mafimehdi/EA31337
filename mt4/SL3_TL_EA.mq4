//+------------------------------------------------------------------+
//| SL3_TL_EA.mq4                                                     |
//| MT4 Expert Advisor port of "Swing L3 + AMD + VP + SuperTrend"     |
//| Unified SIG Engine (latest Pine v5 achievement):                  |
//|   Path A — Entry Checklist (Direction -> Location -> Score -> RR) |
//|   Path B — Direct REV Setup (Sweep -> TL or D up/down)            |
//| Includes fixes from Backtest #1 analysis:                         |
//|   - True sweep detection (prevents stale L3 $150+ stops)          |
//|   - MaxSlUsd cap for $500 accounts (prevents oversized 0.01 loss) |
//|   - BlockOppositeOpen (prevents simultaneous BUY & SELL hedging)  |
//|   - Optional Break-Even & Trailing on Structural TP trades        |
//+------------------------------------------------------------------+
#property strict
#property version   "2.60"

//==================== INPUTS ====================
input string  s0 = "==== General & Risk ====";
input int     Magic             = 31337;
input int     ServerMinusNY     = 7;      // broker server time minus New York time (hours)
input double  RiskPercent       = 1.0;    // risk per trade (% of equity), 0 = use FixedLot
input double  FixedLot          = 0.01;
input int     MaxOpenTrades     = 3;      // max simultaneous open SIG trades
input bool    BlockOppositeOpen = true;   // do not open opposite trade while a trade is open
input bool    CloseOnOpposite   = false;  // close open trades when an opposite SIG appears
input int     MaxTradesPerDay   = 0;      // new entries per server day (0 = unlimited)
input int     MaxLossStreakDay  = 0;      // stop trading for the day after N consecutive losses (0 = off)
input int     SlippagePts       = 30;
input bool    ShowPanel         = true;
input bool    DrawObjects       = true;   // draw session trendlines & SIG arrows on chart

input string  s1 = "==== Entry Engine & Checklist (⑥ Dashboard) ====";
input int     EngineMode        = 1;      // 1 = Legacy TL + Confluence (Champion), 0 = SIG (Checklist+REV), 2 = Both (Legacy+SIG)
input int     ChkRule           = 0;      // 0 = Score, 1 = 2 of 3, 2 = Any 1, 3 = Pin or TL (classic), 4 = Off (REV only)
input bool    ChkAddRev         = true;   // REV setups also fire SIG (without direction/location check)
input int     ChkWin            = 4;      // location -> trigger window (bars)
input int     ChkMem            = 6;      // trigger memory for 2-of-3 / Any-1 / classic (bars)
input int     ChkTrigFilter     = 0;      // 0 = Pin bar + TL, 1 = Pin bar only, 2 = TL only
input bool    ChkL1Hl           = true;   // fresh L1 HL / LH in SuperTrend direction as location
input bool    ChkStLv           = true;   // SuperTrend line as location
input bool    ChkAmdLv          = true;   // AMD range edges as location
input bool    ChkPinTl          = false;  // pin bar -> TL combo counts as location
input int     ChkPinWin         = 8;      // pin -> TL window (bars)
input double  ChkMinRR          = 1.5;    // Checklist minimum R:R

input string  s2 = "==== Trigger Score Weights (⑥b Trigger score) ====";
input double  ScMin             = 4.0;    // Score: minimum to trigger (default 4.0 / 21)
input int     ScMem             = 6;      // Score: memory (bars; full points <= 3, half 4..ScMem)
input double  WRev              = 4.0;    // Weight: REV (sweep + TL/D)
input double  WTl               = 3.0;    // Weight: TL break
input double  WPin              = 3.0;    // Weight: Pin bar
input double  WD                = 2.0;    // Weight: AMD D (distribution)
input double  WM                = 2.0;    // Weight: AMD M (manipulation trap)
input double  WSw               = 2.0;    // Weight: Institutional Sweep
input double  WL3               = 1.0;    // Weight: L3 pivot
input double  WL2               = 1.0;    // Weight: L2 pivot
input double  WL1               = 2.0;    // Weight: L1 HL / LH pivot
input double  WScVol            = 0.5;    // Weight: Heavy Volume candle
input double  WAbs              = 0.5;    // Weight: Absorption candle

input string  s3 = "==== REV Setup & Pin Bars ====";
input bool    ShowRev           = true;   // enable REV setup engine
input int     RevWin            = 8;      // REV: sweep -> TL/D window (bars)
input double  RevMinTp          = 5.0;    // REV: min profit to target ($ price distance)
input double  RevMinRR          = 1.0;    // REV: min R:R
input bool    RevDTrig          = true;   // REV: AMD D up/down also triggers
input bool    RevNoL1           = true;   // REV: ignore L1 sweeps (L2 / L3 / AMD only)
input bool    ChkRequireHtf     = true;   // Checklist: require H1 HTF structure alignment
input bool    RevRequireHtf     = true;   // REV: require H1 HTF structure not against trade
input double  RevBigAtr         = 1.5;    // REV: skip market SIG if trigger candle > x ATR
input double  PinWick           = 66.0;   // Pin bar: min long wick (% of range)
input double  PinBody           = 25.0;   // Pin bar: max body (% of range)
input double  PinOpp            = 10.0;   // Pin bar: max opposite wick (% of range)
input bool    PinProt           = true;   // Pin bar: wick must protrude beyond previous bars
input int     PinLook           = 3;      // Pin bar: protrude beyond last N bars
input double  PinMinAtr         = 0.5;    // Pin bar: min range (x ATR)

input string  s4 = "==== Modules (Swings, HTF, ST, VP, OB, AMD, Inst, TL) ====";
input int     AtrLen            = 14;
input int     PivLeft           = 3;
input int     PivRight          = 2;
input int     HtfPivot          = 2;      // H1 pivot length
input double  StFactor          = 3.0;
input int     StAtr             = 10;
input int     VpLookback        = 200;
input int     VpRows            = 40;
input double  VpVA              = 0.70;
input double  ObDispAtr         = 1.0;    // OB displacement body >= x ATR
input int     ObLookback        = 15;     // OB search lookback (bars)
input int     MaxZones          = 5;      // Max active OBs per side
input bool    ObBodyOnly        = true;   // true = Body (Pine default), false = full Wick
input string  AmdSession        = "20:00-00:00"; // accumulation (NY time)
input int     AmdCoreMin        = 120;
input string  AmdManWin         = "00:00-11:00";
input double  AmdSweepAtr       = 0.1;
input int     AmdReclaim        = 3;
input int     AmdAccept         = 2;
input bool    AmdTrendFilter    = true;
input bool    InstOn            = true;
input int     RvolLen           = 20;
input double  RvolThr           = 1.2;
input int     VolN              = 3;
input double  GcSpike           = 2.5;    // Heavy volume: volume >= x average
input double  AbsBody           = 0.35;   // Absorption: body <= x of candle range
input double  EqTolAtr          = 0.1;
input int     InstHold          = 8;
input int     TlPivot           = 3;      // Trendline pivot bars each side
input double  TlBufAtr          = 0.1;    // Break needs close beyond line by (x ATR)
input bool    TlStOnly          = false;  // Use only TL breaks in SuperTrend direction
input string  TlAsia            = "19:00-03:00"; // NY time
input string  TlLondon          = "03:00-08:00";
input string  TlNewYork         = "08:00-17:00";

input string  s5 = "==== Exit & Stop Management ====";
input int     ExitModel         = 1;      // 1 = SIG Structural TP & SL, 0 = Half at PartialR + L1 trail, 2 = Fixed TpR
input double  TpR               = 2.0;    // Fixed R:R multiple (only when ExitModel = 2)
input double  PlanSlBuf         = 0.25;   // stop buffer behind structural/location extreme (x ATR)
input double  MaxSlAtr          = 6.0;    // skip trade if stop farther than this (x ATR)
input double  MaxSlUsd          = 95.0;   // skip trade if stop farther than this in $ (0 = off)
input double  MinSlUsd          = 12.5;   // minimum stop distance in $ price (0 = off)
input bool    PadMinSl          = true;   // true = pad SL to MinSlUsd (Champion v2.10 mode), false = skip trade
input double  MinSlAtr          = 0.0;    // skip trade if stop closer than this (x ATR, 0 = off)
input double  WideSlUsd         = 70.0;   // if SL distance >= this $, cap open trades to MaxOpenWideSl (0 = off)
input int     MaxOpenWideSl     = 1;      // max simultaneous open trades when SL >= WideSlUsd
input double  MaxRiskPct        = 0.0;    // skip trade if real risk after lot rounding exceeds this % (0 = off)
input double  BeTriggerR        = 0.0;    // move SL to Break-Even (+BeLockUsd) at this R profit (0 = off)
input double  BeLockUsd         = 0.50;   // $ locked above/below entry when Break-Even triggers
input bool    DynamicTrail      = true;   // Regime-Adaptive Dynamic Trailing (Strong vs Normal vs Range/Trend-Flip)
input double  DynStrongStartR   = 0.0;    // Dynamic Trail: start R in Strong Trend (0 = let 2R run uncapped!)
input double  DynStrongDistR    = 1.25;   // Dynamic Trail: distance R in Strong Trend
input double  DynNormStartR     = 1.80;   // Dynamic Trail: start R in Normal Trend (1.80R = late lock near TP)
input double  DynNormDistR      = 1.10;   // Dynamic Trail: distance R in Normal Trend
input double  DynRangeStartR    = 1.00;   // Dynamic Trail: start R in Range / Short-Swing / Trend-Flip
input double  DynRangeDistR     = 0.45;   // Dynamic Trail: distance R in Range / Short-Swing (tight lock)
input double  TrailStartR       = 0.0;    // Fixed trailing start R when DynamicTrail = false (0 = off)
input double  TrailDistR        = 0.85;   // Fixed trailing distance R when DynamicTrail = false
input double  TrailStepR        = 0.10;   // minimum step in R to modify trailing SL
input bool    LockOnSiblingTP   = true;   // when 1 trade in cluster hits TP, protect remaining trades at SiblingLockR
input double  SiblingLockR      = 0.05;   // R locked when sibling hits TP (0.05R = risk-free BE with full pullback room)
input bool    TrailByL1         = false;  // also trail behind L1 swing in Range/Weak regime
input bool    LogTradeRegime    = true;   // print entry & trailing regime diagnostics to MT4 Journal log
input double  PartialR          = 1.5;    // ExitModel 0: close half here, move stop to entry
input double  TrailBufAtr       = 0.1;    // ExitModel 0 / TrailByL1: buffer behind L1 swing (x ATR)

input string  s6 = "==== Trading Hours (BROKER SERVER time) ====";
input bool    UseTradeHours     = true;   // true = active London/NY hours (08:00-19:59 server)
input string  TradeWindow1      = "08:00-19:59";
input string  TradeWindow2      = "00:00-00:00";
input bool    TradeMonday       = false;
input bool    TradeTuesday      = true;
input bool    TradeWednesday    = true;
input bool    TradeThursday     = true;
input bool    TradeFriday       = true;

input string  s7 = "==== Legacy Mode Settings (only when EngineMode = 1) ====";
input int     TlValidBars       = 4;
input double  TlWeightPct       = 30.0;
input int     MinScorePct       = 60;
input int     WStruct           = 2;
input int     WAmd              = 1;
input int     WVp               = 1;
input int     WSt               = 1;
input int     WVol              = 1;
input int     WInst             = 1;
input bool    RequireHtf        = true;

//==================== GLOBALS ====================
#define NB 700
double H[NB], L[NB], O[NB], C[NB], V[NB], ATR[NB], SMAV[NB];
datetime T[NB];
int nb = 0;
datetime lastBar = 0;

// Per-bar module states (indexed by shift b = 1 .. nb-1)
int    htfDirB[NB]; double htfHB[NB], htfLB[NB];
double pdhB[NB], pdlB[NB];
int    stStateB[NB]; double stLineB[NB];
int    amdStateB[NB], amdPhaseB[NB]; bool amdPostB[NB], amdMUpB[NB], amdMDnB[NB], amdDUpB[NB], amdDDnB[NB];
double amdHiB[NB], amdLoB[NB];
bool   tlBrkUpB[NB], tlBrkDnB[NB];
bool   pinBullB[NB], pinBearB[NB];
bool   heavyB[NB], absorbB[NB], sweepBullB[NB], sweepBearB[NB];

// Latest bar (b = 1) summary values for dashboard & legacy mode
int    htfDir = 0; double htfH = EMPTY_VALUE, htfL = EMPTY_VALUE;
int    stState = 0; double stLine = 0;
int    vpState = 0; double vpPOC = 0, vpVAH = 0, vpVAL = 0;
int    volState = 0; double deltaPct = 0, rvolN = 0;
int    amdState = 0; string amdTxt = "";
double amdHi = EMPTY_VALUE, amdLo = EMPTY_VALUE; bool amdPost = false;
int    instState = 0; string instTxt = "";
double lastL1Lo = EMPTY_VALUE, lastL1Hi = EMPTY_VALUE, lastL2Lo = EMPTY_VALUE, lastL2Hi = EMPTY_VALUE, lastL3Lo = EMPTY_VALUE, lastL3Hi = EMPTY_VALUE;
double eqH = EMPTY_VALUE, eqL = EMPTY_VALUE;
int    tlDir = 0, tlAge = 9999; datetime tlTime = 0; string tlTxt = "";
int    score = 0, maxScore = 0; double scorePct = 0;

// SIG Engine (Checklist + Score + REV) latest bar outputs
int    chkDirNow = 0;
bool   ckO1 = false, ckO2 = false, ckO3 = false, ckO4 = false, ckGo = false;
string ckT1 = "", ckT2 = "", ckT3 = "", ckT4 = "", ckRes = "";
bool   sigChkFire = false; int sigChkDir = 0; double sigChkSL = 0, sigChkTP = 0; string sigChkWhy = "";
bool   sigRevFire = false; int sigRevDir = 0; double sigRevSL = 0, sigRevTP = 0; string sigRevWhy = "";
string lastMsg = "waiting for signal";

// Order Block structure
struct ObZone
{
   double top;
   double bot;
   int    bornIdx;
   int    dir;
   int    state;
};

//==================== HELPERS ====================
int BarIdx(int b) { return nb - b; } // increases left-to-right like Pine bar_index

int NyMin(datetime t)
{
   datetime ny = t - ServerMinusNY * 3600;
   int m = (int)((ny % 86400) / 60);
   if (m < 0) m += 1440;
   return m;
}
int ParseHM(string s)
{
   if (StringLen(s) == 9 && StringGetCharacter(s, 4) == '-')
      return (int)StringToInteger(StringSubstr(s, 0, 2)) * 60 + (int)StringToInteger(StringSubstr(s, 2, 2));
   return (int)StringToInteger(StringSubstr(s, 0, 2)) * 60 + (int)StringToInteger(StringSubstr(s, 3, 2));
}
bool InSess(datetime t, string sess)
{
   int a = 0, b = 0;
   if (StringLen(sess) == 9 && StringGetCharacter(sess, 4) == '-')
   {
      a = (int)StringToInteger(StringSubstr(sess, 0, 2)) * 60 + (int)StringToInteger(StringSubstr(sess, 2, 2));
      b = (int)StringToInteger(StringSubstr(sess, 5, 2)) * 60 + (int)StringToInteger(StringSubstr(sess, 7, 2));
   }
   else
   {
      a = ParseHM(StringSubstr(sess, 0, 5));
      b = ParseHM(StringSubstr(sess, 6, 5));
   }
   int m = NyMin(t);
   if (b == 0) b = 1440;
   return a < b ? (m >= a && m < b) : (m >= a || m < b);
}
int SessId(datetime t) { return InSess(t, TlAsia) ? 1 : InSess(t, TlLondon) ? 2 : InSess(t, TlNewYork) ? 3 : 0; }
bool InWin(datetime t, string w)
{
   int a = ParseHM(StringSubstr(w, 0, 5)), b = ParseHM(StringSubstr(w, 6, 5)), m = (int)((t % 86400) / 60);
   if (a == b) return false;
   return a < b ? (m >= a && m <= b) : (m >= a || m <= b);
}
bool TradeTimeOK(datetime t)
{
   int d = TimeDayOfWeek(t);
   if ((d == 1 && !TradeMonday) || (d == 2 && !TradeTuesday) || (d == 3 && !TradeWednesday) || (d == 4 && !TradeThursday) || (d == 5 && !TradeFriday)) return false;
   if (!UseTradeHours) return true;
   return InWin(t, TradeWindow1) || InWin(t, TradeWindow2);
}
double Ema(double prev, double x, int n) { return prev + (x - prev) / n; }

void LoadBars()
{
   nb = MathMin(NB, Bars - 1);
   for (int i = 0; i < nb; i++)
   {
      H[i] = High[i]; L[i] = Low[i]; O[i] = Open[i]; C[i] = Close[i];
      V[i] = (double)Volume[i]; T[i] = Time[i];
      int dShift = iBarShift(NULL, PERIOD_D1, T[i], false) + 1;
      pdhB[i] = iHigh(NULL, PERIOD_D1, dShift);
      pdlB[i] = iLow(NULL, PERIOD_D1, dShift);
   }
   double a = 0;
   for (int k = nb - 2; k >= 0; k--)
   {
      double tr = MathMax(H[k] - L[k], MathMax(MathAbs(H[k] - C[k + 1]), MathAbs(L[k] - C[k + 1])));
      a = (k == nb - 2) ? tr : Ema(a, tr, AtrLen);
      ATR[k] = a;
   }
   ATR[nb - 1] = ATR[nb - 2];
   for (int k = nb - 1; k >= 0; k--)
   {
      double sumV = 0; int cntV = 0;
      for (int j = 0; j < RvolLen && k + j < nb; j++) { sumV += V[k + j]; cntV++; }
      SMAV[k] = cntV > 0 ? sumV / cntV : V[k];
   }
}

bool IsPH(int s, int left, int right)
{
   if (s + left >= nb || s - right < 1) return false;
   for (int j = 1; j <= left; j++) if (H[s + j] >= H[s]) return false;
   for (int j = 1; j <= right; j++) if (H[s - j] > H[s]) return false;
   return true;
}
bool IsPL(int s, int left, int right)
{
   if (s + left >= nb || s - right < 1) return false;
   for (int j = 1; j <= left; j++) if (L[s + j] <= L[s]) return false;
   for (int j = 1; j <= right; j++) if (L[s - j] < L[s]) return false;
   return true;
}

//==================== HTF STRUCTURE (H1, closed bars mapped to M15) ====================
void HtfStructure()
{
   int nH1 = MathMin(400, iBars(NULL, PERIOD_H1) - 1);
   int p = HtfPivot;
   double h1LH[], h1LL[]; int h1D[];
   ArrayResize(h1LH, nH1 + 2); ArrayResize(h1LL, nH1 + 2); ArrayResize(h1D, nH1 + 2);
   for (int i = 0; i < nH1 + 2; i++) { h1LH[i] = EMPTY_VALUE; h1LL[i] = EMPTY_VALUE; h1D[i] = 0; }
   double lh = EMPTY_VALUE, pvh = EMPTY_VALUE, ll = EMPTY_VALUE, pvl = EMPTY_VALUE; int d = 0;
   for (int j = nH1 - 2 * p - 1; j >= 1; j--)
   {
      int s = j + p; bool isH = true, isL = true;
      double hs = iHigh(NULL, PERIOD_H1, s), ls = iLow(NULL, PERIOD_H1, s);
      for (int k = 1; k <= p; k++)
      {
         if (iHigh(NULL, PERIOD_H1, s + k) >= hs || iHigh(NULL, PERIOD_H1, s - k) > hs) isH = false;
         if (iLow(NULL, PERIOD_H1, s + k) <= ls || iLow(NULL, PERIOD_H1, s - k) < ls) isL = false;
      }
      if (isH) { pvh = lh; lh = hs; }
      if (isL) { pvl = ll; ll = ls; }
      double cj = iClose(NULL, PERIOD_H1, j);
      if (lh != EMPTY_VALUE && cj > lh) d = 1;
      else if (ll != EMPTY_VALUE && cj < ll) d = -1;
      else if (isH || isL)
      {
         if (pvh != EMPTY_VALUE && pvl != EMPTY_VALUE && lh > pvh && ll > pvl) d = 1;
         else if (pvh != EMPTY_VALUE && pvl != EMPTY_VALUE && lh < pvh && ll < pvl) d = -1;
      }
      h1LH[j] = lh; h1LL[j] = ll; h1D[j] = d;
   }
   // Pine uses [lh[1], ll[1], d[1]] on the H1 bar covering T[b], i.e. the previous closed H1 bar (sh + 1)
   for (int b = nb - 1; b >= 1; b--)
   {
      int sh = iBarShift(NULL, PERIOD_H1, T[b], false) + 1;
      if (sh < 1) sh = 1;
      if (sh >= nH1) sh = nH1 - 1;
      htfDirB[b] = h1D[sh]; htfHB[b] = h1LH[sh]; htfLB[b] = h1LL[sh];
   }
   htfDir = htfDirB[1]; htfH = htfHB[1]; htfL = htfLB[1];
}

//==================== SUPERTREND ====================
void SuperTrend()
{
   double a = 0, lo = 0, up = 0, st = 0; int dir = 1; bool first = true;
   stStateB[nb - 1] = 1; stLineB[nb - 1] = C[nb - 1];
   for (int k = nb - 2; k >= 1; k--)
   {
      double tr = MathMax(H[k] - L[k], MathMax(MathAbs(H[k] - C[k + 1]), MathAbs(L[k] - C[k + 1])));
      a = first ? tr : Ema(a, tr, StAtr);
      double hl2 = (H[k] + L[k]) / 2.0, nlo = hl2 - StFactor * a, nup = hl2 + StFactor * a;
      if (first) { lo = nlo; up = nup; dir = 1; st = up; first = false; stLineB[k] = st; stStateB[k] = -1; continue; }
      double plo = lo, pup = up, pst = st;
      lo = (nlo > plo || C[k + 1] < plo) ? nlo : plo;
      up = (nup < pup || C[k + 1] > pup) ? nup : pup;
      if (pst == pup) dir = C[k] > up ? -1 : 1; else dir = C[k] < lo ? 1 : -1;
      st = dir == -1 ? lo : up;
      stLineB[k] = st;
      stStateB[k] = dir < 0 ? 1 : -1;
   }
   stLine = stLineB[1]; stState = stStateB[1];
}

//==================== VOLUME PROFILE (at bar shift b0) ====================
void VolumeProfileAt(int b0, double &pocOut, double &vahOut, double &valOut, int &stOut)
{
   pocOut = EMPTY_VALUE; vahOut = EMPTY_VALUE; valOut = EMPTY_VALUE; stOut = 0;
   if (b0 + VpLookback >= nb) return;
   double hi = H[b0], lo = L[b0];
   for (int i = b0; i < b0 + VpLookback; i++) { hi = MathMax(hi, H[i]); lo = MathMin(lo, L[i]); }
   double step = (hi - lo) / VpRows; if (step <= 0) return;
   double vols[]; ArrayResize(vols, VpRows); ArrayInitialize(vols, 0);
   for (int i = b0; i < b0 + VpLookback; i++)
   {
      int r0 = MathMax(0, MathMin(VpRows - 1, (int)MathFloor((L[i] - lo) / step)));
      int r1 = MathMax(0, MathMin(VpRows - 1, (int)MathFloor((H[i] - lo) / step)));
      double sh = V[i] / (r1 - r0 + 1);
      for (int r = r0; r <= r1; r++) vols[r] += sh;
   }
   int poc = ArrayMaximum(vols); double total = 0; for (int r = 0; r < VpRows; r++) total += vols[r];
   int u = poc, d = poc; double acc = vols[poc];
   while (acc < total * VpVA && (u < VpRows - 1 || d > 0))
   {
      double vu = u < VpRows - 1 ? vols[u + 1] : -1, vd = d > 0 ? vols[d - 1] : -1;
      if (vu >= vd) { u++; acc += vu; } else { d--; acc += vd; }
   }
   pocOut = lo + step * (poc + 0.5); vahOut = lo + step * (u + 1); valOut = lo + step * d;
   stOut = C[b0] > vahOut ? 1 : C[b0] < valOut ? -1 : 0;
}
void VolumeProfile()
{
   VolumeProfileAt(1, vpPOC, vpVAH, vpVAL, vpState);
}

//==================== VOLUME DELTA ====================
void VolumeVote()
{
   double sum = 0, del = 0;
   for (int i = 1; i <= VolN; i++) { sum += V[i]; del += C[i] > O[i] ? V[i] : C[i] < O[i] ? -V[i] : 0; }
   rvolN = sum / MathMax(SMAV[1] * VolN, 1e-10); deltaPct = sum > 0 ? del / sum : 0;
   volState = (rvolN >= RvolThr && MathAbs(deltaPct) >= 0.3) ? (deltaPct > 0 ? 1 : -1) : 0;
}

//==================== AMD (Power of 3 + Counter-HTF 2-Close Trap Rule) ====================
void Amd()
{
   for (int i = 0; i < NB; i++)
   {
      amdStateB[i] = 0; amdPhaseB[i] = 0; amdPostB[i] = false;
      amdMUpB[i] = false; amdMDnB[i] = false; amdDUpB[i] = false; amdDDnB[i] = false;
      amdHiB[i] = EMPTY_VALUE; amdLoB[i] = EMPTY_VALUE;
   }
   amdState = 0; amdTxt = "No setup"; amdPost = false; amdHi = EMPTY_VALUE; amdLo = EMPTY_VALUE;
   int core = MathMax(1, AmdCoreMin / Period());
   double hi = EMPTY_VALUE, lo = EMPTY_VALUE, swHi = EMPTY_VALUE, swLo = EMPTY_VALUE;
   int accBar = -1, phase = 0, dir = 0, brk = 0, swHiBar = -1, swLoBar = -1, inHiN = 0, inLoN = 0;
   bool sH = false, sL = false, lkH = false, lkL = false, fail = false, post = false;
   for (int b = nb - 3; b >= 1; b--)
   {
      int idx = BarIdx(b);
      bool inAcc = InSess(T[b], AmdSession);
      bool prevAcc = InSess(T[b + 1], AmdSession);
      bool accStart = inAcc && !prevAcc;
      if (accStart)
      {
         hi = H[b]; lo = L[b]; accBar = idx; phase = 1; dir = 0;
         sH = false; sL = false; swHi = EMPTY_VALUE; swLo = EMPTY_VALUE;
         lkH = false; lkL = false; brk = 0; fail = false; swHiBar = -1; swLoBar = -1;
         inHiN = 0; inLoN = 0;
      }
      else if (inAcc && phase == 1 && accBar >= 0 && idx - accBar < core)
      {
         hi = MathMax(hi, H[b]); lo = MathMin(lo, L[b]);
      }
      post = (hi != EMPTY_VALUE && phase >= 1 && (!inAcc || idx - accBar >= core));
      bool win = inAcc || InSess(T[b], AmdManWin);
      double buf = ATR[b] * AmdSweepAtr;
      int abv = 0, blw = 0;
      for (int k = 0; k < AmdAccept && b + k < nb; k++)
      {
         if (hi != EMPTY_VALUE && C[b + k] > hi) abv++;
         if (lo != EMPTY_VALUE && C[b + k] < lo) blw++;
      }
      int trNow = htfDirB[b];
      if (post && brk == 0)
      {
         if (phase == 1)
         {
            if (win && !sH && !lkH && H[b] > hi + buf) { sH = true; swHiBar = idx; }
            if (win && !sL && !lkL && L[b] < lo - buf) { sL = true; swLoBar = idx; }
            if (sH) swHi = swHi == EMPTY_VALUE ? H[b] : MathMax(swHi, H[b]);
            if (sL) swLo = swLo == EMPTY_VALUE ? L[b] : MathMin(swLo, L[b]);
            inHiN = (sH && C[b] < hi) ? inHiN + 1 : 0;
            inLoN = (sL && C[b] > lo) ? inLoN + 1 : 0;
            bool okHi = (trNow == 1) ? (inHiN >= 2 && C[b] < hi - ATR[b] * 0.25) : true;
            bool okLo = (trNow == -1) ? (inLoN >= 2 && C[b] > lo + ATR[b] * 0.25) : true;
            bool trH = sH && C[b] < hi && (idx - swHiBar) <= AmdReclaim + (trNow == 1 ? 1 : 0) && okHi;
            bool trL = sL && C[b] > lo && (idx - swLoBar) <= AmdReclaim + (trNow == -1 ? 1 : 0) && okLo;
            if (trL && !trH) { phase = 2; dir = 1; amdMUpB[b] = true; }
            else if (trH && !trL) { phase = 2; dir = -1; amdMDnB[b] = true; }
            else if (sH && idx - swHiBar > AmdReclaim && C[b] > hi) brk = 1;
            else if (sL && idx - swLoBar > AmdReclaim && C[b] < lo) brk = -1;
            else if (sH && idx - swHiBar > AmdReclaim) { sH = false; lkH = true; }
            else if (sL && idx - swLoBar > AmdReclaim) { sL = false; lkL = true; }
         }
         if (phase == 2 && dir == -1 && (C[b] > (swHi == EMPTY_VALUE ? 1e10 : swHi) || abv >= AmdAccept))
         {
            phase = 1; dir = 0; sH = false; swHi = EMPTY_VALUE; lkH = true; brk = 1; fail = true; amdDUpB[b] = true;
         }
         if (phase == 2 && dir == 1 && (C[b] < (swLo == EMPTY_VALUE ? -1e10 : swLo) || blw >= AmdAccept))
         {
            phase = 1; dir = 0; sL = false; swLo = EMPTY_VALUE; lkL = true; brk = -1; fail = true; amdDDnB[b] = true;
         }
         if (phase == 2 && dir == 1 && C[b] > hi) { phase = 3; amdDUpB[b] = true; }
         if (phase == 2 && dir == -1 && C[b] < lo) { phase = 3; amdDDnB[b] = true; }
      }
      if (brk == -1 && hi != EMPTY_VALUE && C[b] > hi + buf) { brk = 0; fail = false; phase = 3; dir = 1; amdDUpB[b] = true; }
      if (brk == 1 && lo != EMPTY_VALUE && C[b] < lo - buf) { brk = 0; fail = false; phase = 3; dir = -1; amdDDnB[b] = true; }
      if (phase == 3 && dir == 1 && C[b] < (swLo == EMPTY_VALUE ? lo : swLo) - buf) { dir = 0; phase = 0; }
      if (phase == 3 && dir == -1 && C[b] > (swHi == EMPTY_VALUE ? hi : swHi) + buf) { dir = 0; phase = 0; }

      int bias = brk != 0 ? brk : phase >= 2 ? dir : 0;
      bool counter = (bias != 0 && trNow == -bias);
      amdStateB[b] = (AmdTrendFilter && counter) ? 0 : bias;
      amdPhaseB[b] = phase;
      amdPostB[b] = post;
      amdHiB[b] = hi;
      amdLoB[b] = lo;
   }
   amdHi = amdHiB[1]; amdLo = amdLoB[1]; amdPost = amdPostB[1]; amdState = amdStateB[1];
   amdTxt = brk != 0 ? (fail ? (brk == 1 ? "Distribution up (failed M down)" : "Distribution down (failed M up)") : (brk == 1 ? "Breakout up" : "Breakout down"))
          : phase == 1 ? "Range" : phase == 2 ? (dir == 1 ? "Manipulation (M up)" : "Manipulation (M down)")
          : phase == 3 ? (dir == 1 ? "Distribution (D up)" : "Distribution (D down)") : "No setup";
}

//==================== SESSION TRENDLINES (with carried unbroken lines) ====================
double LineY(double y0, int x0, double y1, int x1, int x) { return x1 == x0 ? y1 : y1 + (y1 - y0) / (x1 - x0) * (x - x1); }
void DrawLine(string nm, bool ok, int idx0, double y0, int idx1, double y1, color col)
{
   ObjectDelete(0, nm); if (!ok || !DrawObjects) return;
   int b0 = nb - idx0, b1 = nb - idx1;
   if (b0 < 0 || b0 >= nb || b1 < 0 || b1 >= nb) return;
   ObjectCreate(0, nm, OBJ_TREND, 0, T[b0], y0, T[b1], y1);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, true);
}

void Trendlines()
{
   for (int i = 0; i < NB; i++) { tlBrkUpB[i] = false; tlBrkDnB[i] = false; }
   double ry0 = 0, ry1 = 0, sy0 = 0, sy1 = 0;
   int rx0 = -1, rx1 = -1, sx0 = -1, sx1 = -1;
   bool hasR = false, hasS = false, rb = false, sb = false, carryR = false, carryS = false;
   datetime sessStartT = 0;
   tlDir = 0; tlAge = 9999; tlTime = 0;
   for (int c = nb - TlPivot - 2; c >= 1; c--)
   {
      int idx = BarIdx(c);
      int id = SessId(T[c]);
      bool newSess = (id != 0 && id != SessId(T[c + 1]));
      if (newSess)
      {
         sessStartT = T[c];
         if (!hasR || rb) { hasR = false; rx0 = -1; rx1 = -1; carryR = false; }
         else carryR = true;
         if (!hasS || sb) { hasS = false; sx0 = -1; sx1 = -1; carryS = false; }
         else carryS = true;
         rb = false; sb = false;
      }
      int s = c + TlPivot;
      int pivIdx = BarIdx(s);
      bool pivInSess = (sessStartT > 0 && T[s] >= sessStartT);
      if (pivInSess && IsPH(s, TlPivot, TlPivot))
      {
         if (carryR) { hasR = false; rx1 = -1; carryR = false; rb = false; }
         ry0 = ry1; rx0 = rx1;
         ry1 = H[s]; rx1 = pivIdx;
         if (rx0 > 0) { hasR = true; rb = false; }
      }
      if (pivInSess && IsPL(s, TlPivot, TlPivot))
      {
         if (carryS) { hasS = false; sx1 = -1; carryS = false; sb = false; }
         sy0 = sy1; sx0 = sx1;
         sy1 = L[s]; sx1 = pivIdx;
         if (sx0 > 0) { hasS = true; sb = false; }
      }
      if (hasR && !rb && idx > rx1)
      {
         double yR = LineY(ry0, rx0, ry1, rx1, idx);
         if (C[c] > yR + TlBufAtr * ATR[c])
         {
            rb = true; tlBrkUpB[c] = true;
            tlDir = 1; tlAge = c; tlTime = T[c];
         }
      }
      if (hasS && !sb && idx > sx1)
      {
         double yS = LineY(sy0, sx0, sy1, sx1, idx);
         if (C[c] < yS - TlBufAtr * ATR[c])
         {
            sb = true; tlBrkDnB[c] = true;
            tlDir = -1; tlAge = c; tlTime = T[c];
         }
      }
   }
   int idxNow = BarIdx(1);
   string sn = SessId(T[1]) == 1 ? "Asia" : SessId(T[1]) == 2 ? "London" : SessId(T[1]) == 3 ? "New York" : "-";
   tlTxt = sn + "  R " + (hasR ? DoubleToString(LineY(ry0, rx0, ry1, rx1, idxNow), Digits) : "-")
              + "  S " + (hasS ? DoubleToString(LineY(sy0, sx0, sy1, sx1, idxNow), Digits) : "-");
   DrawLine("SL3_TL_R", hasR, rx0, ry0, rx1, ry1, clrRed);
   DrawLine("SL3_TL_S", hasS, sx0, sy0, sx1, sy1, clrDodgerBlue);
}

//==================== PIN BARS ====================
void PinBars()
{
   for (int i = 0; i < NB; i++) { pinBullB[i] = false; pinBearB[i] = false; }
   for (int c = nb - PinLook - 2; c >= 1; c--)
   {
      double rng = H[c] - L[c];
      double upW = rng > 0 ? (H[c] - MathMax(O[c], C[c])) / rng * 100.0 : 0;
      double dnW = rng > 0 ? (MathMin(O[c], C[c]) - L[c]) / rng * 100.0 : 0;
      double bd  = rng > 0 ? MathAbs(C[c] - O[c]) / rng * 100.0 : 100.0;
      bool ok = (rng >= ATR[c] * PinMinAtr && bd <= PinBody);
      double prLo = L[c + 1], prHi = H[c + 1];
      for (int k = 1; k <= PinLook && c + k < nb; k++) { prLo = MathMin(prLo, L[c + k]); prHi = MathMax(prHi, H[c + k]); }
      pinBullB[c] = ok && dnW >= PinWick && upW <= PinOpp && (!PinProt || L[c] < prLo);
      pinBearB[c] = ok && upW >= PinWick && dnW <= PinOpp && (!PinProt || H[c] > prHi);
   }
}

//==================== TARGET & SWEEP HELPERS ====================
void LvAdd(double &v[], string &n[], int &cnt, double x, string nm)
{
   if (x == EMPTY_VALUE || x <= 0) return;
   v[cnt] = x; n[cnt] = nm; cnt++;
}
bool FindAbove(double &v[], string &n[], int cnt, double px, double &bv, string &bn)
{
   bv = EMPTY_VALUE; bn = "-";
   for (int i = 0; i < cnt; i++)
      if (v[i] > px && (bv == EMPTY_VALUE || v[i] < bv)) { bv = v[i]; bn = n[i]; }
   return bv != EMPTY_VALUE;
}
bool FindBelow(double &v[], string &n[], int cnt, double px, double &bv, string &bn)
{
   bv = EMPTY_VALUE; bn = "-";
   for (int i = 0; i < cnt; i++)
      if (v[i] < px && (bv == EMPTY_VALUE || v[i] > bv)) { bv = v[i]; bn = n[i]; }
   return bv != EMPTY_VALUE;
}
bool TagLo(int c, double lv) { return lv != EMPTY_VALUE && lv > 0 && L[c] <= lv + ATR[c] * 0.15 && C[c] > lv; }
bool TagHi(int c, double lv) { return lv != EMPTY_VALUE && lv > 0 && H[c] >= lv - ATR[c] * 0.15 && C[c] < lv; }
bool SweepHiAt(int c, double lv) { return lv != EMPTY_VALUE && lv > 0 && H[c] > lv + ATR[c] * 0.05 && C[c] < lv; }
bool SweepLoAt(int c, double lv) { return lv != EMPTY_VALUE && lv > 0 && L[c] < lv - ATR[c] * 0.05 && C[c] > lv; }
// True fresh sweep of a structural level (prevents stale levels $150 away from re-triggering on every bar)
bool FreshSwLo(int c, double lv) { return lv != EMPTY_VALUE && lv > 0 && L[c] < lv && (L[c + 1] >= lv || C[c] > lv - ATR[c] * 0.5); }
bool FreshSwHi(int c, double lv) { return lv != EMPTY_VALUE && lv > 0 && H[c] > lv && (H[c + 1] <= lv || C[c] < lv + ATR[c] * 0.5); }

double ScPts(int curIdx, int bIdx, double w)
{
   if (bIdx < 0 || curIdx - bIdx > ScMem) return 0.0;
   return (curIdx - bIdx <= 3) ? w : w * 0.5;
}
string ScTx(int curIdx, int bIdx, double w, string nm)
{
   double p = ScPts(curIdx, bIdx, w);
   if (p <= 0) return "";
   string s = (MathAbs(p - MathRound(p)) < 0.05) ? IntegerToString((int)MathRound(p)) : DoubleToString(p, 1);
   return nm + " " + s + " . ";
}
bool TgIn(int curIdx, int bIdx) { return bIdx >= 0 && (curIdx - bIdx) <= ChkMem; }

//==================== UNIFIED SWINGS + OB + INST + CHECKLIST + SCORE + REV ====================
void RunSigEngine()
{
   double h1[], l1[], h2[], l2[], h3[], l3[];
   int nh1 = 0, nl1 = 0, nh2 = 0, nl2 = 0, nh3 = 0, nl3 = 0;
   ArrayResize(h1, NB); ArrayResize(l1, NB); ArrayResize(h2, NB); ArrayResize(l2, NB); ArrayResize(h3, NB); ArrayResize(l3, NB);
   double prevPH = EMPTY_VALUE, prevPL = EMPTY_VALUE;
   eqH = EMPTY_VALUE; eqL = EMPTY_VALUE;
   lastL1Hi = EMPTY_VALUE; lastL1Lo = EMPTY_VALUE;
   lastL2Hi = EMPTY_VALUE; lastL2Lo = EMPTY_VALUE;
   lastL3Hi = EMPTY_VALUE; lastL3Lo = EMPTY_VALUE;

   int swingState = 0, bosDir = 0; double bosLvl = EMPTY_VALUE;
   ObZone zones[]; int nZones = 0; ArrayResize(zones, 60);
   int lastBullOB = -1, lastBearOB = -1;
   int lastSwB = -1000, lastSwS = -1000;
   instState = 0; instTxt = "no fresh footprint";

   // Checklist & Trigger Score state across bars
   int locLoBar = -1, locHiBar = -1;
   string locLoTxt = "", locHiTxt = "";
   double locLoExt = EMPTY_VALUE, locHiExt = EMPTY_VALUE;
   int pinLoBar = -1, pinHiBar = -1;
   double pinLoExt = EMPTY_VALUE, pinHiExt = EMPTY_VALUE;
   int tgPinL = -1, tgTlL = -1, tgRvL = -1, tgPinS = -1, tgTlS = -1, tgRvS = -1;

   // Score item bar indices
   int scSwBL = -1, scSwBS = -1;
   int bRevL = -1, bRevS = -1, bTlL = -1, bTlS = -1, bPinL = -1, bPinS = -1;
   int bDL = -1, bDS = -1, bML = -1, bMS = -1, bSwL = -1, bSwS = -1;
   int bL3L = -1, bL3S = -1, bL2L = -1, bL2S = -1, bL1L = -1, bL1S = -1;
   int bVolL = -1, bVolS = -1, bAbL = -1, bAbS = -1;

   // REV state across bars
   int rvLoBar = -1, rvHiBar = -1;
   int goPrevDir = 0;

   sigChkFire = false; sigChkDir = 0; sigChkSL = 0; sigChkTP = 0; sigChkWhy = "";
   sigRevFire = false; sigRevDir = 0; sigRevSL = 0; sigRevTP = 0; sigRevWhy = "";

   for (int c = nb - PivLeft - PivRight - 1; c >= 1; c--)
   {
      int idx = BarIdx(c);
      double pdh = pdhB[c], pdl = pdlB[c];
      double l1Hi_prev = lastL1Hi, l1Lo_prev = lastL1Lo;
      double l2Hi_prev = lastL2Hi, l2Lo_prev = lastL2Lo;
      double l3Hi_prev = lastL3Hi, l3Lo_prev = lastL3Lo;

      // 1) Swings L1 -> L2 -> L3 at confirmation bar c
      int s = c + PivRight;
      double ph = IsPH(s, PivLeft, PivRight) ? H[s] : EMPTY_VALUE;
      double pl = IsPL(s, PivLeft, PivRight) ? L[s] : EMPTY_VALUE;
      double prvH1 = lastL1Hi, prvL1 = lastL1Lo;
      bool newH2 = false, newH3 = false, newL2 = false, newL3 = false;

      if (ph != EMPTY_VALUE)
      {
         h1[nh1++] = ph;
         lastL1Hi = ph;
         if (prevPH != EMPTY_VALUE && MathAbs(ph - prevPH) <= ATR[c] * EqTolAtr) eqH = MathMax(ph, prevPH);
         prevPH = ph;
         if (nh1 >= 3 && h1[nh1 - 2] > h1[nh1 - 3] && h1[nh1 - 2] >= h1[nh1 - 1])
         {
            h2[nh2++] = h1[nh1 - 2]; lastL2Hi = h2[nh2 - 1]; newH2 = true;
            if (nh2 >= 3 && h2[nh2 - 2] > h2[nh2 - 3] && h2[nh2 - 2] >= h2[nh2 - 1])
            {
               h3[nh3++] = h2[nh2 - 2]; lastL3Hi = h3[nh3 - 1]; newH3 = true;
            }
         }
      }
      if (pl != EMPTY_VALUE)
      {
         l1[nl1++] = pl;
         lastL1Lo = pl;
         if (prevPL != EMPTY_VALUE && MathAbs(pl - prevPL) <= ATR[c] * EqTolAtr) eqL = MathMin(pl, prevPL);
         prevPL = pl;
         if (nl1 >= 3 && l1[nl1 - 2] < l1[nl1 - 3] && l1[nl1 - 2] <= l1[nl1 - 1])
         {
            l2[nl2++] = l1[nl1 - 2]; lastL2Lo = l2[nl2 - 1]; newL2 = true;
            if (nl2 >= 3 && l2[nl2 - 2] < l2[nl2 - 3] && l2[nl2 - 2] <= l2[nl2 - 1])
            {
               l3[nl3++] = l2[nl2 - 2]; lastL3Lo = l3[nl3 - 1]; newL3 = true;
            }
         }
      }

      // BOS & Broken structure retest levels
      bool bosUp = (lastL3Hi != EMPTY_VALUE && l3Hi_prev != EMPTY_VALUE && C[c] > lastL3Hi && C[c + 1] <= l3Hi_prev);
      bool bosDn = (lastL3Lo != EMPTY_VALUE && l3Lo_prev != EMPTY_VALUE && C[c] < lastL3Lo && C[c + 1] >= l3Lo_prev);
      if (bosUp) { swingState = 1; bosLvl = lastL3Hi; bosDir = 1; }
      else if (bosDn) { swingState = -1; bosLvl = lastL3Lo; bosDir = -1; }
      else if (newH3 || newL3)
      {
         bool sBull = (nh3 >= 2 && nl3 >= 2 && h3[nh3 - 1] > h3[nh3 - 2] && l3[nl3 - 1] > l3[nl3 - 2]);
         bool sBear = (nh3 >= 2 && nl3 >= 2 && h3[nh3 - 1] < h3[nh3 - 2] && l3[nl3 - 1] < l3[nl3 - 2]);
         swingState = sBull ? 1 : sBear ? -1 : 0; bosDir = 0;
      }
      if (bosDir == 1 && swingState == 1 && C[c] < bosLvl) { swingState = 0; bosDir = 0; }
      if (bosDir == -1 && swingState == -1 && C[c] > bosLvl) { swingState = 0; bosDir = 0; }
      double brkUp = bosDir == 1 ? bosLvl : (htfDirB[c] == 1 && htfHB[c] != EMPTY_VALUE && C[c] > htfHB[c] ? htfHB[c] : EMPTY_VALUE);
      double brkDn = bosDir == -1 ? bosLvl : (htfDirB[c] == -1 && htfLB[c] != EMPTY_VALUE && C[c] < htfLB[c] ? htfLB[c] : EMPTY_VALUE);

      // 2) Order Blocks (displacement + mitigation)
      double body = MathAbs(C[c] - O[c]);
      if (C[c] > O[c] && body >= ObDispAtr * ATR[c])
      {
         for (int i = 1; i <= ObLookback && c + i < nb; i++)
         {
            if (C[c + i] < O[c + i])
            {
               int obIdx = BarIdx(c + i);
               if (obIdx != lastBullOB && C[c] > H[c + i])
               {
                  double zt = ObBodyOnly ? MathMax(O[c + i], C[c + i]) : H[c + i];
                  double zb = ObBodyOnly ? MathMin(O[c + i], C[c + i]) : L[c + i];
                  if (nZones < ArraySize(zones))
                  {
                     zones[nZones].top = zt; zones[nZones].bot = zb; zones[nZones].bornIdx = idx;
                     zones[nZones].dir = 1; zones[nZones].state = 0; nZones++;
                  }
                  lastBullOB = obIdx;
               }
               break;
            }
         }
      }
      if (C[c] < O[c] && body >= ObDispAtr * ATR[c])
      {
         for (int i = 1; i <= ObLookback && c + i < nb; i++)
         {
            if (C[c + i] > O[c + i])
            {
               int obIdx = BarIdx(c + i);
               if (obIdx != lastBearOB && C[c] < L[c + i])
               {
                  double zt = ObBodyOnly ? MathMax(O[c + i], C[c + i]) : H[c + i];
                  double zb = ObBodyOnly ? MathMin(O[c + i], C[c + i]) : L[c + i];
                  if (nZones < ArraySize(zones))
                  {
                     zones[nZones].top = zt; zones[nZones].bot = zb; zones[nZones].bornIdx = idx;
                     zones[nZones].dir = -1; zones[nZones].state = 0; nZones++;
                  }
                  lastBearOB = obIdx;
               }
               break;
            }
         }
      }
      int cntBull = 0, cntBear = 0;
      for (int zi = nZones - 1; zi >= 0; zi--)
      {
         bool dead = false;
         if (zones[zi].dir == 1) { cntBull++; if (cntBull > MaxZones) dead = true; }
         else { cntBear++; if (cntBear > MaxZones) dead = true; }
         if (!dead && idx > zones[zi].bornIdx)
         {
            if (zones[zi].dir == 1) { if (L[c] <= zones[zi].top) zones[zi].state = 1; dead = (C[c] < zones[zi].bot); }
            else { if (H[c] >= zones[zi].bot) zones[zi].state = 1; dead = (C[c] > zones[zi].top); }
         }
         if (dead)
         {
            for (int m = zi; m < nZones - 1; m++) zones[m] = zones[m + 1];
            nZones--;
         }
      }

      // 3) Institutional footprints (Heavy vol, Absorption, Liquidity Sweeps)
      double rngI = MathMax(H[c] - L[c], Point);
      heavyB[c] = InstOn && SMAV[c] > 0 && (V[c] / SMAV[c] >= GcSpike);
      absorbB[c] = heavyB[c] && (MathAbs(C[c] - O[c]) / rngI <= AbsBody);
      double asiaH = amdPostB[c] ? amdHiB[c] : EMPTY_VALUE;
      double asiaL = amdPostB[c] ? amdLoB[c] : EMPTY_VALUE;
      double upW = (H[c] - MathMax(O[c], C[c])) / rngI;
      double dnW = (MathMin(O[c], C[c]) - L[c]) / rngI;
      sweepBearB[c] = InstOn && (SweepHiAt(c, pdh) || SweepHiAt(c, asiaH) || SweepHiAt(c, eqH)) && (upW >= 0.4 || heavyB[c]) && (idx - lastSwS > 8);
      sweepBullB[c] = InstOn && (SweepLoAt(c, pdl) || SweepLoAt(c, asiaL) || SweepLoAt(c, eqL)) && (dnW >= 0.4 || heavyB[c]) && (idx - lastSwB > 8);
      if (sweepBearB[c]) { lastSwS = idx; if (SweepHiAt(c, eqH)) eqH = EMPTY_VALUE; }
      if (sweepBullB[c]) { lastSwB = idx; if (SweepLoAt(c, eqL)) eqL = EMPTY_VALUE; }
      if (c <= InstHold)
      {
         if (sweepBullB[c] && !sweepBearB[c]) { instState = 1; instTxt = "Sweep bull (" + IntegerToString(c - 1) + "b ago)"; }
         else if (sweepBearB[c] && !sweepBullB[c]) { instState = -1; instTxt = "Sweep bear (" + IntegerToString(c - 1) + "b ago)"; }
      }

      // 4) VP levels for recent bars (only computed where needed)
      double cPOC = EMPTY_VALUE, cVAH = EMPTY_VALUE, cVAL = EMPTY_VALUE; int cVpSt = 0;
      if (c <= 12) VolumeProfileAt(c, cPOC, cVAH, cVAL, cVpSt);

      // 5) Checklist Row 1: Direction (2 of 3: HTF, SuperTrend, AMD)
      int chkVotes = htfDirB[c] + stStateB[c] + amdStateB[c];
      int chkDir = chkVotes >= 2 ? 1 : chkVotes <= -2 ? -1 : 0;
      if (ChkRequireHtf && ((chkDir == 1 && htfDirB[c] != 1) || (chkDir == -1 && htfDirB[c] != -1))) chkDir = 0;

      // 6) Checklist Row 2: Location
      bool obLo = false, obHi = false;
      for (int zi = 0; zi < nZones; zi++)
      {
         if (zones[zi].dir == 1 && L[c] <= zones[zi].top && C[c] >= zones[zi].bot) obLo = true;
         if (zones[zi].dir == -1 && H[c] >= zones[zi].bot && C[c] <= zones[zi].top) obHi = true;
      }
      bool l1SweepLo = (l1Lo_prev != EMPTY_VALUE && L[c] < l1Lo_prev && C[c] > l1Lo_prev);
      bool l1SweepHi = (l1Hi_prev != EMPTY_VALUE && H[c] > l1Hi_prev && C[c] < l1Hi_prev);
      bool stLo = ChkStLv && stStateB[c] == 1 && TagLo(c, stLineB[c]);
      bool stHi = ChkStLv && stStateB[c] == -1 && TagHi(c, stLineB[c]);
      double amdLvA = (amdPhaseB[c] > 0 && amdPostB[c]) ? amdHiB[c] : EMPTY_VALUE;
      double amdLvB = (amdPhaseB[c] > 0 && amdPostB[c]) ? amdLoB[c] : EMPTY_VALUE;
      bool amdLoTag = ChkAmdLv && (TagLo(c, amdLvB) || TagLo(c, amdLvA));
      bool amdHiTag = ChkAmdLv && (TagHi(c, amdLvA) || TagHi(c, amdLvB));
      bool l1HlLo = ChkL1Hl && stStateB[c] == 1 && pl != EMPTY_VALUE && prvL1 != EMPTY_VALUE && pl > prvL1;
      bool l1LhHi = ChkL1Hl && stStateB[c] == -1 && ph != EMPTY_VALUE && prvH1 != EMPTY_VALUE && ph < prvH1;

      bool locLoNow = l1HlLo || stLo || amdLoTag || obLo || l1SweepLo || TagLo(c, cVAL) || TagLo(c, cPOC) || TagLo(c, cVAH) || TagLo(c, lastL2Lo) || TagLo(c, lastL3Lo) || TagLo(c, htfLB[c]) || TagLo(c, brkUp);
      bool locHiNow = l1LhHi || stHi || amdHiTag || obHi || l1SweepHi || TagHi(c, cVAH) || TagHi(c, cPOC) || TagHi(c, cVAL) || TagHi(c, lastL2Hi) || TagHi(c, lastL3Hi) || TagHi(c, htfHB[c]) || TagHi(c, brkDn);

      string locLoWhy = l1HlLo ? "L1 HL (trend)" : stLo ? "SuperTrend line" : amdLoTag ? "AMD range edge" : obLo ? "Bull OB" : l1SweepLo ? "L1 low swept" : TagLo(c, cVAL) ? "VAL" : TagLo(c, cPOC) ? "POC" : TagLo(c, cVAH) ? "VAH" : TagLo(c, lastL2Lo) ? "L2 low" : TagLo(c, lastL3Lo) ? "L3 low" : TagLo(c, htfLB[c]) ? "HTF low" : TagLo(c, brkUp) ? "broken high retest" : "";
      string locHiWhy = l1LhHi ? "L1 LH (trend)" : stHi ? "SuperTrend line" : amdHiTag ? "AMD range edge" : obHi ? "Bear OB" : l1SweepHi ? "L1 high swept" : TagHi(c, cVAH) ? "VAH" : TagHi(c, cPOC) ? "POC" : TagHi(c, cVAL) ? "VAL" : TagHi(c, lastL2Hi) ? "L2 high" : TagHi(c, lastL3Hi) ? "L3 high" : TagHi(c, htfHB[c]) ? "HTF high" : TagHi(c, brkDn) ? "broken low retest" : "";

      if (locLoNow)
      {
         locLoBar = idx;
         locLoTxt = locLoWhy + " @ " + DoubleToString(l1HlLo ? pl : L[c], Digits);
         locLoExt = l1HlLo ? MathMin(pl, L[c]) : L[c];
      }
      if (locHiNow)
      {
         locHiBar = idx;
         locHiTxt = locHiWhy + " @ " + DoubleToString(l1LhHi ? ph : H[c], Digits);
         locHiExt = l1LhHi ? MathMax(ph, H[c]) : H[c];
      }

      // 7) Checklist Row 3: Trigger (Score & Classic / 2-of-3 / Any-1)
      bool ckPinB = (ChkTrigFilter != 2) && pinBullB[c];
      bool ckTlB  = (ChkTrigFilter != 1) && tlBrkUpB[c] && (!TlStOnly || stStateB[c] == 1);
      bool ckPinS = (ChkTrigFilter != 2) && pinBearB[c];
      bool ckTlS  = (ChkTrigFilter != 1) && tlBrkDnB[c] && (!TlStOnly || stStateB[c] == -1);

      bool prevPostAcc = amdPostB[c + 1];
      double prevAccLo = amdLoB[c + 1], prevAccHi = amdHiB[c + 1];
      bool scSwL = FreshSwLo(c, l2Lo_prev) || FreshSwLo(c, l3Lo_prev) || (prevPostAcc && FreshSwLo(c, prevAccLo));
      bool scSwS = FreshSwHi(c, l2Hi_prev) || FreshSwHi(c, l3Hi_prev) || (prevPostAcc && FreshSwHi(c, prevAccHi));
      if (scSwL) scSwBL = idx;
      if (scSwS) scSwBS = idx;

      bool ckRvB = scSwL || amdDUpB[c];
      bool ckRvS = scSwS || amdDDnB[c];
      if (ckPinB) tgPinL = idx;
      if (ckTlB)  tgTlL  = idx;
      if (ckRvB)  tgRvL  = idx;
      if (ckPinS) tgPinS = idx;
      if (ckTlS)  tgTlS  = idx;
      if (ckRvS)  tgRvS  = idx;

      // Pin -> TL combo location
      if (ChkPinTl && ckTlB && pinLoBar >= 0 && idx > pinLoBar && idx - pinLoBar <= ChkPinWin)
      {
         locLoBar = idx; locLoTxt = "bull pin -> TL up"; locLoExt = MathMin(pinLoExt, L[c]);
      }
      if (ChkPinTl && ckTlS && pinHiBar >= 0 && idx > pinHiBar && idx - pinHiBar <= ChkPinWin)
      {
         locHiBar = idx; locHiTxt = "bear pin -> TL down"; locHiExt = MathMax(pinHiExt, H[c]);
      }
      if (pinLoBar >= 0 && idx - pinLoBar <= ChkPinWin) pinLoExt = MathMin(pinLoExt, L[c]);
      if (pinHiBar >= 0 && idx - pinHiBar <= ChkPinWin) pinHiExt = MathMax(pinHiExt, H[c]);
      if (pinBullB[c]) { pinLoBar = idx; pinLoExt = L[c]; }
      if (pinBearB[c]) { pinHiBar = idx; pinHiExt = H[c]; }

      bool locLoOk = (locLoBar >= 0 && idx - locLoBar <= ChkWin);
      bool locHiOk = (locHiBar >= 0 && idx - locHiBar <= ChkWin);

      // Update 11 Score items
      bool scRevL = (ckTlB || amdDUpB[c]) && scSwBL >= 0 && (idx - scSwBL <= RevWin);
      bool scRevS = (ckTlS || amdDDnB[c]) && scSwBS >= 0 && (idx - scSwBS <= RevWin);
      if (scRevL) bRevL = idx;
      if (scRevS) bRevS = idx;
      if (ckTlB)  bTlL  = idx;
      if (ckTlS)  bTlS  = idx;
      if (pinBullB[c]) bPinL = idx;
      if (pinBearB[c]) bPinS = idx;
      if (amdDUpB[c])  bDL   = idx;
      if (amdDDnB[c])  bDS   = idx;
      if (amdMUpB[c])  bML   = idx;
      if (amdMDnB[c])  bMS   = idx;
      if (sweepBullB[c]) bSwL = idx;
      if (sweepBearB[c]) bSwS = idx;
      if (newL3) bL3L = idx;
      if (newH3) bL3S = idx;
      if (newL2 && !newL3) bL2L = idx;
      if (newH2 && !newH3) bL2S = idx;
      if (pl != EMPTY_VALUE && prvL1 != EMPTY_VALUE && pl > prvL1) bL1L = idx;
      if (ph != EMPTY_VALUE && prvH1 != EMPTY_VALUE && ph < prvH1) bL1S = idx;
      if (heavyB[c] && C[c] > O[c]) bVolL = idx;
      if (heavyB[c] && C[c] < O[c]) bVolS = idx;
      if (absorbB[c] && (C[c] - L[c] > H[c] - C[c])) bAbL = idx;
      if (absorbB[c] && (H[c] - C[c] > C[c] - L[c])) bAbS = idx;

      double scL = ScPts(idx, bRevL, WRev) + ScPts(idx, bTlL, WTl) + ScPts(idx, bPinL, WPin) + ScPts(idx, bDL, WD) + ScPts(idx, bML, WM) + ScPts(idx, bSwL, WSw) + ScPts(idx, bL3L, WL3) + ScPts(idx, bL2L, WL2) + ScPts(idx, bL1L, WL1) + ScPts(idx, bVolL, WScVol) + ScPts(idx, bAbL, WAbs);
      double scS = ScPts(idx, bRevS, WRev) + ScPts(idx, bTlS, WTl) + ScPts(idx, bPinS, WPin) + ScPts(idx, bDS, WD) + ScPts(idx, bMS, WM) + ScPts(idx, bSwS, WSw) + ScPts(idx, bL3S, WL3) + ScPts(idx, bL2S, WL2) + ScPts(idx, bL1S, WL1) + ScPts(idx, bVolS, WScVol) + ScPts(idx, bAbS, WAbs);
      double scTot = WRev + WTl + WPin + WD + WM + WSw + WL3 + WL2 + WL1 + WScVol + WAbs;
      int scTrgL = MathMax(MathMax(bRevL, bTlL), MathMax(bPinL, bDL));
      int scTrgS = MathMax(MathMax(bRevS, bTlS), MathMax(bPinS, bDS));

      bool useSc = (ChkRule == 0);
      bool scOkL = (scL >= ScMin && scS < scL * 0.5 && scTrgL >= 0 && locLoBar >= 0 && scTrgL >= locLoBar && idx - scTrgL <= ChkWin);
      bool scOkS = (scS >= ScMin && scL < scS * 0.5 && scTrgS >= 0 && locHiBar >= 0 && scTrgS >= locHiBar && idx - scTrgS <= ChkWin);

      int tgNeed = (ChkRule == 1) ? 2 : 1;
      int tgRvLx = (ChkRule == 3) ? -1 : tgRvL;
      int tgRvSx = (ChkRule == 3) ? -1 : tgRvS;
      int tgNL = (TgIn(idx, tgPinL) ? 1 : 0) + (TgIn(idx, tgTlL) ? 1 : 0) + (TgIn(idx, tgRvLx) ? 1 : 0);
      int tgNS = (TgIn(idx, tgPinS) ? 1 : 0) + (TgIn(idx, tgTlS) ? 1 : 0) + (TgIn(idx, tgRvSx) ? 1 : 0);
      int trgLoBar = tgNL >= tgNeed ? MathMax(TgIn(idx, tgPinL) ? tgPinL : -1, MathMax(TgIn(idx, tgTlL) ? tgTlL : -1, TgIn(idx, tgRvLx) ? tgRvLx : -1)) : -1;
      int trgHiBar = tgNS >= tgNeed ? MathMax(TgIn(idx, tgPinS) ? tgPinS : -1, MathMax(TgIn(idx, tgTlS) ? tgTlS : -1, TgIn(idx, tgRvSx) ? tgRvSx : -1)) : -1;

      bool trgLoOk = (ChkRule == 4) ? false : useSc ? (locLoOk && scOkL) : (locLoOk && tgNL >= tgNeed && trgLoBar >= locLoBar && idx - trgLoBar <= ChkWin);
      bool trgHiOk = (ChkRule == 4) ? false : useSc ? (locHiOk && scOkS) : (locHiOk && tgNS >= tgNeed && trgHiBar >= locHiBar && idx - trgHiBar <= ChkWin);

      // 8) Checklist Row 4: Stop & Multi-target R:R walk (only needed on recent bars)
      if (c <= 6)
      {
         int d = chkDir;
         bool locOk = (d == 1) ? locLoOk : (d == -1) ? locHiOk : false;
         bool trgOk = (d == 1) ? trgLoOk : (d == -1) ? trgHiOk : false;
         double chkLo4 = L[c], chkHi4 = H[c];
         for (int k = 0; k < 4 && c + k < nb; k++) { chkLo4 = MathMin(chkLo4, L[c + k]); chkHi4 = MathMax(chkHi4, H[c + k]); }
         double ext = (d == 1) ? (locLoOk && locLoExt != EMPTY_VALUE ? MathMin(locLoExt, chkLo4) : chkLo4)
                               : (locHiOk && locHiExt != EMPTY_VALUE ? MathMax(locHiExt, chkHi4) : chkHi4);
         double slC = (d == 1) ? ext - ATR[c] * PlanSlBuf : ext + ATR[c] * PlanSlBuf;
         double tv[10]; string tn[10]; int tCnt = 0;
         if (d == 1)
         {
            LvAdd(tv, tn, tCnt, lastL1Hi, "L1 high");
            LvAdd(tv, tn, tCnt, lastL2Hi, "L2 high");
            LvAdd(tv, tn, tCnt, lastL3Hi, "L3 high");
            LvAdd(tv, tn, tCnt, htfHB[c], "HTF high");
            LvAdd(tv, tn, tCnt, cVAH, "VAH");
            LvAdd(tv, tn, tCnt, pdh, "PDH");
         }
         else
         {
            LvAdd(tv, tn, tCnt, lastL1Lo, "L1 low");
            LvAdd(tv, tn, tCnt, lastL2Lo, "L2 low");
            LvAdd(tv, tn, tCnt, lastL3Lo, "L3 low");
            LvAdd(tv, tn, tCnt, htfLB[c], "HTF low");
            LvAdd(tv, tn, tCnt, cVAL, "VAL");
            LvAdd(tv, tn, tCnt, pdl, "PDL");
         }
         double risk = MathAbs(C[c] - slC);
         double tgt = EMPTY_VALUE; string tgtN = "-";
         double pxRef = (d == 1) ? C[c] + ATR[c] * 0.3 : C[c] - ATR[c] * 0.3;
         if (d != 0 && risk > 0)
         {
            for (int step = 0; step < 4; step++)
            {
               double tX = EMPTY_VALUE; string tXn = "-";
               bool found = (d == 1) ? FindAbove(tv, tn, tCnt, pxRef, tX, tXn) : FindBelow(tv, tn, tCnt, pxRef, tX, tXn);
               if (!found) break;
               tgt = tX;
               tgtN = tXn + (step > 0 ? " (next)" : "");
               if (MathAbs(tX - C[c]) / risk >= ChkMinRR) break;
               pxRef = (d == 1) ? tX + Point : tX - Point;
            }
         }
         double rr = (d == 0 || tgt == EMPTY_VALUE || risk <= 0) ? 0 : MathAbs(tgt - C[c]) / risk;
         bool rrOk = (rr >= ChkMinRR);
         bool allOk = (d != 0 && locOk && trgOk && rrOk);
         bool goNew = (allOk && d != goPrevDir);
         goPrevDir = allOk ? d : 0;

         if (c == 1)
         {
            string scTxL = ScTx(idx, bRevL, WRev, "REV") + ScTx(idx, bTlL, WTl, "TL") + ScTx(idx, bPinL, WPin, "Pin") + ScTx(idx, bDL, WD, "D") + ScTx(idx, bML, WM, "M") + ScTx(idx, bSwL, WSw, "Sweep") + ScTx(idx, bL3L, WL3, "L3") + ScTx(idx, bL2L, WL2, "L2") + ScTx(idx, bL1L, WL1, "L1") + ScTx(idx, bVolL, WScVol, "Vol") + ScTx(idx, bAbL, WAbs, "Absorb");
            string scTxS = ScTx(idx, bRevS, WRev, "REV") + ScTx(idx, bTlS, WTl, "TL") + ScTx(idx, bPinS, WPin, "Pin") + ScTx(idx, bDS, WD, "D") + ScTx(idx, bMS, WM, "M") + ScTx(idx, bSwS, WSw, "Sweep") + ScTx(idx, bL3S, WL3, "L3") + ScTx(idx, bL2S, WL2, "L2") + ScTx(idx, bL1S, WL1, "L1") + ScTx(idx, bVolS, WScVol, "Vol") + ScTx(idx, bAbS, WAbs, "Absorb");
            string trgLoTxt = "score " + DoubleToString(scL, 1) + "/" + DoubleToString(scTot, 0) + " (min " + DoubleToString(ScMin, 1) + "): " + scTxL + "| opp " + DoubleToString(scS, 1);
            string trgHiTxt = "score " + DoubleToString(scS, 1) + "/" + DoubleToString(scTot, 0) + " (min " + DoubleToString(ScMin, 1) + "): " + scTxS + "| opp " + DoubleToString(scL, 1);

            chkDirNow = d;
            ckO1 = (d != 0); ckO2 = locOk; ckO3 = trgOk; ckO4 = rrOk; ckGo = allOk;
            ckT1 = "HTF " + (htfDirB[1] == 1 ? "UP" : htfDirB[1] == -1 ? "DN" : "-") + "  ST " + (stStateB[1] == 1 ? "UP" : "DN") + "  AMD " + (amdStateB[1] == 1 ? "UP" : amdStateB[1] == -1 ? "DN" : "-") + "  (need 2/3)";
            ckT2 = (d == 1) ? (locLoOk ? locLoTxt + " (" + IntegerToString(idx - locLoBar) + "b ago)" : "no support tagged in last " + IntegerToString(ChkWin) + "b")
                 : (d == -1) ? (locHiOk ? locHiTxt + " (" + IntegerToString(idx - locHiBar) + "b ago)" : "no resistance tagged in last " + IntegerToString(ChkWin) + "b") : "-";
            ckT3 = (d == 1) ? trgLoTxt : (d == -1) ? trgHiTxt : trgLoTxt;
            ckT4 = (d == 0) ? "-" : "SL " + DoubleToString(slC, Digits) + "  TP " + (tgt == EMPTY_VALUE ? "-" : DoubleToString(tgt, Digits) + " (" + tgtN + ")") + "  R:R " + DoubleToString(rr, 1);
            ckRes = allOk ? ((d == 1 ? "BUY allowed @ " : "SELL allowed @ ") + DoubleToString(C[1], Digits) + "  SL " + DoubleToString(slC, Digits) + "  TP " + DoubleToString(tgt, Digits)) : "NO TRADE - waiting";

            if (goNew && tgt != EMPTY_VALUE)
            {
               sigChkFire = true; sigChkDir = d; sigChkSL = slC; sigChkTP = tgt;
               sigChkWhy = (d == 1 ? trgLoTxt : trgHiTxt);
            }
         }
      }

      // 9) REV Setup (True liquidity sweep -> TL break or AMD D up/down within RevWin bars)
      double amdLoLv = amdPostB[c + 1] ? amdLoB[c + 1] : EMPTY_VALUE;
      double amdHiLv = amdPostB[c + 1] ? amdHiB[c + 1] : EMPTY_VALUE;
      bool rvSwLo = (!RevNoL1 && FreshSwLo(c, l1Lo_prev)) || FreshSwLo(c, l2Lo_prev) || FreshSwLo(c, l3Lo_prev) || FreshSwLo(c, amdLoLv);
      bool rvSwHi = (!RevNoL1 && FreshSwHi(c, l1Hi_prev)) || FreshSwHi(c, l2Hi_prev) || FreshSwHi(c, l3Hi_prev) || FreshSwHi(c, amdHiLv);
      if (rvSwLo) rvLoBar = idx;
      if (rvSwHi) rvHiBar = idx;

      bool rvSigL = (tlBrkUpB[c] || (RevDTrig && amdDUpB[c])) && rvLoBar >= 0 && (idx - rvLoBar <= RevWin);
      bool rvSigS = (tlBrkDnB[c] || (RevDTrig && amdDDnB[c])) && rvHiBar >= 0 && (idx - rvHiBar <= RevWin);

      if (c == 1 && ShowRev && ChkAddRev && (rvSigL || rvSigS))
      {
         int rd = rvSigL ? 1 : -1;
         if (!RevRequireHtf || htfDirB[1] != -rd)
         {
            // Compute sweep extreme strictly within the active sweep window (c .. c + (idx - rvBar))
            int span = (rd == 1) ? MathMin(RevWin, idx - rvLoBar) : MathMin(RevWin, idx - rvHiBar);
            double rvExt = (rd == 1) ? L[1] : H[1];
            for (int k = 0; k <= span && 1 + k < nb; k++)
               rvExt = (rd == 1) ? MathMin(rvExt, L[1 + k]) : MathMax(rvExt, H[1 + k]);

            bool big = (H[1] - L[1]) > ATR[1] * RevBigAtr;
            double re = big ? (H[1] + L[1]) / 2.0 : C[1];
            double rSl = (rd == 1) ? rvExt - ATR[1] * PlanSlBuf : rvExt + ATR[1] * PlanSlBuf;
            double rRk = MathAbs(re - rSl);
            double tvR[12]; string tnR[12]; int rCnt = 0;
            double curAmdHi = amdPostB[1] ? amdHiB[1] : EMPTY_VALUE;
            double curAmdLo = amdPostB[1] ? amdLoB[1] : EMPTY_VALUE;
            if (rd == 1)
            {
               LvAdd(tvR, tnR, rCnt, lastL1Hi, "L1 high");
               LvAdd(tvR, tnR, rCnt, lastL2Hi, "L2 high");
               LvAdd(tvR, tnR, rCnt, lastL3Hi, "L3 high");
               LvAdd(tvR, tnR, rCnt, htfHB[1], "HTF high");
               LvAdd(tvR, tnR, rCnt, cVAH, "VAH");
               LvAdd(tvR, tnR, rCnt, cPOC, "POC");
               LvAdd(tvR, tnR, rCnt, pdh, "PDH");
               LvAdd(tvR, tnR, rCnt, curAmdHi, "AMD high");
            }
            else
            {
               LvAdd(tvR, tnR, rCnt, lastL1Lo, "L1 low");
               LvAdd(tvR, tnR, rCnt, lastL2Lo, "L2 low");
               LvAdd(tvR, tnR, rCnt, lastL3Lo, "L3 low");
               LvAdd(tvR, tnR, rCnt, htfLB[1], "HTF low");
               LvAdd(tvR, tnR, rCnt, cVAL, "VAL");
               LvAdd(tvR, tnR, rCnt, cPOC, "POC");
               LvAdd(tvR, tnR, rCnt, pdl, "PDL");
               LvAdd(tvR, tnR, rCnt, curAmdLo, "AMD low");
            }
            double tpR = EMPTY_VALUE; string tpRN = "-";
            double pr = (rd == 1) ? re + RevMinTp : re - RevMinTp;
            if (rRk > 0)
            {
               for (int step = 0; step < 6; step++)
               {
                  double ux = EMPTY_VALUE; string uxn = "-";
                  bool found = (rd == 1) ? FindAbove(tvR, tnR, rCnt, pr - Point, ux, uxn) : FindBelow(tvR, tnR, rCnt, pr + Point, ux, uxn);
                  if (!found) break;
                  if (MathAbs(ux - re) / rRk >= RevMinRR) { tpR = ux; tpRN = uxn; break; }
                  pr = (rd == 1) ? ux + Point : ux - Point;
               }
            }
            if (!big && tpR != EMPTY_VALUE && !(sigChkFire && sigChkDir == rd))
            {
               sigRevFire = true; sigRevDir = rd; sigRevSL = rSl; sigRevTP = tpR;
               sigRevWhy = "REV (" + tpRN + ")";
            }
         }
      }
   }
}

//==================== LEGACY SCORE & PLAN STOP ====================
void LegacyScore()
{
   int base = WStruct + WAmd + WVp + WSt + WVol + WInst;
   int wTl = (int)MathRound(base * TlWeightPct / (100.0 - TlWeightPct));
   int tlVote = (tlDir != 0 && tlAge <= TlValidBars) ? tlDir : 0;
   maxScore = base + wTl;
   score = htfDir * WStruct + amdState * WAmd + vpState * WVp + stState * WSt + volState * WVol + instState * WInst + tlVote * wTl;
   scorePct = maxScore > 0 ? 100.0 * score / maxScore : 0;
}
double LegacyPlanStop(int dir, double entryPx)
{
   double a = ATR[1], best = EMPTY_VALUE;
   double lv[4]; lv[0] = dir == 1 ? lastL2Lo : lastL2Hi; lv[1] = dir == 1 ? lastL3Lo : lastL3Hi; lv[2] = dir == 1 ? htfL : htfH; lv[3] = dir == 1 ? lastL1Lo : lastL1Hi;
   for (int k = 0; k < 4; k++)
   {
      if (lv[k] == EMPTY_VALUE) continue;
      if (dir == 1 && lv[k] < entryPx - a * 0.3 && (best == EMPTY_VALUE || lv[k] > best)) best = lv[k];
      if (dir == -1 && lv[k] > entryPx + a * 0.3 && (best == EMPTY_VALUE || lv[k] < best)) best = lv[k];
   }
   if (best == EMPTY_VALUE) return dir == 1 ? entryPx - a * 1.5 : entryPx + a * 1.5;
   return dir == 1 ? best - a * PlanSlBuf : best + a * PlanSlBuf;
}

//==================== TRADING & EXECUTION ====================
int CountOpen(int &dirOut)
{
   int n = 0; dirOut = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
      if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() <= OP_SELL)
      {
         n++; dirOut = OrderType() == OP_BUY ? 1 : -1;
      }
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
   if (step > 0) lots = MathFloor(lots / step) * step;
   return NormalizeDouble(MathMax(mn, MathMin(mx, lots)), 2);
}
void MarkSig(int dir, string tag)
{
   if (!DrawObjects) return;
   string nm = "SL3_SIG_" + IntegerToString((long)T[1]) + "_" + tag;
   if (ObjectFind(0, nm) >= 0) return;
   ObjectCreate(0, nm, OBJ_ARROW, 0, T[1], dir == 1 ? L[1] - ATR[1] * 0.6 : H[1] + ATR[1] * 0.6);
   ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, dir == 1 ? 233 : 234);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, dir == 1 ? clrGold : clrOrangeRed);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
}

void ExecuteSigOrder(int dir, double rawSL, double rawTP, string commentTag)
{
   int odir = 0; int n = CountOpen(odir);
   if (CloseOnOpposite && n > 0 && dir != odir) { CloseAll(); n = CountOpen(odir); }
   if (BlockOppositeOpen && n > 0 && dir != odir) { lastMsg = "SIG skipped: opposite trade already open"; return; }
   if (n >= MaxOpenTrades) { lastMsg = "SIG skipped: MaxOpenTrades (" + IntegerToString(MaxOpenTrades) + ") reached"; return; }
   double lastP = 0; int streak = LossStreakToday(lastP);
   if (MaxLossStreakDay > 0 && streak >= MaxLossStreakDay) { lastMsg = "SIG skipped: loss streak " + IntegerToString(streak); return; }
   if (MaxTradesPerDay > 0 && TradesToday() >= MaxTradesPerDay) { lastMsg = "SIG skipped: daily limit reached"; return; }
   if (!TradeTimeOK(TimeCurrent())) { lastMsg = "SIG skipped: outside trading hours"; return; }

   RefreshRates();
   double e = (dir == 1) ? Ask : Bid;
   double minD = MathMax(MarketInfo(Symbol(), MODE_STOPLEVEL) * Point, Point * 10);
   double ordSL = rawSL;
   if (dir == 1 && ordSL >= e - minD) ordSL = e - MathMax(minD, ATR[1] * 0.5);
   if (dir == -1 && ordSL <= e + minD) ordSL = e + MathMax(minD, ATR[1] * 0.5);
   double dist = MathAbs(e - ordSL);
   if (MaxSlAtr > 0 && dist > MaxSlAtr * ATR[1]) { lastMsg = "SIG skipped: SL too far (" + DoubleToString(dist / ATR[1], 1) + " ATR)"; return; }
   if (MaxSlUsd > 0 && dist > MaxSlUsd) { lastMsg = "SIG skipped: SL $" + DoubleToString(dist, 1) + " > MaxSlUsd $" + DoubleToString(MaxSlUsd, 1); return; }
   double minReq = MathMax(MinSlUsd, MinSlAtr > 0 ? MinSlAtr * ATR[1] : 0.0);
   if (minReq > 0 && dist < minReq)
   {
      if (PadMinSl)
      {
         ordSL = (dir == 1) ? e - minReq : e + minReq;
         dist = MathAbs(e - ordSL);
      }
      else { lastMsg = "SIG skipped: SL $" + DoubleToString(dist, 1) + " < MinSlUsd $" + DoubleToString(minReq, 1); return; }
   }
   if (WideSlUsd > 0 && dist >= WideSlUsd && n >= MaxOpenWideSl) { lastMsg = "SIG skipped: Wide SL $" + DoubleToString(dist, 1) + " cap (" + IntegerToString(MaxOpenWideSl) + " open)"; return; }

   double ordTP = 0;
   if (ExitModel == 1 && rawTP != EMPTY_VALUE && rawTP > 0)
   {
      ordTP = rawTP;
      if (dir == 1 && ordTP <= e + minD) ordTP = e + dist * ChkMinRR;
      if (dir == -1 && ordTP >= e - minD) ordTP = e - dist * ChkMinRR;
   }
   else if (ExitModel == 2)
   {
      ordTP = (dir == 1) ? e + TpR * dist : e - TpR * dist;
   }

   double lots = LotFor(dist);
   double tv = MarketInfo(Symbol(), MODE_TICKVALUE), ts = MarketInfo(Symbol(), MODE_TICKSIZE);
   double riskPct = (tv > 0 && ts > 0 && AccountEquity() > 0) ? dist / ts * tv * lots / AccountEquity() * 100.0 : 0;
   if (MaxRiskPct > 0 && riskPct > MaxRiskPct) { lastMsg = "SIG skipped: real risk " + DoubleToString(riskPct, 1) + "% > MaxRiskPct"; return; }

   int tk = OrderSend(Symbol(), dir == 1 ? OP_BUY : OP_SELL, lots, e, SlippagePts, NormalizeDouble(ordSL, Digits), NormalizeDouble(ordTP, Digits), commentTag, Magic, 0, dir == 1 ? clrLime : clrRed);
   if (tk > 0)
   {
      double rDist = MathAbs(e - ordSL);
      if (OrderSelect(tk, SELECT_BY_TICKET)) rDist = MathAbs(OrderOpenPrice() - ordSL);
      GlobalVariableSet("SL3_R_" + IntegerToString(tk), rDist);
      double l1Rng = (lastL1Hi != EMPTY_VALUE && lastL1Lo != EMPTY_VALUE) ? MathAbs(lastL1Hi - lastL1Lo) : 999.0;
      double atr1  = (ATR[1] > 0) ? ATR[1] : 10.0;
      bool entryShortSwing = (l1Rng < 1.8 * atr1 && rDist < 1.35 * atr1);
      bool entryStrong     = (!entryShortSwing && htfDir == dir && stState == dir && (amdState == dir || MathAbs(scorePct) >= 70.0));
      int  entryRegime     = entryStrong ? 2 : (entryShortSwing ? 0 : 1); // 2=Strong, 1=Normal, 0=Range/ShortSwing
      GlobalVariableSet("SL3_REG_" + IntegerToString(tk), entryRegime);
      if (LogTradeRegime)
      {
         string regStr = (entryRegime == 2) ? "STRONG_TREND" : (entryRegime == 0 ? "RANGE_SHORT" : "NORMAL_TREND");
         Print("[SL3-OPEN] #", tk, (dir == 1 ? " BUY " : " SELL "), DoubleToString(lots, 2),
               " | Reg=", regStr,
               " | Score=", DoubleToString(scorePct, 0), "%",
               " | SL$=", DoubleToString(rDist, 1), " (", DoubleToString(rDist / atr1, 2), "xATR)",
               " | ATR=", DoubleToString(atr1, 1),
               " | L1Rng$=", DoubleToString(l1Rng, 1),
               " | HTF=", htfDir, " ST=", stState, " AMD=", amdState, " VP=", vpState, " VOL=", volState);
      }
      MarkSig(dir, commentTag);
      lastMsg = commentTag + (dir == 1 ? " BUY " : " SELL ") + DoubleToString(lots, 2) + " @ " + DoubleToString(e, Digits) + " SL " + DoubleToString(ordSL, Digits) + " TP " + DoubleToString(ordTP, Digits);
   }
   else lastMsg = "OrderSend error " + IntegerToString(GetLastError());
}

void TryEntry()
{
   if (EngineMode == 0 || EngineMode == 2)
   {
      if (sigChkFire) ExecuteSigOrder(sigChkDir, sigChkSL, sigChkTP, "SIG-CHK");
      if (sigRevFire) ExecuteSigOrder(sigRevDir, sigRevSL, sigRevTP, "SIG-REV");
      if (EngineMode == 0) return;
   }
   int dir = 0;
   bool gate = (tlDir != 0 && tlAge <= TlValidBars);
   if (gate && tlDir == 1 && scorePct >= MinScorePct && (!RequireHtf || htfDir == 1)) dir = 1;
   if (gate && tlDir == -1 && scorePct <= -MinScorePct && (!RequireHtf || htfDir == -1)) dir = -1;
   if (dir == 0) return;
   RefreshRates();
   double e = (dir == 1) ? Ask : Bid;
   double legSL = LegacyPlanStop(dir, e);
   double legTP = (dir == 1) ? e + TpR * MathAbs(e - legSL) : e - TpR * MathAbs(e - legSL);
   ExecuteSigOrder(dir, legSL, legTP, "SL3-Legacy");
}

int TradesToday()
{
   datetime d0 = iTime(NULL, PERIOD_D1, 0); int n = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
      if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() <= OP_SELL && OrderOpenTime() >= d0 && StringFind(OrderComment(), "from #") < 0) n++;
   for (int i = OrdersHistoryTotal() - 1; i >= 0; i--)
      if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() <= OP_SELL && OrderOpenTime() >= d0 && StringFind(OrderComment(), "from #") < 0) n++;
   return n;
}
int LossStreakToday(double &lastProfit)
{
   datetime d0 = iTime(NULL, PERIOD_D1, 0); int streak = 0; lastProfit = 0;
   int idx[]; datetime ct[]; int n = 0;
   ArrayResize(idx, OrdersHistoryTotal()); ArrayResize(ct, OrdersHistoryTotal());
   for (int i = 0; i < OrdersHistoryTotal(); i++)
      if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() <= OP_SELL) { idx[n] = i; ct[n] = OrderCloseTime(); n++; }
   bool done = false;
   for (int k = 0; k < n && !done; k++)
   {
      int best = -1; datetime bt = 0;
      for (int j = 0; j < n; j++) if (idx[j] >= 0 && ct[j] > bt) { bt = ct[j]; best = j; }
      if (best < 0) break;
      if (OrderSelect(idx[best], SELECT_BY_POS, MODE_HISTORY))
      {
         double p = OrderProfit() + OrderSwap() + OrderCommission();
         if (k == 0) lastProfit = p;
         if (OrderCloseTime() < d0) done = true;
         else if (p < -0.01) streak++;
         else done = true;
      }
      idx[best] = -1;
   }
   return streak;
}
void CloseAll()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
      if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() <= OP_SELL)
         if (!OrderClose(OrderTicket(), OrderLots(), OrderType() == OP_BUY ? Bid : Ask, SlippagePts)) Print("close err ", GetLastError());
}
int lastHistTotal = -1;
datetime lastWinCloseBuy = 0, lastWinCloseSell = 0;
datetime lastWinOpenBuy  = 0, lastWinOpenSell  = 0;

void UpdateWinHistoryCache()
{
   int hTot = OrdersHistoryTotal();
   if (hTot == lastHistTotal) return;
   int startIdx = (lastHistTotal >= 0 && hTot > lastHistTotal) ? lastHistTotal : MathMax(0, hTot - 20);
   for (int i = startIdx; i < hTot; i++)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() <= OP_SELL)
      {
         double netP = OrderProfit() + OrderSwap() + OrderCommission();
         double tp = OrderTakeProfit();
         bool hitTp = (tp > 0 && MathAbs(OrderClosePrice() - tp) <= Point * 80);
         if (netP > 0 && hitTp)
         {
            if (OrderType() == OP_BUY  && OrderCloseTime() > lastWinCloseBuy)  { lastWinCloseBuy  = OrderCloseTime(); lastWinOpenBuy  = OrderOpenTime(); }
            if (OrderType() == OP_SELL && OrderCloseTime() > lastWinCloseSell) { lastWinCloseSell = OrderCloseTime(); lastWinOpenSell = OrderOpenTime(); }
         }
      }
   }
   lastHistTotal = hTot;
}

void Manage(bool newBar)
{
   UpdateWinHistoryCache();
   double minD = MathMax(MarketInfo(Symbol(), MODE_STOPLEVEL) * Point, Point * 10);
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS) || OrderSymbol() != Symbol() || OrderMagicNumber() != Magic || OrderType() > OP_SELL) continue;
      RefreshRates();
      int tk = OrderTicket();
      bool buy = OrderType() == OP_BUY; double op = OrderOpenPrice(), curSL = OrderStopLoss(), px = buy ? Bid : Ask;
      string key = "SL3_R_" + IntegerToString(tk);
      double R = GlobalVariableCheck(key) ? GlobalVariableGet(key) : MathAbs(op - curSL);
      if (R <= 0) continue;
      double move = buy ? (px - op) : (op - px);
      bool atBE = buy ? curSL >= op : (curSL > 0 && curSL <= op);
      double candSL = curSL;
      double stepMin = MathMax(Point * 10, TrailStepR * R);

      // 1) Optional Break-Even when BeTriggerR > 0
      if (!atBE && BeTriggerR > 0 && move >= BeTriggerR * R)
      {
         double beSL = buy ? op + BeLockUsd : op - BeLockUsd;
         if (buy && beSL > candSL) candSL = beSL;
         if (!buy && (candSL == 0 || beSL < candSL)) candSL = beSL;
      }

      // 2) Sibling-TP Profit Lock: only when a sibling in the SAME cluster (opened within 2h) hits full TP and this trade is >= 1.10R in profit
      datetime lastSibWin  = buy ? lastWinCloseBuy : lastWinCloseSell;
      datetime lastSibOpen = buy ? lastWinOpenBuy  : lastWinOpenSell;
      if (LockOnSiblingTP && lastSibWin >= OrderOpenTime() && MathAbs((double)(OrderOpenTime() - lastSibOpen)) <= 7200 && move >= 1.10 * R)
      {
         double lockDist = SiblingLockR * R;
         double sibSL = buy ? op + lockDist : op - lockDist;
         if (buy && sibSL > candSL) candSL = sibSL;
         if (!buy && (candSL == 0 || sibSL < candSL)) candSL = sibSL;
      }

      // 3) Dynamic Regime-Adaptive or Fixed R-Based Trailing Stop
      // Uses persistent Entry Regime (2=Strong, 1=Normal, 0=Range) so Strong Trend trades are NOT prematurely
      // downgraded when tlAge > 4 or on single low-volume candles; only downgrades to Range/Tight if live
      // SuperTrend + H1 structure flip against the trade, or if L1 swings compress while AMD & VP are both flat.
      double effStartR = TrailStartR;
      double effDistR  = TrailDistR;
      int d = buy ? 1 : -1;
      bool isRangeOrWeak = false;
      string regKey = "SL3_REG_" + IntegerToString(tk);
      int entryReg = GlobalVariableCheck(regKey) ? (int)GlobalVariableGet(regKey) : 1;
      if (DynamicTrail)
      {
         double atrNow    = (ATR[1] > 0) ? ATR[1] : 10.0;
         bool shortSwings = (lastL1Hi != EMPTY_VALUE && lastL1Lo != EMPTY_VALUE && MathAbs(lastL1Hi - lastL1Lo) < 1.8 * atrNow);
         bool hardFlip    = (stState == -d && htfDir == -d); // both M15 SuperTrend and H1 structure flipped against trade
         bool softFlipChop= (stState == -d && amdState == 0 && vpState == 0 && shortSwings);
         isRangeOrWeak    = (entryReg == 0 || hardFlip || softFlipChop);
         bool strongTrend = (entryReg == 2 && !isRangeOrWeak && stState != -d);
         if (strongTrend)        { effStartR = DynStrongStartR; effDistR = DynStrongDistR; }
         else if (isRangeOrWeak) { effStartR = DynRangeStartR;  effDistR = DynRangeDistR;  }
         else                    { effStartR = DynNormStartR;   effDistR = DynNormDistR;   }
      }
      if (effStartR > 0 && effDistR > 0 && move >= effStartR * R)
      {
         double trSL = buy ? px - effDistR * R : px + effDistR * R;
         if (buy && trSL > candSL) candSL = trSL;
         if (!buy && (candSL == 0 || trSL < candSL)) candSL = trSL;
      }

      // 4) Optional L1 Swing Structural Trail (only in Range/Weak regime or after effStartR)
      if (TrailByL1 && newBar && ((isRangeOrWeak && move >= 1.00 * R) || (effStartR > 0 && move >= effStartR * R)))
      {
         double trL1 = buy ? lastL1Lo - ATR[1] * TrailBufAtr : lastL1Hi + ATR[1] * TrailBufAtr;
         if (buy && lastL1Lo != EMPTY_VALUE && trL1 > op && trL1 > candSL) candSL = trL1;
         if (!buy && lastL1Hi != EMPTY_VALUE && trL1 < op && (candSL == 0 || trL1 < candSL)) candSL = trL1;
      }

      // Apply candidate SL if it improves curSL by at least stepMin
      candSL = NormalizeDouble(candSL, Digits);
      if (buy && candSL > curSL + stepMin && candSL <= px - minD)
         if (OrderModify(tk, op, candSL, OrderTakeProfit(), 0)) curSL = candSL;
      if (!buy && (curSL == 0 || candSL < curSL - stepMin) && candSL >= px + minD)
         if (OrderModify(tk, op, candSL, OrderTakeProfit(), 0)) curSL = candSL;

      if (ExitModel != 0) continue;   // Below is only for ExitModel 0 (Half at PartialR + L1 trail)
      atBE = buy ? curSL >= op : (curSL > 0 && curSL <= op);
      if (!atBE && move >= PartialR * R)
      {
         double mn = MarketInfo(Symbol(), MODE_MINLOT), step = MarketInfo(Symbol(), MODE_LOTSTEP);
         double half = step > 0 ? MathFloor(OrderLots() / 2.0 / step) * step : OrderLots() / 2.0;
         if (OrderModify(tk, op, NormalizeDouble(op, Digits), OrderTakeProfit(), 0)) {}
         if (half >= mn && OrderLots() - half >= mn)
            if (!OrderClose(tk, NormalizeDouble(half, 2), px, SlippagePts)) Print("partial err ", GetLastError());
         continue;
      }
      if (atBE && newBar)
      {
         double tr = buy ? lastL1Lo - ATR[1] * TrailBufAtr : lastL1Hi + ATR[1] * TrailBufAtr;
         if (lastL1Lo != EMPTY_VALUE && buy && tr > curSL && tr < px - minD)
            if (!OrderModify(tk, op, NormalizeDouble(tr, Digits), OrderTakeProfit(), 0)) Print("trail err ", GetLastError());
         if (lastL1Hi != EMPTY_VALUE && !buy && tr < curSL && tr > px + minD)
            if (!OrderModify(tk, op, NormalizeDouble(tr, Digits), OrderTakeProfit(), 0)) Print("trail err ", GetLastError());
      }
   }
}

//==================== DASHBOARD PANEL ====================
void Panel()
{
   if (!ShowPanel) return;
   int odir = 0; int nOpen = CountOpen(odir);
   string dn = chkDirNow == 1 ? "LONG" : chkDirNow == -1 ? "SHORT" : "NONE";
   string t = "SL3 SIG EA v2.1 (Pine Checklist + Score + REV)  |  " + Symbol() + " M" + IntegerToString(Period()) + "\n";
   t += "ENTRY CHECKLIST  |  candidate: " + dn + "  |  close " + DoubleToString(C[1], Digits) + "  |  open trades: " + IntegerToString(nOpen) + "/" + IntegerToString(MaxOpenTrades) + "\n";
   t += "1 Direction     : [" + (ckO1 ? "OK" : "NO") + "]  " + ckT1 + "\n";
   t += "2 Location      : [" + (ckO2 ? "OK" : "NO") + "]  " + ckT2 + "\n";
   t += "3 Trigger       : [" + (ckO3 ? "OK" : "NO") + "]  " + ckT3 + "\n";
   t += "4 Stop / target : [" + (ckO4 ? "OK" : "NO") + "]  " + ckT4 + "\n";
   t += "RESULT          : [" + (ckGo ? "GO" : "WAIT") + "]  " + ckRes + "\n";
   t += "Modules         : AMD=" + amdTxt + "  |  VP POC=" + DoubleToString(vpPOC, Digits) + " VAH=" + DoubleToString(vpVAH, Digits) + " VAL=" + DoubleToString(vpVAL, Digits) + "  |  TL=" + tlTxt + "\n";
   t += "Last Action     : " + lastMsg;
   Comment(t);
}

//==================== EVENTS ====================
int OnInit()
{
   lastHistTotal = -1;
   lastWinCloseBuy = 0; lastWinCloseSell = 0;
   lastWinOpenBuy  = 0; lastWinOpenSell  = 0;
   if (Period() != PERIOD_M15) Print("SL3 SIG EA: designed for M15");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r)
{
   Comment("");
   ObjectDelete(0, "SL3_TL_R");
   ObjectDelete(0, "SL3_TL_S");
}
void OnTick()
{
   if (Bars < 300) return;
   bool newBar = Time[0] != lastBar;
   if (newBar)
   {
      lastBar = Time[0];
      LoadBars();
      HtfStructure();
      SuperTrend();
      VolumeProfile();
      VolumeVote();
      Amd();
      Trendlines();
      PinBars();
      RunSigEngine();
      LegacyScore();
      TryEntry();
   }
   Manage(newBar);
   Panel();
}
