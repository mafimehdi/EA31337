//+------------------------------------------------------------------+
//|                                                 HarmonicLab.mq4  |
//|  Logic-faithful MT4 port of TradingView "HARMONIC Lab" (v6).     |
//|  Visual drawing, panels, prediction outlines and colour palettes |
//|  are omitted. Detection, lifecycle, alerts and zone confluence   |
//|  follow the Pine script without lookahead.                       |
//|                                                                  |
//|  Signals fire on confirmed bar close only. History is replayed   |
//|  on init so live state matches the indicator. Orders are opened  |
//|  only on Entry transitions after replay (and throughout tests).  |
//+------------------------------------------------------------------+
#property copyright "Harmonic Lab MT4 port"
#property link      ""
#property version   "1.02"
#property strict

#define HL_NA       EMPTY_VALUE
#define HL_MAX_SWING 20
#define HL_SEEN_CAP  2048
#define HL_RULES     22
#define HL_SCALES    3

bool   HlNa(const double v) { return (v == HL_NA); }

//====================================================================
// Inputs — logic-affecting. Defaults = M15 Active (v1.02, after XAUUSD
// backtest: the v1.01 strict pack produced only 7 trades in 9 months).
// See HarmonicLab/M15_COMPATIBILITY.md. Visual-only inputs are not ported.
//====================================================================

enum ENUM_HL_DMODE   { HL_DMODE_DEVELOPING=0, HL_DMODE_CONFIRMED=1 };
enum ENUM_HL_DIR     { HL_DIR_BOTH=0, HL_DIR_LONG=1, HL_DIR_SHORT=2 };
enum ENUM_HL_LBASIS  { HL_LB_STANDARD=0, HL_LB_LEGACY=1, HL_LB_CD=2, HL_LB_AD=3 };
enum ENUM_HL_KEEP    { HL_KEEP_T1=0, HL_KEEP_T2=1 };
enum ENUM_HL_ENTRY   { HL_ENTRY_CLOSE=0, HL_ENTRY_TOUCH=1, HL_ENTRY_CANDLE=2 };
enum ENUM_HL_STOPM   { HL_STOP_ZONE=0, HL_STOP_MANUAL=1, HL_STOP_BE=2, HL_STOP_TRAIL=3 };
enum ENUM_HL_SRC     { HL_SRC_CLOSE=0, HL_SRC_HL=1 };
enum ENUM_HL_OUTSIDE { HL_OUT_BOTH=0, HL_OUT_CONTINUE=1, HL_OUT_OPPOSITE=2 };
enum ENUM_HL_SWING   { HL_SWING_ROLLING=0, HL_SWING_PIVOT=1 };
enum ENUM_HL_TRAIL   { HL_TRAIL_ENTRY=0, HL_TRAIL_T1=1 };
enum ENUM_HL_TREND   { HL_TREND_OFF=0, HL_TREND_EMA=1, HL_TREND_SMA=2 };
enum ENUM_HL_ALERT   { HL_ALERT_TEXT=0, HL_ALERT_JSON=1 };
enum ENUM_HL_LOTS    { HL_LOT_FIXED=0, HL_LOT_RISK=1 };

// 01 Detection — M15 Active (v1.02). Strict pack is HarmonicLab_M15_STRICT.set
input int            InpDepth          = 8;                 // Minimum ZigZag Period (M15: 2h; 2x/3x via multiscale)
input ENUM_HL_DMODE  InpDMode          = HL_DMODE_DEVELOPING;
input int            InpConfirmBars    = 2;                 // used if swing = confirmed pivots
input bool           InpMultiscale     = true;              // 1x/2x/3x depth on the same M15 chart
input bool           InpSearchNested   = true;
input int            InpCandidateLimit = 40;
input double         InpErrorPct       = 8.0;               // original band; 6% starved gold M15
input int            InpMinSize        = 24;                // 6h floor (was 36 / 9h)
input int            InpMaxSize        = 160;               // 40h
input double         InpMinHeight      = 0.12;              // % of D; gold ~$3–5, FX ~12 pips
input int            InpMinCD          = 2;                 // 30m C–D
input ENUM_HL_DIR    InpDirection      = HL_DIR_BOTH;
input string         InpSessionHours   = "0000-0000";
input int            InpUtcOffset      = 0;
input int            InpMaxPerBar      = 2;
input int            InpMaxActive      = 5;
input bool           InpNoSame         = true;
input int            InpMaxAge         = 160;               // 40h
input ENUM_HL_OUTSIDE InpOutsideBar    = HL_OUT_CONTINUE;   // one endpoint per bar (news outside bars)
input ENUM_HL_SWING  InpSwingMethod    = HL_SWING_ROLLING;  // timely D on M15 gold; no 45m XABC lag

// 02 Pattern families — reversal-at-D, plus distinct extras for frequency
input bool           InpUseGartley     = true;
input bool           InpUseButterfly   = true;
input bool           InpUseBat         = true;
input bool           InpUseCrab        = true;
input bool           InpUseAltBat      = true;              // D=1.13, not the same as Bat D=0.886
input bool           InpUseDeepCrab    = true;
input bool           InpUseCypher      = true;
input double         InpCypherMin      = 1.13;
input bool           InpUseABCD        = true;              // own key; time filter on
input bool           InpUseWhiteSwan   = false;
input bool           InpUseBlackSwan   = false;
input bool           InpUseShark       = true;
input bool           InpUseNenStar     = true;              // D=1.272 vs Shark 0.886–1.13
input bool           InpUseLeonardo    = false;
input bool           InpUsePartizan    = false;
input bool           InpUseFiveZero    = true;
input bool           InpUseAntiGartley = false;
input bool           InpUseAntiButterfly = false;
input bool           InpUseAntiBat     = false;
input bool           InpUseAntiCrab    = false;
input bool           InpUseAntiShark   = false;
input bool           InpUseAntiCypher  = false;
input bool           InpUseAntiNenStar = false;
input bool           InpUseThreeDrive  = false;
input bool           InpUseDoubleTop   = false;
input bool           InpUseDoubleBottom= false;
input bool           InpUseHS          = false;
input bool           InpUseIHS         = false;
input bool           InpUseAscending   = false;
input bool           InpUseDescending  = false;
input bool           InpUseSymmetrical = false;
input double         InpClassicTol     = 8.0;               // unused while classical families are off
input int            InpHsSkip         = 1;
input int            InpHsTail         = 1;
input double         InpHsShoulderTol  = 50.0;
input bool           InpTriangleNested = false;
input double         InpTriMinRetrace  = 0.618;
input bool           InpUseABCDTime    = true;
input double         InpAbcdTimeShort  = 20.0;
input double         InpAbcdTimeError  = 50.0;

// 03 Entry and targets — close-gated, family-measured (not R:R)
input ENUM_HL_LBASIS InpLevelBasis     = HL_LB_STANDARD;    // Bat uses AD, others CD
input double         InpEntryPct       = 10.0;
input double         InpT1Pct          = 40.0;
input double         InpT2Pct          = 94.0;
input ENUM_HL_KEEP   InpKeepUntil      = HL_KEEP_T2;        // trail after T1, finish at T2
input bool           InpUseRR          = false;             // keep harmonic measured move
input double         InpRR1            = 1.0;
input double         InpRR2            = 2.0;
input ENUM_HL_ENTRY  InpEntryMode      = HL_ENTRY_TOUCH;    // wick touch at close eval; gold rarely closes beyond entry

// 04 Stop and validation
input ENUM_HL_STOPM  InpStopMode       = HL_STOP_TRAIL;
input double         InpManualPct      = 1.0;
input double         InpZonePadPct     = 12.0;              // gold spread vs CD
input double         InpBePct          = 0.0;
input ENUM_HL_TRAIL  InpTrailAfter     = HL_TRAIL_T1;
input double         InpTrailMult      = 1.0;
input ENUM_HL_SRC    InpInvalidSource  = HL_SRC_CLOSE;
input bool           InpRequireEntrySide = false;           // gold often already running at discovery
input double         InpEntryOvershoot = 0.40;
input bool           InpRequireZone    = false;             // gold D often closes outside PRZ after a valid wick
input ENUM_HL_SRC    InpStopSource     = HL_SRC_CLOSE;

// 07 / 08 Panel date + alerts
input datetime       InpStartDate      = D'2021.01.01 00:00';
input bool           InpANew           = true;
input bool           InpAEntry         = true;
input bool           InpAT1            = true;
input bool           InpAT2            = true;
input bool           InpAStop          = true;
input bool           InpAInvalid       = true;
input bool           InpAExpired       = true;
input string         InpAlertTemplate  = "{ticker} | {tf} | {pattern} | {side} | {event} | Entry={entry} T1={t1} T2={t2} SL={sl}";
input ENUM_HL_ALERT  InpAlertFormat    = HL_ALERT_TEXT;
input string         InpAlertBotId     = "";
input bool           InpAZone          = true;
input bool           InpADiv           = true;
input bool           InpAVol           = true;

// 09 Supply | Demand — H4 zones on M15 chart (16× HTF)
input bool           InpSdEnable       = true;
input int            InpSdZoneTf       = 240;               // H4
input int            InpSdPivotLen     = 4;
input int            InpSdSensitivity  = 5;                 // stricter displacement than 6
input int            InpSdDisplaceWin  = 2;
input double         InpSdWidth        = 0.8;
input int            InpSdMaxPerSide   = 4;
input bool           InpSdHideMitigated= true;
input bool           InpSdConfluence   = true;
input string         InpSdConfluenceMark = "⭐";

// 10 Performance
input int            InpPerfMinTrades  = 5;
input int            InpPerfAutoMin    = 0;                 // off until the sample is large; 50% killed families too early

// 11 Trend filter — OFF: harmonics are reversals; EMA200 on M15 blocked most gold longs
input ENUM_HL_TREND  InpTrendMode      = HL_TREND_OFF;
input int            InpTrendLen       = 200;

// 12 Quality
input int            InpQualityMin     = 40;                // 60 + error 6% left almost no gold M15 D's

// 13 RSI divergence (mark only)
input bool           InpDivShow        = true;
input string         InpDivMark        = "↯";

// 14 Volume (mark only)
input bool           InpVolShow        = true;
input double         InpVolMult        = 1.5;
input string         InpVolMark        = "⚡";
input bool           InpVolRequire     = false;

// EA execution
input bool           InpTradeEnable    = true;
input int            InpMagic          = 3133715;
input ENUM_HL_LOTS   InpLotMode        = HL_LOT_RISK;
input double         InpLots           = 0.10;
input double         InpRiskPercent    = 1.0;               // 0.5% of $500 was ~$2.50/trade — invisible on gold
input int            InpSlippage       = 30;
input bool           InpBrokerStops    = false;

//====================================================================
// Data model
//====================================================================
struct Pivot
  {
   double            price;
   int               idx;
   int               sign;
  };

struct Rule
  {
   string            name;
   bool              enabled;
   double            b0,b1,c0,c1,e0,e1,d0,d1;
   int               mode;
  };

struct Candidate
  {
   Pivot             x,a,b,c,d;
  };

struct ExtraFormation
  {
   string            name;
   Pivot             points[16];
   int               npts;
   int               side;
   double            trigger;
   double            invalidation;
   double            unit;
   string            key;
   int               kind;
   int               dBar;
   double            dPrice;
  };

class Pattern
  {
public:
   string            name;
   string            key;
   int               side;
   int               born;
   int               state;
   int               entryBar;
   int               doneBar;
   double            entry;
   double            t1;
   double            t2;
   double            stop;
   double            zlo;
   double            zhi;
   double            best;
   bool              reachedT1;
   bool              hidden;
   int               dBar;
   bool              inZone;
   double            quality;
   bool              diverge;
   double            risk0;
   double            worst;
   bool              volSpike;
   bool              traded;
   int               ticket;
                     Pattern()
     {
      name=""; key=""; side=0; born=0; state=0; entryBar=-1; doneBar=-1;
      entry=0; t1=0; t2=0; stop=0; zlo=0; zhi=0; best=0;
      reachedT1=false; hidden=false; dBar=-1; inZone=false;
      quality=HL_NA; diverge=false; risk0=HL_NA; worst=0; volSpike=false;
      traded=false; ticket=-1;
     }
  };

struct Swing
  {
   Pivot             points[HL_MAX_SWING];
   int               n;
  };

//====================================================================
// Series + globals
//====================================================================
double   g_open[], g_high[], g_low[], g_close[], g_vol[];
datetime g_time[];
double   g_rsi[], g_volAvg[];
int      g_bars = 0;
int      g_barIndex = -1;

Rule     g_rules[HL_RULES];
Swing    g_swings[HL_SCALES];

Pattern *g_patterns[];
int      g_nPat = 0;

string   g_seen[];
int      g_nSeen = 0;
string   g_seenGeom[];
int      g_nSeenGeom = 0;

int      g_foundCount=0, g_enteredCount=0, g_target1Count=0, g_target2Count=0;
int      g_stopCount=0, g_invalidCount=0, g_expiredCount=0;

string   g_perfNames[];
int      g_perfEntered[], g_perfT1[], g_perfT2[], g_perfLoss[], g_perfBars[], g_perfClosed[];
double   g_perfR[], g_perfMAE[];
int      g_nPerf = 0;

double   g_perfAutoMin = 0.0;
bool     g_perfDeep = true;

double   g_trendMa = HL_NA;
bool     g_trendOn = false;
bool     g_divOn = true;
string   g_divMark = "↯";
bool     g_aDiv = true;
bool     g_volOn = true;
double   g_volMult = 1.5;
string   g_volMark = "⚡";
bool     g_volRequire = false;
bool     g_aVol = true;
double   g_qualityMin = 0.0;
bool     g_qualityInName = true;
bool     g_alertJson = false;
string   g_alertBotId = "";
string   g_confluenceMark = "⭐";

double   g_rsiAvgGain = 0.0, g_rsiAvgLoss = 0.0;
bool     g_rsiSeeded = false;
double   g_volSmaSum = 0.0;

bool     g_replaying = true;
bool     g_isRealtime = false;

