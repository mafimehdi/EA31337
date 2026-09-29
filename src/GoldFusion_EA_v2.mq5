// GoldFusion EA v6.2 MT5 port. Hedging accounts only. Defaults: approved body 0.45 preset.
#property strict
#property version "6.20"
#include <Trade/Trade.mqh>
CTrade trade;
enum ENUM_SIGNAL_MODE { MODE_PULLBACK=0, MODE_SP2L=1, MODE_BOTH=2 };
input ENUM_SIGNAL_MODE SignalMode = MODE_BOTH;
enum ENUM_RETREAT_MODE { RETREAT_FULL_RESET=0, RETREAT_FIXED_DIST=1 };
input int TrendEMA=200;
input int PullbackEMA=50;
input int PullbackValidBars=12;
input int ATR_Period=14;
input int SP2L_SpikeBars=2;
input double SP2L_MinSpikeATR=1.2;
input double SP2L_MinBodyRatio=0.45;
input bool SP2L_RequireGap=true;
input int SP2L_MaxLegBars=12;
input bool SP2L_StrictBreak=false;
input bool SP2L_UseTrendFilter=true;
input bool UseUTFilter=true;
input double UT_KeyValue=1.0;
input int UT_ATRPeriod=14;
input bool UseRSIFilter=false;
input int RSI_Length=14;
input int RSI_Overbought=70;
input int RSI_Oversold=30;
input double RSI_MidLine=50.0;
enum ENUM_BB_MODE { BB_POSITION=0, BB_SLOPE=1, BB_BOTH=2 };
input bool UseBBFilter=true;
input int BB_Length=50;
input ENUM_BB_MODE BB_FilterMode=BB_BOTH;
input double FixedLot=0.01;
input double RiskUSD=10.0;
input double RewardUSD=50.0;
input int MaxOpenTrades=3;
input int TradesPerSignal=3;
input bool UseBreakEven=true;
input double BE_TriggerUSD=0.4;
input int BE_Extra_Points=20;
input bool UseBE_Retreat=true;
input ENUM_RETREAT_MODE BE_RetreatMode=RETREAT_FULL_RESET;
input double BE_RetreatDistUSD=2.0;
input bool UseTrailing=true;
input double TrailStartUSD=1.0;
input double TrailDistUSD=1.0;
input double MaxDailyLossUSD=0.0;
input int MaxTradesPerDay=0;
input int MaxSpreadPoints=50;
input bool AllowLong=true;
input bool AllowShort=true;
input int SL_CooldownBars=1;
input bool UseTimeFilter=true;
input int SessionStartHour=15;
input int SessionEndHour=20;
input bool CloseOutsideSession=false;
input int DST_Mode=0;
// AUTO uses Pullback when both engines are enabled; SP2L when SP2L-only.
// Explicit selection must be enabled by SignalMode. All votes are closed-bar votes.
enum ENUM_REVERSAL_PRIMARY { REV_AUTO=0, REV_PULLBACK=1, REV_SP2L=2 };
input bool UseReversal=true;
input ENUM_REVERSAL_PRIMARY ReversalPrimary=REV_PULLBACK;
input bool ShowStatsTable=true;
input int MagicNumber=20260927;
input int Slippage=30;

#define ENGINE_PB 0
#define ENGINE_SP2L 1
#define MAX_TRACKED 64
MqlRates rates[];
double opens[],highs[],lows[],closes[];
int g_bars=0;
datetime g_lastStatsSecond=0,g_lastModifyLogMinute=0;
int emaTrend=INVALID_HANDLE,emaPull=INVALID_HANDLE,atrHandle=INVALID_HANDLE,utAtrHandle=INVALID_HANDLE,rsiHandle=INVALID_HANDLE;
datetime g_lastBarTime=0;
int g_barIndex=0,g_slHitBar=-1,g_curDayId=0,g_entriesToday=0;
double g_utStop=0,g_dayStartEquity=0,g_profitDollar=0;
int g_trades=0,g_wins=0,g_losses=0,g_breakevens=0,g_tradesPB=0,g_winsPB=0,g_tradesSP=0,g_winsSP=0;
ulong g_knownTickets[MAX_TRACKED],g_beTickets[MAX_TRACKED],g_trailTickets[MAX_TRACKED];
int g_knownCount=0,g_beCount=0,g_trailCount=0;
ulong g_failedModifyIds[MAX_TRACKED];
datetime g_failedModifySecond[MAX_TRACKED];
int g_failedModifyCount=0;
// MQL4 series index: zero is the forming candle.
bool LoadRates()
{
   int available=iBars(_Symbol,_Period);
   g_bars=MathMin(available,MathMax(TrendEMA+PullbackValidBars+SP2L_SpikeBars+SP2L_MaxLegBars+20,350));
   if(g_bars<=0) return(false);
   ArraySetAsSeries(rates,true);
   if(CopyRates(_Symbol,_Period,0,g_bars,rates)<g_bars) return(false);
   ArrayResize(opens,g_bars); ArrayResize(highs,g_bars); ArrayResize(lows,g_bars); ArrayResize(closes,g_bars);
   ArraySetAsSeries(opens,true); ArraySetAsSeries(highs,true); ArraySetAsSeries(lows,true); ArraySetAsSeries(closes,true);
   for(int i=0;i<g_bars;i++) { opens[i]=rates[i].open; highs[i]=rates[i].high; lows[i]=rates[i].low; closes[i]=rates[i].close; }
   return(true);
}
#define Open opens
#define High highs
#define Low lows
#define Close closes

