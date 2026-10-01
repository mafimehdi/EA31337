#!/usr/bin/env python3
"""Full-input MT5 hedging mode comparison from approved body-ratio 0.45."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import re

root = Path(__file__).resolve().parents[2]
source = root / 'sets/goldfusion_spike_signals_2026/more_minbodyratio_0_45.set'
out = root / 'sets/goldfusion_mt5_engines_2026'
out.mkdir(parents=True, exist_ok=True)
base = dict(line.split('=', 1) for line in source.read_text(encoding='ascii').splitlines())
assert len(base) == 53 and base['SP2L_MinBodyRatio'] == '0.45'
assert base['SignalMode'] == '2' and base['ReversalPrimary'] == '1'
variants = {
    'goldfusion_mt5_both_body045.set': ('2', '1'),
    'goldfusion_mt5_pullback_only_body045.set': ('0', '1'),
    'goldfusion_mt5_sp2l_only_body045.set': ('1', '0'),
}
for filename, (mode, primary) in variants.items():
    data = dict(base, SignalMode=mode, ReversalPrimary=primary)
    (out / filename).write_text(''.join(f'{k}={v}\n' for k,v in data.items()), encoding='ascii')
    changed = {k for k in base if base[k] != data[k]}
    assert changed <= {'SignalMode','ReversalPrimary'}
    assert not (mode == '1' and primary == '1')
# Ensure every expected input exists in the MQL5 file, including enums.
code = (root / 'src/GoldFusion_EA_v2.mq5').read_text()
inputs = set(re.findall(r'^input\s+\w+\s+(\w+)\s*=', code, re.M))
assert set(base) == inputs, (set(base)-inputs, inputs-set(base))
with ZipFile(out.with_suffix('.zip'), 'w', ZIP_DEFLATED) as z:
    for p in sorted(out.iterdir()):
        if p.is_file(): z.write(p, p.relative_to(out.parent))
print('Validated 3 modes, 53 inputs each, MT5 EA input names and ZIP')
