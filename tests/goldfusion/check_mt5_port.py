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
assert len(inputs) == len(reference) == 53
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
core4 = core4.replace('iRSI(_Symbol,PERIOD_CURRENT,RSI_Length,PRICE_CLOSE,1)', 'BufferAt(rsiHandle,1)')
assert core4.rstrip() == core5.rstrip(), 'Closed-bar signal and reversal logic drifted from MT4'
assert 'ACCOUNT_MARGIN_MODE_RETAIL_HEDGING' in mq5
print('MT5 default inputs match approved .45 SET; signals/reversal logic match supplied MT4 source.')