bool     g_buySignal=false, g_sellSignal=false, g_newSignal=false;
bool     g_hitT1Signal=false, g_hitT2Signal=false, g_stopSignal=false;
bool     g_invalidSignal=false, g_expiredSignal=false, g_zoneSignal=false;

double   g_tick = 0.0;
int      g_digits = 5;

int      g_sdTf = PERIOD_H4;
double   g_sdSupplyTops[], g_sdSupplyBots[];
int      g_sdSupplyLefts[];
int      g_nSdSup = 0;
double   g_sdDemandTops[], g_sdDemandBots[];
int      g_sdDemandLefts[];
int      g_nSdDem = 0;

// HTF SD state machine (mirrors f_sdZones var fields)
double   sd_sHigh=HL_NA, sd_sLow=HL_NA, sd_sBodyLow=HL_NA, sd_sAtr=HL_NA;
datetime sd_sTime=0; int sd_sCount=0;
double   sd_dLow=HL_NA, sd_dHigh=HL_NA, sd_dBodyHigh=HL_NA, sd_dAtr=HL_NA;
datetime sd_dTime=0; int sd_dCount=0;
double   sd_atrRma = HL_NA;
double   sd_trPrevClose = HL_NA;
int      sd_atrN = 0;
double   sd_atrHist[];
int      sd_atrHistN = 0;
double   sd_lastClosedHigh=HL_NA, sd_lastClosedLow=HL_NA, sd_lastClosedTime=0;
bool     sd_lastSupplySig=false, sd_lastDemandSig=false;
double   sd_lastSupTop=HL_NA, sd_lastSupBot=HL_NA, sd_lastDemTop=HL_NA, sd_lastDemBot=HL_NA;
datetime sd_lastSupLeft=0, sd_lastDemLeft=0;
datetime sd_prevHtfTime = 0;
bool     sd_hasPrev = false;
bool     sd_prevSup=false, sd_prevDem=false;
double   sd_prevSupTop=HL_NA, sd_prevSupBot=HL_NA, sd_prevDemTop=HL_NA, sd_prevDemBot=HL_NA;
datetime sd_prevSupLeft=0, sd_prevDemLeft=0;

datetime g_lastChartBar = 0;

//====================================================================
// Small helpers
//====================================================================
double TickSize()
  {
   double ts = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(ts <= 0.0) ts = Point;
   return(ts);
  }

double RoundTick(const double p)
  {
   double ts = g_tick;
   if(ts <= 0.0) ts = TickSize();
   return(NormalizeDouble(MathRound(p / ts) * ts, g_digits));
  }

string F_Num(const double n)
  {
   return(DoubleToString(n, g_digits));
  }

string TfText()
  {
   int p = Period();
   if(p >= 43200) return IntegerToString(p/43200)+"MN";
   if(p >= 10080) return IntegerToString(p/10080)+"W";
   if(p >= 1440)  return IntegerToString(p/1440)+"D";
   if(p >= 60)    return IntegerToString(p/60)+"H";
   return IntegerToString(p)+"m";
  }

bool F_Band(const double value, const double lo, const double hi)
  {
   return(value >= lo * (1.0 - InpErrorPct / 100.0) &&
          value <= hi * (1.0 + InpErrorPct / 100.0));
  }

double ArrMin(const double &a[], const int fromIdx, const int toIdx)
  {
   double m = a[fromIdx];
   for(int i=fromIdx+1; i<=toIdx; i++) if(a[i] < m) m = a[i];
   return(m);
  }
double ArrMax(const double &a[], const int fromIdx, const int toIdx)
  {
   double m = a[fromIdx];
   for(int i=fromIdx+1; i<=toIdx; i++) if(a[i] > m) m = a[i];
   return(m);
  }

int PivotCount(const Swing &sw) { return(sw.n); }

Pivot SwingGet(const Swing &sw, const int i)
  {
   Pivot p; p.price=0; p.idx=0; p.sign=0;
   if(i>=0 && i<sw.n) p = sw.points[i];
   return(p);
  }

void SwingSet(Swing &sw, const int i, const Pivot &pt)
  {
   if(i>=0 && i<sw.n) sw.points[i] = pt;
  }

void SwingPush(Swing &sw, const Pivot &pt)
  {
   if(sw.n >= HL_MAX_SWING)
     {
      for(int i=0;i<HL_MAX_SWING-1;i++) sw.points[i]=sw.points[i+1];
      sw.n = HL_MAX_SWING-1;
     }
   sw.points[sw.n] = pt;
   sw.n++;
  }

void SwingPop(Swing &sw)
  {
   if(sw.n>0) sw.n--;
  }

void SwingCopy(Swing &dst, const Swing &src)
  {
   dst.n = src.n;
   for(int i=0;i<src.n;i++) dst.points[i]=src.points[i];
  }

bool SeenHas(const string &arr[], const int n, const string key)
  {
   for(int i=0;i<n;i++) if(arr[i]==key) return(true);
   return(false);
  }

void SeenPush(string &arr[], int &n, const string key, const int cap)
  {
   if(n >= cap)
     {
      for(int i=0;i<n-1;i++) arr[i]=arr[i+1];
      n--;
      ArrayResize(arr, n);
     }
   ArrayResize(arr, n+1);
   arr[n] = key;
   n++;
  }

int PerfIndex(const string name)
  {
   for(int i=0;i<g_nPerf;i++) if(g_perfNames[i]==name) return(i);
   ArrayResize(g_perfNames, g_nPerf+1);
   ArrayResize(g_perfEntered, g_nPerf+1);
   ArrayResize(g_perfT1, g_nPerf+1);
   ArrayResize(g_perfT2, g_nPerf+1);
   ArrayResize(g_perfLoss, g_nPerf+1);
   ArrayResize(g_perfBars, g_nPerf+1);
   ArrayResize(g_perfR, g_nPerf+1);
   ArrayResize(g_perfMAE, g_nPerf+1);
   ArrayResize(g_perfClosed, g_nPerf+1);
   g_perfNames[g_nPerf]=name;
   g_perfEntered[g_nPerf]=0; g_perfT1[g_nPerf]=0; g_perfT2[g_nPerf]=0; g_perfLoss[g_nPerf]=0;
   g_perfBars[g_nPerf]=0; g_perfR[g_nPerf]=0; g_perfMAE[g_nPerf]=0; g_perfClosed[g_nPerf]=0;
   g_nPerf++;
   return(g_nPerf-1);
  }

void F_Perf(const string name, const int kind)
  {
   int i = PerfIndex(name);
   if(kind==0) g_perfEntered[i]++;
   else if(kind==1) g_perfT1[i]++;
   else if(kind==2) g_perfT2[i]++;
   else g_perfLoss[i]++;
  }

void F_PerfResult(Pattern *p, const double exitPrice, const bool win)
  {
   int i = PerfIndex(p.name);
   double risk = MathMax(p.risk0, g_tick);
   g_perfR[i]   += (exitPrice - p.entry) * p.side / risk;
   g_perfMAE[i] += MathMax(0.0, (p.entry - p.worst) * p.side) / risk;
   g_perfClosed[i]++;
   if(win) g_perfBars[i] += (g_barIndex - p.entryBar);
  }

bool F_AutoBlocked(const string name)
  {
   if(g_perfAutoMin <= 0.0) return(false);
   for(int i=0;i<g_nPerf;i++)
     {
      if(g_perfNames[i]!=name) continue;
      int w = g_perfT1[i];
      int l = g_perfLoss[i];
      if(w + l >= 5 && 100.0 * w / (w + l) < g_perfAutoMin) return(true);
     }
   return(false);
  }

bool F_TimeOK(const int mode, const int aIdx, const int bIdx, const int cIdx, const int dIdx)
  {
   int abBars = bIdx - aIdx;
   int cdBars = dIdx - cIdx;
   if(mode != 2 || !InpUseABCDTime) return(true);
   if(!(abBars > 0 && cdBars > 0)) return(false);
   double ratio = cdBars / (double)abBars;
   return(ratio >= 1.0 - InpAbcdTimeShort / 100.0 - 1e-9 &&
          ratio <= 1.0 + InpAbcdTimeError / 100.0 + 1e-9);
  }

bool F_VolSpike(const Pivot &d)
  {
   int n = g_barIndex - d.idx;
   bool spike = false;
   if(n >= 0 && d.idx >= 0 && d.idx < g_bars)
     {
      if(g_volAvg[d.idx] > 0.0)
         spike = (g_vol[d.idx] >= g_volMult * g_volAvg[d.idx]);
     }
   return(spike);
  }

bool F_Div(const int side, const Pivot &refp, const Pivot &d)
  {
   int nd = g_barIndex - d.idx;
   int nr = g_barIndex - refp.idx;
   bool beyond = (side == 1) ? (d.price < refp.price) : (d.price > refp.price);
   if(!(beyond && nd >= 0 && nr >= 0 && d.idx>=0 && refp.idx>=0 && d.idx<g_bars && refp.idx<g_bars))
      return(false);
   return (side == 1) ? (g_rsi[d.idx] > g_rsi[refp.idx]) : (g_rsi[d.idx] < g_rsi[refp.idx]);
  }

bool F_Allowed(const int side)
  {
   bool dirOK = (InpDirection==HL_DIR_BOTH) ||
                (InpDirection==HL_DIR_LONG && side==1) ||
                (InpDirection==HL_DIR_SHORT && side==-1);
   bool trendOK = (!g_trendOn) || HlNa(g_trendMa) ||
                  ((side==1) ? (g_close[g_barIndex] > g_trendMa) : (g_close[g_barIndex] < g_trendMa));
   return(dirOK && trendOK);
  }

int F_Active()
  {
   int n=0;
   for(int i=0;i<g_nPat;i++) if(g_patterns[i].state < 3) n++;
   return(n);
  }

bool F_Blocked(const string name, const int side)
  {
   if(!InpNoSame) return(false);
   for(int i=0;i<g_nPat;i++)
     {
      Pattern *p = g_patterns[i];
      if(p.name==name && p.side==side && p.state<3) return(true);
     }
   return(false);
  }

bool F_StopHit(const int side, const double stopPrice, const double barClose, const double barHigh, const double barLow)
  {
   double price = (InpStopSource==HL_SRC_CLOSE) ? barClose : ((side==1) ? barLow : barHigh);
   return (side==1) ? (price <= stopPrice) : (price >= stopPrice);
  }

bool F_CandleOK(const int side)
  {
   if(g_barIndex < 1) return(false);
   double c = g_close[g_barIndex], o = g_open[g_barIndex];
   double h = g_high[g_barIndex],  l = g_low[g_barIndex];
   double c1 = g_close[g_barIndex-1], o1 = g_open[g_barIndex-1];
   double h1 = g_high[g_barIndex-1],  l1 = g_low[g_barIndex-1];
   double body = MathAbs(c - o);
   bool bodyOK = ((c - o) * side > 0.0);
   bool engulf = bodyOK && ((side==1) ? (c > h1 && o <= c1) : (c < l1 && o >= c1));
   double wick = (side==1) ? (MathMin(o,c) - l) : (h - MathMax(o,c));
   bool pin = (wick >= 2.0 * body && wick > 0.0 &&
               ((side==1) ? (c > (h+l)/2.0) : (c < (h+l)/2.0)));
   return(engulf || pin);
  }

//====================================================================
// Session / calendar
//====================================================================
int SessionTfMinutes()
  {
   return(Period());
  }

bool InSessionAt(const datetime t)
  {
   if(InpSessionHours=="" || InpSessionHours=="0000-0000") return(true);
   string s = InpSessionHours;
   int dash = StringFind(s, "-");
   if(dash < 0) return(true);
   int a = (int)StringToInteger(StringSubstr(s,0,dash));
   int b = (int)StringToInteger(StringSubstr(s,dash+1));
   int sh = a / 100, sm = a % 100, eh = b / 100, em = b % 100;
   datetime utc = t - TimeGMTOffset(); // t is broker time
   // Apply user UTC offset relative to UTC: session clock = UTC + InpUtcOffset
   datetime sess = utc + InpUtcOffset * 3600;
   MqlDateTime dt; TimeToStruct(sess, dt);
   int nowm = dt.hour * 60 + dt.min;
   int smn = sh*60+sm, emn = eh*60+em;
   if(smn==emn) return(true);
   if(emn > smn) return(nowm >= smn && nowm < emn);
   return(nowm >= smn || nowm < emn);
  }

//====================================================================
// JSON / alerts
//====================================================================
string JsonStr(const string v)
  {
   string s = v;
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   return("\""+s+"\"");
  }

string F_Json(Pattern *p, const string eventName)
  {
   string ev = eventName;
   StringToLower(ev);
   StringReplace(ev, " ", "_");
   StringReplace(ev, "(", "");
   StringReplace(ev, ")", "");
   string j = "{";
   j += "\"event\":"+JsonStr(ev);
   j += ",\"symbol\":"+JsonStr(Symbol());
   j += ",\"ticker\":"+JsonStr(Symbol());
   j += ",\"exchange\":"+JsonStr(AccountCompany());
   j += ",\"tf\":"+JsonStr(TfText());
   j += ",\"pattern\":"+JsonStr(p.name);
   j += ",\"side\":"+JsonStr(p.side==1?"long":"short");
   string action = "close";
   if(eventName=="Entry") action = (p.side==1?"buy":"sell");
   else if(eventName=="New pattern") action = "watch";
   j += ",\"action\":"+JsonStr(action);
   j += ",\"price\":"+F_Num(g_close[g_barIndex]);
   j += ",\"entry\":"+F_Num(p.entry);
   j += ",\"sl\":"+F_Num(p.stop);
   j += ",\"tp1\":"+F_Num(p.t1);
   j += ",\"tp2\":"+F_Num(p.t2);
   j += ",\"quality\":"+(HlNa(p.quality)?"null":DoubleToString(p.quality,0));
   j += ",\"zone\":"+(p.inZone?"true":"false");
   j += ",\"divergence\":"+(p.diverge?"true":"false");
   j += ",\"volume\":"+(p.volSpike?"true":"false");
   j += ",\"time\":"+JsonStr(TimeToString(g_time[g_barIndex], TIME_DATE|TIME_SECONDS));
   if(g_alertBotId != "") j += ",\"bot_id\":"+JsonStr(g_alertBotId);
   j += "}";
   return(j);
  }

