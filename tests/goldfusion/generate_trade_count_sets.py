#!/usr/bin/env python3
"""Nine GoldFusion trade-cap tests based on the user's personal preset 4."""
import csv
import itertools
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
for max_open, per_signal in itertools.product((1, 2, 3), repeat=2):
    values = dict(base)
    values['MaxOpenTrades'] = str(max_open)
    values['TradesPerSignal'] = str(per_signal)
    name = f'personal4_maxopen_{max_open}_persignal_{per_signal}.set'
    (OUT / name).write_text(''.join(f'{k}={v}\n' for k, v in values.items()), encoding='ascii')
    rows.append((name, max_open, per_signal, max_open * 10,
                 'already tested at spread 47' if (max_open, per_signal) == (3, 3) else 'new'))
with (OUT / 'manifest.csv').open('w', newline='', encoding='utf-8') as handle:
    writer = csv.writer(handle, lineterminator='\n')
    writer.writerow(('file', 'MaxOpenTrades', 'TradesPerSignal',
                     'maximum_nominal_open_risk_USD', 'status'))
    writer.writerows(rows)
with ZipFile(OUT.with_suffix('.zip'), 'w', ZIP_DEFLATED) as archive:
    for path in sorted(OUT.iterdir()):
        if path.is_file(): archive.write(path, path.relative_to(OUT.parent))
print('Generated 9 trade-count settings; 8 new and 1 existing control')
