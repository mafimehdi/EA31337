//+------------------------------------------------------------------+
//|                                       XAUUSD_AMD_Fusion_v340.mq4 |
//|   Hybrid Architecture: XAUUSD_AMD_Liquidity v3.30 (HYBRID_04)    |
//|              + GoldFusion v6.3 Institutional Modules             |
//|                                                                  |
//|   1. Core Spine (90%): Locked HYBRID_04 (118 trades, 88.14% WR,  |
//|      +$9,412.31 Net Profit, 10.00% MaxDD, $79.77 Payoff):        |
//|      - M15 NY Micro-Killzones (16:00-18:15 & 20:00-20:45)        |
//|      - Step Compounding ($165/0.01 lot, 3.0% risk, 1.95R TP)     |
//|      - 3-Stage Step-Lock (+0.92R->+0.60R & 50% Partial,          |
//|        +1.30R->+1.15R, +1.62R->+1.50R)                           |
//|   2. GoldFusion v6.3 Modules (10% - Bug-Fixed & R-Normalized):   |
//|      - Engine 4 (GF_SP2L): 2-Bar Spike (>=1.2x ATR21, Body>=45%) |
//|        + FVG Gap + 2-Leg Pullback + Breakout, upgraded with      |
//|        Single-Use Spike Tracking & Step-Lock R-Management        |
//|      - Warm-Up Fixed UT Bot (KeyValue=1.0, ATR=21) & BB/SMA50    |
//|        Slope Filter with selectable scope (Engine4-Only,         |
//|        Long-Only to boost 82.14% BUY WR, or All-Engines)         |
//|      - Optional Dedicated Pre-NY Session (14:00-15:30 Broker)    |
//|        with separate trade counter (zero slot theft from NY AM)  |
//|      - Pre-Step1 Confirmed Reversal Quorum Shield (protects      |
//|        un-locked losing positions without cutting Step1 runners) |
//+------------------------------------------------------------------+
#property copyright "EA31337 Quantitative Research - XAUUSD AMD + GoldFusion v3.40"
#property link      "https://github.com/mafimehdi/EA31337"
#property version   "3.40"
#property strict

enum ENUM_M15_PRESET
  {
   M15_ULTRA_TUNED_PF384    = 0, // HYBRID_04 Base + Engine 4 SP2L
   M15_NY_PLUS_LONDON       = 1, // M15 NY + London 10:00 Session
   M15_CUSTOM_INPUTS        = 2  // Use Custom Input Parameters Below
  };

enum ENUM_ENTRY_MODE
  {
   ENTRY_SHALLOW_15_FVG     = 0, // 15% Shallow FVG Limit (1-Bar Fast Expiry)
   ENTRY_MARKET_CLOSE       = 1  // Immediate Market Execution on Confirmation Close
  };

enum ENUM_GF_FILTER_SCOPE
  {
   GF_FILTER_OFF            = 0, // Off (Pure AMD Slope Filter Only)
   GF_FILTER_ENGINE4_ONLY   = 1, // Apply UT+BB50 Only to Engine 4 (SP2L) & Pre-NY
   GF_FILTER_LONG_ONLY      = 2, // Apply UT+BB50 to BUY Signals (+Engine 4)
   GF_FILTER_ALL_ENGINES    = 3  // Apply UT+BB50 to All Engines (BUY & SELL)
  };

//--- Input Parameters
input string               Sep0                        = "=== 0. M15 Optimization Preset ===";
input ENUM_M15_PRESET      M15_Preset                  = M15_CUSTOM_INPUTS;
input int                  Magic_Number                = 3133740;
input int                  Broker_Winter_GMT           = 2;       // Broker Winter GMT Offset (2 for EET/EEST)
input bool                 Auto_Broker_DST             = true;    // Broker uses GMT+3 in Summer & GMT+2 in Winter
input bool                 Auto_US_DST                 = true;    // Adjust NY Time for US Daylight Saving Time
input int                  Max_Spread_Points           = 120;     // Max Allowed Spread in MT4 Points
input bool                 Ignore_Spread_In_Tester     = true;    // Bypass Spread Filter inside MT4 Strategy Tester

input string               Sep1                        = "=== 1. Risk, Compounding & 3-Stage Step-Lock (HYBRID_04) ===";
input bool                 Use_Step_Compounding        = true;    // Auto-Scale Lots as $500 Account Grows
input double               Balance_Per_001_Lot         = 165.0;   // +0.01 Lot per $165 Balance (HYBRID_04 10K Master)
input double               Risk_Percent_Per_Trade      = 3.0;     // Risk % of Account Balance per Trade (3.0%)
input double               Fixed_Lots_Fallback         = 0.01;    // Base Lot Size on $500 Accounts
input double               RR_Target                   = 1.95;    // Take-Profit Risk:Reward Ratio (1.95R)
input bool                 Use_StepLock_Profit         = true;    // Enable High-Retention 3-Stage Step-Lock Trailing
input double               Trigger_Step1_R             = 0.92;    // Step 1 Trigger (+0.92R) -> Locks +0.60R & 50% Partial
input double               Lock_R_At_Step1             = 0.60;    // Profit Locked at Step 1 (+0.60R)
input double               Trigger_Step2_R             = 1.30;    // Step 2 Trigger (+1.30R) -> Locks +1.15R
input double               Lock_R_At_Step2             = 1.15;    // Profit Locked at Step 2 (+1.15R)
input double               Trigger_Step3_R             = 1.62;    // Step 3 Trigger (+1.62R) -> Locks +1.50R
input double               Lock_R_At_Step3             = 1.50;    // Profit Locked at Step 3 (+1.50R)
input double               SL_Buffer_ATR               = 0.22;    // Stop-Loss Buffer behind Manipulation Wick (x M15 ATR)
input double               Min_SL_Price_Pct            = 0.27;    // Min M15 SL (% of Gold Price)
input double               Max_SL_Price_Pct            = 0.482;   // Max M15 SL (% of Gold Price)

input string               Sep2                        = "=== 2. M15 Micro-Killzone Windows (Time[0]) ===";
input ENUM_ENTRY_MODE      Entry_Mode                  = ENTRY_SHALLOW_15_FVG;
input double               FVG_Pullback_Ratio          = 0.15;    // 15% Shallow Pullback Ratio
input int                  Pending_Expiry_Bars         = 1;       // 1 M15 Bar Expiry for Unfilled Limits
input bool                 Skip_NYSE_Whip_1645_1745    = true;    // Skip 16:45 (NYSE Open Whip) & 17:45
input bool                 Skip_Late_Window_Buys       = true;    // Block Late Top-Chasing Buys at 18:15 & 20:15-20:45
input int                  Max_Trades_NY_Morning       = 3;       // Max Trades in NY Morning (16:00-18:15 Broker Time[0])
input int                  Max_Trades_NY_Afternoon     = 2;       // Max Trades in NY PM Macro (20:00-20:45 Broker Time[0])
input bool                 Enable_London_Session       = false;   // Trade London 10:00-10:45 Window (False = Pure NY)
input int                  Cooldown_M15_Bars           = 1;       // Min M15 Bars Between Consecutive Trades
input int                  Post_Loss_Cooldown_Bars     = 3;       // Extra M15 Bars Cooldown After a Stop-Loss
input bool                 Close_At_NY_End             = false;   // Keep Overnight Runners Open (HYBRID_04 88.14% WR)

