# AlgoX SuperTrend Pro EA - M5 / M15 presets (round 3, after two live rounds)

Ready-made MT4 presets for `src/AlgoX_SuperTrend_Pro_EA.mq4`. Round 1 was wiped by a sizing error
and a 0.47 spread on M1; round 2 found the first preset with a real edge. Read the results first.

## Round 2 results (M5 / M15, 47 spread, 500 USD, 2026.01.01-2026.09.25)

| Preset | TF | Trades | Net | PF | Win % | Avg win | Avg loss | Break-even win % | Gap | Max DD |
|---|---|---|---|---|---|---|---|---|---|---|
| `00_Pine_Baseline` (control) | M15 | 17 | -491.12 | 0.16 | 64.7 | 8.79 | -97.96 | 91.8 | -27.1 | 99.5% |
| `M15_A_Breakout_Volume` | M15 | 52 | -126.27 | 0.80 | 40.4 | 24.38 | -20.59 | 45.8 | -5.4 | 57.8% |
| `M15_B_Trend_Runner` | M15 | 118 | -463.29 | 0.60 | 50.0 | 11.96 | -19.81 | 62.4 | -12.4 | 93.3% |
| `M15_C_NY_Expansion` | M15 | 10 | **+69.75** | **2.26** | 40.0 | 31.30 | -9.24 | 22.8 | **+17.2** | 8.1% |
| `M5_A_Breakout_Volume` | M5 | 155 | **+84.10** | **1.11** | 40.7 | 13.87 | -8.59 | 38.3 | **+2.4** | 21.6% |
| `M5_B_Trend_Momentum` | M5 | 876 | -304.36 | 0.92 | 45.7 | 8.65 | -7.91 | 47.8 | -2.1 | 93.8% |
| `M5_C_NY_Expansion` | M5 | 36 | -47.42 | 0.75 | 33.3 | 12.03 | -7.99 | 39.9 | -6.6 | 13.4% |

Modelling quality 90% (up from 25% in round 1), so these numbers are comparable.

### What the numbers say

1. **The breakout family wins, the trend + momentum family loses.** `M5_A` (structure break + 200-bar
   extreme + relative volume) is the only preset with a usable sample that clears its break-even win
   rate (+2.4 points, PF 1.11). `M5_B` and `M15_B` (trend + MACD) both sit below their break-even
   win rate. This is consistent with the published evidence: momentum indicators alone are weak, the
   volume/expansion combination is the one that carries information.
2. **The runner exit destroys the payoff ratio.** `M15_B` wins 50% of its trades but has an average
   win of 11.96 against an average loss of 19.81 (ratio 0.60) - the trailing stop cuts the winners
   and leaves the losers full size. The fixed TP2 with the break-even trigger has a ratio of 1.61
   (`M5_A`). Do not use the trailing exit on this system.
3. **The session filter is a coin flip.** On M15 it produced the best single result (`M15_C`,
   PF 2.26) - but on only 10 trades, which is statistically meaningless. On M5 the same filter made
   things worse (`M5_C` 0.75 vs `M5_A` 1.11). Keep it as a "watch", not as a conclusion.
4. **`M5_A` is not a free lunch yet.** The same preset made 84 USD in 9 months (17%) with a 21.6%
   drawdown, and its largest single win (196 USD) is 22% of the gross profit - the result leans on
   a few trades. It needs an out-of-sample run before it deserves real money.
5. **The control is a catastrophe, and it exposed a real bug.** The raw signal lost 491 USD with a
   -511 USD single trade: the fill arrived without a working stop loss and nothing stopped it. That
   is now impossible (see the new guards below).

## What is different in this set (round 3)

| | Round 1 (M1) | Round 2 (M5/M15) | Round 3 (now) |
|---|---|---|---|
| Sizing | PINE_FIXED, 10x too much | AX_SIZING_BROKER 0.5% | same |
| Margin cap / daily loss cap / trade cap | none | yes | yes |
| Equity stop | none | -20% | -20% |
| **Max loss per single trade** | **none** | **none** | **2% of the balance, closes the trade** |
| **Stop loss integrity check** | **none** | **none** | **SL re-attached when the fill has none or a farther one** |
| Live spread cap | off | 60 points | 60 points |

The two new guards are the direct answer to the `00_Pine_Baseline` report:
`InpMaxTradeLossPercent=2.0` closes any trade whose floating loss reaches 2% of the balance, and
`InpForceStopLoss=true` re-attaches the stop at the intended risk distance when the fill arrives
without one (`SAFETY: stop loss fixed ...` in the journal).

## The presets

| File | TF | Status | Idea | Hard filters | ATR gate |
|---|---|---|---|---|---|
| `00_Pine_Baseline` | M15 | control | the raw signal, no cost gates | none | off |
| `M5_A_Breakout_Volume` | M5 | **candidate** | expansion breakout + volume (PF 1.11) | structure, RVOL, 200-bar | 2.0 |
| `M15_C_NY_Expansion` | M15 | watch (10 trades) | breakout + NY session (PF 2.26) | structure, RVOL, 200-bar | 3.5 |
| `M5_C_NY_Expansion` | M5 | watch | M5 breakout in the NY session (PF 0.75) | structure, RVOL, 200-bar, NY | 2.5 |
| `M15_A_Breakout_Volume` | M15 | reference (PF 0.80) | the M15 breakout, too slow | structure, RVOL, 200-bar | 3.0 |
| `M5_B_Trend_Momentum` | M5 | rejected (PF 0.92) | trend (M30) + MACD, 876 trades | M30 trend, MACD | 2.0 |
| `M15_B_Trend_Runner` | M15 | rejected (PF 0.60) | trend + MACD with the ATR trailing runner | H1 trend, MACD | 3.0 |

