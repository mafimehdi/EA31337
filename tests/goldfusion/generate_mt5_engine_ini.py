#!/usr/bin/env python3
"""MT5 /config tester INIs for the previously generated full-input SETs."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[2]
out = root / 'sets/goldfusion_mt5_engines_2026'
for mode in ('both', 'pullback_only', 'sp2l_only'):
    stem = f'goldfusion_mt5_{mode}_body045'
    assert (out / f'{stem}.set').is_file()
    text = '\n'.join((
        '[Tester]',
        'Expert=15.ex5',
        f'ExpertParameters={stem}.set',
        'Symbol=XAUUSD_i',
        'Period=M15',
        'Model=4',
        'Optimization=0',
        'FromDate=2026.01.01',
        'ToDate=2026.09.28',
        'ForwardMode=0',
        'Deposit=500',
        'Currency=USD',
        'Leverage=1:100',
        'Visual=0',
        'UseLocal=1',
        'UseRemote=0',
        'UseCloud=0',
        f'Report=GoldFusion_{mode}_body045_2026',
        'ReplaceReport=1',
        'ShutdownTerminal=0',
        '',
    ))
    (out / f'{stem}.ini').write_text(text, encoding='ascii')
with ZipFile(out.with_suffix('.zip'), 'w', ZIP_DEFLATED) as archive:
    for p in sorted(out.iterdir()):
        if p.is_file(): archive.write(p, p.relative_to(out.parent))
print('Created 3 INIs; ZIP includes 3 INIs + 3 SETs + README')
