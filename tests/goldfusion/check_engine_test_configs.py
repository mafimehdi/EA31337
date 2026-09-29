#!/usr/bin/env python3
"""Static check of the three MT5 engine-comparison configurations.

Verifies, from the files as committed, that the Pullback-only run
(SignalMode=0, ReversalPrimary=1, UseReversal=true) differs from the BOTH
control in SignalMode only, that every tester condition matches the agreed run
conditions, that the native-INI and SET packages agree, and that each case
passes the EA's OnInit ReversalPrimary guard. It also derives the reversal
quorum and the entry gate implied by each case from the EA's own rules.

It runs no backtest and says nothing about profitability.
"""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
native = root / 'sets/goldfusion_mt5_native_ini_2026'
engines = root / 'sets/goldfusion_mt5_engines_2026'
ea = (root / 'src/GoldFusion_EA_v2.mq5').read_text()

# Agreed run conditions: Alpari-MT5 hedging, XAUUSD_i M15, real ticks, $500, 1:100.
CONDITIONS = {'Symbol': 'XAUUSD_i', 'Period': 'M15', 'Model': '4',
              'FromDate': '2026.01.01', 'ToDate': '2026.09.28',
              'Deposit': '500', 'Currency': 'USD', 'Leverage': '1:100'}
BASELINE = {'SP2L_MinBodyRatio': '0.45', 'RiskUSD': '10', 'MaxOpenTrades': '3',
            'TradesPerSignal': '3', 'UseReversal': 'true'}
# case -> (SignalMode, ReversalPrimary, inputs that may differ from the BOTH control)
CASES = {'both': ('2', '1', set()),
         'pullback_only': ('0', '1', {'SignalMode'}),
         'sp2l_only': ('1', '0', {'SignalMode', 'ReversalPrimary'})}
# Derived from the EA rules: (votes total, votes required, primary engine,
# engines whose entry-grade signal always meets the quorum).
EXPECTED_GATE = {'both': (4, 3, 'PB', ['PB']),
                 'pullback_only': (3, 2, 'PB', ['PB']),
                 'sp2l_only': (3, 2, 'SP2L', ['SP2L'])}


def same(a, b):
    """Numeric-tolerant equality: '10' == '10.0'; 'true' compares as text."""
    try:
        return float(a) == float(b)
    except ValueError:
        return a == b


def read_native(path):
    """Return ([Tester] dict, {input: first field}) of a MT5 tester INI."""
    tester, inputs, section = {}, {}, None
    for line in path.read_text(encoding='ascii').splitlines():
        if line.startswith('['):
            section = line.strip('[]')
        elif line.strip():
            key, value = line.split('=', 1)
            if section == 'Tester':
                tester[key] = value
            else:
                inputs[key] = value.split('||')[0]
    return tester, inputs


def read_set(path):
    return dict(line.split('=', 1)
                for line in path.read_text(encoding='ascii').splitlines() if line.strip())


def reversal_gate(inputs):
    """Quorum (EA ReversalConfirmed) and which engine entries it always covers."""
    mode, primary = inputs['SignalMode'], inputs['ReversalPrimary']
    filters = sum(inputs[k] == 'true' for k in ('UseUTFilter', 'UseRSIFilter', 'UseBBFilter'))
    engines_on = [name for name, off_mode in (('PB', '1'), ('SP2L', '0')) if mode != off_mode]
    total = len(engines_on) + filters
    required = (2 * total + 2) // 3          # MQL5 integer division, as in the EA
    if primary == '1':
        engine = 'PB'
    elif primary == '2':
        engine = 'SP2L'
    else:                                     # AUTO: SP2L only when SP2L-only
        engine = 'SP2L' if mode == '1' else 'PB'
    # An entry-grade signal = own engine vote + every enabled filter agreeing, so it
    # carries 1 + filters votes. The primary engine must also vote for the quorum,
    # which only the primary engine's own signal guarantees.
    gated = [e for e in engines_on if e == engine and 1 + filters >= required]
    return total, required, engine, gated