double BufferAt(int handle,int shift)
{
   if(handle==INVALID_HANDLE) return(0);
   double b[];
   if(CopyBuffer(handle,0,shift,1,b)!=1) return(0);
   return(b[0]);
}
double EMA(int period,int shift) { return(BufferAt(period==TrendEMA ? emaTrend : emaPull,shift)); }
double TrueRange(int i)
{
   if(i+1<g_bars) return(MathMax(High[i]-Low[i],MathMax(MathAbs(High[i]-Close[i+1]),MathAbs(Low[i]-Close[i+1]))));
   return(High[i]-Low[i]);
}
double SafeATR(int period,int shift)
{
   double atr=BufferAt(period==UT_ATRPeriod ? utAtrHandle : atrHandle,shift);
   if(atr<=0 || atr<0.00001)
   {
      double sum=0; int cnt=0;
      for(int i=shift;i<shift+period && i<g_bars;i++) { double tr=TrueRange(i); if(tr>0) { sum+=tr; cnt++; } }
      atr=cnt>0 ? sum/cnt : (High[0]-Low[0])*0.5;
   }
   return(atr);
}
double NP(double price) { return(NormalizeDouble(price,_Digits)); }
double DollarsPerPriceUnit(double lot)
{
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE), tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(tickSize<=0 || tickValue<=0) return(0);
   return(lot*tickValue/tickSize);
}
double NormalizeLot(double lot)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.01;
   lot=MathFloor(lot/step)*step;
   lot=MathMax(minLot,MathMin(maxLot,lot));
   int decimals=0; double x=step;
   while(decimals<6 && x<0.9999999) { x*=10; decimals++; }
   if(decimals<1) decimals=1;
   return(NormalizeDouble(lot,decimals));
}
bool Mine(ulong ticket)
{
   return(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==MagicNumber);
}
int CountMyOrders()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i++) if(Mine(PositionGetTicket(i))) n++;
   return(n);
}
bool ListContains(ulong &arr[],int count,ulong ticket)
{
   for(int i=0;i<count;i++) if(arr[i]==ticket) return(true);
   return(false);
}
void ListAdd(ulong &arr[],int &count,ulong ticket)
{
   if(ListContains(arr,count,ticket) || count>=MAX_TRACKED) return;
   arr[count++]=ticket;
}
void ListRemove(ulong &arr[],int &count,ulong ticket)
{
   for(int i=0;i<count;i++) if(arr[i]==ticket)
   { for(int j=i;j<count-1;j++) arr[j]=arr[j+1]; count--; return; }
}
bool IsWinterDST()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.mon>=4 && dt.mon<=9) return(false);
   if(dt.mon>=11 || dt.mon<=2) return(true);
   int last=31; MqlDateTime c; datetime ct;
   while(last>24)
   {
      ZeroMemory(c); c.year=dt.year; c.mon=dt.mon; c.day=last;
      ct=StructToTime(c); TimeToStruct(ct,c);
      if(c.day_of_week==0) break;
      last--;
   }
   if(dt.mon==10) return(dt.day>last || (dt.day==last && dt.hour>=1));
   if(dt.mon==3) return(dt.day<last || (dt.day==last && dt.hour<1));
   return(false);
}
bool InSession()
{
   if(!UseTimeFilter) return(true);
   int startH=SessionStartHour,endH=SessionEndHour;
   bool winter=(DST_Mode==3 || (DST_Mode==1 && IsWinterDST()));
   if(winter) { startH=(startH+23)%24; endH=(endH+23)%24; }
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); int h=dt.hour;
   if(startH==endH) return(true);
   if(startH<endH) return(h>=startH && h<endH);
   return(h>=startH || h<endH);
}
void CheckDailyReset()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int dayId=dt.year*10000+dt.mon*100+dt.day;
   if(dayId==g_curDayId) return;
   g_curDayId=dayId;
   g_trades=0;g_wins=0;g_losses=0;g_breakevens=0;g_profitDollar=0;g_entriesToday=0;
   g_tradesPB=0;g_winsPB=0;g_tradesSP=0;g_winsSP=0;
   g_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
}
bool DailyLimitsOK()
{
   if(MaxDailyLossUSD>0 && g_dayStartEquity>0 && g_dayStartEquity-AccountInfoDouble(ACCOUNT_EQUITY)>=MaxDailyLossUSD) return(false);
   if(MaxTradesPerDay>0 && g_entriesToday>=MaxTradesPerDay) return(false);
   return(true);
}
bool TradeDone()
{
   uint rc=trade.ResultRetcode();
   return(rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL);
}
bool ModifyRecentlyFailed(ulong id)
{
   for(int i=0;i<g_failedModifyCount;i++)
      if(g_failedModifyIds[i]==id) return(g_failedModifySecond[i]==TimeCurrent());
   return(false);
}
void MarkModifyFailure(ulong id)
{
   int slot=-1;
   for(int i=0;i<g_failedModifyCount;i++) if(g_failedModifyIds[i]==id) { slot=i; break; }
   if(slot<0)
   {
      if(g_failedModifyCount<MAX_TRACKED) slot=g_failedModifyCount++;
      else slot=(int)(id%MAX_TRACKED);
   }
   g_failedModifyIds[slot]=id;
   g_failedModifySecond[slot]=TimeCurrent();
}
bool TryModify(ulong ticket,double sl,double tp)
{
   // Invalid/frozen stops cannot be fixed by immediately resending the same
   // request. On real-tick tests those retries plus Sleep stalled the tester.
   for(int i=0;i<3;i++)
   {
      bool sent=trade.PositionModify(ticket,sl,tp);
      uint rc=trade.ResultRetcode();
      if(sent && (TradeDone() || rc==TRADE_RETCODE_NO_CHANGES)) return(true);
      datetime minute=TimeCurrent()/60*60;
      if(minute!=g_lastModifyLogMinute)
      {
         Print("PositionModify #",ticket," failed: ",trade.ResultRetcodeDescription());
         g_lastModifyLogMinute=minute;
      }
      if(rc!=TRADE_RETCODE_REQUOTE && rc!=TRADE_RETCODE_PRICE_CHANGED &&
         rc!=TRADE_RETCODE_TIMEOUT && rc!=TRADE_RETCODE_CONNECTION) break;
      if(i<2 && !MQLInfoInteger(MQL_TESTER)) Sleep(50);
   }
   if(PositionSelectByTicket(ticket)) MarkModifyFailure((ulong)PositionGetInteger(POSITION_IDENTIFIER));
   return(false);
}
bool CloseTicket(ulong ticket,string reason)
{
   for(int r=0;r<3;r++)
   {
      if(trade.PositionClose(ticket,Slippage) && TradeDone()) return(true);
      Print(reason," #",ticket," attempt ",r+1," failed: ",trade.ResultRetcodeDescription());
      if(r<2 && !MQLInfoInteger(MQL_TESTER)) Sleep(100);
   }
   return(false);
}
void CloseAllMyPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i); if(Mine(t)) CloseTicket(t,"Session close"); }
}
void ManageOneOrder(ulong ticket)
{
   if(!Mine(ticket)) return;
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double stopLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(stopLevel<=0) stopLevel=20*_Point;
   double entry=PositionGetDouble(POSITION_PRICE_OPEN), curSL=PositionGetDouble(POSITION_SL), newSL=curSL;
   double upu=DollarsPerPriceUnit(PositionGetDouble(POSITION_VOLUME));
   if(upu<=0) return;
   ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   bool beApplied=ListContains(g_beTickets,g_beCount,positionId);
   bool trailOn=ListContains(g_trailTickets,g_trailCount,positionId);
   double dist=BE_RetreatDistUSD>0 ? BE_RetreatDistUSD : RiskUSD;
   if(dist>RiskUSD) dist=RiskUSD;
   if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
   {
      double profitUSD=(tick.bid-entry)*upu;
      if(UseTrailing && profitUSD>=TrailStartUSD && !trailOn) { ListAdd(g_trailTickets,g_trailCount,positionId); trailOn=true; }
      if(UseBreakEven && profitUSD>=BE_TriggerUSD)
      {
         if(!beApplied) { ListAdd(g_beTickets,g_beCount,positionId); beApplied=true; }
         double beSL=NP(entry+BE_Extra_Points*_Point);
         if(beSL>newSL && tick.bid-beSL>=stopLevel) newSL=beSL;
      }
      if(UseTrailing && profitUSD>=TrailStartUSD)
      { double sl=NP(tick.bid-TrailDistUSD/upu); if(sl>newSL && tick.bid-sl>=stopLevel) newSL=sl; }
      if(UseBE_Retreat && beApplied && !trailOn && tick.bid<entry)
      {
         double sl=BE_RetreatMode==RETREAT_FULL_RESET ? NP(entry-RiskUSD/upu) : NP(MathMax(entry-dist/upu,entry-RiskUSD/upu));
         if(sl<newSL && tick.bid-sl>=stopLevel) newSL=sl;
      }
   }
   else if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)
   {
      double profitUSD=(entry-tick.ask)*upu;
      if(UseTrailing && profitUSD>=TrailStartUSD && !trailOn) { ListAdd(g_trailTickets,g_trailCount,positionId); trailOn=true; }
      if(UseBreakEven && profitUSD>=BE_TriggerUSD)
      {
         if(!beApplied) { ListAdd(g_beTickets,g_beCount,positionId); beApplied=true; }
         double beSL=NP(entry-BE_Extra_Points*_Point);
         if((newSL==0 || beSL<newSL) && beSL-tick.ask>=stopLevel) newSL=beSL;
      }
      if(UseTrailing && profitUSD>=TrailStartUSD)
      { double sl=NP(tick.ask+TrailDistUSD/upu); if((newSL==0 || sl<newSL) && sl-tick.ask>=stopLevel) newSL=sl; }
      if(UseBE_Retreat && beApplied && !trailOn && tick.ask>entry)
      {
         double sl=BE_RetreatMode==RETREAT_FULL_RESET ? NP(entry+RiskUSD/upu) : NP(MathMin(entry+dist/upu,entry+RiskUSD/upu));
         if((newSL==0 || sl>newSL) && sl-tick.ask>=stopLevel) newSL=sl;
      }
   }
   if(newSL!=curSL && !ModifyRecentlyFailed(positionId)) TryModify(ticket,newSL,PositionGetDouble(POSITION_TP));
}
void ManageAllPositions()
{
   ulong tickets[MAX_TRACKED]; int n=0;
   for(int i=PositionsTotal()-1;i>=0 && n<MAX_TRACKED;i--)
   { ulong t=PositionGetTicket(i); if(Mine(t)) tickets[n++]=t; }
   for(int k=0;k<n;k++) ManageOneOrder(tickets[k]);
}
void UpdateUTStop(int shift)
{
   if(shift+1>=g_bars) return;
   double c=Close[shift], cP=Close[shift+1];
   double nLoss=UT_KeyValue*SafeATR(UT_ATRPeriod,shift);
   if(g_utStop==0) g_utStop=c;
   double ns=g_utStop;
   if(c>g_utStop && cP>g_utStop) ns=MathMax(g_utStop,c-nLoss);
   else if(c<g_utStop && cP<g_utStop) ns=MathMin(g_utStop,c+nLoss);
   else if(c>g_utStop) ns=c-nLoss;
   else ns=c+nLoss;
   g_utStop=ns;
}
bool RSIAllow(int dir)
{
   if(!UseRSIFilter) return(true);
   double r=BufferAt(rsiHandle,1);
   if(dir>0) return(r>RSI_MidLine && r<RSI_Overbought);
   return(r<RSI_MidLine && r>RSI_Oversold);
}
double BBMid(int shift)
{
   double sum=0;
   for(int i=0;i<BB_Length;i++) sum+=Close[shift+i];
   return(sum/BB_Length);
}
bool BBAllow(int dir)
{
   if(!UseBBFilter || g_bars<BB_Length+3) return(true);
   double basis=BBMid(1), prev=BBMid(2), c=Close[1];
   if(BB_FilterMode==BB_POSITION) return(dir>0 ? c>basis : c<basis);
   if(BB_FilterMode==BB_SLOPE) return(dir>0 ? basis>prev : basis<prev);
   return(dir>0 ? (c>basis && basis>prev) : (c<basis && basis<prev));
}
bool UTAllow(int dir)
{
   if(!UseUTFilter) return(true);
   return(dir>0 ? Close[1]>g_utStop : Close[1]<g_utStop);
}
// Raw engine signals can be used as reversal votes without optional entry filters.
int PullbackCoreSignal()
{
   double ema200_1=EMA(TrendEMA,1);
   if(ema200_1==0) return(0);
   if(Close[1]>ema200_1 && Close[1]>Open[1] && Close[1]>High[2])
      for(int k=1;k<=PullbackValidBars;k++)
         if(Low[k]<=EMA(PullbackEMA,k) && Close[k]>EMA(TrendEMA,k)) return(+1);
   if(Close[1]<ema200_1 && Close[1]<Open[1] && Close[1]<Low[2])
      for(int k=1;k<=PullbackValidBars;k++)
         if(High[k]>=EMA(PullbackEMA,k) && Close[k]<EMA(TrendEMA,k)) return(-1);
   return(0);
}
int GetPullbackSignal()
{
   int d=PullbackCoreSignal();
   if(d!=0 && UTAllow(d) && RSIAllow(d) && BBAllow(d)) return(d);
   return(0);
}
bool IsBullishSpike(int s,double atr,double &hh)
{
   int n=SP2L_SpikeBars;
   if(s+n+1>=g_bars) return(false);
   hh=0;
   double origin=MathMin(Low[s+n],Low[s+n-1]);
   for(int i=s;i<s+n;i++)
   {
      if(Close[i]<=Open[i]) return(false);
      double range=High[i]-Low[i];
      if(range<=0 || (Close[i]-Open[i])/range<SP2L_MinBodyRatio) return(false);
      if(High[i]>hh) hh=High[i];
   }
   if(hh-origin<SP2L_MinSpikeATR*atr) return(false);
   if(SP2L_RequireGap)
   {
      bool gap=false;
      for(int j=s;j+2<=s+n && !gap;j++) if(Low[j]>High[j+2]) gap=true;
      if(!gap) return(false);
   }
   return(true);
}
bool IsBearishSpike(int s,double atr,double &ll)
{
   int n=SP2L_SpikeBars;
   if(s+n+1>=g_bars) return(false);
   ll=0;
   double origin=MathMax(High[s+n],High[s+n-1]);
   for(int i=s;i<s+n;i++)
   {
      if(Close[i]>=Open[i]) return(false);
      double range=High[i]-Low[i];
      if(range<=0 || (Open[i]-Close[i])/range<SP2L_MinBodyRatio) return(false);
      if(ll==0 || Low[i]<ll) ll=Low[i];
   }
   if(origin-ll<SP2L_MinSpikeATR*atr) return(false);
   if(SP2L_RequireGap)
   {
      bool gap=false;
      for(int j=s;j+2<=s+n && !gap;j++) if(High[j]<Low[j+2]) gap=true;
      if(!gap) return(false);
   }
   return(true);
}
int SP2LCoreSignal()
{
   double atr=SafeATR(ATR_Period,1);
   if(atr<=0) return(0);
   double ema200_1=EMA(TrendEMA,1);
   int maxBack=SP2L_MaxLegBars+2;
   if((!SP2L_UseTrendFilter || (ema200_1!=0 && Close[1]>ema200_1)) && Close[1]>Open[1] && Close[1]>High[2])
   {
      for(int s=2;s<=maxBack;s++)
      {
         double hh=0;
         if(!IsBullishSpike(s,atr,hh)) continue;
         if(SP2L_StrictBreak && Close[1]<=hh) return(0);
         double origin=MathMin(Low[s+SP2L_SpikeBars],Low[s+SP2L_SpikeBars-1]);
         bool leg=false;
         for(int k=s-1;k>=2;k--)
         {
            if(Low[k]<origin) break;
            if(Low[k]<=Low[k+1]) { leg=true; break; }
         }
         if(leg && Low[1]>origin) return(+1);
         return(0); // nearest spike only
      }
   }
   if((!SP2L_UseTrendFilter || (ema200_1!=0 && Close[1]<ema200_1)) && Close[1]<Open[1] && Close[1]<Low[2])
   {
      for(int s=2;s<=maxBack;s++)
      {
         double ll=0;
         if(!IsBearishSpike(s,atr,ll)) continue;
         if(SP2L_StrictBreak && Close[1]>=ll) return(0);
         double origin=MathMax(High[s+SP2L_SpikeBars],High[s+SP2L_SpikeBars-1]);
         bool leg=false;
         for(int k=s-1;k>=2;k--)
         {
            if(High[k]>origin) break;
            if(High[k]>=High[k+1]) { leg=true; break; }
         }
         if(leg && High[1]<origin) return(-1);
         return(0);
      }
   }
   return(0);
}
int GetSP2LSignal()
{
   int d=SP2LCoreSignal();
   if(d!=0 && UTAllow(d) && RSIAllow(d) && BBAllow(d)) return(d);
   return(0);
}
int GetSignal(int &engine)
{
   engine=ENGINE_PB;
   if(SignalMode==MODE_PULLBACK || SignalMode==MODE_BOTH)
   {
      int d=GetPullbackSignal();
      if(d!=0) return(d);
   }
   if(SignalMode==MODE_SP2L || SignalMode==MODE_BOTH)
   {
      int d=GetSP2LSignal();
      if(d!=0) { engine=ENGINE_SP2L; return(d); }
   }
   return(0);
}
// Reversal quorum: ceil(2*N/3), including the mandatory primary engine.
// PB/SP2L each count once when enabled by SignalMode; UT/RSI/BB count
// individually only when enabled. A neutral or contrary vote counts as no.
int ReversalPrimaryEngine()
{
   if(ReversalPrimary==REV_PULLBACK) return(ENGINE_PB);
   if(ReversalPrimary==REV_SP2L) return(ENGINE_SP2L);
   return(SignalMode==MODE_SP2L ? ENGINE_SP2L : ENGINE_PB);
}
bool ReversalConfirmed(int dir,int pbVote,int spVote)
{
   int primary=ReversalPrimaryEngine();
   if((primary==ENGINE_PB ? pbVote : spVote)!=dir) return(false);
   int total=0, votes=0;
   if(SignalMode!=MODE_SP2L) { total++; if(pbVote==dir) votes++; }
   if(SignalMode!=MODE_PULLBACK) { total++; if(spVote==dir) votes++; }
   if(UseUTFilter) { total++; if(g_utStop!=0 && UTAllow(dir)) votes++; }
   if(UseRSIFilter) { total++; if(RSIAllow(dir)) votes++; }
   if(UseBBFilter) { total++; if(g_bars>=BB_Length+3 && BBAllow(dir)) votes++; }
   int required=(2*total+2)/3;
   if(votes<required) return(false);
   Print("[REVERSAL] ",(dir>0 ? "BUY" : "SELL")," confirmed: ",votes,"/",total," (need ",required,") primary=",(primary==ENGINE_PB ? "PB" : "SP2L"));
   return(true);
}
bool CloseReversedPositions(bool closeBuys,bool closeSells)
{
   bool closed=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!Mine(ticket)) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(!((type==POSITION_TYPE_BUY && closeBuys) || (type==POSITION_TYPE_SELL && closeSells))) continue;
      if(CloseTicket(ticket,"[REVERSAL] Close")) { closed=true; Print("[REVERSAL] Closed ticket ",ticket); }
   }
   return(closed);
}
bool OpenSingleTrade(int direction,int engine,int seq,int total)
{
   if(direction>0 && !AllowLong) return(false);
   if(direction<0 && !AllowShort) return(false);
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   { Print("[!] Trading not allowed or disconnected"); return(false); }
   if(RiskUSD<=0 || FixedLot<=0) { Print("[!] RiskUSD and FixedLot must be > 0"); return(false); }
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return(false);
   if(MaxSpreadPoints>0)
   {
      int spr=(int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
      if(spr>MaxSpreadPoints) { Print("[!] Spread ",spr," > max ",MaxSpreadPoints); return(false); }
   }
   double lot=NormalizeLot(FixedLot), upu=DollarsPerPriceUnit(lot);
   if(upu<=0) { Print("[!] Tick value unavailable"); return(false); }
   double slDist=RiskUSD/upu,tpDist=RewardUSD>0 ? RewardUSD/upu : 0;
   double stopLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(stopLevel<=0) stopLevel=20*_Point;
   if(slDist<stopLevel) slDist=stopLevel+_Point;
   if(tpDist>0 && tpDist<stopLevel) tpDist=stopLevel+_Point;
   ENUM_ORDER_TYPE op=direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double margin=0;
   if(!OrderCalcMargin(op,_Symbol,lot,direction>0 ? tick.ask : tick.bid,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   { Print("[!] Not enough free margin"); return(false); }
   string comment=engine==ENGINE_SP2L ? "GF62 SP2L" : "GF62 PB";
   for(int attempt=0;attempt<3;attempt++)
   {
      if(!SymbolInfoTick(_Symbol,tick)) return(false);
      double px=NP(direction>0 ? tick.ask : tick.bid);
      double sl=NP(direction>0 ? px-slDist : px+slDist);
      double tp=tpDist>0 ? NP(direction>0 ? px+tpDist : px-tpDist) : 0;
      bool sent=direction>0 ? trade.Buy(lot,_Symbol,px,sl,tp,comment) : trade.Sell(lot,_Symbol,px,sl,tp,comment);
      if(sent && TradeDone())
      {
         g_entriesToday++;
         // As in MT4, observe new positions during the next tracking pass.
         Print("[SIGNAL ",seq,"/",total,"] engine=",engine==ENGINE_SP2L ? "SP2L" : "PB"," dir=",direction,
               " order=",trade.ResultOrder()," lot=",DoubleToString(lot,2)," SL=",RiskUSD,"$ TP=",RewardUSD,"$");
         return(true);
      }
      Print("[X] Send attempt ",attempt+1," failed: ",trade.ResultRetcodeDescription());
      if(attempt<2 && !MQLInfoInteger(MQL_TESTER)) Sleep(100);
   }
   return(false);
}
void OpenTrades(int direction,int engine,int count)
{
   if(count<=0) return;
   int opened=0;
   for(int i=0;i<count;i++)
   {
      if(MaxTradesPerDay>0 && g_entriesToday>=MaxTradesPerDay) break;
      if(OpenSingleTrade(direction,engine,i+1,count)) opened++;
   }
   if(opened>0) Print("[BATCH] ",opened," trade(s) opened for one ",engine==ENGINE_SP2L ? "SP2L" : "PB"," signal");
}
// MT5 position tickets are distinct on hedging accounts; closed positions are
// reconciled by their immutable POSITION_IDENTIFIER and history position id.
void TrackClosedOrders()
{
   for(int i=0;i<g_knownCount;i++)
   {
      ulong id=g_knownTickets[i]; bool open=false;
      for(int j=PositionsTotal()-1;j>=0 && !open;j--)
      { ulong t=PositionGetTicket(j); if(Mine(t) && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) open=true; }
      if(open) continue;
      if(HistorySelectByPosition(id))
      {
         double p=0; bool found=false; int eng=ENGINE_PB;
         for(int j=0;j<HistoryDealsTotal();j++)
         {
            ulong d=HistoryDealGetTicket(j);
            if(d==0) continue;
            p+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
            if(HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN) { found=true; if(StringFind(HistoryDealGetString(d,DEAL_COMMENT),"SP2L")>=0) eng=ENGINE_SP2L; }
         }
         if(found)
         {
            g_trades++; g_profitDollar+=p;
            if(p>0) g_wins++;
            else if(p<0) { g_losses++;g_slHitBar=g_barIndex; }
            else g_breakevens++;
            if(eng==ENGINE_SP2L) { g_tradesSP++; if(p>0) g_winsSP++; }
            else { g_tradesPB++; if(p>0) g_winsPB++; }
         }
      }
      else Print("[!] Closed position ",id," not found in account history");
      ListRemove(g_knownTickets,g_knownCount,id);
      ListRemove(g_beTickets,g_beCount,id);
      ListRemove(g_trailTickets,g_trailCount,id);
      i--;
   }
   for(int j=PositionsTotal()-1;j>=0;j--)
   { ulong t=PositionGetTicket(j); if(Mine(t)) ListAdd(g_knownTickets,g_knownCount,(ulong)PositionGetInteger(POSITION_IDENTIFIER)); }
}
void ShowStats()
{
   if(!ShowStatsTable) return;
   // One chart update per server second is enough; 75M-tick tests must not
   // rebuild the display on every intra-second tick.
   datetime second=TimeCurrent();
   if(second==g_lastStatsSecond) return;
   g_lastStatsSecond=second;
   string s="[GoldFusion v6.2 MT5 | "+_Symbol+" | "+EnumToString(SignalMode)+"]\n";
   s+=TimeToString(TimeCurrent(),TIME_DATE)+" daily stats\n";
   s+="Trades: "+IntegerToString(g_trades)+" W:"+IntegerToString(g_wins)+" L:"+IntegerToString(g_losses)+" BE:"+IntegerToString(g_breakevens)+"\n";
   s+="Net$: "+DoubleToString(g_profitDollar,2)+" PB "+IntegerToString(g_winsPB)+"/"+IntegerToString(g_tradesPB)+" SP2L "+IntegerToString(g_winsSP)+"/"+IntegerToString(g_tradesSP)+"\n";
   s+="Open: "+IntegerToString(CountMyOrders())+"/"+IntegerToString(MathMax(1,MaxOpenTrades))+" (per signal: "+IntegerToString(TradesPerSignal)+")\n";
   string status="READY";
   if(UseTimeFilter && !InSession()) status="session closed";
   else if(!DailyLimitsOK()) status="DAILY LIMIT HIT";
   else if(SL_CooldownBars>0 && g_slHitBar>=0 && g_barIndex-g_slHitBar<SL_CooldownBars) status="SL cooldown";
   s+="Status: "+status+" Spread: "+IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD))+" pts\n";
   double lotN=NormalizeLot(FixedLot),upu=DollarsPerPriceUnit(lotN);
   s+="FIXED: lot "+DoubleToString(lotN,2)+" | SL "+DoubleToString(RiskUSD,2)+"$";
   if(upu>0) s+=" ("+DoubleToString(RiskUSD/upu,_Digits)+")";
   s+=" | TP "+DoubleToString(RewardUSD,2)+"$\n";
   if(UseBreakEven) s+="BE@"+DoubleToString(BE_TriggerUSD,2)+"$ "+(UseBE_Retreat ? (BE_RetreatMode==RETREAT_FULL_RESET ? "retreat: full reset " : "retreat: fixed ") : "");
   if(UseTrailing) s+="| Trail from "+DoubleToString(TrailStartUSD,2)+"$, dist "+DoubleToString(TrailDistUSD,2)+"$";
   if(UseReversal)
   {
      int n=1; if(SignalMode==MODE_BOTH) n++;
      if(UseUTFilter) n++; if(UseRSIFilter) n++; if(UseBBFilter) n++;
      s+="\nReversal: "+(ReversalPrimaryEngine()==ENGINE_PB ? "PB" : "SP2L")+" primary, quorum "+IntegerToString((2*n+2)/3)+"/"+IntegerToString(n);
   }
   Comment(s);
}
int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   { Print("[!] Hedging account required: netting cannot preserve three independent MT4 positions."); return(INIT_FAILED); }
   if(UseReversal && ((ReversalPrimary==REV_PULLBACK && SignalMode==MODE_SP2L) ||
                       (ReversalPrimary==REV_SP2L && SignalMode==MODE_PULLBACK)))
   { Print("[!] ReversalPrimary must be enabled by SignalMode."); return(INIT_PARAMETERS_INCORRECT); }
   emaTrend=iMA(_Symbol,_Period,TrendEMA,0,MODE_EMA,PRICE_CLOSE);
   emaPull=iMA(_Symbol,_Period,PullbackEMA,0,MODE_EMA,PRICE_CLOSE);
   atrHandle=iATR(_Symbol,_Period,ATR_Period);
   utAtrHandle=iATR(_Symbol,_Period,UT_ATRPeriod);
   rsiHandle=iRSI(_Symbol,_Period,RSI_Length,PRICE_CLOSE);
   if(emaTrend==INVALID_HANDLE || emaPull==INVALID_HANDLE || atrHandle==INVALID_HANDLE || utAtrHandle==INVALID_HANDLE || rsiHandle==INVALID_HANDLE)
   { Print("[!] Indicator handle creation failed"); return(INIT_FAILED); }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   CheckDailyReset();g_lastBarTime=0;
   Print("GoldFusion EA v6.2 MT5 init | ",EnumToString(SignalMode)," | lot=",FixedLot," | SL=",RiskUSD,"$ TP=",RewardUSD,"$ | Hedging only");
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason)
{
   Comment("");
   IndicatorRelease(emaTrend); IndicatorRelease(emaPull);
   IndicatorRelease(atrHandle); IndicatorRelease(utAtrHandle); IndicatorRelease(rsiHandle);
}
void OnTick()
{
   CheckDailyReset(); TrackClosedOrders();
   // Closed-bar entry signals/indicators only need a fresh series once per bar.
   datetime barTime=iTime(_Symbol,_Period,0);
   if(barTime==0) return;
   bool newBar=(barTime!=g_lastBarTime);
   if(newBar && !LoadRates()) return;
   if(newBar)
   {
      g_lastBarTime=barTime;g_barIndex++;
      if(UseUTFilter) UpdateUTStop(1);
   }
   if(UseTimeFilter && CloseOutsideSession && CountMyOrders()>0 && !InSession())
   { CloseAllMyPositions();ShowStats();return; }
   int openNow=CountMyOrders();
   if(openNow>0) ManageAllPositions();
   if(!newBar) { ShowStats();return; }
   if(g_bars<TrendEMA+PullbackValidBars+SP2L_SpikeBars+SP2L_MaxLegBars+5)
   { ShowStats();return; }
   // Reversal is exit-only, before session and entry gates.
   if(UseReversal && openNow>0)
   {
      int pbVote=0,spVote=0;
      if(SignalMode!=MODE_SP2L) pbVote=PullbackCoreSignal();
      if(SignalMode!=MODE_PULLBACK) spVote=SP2LCoreSignal();
      bool closeBuys=ReversalConfirmed(-1,pbVote,spVote);
      bool closeSells=ReversalConfirmed(+1,pbVote,spVote);
      if(closeBuys || closeSells)
      { CloseReversedPositions(closeBuys,closeSells);TrackClosedOrders();ShowStats();return; }
   }
   if(!InSession()) { ShowStats();return; }
   if(!DailyLimitsOK()) { ShowStats();return; }
   if(SL_CooldownBars>0 && g_slHitBar>=0 && g_barIndex-g_slHitBar<SL_CooldownBars)
   { ShowStats();return; }
   openNow=CountMyOrders();
   int slots=MathMax(1,MaxOpenTrades)-openNow;
   if(slots>0)
   {
      int engine=ENGINE_PB,dir=GetSignal(engine);
      if(dir!=0) OpenTrades(dir,engine,MathMin(TradesPerSignal,slots));
   }
   ShowStats();
}
