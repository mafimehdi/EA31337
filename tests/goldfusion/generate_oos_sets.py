#!/usr/bin/env python3
"""Package four frozen GoldFusion candidates for an untouched 2025 test."""
import csv
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'sets/goldfusion_filters_exit1111_2026'
OUT = ROOT / 'sets/goldfusion_oos_2025'
OUT.mkdir(parents=True, exist_ok=True)
rows = []
for tag, description in (
    ('000', 'Both engines; no optional filters'),
    ('001', 'Both engines; BB only'),
    ('101', 'Both engines; UT and BB'),
    ('111', 'Both engines; UT, RSI and BB'),
):
    filename = f'10_filters_2_{tag}_1.set'
    content = (SOURCE / filename).read_bytes()
    (OUT / filename).write_bytes(content)  # do not tune parameters using 2025 results
    rows.append((filename, description))
with (OUT / 'manifest.csv').open('w', newline='', encoding='utf-8') as handle:
    writer = csv.writer(handle, lineterminator='\n')
    writer.writerow(('file', 'configuration'))
    writer.writerows(rows)
with ZipFile(OUT.with_suffix('.zip'), 'w', ZIP_DEFLATED) as archive:
    for path in sorted(OUT.iterdir()):
        if path.is_file():
            archive.write(path, path.relative_to(OUT.parent))
print('Packaged 4 unmodified candidates:', OUT)
