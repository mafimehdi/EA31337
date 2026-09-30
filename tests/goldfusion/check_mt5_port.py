#!/usr/bin/env python3
"""Static parity checks; does not substitute for MetaEditor/Strategy Tester."""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
mq4 = (root / 'src/GoldFusion_EA_v2.mq4').read_text()
mq5 = (root / 'src/GoldFusion_EA_v2.mq5').read_text()
reference = dict(line.split('=', 1) for line in
                 (root / 'sets/goldfusion_spike_signals_2026/more_minbodyratio_0_45.set').read_text().splitlines())
inputs = dict(re.findall(r'^input\s+\w+\s+(\w+)\s*=\s*([^;]+);', mq5, re.M))
assert len(reference) == 53
assert len(inputs) == 65
assert {k: inputs[k] for k in ("SP2L_UseEMASlope", "SP2L_EMASlopeBars", "SP2L_MinSlopeATR")} == {
    "SP2L_UseEMASlope": "false", "SP2L_EMASlopeBars": "4", "SP2L_MinSlopeATR": "0.2"}
named = {'SignalMode': {'2': 'MODE_BOTH'}, 'BB_FilterMode': {'2': 'BB_BOTH'},
         'BE_RetreatMode': {'0': 'RETREAT_FULL_RESET'}, 'ReversalPrimary': {'1': 'REV_PULLBACK'}}
for k, v in reference.items():
    expected = named.get(k, {}).get(v, v)
    actual = inputs[k]
    assert actual == expected or (actual not in ('true', 'false') and expected not in ('true', 'false')
                                  and float(actual) == float(expected)), (k, actual, expected)
start, end = 'void UpdateUTStop(', '// Closing is independent of session'
core4 = mq4[mq4.index(start):mq4.index(end)]
core5 = mq5[mq5.index(start):mq5.index('bool CloseReversedPositions(', mq5.index(start))]
core5 = core5[:core5.index('// Alternative closed-bar setup.')] + core5[core5.index('int GetSignal(int &engine)'): ]
core5 = core5.replace('''   if(UseContinuationEntry && SignalMode==MODE_SP2L && g_contCandidate!=0)
   {
      int d=g_contCandidate;
      if(UTAllow(d) && RSIAllow(d) && BBAllow(d))
      { engine=ENGINE_CONT; g_contPassed++; return(d); }
      g_contFiltered++;
   }
''', '')
core4 = core4.replace('iRSI(_Symbol,PERIOD_CURRENT,RSI_Length,PRICE_CLOSE,1)', 'BufferAt(rsiHandle,1)')
core4 = re.sub(r'\bBars\b', 'g_bars', core4)
assert core4.rstrip() == core5.rstrip(), 'Closed-bar signal and reversal logic drifted from MT4'
assert not re.search(r'\bBars\b', mq5), 'MQL5 Bars() built-in must not be shadowed'
assert 'for(int i=PositionsTotal()-1;i>=0;i--) if(Mine(PositionGetTicket(i))) n++;' in mq5
assert '[EXIT_DIAG]' in mq5 and '[EXIT_SUMMARY]' in mq5
assert 'OrderCalcProfit(' in mq5 and 'SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE)' not in mq5
assert 'ACCOUNT_MARGIN_MODE_RETAIL_HEDGING' in mq5
print('MT5 default inputs match approved .45 SET; signals/reversal logic match supplied MT4 source.')

assert 'SP2LEMASlopeAllows(dir) && SP2LExtensionAllows(dir)' in mq5
assert 'SP2L_UseMaxExtension=false;' in mq5
assert 'dir*(now-past)>=SP2L_MinSlopeATR*atr' in mq5

# New experimental path is opt-in, entry-only and compared against identical tester settings.
assert inputs['UseContinuationEntry'] == 'false'
assert inputs['ContinuationTouchBars'] == '6'
assert 'UpdateContinuation();' in mq5 and 'engine=ENGINE_CONT' in mq5
assert mq5.index('UpdateContinuation();') < mq5.index('if(!InSession()) { ShowStats();return; }')
config_dir = root / 'sets/goldfusion_mt5_continuation_2026'
off = (config_dir / 'goldfusion_mt5_sp2l_continuation_off_control.ini').read_text()
on = (config_dir / 'goldfusion_mt5_sp2l_continuation_on.ini').read_text()
assert on.replace('UseContinuationEntry=true||false||0||true||N',
                  'UseContinuationEntry=false||false||0||true||N') == off
experimental = (config_dir / 'goldfusion_mt5_sp2l_continuation_experimental_on.ini').read_text()
assert experimental.replace('ContinuationExperimental=true||false||0||true||N',
                            'ContinuationExperimental=false||false||0||true||N') == on
assert 'SP2L_UseMaxExtension=false||' in on
assert 'SP2L_MinBodyRatio=0.60||' in on

assert inputs['ContinuationEntryDiagnostics'] == 'false'
assert 'DiagnoseContinuationCandidate(false);' in mq5
assert 'labels[reason]' in mq5
base = (config_dir / 'goldfusion_mt5_sp2l_continuation_on.ini').read_text()
verbose = (config_dir / 'goldfusion_mt5_sp2l_continuation_diagnostics_on.ini').read_text()
assert verbose.replace('ContinuationEntryDiagnostics=true||false||0||true||N',
                       'ContinuationEntryDiagnostics=false||false||0||true||N') == base
assert 'ContinuationExperimental=false||' in verbose