void F_Emit(Pattern *p, const string eventName, const bool enabled)
  {
   if(!enabled) return;
   if(!g_isRealtime) return;
   string msg;
   if(g_alertJson) msg = F_Json(p, eventName);
   else
     {
      msg = InpAlertTemplate;
      StringReplace(msg, "{ticker}", Symbol());
      StringReplace(msg, "{tf}", TfText());
      StringReplace(msg, "{pattern}", p.name);
      StringReplace(msg, "{side}", p.side==1?"Long":"Short");
      StringReplace(msg, "{event}", eventName);
      StringReplace(msg, "{entry}", F_Num(p.entry));
      StringReplace(msg, "{t1}", F_Num(p.t1));
      StringReplace(msg, "{t2}", F_Num(p.t2));
      StringReplace(msg, "{sl}", F_Num(p.stop));
      StringReplace(msg, "{price}", F_Num(g_close[g_barIndex]));
      StringReplace(msg, "{quality}", HlNa(p.quality)?"-":DoubleToString(p.quality,0));
     }
   Alert(msg);
   Print(msg);
  }

//====================================================================
// Series: RSI (Wilder, period 14) and volume SMA 20 — match ta.rsi / ta.sma
//====================================================================
void PushSeriesBar(const double o, const double h, const double l, const double c,
                   const double vol, const datetime t)
  {
   int n = g_bars;
   ArrayResize(g_open, n+1);
   ArrayResize(g_high, n+1);
   ArrayResize(g_low, n+1);
   ArrayResize(g_close, n+1);
   ArrayResize(g_vol, n+1);
   ArrayResize(g_time, n+1);
   ArrayResize(g_rsi, n+1);
   ArrayResize(g_volAvg, n+1);
   g_open[n]=o; g_high[n]=h; g_low[n]=l; g_close[n]=c; g_vol[n]=vol; g_time[n]=t;

   // Volume SMA 20
   g_volSmaSum += vol;
   if(n>=20) g_volSmaSum -= g_vol[n-20];
   g_volAvg[n] = (n>=19) ? (g_volSmaSum / 20.0) : HL_NA;

   // RSI 14 Wilder
   double rsi = HL_NA;
   if(n==0)
     {
      g_rsi[n]=HL_NA;
     }
   else
     {
      double ch = c - g_close[n-1];
      double gain = MathMax(ch, 0.0);
      double loss = MathMax(-ch, 0.0);
      if(n < 14)
        {
         g_rsiAvgGain += gain;
         g_rsiAvgLoss += loss;
         g_rsi[n]=HL_NA;
        }
      else if(n==14)
        {
         g_rsiAvgGain = (g_rsiAvgGain + gain) / 14.0;
         g_rsiAvgLoss = (g_rsiAvgLoss + loss) / 14.0;
         g_rsiSeeded = true;
         if(g_rsiAvgLoss==0.0) rsi = 100.0;
         else rsi = 100.0 - 100.0 / (1.0 + g_rsiAvgGain / g_rsiAvgLoss);
         g_rsi[n]=rsi;
        }
      else
        {
         g_rsiAvgGain = (g_rsiAvgGain * 13.0 + gain) / 14.0;
         g_rsiAvgLoss = (g_rsiAvgLoss * 13.0 + loss) / 14.0;
         if(g_rsiAvgLoss==0.0) rsi = 100.0;
         else rsi = 100.0 - 100.0 / (1.0 + g_rsiAvgGain / g_rsiAvgLoss);
         g_rsi[n]=rsi;
        }
     }
   g_bars = n+1;
   g_barIndex = n;
  }

double PivotHighAt(const int depth, const int right)
  {
   int pivotIdx = g_barIndex - right;
   if(pivotIdx - depth < 0) return(HL_NA);
   double v = g_high[pivotIdx];
   for(int i=pivotIdx-depth; i<=pivotIdx+right; i++)
     {
      if(i==pivotIdx) continue;
      if(i<0 || i>g_barIndex) return(HL_NA);
      if(g_high[i] >= v) return(HL_NA);
     }
   return(v);
  }
double PivotLowAt(const int depth, const int right)
  {
   int pivotIdx = g_barIndex - right;
   if(pivotIdx - depth < 0) return(HL_NA);
   double v = g_low[pivotIdx];
   for(int i=pivotIdx-depth; i<=pivotIdx+right; i++)
     {
      if(i==pivotIdx) continue;
      if(i<0 || i>g_barIndex) return(HL_NA);
      if(g_low[i] <= v) return(HL_NA);
     }
   return(v);
  }

double HighestLookback(const int len)
  {
   int from = g_barIndex - len + 1;
   if(from<0) from=0;
   return(ArrMax(g_high, from, g_barIndex));
  }
double LowestLookback(const int len)
  {
   int from = g_barIndex - len + 1;
   if(from<0) from=0;
   return(ArrMin(g_low, from, g_barIndex));
  }

//====================================================================
// Rules
//====================================================================
void RuleSet(const int i, const string name, const bool en,
             const double b0, const double b1, const double c0, const double c1,
             const double e0, const double e1, const double d0, const double d1, const int mode)
  {
   g_rules[i].name=name; g_rules[i].enabled=en;
   g_rules[i].b0=b0; g_rules[i].b1=b1; g_rules[i].c0=c0; g_rules[i].c1=c1;
   g_rules[i].e0=e0; g_rules[i].e1=e1; g_rules[i].d0=d0; g_rules[i].d1=d1;
   g_rules[i].mode=mode;
  }

void InitRules()
  {
   RuleSet(0,  "Gartley",          InpUseGartley,     0.618, 0.618, 0.382, 0.886, 1.13,  1.618, 0.786, 0.786, 0);
   RuleSet(1,  "Butterfly",        InpUseButterfly,   0.786, 0.786, 0.382, 0.886, 1.618, 2.618, 1.27,  1.618, 0);
   RuleSet(2,  "Bat",              InpUseBat,         0.382, 0.50,  0.382, 0.886, 1.618, 2.618, 0.886, 0.886, 0);
   RuleSet(3,  "Crab",             InpUseCrab,        0.382, 0.618, 0.382, 0.886, 2.24,  3.618, 1.618, 1.618, 0);
   RuleSet(4,  "Alternate Bat",    InpUseAltBat,      0.236, 0.382, 0.382, 0.886, 2.0,   3.618, 1.13,  1.13,  0);
   RuleSet(5,  "Deep Crab",        InpUseDeepCrab,    0.886, 0.886, 0.382, 0.886, 2.0,   3.618, 1.618, 1.618, 0);
   RuleSet(6,  "Cypher",           InpUseCypher,      0.382, 0.618, InpCypherMin, 1.414, 0, 0, 0.786, 0.786, 1);
   RuleSet(7,  "AB=CD",            InpUseABCD,        0,     0,     0.618, 0.886, 1.13,  1.618, 1,     1,     2);
   RuleSet(8,  "White Swan",       InpUseWhiteSwan,   0.382, 0.786, 2.0,   4.237, 0.5,   0.886, 0.236, 0.886, 0);
   RuleSet(9,  "Black Swan",       InpUseBlackSwan,   1.382, 2.618, 0.236, 0.5,   1.128, 2.0,   1.128, 2.618, 0);
   RuleSet(10, "Shark",            InpUseShark,       0.382, 0.618, 1.128, 1.618, 1.618, 2.236, 0.886, 1.13,  0);
   RuleSet(11, "Nen Star",         InpUseNenStar,     0.382, 0.618, 1.414, 2.14,  1.128, 2,     1.272, 1.272, 0);
   RuleSet(12, "Leonardo",         InpUseLeonardo,    0.5,   0.5,   0.382, 0.886, 1.128, 2.618, 0.786, 0.786, 0);
   RuleSet(13, "Partizan",         InpUsePartizan,    0.128, 3.618, 0.382, 0.382, 1.618, 1.618, 0.618, 3.618, 0);
   RuleSet(14, "5-0",              InpUseFiveZero,    1.13,  1.618, 1.618, 2.24,  0.5,   0.5,   0.5,   0.5,   3);
   RuleSet(15, "Anti-Gartley",     InpUseAntiGartley, 0.618, 0.786, 1.128, 2.618, 1.618, 1.618, 1.272, 1.272, 0);
   RuleSet(16, "Anti-Butterfly",   InpUseAntiButterfly,0.382,0.618, 1.128, 2.618, 1.272, 1.272, 0.618, 0.786, 0);
   RuleSet(17, "Anti-Bat",         InpUseAntiBat,     0.382, 0.618, 1.128, 2.618, 2,     2.618, 1.128, 1.128, 0);
   RuleSet(18, "Anti-Crab",        InpUseAntiCrab,    0.276, 0.446, 1.128, 2.618, 1.618, 2.618, 0.618, 0.618, 0);
   RuleSet(19, "Anti-Shark",       InpUseAntiShark,   0.446, 0.618, 0.618, 0.886, 1.618, 2.618, 1.128, 1.128, 0);
   RuleSet(20, "Anti-Cypher",      InpUseAntiCypher,  0.5,   0.786, 0.476, 0.707, 1.618, 2.618, 1.272, 1.272, 0);
   RuleSet(21, "Anti-Nen Star",    InpUseAntiNenStar, 0.5,   0.886, 0.467, 0.707, 1.618, 2.618, 0.786, 0.786, 0);
  }

//====================================================================
// Swing updates
//====================================================================
bool F_Update(Swing &sw, const double ph, const double pl)
  {
   bool changed = false;
   bool hasH = !HlNa(ph);
   bool hasL = !HlNa(pl);
   if(hasH != hasL)
     {
      int sg = hasH ? 1 : -1;
      double price = (sg==1) ? ph : pl;
      Pivot pt; pt.price=price; pt.idx=g_barIndex-InpConfirmBars; pt.sign=sg;
      int n = sw.n;
      if(n==0)
        {
         SwingPush(sw, pt);
         changed = true;
        }
      else
        {
         Pivot prev = sw.points[n-1];
         if(pt.idx > prev.idx)
           {
            if(sg == prev.sign)
              {
               if((price - prev.price) * sg > 0.0)
                 {
                  sw.points[n-1] = pt;
                  changed = true;
                 }
              }
            else if((price - prev.price) * sg > g_tick)
              {
               SwingPush(sw, pt);
               changed = true;
              }
           }
        }
     }
   return(changed);
  }

bool F_UpdateRolling(Swing &sw, const bool newHigh, const bool newLow)
  {
   bool changed = false;
   if(newHigh || newLow)
     {
      int previousSign = (sw.n>0) ? sw.points[sw.n-1].sign : 0;
      int sg;
      if(newHigh && newLow)
         sg = (InpOutsideBar==HL_OUT_OPPOSITE) ? -previousSign : previousSign;
      else
         sg = newHigh ? 1 : -1;
      double value = (sg==1) ? g_high[g_barIndex] : g_low[g_barIndex];
      Pivot pt; pt.price=value; pt.idx=g_barIndex; pt.sign=sg;
      int n = sw.n;
      if(n==0 && sg!=0)
        {
         SwingPush(sw, pt);
         changed = true;
        }
      else if(n>0)
        {
         Pivot prev = sw.points[n-1];
         if(g_barIndex > prev.idx && (value - prev.price) * sg > g_tick)
           {
            if(sg == prev.sign) sw.points[n-1] = pt;
            else SwingPush(sw, pt);
            changed = true;
           }
        }
      if(newHigh && newLow && InpOutsideBar==HL_OUT_BOTH && previousSign!=0)
        {
         int n2 = sw.n;
         Pivot last = sw.points[n2-1];
         int sg2 = -last.sign;
         double value2 = (sg2==1) ? g_high[g_barIndex] : g_low[g_barIndex];
         if((value2 - last.price) * sg2 > g_tick)
           {
            Pivot p2; p2.price=value2; p2.idx=g_barIndex; p2.sign=sg2;
            SwingPush(sw, p2);
            changed = true;
           }
        }
     }
   return(changed);
  }

bool F_LegContained(const Swing &sw, const int fromIndex, const int toIndex)
  {
   Pivot left = sw.points[fromIndex];
   Pivot right = sw.points[toIndex];
   double lo = MathMin(left.price, right.price) - g_tick * 0.1;
   double hi = MathMax(left.price, right.price) + g_tick * 0.1;
   if(toIndex - fromIndex > 1)
     {
      for(int k=fromIndex+1; k<=toIndex-1; k++)
        {
         double v = sw.points[k].price;
         if(v < lo || v > hi) return(false);
        }
     }
   return(true);
  }

void F_XabcdCandidates(const Swing &sw, const int limit, Candidate &result[], int &nRes)
  {
   nRes = 0;
   ArrayResize(result, 0);
   int di = sw.n - 1;
   int maxCG = InpSearchNested ? (int)MathFloor((di - 4) / 2.0) : 0;
   for(int cg=0; cg<=maxCG; cg++)
     {
      if(nRes >= limit) break;
      int ci = di - 1 - 2 * cg;
      if(!F_LegContained(sw, ci, di)) continue;
      int maxBG = InpSearchNested ? (int)MathFloor((ci - 3) / 2.0) : 0;
      for(int bg=0; bg<=maxBG; bg++)
        {
         if(nRes >= limit) break;
         int bi = ci - 1 - 2 * bg;
         if(!F_LegContained(sw, bi, ci)) continue;
         int maxAG = InpSearchNested ? (int)MathFloor((bi - 2) / 2.0) : 0;
         for(int ag=0; ag<=maxAG; ag++)
           {
            if(nRes >= limit) break;
            int ai = bi - 1 - 2 * ag;
            if(!F_LegContained(sw, ai, bi)) continue;
            int maxXG = InpSearchNested ? (int)MathFloor((ai - 1) / 2.0) : 0;
            for(int xg=0; xg<=maxXG; xg++)
              {
               if(nRes >= limit) break;
               int xi = ai - 1 - 2 * xg;
               if(xi >= 0 && F_LegContained(sw, xi, ai))
                 {
                  ArrayResize(result, nRes+1);
                  result[nRes].x = sw.points[xi];
                  result[nRes].a = sw.points[ai];
                  result[nRes].b = sw.points[bi];
                  result[nRes].c = sw.points[ci];
                  result[nRes].d = sw.points[di];
                  nRes++;
                 }
              }
           }
        }
     }
  }