# The EA source must still contain the exact rules this check models. If one of
# these fails after an intentional EA change, update the check AND the comparison
# note (tests/goldfusion/MT5_ENGINE_COMPARISON_FA.md) before trusting either.
compact = re.sub(r'\s+', '', ea)
assert 'int required=(2*total+2)/3;' in ea, 'reversal quorum formula changed; update reversal_gate()'
assert ('(ReversalPrimary==REV_PULLBACK&&SignalMode==MODE_SP2L)||'
        '(ReversalPrimary==REV_SP2L&&SignalMode==MODE_PULLBACK)') in compact, \
    'OnInit ReversalPrimary guard changed; update the OnInit check below'
assert ('if(closeBuys||closeSells){CloseReversedPositions(closeBuys,closeSells);'
        'TrackClosedOrders();ShowStats();return;}') in compact, \
    'reversal branch no longer returns unconditionally; entry-gate note is stale'
ea_inputs = set(re.findall(r'^input\s+\w+\s+(\w+)\s*=', ea, re.M))
assert len(ea_inputs) == 53

parsed = {}
for case, (mode, primary, _) in CASES.items():
    stem = f'goldfusion_mt5_{case}_body045'
    tester, inputs = read_native(native / f'{stem}.ini')
    assert set(inputs) == ea_inputs, (case, set(inputs) ^ ea_inputs)
    actual = (inputs['SignalMode'], inputs['ReversalPrimary'])
    assert actual == (mode, primary), (case, 'SignalMode/ReversalPrimary', actual, 'expected', (mode, primary))
    for key, value in CONDITIONS.items():
        assert tester.get(key) == value, (case, key, tester.get(key), value)
    for key, value in BASELINE.items():
        assert same(inputs[key], value), (case, key, inputs[key], value)
    # EA OnInit guard: a primary engine that SignalMode disables is rejected.
    assert not (inputs['UseReversal'] == 'true' and
                ((primary == '1' and mode == '1') or (primary == '2' and mode == '0'))), \
        (case, 'EA OnInit rejects this SignalMode/ReversalPrimary while UseReversal=true')
    # The SET package and its INI must describe the same run as the native INI.
    flat = read_set(engines / f'{stem}.set')
    drift = sorted(k for k in set(flat) | set(inputs) if not same(flat.get(k, '?'), inputs.get(k, '?')))
    assert not drift, (case, 'engines SET differs from native INI in', drift)
    engine_tester, _ = read_native(engines / f'{stem}.ini')
    for key, value in CONDITIONS.items():
        assert engine_tester.get(key) == value, (case, 'engines INI', key)
    assert engine_tester['ExpertParameters'] == f'{stem}.set', \
        (case, 'engines INI ExpertParameters', engine_tester['ExpertParameters'])
    parsed[case] = (tester, inputs)

control_tester, control_inputs = parsed['both']
print(f'{"case":14s} {"SM":>2s} {"RP":>2s} {"UseRev":>6s}  {"changed vs BOTH":27s} quorum  entries always gated')
for case, (mode, primary, allowed) in CASES.items():
    tester, inputs = parsed[case]
    assert tester == control_tester, \
        (case, '[Tester] differs from BOTH in', sorted(k for k in tester if tester[k] != control_tester.get(k)))
    changed = {k for k in inputs if not same(inputs[k], control_inputs[k])}
    assert changed == allowed, (case, 'inputs changed vs BOTH', sorted(changed), 'allowed', sorted(allowed))
    total, required, engine, gated = reversal_gate(inputs)
    assert (total, required, engine, gated) == EXPECTED_GATE[case], (case, total, required, engine, gated)
    print(f'{case:14s} {mode:>2s} {primary:>2s} {inputs["UseReversal"]:>6s}  '
          f'{",".join(sorted(changed)) or "-":27s} {required}/{total}     {",".join(gated) or "-"}')

print('OK: Pullback-only (SignalMode=0, ReversalPrimary=1, UseReversal=true) equals the BOTH control '
      'except SignalMode; tester conditions, 53 inputs, OnInit guard and both packages verified.')
print('Static check only - no MetaTrader backtest was run and nothing here implies profitability.')