input string               Sep3                        = "=== 3. M15 Core Engines (AMD & Layer 3) ===";
input bool                 Strict_EMA_Slope_Filter     = true;    // Require Strict EMA50 > EMA200 & Non-Opposing Slope
input double               Min_Sweep_ATR               = 0.07;    // Min Sweep Penetration beyond Liquidity Pool (x M15 ATR)
input double               Max_Sweep_ATR               = 2.20;    // Max Sweep Penetration before Breakout Invalidation
input int                  Max_Bars_For_MSS            = 6;       // Max M15 Bars after Sweep to Trigger
input double               Disp_Body_ATR               = 0.25;    // Min M15 Displacement Body Size (x M15 ATR)
input bool                 Enable_Engine1_AMDSweep     = true;    // Engine 1: AMD External/Session Liquidity Sweep
input bool                 Enable_Engine2_Turtle       = true;    // Engine 2: Layer 3 Internal Swing Sweep (PF 3.18!)
input bool                 Enable_Engine3_SilverB      = false;   // Engine 3: NY Silver Bullet FVG Continuation
input bool                 Allow_SilverB_Sell          = false;   // Allow Silver Bullet SELL without BSL Sweep
input bool                 Draw_Liquidity_Lines        = true;    // Draw Asian/London Liquidity Levels on Chart

input string               Sep4                        = "=== 4. GoldFusion v6.3 Modules (SP2L + UT + Quorum) ===";
input bool                 Enable_Engine4_GF_SP2L      = true;    // Engine 4: GoldFusion SP2L (2-Bar Spike + FVG + 2-Leg PB)
input bool                 SP2L_NY_PM_Only             = true;    // Run Engine 4 ONLY in NY_PM 20:00-20:45 (80% WR, +$756!)
input int                  SP2L_SpikeBars              = 2;       // SP2L Consecutive Spike Bars (GoldFusion=2)
input double               SP2L_MinSpikeATR            = 1.20;    // SP2L Min Spike Displacement (x ATR21, GoldFusion=1.2)
input double               SP2L_MinBodyRatio           = 0.45;    // SP2L Min Candle Body Ratio (GoldFusion Report=0.45)
input bool                 SP2L_RequireGap             = true;    // SP2L Require Fair Value Gap in Spike
input int                  SP2L_MaxLegBars             = 12;      // SP2L Max Pullback Bars After Spike (GoldFusion=12)
input bool                 SP2L_StrictBreak            = false;   // SP2L Require Close Beyond Spike High/Low
input bool                 Enable_PreNY_1400_1530      = false;   // Dedicated GoldFusion Pre-NY Window (14:00-15:30)
input int                  Max_Trades_PreNY            = 1;       // Separate Trade Cap for 14:00-15:30 (Zero NY AM Overlap)
input ENUM_GF_FILTER_SCOPE GF_Filter_Scope             = GF_FILTER_ENGINE4_ONLY; // Where to Apply UT Bot + BB50
input bool                 Use_GF_UT_Filter            = true;    // GoldFusion UT Bot ATR Trailing Filter (Warm-Up Fixed)
input double               UT_KeyValue                 = 1.0;     // UT Bot Sensitivity Multiplier (GoldFusion=1.0)
input int                  UT_ATRPeriod                = 21;      // UT Bot ATR Period (GoldFusion=21)
input bool                 Use_GF_BB50_Filter          = true;    // GoldFusion BB50 Basis + Slope Filter (GoldFusion=50)
input int                  BB_Length                   = 50;      // BB Basis SMA Period (GoldFusion=50)
input bool                 Use_GF_Reversal_Shield      = true;    // Exit Pre-Step1 Losing Trades on Confirmed 3/4 Reversal

//--- Effective Active Parameters
double g_rr_target        = 1.95;
double g_sl_buf_atr       = 0.22;
double g_min_sl_pct       = 0.27;
double g_max_sl_pct       = 0.482;
int    g_entry_mode       = ENTRY_SHALLOW_15_FVG;
double g_fvg_pullback     = 0.15;
int    g_pending_exp      = 1;
bool   g_skip_whip_bars   = true;
bool   g_skip_late_buys   = true;
int    g_max_ny_am        = 3;
int    g_max_ny_pm        = 2;
bool   g_enable_london    = false;
int    g_cooldown_bars    = 1;
bool   g_strict_ema       = true;
double g_min_sweep_atr    = 0.07;
double g_max_sweep_atr    = 2.20;
int    g_max_mss_bars     = 6;
double g_disp_body_atr    = 0.25;
bool   g_eng1_amd         = true;
bool   g_eng2_turtle      = true;
bool   g_eng3_silverb     = false;
bool   g_allow_sb_sell    = false;

//--- Self-Contained Daily Session Tracking
int      g_current_trading_day  = -1;
double   g_asian_high           = 0.0;
double   g_asian_low            = 0.0;
double   g_london_high          = 0.0;
double   g_london_low           = 0.0;
double   g_midnight_open        = 0.0;
double   g_cur_day_high         = 0.0;
double   g_cur_day_low          = 0.0;
double   g_pdh                  = 0.0;
double   g_pdl                  = 0.0;
double   g_daily_atr            = 0.0;
int      g_lon_trades_count     = 0;
int      g_preny_trades_count   = 0;
int      g_ny_am_trades_count   = 0;
int      g_ny_pm_trades_count   = 0;

//--- State Machine Manipulation Tracking
bool     g_bull_sweep_active    = false;
int      g_bull_sweep_bars      = 0;
double   g_bull_swept_level     = 0.0;
double   g_bull_manip_low       = 1e9;

bool     g_bear_sweep_active    = false;
int      g_bear_sweep_bars      = 0;
double   g_bear_swept_level     = 0.0;
double   g_bear_manip_high      = -1e9;

datetime g_last_bar_time        = 0;
int      g_bars_since_entry     = 999;
int      g_pending_bars_alive   = 0;
double   g_pending_inval_price  = 0.0;
int      g_pending_dir          = 0;
string   g_pending_window       = "";
int      g_last_partial_ticket  = -1;
int      g_last_closed_ticket   = -1;
datetime g_last_sp2l_spike_time = 0;

