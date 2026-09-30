//+------------------------------------------------------------------+
//| GoldFusion_EA_v2.mq4 - v6.3 independent initial SL modes          |
//| Standalone XAUUSD EA; reversal only CLOSES existing positions.   |
//+------------------------------------------------------------------+
#property strict
#property description "GoldFusion EA - dollar stops, independent BE/retreat/trail and confirmed reversal exits"

enum ENUM_SIGNAL_MODE { MODE_PULLBACK=0, MODE_SP2L=1, MODE_BOTH=2 };
input ENUM_SIGNAL_MODE SignalMode = MODE_BOTH;
enum ENUM_RETREAT_MODE { RETREAT_FULL_RESET=0, RETREAT_FIXED_DIST=1 };
input int TrendEMA=200;
input int PullbackEMA=50;
input int PullbackValidBars=8;
input int ATR_Period=14;
input int SP2L_SpikeBars=2;
input double SP2L_MinSpikeATR=1.2;
input double SP2L_MinBodyRatio=0.60;
input bool SP2L_RequireGap=true;
input int SP2L_MaxLegBars=8;
input bool SP2L_StrictBreak=false;
input bool SP2L_UseTrendFilter=true;
input bool UseUTFilter=false;
input double UT_KeyValue=1.0;
input int UT_ATRPeriod=14;
input bool UseRSIFilter=false;
input int RSI_Length=14;
input int RSI_Overbought=70;
input int RSI_Oversold=30;
input double RSI_MidLine=50.0;
enum ENUM_BB_MODE { BB_POSITION=0, BB_SLOPE=1, BB_BOTH=2 };
input bool UseBBFilter=false;
input int BB_Length=50;
input ENUM_BB_MODE BB_FilterMode=BB_BOTH;
input double FixedLot=0.01;
input double RiskUSD=5.0;
input double RewardUSD=5.0;
input int MaxOpenTrades=3;
input int TradesPerSignal=3;
// Initial SL modes: either or both may be enabled. Both use the wider distance.
input bool UseFixedDollarStop=true;
input bool UseATRStopFloor=false;
input double ATRStopMult=4.0;
input int ATR_SL_Period=14;
input bool UseSpreadStopBuffer=false;
input bool BE_RetreatNoWorseThanEntry=false;
input bool UseBreakEven=true;
input double BE_TriggerUSD=1.5;
input int BE_Extra_Points=20;
input bool UseBE_Retreat=true;
input ENUM_RETREAT_MODE BE_RetreatMode=RETREAT_FULL_RESET;
input double BE_RetreatDistUSD=2.0;
input bool UseTrailing=true;
input double TrailStartUSD=2.5;
input double TrailDistUSD=2.0;
input double MaxDailyLossUSD=0.0;
input int MaxTradesPerDay=0;
input int MaxSpreadPoints=50;
input bool AllowLong=true;
input bool AllowShort=true;
input int SL_CooldownBars=0;
input bool UseTimeFilter=true;
input int SessionStartHour=13;
input int SessionEndHour=21;
input bool CloseOutsideSession=false;
input int DST_Mode=0;
// AUTO uses Pullback when both engines are enabled; SP2L when SP2L-only.
// Explicit selection must be enabled by SignalMode. All votes are closed-bar votes.
enum ENUM_REVERSAL_PRIMARY { REV_AUTO=0, REV_PULLBACK=1, REV_SP2L=2 };
input bool UseReversal=true;
input ENUM_REVERSAL_PRIMARY ReversalPrimary=REV_AUTO;
input bool ShowStatsTable=true;
input int MagicNumber=20260927;
input int Slippage=30;

#define ENGINE_PB 0
#define ENGINE_SP2L 1
#define MAX_TRACKED 64
datetime g_lastBarTime=0;
int g_barIndex=0, g_slHitBar=-1;
double g_utStop=0.0;
int g_beTickets[MAX_TRACKED], g_beCount=0;
int g_trailTickets[MAX_TRACKED], g_trailCount=0;
int g_knownTickets[MAX_TRACKED], g_knownCount=0;
int g_curDayId=0;
int g_trades=0, g_wins=0, g_losses=0, g_breakevens=0;
double g_profitDollar=0.0;
int g_entriesToday=0;
double g_dayStartEquity=0.0;
int g_tradesPB=0, g_winsPB=0, g_tradesSP=0, g_winsSP=0;

