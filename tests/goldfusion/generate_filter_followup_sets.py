#!/usr/bin/env python3
"""Generate the 32 filter/primary scenarios under the confirmed exit_1111 regime."""
import csv
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'sets/goldfusion_alpari_xauusd_m15_2026'
OUT = ROOT / 'sets/goldfusion_filters_exit1111_2026'
OUT.mkdir(parents=True, exist_ok=True)
OVERRIDES = {
    'SessionStartHour': '15', 'SessionEndHour': '19',
    'BE_TriggerUSD': '0.5', 'TrailStartUSD': '1.0', 'TrailDistUSD': '1.0',
}
rows = []
for original in sorted(SOURCE.glob('10_filters_*.set')):
    settings = dict(line.split('=', 1) for line in original.read_text().splitlines())
    assert len(settings) == 53
    settings.update(OVERRIDES)
    target = OUT / original.name
    target.write_text(''.join(f'{key}={value}\n' for key, value in settings.items()), encoding='ascii')
    rows.append((target.name, settings['SignalMode'], settings['UseUTFilter'],
                 settings['UseRSIFilter'], settings['UseBBFilter'], settings['ReversalPrimary']))
assert len(rows) == 32
with (OUT / 'manifest.csv').open('w', newline='', encoding='utf-8') as handle:
    writer = csv.writer(handle, lineterminator='\n')
    writer.writerow(('file', 'SignalMode', 'UseUTFilter', 'UseRSIFilter',
                     'UseBBFilter', 'ReversalPrimary'))
    writer.writerows(rows)
with ZipFile(OUT.with_suffix('.zip'), 'w', ZIP_DEFLATED) as archive:
    for path in sorted(OUT.iterdir()):
        if path.is_file():
            archive.write(path, path.relative_to(OUT.parent))
print('Generated', len(rows), 'sets in', OUT)
