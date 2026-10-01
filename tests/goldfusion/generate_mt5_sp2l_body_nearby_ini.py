#!/usr/bin/env python3
"""Native MT5 INIs for local SP2L body-ratio sensitivity around 0.60."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[2]
source = root/'sets/goldfusion_mt5_sp2l_quality_2026/goldfusion_mt5_sp2l_minbodyratio_060.ini'
out = root/'sets/goldfusion_mt5_sp2l_body_nearby_2026'
out.mkdir(parents=True, exist_ok=True)
base = source.read_text(encoding='ascii')
needle = 'SP2L_MinBodyRatio=0.60||'
assert base.count(needle) == 1 and 'Leverage=1:100\n' in base
assert 'SignalMode=1||' in base and 'ReversalPrimary=0||' in base and 'UseReversal=true||' in base
cases = {'goldfusion_mt5_sp2l_bodyratio_055.ini':'0.55',
         'goldfusion_mt5_sp2l_bodyratio_060_control.ini':'0.60',
         'goldfusion_mt5_sp2l_bodyratio_065.ini':'0.65',
         'goldfusion_mt5_sp2l_bodyratio_070.ini':'0.70'}
for name,value in cases.items():
    content = base.replace(needle,'SP2L_MinBodyRatio='+value+'||',1)
    assert len(content.split('[TesterInputs]\n',1)[1].splitlines())==53
    assert 'ExpertParameters=' not in content
    (out/name).write_text(content,encoding='ascii')
with ZipFile(out.with_suffix('.zip'),'w',ZIP_DEFLATED) as z:
    for path in sorted(out.iterdir()):
        if path.is_file(): z.write(path,path.relative_to(out.parent))
print('Generated 4 standalone native MT5 INIs, 3 new and 1 already-tested control')