void F_AbcdCandidates(const Swing &sw, const int limit, Candidate &result[], int &nRes)
  {
   nRes = 0;
   ArrayResize(result, 0);
   int di = sw.n - 1;
   if(di < 3) return;
   int maxCG = InpSearchNested ? (int)MathFloor((di - 3) / 2.0) : 0;
   for(int cg=0; cg<=maxCG; cg++)
     {
      if(nRes >= limit) break;
      int ci = di - 1 - 2 * cg;
      if(!F_LegContained(sw, ci, di)) continue;
      int maxBG = InpSearchNested ? (int)MathFloor((ci - 2) / 2.0) : 0;
      for(int bg=0; bg<=maxBG; bg++)
        {
         if(nRes >= limit) break;
         int bi = ci - 1 - 2 * bg;
         if(!F_LegContained(sw, bi, ci)) continue;
         int maxAG = InpSearchNested ? (int)MathFloor((bi - 1) / 2.0) : 0;
         for(int ag=0; ag<=maxAG; ag++)
           {
            if(nRes >= limit) break;
            int ai = bi - 1 - 2 * ag;
            if(ai >= 0 && F_LegContained(sw, ai, bi))
              {
               ArrayResize(result, nRes+1);
               Pivot a = sw.points[ai];
               result[nRes].x = a;
               result[nRes].a = a;
               result[nRes].b = sw.points[bi];
               result[nRes].c = sw.points[ci];
               result[nRes].d = sw.points[di];
               nRes++;
              }
           }
        }
     }
  }

void F_Candidates(const Swing &sw, const int limit, Candidate &result[], int &nRes)
  {
   int cap = (limit > 0) ? limit : InpCandidateLimit;
   nRes = 0;
   ArrayResize(result, 0);
   if(sw.n >= 5)
     {
      F_XabcdCandidates(sw, cap, result, nRes);
     }
   if(InpUseABCD)
     {
      Candidate extra[]; int nEx=0;
      F_AbcdCandidates(sw, cap, extra, nEx);
      int base = nRes;
      ArrayResize(result, base + nEx);
      for(int i=0;i<nEx;i++) result[base+i] = extra[i];
      nRes = base + nEx;
     }
  }

void F_LiveCandidates(const Swing &sw, const bool newHigh, const bool newLow,
                      Candidate &result[], int &nRes)
  {
   nRes = 0;
   ArrayResize(result, 0);
   Swing temp; SwingCopy(temp, sw);
   bool ready = false;
   if(newHigh != newLow && temp.n > 0)
     {
      int sg = newHigh ? 1 : -1;
      double value = newHigh ? g_high[g_barIndex] : g_low[g_barIndex];
      int lastIndex = temp.n - 1;
      Pivot prev = temp.points[lastIndex];
      Pivot live; live.price=value; live.idx=g_barIndex; live.sign=sg;
      if((value - prev.price) * sg > g_tick && g_barIndex > prev.idx)
        {
         if(sg == prev.sign) temp.points[lastIndex] = live;
         else SwingPush(temp, live);
         ready = true;
        }
     }
   if(ready && temp.n >= 4) F_Candidates(temp, 0, result, nRes);
  }

//====================================================================
// Zone + quality + unit
//====================================================================
bool F_Zone(const Rule &r, const double x, const double a, const double b, const double c,
            const int side, double &lo, double &hi)
  {
   double xa = MathAbs(a - x);
   double ab = MathAbs(b - a);
   double bc = MathAbs(c - b);
   double xc = MathAbs(c - x);
   bool geom = ((a - b) * side > 0.0 && (c - b) * side > 0.0);
   bool valid = (ab > g_tick && bc > g_tick && geom);
   if(r.mode != 2) valid = valid && (xa > g_tick);
   if(r.mode != 2)
      valid = valid && ((a - x) * side > 0.0) &&
              (r.b1 > 1.0 || (b - x) * side > 0.0) &&
              F_Band(ab / xa, r.b0, r.b1);
   if(r.mode == 1)
      valid = valid && ((c - a) * side > 0.0) && F_Band(xc / xa, r.c0, r.c1);
   else
      valid = valid && (r.c1 > 1.0 || (a - c) * side > 0.0) && F_Band(bc / ab, r.c0, r.c1);

   double unit = (r.mode==0) ? xa : (r.mode==1 ? xc : (r.mode==3 ? bc : ab));
   double anchor = (r.mode==0) ? a : c;
   double q0 = anchor - side * unit * r.d0 * (1.0 - InpErrorPct / 100.0);
   double q1 = anchor - side * unit * r.d1 * (1.0 + InpErrorPct / 100.0);
   lo = MathMin(q0, q1);
   hi = MathMax(q0, q1);
   if(r.mode != 1)
     {
      double e0 = c - side * bc * r.e0 * (1.0 - InpErrorPct / 100.0);
      double e1 = c - side * bc * r.e1 * (1.0 + InpErrorPct / 100.0);
      lo = MathMax(lo, MathMin(e0, e1));
      hi = MathMin(hi, MathMax(e0, e1));
     }
   bool pastB = (r.mode != 1 && r.e0 >= 1.0);
   double boundary = pastB ? ((side==1) ? MathMin(b,c) : MathMax(b,c)) : c;
   if(side==1) hi = MathMin(hi, boundary - g_tick);
   else        lo = MathMax(lo, boundary + g_tick);
   if(r.mode == 0)
     {
      if(r.d1 < 1.0)
        {
         if(side==1) lo = MathMax(lo, x + g_tick);
         else        hi = MathMin(hi, x - g_tick);
        }
      if(r.d0 > 1.0)
        {
         if(side==1) hi = MathMin(hi, x - g_tick);
         else        lo = MathMax(lo, x + g_tick);
        }
     }
   return(valid && lo <= hi);
  }

double F_Unit(const Rule &r, const double a, const double c, const double d)
  {
   bool calibrated = (InpLevelBasis==HL_LB_STANDARD || InpLevelBasis==HL_LB_LEGACY);
   bool useAD = (r.mode != 2 && InpLevelBasis==HL_LB_AD) ||
                (calibrated && (r.mode==2 || r.name=="Black Swan" || r.name=="Bat" ||
                                r.name=="Anti-Cypher" || r.name=="Anti-Bat" || r.name=="Anti-Nen Star"));
   return useAD ? MathAbs(a - d) : MathAbs(c - d);
  }

double F_RatioScore(const double value, const double lo, const double hi)
  {
   double tol = InpErrorPct / 100.0;
   double score = 1.0;
   if(value < lo)
      score = 1.0 - (lo - value) / MathMax(lo * tol, g_tick);
   else if(value > hi)
      score = 1.0 - (value - hi) / MathMax(hi * tol, g_tick);
   return(MathMax(0.0, MathMin(1.0, score)));
  }

double F_Quality(const Rule &r, const double x, const double a, const double b, const double c, const double d)
  {
   if(r.mode >= 10) return(HL_NA);
   double xa = MathAbs(a - x);
   double ab = MathAbs(b - a);
   double bc = MathAbs(c - b);
   double cd = MathAbs(d - c);
   double xc = MathAbs(c - x);
   double sum = 0.0;
   int n = 0;
   if(r.mode != 2 && xa > 0.0) { sum += F_RatioScore(ab / xa, r.b0, r.b1); n++; }
   if(r.mode == 1)
     {
      if(xa > 0.0) { sum += F_RatioScore(xc / xa, r.c0, r.c1); n++; }
     }
   else if(ab > 0.0) { sum += F_RatioScore(bc / ab, r.c0, r.c1); n++; }
   if(r.mode != 1 && r.e0 > 0.0 && bc > 0.0) { sum += F_RatioScore(cd / bc, r.e0, r.e1); n++; }
   double unit = (r.mode==0)?xa:(r.mode==1?xc:(r.mode==3?bc:ab));
   double anchor = (r.mode==0)?a:c;
   if(unit > 0.0)
     {
      sum += F_RatioScore(MathAbs(anchor - d) / unit, MathMin(r.d0, r.d1), MathMax(r.d0, r.d1));
      n++;
     }
   return (n>0) ? (100.0 * sum / n) : HL_NA;
  }

//====================================================================
// Trade execution on the same events the indicator would emit
//====================================================================
double LotStep() { double v=MarketInfo(Symbol(), MODE_LOTSTEP); return(v>0?v:0.01); }
double LotMin()  { double v=MarketInfo(Symbol(), MODE_MINLOT);  return(v>0?v:0.01); }
double LotMax()  { double v=MarketInfo(Symbol(), MODE_MAXLOT);  return(v>0?v:100); }

double NormLot(double lots)
  {
   double step = LotStep();
   lots = MathFloor(lots / step + 1e-8) * step;
   lots = MathMax(LotMin(), MathMin(LotMax(), lots));
   return(NormalizeDouble(lots, 2));
  }

double LotsFor(Pattern *p)
  {
   if(InpLotMode==HL_LOT_FIXED) return(NormLot(InpLots));
   double riskMoney = AccountBalance() * InpRiskPercent / 100.0;
   double tickVal = MarketInfo(Symbol(), MODE_TICKVALUE);
   double ts = g_tick;
   if(ts<=0 || tickVal<=0) return(NormLot(InpLots));
   double dist = MathAbs(p.entry - p.stop);
   if(dist < ts) dist = ts;
   double lots = riskMoney / (dist / ts * tickVal);
   return(NormLot(lots));
  }

bool CanTradeNow()
  {
   if(!InpTradeEnable) return(false);
   if(g_replaying && !IsTesting() && !IsOptimization()) return(false);
   return(true);
  }

int OpenTrade(Pattern *p)
  {
   if(!CanTradeNow()) return(-1);
   if(p.traded && p.ticket>0) return(p.ticket);
   double lots = LotsFor(p);
   int type = (p.side==1) ? OP_BUY : OP_SELL;
   double price = (p.side==1) ? Ask : Bid;
   double sl=0, tp=0;
   if(InpBrokerStops)
     {
      sl = p.stop;
      tp = (InpKeepUntil==HL_KEEP_T1) ? p.t1 : p.t2;
     }
   int ticket = OrderSend(Symbol(), type, lots, price, InpSlippage, sl, tp,
                          p.name, InpMagic, 0, (p.side==1)?clrTeal:clrFireBrick);
   if(ticket<0)
     {
      Print("OrderSend failed ", GetLastError(), " ", p.name, " ", lots);
      return(-1);
     }
   p.traded = true;
   p.ticket = ticket;
   return(ticket);
  }

void CloseTrade(Pattern *p, const string why)
  {
   if(!p.traded || p.ticket<=0) return;
   if(!OrderSelect(p.ticket, SELECT_BY_TICKET)) { p.ticket=-1; return; }
   if(OrderCloseTime()>0) { p.ticket=-1; return; }
   double price = (OrderType()==OP_BUY) ? Bid : Ask;
   if(!OrderClose(p.ticket, OrderLots(), price, InpSlippage, clrGold))
      Print("OrderClose failed ", GetLastError(), " ", why);
   p.ticket = -1;
  }

void ModifyTradeSL(Pattern *p)
  {
   if(!InpBrokerStops) return;
   if(!p.traded || p.ticket<=0) return;
   if(!OrderSelect(p.ticket, SELECT_BY_TICKET)) return;
   if(OrderCloseTime()>0) return;
   if(MathAbs(OrderStopLoss() - p.stop) < g_tick * 0.5) return;
   if(!OrderModify(p.ticket, OrderOpenPrice(), p.stop, OrderTakeProfit(), 0, clrYellow))
      Print("OrderModify failed ", GetLastError());
  }

//====================================================================
// Create pattern (levels only — no drawings)
//====================================================================
Pattern *F_Create(const Rule &r, const Pivot &x, const Pivot &a, const Pivot &b,
                  const Pivot &c, const Pivot &d, double lo, double hi, const string key)
  {
   int side = -d.sign;
   double span = (r.mode >= 10) ? r.d0 : F_Unit(r, a.price, c.price, d.price);
   double en = RoundTick(d.price + side * span * InpEntryPct / 100.0);
   double stopLo = lo;
   double stopHi = hi;
   if(r.name == "Anti-Bat")
     {
      Rule stopRule = r;
      stopRule.d1 = 1.13;
      double slLo, slHi;
      bool stopValid = F_Zone(stopRule, x.price, a.price, b.price, c.price, side, slLo, slHi);
      if(stopValid) { stopLo = slLo; stopHi = slHi; }
     }
   double zl = stopLo - MathAbs(c.price - d.price) * InpZonePadPct / 100.0;
   double zh = stopHi + MathAbs(c.price - d.price) * InpZonePadPct / 100.0;
   double sl = (InpStopMode==HL_STOP_MANUAL)
               ? (en - side * MathAbs(en) * InpManualPct / 100.0)
               : ((side==1) ? zl : zh);
   sl = (side==1) ? MathMin(sl, en - g_tick) : MathMax(sl, en + g_tick);
   double risk = MathAbs(en - sl);
   double t1 = InpUseRR ? (en + side * risk * InpRR1) : (d.price + side * span * InpT1Pct / 100.0);
   double t2 = InpUseRR ? (en + side * risk * InpRR2) : (d.price + side * span * InpT2Pct / 100.0);
   t1 = RoundTick(t1);
   t2 = RoundTick(t2);
   t1 = (side==1) ? MathMax(t1, en + g_tick) : MathMin(t1, en - g_tick);
   t2 = (side==1) ? MathMax(t2, t1 + g_tick) : MathMin(t2, t1 - g_tick);

   Pattern *p = new Pattern();
   p.name = r.name;
   p.key = key;
   p.side = side;
   p.born = g_barIndex;
   p.state = 0;
   p.entry = en;
   p.t1 = t1;
   p.t2 = t2;
   p.stop = sl;
   p.zlo = zl;
   p.zhi = zh;
   p.best = en;
   p.dBar = d.idx;
   p.risk0 = MathAbs(en - sl);
   p.worst = en;
   p.quality = F_Quality(r, x.price, a.price, b.price, c.price, d.price);
   p.diverge = g_divOn && r.mode < 10 && (F_Div(side, b, d) || (r.mode != 2 && x.sign == d.sign && F_Div(side, x, d)));
   p.volSpike = g_volOn && r.mode < 10 && F_VolSpike(d);
   return(p);
  }

