#!/usr/bin/env python3
"""Controlled 2x2x2x2 MT4 experiments using the original baseline inputs."""
import csv
import itertools
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'sets/goldfusion_alpari_xauusd_m15_2026/00_baseline.set'
OUT = ROOT / 'sets/goldfusion_exit_session_2026'
OUT.mkdir(parents=True, exist_ok=True)
base = dict(line.split('=', 1) for line in BASE.read_text().splitlines())
assert (base['BE_TriggerUSD'], base['TrailStartUSD'], base['TrailDistUSD'],
        base['SessionStartHour'], base['SessionEndHour']) == ('1.5', '2.5', '2.0', '13', '21')
rows = []
for session, be, start, dist in itertools.product((0, 1), repeat=4):
    settings = dict(base)
    settings.update({
        'SessionStartHour': '15' if session else '13',
        'SessionEndHour': '19' if session else '21',
        'BE_TriggerUSD': '0.5' if be else '1.5',
        'TrailStartUSD': '1.0' if start else '2.5',
        'TrailDistUSD': '1.0' if dist else '2.0',
    })
    tag = ''.join(map(str, (session, be, start, dist)))
    filename = f'exit_{tag}.set'
    (OUT / filename).write_text(''.join(f'{k}={v}\n' for k, v in settings.items()), encoding='ascii')
    already = { '0000': '00_baseline', '0111': 'personal_1', '1111': 'personal_2' }.get(tag, '')
    rows.append((filename, session, be, start, dist, already))
with (OUT / 'manifest.csv').open('w', newline='', encoding='utf-8') as handle:
    writer = csv.writer(handle, lineterminator='\n')
    writer.writerow(('file', 'session_15_19', 'be_trigger_0_5', 'trail_start_1_0',
                     'trail_dist_1_0', 'already_tested'))
    writer.writerows(rows)
with ZipFile(OUT.with_suffix('.zip'), 'w', ZIP_DEFLATED) as zipfile:
    for path in sorted(OUT.iterdir()):
        if path.is_file():
            zipfile.write(path, path.relative_to(OUT.parent))
print('16 scenarios; 3 already reported, 13 remaining; output:', OUT)
