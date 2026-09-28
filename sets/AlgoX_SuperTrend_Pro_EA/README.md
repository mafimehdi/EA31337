# AlgoX SuperTrend Pro EA - M5 / M15 research presets (after the first live round)

Ready-made MT4 presets for `src/AlgoX_SuperTrend_Pro_EA.mq4`, rebuilt after four presets wiped
real accounts. **Read the first section before running anything.**

## What happened in the first round (the honest version)

Four presets (C1-C4) were built around a **0.47 USD spread on XAUUSD M1**. They were tested on
Alpari-Standard3, 500 USD, 2026.01.01-2026.09.25, spread 47, Every tick:

| Preset | Trades | Net | PF | Win % | Avg win | Avg loss | Break-even win % needed | Gap |
|---|---|---|---|---|---|---|---|---|
| C1 Trend-Momentum | 157 | -473.27 | 0.60 | 31.2 | 14.60 | -11.01 | 42.99 | **-11.78** |
| C2 Expansion Breakout | 528 | -347.32 | 0.87 | 38.3 | 11.85 | -8.41 | 41.51 | **-3.25** |
| C3 Cost-Gates Only | 256 | -462.94 | 0.64 | 34.0 | 9.48 | -7.62 | 44.56 | **-10.58** |
| C4 Session Expansion | 235 | -461.13 | 0.64 | 33.6 | 10.18 | -8.11 | 44.34 | **-10.72** |

Three independent causes, none of them "the indicator is bad":

1. **The cost.** On M1 gold the 0.47 spread is 28-50% of the ATR based risk distance. Every preset
   needed a 41.5-44.6% win rate to break even and delivered 31-38%. Adding the spread back to the
   results turns them roughly break-even to positive - the raw signal has a small edge, the spread
   eats all of it.
2. **A 10x sizing error (the account killer).** The presets used `PINE_FIXED` sizing, which assumes
   the indicator's manual lot value (10 USD per 1.0 move per lot = a 10 oz contract). The broker
   trades **100 oz** per lot, so the intended 1.50 USD risk per trade was really ~15 USD, i.e.
   ~3.2% of a 500 USD account **per trade** - and four presets running side by side multiplied it.
   The average loss in the reports (-8 to -11 USD) is exactly that number.
3. **No account level safety.** The EA had no daily loss cap, no trade count cap, no margin cap and
   no circuit breaker. The only guard was "free margin > 0", which fires when it is already too late.

## What is different in this set

| | First round | This set |
|---|---|---|
| Chart timeframe | M1 | **M5 and M15** |
| Spread share of risk | 28-50% | **~13% (M5), ~9% (M15)** |
| Sizing | PINE_FIXED (10 oz assumption) | **AX_SIZING_BROKER, 0.5% of real equity** |
| Margin guard | none | **max 5% of equity per trade** |
| Daily loss cap | none | **3% of the day start equity, then stop** |
| Trade count cap | none | **3 entries per day** |
| Loss streak cap | none | **4 consecutive losses, then stop for the day** |
| Circuit breaker | none | **-20% equity: close and halt until reload** |
| Live spread cap | off | **60 points** |
| Parallel presets per account | up to 4 | **1 - enforced in the README and the generator** |

## The presets

| File | Timeframe | Idea | Hard filters | ATR gate |
|---|---|---|---|---|
| `00_Pine_Baseline` | M5/M15 (runs on any) | the raw signal, no cost gates - the control | none | off |
| `M15_A_Breakout_Volume` | M15 | expansion breakout + volume (the best of round 1) | structure, RVOL, 200-bar | 3.0 USD |
| `M15_B_Trend_Runner` | M15 | trend + momentum with an ATR trailing runner | H1 trend, MACD | 3.0 USD |
| `M15_C_NY_Expansion` | M15 | A + New York session only | structure, RVOL, 200-bar, NY | 3.5 USD |
| `M5_A_Breakout_Volume` | M5 | the same breakout, faster | structure, RVOL, 200-bar | 2.0 USD |
| `M5_B_Trend_Momentum` | M5 | trend (M30) + MACD | M30 trend, MACD | 2.0 USD |
| `M5_C_NY_Expansion` | M5 | M5_A in the New York session | structure, RVOL, 200-bar, NY | 2.5 USD |

All research presets target **TP2 with the stop moved to break-even at the TP1 distance**
(`AX_EXIT_TP2_BE`); `M15_B` uses the ATR trailing runner instead (`AX_EXIT_TRAIL_AFTER_TP1`,
2x ATR). No preset uses the TP1-only exit - it cannot pay a 0.47 spread.

## How to test (in this order, one at a time)

**Step 0 - the diagnostic that decides everything.** Run `00_Pine_Baseline` twice on M15 and on M5,
same period, same symbol:

- once with the tester spread at **47** (the real cost),
- once with the tester spread at **0** (the raw signal).

If the spread-0 run has PF > 1.2 and the spread-47 run does not, the signal exists and the cost is
the problem - the M5/M15 presets below are the right path. If the spread-0 run is also below PF 1.0,
**no filter combination will save it on this symbol** and we change the signal (or the symbol),
not the timeframe.

**Step 1 - the candidates.** Run them one by one, never two on the same account:

1. `M15_A_Breakout_Volume` - the best hypothesis of round 1, now with ~9% cost share.
2. `M15_B_Trend_Runner` - the trend variant with the runner exit.
3. `M5_A_Breakout_Volume` - double the trades, ~13% cost share.
4. `M15_C_NY_Expansion` / `M5_C_NY_Expansion` - the session limited versions.

Acceptance criteria before any real money: **PF > 1.2, at least 100 trades, and a drawdown you can
survive on the smallest account you own.** Run it in the Strategy Tester and on a **demo** account
for at least a month afterwards.

**Step 2 - the tester settings that make the numbers comparable.** Symbol XAUUSD, period M15 or M5,
model **Every tick**, and download the M1 history first: the first reports show a
**modelling quality of 25%**, which means the tester was filling gaps in the tick data - the
absolute numbers of that run are not trustworthy. In Alpari: `Tools -> History Center -> XAUUSD ->
download M1`, then rerun. Spread: 47 for the comparison, 0 only for the diagnostic.

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
