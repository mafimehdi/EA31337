# GoldFusion EA v6.2 — MT5 port

`GoldFusion_EA_v2.mq5` is a standalone MQL5 expert for **hedging accounts only**. All 53 input defaults match the approved `more_minbodyratio_0_45.set` settings (including `SignalMode=2`, `ReversalPrimary=1`, `SP2L_MinBodyRatio=0.45`, 3/3 position limits, BE 0.4, and server hours 15–20). No separate MT5 SET is necessary. Switching to SP2L-only requires `ReversalPrimary=0` or `2`, as in the MT4 EA.

Entry priority, closed-bar Pullback/SP2L/UT/BB voting, and exit-only reversal were preserved from the MT4 source. MT5's ticket-based hedging positions, indicator handles and trade API replace MT4 order/indicator calls. Stop distances are based on the MT5 broker's tick value and tick size; trade requests are checked using server retcodes. Netting accounts are explicitly rejected because they cannot hold three independently managed positions of the same symbol.

**Verification required before use:** No MetaEditor or MT5 Strategy Tester is available in this workspace, so compilation and trading equivalence have **not** been verified. Compile `GoldFusion_EA_v2.mq5` in MetaEditor 5, review any diagnostics, and compare 2026 XAUUSD M15 backtests with identical symbol contract, historical ticks, spread, commission, server time, account currency and hedging mode. MT4 and MT5 results can legitimately differ because execution and tick modelling differ; do not assume the MT4 profit reports apply to this port. Check the Experts/Journal logs and start on demo only after validation.

Static defaults/source-core check: `python3 tests/goldfusion/check_mt5_port.py`.
