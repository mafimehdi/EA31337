#!/usr/bin/env python3
"""Six behaviorally distinct GoldFusion trade-cap tests."""
import csv
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'sets/goldfusion_combined_be04_session1520_2026/filter_101_be_04_session_15_20.set'
OUT = ROOT / 'sets/goldfusion_trade_counts_2025_2026'
OUT.mkdir(parents=True, exist_ok=True)
base = dict(line.split('=', 1) for line in SOURCE.read_text().splitlines())
assert len(base) == 53
# Reconstruct personal preset 4, as verified in the user's 2025/2026 reports.
base.update({'PullbackValidBars': '12', 'SP2L_MaxLegBars': '12',
             'RiskUSD': '10', 'RewardUSD': '50', 'SL_CooldownBars': '1',
             'ATR_Period': '14'})
assert base['SignalMode'] == '2' and base['UseUTFilter'] == 'true' and base['UseBBFilter'] == 'true'
assert base['BE_TriggerUSD'] == '0.4' and base['SessionStartHour'] == '15' and base['SessionEndHour'] == '20'
rows = []
expected = set()
for max_open in (1, 2, 3):
    for per_signal in range(1, max_open + 1):
        values = dict(base)
        values['MaxOpenTrades'] = str(max_open)
        values['TradesPerSignal'] = str(per_signal)
        name = f'personal4_maxopen_{max_open}_persignal_{per_signal}.set'
        expected.add(name)
        (OUT / name).write_text(''.join(f'{k}={v}\n' for k, v in values.items()), encoding='ascii')
        rows.append((name, max_open, per_signal, max_open * 10,
                     'already tested at spread 47' if (max_open, per_signal) == (3, 3) else 'new'))
# Remove only stale .set files from this generated folder (the redundant cases).
for path in OUT.glob('personal4_maxopen_*_persignal_*.set'):
    if path.name not in expected:
        path.unlink()
# The loop in OnTick uses min(TradesPerSignal, MaxOpenTrades - openNow).
# No other part of this EA reads TradesPerSignal, so a value above max_open
# has exactly the same requested batch size for every possible openNow.
for max_open in (1, 2, 3):
    for per_signal in range(max_open + 1, 4):
        assert all(min(per_signal, max_open - n) == min(max_open, max_open - n)
                   for n in range(max_open))
assert len(rows) == 6
with (OUT / 'manifest.csv').open('w', newline='', encoding='utf-8') as handle:
    writer = csv.writer(handle, lineterminator='\n')
    writer.writerow(('file', 'MaxOpenTrades', 'TradesPerSignal',
                     'maximum_nominal_open_risk_USD', 'status'))
    writer.writerows(rows)
with ZipFile(OUT.with_suffix('.zip'), 'w', ZIP_DEFLATED) as archive:
    for path in sorted(OUT.iterdir()):
        if path.is_file(): archive.write(path, path.relative_to(OUT.parent))
print('Generated 6 distinct trade-count settings; 5 new and 1 existing control')