Statuses come from the round 2 results above. `candidate` = worth an out-of-sample run,
`watch` = promising but too few trades to judge, `rejected` = the evidence says no,
`reference` = kept for comparison, `control` = the measuring stick.

All research presets target **TP2 with the stop moved to break-even at the TP1 distance**
(`AX_EXIT_TP2_BE`); `M15_B` uses the ATR trailing runner instead (`AX_EXIT_TRAIL_AFTER_TP1`,
2x ATR). No preset uses the TP1-only exit - it cannot pay a 0.47 spread.

## How to test (round 3 plan, in this order)

**Step 0 - is the `M5_A` edge real?** Two runs, same period as round 2, everything else untouched:

1. `M5_A_Breakout_Volume` with the tester spread at **0**. This measures how much of the edge the
   spread eats. Round 2 was PF 1.11 *with* the 47 point spread; if the zero-spread run is ~1.3-1.4,
   the edge is genuine and the cost model is doing its job. If both runs are equal, the edge comes
   from somewhere else than the breakout logic and needs a second look.
2. `M5_A_Breakout_Volume` on a **different period** (e.g. 2025.01.01-2025.12.31, or as much history
   as the broker gives). This is the out-of-sample test. A PF above 1.1 on a period it was not
   designed on is the minimum bar for demo. Below 1.0 it was curve-luck and we stop here.

**Step 1 - only if step 0 passes:** run `M15_C_NY_Expansion` on the same period and on 2025 to see
whether the session restricted version holds up (it needs at least 50+ trades before it means
anything), and compare against `M5_A`.

**Step 2 - after a demo month**, not before: micro-tuning of the candidate (`InpTP2Multiplier`,
`InpCooldownBars`, the ATR gate) - one change at a time, on the out-of-sample period.

Do not run the `rejected` presets again on real money. They are kept in the folder for the record.

## Account safety layer (new inputs, all adjustable)

| Input | Preset value | What it does |
|---|---|---|
| `InpUseSafetyLimits` | true | master switch of every guard below |
| `InpRiskPercentCap` | 1.0 | hard ceiling on the risk percent per trade |
| `InpMaxMarginPercent` | 5.0 | max % of equity used as margin for one trade |
| `InpMaxTradesPerDay` | 3 | entries per day, then stop |
| `InpMaxDailyLossPercent` | 3.0 | stop for the day after this loss of the day start equity |
| `InpMaxConsecutiveLosses` | 4 | stop for the day after N losing trades in a row |
| `InpEquityStopPercent` | 20.0 | close and halt trading until the EA is reloaded |
| `InpCloseOnEquityStop` | true | the position is closed when the circuit breaker fires |
| `InpMaxTradeLossPercent` | 2.0 | close a trade whose floating loss reaches 2% of the balance |
| `InpForceStopLoss` | true | re-attach the SL when the fill has none (or a farther one) |

The EA also prints, at startup, the broker's real contract value
(`1.0 price move per lot = X account currency`), the margin per lot and the risk percent in use -
plus a warning if a fixed sizing mode is selected. When a trade is taken, the journal line contains
the **real risk in account currency and as a % of the balance**, so a sizing error is visible
immediately instead of after the account is gone.

## Rules the generator enforces (no preset can break them)

1. Sizing must be `AX_SIZING_BROKER` and the risk must be **≤ 0.75%** per trade.
2. The safety layer must be on, with a margin cap ≤ 5%, a live spread cap, a daily loss cap, a
   trade count cap, a loss streak cap and an equity stop.
3. The ATR gate must match the timeframe: **≥ 2.0 USD on M5, ≥ 3.0 USD on M15**.
4. Cost gates on, 47 point spread assumed, `SL ≥ 2x spread`, `TP2 ≥ 3x spread`,
   `InpSkipTP1IfUneconomic=true`.
5. `AX_EXIT_TP1_ONLY` anywhere except the reference is rejected by the generator.
6. Fibonacci and structure may not carry more than 15 points of weight each if the preset is a
   research preset (the evidence for them is the weakest of all blocks).
7. At most 2 hard filters per family and 5 in total, the trend filter must stay above the chart
   timeframe, and stop-entry presets may not run the anti-whipsaw penalty.

## Regenerating the files

```bash
python3 generate_presets.py     # parses the EA inputs, validates every rule, writes the .set files
```

The script removes stale `.set` files that are no longer in `PRESETS`, so the folder always matches
the code in this folder.

## Notes and caveats

- These are **hypotheses with a cost model behind them, not validated edges**. The only proof is a
  clean backtest on your data with good history quality (99%) and a demo month afterwards.
- The spread gates assume 47 points. Set `InpFixedSpreadPoints=0` to let them use the live spread,
  or keep 47 and rely on `InpMaxSpreadPoints=60` as the live guard.
- Session presets use a fixed broker offset (`InpBrokerGMTOffsetHrs=3`); a fixed offset does not
  follow daylight saving time. Set `InpUseManualGMTOffset=false` to use `TimeGMT()`.
- No MetaTrader compiler exists in this repository environment: compile the EA once in MetaEditor
  (F7) and check the Experts log for the contract and sizing lines.
