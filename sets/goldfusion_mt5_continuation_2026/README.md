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
