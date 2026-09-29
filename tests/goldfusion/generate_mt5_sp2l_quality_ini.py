#!/usr/bin/env python3
"""One-factor SP2L-only MT5 tester INIs using the user's native [TesterInputs]."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[2]
source = root / 'sets/goldfusion_mt5_native_ini_2026/goldfusion_mt5_sp2l_only_body045.ini'
out = root / 'sets/goldfusion_mt5_sp2l_quality_2026'
out.mkdir(parents=True, exist_ok=True)
base = source.read_text(encoding='ascii')
assert base.count('[TesterInputs]') == 1
assert 'Leverage=1:100\n' in base and 'Expert=15.ex5\n' in base
assert 'SignalMode=1||' in base and 'ReversalPrimary=0||' in base and 'UseReversal=true||' in base
cases = (
    ('goldfusion_mt5_sp2l_control_body045.ini', None, None),
    ('goldfusion_mt5_sp2l_minbodyratio_060.ini', 'SP2L_MinBodyRatio', '0.60'),
    ('goldfusion_mt5_sp2l_minspikeatr_15.ini', 'SP2L_MinSpikeATR', '1.5'),
    ('goldfusion_mt5_sp2l_strictbreak_true.ini', 'SP2L_StrictBreak', 'true'),
)
for filename, key, value in cases:
    lines = base.splitlines(keepends=True)
    if key is not None:
        matches = [i for i,line in enumerate(lines) if line.startswith(key+'=')]
        assert len(matches) == 1
        i = matches[0]
        head, sep, tail = lines[i].partition('||')
        assert sep and head != key+'='+value
        lines[i] = key+'='+value+sep+tail
    text = ''.join(lines)
    assert len(text.split('[TesterInputs]\n', 1)[1].splitlines()) == 53
    assert all(text.count(x)==1 for x in ('SignalMode=1||','ReversalPrimary=0||','UseReversal=true||'))
    (out/filename).write_text(text, encoding='ascii')
with ZipFile(out.with_suffix('.zip'), 'w', ZIP_DEFLATED) as z:
    for path in sorted(out.iterdir()):
        if path.is_file(): z.write(path,path.relative_to(out.parent))
print('Generated 4 standalone SP2L-only INIs (one control + three one-factor tests)')
