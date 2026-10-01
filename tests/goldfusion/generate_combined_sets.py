#!/usr/bin/env python3
"""Two previously untested combinations; no other GoldFusion inputs change."""
import csv
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'sets/goldfusion_nearby_2026'
OUT = ROOT / 'sets/goldfusion_combined_be04_session1520_2026'
OUT.mkdir(parents=True, exist_ok=True)
rows = []
for tag in ('001', '101'):
    base = dict(line.split('=', 1) for line in (SOURCE / f'filter_{tag}_center.set').read_text().splitlines())
    assert len(base) == 53
    assert (base['BE_TriggerUSD'], base['SessionStartHour'], base['SessionEndHour']) == ('0.5', '15', '19')
    base['BE_TriggerUSD'] = '0.4'
    base['SessionEndHour'] = '20'
    filename = f'filter_{tag}_be_04_session_15_20.set'
    (OUT / filename).write_text(''.join(f'{k}={v}\n' for k, v in base.items()), encoding='ascii')
    rows.append((filename, tag, '0.4', '15', '20'))
with (OUT / 'manifest.csv').open('w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f, lineterminator='\n')
    writer.writerow(('file', 'filters', 'BE_TriggerUSD', 'SessionStartHour', 'SessionEndHour'))
    writer.writerows(rows)
with ZipFile(OUT.with_suffix('.zip'), 'w', ZIP_DEFLATED) as z:
    for path in sorted(OUT.iterdir()):
        if path.is_file(): z.write(path, path.relative_to(OUT.parent))
print('Created:', ', '.join(row[0] for row in rows))