double EMA(int period,int shift) { return(iMA(_Symbol,PERIOD_CURRENT,period,0,MODE_EMA,PRICE_CLOSE,shift)); }
double TrueRange(int i)
{
   if(i+1<Bars) return(MathMax(High[i]-Low[i],MathMax(MathAbs(High[i]-Close[i+1]),MathAbs(Low[i]-Close[i+1]))));
   return(High[i]-Low[i]);
}
double SafeATR(int period,int shift)
{
   double atr=iATR(_Symbol,PERIOD_CURRENT,period,shift);
   if(atr==0.0 || atr<0.00001)
   {
      double sum=0; int cnt=0;
      for(int i=shift;i<shift+period && i<Bars;i++)
      {
         double tr=TrueRange(i);
         if(tr>0) { sum+=tr; cnt++; }
      }
      atr=(cnt>0) ? sum/cnt : (High[0]-Low[0])*0.5;
   }
   return(atr);
}
double NP(double price) { return(NormalizeDouble(price,_Digits)); }
double DollarsPerPriceUnit(double lot)
{
   double tickSize=MarketInfo(_Symbol,MODE_TICKSIZE), tickValue=MarketInfo(_Symbol,MODE_TICKVALUE);
   if(tickSize>0 && tickValue>0) return(lot*tickValue/tickSize);
   double contract=MarketInfo(_Symbol,MODE_LOTSIZE);
   if(contract>0) return(lot*contract);
   return(0.0);
}
double MinStopDist()
{
   double sl=MarketInfo(_Symbol,MODE_STOPLEVEL)*_Point;
   double fl=MarketInfo(_Symbol,MODE_FREEZELEVEL)*_Point;
   double d=MathMax(sl,fl);
   if(UseSpreadStopBuffer)
   {
      double spr=MarketInfo(_Symbol,MODE_SPREAD)*_Point;
      d=MathMax(d,2*spr);
   }
   if(d<=0) d=20*_Point;
   return(d);
}
double NormalizeLot(double lot)
{
   double minLot=MarketInfo(_Symbol,MODE_MINLOT), maxLot=MarketInfo(_Symbol,MODE_MAXLOT);
   double lotStep=MarketInfo(_Symbol,MODE_LOTSTEP);
   if(lotStep<=0) lotStep=0.01;
   lot=MathFloor(lot/lotStep)*lotStep;
   if(lot<minLot) lot=minLot;
   if(lot>maxLot) lot=maxLot;
   int decimals=0; double s=lotStep;
   while(decimals<6 && s<0.9999999) { s*=10; decimals++; }
   if(decimals<1) decimals=1;
   return(NormalizeDouble(lot,decimals));
}
int CountMyOrders()
{
   int cnt=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderSymbol()==_Symbol && OrderMagicNumber()==MagicNumber) cnt++;
   return(cnt);
}
bool ListContains(int &arr[],int count,int ticket)
{
   for(int i=0;i<count;i++) if(arr[i]==ticket) return(true);
   return(false);
}
void ListAdd(int &arr[],int &count,int ticket)
{
   if(ListContains(arr,count,ticket) || count>=MAX_TRACKED) return;
   arr[count]=ticket; count++;
}
void ListRemove(int &arr[],int &count,int ticket)
{
   for(int i=0;i<count;i++) if(arr[i]==ticket)
   {
      for(int j=i;j<count-1;j++) arr[j]=arr[j+1];
      count--; return;
   }
}
bool IsWinterDST()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.mon>=4 && dt.mon<=9) return(false);
   if(dt.mon>=11 || dt.mon<=2) return(true);
   int last=31; MqlDateTime c; datetime ct;
   while(last>24)
   {
      c.year=dt.year; c.mon=dt.mon; c.day=last; c.hour=0; c.min=0; c.sec=0;
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
   int startH=SessionStartHour, endH=SessionEndHour;
   bool winter=(DST_Mode==3 || (DST_Mode==1 && IsWinterDST()));
   if(winter) { startH=(startH+23)%24; endH=(endH+23)%24; }
   int h=TimeHour(TimeCurrent());
   if(startH==endH) return(true);
   if(startH<endH) return(h>=startH && h<endH);
   return(h>=startH || h<endH);
}
bool TradingAllowed()
{
   if(!IsConnected()) { Print("[!] Not connected to server."); return(false); }
   if(!IsTradeAllowed()) { Print("[!] Trading not allowed by terminal."); return(false); }
   if(IsTradeContextBusy()) { Print("[!] Trade context busy, skipped."); return(false); }
   return(true);
}
void CheckDailyReset()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int dayId=dt.year*10000+dt.mon*100+dt.day;
   if(dayId==g_curDayId) return;
   g_curDayId=dayId;
   g_trades=0; g_wins=0; g_losses=0; g_breakevens=0;
   g_profitDollar=0; g_entriesToday=0;
   g_tradesPB=0; g_winsPB=0; g_tradesSP=0; g_winsSP=0;
   g_dayStartEquity=AccountEquity();
}
bool DailyLimitsOK()
{
   if(MaxDailyLossUSD>0 && g_dayStartEquity>0 && g_dayStartEquity-AccountEquity()>=MaxDailyLossUSD) return(false);
   if(MaxTradesPerDay>0 && g_entriesToday>=MaxTradesPerDay) return(false);
   return(true);
}
bool TryModify(int ticket,double entry,double sl,double tp)
{
   for(int i=0;i<3;i++)
   {
      if(OrderModify(ticket,entry,sl,tp,0,clrGreen)) return(true);
      int err=GetLastError();
      if(err==ERR_NO_RESULT) return(true);
      Print("OrderModify attempt ",i+1," failed: ",err);
      if(i<2) { RefreshRates(); Sleep(50); }
   }
   return(false);
}
void CloseAllMyPositions()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=_Symbol || OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType(); if(type!=OP_BUY && type!=OP_SELL) continue;
      int ticket=OrderTicket(); double lots=OrderLots();
      for(int r=0;r<3;r++)
      {
         RefreshRates();
         double px=(type==OP_BUY) ? NP(Bid) : NP(Ask);
         if(OrderClose(ticket,lots,px,Slippage,clrOrange)) break;
         Print("Session close attempt ",r+1," failed: ",GetLastError());
         if(r<2) Sleep(100);
      }
   }
}
void ManageOneOrder(int ticket)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES) || OrderCloseTime()!=0) return;
   double stopLevel=MinStopDist();
   double entry=OrderOpenPrice(), curSL=OrderStopLoss(), newSL=curSL;
   double upu=DollarsPerPriceUnit(OrderLots());
   if(upu<=0) return;
   bool beApplied=ListContains(g_beTickets,g_beCount,ticket);
   bool trailOn=ListContains(g_trailTickets,g_trailCount,ticket);
   double dist=(BE_RetreatDistUSD>0) ? BE_RetreatDistUSD : RiskUSD;
   if(dist>RiskUSD) dist=RiskUSD;
   if(OrderType()==OP_BUY)
   {
      double profitUSD=(Bid-entry)*upu;
      if(UseTrailing && profitUSD>=TrailStartUSD && !trailOn)
      { ListAdd(g_trailTickets,g_trailCount,ticket); trailOn=true; }
      if(UseBreakEven && profitUSD>=BE_TriggerUSD)
      {
         if(!beApplied) { ListAdd(g_beTickets,g_beCount,ticket); beApplied=true; }
         double beSL=NP(entry+BE_Extra_Points*_Point);
         if(beSL>newSL && Bid-beSL>=stopLevel) newSL=beSL;
      }
      if(UseTrailing && profitUSD>=TrailStartUSD)
      {
         double trailSL=NP(Bid-TrailDistUSD/upu);
         if(trailSL>newSL && Bid-trailSL>=stopLevel) newSL=trailSL;
      }
      if(UseBE_Retreat && beApplied && !trailOn && Bid<entry)
      {
         double retreatSL=(BE_RetreatMode==RETREAT_FULL_RESET) ? NP(entry-RiskUSD/upu) : NP(MathMax(entry-dist/upu,entry-RiskUSD/upu));
         if(BE_RetreatNoWorseThanEntry && retreatSL<NP(entry)) retreatSL=NP(entry);
         if(retreatSL<newSL && Bid-retreatSL>=stopLevel) newSL=retreatSL;
      }
      if(MathAbs(newSL-curSL)>_Point/2 && !TryModify(ticket,entry,newSL,OrderTakeProfit())) Print("BUY #",ticket," OrderModify failed after retries");
   }
   else if(OrderType()==OP_SELL)
   {
      double profitUSD=(entry-Ask)*upu;
      if(UseTrailing && profitUSD>=TrailStartUSD && !trailOn)
      { ListAdd(g_trailTickets,g_trailCount,ticket); trailOn=true; }
      if(UseBreakEven && profitUSD>=BE_TriggerUSD)
      {
         if(!beApplied) { ListAdd(g_beTickets,g_beCount,ticket); beApplied=true; }
         double beSL=NP(entry-BE_Extra_Points*_Point);
         if((newSL==0 || beSL<newSL) && beSL-Ask>=stopLevel) newSL=beSL;
      }
      if(UseTrailing && profitUSD>=TrailStartUSD)
      {
         double trailSL=NP(Ask+TrailDistUSD/upu);
         if((newSL==0 || trailSL<newSL) && trailSL-Ask>=stopLevel) newSL=trailSL;
      }
      if(UseBE_Retreat && beApplied && !trailOn && Ask>entry)
      {
         double retreatSL=(BE_RetreatMode==RETREAT_FULL_RESET) ? NP(entry+RiskUSD/upu) : NP(MathMin(entry+dist/upu,entry+RiskUSD/upu));
         if(BE_RetreatNoWorseThanEntry && retreatSL>NP(entry)) retreatSL=NP(entry);
         if((newSL==0 || retreatSL>newSL) && retreatSL-Ask>=stopLevel) newSL=retreatSL;
      }
      if(MathAbs(newSL-curSL)>_Point/2 && !TryModify(ticket,entry,newSL,OrderTakeProfit())) Print("SELL #",ticket," OrderModify failed after retries");
   }
}
void ManageAllPositions()
{
   int tickets[MAX_TRACKED], n=0;
   ArrayInitialize(tickets,0);
   for(int i=OrdersTotal()-1;i>=0 && n<MAX_TRACKED;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=_Symbol || OrderMagicNumber()!=MagicNumber) continue;
      tickets[n++]=OrderTicket();
   }
   for(int k=0;k<n;k++) ManageOneOrder(tickets[k]);
}
void UpdateUTStop(int shift)
{
   if(shift+1>=Bars) return;
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
   double r=iRSI(_Symbol,PERIOD_CURRENT,RSI_Length,PRICE_CLOSE,1);
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
   if(!UseBBFilter || Bars<BB_Length+3) return(true);
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
   if(s+n+1>=Bars) return(false);
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
   if(s+n+1>=Bars) return(false);
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
   if(UseBBFilter) { total++; if(Bars>=BB_Length+3 && BBAllow(dir)) votes++; }
   int required=(2*total+2)/3;
   if(votes<required) return(false);
   Print("[REVERSAL] ",(dir>0 ? "BUY" : "SELL")," confirmed: ",votes,"/",total," (need ",required,") primary=",(primary==ENGINE_PB ? "PB" : "SP2L"));
   return(true);
}
// Closing is independent of session, spread, free slots and daily entry brakes.
// Only successfully closed opposite positions cause entry to be skipped this bar.
bool CloseReversedPositions(bool closeBuys,bool closeSells)
{
   bool closed=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=_Symbol || OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(!((type==OP_BUY && closeBuys) || (type==OP_SELL && closeSells))) continue;
      int ticket=OrderTicket(); double lots=OrderLots();
      for(int r=0;r<3;r++)
      {
         RefreshRates();
         if(OrderClose(ticket,lots,NP(type==OP_BUY ? Bid : Ask),Slippage,clrOrange))
         { closed=true; Print("[REVERSAL] Closed ticket ",ticket); break; }
         Print("[REVERSAL] Close ticket ",ticket," attempt ",r+1," failed: ",GetLastError());
         if(r<2) Sleep(100);
      }
   }
   return(closed);
}
bool OpenSingleTrade(int direction,int engine,int seq,int total)
{
   if(direction>0 && !AllowLong) return(false);
   if(direction<0 && !AllowShort) return(false);
   if(!TradingAllowed()) return(false);
   if(FixedLot<=0 || (UseFixedDollarStop && RiskUSD<=0) || (UseATRStopFloor && (ATRStopMult<=0 || ATR_SL_Period<=0)))
   { Print("[!] Invalid lot or enabled SL mode parameters -> entry skipped."); return(false); }
   if(!UseFixedDollarStop && !UseATRStopFloor)
   { Print("[!] Both initial SL modes disabled -> entry skipped."); return(false); }
   RefreshRates();
   if(MaxSpreadPoints>0)
   {
      int spr=(int)MarketInfo(_Symbol,MODE_SPREAD);
      if(spr>MaxSpreadPoints) { Print("[!] Spread ",spr," > max ",MaxSpreadPoints," -> entry skipped"); return(false); }
   }
   double lot=NormalizeLot(FixedLot), upu=DollarsPerPriceUnit(lot);
   if(upu<=0) { Print("[!] Tick value unavailable, entry skipped."); return(false); }
   double slDist=UseFixedDollarStop ? RiskUSD/upu : 0;
   double tpDist=(RewardUSD>0) ? RewardUSD/upu : 0;
   if(UseATRStopFloor)
   {
      double atrFloor=ATRStopMult*SafeATR(ATR_SL_Period,1);
      if(atrFloor>slDist) slDist=atrFloor;
   }
   double stopLevel=MinStopDist();
   if(slDist<stopLevel) slDist=stopLevel+_Point;
   if(tpDist>0 && tpDist<stopLevel) tpDist=stopLevel+_Point;
   string comment=(engine==ENGINE_SP2L) ? "GF63 SP2L" : "GF63 PB";
   int op=(direction>0) ? OP_BUY : OP_SELL;
   ResetLastError();
   double fm=AccountFreeMarginCheck(_Symbol,op,lot);
   if(fm<=0 || GetLastError()==134) { Print("[!] Not enough free margin, order skipped."); return(false); }
   for(int attempt=0;attempt<3;attempt++)
   {
      RefreshRates();
      double price=(direction>0) ? NP(Ask) : NP(Bid);
      double sl=(direction>0) ? NP(price-slDist) : NP(price+slDist);
      double tp=(tpDist>0) ? ((direction>0) ? NP(price+tpDist) : NP(price-tpDist)) : 0;
      int ticket=OrderSend(_Symbol,op,lot,price,Slippage,sl,tp,comment,MagicNumber,0,(direction>0) ? clrBlue : clrRed);
      if(ticket>0)
      {
         g_entriesToday++; ListAdd(g_knownTickets,g_knownCount,ticket);
         Print("[SIGNAL ",seq,"/",total,"] engine=",(engine==ENGINE_SP2L ? "SP2L" : "PB")," dir=",direction,
               " ticket=",ticket," lot=",DoubleToString(lot,2)," SL=",DoubleToString(RiskUSD,2),
               "$ (",DoubleToString(slDist,_Digits)," price) TP=",DoubleToString(RewardUSD,2),
               "$ (",DoubleToString(tpDist,_Digits)," price)");
         return(true);
      }
      Print("[X] OrderSend attempt ",attempt+1," failed: ",GetLastError());
      if(attempt<2) Sleep(100);
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
   if(opened>0) Print("[BATCH] ",opened," trade(s) opened for one ",(engine==ENGINE_SP2L ? "SP2L" : "PB")," signal");
}
void TrackClosedOrders()
{
   for(int i=0;i<g_knownCount;i++)
   {
      int t=g_knownTickets[i]; bool stillOpen=false;
      for(int j=OrdersTotal()-1;j>=0 && !stillOpen;j--)
         if(OrderSelect(j,SELECT_BY_POS,MODE_TRADES) && OrderTicket()==t && OrderSymbol()==_Symbol && OrderMagicNumber()==MagicNumber) stillOpen=true;
      if(stillOpen) continue;
      if(OrderSelect(t,SELECT_BY_TICKET,MODE_HISTORY))
      {
         double p=OrderProfit()+OrderSwap()+OrderCommission();
         int eng=(StringFind(OrderComment(),"SP2L")>=0) ? ENGINE_SP2L : ENGINE_PB;
         g_trades++; g_profitDollar+=p;
         if(p>0) g_wins++;
         else if(p<0) { g_losses++; g_slHitBar=g_barIndex; }
         else g_breakevens++;
         if(eng==ENGINE_SP2L) { g_tradesSP++; if(p>0) g_winsSP++; }
         else { g_tradesPB++; if(p>0) g_winsPB++; }
      }
      else Print("[!] Closed ticket ",t," not found in account history");
      ListRemove(g_knownTickets,g_knownCount,t);
      ListRemove(g_beTickets,g_beCount,t);
      ListRemove(g_trailTickets,g_trailCount,t);
      i--;
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
      if(OrderSelect(j,SELECT_BY_POS,MODE_TRADES) && OrderSymbol()==_Symbol && OrderMagicNumber()==MagicNumber)
         ListAdd(g_knownTickets,g_knownCount,OrderTicket());
}
void ShowStats()
{
   if(!ShowStatsTable) return;
   string s="[GoldFusion v6.3 | "+_Symbol+" "+EnumToString((ENUM_TIMEFRAMES)Period())+" | "+EnumToString(SignalMode)+"]\n";
   s+=TimeToString(TimeCurrent(),TIME_DATE)+" (daily stats)\n";
   s+="Trades: "+IntegerToString(g_trades)+"  W:"+IntegerToString(g_wins)+"  L:"+IntegerToString(g_losses)+"  BE:"+IntegerToString(g_breakevens)+"\n";
   s+="Net$: "+DoubleToString(g_profitDollar,2)+"   PB "+IntegerToString(g_winsPB)+"/"+IntegerToString(g_tradesPB)+
      "   SP2L "+IntegerToString(g_winsSP)+"/"+IntegerToString(g_tradesSP)+"\n";
   s+="Open: "+IntegerToString(CountMyOrders())+"/"+IntegerToString(MathMax(1,MaxOpenTrades))+
      "  (per signal: "+IntegerToString(TradesPerSignal)+")\n";
   string status="READY";
   if(UseTimeFilter && !InSession()) status="session closed";
   else if(!DailyLimitsOK()) status="DAILY LIMIT HIT";
   else if(SL_CooldownBars>0 && g_slHitBar>=0 && g_barIndex-g_slHitBar<SL_CooldownBars) status="SL cooldown";
   s+="Status: "+status+"   Spread: "+DoubleToString(MarketInfo(_Symbol,MODE_SPREAD),0)+" pts\n";
   double lotN=NormalizeLot(FixedLot);
   s+="Lot "+DoubleToString(lotN,2);
   if(UseFixedDollarStop) s+=" | USD SL base "+DoubleToString(RiskUSD,2)+"$";
   if(UseATRStopFloor) s+=" | ATR SL floor x"+DoubleToString(ATRStopMult,1);
   s+=" | TP "+DoubleToString(RewardUSD,2)+"$";
   s+=" | SL modes: "+(UseFixedDollarStop ? "USD" : "")+
      (UseFixedDollarStop && UseATRStopFloor ? "+" : "")+(UseATRStopFloor ? "ATR floor" : "")+
      (!UseFixedDollarStop && !UseATRStopFloor ? "OFF (no entry)" : "");
   string exits="";
   if(UseBreakEven)
   {
      exits+="BE@"+DoubleToString(BE_TriggerUSD,2)+"$ ";
      if(UseBE_Retreat)
      {
         if(BE_RetreatMode==RETREAT_FULL_RESET) exits+="(retreat: full reset) ";
         else exits+="(retreat: "+DoubleToString(BE_RetreatDistUSD,2)+"$) ";
      }
   }
   if(UseTrailing) exits+="| Trail from "+DoubleToString(TrailStartUSD,2)+"$, dist "+DoubleToString(TrailDistUSD,2)+"$";
   if(exits!="") s+="\n"+exits;
   if(UseReversal)
   {
      int n=1;
      if(SignalMode==MODE_BOTH) n++;
      if(UseUTFilter) n++;
      if(UseRSIFilter) n++;
      if(UseBBFilter) n++;
      s+="\nReversal: "+(ReversalPrimaryEngine()==ENGINE_PB ? "PB" : "SP2L")+
         " primary, quorum "+IntegerToString((2*n+2)/3)+"/"+IntegerToString(n);
   }
   if(MaxDailyLossUSD>0) s+="\nOptional day stop at -"+DoubleToString(MaxDailyLossUSD,2)+"$";
   Comment(s);
}
int OnInit()
{
   if(!UseFixedDollarStop && !UseATRStopFloor)
   { Print("[!] Enable at least one initial SL mode."); return(INIT_PARAMETERS_INCORRECT); }
   if(UseFixedDollarStop && RiskUSD<=0)
   { Print("[!] RiskUSD must be > 0 when fixed-dollar SL is enabled."); return(INIT_PARAMETERS_INCORRECT); }
   if(UseATRStopFloor && (ATRStopMult<=0 || ATR_SL_Period<=0))
   { Print("[!] ATR stop settings must be > 0."); return(INIT_PARAMETERS_INCORRECT); }
   if(UseReversal && ((ReversalPrimary==REV_PULLBACK && SignalMode==MODE_SP2L) ||
                       (ReversalPrimary==REV_SP2L && SignalMode==MODE_PULLBACK)))
   {
      Print("[!] ReversalPrimary must be enabled by SignalMode.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   string su=_Symbol; StringToUpper(su);
   if(StringFind(su,"XAU")<0 && StringFind(su,"GOLD")<0) Print("[!] WARNING: GoldFusion is tuned for gold; current symbol is ",_Symbol);
   if(Period()!=PERIOD_M15 && Period()!=PERIOD_M5)
      Print("[!] WARNING: GoldFusion is tuned for M15/M5; current timeframe is ",EnumToString((ENUM_TIMEFRAMES)Period()));
   CheckDailyReset(); g_lastBarTime=0;
   double lotN=NormalizeLot(FixedLot), upu=DollarsPerPriceUnit(lotN);
   Print("GoldFusion_EA v6.3 init on ",_Symbol," ",EnumToString((ENUM_TIMEFRAMES)Period()),
         " | engines=",EnumToString(SignalMode)," | lot=",DoubleToString(lotN,2),
         " | USD SL base=",(UseFixedDollarStop ? DoubleToString(RiskUSD,2)+"$" : "off"),
         " | ATR SL floor=",(UseATRStopFloor ? "x"+DoubleToString(ATRStopMult,1) : "off"),
         " | TP=",DoubleToString(RewardUSD,2),"$",(upu>0 ? " (= "+DoubleToString(RewardUSD/upu,_Digits)+" price)" : ""),
         " | BE@",DoubleToString(BE_TriggerUSD,2),"$ retreat=",
         (UseBE_Retreat ? (BE_RetreatMode==RETREAT_FULL_RESET ? "reset" : DoubleToString(BE_RetreatDistUSD,2)+"$") : "off"),
         " | Trail from ",DoubleToString(TrailStartUSD,2),"$ dist ",DoubleToString(TrailDistUSD,2),"$",
         " | MaxOpen=",MathMax(1,MaxOpenTrades)," | PerSignal=",TradesPerSignal,
         " | Reversal=",(UseReversal ? EnumToString(ReversalPrimary) : "off"));
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) { Comment(""); }
void OnTick()
{
   CheckDailyReset(); TrackClosedOrders();
   bool newBar=(Time[0]!=g_lastBarTime);
   if(newBar)
   {
      g_lastBarTime=Time[0]; g_barIndex++;
      if(UseUTFilter) UpdateUTStop(1);
   }
   if(UseTimeFilter && CloseOutsideSession && CountMyOrders()>0 && !InSession())
   { CloseAllMyPositions(); ShowStats(); return; }
   int openNow=CountMyOrders();
   if(openNow>0) ManageAllPositions();
   if(!newBar) { ShowStats(); return; }
   if(Bars<TrendEMA+PullbackValidBars+SP2L_SpikeBars+SP2L_MaxLegBars+5)
   { ShowStats(); return; }
   // Exit before all entry gates, even outside session / while daily limits apply.
   if(UseReversal && openNow>0)
   {
      int pbVote=0, spVote=0;
      if(SignalMode!=MODE_SP2L) pbVote=PullbackCoreSignal();
      if(SignalMode!=MODE_PULLBACK) spVote=SP2LCoreSignal();
      bool closeBuys=ReversalConfirmed(-1,pbVote,spVote);
      bool closeSells=ReversalConfirmed(+1,pbVote,spVote);
      if(closeBuys || closeSells)
      {
         CloseReversedPositions(closeBuys,closeSells);
         TrackClosedOrders(); ShowStats(); return; // retry failed closes on next bar; no entry
      }
   }
   if(!InSession()) { ShowStats(); return; }
   if(!DailyLimitsOK()) { ShowStats(); return; }
   if(SL_CooldownBars>0 && g_slHitBar>=0 && g_barIndex-g_slHitBar<SL_CooldownBars)
   { ShowStats(); return; }
   openNow=CountMyOrders();
   int slots=MathMax(1,MaxOpenTrades)-openNow;
   if(slots>0)
   {
      int engine=ENGINE_PB, dir=GetSignal(engine);
      if(dir!=0) OpenTrades(dir,engine,MathMin(TradesPerSignal,slots));
   }
   ShowStats();
}
//+------------------------------------------------------------------+
