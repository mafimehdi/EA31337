#!/usr/bin/env python3
"""Reproducible MT4 GoldFusion .set scenarios; no external dependencies."""
import csv
import itertools
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'src/GoldFusion_EA_v2.mq4'
OUTPUT = ROOT / 'sets/goldfusion_alpari_xauusd_m15_2026'
INPUT_RE = re.compile(r'^input\s+\w+\s+(\w+)\s*=\s*([^;]+);', re.M)
inputs = dict(INPUT_RE.findall(SOURCE.read_text()))
# MT4 stores enum indices as integers, and bools as true/false.
enum = {'MODE_PULLBACK': '0', 'MODE_SP2L': '1', 'MODE_BOTH': '2',
        'BB_POSITION': '0', 'BB_SLOPE': '1', 'BB_BOTH': '2',
        'RETREAT_FULL_RESET': '0', 'RETREAT_FIXED_DIST': '1',
        'REV_AUTO': '0', 'REV_PULLBACK': '1', 'REV_SP2L': '2'}
base = {k: enum.get(v, v) for k, v in inputs.items()}
# Representative stress/boundary values, not claims of optimality.
choices = {
    'SignalMode': ['0', '1', '2'],
    'TrendEMA': ['100', '300'], 'PullbackEMA': ['20', '80'],
    'PullbackValidBars': ['3', '12'], 'ATR_Period': ['7', '21'],
    'SP2L_SpikeBars': ['3', '4'], 'SP2L_MinSpikeATR': ['0.8', '1.8'],
    'SP2L_MinBodyRatio': ['0.5', '0.75'], 'SP2L_RequireGap': ['false'],
    'SP2L_MaxLegBars': ['4', '12'], 'SP2L_StrictBreak': ['true'],
    'SP2L_UseTrendFilter': ['false'], 'UseUTFilter': ['true'],
    'UT_KeyValue': ['0.7', '1.5'], 'UT_ATRPeriod': ['7', '21'],
    'UseRSIFilter': ['true'], 'RSI_Length': ['7', '21'],
    'RSI_Overbought': ['65', '80'], 'RSI_Oversold': ['20', '35'],
    'RSI_MidLine': ['45', '55'], 'UseBBFilter': ['true'],
    'BB_Length': ['20', '100'], 'BB_FilterMode': ['0', '1'],
    'FixedLot': ['0.02'], 'RiskUSD': ['3.0', '10.0'],
    'RewardUSD': ['0.0', '10.0'], 'MaxOpenTrades': ['1', '5'],
    'TradesPerSignal': ['0', '1'], 'UseBreakEven': ['false'],
    'BE_TriggerUSD': ['0.75', '3.0'], 'BE_Extra_Points': ['0', '50'],
    'UseBE_Retreat': ['false'], 'BE_RetreatMode': ['1'],
    'BE_RetreatDistUSD': ['1.0', '4.0'], 'UseTrailing': ['false'],
    'TrailStartUSD': ['1.5', '4.0'], 'TrailDistUSD': ['1.0', '3.0'],
    'MaxDailyLossUSD': ['10.0', '30.0'], 'MaxTradesPerDay': ['3', '10'],
    'MaxSpreadPoints': ['0', '100'], 'AllowLong': ['false'],
    'AllowShort': ['false'], 'SL_CooldownBars': ['2', '8'],
    'UseTimeFilter': ['false'], 'SessionStartHour': ['8', '20'],
    'SessionEndHour': ['12', '23'], 'CloseOutsideSession': ['true'],
    'DST_Mode': ['1', '3'], 'UseReversal': ['false'],
    'ReversalPrimary': ['1', '2'], 'ShowStatsTable': ['false'],
    'MagicNumber': ['20260928'], 'Slippage': ['10', '50'],
}
assert set(choices) == set(inputs), (set(choices) ^ set(inputs))
OUTPUT.mkdir(parents=True, exist_ok=True)
rows = []

def emit(name, group, overrides, notes):
    config = dict(base)
    config.update(overrides)
    assert config['ReversalPrimary'] != '1' or config['SignalMode'] != '1', name
    assert config['ReversalPrimary'] != '2' or config['SignalMode'] != '0', name
    path = OUTPUT / (name + '.set')
    path.write_bytes(('\n'.join(f'{k}={v}' for k, v in config.items()) + '\n').encode('ascii'))
    rows.append((path.name, group, notes))

emit('00_baseline', 'baseline', {}, 'Original defaults; both engines; optional filters off')
# Every enabled filter subset; both engines get either main-engine selection.
for mode, ut, rsi, bb in itertools.product(('0', '1', '2'), *[('false', 'true')]*3):
    primaries = ('1', '2') if mode == '2' else (('1',) if mode == '0' else ('2',))
    for primary in primaries:
        tag = f'{mode}_{int(ut=="true")}{int(rsi=="true")}{int(bb=="true")}_{primary}'
        emit('10_filters_' + tag, 'filter_matrix',
             {'SignalMode': mode, 'UseUTFilter': ut, 'UseRSIFilter': rsi,
              'UseBBFilter': bb, 'ReversalPrimary': primary},
             'Engine(s), optional votes and mandatory primary; quorum ceil(2N/3)')
# Single-factor scenarios keep dependent features enabled when varying their tuning.
for key, values in choices.items():
    for idx, value in enumerate(values, 1):
        changes = {key: value}
        if key.startswith('UT_'): changes['UseUTFilter'] = 'true'
        if key.startswith('RSI_'): changes['UseRSIFilter'] = 'true'
        if key.startswith('BB_'): changes['UseBBFilter'] = 'true'
        if key.startswith('SP2L_') or key == 'ATR_Period': changes['SignalMode'] = '1'
        if key == 'BE_RetreatMode' or key == 'BE_RetreatDistUSD':
            changes['UseBreakEven'] = 'true'; changes['UseBE_Retreat'] = 'true'
        if key in ('SessionStartHour', 'SessionEndHour', 'DST_Mode', 'CloseOutsideSession'):
            changes['UseTimeFilter'] = 'true'
        if key == 'ReversalPrimary' and value == '2': changes['SignalMode'] = '2'
        emit(f'20_single_{key}_{idx:02}', 'single_factor', changes,
             f'{key}={value}; dependent feature enabled')
# 64-row binary orthogonal array: every pair of these 2-level parameters
# appears in all four combinations (0/0, 0/1, 1/0, 1/1).
# Use baseline and first alternative. All modes/primaries handled in matrix above.
factors = [key for key in choices if key not in ('SignalMode', 'ReversalPrimary')]
assert len(factors) <= 63
for r in range(64):
    changes = {}
    for mask, key in enumerate(factors, 1):
        if (r & mask).bit_count() % 2: changes[key] = choices[key][0]
    emit(f'30_pairwise_{r:02}', 'pairwise', changes,
         'Binary pairwise input coverage; some conditional inputs may be inactive')
with (OUTPUT / 'manifest.csv').open('w', newline='') as f:
    writer = csv.writer(f, lineterminator='\n'); writer.writerow(('file', 'group', 'purpose')); writer.writerows(rows)
print(f'{len(rows)} sets, {len(inputs)} inputs, {len(factors)} binary pairwise factors -> {OUTPUT}')
