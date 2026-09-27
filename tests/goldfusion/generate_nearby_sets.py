#!/usr/bin/env python3
"""One-factor-at-a-time neighbourhood around two frozen 2026 candidates."""
import csv
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'sets/goldfusion_filters_exit1111_2026'
OUT = ROOT / 'sets/goldfusion_nearby_2026'
OUT.mkdir(parents=True, exist_ok=True)
# Two controls and eight single-factor changes for each control.
VARIANTS = (
    ('center', {}),
    ('be_04', {'BE_TriggerUSD': '0.4'}),
    ('be_06', {'BE_TriggerUSD': '0.6'}),
    ('start_08', {'TrailStartUSD': '0.8'}),
    ('start_12', {'TrailStartUSD': '1.2'}),
    ('dist_08', {'TrailDistUSD': '0.8'}),
    ('dist_12', {'TrailDistUSD': '1.2'}),
    ('session_14_19', {'SessionStartHour': '14'}),
    ('session_15_20', {'SessionEndHour': '20'}),
)
rows = []
for tag in ('001', '101'):
    reference = SOURCE / f'10_filters_2_{tag}_1.set'
    base = dict(line.split('=', 1) for line in reference.read_text().splitlines())
    assert len(base) == 53
    assert (base['BE_TriggerUSD'], base['TrailStartUSD'], base['TrailDistUSD'],
            base['SessionStartHour'], base['SessionEndHour']) == ('0.5', '1.0', '1.0', '15', '19')
    for name, change in VARIANTS:
        values = dict(base)
        values.update(change)
        target = OUT / f'filter_{tag}_{name}.set'
        target.write_text(''.join(f'{k}={v}\n' for k, v in values.items()), encoding='ascii')
        rows.append((target.name, tag, name, '; '.join(f'{k}={v}' for k, v in change.items()),
                     '2026 results already supplied' if not change else 'run in MT4'))
assert len(rows) == 18
with (OUT / 'manifest.csv').open('w', newline='', encoding='utf-8') as handle:
    writer = csv.writer(handle, lineterminator='\n')
    writer.writerow(('file', 'filters', 'variant', 'change_from_center', 'status'))
    writer.writerows(rows)
with ZipFile(OUT.with_suffix('.zip'), 'w', ZIP_DEFLATED) as archive:
    for path in sorted(OUT.iterdir()):
        if path.is_file(): archive.write(path, path.relative_to(OUT.parent))
print('18 files: 2 controls already tested, 16 new scenarios')