void PatternsPush(Pattern *p)
  {
   ArrayResize(g_patterns, g_nPat+1);
   g_patterns[g_nPat] = p;
   g_nPat++;
  }

void PatternsRemoveAt(const int idx)
  {
   if(idx<0 || idx>=g_nPat) return;
   delete g_patterns[idx];
   for(int i=idx;i<g_nPat-1;i++) g_patterns[i]=g_patterns[i+1];
   g_nPat--;
   ArrayResize(g_patterns, g_nPat);
  }

double F_SegmentPrice(const Pivot &p, const Pivot &q, const int idx)
  {
   return(p.price + (q.price - p.price) * (idx - p.idx) / MathMax(q.idx - p.idx, 1));
  }

int F_ExtremeBetween(const Swing &sw, const int fromIndex, const int toIndex, const int sign)
  {
   int best = fromIndex + 1;
   if(toIndex - fromIndex > 2)
     {
      for(int k=fromIndex+2; k<=toIndex-1; k++)
        {
         Pivot q = sw.points[k];
         if(q.sign==sign && (q.price - sw.points[best].price) * sign > 0.0)
            best = k;
        }
     }
   return(best);
  }

//====================================================================
// Classical extras
//====================================================================
void ExtraPush(ExtraFormation &arr[], int &n, const ExtraFormation &e)
  {
   ArrayResize(arr, n+1);
   arr[n] = e;
   n++;
  }

void F_ExtraCandidates(const Swing &sw, ExtraFormation &result[], int &nRes)
  {
   nRes = 0;
   ArrayResize(result, 0);
   int n = sw.n;
   int offset, k;
   double windowLow  = LowestLookback(InpMaxSize);
   double windowHigh = HighestLookback(InpMaxSize);

   if(n >= 4 && (InpUseDoubleTop || InpUseDoubleBottom))
     {
      int maxOff = (int)MathMin(3, n-3);
      for(offset=0; offset<=maxOff; offset++)
        {
         int ci = n - 1 - offset;
         Pivot c = sw.points[ci];
         int side = -c.sign;
         if((side==1 && InpUseDoubleBottom) || (side==-1 && InpUseDoubleTop))
           {
            for(int bi=ci-1; bi>=1; bi--)
              {
               Pivot b = sw.points[bi];
               if(b.sign==side && bi>=2)
                 {
                  for(int ai=bi-1; ai>=1; ai--)
                    {
                     Pivot a = sw.points[ai];
                     Pivot lead = sw.points[ai-1];
                     double height = (b.price - c.price) * side;
                     double tolerance = height * InpClassicTol / 100.0;
                     bool symmetric = (a.sign==c.sign && height > g_tick && MathAbs(a.price-c.price) <= tolerance);
                     bool approach = ((lead.price - b.price) * side > 0.0);
                     bool contained = symmetric && F_LegContained(sw, ai, bi) && F_LegContained(sw, bi, ci);
                     bool breakout = ((side==1) ? (g_high[g_barIndex] >= b.price) : (g_low[g_barIndex] <= b.price)) && (g_barIndex > c.idx);
                     if(symmetric && approach && contained && breakout &&
                        g_barIndex-a.idx >= InpMinSize && g_barIndex-a.idx <= InpMaxSize && nRes < InpCandidateLimit)
                       {
                        ExtraFormation e;
                        e.name = (side==1) ? "Double Bottom" : "Double Top";
                        e.npts = 4;
                        e.points[0]=lead; e.points[1]=a; e.points[2]=b; e.points[3]=c;
                        e.side=side; e.trigger=b.price; e.invalidation=c.price;
                        e.unit=height*1.5;
                        e.key = e.name+":"+IntegerToString(a.idx)+":"+IntegerToString(b.idx)+":"+IntegerToString(c.idx);
                        e.kind=10; e.dBar=0; e.dPrice=HL_NA;
                        ExtraPush(result, nRes, e);
                       }
                    }
                 }
              }
           }
        }
     }

   if(n >= 4 && (InpUseAscending || InpUseDescending || InpUseSymmetrical))
     {
      int maxOffT = (int)MathMin(1, n-4);
      for(offset=0; offset<=maxOffT; offset++)
        {
         Swing boundary; SwingCopy(boundary, sw);
         if(offset==1) SwingPop(boundary);
         Candidate tris[]; int nTri=0;
         F_AbcdCandidates(boundary, InpTriangleNested ? InpCandidateLimit : 1, tris, nTri);
         for(int ti=0; ti<nTri; ti++)
           {
            Pivot x = tris[ti].a;
            Pivot a = tris[ti].b;
            Pivot b = tris[ti].c;
            Pivot c = tris[ti].d;
            double width = MathAbs(x.price - a.price);
            double eps = width * InpClassicTol / 100.0;
            Pivot h0 = (x.sign==1)?x:a;
            Pivot h1 = (x.sign==1)?b:c;
            Pivot l0 = (x.sign==-1)?x:a;
            Pivot l1 = (x.sign==-1)?b:c;
            bool flatHigh = MathAbs(h1.price-h0.price) <= eps;
            bool flatLow  = MathAbs(l1.price-l0.price) <= eps;
            bool lowerHigh = h1.price < h0.price - eps;
            bool higherLow = l1.price > l0.price + eps;
            string name = "";
            if(flatHigh && higherLow && InpUseAscending) name = "Ascending Triangle";
            else if(flatLow && lowerHigh && InpUseDescending) name = "Descending Triangle";
            else if(lowerHigh && higherLow && InpUseSymmetrical) name = "Symmetrical Triangle";
            double upper = F_SegmentPrice(h0, h1, g_barIndex);
            double lower = F_SegmentPrice(l0, l1, g_barIndex);
            int side = -c.sign;
            double trigger = (side==1)?upper:lower;
            bool sized = (g_barIndex-x.idx >= InpMinSize && g_barIndex-x.idx <= InpMaxSize && g_barIndex-c.idx >= InpMinCD);
            bool crossed = ((g_close[g_barIndex] - trigger) * side > 0.0);
            double ab = MathAbs(b.price - a.price);
            double bc = MathAbs(c.price - b.price);
            bool retracements = (width > g_tick && ab > g_tick && ab/width >= InpTriMinRetrace && bc/ab >= InpTriMinRetrace);
            bool contracting = (h1.price <= h0.price && l1.price >= l0.price);
            if(contracting && retracements && sized && width > g_tick && upper > lower && name!="" && crossed && nRes < InpCandidateLimit)
              {
               ExtraFormation e;
               e.name=name; e.npts=4;
               e.points[0]=x; e.points[1]=a; e.points[2]=b; e.points[3]=c;
               e.side=side; e.trigger=trigger; e.invalidation=c.price; e.unit=width;
               e.key=name+":"+IntegerToString(x.idx)+":"+IntegerToString(a.idx)+":"+IntegerToString(b.idx)+":"+IntegerToString(c.idx)+":"+IntegerToString(side);
               e.kind=12;
               e.dBar=g_barIndex;
               e.dPrice=(side==1)?g_high[g_barIndex]:g_low[g_barIndex];
               for(k=c.idx+1; k<=g_barIndex; k++)
                 {
                  double v = (side==1)?g_high[k]:g_low[k];
                  if((v - e.dPrice)*side > 0.0) { e.dPrice=v; e.dBar=k; }
                 }
               ExtraPush(result, nRes, e);
              }
           }
        }
     }

   if(n >= 6)
     {
      int lastIdx = n - 1;
      for(int tail=0; tail<=InpHsTail; tail++)
        {
         int rIdx = lastIdx - tail;
         if(rIdx < 5) break;
         Pivot p4 = sw.points[rIdx];
         int side = -p4.sign;
         bool tailOK = (g_barIndex > p4.idx);
         if(tail > 0)
           {
            for(k=rIdx+1; k<=lastIdx; k++)
               if((sw.points[k].price - p4.price) * (-side) > 0.0) tailOK=false;
           }
         if(tailOK && ((side==1 && InpUseIHS) || (side==-1 && InpUseHS)))
           {
            bool taken = false;
            for(int skipH=0; skipH<=InpHsSkip; skipH++)
              {
               int hIdx = rIdx - 2 - 2*skipH;
               if(hIdx < 3 || taken) break;
               Pivot p2 = sw.points[hIdx];
               int m2 = F_ExtremeBetween(sw, hIdx, rIdx, side);
               Pivot p3 = sw.points[m2];
               if((p2.price - p4.price)*(-side) > 0.0 && F_LegContained(sw,hIdx,m2) && F_LegContained(sw,m2,rIdx))
                 {
                  for(int skipL=0; skipL<=InpHsSkip; skipL++)
                    {
                     int lIdx = hIdx - 2 - 2*skipL;
                     if(lIdx < 1 || taken) break;
                     Pivot p0 = sw.points[lIdx];
                     int m1 = F_ExtremeBetween(sw, lIdx, hIdx, side);
                     Pivot p1 = sw.points[m1];
                     Pivot lead = sw.points[lIdx-1];
                     if((p2.price - p0.price)*(-side) > 0.0 && F_LegContained(sw,lIdx,m1) && F_LegContained(sw,m1,hIdx))
                       {
                        bool sized = (g_barIndex-lead.idx >= InpMinSize && g_barIndex-lead.idx <= InpMaxSize);
                        double neck = p1.price;
                        double height = (neck - p2.price) * side;
                        bool shoulders = (height > g_tick && (p0.price-p2.price)*side > 0.0 &&
                                          (p4.price-p2.price)*side > 0.0 && (neck-p4.price)*side > 0.0 &&
                                          MathAbs(p0.price-p4.price) <= height * InpHsShoulderTol / 100.0);
                        bool approach = ((lead.price - neck) * side > 0.0);
                        bool flatNeck = (MathAbs(p3.price - neck) <= height * InpErrorPct / 100.0);
                        double rightDepth = (p2.price - p3.price) * (-side);
                        double lsRatio = (p0.price - neck) * (-side) / height;
                        double rsRatio = (rightDepth > g_tick) ? ((p4.price - p3.price) * (-side) / rightDepth) : 0.0;
                        bool shoulderRatios = F_Band(lsRatio, 0.382, 0.786) && F_Band(rsRatio, 0.382, 0.786);
                        double outerNeck = (side==1) ? MathMax(neck, p3.price) : MathMin(neck, p3.price);
                        bool broken = (side==1) ? (g_high[g_barIndex] > outerNeck) : (g_low[g_barIndex] < outerNeck);
                        bool dominant = (side==1) ? (p2.price <= windowLow + g_tick*0.1)
                                                  : (p2.price >= windowHigh - g_tick*0.1);
                        if(sized && shoulders && approach && flatNeck && shoulderRatios && dominant && broken && nRes < InpCandidateLimit)
                          {
                           ExtraFormation e;
                           e.name = (side==1) ? "Inverse Head and Shoulders" : "Head and Shoulders";
                           e.npts=6;
                           e.points[0]=lead; e.points[1]=p0; e.points[2]=p1;
                           e.points[3]=p2; e.points[4]=p3; e.points[5]=p4;
                           e.side=side;
                           double outer = (side==1) ? MathMax(neck, p3.price) : MathMin(neck, p3.price);
                           e.trigger=outer; e.invalidation=p2.price; e.unit=height;
                           e.key=e.name+":"+IntegerToString(p0.idx)+":"+IntegerToString(p2.idx)+":"+IntegerToString(p4.idx);
                           e.kind=11; e.dBar=0; e.dPrice=HL_NA;
                           ExtraPush(result, nRes, e);
                           taken = true;
                          }
                       }
                    }
                 }
              }
           }
        }
     }

   if(InpUseThreeDrive && n >= 5)
     {
      Pivot pts[5];
      for(k=0;k<5;k++) pts[k]=sw.points[n-5+k];
      Pivot p1=pts[0], p2=pts[1], p3=pts[2], p4=pts[3], p5=pts[4];
      int side = -p5.sign;
      double retrace1 = MathAbs(p2.price-p1.price);
      double drive2   = MathAbs(p3.price-p2.price);
      double retrace2 = MathAbs(p4.price-p3.price);
      double drive3   = MathAbs(p5.price-p4.price);
      bool positive = (MathMin(MathMin(retrace1, drive2), retrace2) > g_tick);
      bool geometry = ((p1.price-p3.price)*side > 0.0 && (p3.price-p5.price)*side > 0.0 && (p2.price-p4.price)*side > 0.0);
      bool ratios = positive && F_Band(drive2/retrace1, 1.272, 1.618) && F_Band(retrace2/drive2, 0.618, 0.786) && F_Band(drive3/retrace2, 1.272, 1.618);
      bool firstOK = true;
      if(n >= 6)
        {
         Pivot p0 = sw.points[n-6];
         double first = MathAbs(p1.price - p0.price);
         firstOK = (first > g_tick && (p0.price-p2.price)*side > 0.0 && F_Band(retrace1/first, 0.618, 0.786));
        }
      if(geometry && ratios && firstOK && g_barIndex-p1.idx >= InpMinSize && g_barIndex-p1.idx <= InpMaxSize && g_barIndex-p5.idx <= InpConfirmBars)
        {
         ExtraFormation e;
         e.name="3-Drive"; e.npts=5;
         for(k=0;k<5;k++) e.points[k]=pts[k];
         e.side=side; e.trigger=p5.price;
         e.invalidation = p5.price - side * drive3 * InpErrorPct / 100.0;
         e.unit = MathAbs(p2.price - p5.price);
         e.key="3-Drive:"+IntegerToString(p1.idx)+":"+IntegerToString(p5.idx);
         e.kind=13; e.dBar=0; e.dPrice=HL_NA;
         ExtraPush(result, nRes, e);
        }
     }
  }

