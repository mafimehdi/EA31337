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