//+------------------------------------------------------------------+
//| Apply M15 Preset                                                 |
//+------------------------------------------------------------------+
void ApplyM15Preset()
  {
   if(M15_Preset == M15_ULTRA_TUNED_PF384)
     {
      g_rr_target        = 1.95;
      g_sl_buf_atr       = 0.22;
      g_min_sl_pct       = 0.27;
      g_max_sl_pct       = 0.482;
      g_entry_mode       = ENTRY_SHALLOW_15_FVG;
      g_fvg_pullback     = 0.15;
      g_pending_exp      = 1;
      g_skip_whip_bars   = true;
      g_skip_late_buys   = true;
      g_max_ny_am        = 3;
      g_max_ny_pm        = 2;
      g_enable_london    = false;
      g_cooldown_bars    = 1;
      g_strict_ema       = true;
      g_min_sweep_atr    = 0.07;
      g_max_sweep_atr    = 2.20;
      g_max_mss_bars     = 6;
      g_disp_body_atr    = 0.25;
      g_eng1_amd         = true;
      g_eng2_turtle      = true;
      g_eng3_silverb     = false;
      g_allow_sb_sell    = false;
     }
   else if(M15_Preset == M15_NY_PLUS_LONDON)
     {
      g_rr_target        = 1.85;
      g_sl_buf_atr       = 0.22;
      g_min_sl_pct       = 0.27;
      g_max_sl_pct       = 0.50;
      g_entry_mode       = ENTRY_SHALLOW_15_FVG;
      g_fvg_pullback     = 0.15;
      g_pending_exp      = 1;
      g_skip_whip_bars   = true;
      g_skip_late_buys   = true;
      g_max_ny_am        = 3;
      g_max_ny_pm        = 2;
      g_enable_london    = true;
      g_cooldown_bars    = 1;
      g_strict_ema       = true;
      g_min_sweep_atr    = 0.05;
      g_max_sweep_atr    = 2.20;
      g_max_mss_bars     = 6;
      g_disp_body_atr    = 0.25;
      g_eng1_amd         = true;
      g_eng2_turtle      = true;
      g_eng3_silverb     = false;
      g_allow_sb_sell    = false;
     }
   else
     {
      g_rr_target        = RR_Target;
      g_sl_buf_atr       = SL_Buffer_ATR;
      g_min_sl_pct       = Min_SL_Price_Pct;
      g_max_sl_pct       = Max_SL_Price_Pct;
      g_entry_mode       = Entry_Mode;
      g_fvg_pullback     = FVG_Pullback_Ratio;
      g_pending_exp      = Pending_Expiry_Bars;
      g_skip_whip_bars   = Skip_NYSE_Whip_1645_1745;
      g_skip_late_buys   = Skip_Late_Window_Buys;
      g_max_ny_am        = Max_Trades_NY_Morning;
      g_max_ny_pm        = Max_Trades_NY_Afternoon;
      g_enable_london    = Enable_London_Session;
      g_cooldown_bars    = Cooldown_M15_Bars;
      g_strict_ema       = Strict_EMA_Slope_Filter;
      g_min_sweep_atr    = Min_Sweep_ATR;
      g_max_sweep_atr    = Max_Sweep_ATR;
      g_max_mss_bars     = Max_Bars_For_MSS;
      g_disp_body_atr    = Disp_Body_ATR;
      g_eng1_amd         = Enable_Engine1_AMDSweep;
      g_eng2_turtle      = Enable_Engine2_Turtle;
      g_eng3_silverb     = Enable_Engine3_SilverB;
      g_allow_sb_sell    = Allow_SilverB_Sell;
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ApplyM15Preset();
   Print("XAUUSD AMD + GoldFusion EA v3.40 Initialized. Preset=",
         EnumToString(M15_Preset), " | Engine4_SP2L=", Enable_Engine4_GF_SP2L,
         " | PreNY_14_1530=", Enable_PreNY_1400_1530,
         " | GF_Filter_Scope=", EnumToString(GF_Filter_Scope),
         " | Reversal_Shield=", Use_GF_Reversal_Shield);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Convert Broker Server Time to New York Time (EST/EDT)            |
//+------------------------------------------------------------------+
datetime GetNewYorkTime(datetime server_time)
  {
   int m = TimeMonth(server_time);
   int d = TimeDay(server_time);

   int broker_offset = Broker_Winter_GMT;
   if(Auto_Broker_DST)
     {
      if(m > 3 && m < 10)
         broker_offset = Broker_Winter_GMT + 1;
      else if(m == 3 && d >= 28)
         broker_offset = Broker_Winter_GMT + 1;
      else if(m == 10 && d < 26)
         broker_offset = Broker_Winter_GMT + 1;
     }

   datetime utc_time = server_time - (broker_offset * 3600);

   int ny_offset = -5;
   if(Auto_US_DST)
     {
      if(m > 3 && m < 11)
         ny_offset = -4;
      else if(m == 3 && d >= 10)
         ny_offset = -4;
      else if(m == 11 && d < 3)
         ny_offset = -4;
     }
   return(utc_time + (ny_offset * 3600));
  }

double GetNYDecimalHour(datetime server_time)
  {
   datetime ny_t = GetNewYorkTime(server_time);
   return((double)TimeHour(ny_t) + ((double)TimeMinute(ny_t) / 60.0));
  }

double GetBrokerDecimalHour(datetime server_time)
  {
   return((double)TimeHour(server_time) + ((double)TimeMinute(server_time) / 60.0));
  }

int GetTradingDayID(datetime server_time)
  {
   datetime ny_shifted = GetNewYorkTime(server_time) + (6 * 3600);
   return(TimeYear(ny_shifted) * 1000 + TimeDayOfYear(ny_shifted));
  }

//+------------------------------------------------------------------+
//| GoldFusion Helper Functions (Warm-Up Fixed & Deterministic)      |
//+------------------------------------------------------------------+
double SafeATR(int period, int shift)
  {
   double atr = iATR(Symbol(), Period(), period, shift);
   if(atr <= 0.00001)
     {
      double sum = 0.0;
      int    cnt = 0;
      for(int i = shift; i < shift + period && i + 1 < Bars; i++)
        {
         double tr = MathMax(High[i] - Low[i], MathMax(MathAbs(High[i] - Close[i + 1]), MathAbs(Low[i] - Close[i + 1])));
         if(tr > 0) { sum += tr; cnt++; }
        }
      atr = (cnt > 0) ? (sum / cnt) : ((High[shift] - Low[shift]) * 0.5);
     }
   return(atr);
  }

// Computes UT Bot ATR Trailing Stop at Bar[1] with 120-Bar Warm-Up
// (Fixes GoldFusion v6.3's cold-start bug where g_utStop started at 0)
double ComputeUTBotStopBar1()
  {
   int lookback = MathMin(Bars - 25, 120);
   if(lookback < 5)
      return(Close[1]);

   double ut_stop = Close[lookback];
   for(int s = lookback - 1; s >= 1; s--)
     {
      double c     = Close[s];
      double cP    = Close[s + 1];
      double nLoss = UT_KeyValue * SafeATR(UT_ATRPeriod, s);
      double ns    = ut_stop;

      if(c > ut_stop && cP > ut_stop)
         ns = MathMax(ut_stop, c - nLoss);
      else if(c < ut_stop && cP < ut_stop)
         ns = MathMin(ut_stop, c + nLoss);
      else if(c > ut_stop)
         ns = c - nLoss;
      else
         ns = c + nLoss;

      ut_stop = ns;
     }
   return(ut_stop);
  }

bool GF_UTAllow(int dir)
  {
   if(!Use_GF_UT_Filter)
      return(true);
   double ut_stop = ComputeUTBotStopBar1();
   return((dir > 0) ? (Close[1] > ut_stop) : (Close[1] < ut_stop));
  }

bool GF_BB50Allow(int dir)
  {
   if(!Use_GF_BB50_Filter || Bars < BB_Length + 5)
      return(true);
   double basis1 = iMA(Symbol(), Period(), BB_Length, 0, MODE_SMA, PRICE_CLOSE, 1);
   double basis2 = iMA(Symbol(), Period(), BB_Length, 0, MODE_SMA, PRICE_CLOSE, 2);
   double c1     = Close[1];
   return((dir > 0) ? (c1 > basis1 && basis1 > basis2) : (c1 < basis1 && basis1 < basis2));
  }

bool GF_FiltersAllow(int dir, bool is_engine4_or_preny)
  {
   if(GF_Filter_Scope == GF_FILTER_OFF)
      return(true);
   if(GF_Filter_Scope == GF_FILTER_ENGINE4_ONLY && !is_engine4_or_preny)
      return(true);
   if(GF_Filter_Scope == GF_FILTER_LONG_ONLY && dir < 0 && !is_engine4_or_preny)
      return(true);

   return(GF_UTAllow(dir) && GF_BB50Allow(dir));
  }

bool GF_IsBullishSpike(int s, double atr21, double &hh_out)
  {
   int n = SP2L_SpikeBars;
   if(s + n + 2 >= Bars)
      return(false);
   hh_out = 0.0;
   double origin = MathMin(Low[s + n], Low[s + n - 1]);
   for(int i = s; i < s + n; i++)
     {
      if(Close[i] <= Open[i])
         return(false);
      double rng = High[i] - Low[i];
      if(rng <= 0 || ((Close[i] - Open[i]) / rng) < SP2L_MinBodyRatio)
         return(false);
      if(High[i] > hh_out)
         hh_out = High[i];
     }
   if((hh_out - origin) < SP2L_MinSpikeATR * atr21)
      return(false);
   if(SP2L_RequireGap)
     {
      bool gap = false;
      for(int j = s; j + 2 <= s + n && !gap; j++)
         if(Low[j] > High[j + 2])
            gap = true;
      if(!gap)
         return(false);
     }
   return(true);
  }

bool GF_IsBearishSpike(int s, double atr21, double &ll_out)
  {
   int n = SP2L_SpikeBars;
   if(s + n + 2 >= Bars)
      return(false);
   ll_out = 0.0;
   double origin = MathMax(High[s + n], High[s + n - 1]);
   for(int i = s; i < s + n; i++)
     {
      if(Close[i] >= Open[i])
         return(false);
      double rng = High[i] - Low[i];
      if(rng <= 0 || ((Open[i] - Close[i]) / rng) < SP2L_MinBodyRatio)
         return(false);
      if(ll_out == 0.0 || Low[i] < ll_out)
         ll_out = Low[i];
     }
   if((origin - ll_out) < SP2L_MinSpikeATR * atr21)
      return(false);
   if(SP2L_RequireGap)
     {
      bool gap = false;
      for(int j = s; j + 2 <= s + n && !gap; j++)
         if(High[j] < Low[j + 2])
            gap = true;
      if(!gap)
         return(false);
     }
   return(true);
  }

// Engine 4: GoldFusion SP2L (2-Bar Spike + FVG + 2-Leg Pullback + Breakout)
// Upgraded with Single-Use Spike Timestamp & Structural Pullback Extreme for R-Sizing
int GF_DetectSP2LSignal(bool bull_bias, bool bear_bias, bool bull_close_q, bool bear_close_q,
                        double &manip_extreme_out, datetime &spike_time_out)
  {
   double atr21 = SafeATR(21, 1);
   if(atr21 <= 0)
      return(0);

   int maxBack = SP2L_MaxLegBars + 2;

   if(bull_bias && bull_close_q && Close[1] > Open[1] && Close[1] > High[2])
     {
      for(int s = 2; s <= maxBack; s++)
        {
         double hh = 0.0;
         if(!GF_IsBullishSpike(s, atr21, hh))
            continue;
         if(Time[s] == g_last_sp2l_spike_time)
            return(0); // Prevent duplicate entries on already-traded spike
         if(SP2L_StrictBreak && Close[1] <= hh)
            return(0);

         double origin     = MathMin(Low[s + SP2L_SpikeBars], Low[s + SP2L_SpikeBars - 1]);
         bool   leg        = false;
         double leg_min_lo = Low[1];

         for(int k = s - 1; k >= 2; k--)
           {
            if(Low[k] < origin)
               break;
            if(Low[k] < leg_min_lo)
               leg_min_lo = Low[k];
            if(Low[k] <= Low[k + 1])
               leg = true;
           }
         if(leg && Low[1] > origin)
           {
            manip_extreme_out = MathMin(leg_min_lo, Low[1]);
            spike_time_out    = Time[s];
            return(1);
           }
         return(0); // Nearest spike only
        }
     }

   if(bear_bias && bear_close_q && Close[1] < Open[1] && Close[1] < Low[2])
     {
      for(int s = 2; s <= maxBack; s++)
        {
         double ll = 0.0;
         if(!GF_IsBearishSpike(s, atr21, ll))
            continue;
         if(Time[s] == g_last_sp2l_spike_time)
            return(0);
         if(SP2L_StrictBreak && Close[1] >= ll)
            return(0);

         double origin     = MathMax(High[s + SP2L_SpikeBars], High[s + SP2L_SpikeBars - 1]);
         bool   leg        = false;
         double leg_max_hi = High[1];

         for(int k = s - 1; k >= 2; k--)
           {
            if(High[k] > origin)
               break;
            if(High[k] > leg_max_hi)
               leg_max_hi = High[k];
            if(High[k] >= High[k + 1])
               leg = true;
           }
         if(leg && High[1] < origin)
           {
            manip_extreme_out = MathMax(leg_max_hi, High[1]);
            spike_time_out    = Time[s];
            return(-1);
           }
         return(0);
        }
     }

   return(0);
  }

// GoldFusion Pullback Vote (used for Reversal Quorum check)
int GF_PullbackVote()
  {
   double ema200_1 = iMA(Symbol(), Period(), 200, 0, MODE_EMA, PRICE_CLOSE, 1);
   if(ema200_1 <= 0)
      return(0);
   if(Close[1] > ema200_1 && Close[1] > Open[1] && Close[1] > High[2])
     {
      for(int k = 1; k <= 14; k++)
         if(Low[k] <= iMA(Symbol(), Period(), 50, 0, MODE_EMA, PRICE_CLOSE, k) &&
            Close[k] > iMA(Symbol(), Period(), 200, 0, MODE_EMA, PRICE_CLOSE, k))
            return(1);
     }
   if(Close[1] < ema200_1 && Close[1] < Open[1] && Close[1] < Low[2])
     {
      for(int k = 1; k <= 14; k++)
         if(High[k] >= iMA(Symbol(), Period(), 50, 0, MODE_EMA, PRICE_CLOSE, k) &&
            Close[k] < iMA(Symbol(), Period(), 200, 0, MODE_EMA, PRICE_CLOSE, k))
            return(-1);
     }
   return(0);
  }

// Pre-Step1 Reversal Shield: Only exits an open losing position (before Step 1 lock)
// if a confirmed 3-of-4 opposite quorum (PB + Opposite Sweep/SP2L + UT Bot + BB50) fires
void CheckPreStep1ReversalShield()
  {
   if(!Use_GF_Reversal_Shield)
      return;

   int pb_vote = GF_PullbackVote();
   if(pb_vote == 0)
      return;

   for(int idx = OrdersTotal() - 1; idx >= 0; idx--)
     {
      if(!OrderSelect(idx, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number)
         continue;

      int    type   = OrderType();
      int    ticket = OrderTicket();
      double open_p = OrderOpenPrice();
      double sl_p   = OrderStopLoss();

      // Only shield positions that have NOT yet locked profit at Step 1
      // and are currently underwater
      if(type == OP_BUY && sl_p < open_p && Bid < open_p && pb_vote == -1)
        {
         int votes = 1; // pb_vote == -1
         if(g_bear_sweep_active) votes++;
         if(GF_UTAllow(-1))      votes++;
         if(GF_BB50Allow(-1))    votes++;
         if(votes >= 3)
           {
            bool c = OrderClose(ticket, OrderLots(), Bid, 10, clrOrange);
            if(c) Print("v3.40 Reversal Shield Closed Underwater BUY #", ticket, " (Quorum=", votes, "/4)");
           }
        }
      else if(type == OP_SELL && (sl_p > open_p || sl_p == 0) && Ask > open_p && pb_vote == 1)
        {
         int votes = 1; // pb_vote == +1
         if(g_bull_sweep_active) votes++;
         if(GF_UTAllow(1))       votes++;
         if(GF_BB50Allow(1))     votes++;
         if(votes >= 3)
           {
            bool c = OrderClose(ticket, OrderLots(), Ask, 10, clrOrange);
            if(c) Print("v3.40 Reversal Shield Closed Underwater SELL #", ticket, " (Quorum=", votes, "/4)");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Update Daily Session Ranges & Liquidity Levels                   |
//+------------------------------------------------------------------+
void UpdateSessionLiquidityLevels(double m15_atr)
  {
   int t_day = GetTradingDayID(Time[1]);

   if(g_current_trading_day == -1)
     {
      g_current_trading_day = t_day;
      g_asian_high          = High[1];
      g_asian_low           = Low[1];
      g_london_high         = High[1];
      g_london_low          = Low[1];
      g_cur_day_high        = High[1];
      g_cur_day_low         = Low[1];
      g_midnight_open       = Open[1];
      g_daily_atr           = m15_atr * 8.0;
     }

   if(t_day != g_current_trading_day)
     {
      double prev_range = g_cur_day_high - g_cur_day_low;
      if(prev_range > m15_atr * 1.5)
        {
         g_pdh = g_cur_day_high;
         g_pdl = g_cur_day_low;
         g_daily_atr = (g_daily_atr <= 0) ? prev_range : (0.85 * g_daily_atr + 0.15 * prev_range);
        }

      g_current_trading_day = t_day;
      g_asian_high          = 0.0;
      g_asian_low           = 1e9;
      g_london_high         = 0.0;
      g_london_low          = 1e9;
      g_midnight_open       = 0.0;
      g_cur_day_high        = High[1];
      g_cur_day_low         = Low[1];
      g_lon_trades_count    = 0;
      g_preny_trades_count  = 0;
      g_ny_am_trades_count  = 0;
      g_ny_pm_trades_count  = 0;
      g_bull_sweep_active   = false;
      g_bear_sweep_active   = false;
     }

   if(High[1] > g_cur_day_high) g_cur_day_high = High[1];
   if(Low[1]  < g_cur_day_low)  g_cur_day_low  = Low[1];

   double hr = GetNYDecimalHour(Time[1]);

   if(hr >= 18.0 || hr < 2.0)
     {
      if(High[1] > g_asian_high) g_asian_high = High[1];
      if(Low[1]  < g_asian_low)  g_asian_low  = Low[1];
     }

   if(hr >= 0.0 && hr < 2.0 && g_midnight_open == 0.0)
      g_midnight_open = Open[1];

   if(hr >= 2.0 && hr < 7.0)
     {
      if(High[1] > g_london_high) g_london_high = High[1];
      if(Low[1]  < g_london_low)  g_london_low  = Low[1];
     }

   if(g_asian_high <= 0 || g_asian_low >= 1e8)
     {
      int lookback = MathMin(Bars - 1, 32);
      g_asian_high = High[iHighest(Symbol(), Period(), MODE_HIGH, lookback, 2)];
      g_asian_low  = Low[iLowest(Symbol(), Period(), MODE_LOW, lookback, 2)];
     }

   if(g_daily_atr <= 0)
      g_daily_atr = m15_atr * 8.0;

   if(Draw_Liquidity_Lines && (!IsTesting() || IsVisualMode()))
     {
      if(g_asian_high > 0 && g_asian_low < 1e8)
        {
         DrawHorizontalLevel("AMD_Asian_High", g_asian_high, clrGold);
         DrawHorizontalLevel("AMD_Asian_Low",  g_asian_low,  clrGold);
        }
      if(g_midnight_open > 0)
         DrawHorizontalLevel("AMD_Midnight_Open", g_midnight_open, clrAqua);
     }
  }

void DrawHorizontalLevel(string name, double price, color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
     }
   else
     {
      ObjectMove(0, name, 0, 0, price);
     }
  }

//+------------------------------------------------------------------+
//| Manage Open Positions: 1-Bar Fast Expiry & High-Retention Lock   |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   double ny_hr      = GetNYDecimalHour(TimeCurrent());
   double brk_hr     = GetBrokerDecimalHour(TimeCurrent());
   double stop_level = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int idx = OrdersTotal() - 1; idx >= 0; idx--)
     {
      if(!OrderSelect(idx, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number)
         continue;

      int type   = OrderType();
      int ticket = OrderTicket();

      // 1. Fast Expiry for Unfilled Limit Orders
      if(type == OP_BUYLIMIT || type == OP_SELLLIMIT)
        {
         bool invalidated = (g_pending_dir == 1 && Low[0] <= g_pending_inval_price) ||
                            (g_pending_dir == -1 && High[0] >= g_pending_inval_price);
         bool end_of_day  = (Close_At_NY_End && ((ny_hr >= 16.0 && ny_hr < 18.0) || brk_hr >= 22.50));
         if(g_pending_bars_alive > g_pending_exp || invalidated || end_of_day)
           {
            if(OrderDelete(ticket))
              {
               if(g_pending_window == "LON10"  && g_lon_trades_count   > 0) g_lon_trades_count--;
               if(g_pending_window == "PRE_NY" && g_preny_trades_count > 0) g_preny_trades_count--;
               if(g_pending_window == "NY_AM"  && g_ny_am_trades_count > 0) g_ny_am_trades_count--;
               if(g_pending_window == "NY_PM"  && g_ny_pm_trades_count > 0) g_ny_pm_trades_count--;
              }
           }
         continue;
        }

      // 2. Close Intraday Positions at End of NY Session (22:50+ Broker Time / 16:00 NY)
      if(Close_At_NY_End && ((ny_hr >= 16.0 && ny_hr < 18.0) || brk_hr >= 22.85))
        {
         if(type == OP_BUY)
            bool c1 = OrderClose(ticket, OrderLots(), Bid, 10, clrWhite);
         else if(type == OP_SELL)
            bool c2 = OrderClose(ticket, OrderLots(), Ask, 10, clrWhite);
         continue;
        }

      // 3. High-Retention 3-Stage Step-Lock Profit Management
      if(!Use_StepLock_Profit)
         continue;

      double open_p = OrderOpenPrice();
      double sl_p   = OrderStopLoss();
      double tp_p   = OrderTakeProfit();

      if(type == OP_BUY && tp_p > open_p)
        {
         double risk_dist = (tp_p - open_p) / g_rr_target;
         if(risk_dist <= 0) continue;

         double s1_trig = open_p + Trigger_Step1_R * risk_dist;
         double s1_lock = NormalizeDouble(open_p + Lock_R_At_Step1 * risk_dist, Digits);

         double s2_trig = open_p + Trigger_Step2_R * risk_dist;
         double s2_lock = NormalizeDouble(open_p + Lock_R_At_Step2 * risk_dist, Digits);

         double s3_trig = open_p + Trigger_Step3_R * risk_dist;
         double s3_lock = NormalizeDouble(open_p + Lock_R_At_Step3 * risk_dist, Digits);

         if(Bid >= s3_trig && sl_p < (s3_lock - Point) && (Bid - s3_lock) > stop_level)
           {
            bool m3 = OrderModify(ticket, open_p, s3_lock, tp_p, 0, clrAqua);
           }
         else if(Bid >= s2_trig && sl_p < (s2_lock - Point) && (Bid - s2_lock) > stop_level)
           {
            bool m2 = OrderModify(ticket, open_p, s2_lock, tp_p, 0, clrLime);
           }
         else if(Bid >= s1_trig && sl_p < (s1_lock - Point) && (Bid - s1_lock) > stop_level)
           {
            if(OrderModify(ticket, open_p, s1_lock, tp_p, 0, clrGreen))
              {
               if(ticket != g_last_partial_ticket)
                 {
                  g_last_partial_ticket = ticket;
                  double half_lots = NormalizeLots(OrderLots() * 0.5);
                  double min_lot   = MarketInfo(Symbol(), MODE_MINLOT);
                  if(half_lots >= min_lot && (OrderLots() - half_lots) >= min_lot)
                     bool pc = OrderClose(ticket, half_lots, Bid, 10, clrGreen);
                 }
              }
           }
        }
      else if(type == OP_SELL && tp_p < open_p && tp_p > 0)
        {
         double risk_dist = (open_p - tp_p) / g_rr_target;
         if(risk_dist <= 0) continue;

         double s1_trig = open_p - Trigger_Step1_R * risk_dist;
         double s1_lock = NormalizeDouble(open_p - Lock_R_At_Step1 * risk_dist, Digits);

         double s2_trig = open_p - Trigger_Step2_R * risk_dist;
         double s2_lock = NormalizeDouble(open_p - Lock_R_At_Step2 * risk_dist, Digits);

         double s3_trig = open_p - Trigger_Step3_R * risk_dist;
         double s3_lock = NormalizeDouble(open_p - Lock_R_At_Step3 * risk_dist, Digits);

         if(Ask <= s3_trig && (sl_p > (s3_lock + Point) || sl_p == 0) && (s3_lock - Ask) > stop_level)
           {
            bool m3 = OrderModify(ticket, open_p, s3_lock, tp_p, 0, clrAqua);
           }
         else if(Ask <= s2_trig && (sl_p > (s2_lock + Point) || sl_p == 0) && (s2_lock - Ask) > stop_level)
           {
            bool m2 = OrderModify(ticket, open_p, s2_lock, tp_p, 0, clrOrangeRed);
           }
         else if(Ask <= s1_trig && (sl_p > (s1_lock + Point) || sl_p == 0) && (s1_lock - Ask) > stop_level)
           {
            if(OrderModify(ticket, open_p, s1_lock, tp_p, 0, clrRed))
              {
               if(ticket != g_last_partial_ticket)
                 {
                  g_last_partial_ticket = ticket;
                  double half_lots = NormalizeLots(OrderLots() * 0.5);
                  double min_lot   = MarketInfo(Symbol(), MODE_MINLOT);
                  if(half_lots >= min_lot && (OrderLots() - half_lots) >= min_lot)
                     bool pc = OrderClose(ticket, half_lots, Ask, 10, clrRed);
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if Last Closed Trade Was a Loss (for Post-Loss Cooldown)   |
//+------------------------------------------------------------------+
void CheckRecentClosedLoss()
  {
   int h_total = OrdersHistoryTotal();
   for(int i = h_total - 1; i >= MathMax(0, h_total - 5); i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      int tkt = OrderTicket();
      if(tkt != g_last_closed_ticket)
        {
         g_last_closed_ticket = tkt;
         if(OrderProfit() < -1.0)
           {
            g_bars_since_entry = g_cooldown_bars - Post_Loss_Cooldown_Bars;
           }
        }
      break;
     }
  }

//+------------------------------------------------------------------+
//| Count Active Orders/Positions for this EA                        |
//+------------------------------------------------------------------+
int CountActiveOrders(int &pending_count_out)
  {
   int count = 0;
   pending_count_out = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            count++;
            if(OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT)
               pending_count_out++;
           }
     }
   return(count);
  }

double NormalizeLots(double lots)
  {
   double min_lot  = MarketInfo(Symbol(), MODE_MINLOT);
   double max_lot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lot_step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(min_lot <= 0)  min_lot  = 0.01;
   if(max_lot <= 0)  max_lot  = 100.0;
   if(lot_step <= 0) lot_step = 0.01;
   double stepped = MathFloor(lots / lot_step) * lot_step;
   return(MathMax(min_lot, MathMin(max_lot, NormalizeDouble(stepped, 2))));
  }

double CalculatePositionLots(double sl_distance_price, int cmd_type)
  {
   double min_lot = MarketInfo(Symbol(), MODE_MINLOT);
   if(min_lot <= 0) min_lot = 0.01;
   if(!Use_Step_Compounding || sl_distance_price <= 0)
      return(NormalizeLots(Fixed_Lots_Fallback));

   double risk_money    = AccountBalance() * (Risk_Percent_Per_Trade / 100.0);
   double tick_val      = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tick_size     = MarketInfo(Symbol(), MODE_TICKSIZE);
   double contract_size = MarketInfo(Symbol(), MODE_LOTSIZE);
   if(contract_size <= 0) contract_size = 100.0;

   double loss_per_lot = 0.0;
   if(tick_val > 0 && tick_size > 0)
      loss_per_lot = (sl_distance_price / tick_size) * tick_val;

   double expected_gold_loss = sl_distance_price * contract_size;
   if(loss_per_lot <= expected_gold_loss * 0.05 || loss_per_lot > expected_gold_loss * 20.0)
      loss_per_lot = expected_gold_loss;

   double risk_lots = (loss_per_lot > 0) ? (risk_money / loss_per_lot) : Fixed_Lots_Fallback;

   double step_lots = Fixed_Lots_Fallback;
   if(Balance_Per_001_Lot > 0)
      step_lots = MathMax(Fixed_Lots_Fallback, MathFloor(AccountBalance() / Balance_Per_001_Lot) * 0.01);

   double raw_lots  = MathMax(risk_lots, step_lots);
   double lots      = NormalizeLots(raw_lots);

   int mkt_cmd = (cmd_type == OP_BUY || cmd_type == OP_BUYLIMIT) ? OP_BUY : OP_SELL;
   while(lots > min_lot && AccountFreeMarginCheck(Symbol(), mkt_cmd, lots) <= 0)
     {
      lots = NormalizeLots(lots - 0.01);
     }
   if(AccountFreeMarginCheck(Symbol(), mkt_cmd, lots) <= 0)
      return(min_lot);

   return(lots);
  }

//+------------------------------------------------------------------+
//| Expert tick function (Hybrid AMD v3.30 + GoldFusion v6.3 Engine) |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageOpenPositions();

   // Process State Machine once per new Closed M15 Bar (Bar[1])
   if(Time[0] == g_last_bar_time)
      return;
   g_last_bar_time = Time[0];

   if(Bars < 250)
      return;

   g_bars_since_entry++;
   CheckRecentClosedLoss();

   int pending_cnt = 0;
   int active_cnt  = CountActiveOrders(pending_cnt);

   if(pending_cnt > 0)
      g_pending_bars_alive++;
   else
      g_pending_bars_alive = 0;

   double atr1 = iATR(Symbol(), Period(), 14, 1);
   double atr2 = iATR(Symbol(), Period(), 14, 2);
   if(atr1 <= 0)
      return;

   UpdateSessionLiquidityLevels(atr1);

   // 1. M15 MICRO-KILLZONE WINDOWS (Time[0]) + OPTIONAL PRE-NY GOLDFUSION WINDOW:
   double brk_hr_now = GetBrokerDecimalHour(Time[0]);
   int    hr_int     = TimeHour(Time[0]);
   int    min_int    = TimeMinute(Time[0]);

   bool is_whip_bar  = g_skip_whip_bars && ((hr_int == 16 && min_int == 45) || (hr_int == 17 && min_int == 45));
   bool is_late_buy  = g_skip_late_buys && ((hr_int == 18 && min_int >= 15) || (hr_int == 20 && min_int >= 35));

   bool in_lon10     = g_enable_london        && (brk_hr_now >= 10.00 && brk_hr_now <= 10.75);
   bool in_preny     = Enable_PreNY_1400_1530 && (brk_hr_now >= 14.00 && brk_hr_now <= 15.50);
   bool in_ny_am     = (brk_hr_now >= 16.00 && brk_hr_now <= 18.25) && !is_whip_bar;
   bool in_ny_pm     = (brk_hr_now >= 20.00 && brk_hr_now <= 20.75);

   string active_window  = "";
   string active_session = "";

   if(in_ny_am && g_ny_am_trades_count < g_max_ny_am)
     {
      active_window  = "NY_AM";
      active_session = "NY";
     }
   else if(in_ny_pm && g_ny_pm_trades_count < g_max_ny_pm)
     {
      active_window  = "NY_PM";
      active_session = "NY";
     }
   else if(in_preny && g_preny_trades_count < Max_Trades_PreNY)
     {
      active_window  = "PRE_NY";
      active_session = "PRE_NY";
     }
   else if(in_lon10 && g_lon_trades_count < 1)
     {
      active_window  = "LON10";
      active_session = "LONDON";
     }

   bool in_sweep_tracking_hours = (g_enable_london && brk_hr_now >= 9.50 && brk_hr_now <= 10.75) ||
                                  (Enable_PreNY_1400_1530 && brk_hr_now >= 13.50 && brk_hr_now <= 20.75) ||
                                  (brk_hr_now >= 15.25 && brk_hr_now <= 20.75);
   if(!in_sweep_tracking_hours)
     {
      g_bull_sweep_active = false;
      g_bear_sweep_active = false;
      return;
     }

   // 2. Compute M15 Indicators
   double ema20        = iMA(Symbol(), Period(), 20,  0, MODE_EMA, PRICE_CLOSE, 1);
   double ema50        = iMA(Symbol(), Period(), 50,  0, MODE_EMA, PRICE_CLOSE, 1);
   double ema50_prev4  = iMA(Symbol(), Period(), 50,  0, MODE_EMA, PRICE_CLOSE, 5);
   double ema200       = iMA(Symbol(), Period(), 200, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema200_prev8 = iMA(Symbol(), Period(), 200, 0, MODE_EMA, PRICE_CLOSE, 9);

   double body1       = MathAbs(Close[1] - Open[1]);
   double body2       = MathAbs(Close[2] - Open[2]);
   double range1      = MathMax(High[1] - Low[1], Point);
   double lower_wick  = MathMin(Open[1], Close[1]) - Low[1];
   double upper_wick  = High[1] - MathMax(Open[1], Close[1]);

   bool bull_close_quality = (Close[1] > Open[1]) && ((High[1] - Close[1]) <= 0.45 * range1);
   bool bear_close_quality = (Close[1] < Open[1]) && ((Close[1] - Low[1])  <= 0.45 * range1);

   // M15 Structural Swing Highs/Lows
   double sw_high_4   = High[iHighest(Symbol(), Period(), MODE_HIGH, 4, 2)];
   double sw_low_4    = Low[iLowest(Symbol(), Period(), MODE_LOW, 4, 2)];
   double ind_high_10 = High[iHighest(Symbol(), Period(), MODE_HIGH, 10, 3)];
   double ind_low_10  = Low[iLowest(Symbol(), Period(), MODE_LOW, 10, 3)];
   double ext_high_20 = High[iHighest(Symbol(), Period(), MODE_HIGH, 20, 4)];
   double ext_low_20  = Low[iLowest(Symbol(), Period(), MODE_LOW, 20, 4)];

   bool bull_fvg = ((Low[1] > High[3]) && (Close[2] > Open[2])) || ((Low[2] > High[4]) && (Close[3] > Open[3]));
   bool bear_fvg = ((High[1] < Low[3]) && (Close[2] < Open[2])) || ((High[2] < Low[4]) && (Close[3] < Open[3]));

   double ssl_pools[6];
   double bsl_pools[6];
   ssl_pools[0] = g_asian_low;
   ssl_pools[1] = g_pdl;
   ssl_pools[2] = ext_low_20;
   ssl_pools[3] = ind_low_10;
   ssl_pools[4] = sw_low_4;
   ssl_pools[5] = (g_london_low < 1e8 && g_london_low > 0) ? g_london_low : g_asian_low;

   bsl_pools[0] = g_asian_high;
   bsl_pools[1] = g_pdh;
   bsl_pools[2] = ext_high_20;
   bsl_pools[3] = ind_high_10;
   bsl_pools[4] = sw_high_4;
   bsl_pools[5] = (g_london_high > 0) ? g_london_high : g_asian_high;

   double sweep_min = g_min_sweep_atr * atr1;
   double sweep_max = g_max_sweep_atr * atr1;

   // 3. Track Manipulation Liquidity Sweeps
   if(g_bull_sweep_active)
     {
      g_bull_sweep_bars++;
      g_bull_manip_low = MathMin(g_bull_manip_low, Low[1]);
      if(g_bull_sweep_bars > g_max_mss_bars || (g_bull_swept_level - g_bull_manip_low) > sweep_max)
         g_bull_sweep_active = false;
     }

   if(!g_bull_sweep_active)
     {
      for(int p = 0; p < 6; p++)
        {
         double pool = ssl_pools[p];
         if(pool > 0 && pool < 1e8 && Low[1] <= (pool - sweep_min) && (pool - Low[1]) <= sweep_max)
           {
            g_bull_sweep_active = true;
            g_bull_sweep_bars   = 0;
            g_bull_swept_level  = pool;
            g_bull_manip_low    = Low[1];
            break;
           }
        }
     }

   if(g_bear_sweep_active)
     {
      g_bear_sweep_bars++;
      g_bear_manip_high = MathMax(g_bear_manip_high, High[1]);
      if(g_bear_sweep_bars > g_max_mss_bars || (g_bear_manip_high - g_bear_swept_level) > sweep_max)
         g_bear_sweep_active = false;
     }

   if(!g_bear_sweep_active)
     {
      for(int p = 0; p < 6; p++)
        {
         double pool = bsl_pools[p];
         if(pool > 0 && pool < 1e8 && High[1] >= (pool + sweep_min) && (High[1] - pool) <= sweep_max)
           {
            g_bear_sweep_active = true;
            g_bear_sweep_bars   = 0;
            g_bear_swept_level  = pool;
            g_bear_manip_high   = High[1];
            break;
           }
        }
     }

   // Optional Pre-Step1 Confirmed Reversal Shield on Active Positions
   if(active_cnt > 0 && Use_GF_Reversal_Shield)
     {
      CheckPreStep1ReversalShield();
      active_cnt = CountActiveOrders(pending_cnt);
     }

   if(active_window == "" || active_cnt > 0 || g_bars_since_entry < g_cooldown_bars)
      return;

   // 4. STRICT M15 TREND & SLOPE ENGINE
   bool bull_bias = (Close[1] > ema200) && (ema50 > ema200) && !is_late_buy;
   bool bear_bias = (Close[1] < ema200) && (ema50 < ema200);

   if(g_strict_ema)
     {
      bull_bias = bull_bias && (ema50 >= ema50_prev4 - 0.10 * atr1) && (ema200 >= ema200_prev8 - 0.10 * atr1);
      bear_bias = bear_bias && (ema50 <= ema50_prev4 + 0.10 * atr1) && (ema200 <= ema200_prev8 + 0.10 * atr1);
     }

   int      signal_dir      = 0;
   double   manip_extreme   = 0.0;
   string   engine_tag      = "";
   datetime sp2l_spike_time = 0;
   bool     is_preny_win    = (active_window == "PRE_NY");

   // 5A. ENGINE 1: Classic AMD Liquidity Sweep + Displacement/MSS
   if(g_eng1_amd)
     {
      if(g_bull_sweep_active && bull_bias && bull_close_quality && Close[1] > g_bull_swept_level)
        {
         bool has_disp = (body1 >= g_disp_body_atr * atr1) || (body2 >= g_disp_body_atr * atr2 && Close[2] > Open[2]);
         bool has_mss  = (Close[1] >= sw_high_4 - 0.20 * atr1) || bull_fvg || (Close[1] > High[2]);
         if(has_disp && has_mss && GF_FiltersAllow(1, is_preny_win))
           {
            signal_dir    = 1;
            manip_extreme = MathMin(g_bull_manip_low, Low[1]);
            engine_tag    = "AMD";
           }
        }
      else if(g_bear_sweep_active && bear_bias && bear_close_quality && Close[1] < g_bear_swept_level)
        {
         bool has_disp = (body1 >= g_disp_body_atr * atr1) || (body2 >= g_disp_body_atr * atr2 && Close[2] < Open[2]);
         bool has_mss  = (Close[1] <= sw_low_4 + 0.20 * atr1) || bear_fvg || (Close[1] < Low[2]);
         if(has_disp && has_mss && GF_FiltersAllow(-1, is_preny_win))
           {
            signal_dir    = -1;
            manip_extreme = MathMax(g_bear_manip_high, High[1]);
            engine_tag    = "AMD";
           }
        }
     }

   // 5B. ENGINE 2: Layer 3 Internal Swing Sweep / Turtle Soup Rejection (PF 3.18!)
   if(signal_dir == 0 && g_eng2_turtle)
     {
      double prev_low_3  = Low[iLowest(Symbol(), Period(), MODE_LOW, 3, 2)];
      double prev_high_3 = High[iHighest(Symbol(), Period(), MODE_HIGH, 3, 2)];

      if(bull_bias && Close[1] > ema50 && Low[1] < prev_low_3 && Close[1] > prev_low_3 && bull_close_quality)
        {
         if((lower_wick >= 0.30 * atr1 || body1 >= 0.30 * atr1) && (Close[1] > High[2] || bull_fvg) &&
            GF_FiltersAllow(1, is_preny_win))
           {
            signal_dir    = 1;
            manip_extreme = Low[1];
            engine_tag    = "L3_SWEEP";
           }
        }
      else if(bear_bias && Close[1] < ema50 && High[1] > prev_high_3 && Close[1] < prev_high_3 && bear_close_quality)
        {
         if((upper_wick >= 0.30 * atr1 || body1 >= 0.30 * atr1) && (Close[1] < Low[2] || bear_fvg) &&
            GF_FiltersAllow(-1, is_preny_win))
           {
            signal_dir    = -1;
            manip_extreme = High[1];
            engine_tag    = "L3_SWEEP";
           }
        }
     }

   // 5C. ENGINE 3: NY Silver Bullet Trend FVG Continuation
   if(signal_dir == 0 && g_eng3_silverb)
     {
      double recent_low_3  = Low[iLowest(Symbol(), Period(), MODE_LOW, 3, 1)];
      double recent_high_3 = High[iHighest(Symbol(), Period(), MODE_HIGH, 3, 1)];

      if(bull_bias && Close[1] > ema20 && ema20 > ema50 && ema50 > ema50_prev4 && bull_close_quality && (bull_fvg || Close[1] > High[2]))
        {
         if(recent_low_3 <= ema20 + 0.18 * atr1 && recent_low_3 >= ema50 - 0.10 * atr1 && body1 >= g_disp_body_atr * atr1 &&
            GF_FiltersAllow(1, is_preny_win))
           {
            signal_dir    = 1;
            manip_extreme = recent_low_3;
            engine_tag    = "SILVER_B";
           }
        }
      else if(g_allow_sb_sell && bear_bias && Close[1] < ema20 && ema20 < ema50 && ema50 < ema50_prev4 && bear_close_quality && (bear_fvg || Close[1] < Low[2]))
        {
         if(recent_high_3 >= ema20 - 0.18 * atr1 && recent_high_3 <= ema50 + 0.10 * atr1 && body1 >= g_disp_body_atr * atr1 &&
            GF_FiltersAllow(-1, is_preny_win))
           {
            signal_dir    = -1;
            manip_extreme = recent_high_3;
            engine_tag    = "SILVER_B";
           }
        }
     }

   // 5D. ENGINE 4: GoldFusion SP2L (2-Bar Spike + FVG + 2-Leg Pullback + Breakout)
   // Forensic result from FUSION_04: NY_PM (20:00-20:45) achieved 80.0% WR (+$756.65),
   // whereas NY_AM (16:00-18:15) lost -$862.38 and displaced AMD setups -> SP2L_NY_PM_Only=true!
   if(signal_dir == 0 && Enable_Engine4_GF_SP2L && (!SP2L_NY_PM_Only || active_window == "NY_PM"))
     {
      double   sp2l_extreme = 0.0;
      datetime sp2l_time    = 0;
      int      sp2l_dir     = GF_DetectSP2LSignal(bull_bias, bear_bias, bull_close_quality, bear_close_quality,
                                                  sp2l_extreme, sp2l_time);
      if(sp2l_dir != 0 && GF_FiltersAllow(sp2l_dir, true))
        {
         signal_dir      = sp2l_dir;
         manip_extreme   = sp2l_extreme;
         sp2l_spike_time = sp2l_time;
         engine_tag      = "GF_SP2L";
        }
     }

   if(signal_dir == 0)
      return;

   // 6. Check Spread Filter in Points
   double spread_points = MarketInfo(Symbol(), MODE_SPREAD);
   if(!(IsTesting() && Ignore_Spread_In_Tester))
     {
      if(Max_Spread_Points > 0 && spread_points > Max_Spread_Points)
         return;
     }

   // 7. Calculate M15 Entry, Stop-Loss & Take-Profit
   double leg_size     = MathAbs(Close[1] - manip_extreme);
   double stop_level   = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double spread_price = Ask - Bid;

   double limit_price  = Close[1] - signal_dir * (g_fvg_pullback * leg_size);
   limit_price         = NormalizeDouble(limit_price, Digits);

   bool use_limit = (g_entry_mode == ENTRY_SHALLOW_15_FVG);
   if(use_limit)
     {
      if(signal_dir == 1 && limit_price >= (Ask - stop_level - Point))
         use_limit = false;
      if(signal_dir == -1 && limit_price <= (Bid + stop_level + Point))
         use_limit = false;
     }

   double ref_entry = use_limit ? limit_price : ((signal_dir == 1) ? Ask : Bid);
   double sl_price  = (signal_dir == 1)
                      ? NormalizeDouble(manip_extreme - g_sl_buf_atr * atr1 - spread_price, Digits)
                      : NormalizeDouble(manip_extreme + g_sl_buf_atr * atr1 + spread_price, Digits);

   double risk_dist = MathAbs(ref_entry - sl_price);

   double min_struct_sl = MathMax(Bid * (g_min_sl_pct / 100.0), stop_level + spread_price * 2.0);
   double max_struct_sl = Bid * (g_max_sl_pct / 100.0);

   if(risk_dist < min_struct_sl)
     {
      risk_dist = min_struct_sl;
      sl_price  = NormalizeDouble(ref_entry - signal_dir * risk_dist, Digits);
     }
   if(risk_dist > max_struct_sl)
     {
      g_bull_sweep_active = false;
      g_bear_sweep_active = false;
      return;
     }

   double tp_price = NormalizeDouble(ref_entry + signal_dir * (g_rr_target * risk_dist), Digits);
   int    cmd      = use_limit ? ((signal_dir == 1) ? OP_BUYLIMIT : OP_SELLLIMIT)
                               : ((signal_dir == 1) ? OP_BUY : OP_SELL);
   double lots     = CalculatePositionLots(risk_dist, cmd);

   // 8. Send Order (with automatic Market Order fallback if Limit Order is rejected)
   string comment = "M15_" + engine_tag + "_" + active_window;
   color  clr     = (signal_dir == 1) ? clrDodgerBlue : clrCrimson;
   int    ticket  = OrderSend(Symbol(), cmd, lots, ref_entry, 10, sl_price, tp_price, comment, Magic_Number, 0, clr);

   if(ticket < 0 && use_limit)
     {
      int mkt_cmd   = (signal_dir == 1) ? OP_BUY : OP_SELL;
      double mkt_p  = (signal_dir == 1) ? Ask : Bid;
      double mkt_sl = NormalizeDouble(mkt_p - signal_dir * risk_dist, Digits);
      double mkt_tp = NormalizeDouble(mkt_p + signal_dir * (g_rr_target * risk_dist), Digits);
      ticket = OrderSend(Symbol(), mkt_cmd, lots, mkt_p, 10, mkt_sl, mkt_tp, comment, Magic_Number, 0, clr);
      use_limit = false;
     }

   if(ticket > 0)
     {
      g_bars_since_entry = 0;
      if(sp2l_spike_time > 0)
         g_last_sp2l_spike_time = sp2l_spike_time;
      if(use_limit)
        {
         g_pending_bars_alive  = 0;
         g_pending_inval_price = manip_extreme;
         g_pending_dir         = signal_dir;
         g_pending_window      = active_window;
        }
      if(active_window == "LON10")  g_lon_trades_count++;
      if(active_window == "PRE_NY") g_preny_trades_count++;
      if(active_window == "NY_AM")  g_ny_am_trades_count++;
      if(active_window == "NY_PM")  g_ny_pm_trades_count++;
      if(engine_tag != "GF_SP2L")
        {
         g_bull_sweep_active = false;
         g_bear_sweep_active = false;
        }
      Print("M15 v3.40 Fusion Order Opened [", engine_tag, "|", active_window, "]: Ticket=", ticket, " Type=", cmd,
            " Entry=", ref_entry, " SL=", sl_price, " TP=", tp_price, " Risk$=", DoubleToString(risk_dist, 2), " Lots=", lots);
     }
  }
//+------------------------------------------------------------------+