Pattern *F_CreateExtra(const ExtraFormation &e)
  {
   Pivot first = e.points[0];
   Pivot last  = e.points[e.npts-1];
   Pivot anchor; anchor.price=e.trigger; anchor.idx=g_barIndex; anchor.sign=-e.side;
   Rule r;
   r.name=e.name; r.enabled=true;
   r.b0=0; r.b1=0; r.c0=0; r.c1=0; r.e0=0; r.e1=0; r.d0=e.unit; r.d1=0; r.mode=e.kind;
   double lo = (e.side==1) ? e.invalidation : e.trigger;
   double hi = (e.side==1) ? e.trigger : e.invalidation;
   if(e.kind==10)
     {
      double ext = (hi - lo) * (1.0 + InpErrorPct / 100.0);
      if(e.side==1) hi = lo + ext;
      else          lo = hi - ext;
     }
   if(e.kind==11)
     {
      double n1 = e.points[2].price;
      double n2 = e.points[4].price;
      double innerNeck = (e.side==1) ? MathMin(n1,n2) : MathMax(n1,n2);
      if(e.side==1) hi = innerNeck;
      else          lo = innerNeck;
     }
   if(e.kind==13)
     {
      Pivot bPt = e.points[2];
      Pivot cPt = e.points[3];
      double bc = MathAbs(cPt.price - bPt.price);
      double nearv = cPt.price - e.side * bc * 1.272 * (1.0 - InpErrorPct / 100.0);
      double farv  = cPt.price - e.side * bc * 1.618 * (1.0 + InpErrorPct / 100.0);
      lo = MathMin(nearv, farv);
      hi = MathMax(nearv, farv);
     }
   return(F_Create(r, first, first, last, last, anchor, lo, hi, e.key));
  }

//====================================================================
// Supply | Demand (data only; no boxes). HTF closed-bar, lookahead off.
//====================================================================
int MapTf(const int minutes)
  {
   if(minutes<=0) return(Period());
   if(minutes>=43200) return(PERIOD_MN1);
   if(minutes>=10080) return(PERIOD_W1);
   if(minutes>=1440)  return(PERIOD_D1);
   if(minutes>=240)   return(PERIOD_H4);
   if(minutes>=60)    return(PERIOD_H1);
   if(minutes>=30)    return(PERIOD_M30);
   if(minutes>=15)    return(PERIOD_M15);
   if(minutes>=5)     return(PERIOD_M5);
   if(minutes>=1)     return(PERIOD_M1);
   return(Period());
  }

double SdWidthFactor() { return(0.12 + InpSdWidth * 0.18); }
double SdDispFactor()  { return(MathMax(0.10, 1.15 - InpSdSensitivity * 0.10)); }

bool SdZoneExists(const double &tops[], const double &bots[], const int &lefts[],
                  const int n, const double zTop, const double zBottom, const int leftTime)
  {
   if(n<=0) return(false);
   int tfSec = g_sdTf * 60;
   for(int i=0;i<n;i++)
     {
      double zOldTop=tops[i], zOldBottom=bots[i];
      int zOldLeft=lefts[i];
      double zOverlap = MathMin(zOldTop, zTop) - MathMax(zOldBottom, zBottom);
      double zMinH = MathMin(zOldTop-zOldBottom, zTop-zBottom);
      // Pine compares ms timestamps; MT4 datetime is seconds.
      bool zCloseInTime = (MathAbs(zOldLeft - leftTime) <= tfSec * (InpSdPivotLen + 2));
      if(zOverlap > zMinH * 0.45 ||
         (zCloseInTime && MathAbs((zOldTop+zOldBottom)*0.5 - (zTop+zBottom)*0.5) <= zMinH*0.6))
         return(true);
     }
   return(false);
  }

void SdTrim(double &tops[], double &bots[], int &lefts[], int &n, const int maxCount)
  {
   while(n > maxCount)
     {
      n--;
      ArrayResize(tops, n);
      ArrayResize(bots, n);
      ArrayResize(lefts, n);
     }
  }

void SdAddZone(const bool isSupply, const double zTop, const double zBottom, const int leftTime)
  {
   int i;
   if(HlNa(zTop) || HlNa(zBottom) || !(zTop > zBottom)) return;
   if(isSupply)
     {
      if(SdZoneExists(g_sdSupplyTops, g_sdSupplyBots, g_sdSupplyLefts, g_nSdSup, zTop, zBottom, leftTime)) return;
      // unshift
      ArrayResize(g_sdSupplyTops, g_nSdSup+1);
      ArrayResize(g_sdSupplyBots, g_nSdSup+1);
      ArrayResize(g_sdSupplyLefts, g_nSdSup+1);
      for(i=g_nSdSup;i>0;i--)
        { g_sdSupplyTops[i]=g_sdSupplyTops[i-1]; g_sdSupplyBots[i]=g_sdSupplyBots[i-1]; g_sdSupplyLefts[i]=g_sdSupplyLefts[i-1]; }
      g_sdSupplyTops[0]=zTop; g_sdSupplyBots[0]=zBottom; g_sdSupplyLefts[0]=leftTime;
      g_nSdSup++;
      SdTrim(g_sdSupplyTops, g_sdSupplyBots, g_sdSupplyLefts, g_nSdSup, InpSdMaxPerSide);
     }
   else
     {
      if(SdZoneExists(g_sdDemandTops, g_sdDemandBots, g_sdDemandLefts, g_nSdDem, zTop, zBottom, leftTime)) return;
      ArrayResize(g_sdDemandTops, g_nSdDem+1);
      ArrayResize(g_sdDemandBots, g_nSdDem+1);
      ArrayResize(g_sdDemandLefts, g_nSdDem+1);
      for(i=g_nSdDem;i>0;i--)
        { g_sdDemandTops[i]=g_sdDemandTops[i-1]; g_sdDemandBots[i]=g_sdDemandBots[i-1]; g_sdDemandLefts[i]=g_sdDemandLefts[i-1]; }
      g_sdDemandTops[0]=zTop; g_sdDemandBots[0]=zBottom; g_sdDemandLefts[0]=leftTime;
      g_nSdDem++;
      SdTrim(g_sdDemandTops, g_sdDemandBots, g_sdDemandLefts, g_nSdDem, InpSdMaxPerSide);
     }
  }

void SdDeleteAt(double &tops[], double &bots[], int &lefts[], int &n, const int idx)
  {
   for(int i=idx;i<n-1;i++)
     { tops[i]=tops[i+1]; bots[i]=bots[i+1]; lefts[i]=lefts[i+1]; }
   n--;
   ArrayResize(tops, n);
   ArrayResize(bots, n);
   ArrayResize(lefts, n);
  }

void SdMaintain(const bool isSupply)
  {
   int i;
   double c = g_close[g_barIndex];
   if(isSupply)
     {
      for(i=g_nSdSup-1; i>=0; i--)
        {
         bool zInvalid = (c > g_sdSupplyTops[i]);
         if(InpSdHideMitigated && zInvalid)
            SdDeleteAt(g_sdSupplyTops, g_sdSupplyBots, g_sdSupplyLefts, g_nSdSup, i);
        }
     }
   else
     {
      for(i=g_nSdDem-1; i>=0; i--)
        {
         bool zInvalid = (c < g_sdDemandBots[i]);
         if(InpSdHideMitigated && zInvalid)
            SdDeleteAt(g_sdDemandTops, g_sdDemandBots, g_sdDemandLefts, g_nSdDem, i);
        }
     }
  }

bool SdOverlap(const double &tops[], const double &bots[], const int n, const double lo, const double hi)
  {
   for(int i=0;i<n;i++)
      if(bots[i] <= hi && tops[i] >= lo) return(true);
   return(false);
  }

// True Range + Wilder ATR on an HTF bar (shift is HTF shift, processing oldest→newest so we keep running ATR).
double TrueRangeHTF(const int shift, const double prevClose)
  {
   double h = iHigh(Symbol(), g_sdTf, shift);
   double l = iLow(Symbol(), g_sdTf, shift);
   if(HlNa(prevClose) || prevClose==0.0) return(h-l);
   double tr = MathMax(h-l, MathMax(MathAbs(h-prevClose), MathAbs(l-prevClose)));
   return(tr);
  }

void SdProcessClosedHtfBar(const int htfShift)
  {
   // htfShift is the just-closed HTF bar (1 = most recent closed when live).
   double h = iHigh(Symbol(), g_sdTf, htfShift);
   double l = iLow(Symbol(), g_sdTf, htfShift);
   double o = iOpen(Symbol(), g_sdTf, htfShift);
   double c = iClose(Symbol(), g_sdTf, htfShift);
   datetime tm = iTime(Symbol(), g_sdTf, htfShift);
   if(tm==0) return;

   double tr = TrueRangeHTF(htfShift, sd_trPrevClose);
   if(sd_atrN < 14)
     {
      sd_atrRma = HlNa(sd_atrRma) ? tr : (sd_atrRma + tr);
      sd_atrN++;
      if(sd_atrN==14) sd_atrRma /= 14.0;
     }
   else
     {
      sd_atrRma = (sd_atrRma * 13.0 + tr) / 14.0;
      sd_atrN++;
     }
   double atrV = (sd_atrN>=14) ? sd_atrRma : HL_NA;
   sd_trPrevClose = c;
   ArrayResize(sd_atrHist, sd_atrHistN+1);
   sd_atrHist[sd_atrHistN] = atrV;
   sd_atrHistN++;

   // pivothigh(high, len, len) on this closed bar: pivot is at htfShift+len relative to this bar.
   // When we process bars oldest-first, a pivot confirms on the bar `len` after the extreme.
   int plen = InpSdPivotLen;
   double sdPh = HL_NA, sdPl = HL_NA;
   // Need plen bars on each side of candidate. Candidate index in HTF series = this bar's index - plen.
   // Using shift coordinates: candidate shift = htfShift + plen (older).
   int hb = iBars(Symbol(), g_sdTf);
   int candShift = htfShift + plen;
   if(candShift + plen < hb && candShift - plen >= 0)
     {
      double pvH = iHigh(Symbol(), g_sdTf, candShift);
      double pvL = iLow(Symbol(), g_sdTf, candShift);
      bool isPH=true, isPL=true;
      for(int k=candShift-plen; k<=candShift+plen; k++)
        {
         if(k==candShift) continue;
         if(iHigh(Symbol(), g_sdTf, k) >= pvH) isPH=false;
         if(iLow(Symbol(), g_sdTf, k)  <= pvL) isPL=false;
        }
      if(isPH) sdPh = pvH;
      if(isPL) sdPl = pvL;
     }

   if(!HlNa(sdPh))
     {
      sd_sHigh    = iHigh(Symbol(), g_sdTf, htfShift + plen);
      sd_sLow     = iLow(Symbol(), g_sdTf, htfShift + plen);
      double so   = iOpen(Symbol(), g_sdTf, htfShift + plen);
      double sc   = iClose(Symbol(), g_sdTf, htfShift + plen);
      sd_sBodyLow = MathMin(so, sc);
      sd_sAtr     = (sd_atrHistN > plen) ? sd_atrHist[sd_atrHistN-1-plen] : atrV;
      sd_sTime    = iTime(Symbol(), g_sdTf, htfShift + plen);
      sd_sCount   = InpSdDisplaceWin + 1;
     }
   bool supplySig=false; double supplyTopV=HL_NA, supplyBotV=HL_NA; datetime supplyLeftV=0;
   if(sd_sCount>0 && !HlNa(sd_sHigh) && !HlNa(sd_sAtr))
     {
      if(c < sd_sLow - sd_sAtr * SdDispFactor())
        {
         double zBase = MathMax(sd_sHigh - sd_sBodyLow, g_tick * 4.0);
         double zHeight = MathMax(zBase, sd_sAtr * SdWidthFactor());
         supplySig = true;
         supplyTopV = sd_sHigh;
         supplyBotV = sd_sHigh - zHeight;
         supplyLeftV = sd_sTime;
         sd_sCount = 0;
         sd_sHigh = HL_NA;
        }
      else
         sd_sCount = sd_sCount - 1;
     }

   if(!HlNa(sdPl))
     {
      sd_dLow      = iLow(Symbol(), g_sdTf, htfShift + plen);
      sd_dHigh     = iHigh(Symbol(), g_sdTf, htfShift + plen);
      double d_o   = iOpen(Symbol(), g_sdTf, htfShift + plen);
      double d_c   = iClose(Symbol(), g_sdTf, htfShift + plen);
      sd_dBodyHigh = MathMax(d_o, d_c);
      sd_dAtr      = (sd_atrHistN > plen) ? sd_atrHist[sd_atrHistN-1-plen] : atrV;
      sd_dTime     = iTime(Symbol(), g_sdTf, htfShift + plen);
      sd_dCount    = InpSdDisplaceWin + 1;
     }
   bool demandSig=false; double demandTopV=HL_NA, demandBotV=HL_NA; datetime demandLeftV=0;
   if(sd_dCount>0 && !HlNa(sd_dLow) && !HlNa(sd_dAtr))
     {
      if(c > sd_dHigh + sd_dAtr * SdDispFactor())
        {
         double zBase2 = MathMax(sd_dBodyHigh - sd_dLow, g_tick * 4.0);
         double zHeight2 = MathMax(zBase2, sd_dAtr * SdWidthFactor());
         demandSig = true;
         demandTopV = sd_dLow + zHeight2;
         demandBotV = sd_dLow;
         demandLeftV = sd_dTime;
         sd_dCount = 0;
         sd_dLow = HL_NA;
        }
      else
         sd_dCount = sd_dCount - 1;
     }

   // Stash this HTF bar's outputs. Caller adds zone from PREVIOUS HTF bar on a new HTF bar
   // (signal[1] when time(htf) changes) — handled in SdOnChartBar.
   sd_lastSupplySig = supplySig;
   sd_lastDemandSig = demandSig;
   sd_lastSupTop = supplyTopV; sd_lastSupBot = supplyBotV; sd_lastSupLeft = supplyLeftV;
   sd_lastDemTop = demandTopV; sd_lastDemBot = demandBotV; sd_lastDemLeft = demandLeftV;
  }

