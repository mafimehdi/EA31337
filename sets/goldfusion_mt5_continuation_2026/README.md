# Experimental EMA50 continuation A/B (MT5)

Run `goldfusion_mt5_sp2l_continuation_off_control.ini` and
`goldfusion_mt5_sp2l_continuation_on.ini` with the same EA build and Alpari
XAUUSD_i M15 real-tick history. Both retain SP2L body 0.60, Gap on, EMA200
slope 0.2 ATR / 4 bars, TrailStartUSD 2, and extension OFF. The only
configuration difference is `UseContinuationEntry`.

The entry-only continuation path is available in SP2L-only mode. An EMA50
contact starts an episode. The first confirmed breakout on a later closed bar,
within six bars after contact, consumes that episode even if the session or
other entry gates reject it. A fresh contact after a non-contact bar starts a
new episode. The same UT/BB/RSI and order-management gates apply. SP2L has
priority on coincident bars; existing reversal voting remains SP2L-based and
never opens opposite trades. `CONT_DIAG` counts candidates, not positions;
`SIGNAL` lines identify executed engine and three orders per signal.

Compare independent entry batches (`[BATCH]` / `eligible_signals` for the
control), total trades, net profit, equity drawdown, long/short distribution,
and visually inspect representative CONT entries on the chart. This is a
hypothesis test, not evidence of improved performance until run. The
existing January–September 2026 sample is in-sample; independent history
would be preferable for validation. No local MetaEditor or MT5 tester is
available here; compile and run both configurations in MT5 before use.

## Third run: optional shallow-retracement/impulse experiment

`goldfusion_mt5_sp2l_continuation_experimental_on.ini` differs from the
continuation-on file only in `ContinuationExperimental=true`. Both have
`UseContinuationEntry=true`. The experimental logic uses the prior six closed
bars' extreme, a 0.5 ATR retracement and the existing EMA200 trend / four-bar
0.2 ATR slope. On a normal confirming breakout it enters once per episode.
When the confirming candle's range exceeds 1.5 times *prior-bar* ATR, it
instead waits up to three closed bars for a counter-direction candle followed
by a fresh direction-confirming close beyond the preceding candle's high/low.
It does not replay missed out-of-session signals. SP2L entries retain priority.
The original `UseContinuationEntry=true` algorithm is not changed unless the
new flag is enabled. Compare all three runs on the *same newly compiled EA*;
count independent CONT batches and inspect fast-reversing entries, not only net
profit. The numbers are an unoptimized hypothesis, not a live-trading preset.

## Read-only CONT candidate-path diagnostics

Compile the latest `src/GoldFusion_EA_v2.mq5` as `GoldFusion_EA_v2.ex5`, then
run only `goldfusion_mt5_sp2l_continuation_diagnostics_on.ini` to inspect the
previous EMA50 continuation strategy. It differs from `continuation_on.ini`
only in `ContinuationEntryDiagnostics=true`. It does NOT enable the rejected
shallow-retracement experiment. The `[CONT_PATH]` line attributes each
candidate to the first blocking entry gate in the actual OnTick order, or
`ATTEMPT` when execution is tried. `[BATCH]` identifies real filled batches;
`ATTEMPT` alone does not prove an order was filled. `[CONT_PATH_SUMMARY]` totals
are classifications per bar, not trades. Compare final balance 553.76 and
135 positions to the earlier run; if different, stop and diagnose before
changing any trading rule.

## Fourth run: session range breakout / retest (opt-in)

`goldfusion_mt5_sp2l_session_retest_on.ini` differs from `continuation_on.ini`
only in `UseSessionRetestEntry=true`. The former still keeps `CONT` enabled and
`ContinuationExperimental=false`; SP2L takes priority over CONT, which takes
priority over RETEST on a coincident bar. Once six closed M15 candles from the
current 15:00–20:00 broker session are available, a close beyond their high or
low, in the existing EMA200 0.2 ATR / four-bar trend direction, arms a level.
No order opens on the breakout. Within the next four completed candles, a
price touch of that level plus a close back beyond it in the breakout direction
can produce one candidate. A close across the level against the breakout, an
expired window or the session ending cancels the opportunity. One level is
used at most once; a subsequent breakout must exceed the previous used level.
UT/BB/RSI, the same order management and exit-only reversal remain unchanged.
`[RETEST_CANDIDATE]` is not an order; count `[BATCH] ... RETEST` for fills.
Run only this new configuration with the newly compiled EA and compare it to
the established 45 independent batches, +$53.76 and 3.57% equity drawdown.
Do not treat an increase in signal count alone as a success.

## Experimental CONT SELL-only BB bypass

Compile `src/GoldFusion_EA_v2.mq5` again before testing. Run
`goldfusion_mt5_sp2l_continuation_sell_bb_bypass_on.ini` against the same
2026-01-01–2026-09-28 XAUUSD_i M15 real-tick baseline. It differs from
`goldfusion_mt5_sp2l_continuation_on.ini` in exactly one input:
`ContinuationSellBypassBB=true`. This bypasses BB for CONT SELL **entries
only**; CONT BUY, SP2L, RETEST, reversal exits, UT, and trade management
retain their existing rules. The default is false. Compare with the baseline
$53.76 net / 135 positions / 3.57% max equity drawdown, and inspect actual
`[BATCH] engine=CONT` fills and outcomes. Two historical rejected SELL
candidates motivated the experiment; M15 OHLC alone cannot prove their
counterfactual realized profits. Do not treat this as a recommended live preset.
