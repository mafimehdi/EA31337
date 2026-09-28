#!/usr/bin/env python3
"""One-factor SP2L signal sensitivity sets based on personal4 3/3."""
import csv
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[2]
source = root / 'sets/goldfusion_trade_counts_2025_2026/personal4_maxopen_3_persignal_3.set'
out = root / 'sets/goldfusion_spike_signals_2026'
out.mkdir(exist_ok=True)
base = dict(line.split('=', 1) for line in source.read_text(encoding='ascii').splitlines())
assert len(base) == 53
assert base['MaxOpenTrades'] == base['TradesPerSignal'] == '3'
assert base['SignalMode'] == '2' and base['ReversalPrimary'] == '1'
# Group names express a hypothesis, not an observed change in entry counts or quality.
cases = [
    ('control_personal4_maxopen_3_persignal_3', None, None, 'control'),
    ('more_minspikeatr_0_9', 'SP2L_MinSpikeATR', '0.9', 'more'),
    ('more_minbodyratio_0_45', 'SP2L_MinBodyRatio', '0.45', 'more'),
    ('more_requiregap_false', 'SP2L_RequireGap', 'false', 'more'),
    ('more_maxlegbars_16', 'SP2L_MaxLegBars', '16', 'more'),
    ('fewer_minspikeatr_1_5', 'SP2L_MinSpikeATR', '1.5', 'fewer'),
    ('fewer_minbodyratio_0_75', 'SP2L_MinBodyRatio', '0.75', 'fewer'),
    ('fewer_strictbreak_true', 'SP2L_StrictBreak', 'true', 'fewer'),
    ('fewer_maxlegbars_8', 'SP2L_MaxLegBars', '8', 'fewer'),
]
rows = []
for stem, key, value, hypothesis in cases:
    data = dict(base)
    if key:
        assert key.startswith('SP2L_') and key in data and data[key] != value
        data[key] = value
    name = stem + '.set'
    (out / name).write_text(''.join(f'{k}={v}\n' for k, v in data.items()), encoding='ascii')
    rows.append((name, hypothesis, key or 'none', base[key] if key else '', value or ''))
with (out / 'manifest.csv').open('w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f, lineterminator='\n')
    writer.writerow(('file', 'hypothesized_signal_frequency', 'changed_input', 'control_value', 'test_value'))
    writer.writerows(rows)
with ZipFile(out.with_suffix('.zip'), 'w', ZIP_DEFLATED) as archive:
    for path in sorted(out.iterdir()):
        if path.is_file():
            archive.write(path, path.relative_to(out.parent))
print(f'Generated {len(cases)} sets: 1 control, 4 more, 4 fewer')