void SdOnChartBar()
  {
   if(!InpSdEnable)
     {
      g_nSdSup=0; g_nSdDem=0;
      ArrayResize(g_sdSupplyTops,0); ArrayResize(g_sdSupplyBots,0); ArrayResize(g_sdSupplyLefts,0);
      ArrayResize(g_sdDemandTops,0); ArrayResize(g_sdDemandBots,0); ArrayResize(g_sdDemandLefts,0);
      return;
     }
   int sh = iBarShift(Symbol(), g_sdTf, g_time[g_barIndex], false);
   if(sh < 0) sh = 0;
   datetime curHtf = iTime(Symbol(), g_sdTf, sh);

   bool htfNew = (sd_prevHtfTime != 0 && curHtf != sd_prevHtfTime);
   if(htfNew && sd_hasPrev)
     {
      if(sd_prevSup && sd_prevSupLeft != 0)
         SdAddZone(true, sd_prevSupTop, sd_prevSupBot, (int)sd_prevSupLeft);
      if(sd_prevDem && sd_prevDemLeft != 0)
         SdAddZone(false, sd_prevDemTop, sd_prevDemBot, (int)sd_prevDemLeft);
     }

   // Process the HTF bar that just closed when HTF time changes. During first visit of an
   // HTF bar we do not update the machine (forming). When it closes (htfNew), process shift 1
   // relative to that moment — which is the closed bar.
   if(htfNew)
     {
      // closed HTF bar is the previous one: shift of sd_prevHtfTime
      int closedSh = iBarShift(Symbol(), g_sdTf, sd_prevHtfTime, false);
      if(closedSh >= 0)
         SdProcessClosedHtfBar(closedSh);
      sd_prevSup = sd_lastSupplySig; sd_prevDem = sd_lastDemandSig;
      sd_prevSupTop = sd_lastSupTop; sd_prevSupBot = sd_lastSupBot; sd_prevSupLeft = sd_lastSupLeft;
      sd_prevDemTop = sd_lastDemTop; sd_prevDemBot = sd_lastDemBot; sd_prevDemLeft = sd_lastDemLeft;
      sd_hasPrev = true;
     }
   else if(sd_prevHtfTime==0)
     {
      // seed: process all older closed HTF bars once via sequential walk on first bars
      sd_hasPrev = false;
     }
   sd_prevHtfTime = curHtf;

   SdMaintain(true);
   SdMaintain(false);
  }

//====================================================================
// Lifecycle + detection on a confirmed bar
//====================================================================
void AdvancePatterns()
  {
   double c = g_close[g_barIndex];
   double h = g_high[g_barIndex];
   double l = g_low[g_barIndex];
   double o = g_open[g_barIndex];

   for(int i=0;i<g_nPat;i++)
     {
      Pattern *p = g_patterns[i];
      if(p.state >= 3) continue;
      bool expired = (g_barIndex - p.born >= InpMaxAge);
      if(expired)
        {
         p.state = 6;
         g_expiredCount++;
         g_expiredSignal = true;
         F_Emit(p, "Expired", InpAExpired);
         CloseTrade(p, "Expired");
        }
      else if(p.state == 0)
        {
         double badPrice = (InpInvalidSource==HL_SRC_CLOSE) ? c : ((p.side==1)?l:h);
         bool invalid = (p.side==1) ? (badPrice < p.zlo) : (badPrice > p.zhi);
         bool nearZone = (p.side==1) ? (l <= p.zhi) : (h >= p.zlo);
         bool touched;
         if(InpEntryMode==HL_ENTRY_CLOSE)      touched = ((c - p.entry) * p.side >= 0.0);
         else if(InpEntryMode==HL_ENTRY_CANDLE) touched = (nearZone && F_CandleOK(p.side));
         else                                   touched = (p.side==1) ? (h >= p.entry) : (l <= p.entry);
         bool overshot = ((o - p.t1) * p.side >= 0.0) ||
                         (InpEntryMode != HL_ENTRY_TOUCH && ((c - p.t1) * p.side >= 0.0));
         if(invalid || (touched && overshot))
           {
            p.state = 5;
            g_invalidCount++;
            g_invalidSignal = true;
            F_Emit(p, "Invalidated", InpAInvalid);
           }
         else if(touched)
           {
            p.state = 1;
            p.entryBar = g_barIndex;
            p.best = c;
            g_enteredCount++;
            F_Perf(p.name, 0);
            if(p.side==1) g_buySignal = true;
            else          g_sellSignal = true;
            F_Emit(p, "Entry", InpAEntry);
            OpenTrade(p);
            bool touchStop = (InpEntryMode==HL_ENTRY_TOUCH) && F_StopHit(p.side, p.stop, c, h, l);
            if(touchStop)
              {
               p.state = 4;
               g_stopCount++;
               F_Perf(p.name, 3);
               F_PerfResult(p, (InpStopSource==HL_SRC_CLOSE)?c:p.stop, false);
               g_stopSignal = true;
               F_Emit(p, "Stop (entry bar ambiguity)", InpAStop);
               CloseTrade(p, "Stop entry bar");
              }
            else if(InpEntryMode==HL_ENTRY_TOUCH)
              {
               bool sameBarT1 = (p.side==1) ? (h >= p.t1) : (l <= p.t1);
               bool sameBarT2 = (p.side==1) ? (h >= p.t2) : (l <= p.t2);
               if(sameBarT1)
                 {
                  p.state = 2;
                  p.reachedT1 = true;
                  g_target1Count++;
                  F_Perf(p.name, 1);
                  F_PerfResult(p, p.t1, true);
                  g_hitT1Signal = true;
                  F_Emit(p, "Target 1", InpAT1);
                 }
               if(sameBarT2)
                 {
                  p.state = 3;
                  g_target2Count++;
                  F_Perf(p.name, 2);
                  g_hitT2Signal = true;
                  F_Emit(p, "Target 2", InpAT2);
                  CloseTrade(p, "T2");
                 }
              }
           }
        }
      else
        {
         bool stopped = F_StopHit(p.side, p.stop, c, h, l);
         bool hit1 = (p.side==1) ? (h >= p.t1) : (l <= p.t1);
         bool hit2 = (p.side==1) ? (h >= p.t2) : (l <= p.t2);
         if(stopped)
           {
            p.state = 4;
            g_stopCount++;
            if(!p.reachedT1)
              {
               F_Perf(p.name, 3);
               F_PerfResult(p, (InpStopSource==HL_SRC_CLOSE)?c:p.stop, false);
              }
            g_stopSignal = true;
            F_Emit(p, "Stop", InpAStop);
            CloseTrade(p, "Stop");
           }
         else
           {
            if(p.state==1 && hit1)
              {
               p.state = 2;
               p.reachedT1 = true;
               g_target1Count++;
               F_Perf(p.name, 1);
               F_PerfResult(p, p.t1, true);
               g_hitT1Signal = true;
               F_Emit(p, "Target 1", InpAT1);
               if(InpKeepUntil==HL_KEEP_T1)
                 {
                  // keepUntil T1 is applied below after hit2 check in Pine:
                  // if state==2 and keepUntil==T1 then state=3 — handled next.
                 }
              }
            if(hit2)
              {
               p.state = 3;
               g_target2Count++;
               F_Perf(p.name, 2);
               g_hitT2Signal = true;
               F_Emit(p, "Target 2", InpAT2);
               CloseTrade(p, "T2");
              }
            else if(p.state==2 && InpKeepUntil==HL_KEEP_T1)
              {
               p.state = 3;
               CloseTrade(p, "T1 keepUntil");
              }
            if(p.state < 3)
              {
               p.best  = (p.side==1) ? MathMax(p.best, h) : MathMin(p.best, l);
               p.worst = (p.side==1) ? MathMin(p.worst, l) : MathMax(p.worst, h);
               double nextStop = p.stop;
               if(InpStopMode==HL_STOP_BE && p.state==2)
                  nextStop = p.entry + (p.t1 - p.entry) * InpBePct / 100.0;
               if(InpStopMode==HL_STOP_TRAIL && (InpTrailAfter==HL_TRAIL_ENTRY || p.state==2))
                  nextStop = p.best - p.side * MathAbs(p.t1 - p.entry) * InpTrailMult;
               p.stop = (p.side==1) ? MathMax(p.stop, nextStop) : MathMin(p.stop, nextStop);
               ModifyTradeSL(p);
              }
           }
        }
      if(p.state >= 3) p.doneBar = g_barIndex;
     }
  }

void DetectHarmonic(int &added)
  {
   int ri;
   double c = g_close[g_barIndex];
   bool inSess = InSessionAt(g_time[g_barIndex]);
   bool afterStart = (g_time[g_barIndex] >= InpStartDate);

   for(int scale=0; scale<=2; scale++)
     {
      Swing sw = g_swings[scale];
      int depth = InpDepth * (scale+1);
      double ph = PivotHighAt(depth, InpConfirmBars);
      double pl = PivotLowAt(depth, InpConfirmBars);
      bool rolling = (InpSwingMethod==HL_SWING_ROLLING);
      bool newHigh = (g_high[g_barIndex] == HighestLookback(depth));
      bool newLow  = (g_low[g_barIndex]  == LowestLookback(depth));
      bool changed = rolling ? F_UpdateRolling(g_swings[scale], newHigh, newLow)
                             : F_Update(g_swings[scale], ph, pl);
      sw = g_swings[scale];
      int nn = sw.n;
      bool developing = (!rolling && InpDMode==HL_DMODE_DEVELOPING);
      bool roomLeft = (added < InpMaxPerBar && F_Active() < InpMaxActive);
      if((developing || changed) && roomLeft && nn >= (developing?3:4) &&
         (scale==0 || InpMultiscale) && inSess && afterStart)
        {
         Candidate cands[]; int nC=0;
         if(developing) F_LiveCandidates(sw, newHigh, newLow, cands, nC);
         else if(nn>=4) F_Candidates(sw, 0, cands, nC);

         for(int ci=0; ci<nC; ci++)
           {
            Pivot x=cands[ci].x, a=cands[ci].a, b=cands[ci].b, cc=cands[ci].c, d=cands[ci].d;
            int side = -d.sign;
            double cxa = MathAbs(a.price - x.price);
            double cab = MathAbs(b.price - a.price);
            double cbc = MathAbs(cc.price - b.price);
            double cxc = MathAbs(cc.price - x.price);
            bool abcdCandidate = (x.idx == a.idx);
            double rAB = (abcdCandidate || cxa <= g_tick) ? HL_NA : cab/cxa;
            double rBC = (cab <= g_tick) ? HL_NA : cbc/cab;
            double rXC = (abcdCandidate || cxa <= g_tick) ? HL_NA : cxc/cxa;
            bool anyFamily = false;
            for(ri=0; ri<HL_RULES; ri++)
              {
               Rule r = g_rules[ri];
               if(r.enabled && ((r.mode==2)==abcdCandidate))
                 {
                  bool bOK = (r.mode==2) || (!HlNa(rAB) && F_Band(rAB, r.b0, r.b1));
                  bool cOK = (r.mode==1) ? (!HlNa(rXC) && F_Band(rXC, r.c0, r.c1))
                                         : (!HlNa(rBC) && F_Band(rBC, r.c0, r.c1));
                  if(bOK && cOK) { anyFamily=true; break; }
                 }
              }
            for(ri=0; ri<HL_RULES; ri++)
              {
               Rule r = g_rules[ri];
               bool bPre = (r.mode==2) || (!HlNa(rAB) && F_Band(rAB, r.b0, r.b1));
               bool cPre = (r.mode==1) ? (!HlNa(rXC) && F_Band(rXC, r.c0, r.c1))
                                       : (!HlNa(rBC) && F_Band(rBC, r.c0, r.c1));
               int spanBars = d.idx - ((r.mode==2)?a.idx:x.idx);
               double top = MathMax(MathMax(a.price, cc.price), MathMax(b.price, d.price));
               double bottom = MathMin(MathMin(a.price, cc.price), MathMin(b.price, d.price));
               if(r.mode != 2) { top=MathMax(top,x.price); bottom=MathMin(bottom,x.price); }
               double heightPct = 100.0 * (top - bottom) / MathMax(MathAbs(d.price), g_tick);
               bool sizeOK = (spanBars >= InpMinSize && spanBars <= InpMaxSize &&
                              d.idx - cc.idx >= InpMinCD && heightPct >= InpMinHeight);
               if(anyFamily && bPre && cPre && r.enabled && ((r.mode==2)==(x.idx==a.idx)) &&
                  F_TimeOK(r.mode, a.idx, b.idx, cc.idx, d.idx) && F_Allowed(side) && sizeOK &&
                  added < InpMaxPerBar && F_Active() < InpMaxActive &&
                  !F_Blocked(r.name, side) && !F_AutoBlocked(r.name))
                 {
                  double lo, hi;
                  bool valid = F_Zone(r, x.price, a.price, b.price, cc.price, side, lo, hi);
                  bool dOK = valid && d.price >= lo && d.price <= hi;
                  double padding = MathAbs(cc.price - d.price) * InpZonePadPct / 100.0;
                  bool closeOK = (!InpRequireZone) || (c >= lo - padding && c <= hi + padding);
                  bool liveOK = (side==1) ? (c >= lo - padding) : (c <= hi + padding);
                  string key = r.name+":"+IntegerToString((r.mode==2)?a.idx:x.idx)+":"+IntegerToString(a.idx)+":"+
                               IntegerToString(b.idx)+":"+IntegerToString(cc.idx)+":"+IntegerToString(d.idx);
                  double candidateEntry = d.price + side * F_Unit(r, a.price, cc.price, d.price) * InpEntryPct / 100.0;
                  bool entrySideOK = (!InpRequireEntrySide) ||
                                     ((c - candidateEntry) * side <= MathAbs(candidateEntry) * InpEntryOvershoot / 100.0);
                  bool preferred = true;
                  if(InpNoSame && r.name=="Anti-Nen Star" && dOK && closeOK && liveOK && entrySideOK)
                    {
                     for(int aj=0; aj<nC; aj++)
                       {
                        Candidate alt = cands[aj];
                        if(alt.x.idx < x.idx && alt.a.idx==a.idx && alt.b.idx==b.idx &&
                           alt.c.idx==cc.idx && alt.d.idx==d.idx && d.idx-alt.x.idx <= InpMaxSize)
                          {
                           double altLo, altHi;
                           bool altValid = F_Zone(r, alt.x.price, a.price, b.price, cc.price, side, altLo, altHi);
                           double altTop = MathMax(MathMax(MathMax(a.price, cc.price), MathMax(b.price, d.price)), alt.x.price);
                           double altBottom = MathMin(MathMin(MathMin(a.price, cc.price), MathMin(b.price, d.price)), alt.x.price);
                           bool altHeight = 100.0*(altTop-altBottom)/MathMax(MathAbs(d.price), g_tick) >= InpMinHeight;
                           bool altClose = (!InpRequireZone) || (c >= altLo-padding && c <= altHi+padding);
                           bool altLive = (side==1) ? (c >= altLo-padding) : (c <= altHi+padding);
                           if(altValid && d.price>=altLo && d.price<=altHi && altHeight && altClose && altLive)
                              preferred = false;
                          }
                       }
                    }
                  string gkey = IntegerToString((r.mode==2)?a.idx:x.idx)+":"+IntegerToString(a.idx)+":"+
                                IntegerToString(b.idx)+":"+IntegerToString(cc.idx)+":"+IntegerToString(d.idx);
                  double qv = F_Quality(r, x.price, a.price, b.price, cc.price, d.price);
                  bool qualityOK = (g_qualityMin <= 0.0) || (!HlNa(qv) && qv >= g_qualityMin);
                  bool volumeOK = (!g_volRequire) || F_VolSpike(d);
                  if(preferred && qualityOK && volumeOK && dOK && closeOK && liveOK && entrySideOK &&
                     !SeenHas(g_seen, g_nSeen, key) && !SeenHas(g_seenGeom, g_nSeenGeom, gkey))
                    {
                     Pattern *p = F_Create(r, x, a, b, cc, d, lo, hi, key);
                     PatternsPush(p);
                     SeenPush(g_seen, g_nSeen, key, HL_SEEN_CAP);
                     SeenPush(g_seenGeom, g_nSeenGeom, gkey, HL_SEEN_CAP);
                     g_foundCount++;
                     added++;
                     g_newSignal = true;
                     F_Emit(p, "New pattern", InpANew);
                     if(p.diverge) F_Emit(p, "RSI divergence", g_aDiv);
                     if(p.volSpike) F_Emit(p, "Volume confirmation", g_aVol);
                    }
                 }
              }
           }
        }
     }
  }

void DetectExtras(int &added)
  {
   bool inSess = InSessionAt(g_time[g_barIndex]);
   bool afterStart = (g_time[g_barIndex] >= InpStartDate);
   double c = g_close[g_barIndex];
   for(int scale=0; scale<=2; scale++)
     {
      if(!((scale==0 || InpMultiscale) && inSess && afterStart && added < InpMaxPerBar && F_Active() < InpMaxActive))
         continue;
      Swing sw = g_swings[scale];
      ExtraFormation extras[]; int nE=0;
      F_ExtraCandidates(sw, extras, nE);
      for(int ei=0; ei<nE; ei++)
        {
         ExtraFormation e = extras[ei];
         bool allowed = F_Allowed(e.side) && !F_Blocked(e.name, e.side) && !F_AutoBlocked(e.name) &&
                        !SeenHas(g_seen, g_nSeen, e.key);
         bool riskSide = ((e.trigger - e.invalidation) * e.side > g_tick);
         bool liveOK = ((c - e.invalidation) * e.side >= 0.0);
         double en = e.trigger + e.side * e.unit * InpEntryPct / 100.0;
         bool entrySideOK = (!InpRequireEntrySide) ||
                            ((c - en) * e.side <= MathAbs(en) * InpEntryOvershoot / 100.0);
         double formationHigh = e.trigger, formationLow = e.trigger;
         for(int pi=0; pi<e.npts; pi++)
           {
            formationHigh = MathMax(formationHigh, e.points[pi].price);
            formationLow  = MathMin(formationLow,  e.points[pi].price);
           }
         bool heightOK = 100.0*(formationHigh-formationLow)/MathMax(MathAbs(e.trigger), g_tick) >= InpMinHeight;
         bool zoneOK = (!InpRequireZone) || (c >= MathMin(e.invalidation, e.trigger) && c <= MathMax(e.invalidation, e.trigger));
         if(allowed && riskSide && liveOK && entrySideOK && heightOK && zoneOK &&
            added < InpMaxPerBar && F_Active() < InpMaxActive)
           {
            Pattern *p = F_CreateExtra(e);
            PatternsPush(p);
            SeenPush(g_seen, g_nSeen, e.key, HL_SEEN_CAP);
            added++;
            g_foundCount++;
            g_newSignal = true;
            F_Emit(p, "New pattern", InpANew);
           }
        }
     }
  }

void CleanupCompleted()
  {
   int completed = g_nPat - F_Active();
   int idx = 0;
   int minKeep = 0;
   while(idx < g_nPat)
     {
      Pattern *old = g_patterns[idx];
      bool stale = (old.state >= 4) || (old.doneBar >= 0 && g_barIndex - old.doneBar > InpMaxAge) || (completed > 12);
      if(old.state >= 3 && stale && completed > minKeep)
        {
         PatternsRemoveAt(idx);
         completed--;
        }
      else idx++;
     }
  }

void ZoneConfluence()
  {
   if(!(InpSdEnable && InpSdConfluence)) return;
   for(int i=0;i<g_nPat;i++)
     {
      Pattern *p = g_patterns[i];
      if(p.state <= 1 && !p.inZone)
        {
         bool hit = (p.side==1)
                    ? SdOverlap(g_sdDemandTops, g_sdDemandBots, g_nSdDem, p.zlo, p.zhi)
                    : SdOverlap(g_sdSupplyTops, g_sdSupplyBots, g_nSdSup, p.zlo, p.zhi);
         if(hit)
           {
            p.inZone = true;
            g_zoneSignal = true;
            F_Emit(p, (p.side==1) ? "Demand zone confluence" : "Supply zone confluence", InpAZone);
           }
        }
     }
  }

void EndBarBridgedInputs()
  {
   // Applied AFTER detection, so the next bar sees the updated values (Pine order).
   g_qualityMin = (double)InpQualityMin;
   g_qualityInName = true;
   g_divOn = InpDivShow;
   g_divMark = InpDivMark;
   g_aDiv = InpADiv;
   g_volOn = InpVolShow;
   g_volMult = InpVolMult;
   g_volMark = InpVolMark;
   g_volRequire = InpVolRequire;
   g_aVol = InpAVol;
   g_alertJson = (InpAlertFormat==HL_ALERT_JSON);
   g_alertBotId = InpAlertBotId;
   g_confluenceMark = InpSdConfluenceMark;
   g_perfDeep = true;
   g_perfAutoMin = (double)InpPerfAutoMin;

   g_trendOn = (InpTrendMode != HL_TREND_OFF);
   if(g_trendOn)
     {
      int len = InpTrendLen;
      int ti;
      if(InpTrendMode==HL_TREND_SMA)
        {
         if(g_barIndex+1 >= len)
           {
            double s=0;
            for(ti=g_barIndex-len+1;ti<=g_barIndex;ti++) s+=g_close[ti];
            g_trendMa = s / len;
           }
         else g_trendMa = HL_NA;
        }
      else
        {
         static double ema = HL_NA;
         static bool emaSeeded=false;
         if(g_barIndex==0) { ema=HL_NA; emaSeeded=false; }
         if(!emaSeeded)
           {
            if(g_barIndex+1 >= len)
              {
               double s=0;
               for(ti=g_barIndex-len+1;ti<=g_barIndex;ti++) s+=g_close[ti];
               ema = s / len;
               emaSeeded=true;
               g_trendMa = ema;
              }
            else g_trendMa = HL_NA;
           }
         else
           {
            double alpha = 2.0 / (len + 1.0);
            ema = alpha * g_close[g_barIndex] + (1.0 - alpha) * ema;
            g_trendMa = ema;
           }
        }
     }
   else g_trendMa = HL_NA;
  }

void ProcessConfirmedBar()
  {
   g_buySignal=g_sellSignal=g_newSignal=false;
   g_hitT1Signal=g_hitT2Signal=g_stopSignal=false;
   g_invalidSignal=g_expiredSignal=g_zoneSignal=false;

   AdvancePatterns();
   int added = 0;
   DetectHarmonic(added);
   DetectExtras(added);
   CleanupCompleted();

   SdOnChartBar();
   ZoneConfluence();
   EndBarBridgedInputs();
  }

void ReplayHistory()
  {
   int total = Bars;
   int cap = 5000;
   int oldest = MathMin(total - 1, cap);
   if(oldest < InpMinSize) return;

   g_replaying = true;
   g_isRealtime = false;

   for(int sh=oldest; sh>=1; sh--)
     {
      PushSeriesBar(Open[sh], High[sh], Low[sh], Close[sh], (double)Volume[sh], Time[sh]);
      ProcessConfirmedBar();
     }
   g_replaying = false;
  }

void CommentState()
  {
   string s = "Harmonic Lab MT4 | active "+IntegerToString(F_Active())+
              " | found "+IntegerToString(g_foundCount)+
              " | entry "+IntegerToString(g_enteredCount)+
              " | T1 "+IntegerToString(g_target1Count)+
              " | T2 "+IntegerToString(g_target2Count)+
              " | stop "+IntegerToString(g_stopCount)+
              " | inv "+IntegerToString(g_invalidCount)+
              " | exp "+IntegerToString(g_expiredCount);
   Comment(s);
  }

//====================================================================
int OnInit()
  {
   g_tick = TickSize();
   g_digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   if(g_digits<=0) g_digits = Digits;

   if(InpMinSize > InpMaxSize)
     {
      Alert("Minimum pattern bars must not exceed maximum.");
      return(INIT_FAILED);
     }
   if(!InpUseRR && (InpEntryPct >= InpT1Pct || InpT1Pct >= InpT2Pct))
     {
      Alert("Require Entry % < Target 1 % < Target 2 %.");
      return(INIT_FAILED);
     }
   if(InpUseRR && InpRR1 >= InpRR2)
     {
      Alert("Target 2 reward/risk must exceed Target 1.");
      return(INIT_FAILED);
     }

   int i;
   for(i=0;i<g_nPat;i++) delete g_patterns[i];
   g_nPat=0;
   ArrayResize(g_patterns,0);
   ArrayResize(g_open,0); ArrayResize(g_high,0); ArrayResize(g_low,0);
   ArrayResize(g_close,0); ArrayResize(g_vol,0); ArrayResize(g_time,0);
   ArrayResize(g_rsi,0); ArrayResize(g_volAvg,0);
   g_bars=0; g_barIndex=-1;
   g_nSeen=0; g_nSeenGeom=0; ArrayResize(g_seen,0); ArrayResize(g_seenGeom,0);
   g_foundCount=g_enteredCount=g_target1Count=g_target2Count=0;
   g_stopCount=g_invalidCount=g_expiredCount=0;
   g_nPerf=0;
   g_rsiAvgGain=0; g_rsiAvgLoss=0; g_rsiSeeded=false; g_volSmaSum=0;
   g_nSdSup=0; g_nSdDem=0;
   ArrayResize(g_sdSupplyTops,0); ArrayResize(g_sdSupplyBots,0); ArrayResize(g_sdSupplyLefts,0);
   ArrayResize(g_sdDemandTops,0); ArrayResize(g_sdDemandBots,0); ArrayResize(g_sdDemandLefts,0);
   sd_sHigh=HL_NA; sd_sCount=0; sd_dLow=HL_NA; sd_dCount=0;
   sd_atrRma=HL_NA; sd_atrN=0; sd_trPrevClose=HL_NA;
   sd_atrHistN=0; ArrayResize(sd_atrHist,0);
   sd_prevHtfTime=0; sd_hasPrev=false;

   InitRules();
   for(i=0;i<HL_SCALES;i++) g_swings[i].n=0;

   int chartTfSec = Period() * 60;
   int wantSec = InpSdZoneTf * 60;
   if(InpSdZoneTf<=0 || wantSec < chartTfSec) g_sdTf = Period();
   else g_sdTf = MapTf(InpSdZoneTf);

   // Bridged defaults (Pine var initialisers) — first bar uses these.
   g_trendMa = HL_NA; g_trendOn=false;
   g_divOn=true; g_divMark="↯"; g_aDiv=true;
   g_volOn=true; g_volMult=1.5; g_volMark="⚡"; g_volRequire=false; g_aVol=true;
   g_qualityMin=0; g_qualityInName=true;
   g_alertJson=false; g_alertBotId="";
   g_confluenceMark="⭐";
   g_perfAutoMin=0; g_perfDeep=true;

   if(!IsTesting() && !IsOptimization())
     {
      ReplayHistory();
      g_lastChartBar = Time[0];
     }
   else
     {
      g_replaying = false;
      g_isRealtime = false;
      g_lastChartBar = 0;
     }

   CommentState();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   for(int i=0;i<g_nPat;i++) delete g_patterns[i];
   g_nPat=0;
   ArrayResize(g_patterns,0);
   Comment("");
  }

void OnTick()
  {
   if(Bars < InpMinSize + InpConfirmBars + 5) return;

   bool newBar = (Time[0] != g_lastChartBar);
   if(IsTesting() || IsOptimization())
     {
      // In the tester, process each newly formed confirmed bar (the bar that just closed).
      if(!newBar && g_bars>0) { /* intra-bar: lifecycle is close-gated, skip */ return; }
     }
   else
     {
      if(!newBar) return;
     }

   if(newBar)
     {
      // Confirm the bar that just closed: shift 1.
      if(Time[1] != 0)
        {
         bool already = (g_bars>0 && g_time[g_bars-1]==Time[1]);
         if(!already)
           {
            g_isRealtime = (!g_replaying && !IsTesting() && !IsOptimization());
            // During tester, treat as confirmed historical-but-tradeable (alerts still off).
            if(IsTesting() || IsOptimization()) g_isRealtime = false;
            PushSeriesBar(Open[1], High[1], Low[1], Close[1], (double)Volume[1], Time[1]);
            ProcessConfirmedBar();
           }
        }
      g_lastChartBar = Time[0];
      CommentState();
     }
  }
//+------------------------------------------------------------------+
