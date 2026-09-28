# AlgoX SuperTrend Pro EA - research presets (XAUUSD M1, 0.47 USD spread)

Ready-made MT4 presets for `src/AlgoX_SuperTrend_Pro_EA.mq4`, rebuilt around one target:

> **Symbol XAUUSD, chart timeframe M1, fixed spread 47 points (0.47 USD).**
> Which filter combination survives those costs?

The old "one idea per preset" set is replaced by **4 research presets + 1 reference baseline**.
The full evidence (22 indicator blocks, per-block research, synergy map, cost model and the
derivation of every threshold) is in `docs/AlgoX_M1_Filter_Research_fa.md`.

## How to use

1. Copy the `.set` file(s) into `<Terminal Data Folder>/MQL4/Presets`.
2. Attach the EA, open its properties, switch to the **Inputs** tab.
3. Press **Load**, choose the preset, then **OK**.
4. Strategy Tester: `Strategy Tester -> Expert properties -> Inputs -> Load`.

Each file contains every input of the EA, so loading it fully replaces the previous settings
(the magic number is unique per preset, so several presets can run side by side).

## Prebuilt archives (download)

Two ready-to-download archives are kept in `archive/`:

- `AlgoX_SuperTrend_Pro_EA_complete.zip` - EA source, all presets, this README, the generator
  script and the Persian guide.
- `AlgoX_Set_Files_Only.zip` - only the `.set` files, flat, ready to be copied into `MQL4/Presets`.

Download (branch `arena/01a0e88e-ea31337`):

- complete:
  `https://github.com/mafimehdi/EA31337/raw/arena/01a0e88e-ea31337/sets/AlgoX_SuperTrend_Pro_EA/archive/AlgoX_SuperTrend_Pro_EA_complete.zip`
- set files only:
  `https://github.com/mafimehdi/EA31337/raw/arena/01a0e88e-ea31337/sets/AlgoX_SuperTrend_Pro_EA/archive/AlgoX_Set_Files_Only.zip`

## Why the presets look like this (short version of the research)

With a 0.47 USD spread on gold M1 the arithmetic is unforgiving:

| Regime (ADX) | R:R of the original indicator | Zero-cost break-even win rate | Break-even win rate with 0.47 spread |
|---|---|---|---|
| weak (<20) | 0.65 | 60.6% | above 70% - not tradable |
| medium (20-40) | 0.75 | 57.1% | above 70% - not tradable |
| strong (>=40) | 1.50 | 40.0% | ~48-55% depending on the ATR |

Exit choice for a strong regime (spread included in the target):

| Exit | TP size | Break-even win rate |
|---|---|---|
| TP1 only | 0.8 x ATR | 54.7% |
| TP1 only | 1.0 x ATR | 51.8% |
| **TP2 (1.5 x TP1)** | **1.2 x ATR** | **42.1%** |
| **TP2** | **1.5 x ATR** | **39.8%** |

Two conclusions drive everything:

1. **The small TP1 cannot pay the spread.** The trade must target TP2 / the runner, and the stop
   must still be wide enough not to be noise (ATR based stops below 1 x ATR are hit by noise in
   more than 65% of the cases within three bars).
2. **The score engine had its weight in the wrong place.** 55% of the score sat on Fibonacci
   (25) and the pivot structure break (30) - the two blocks with the weakest evidence - while the
   blocks with the strongest published evidence (MACD, volume) were off by default. The presets
   therefore use rebalanced weights: fib 10, structure 10, EMA 20, RSI 20, MACD 20, volume 20.

Cost gates added to the EA for exactly this purpose (all inputs, all adjustable):
`InpUseCostFilters`, `InpFixedSpreadPoints=47`, `InpMinATR=1.0`, `InpMinADXRegime`,
`InpMinSLSpreadMult=2.0`, `InpMinTargetSpreadMult=3.0`, `InpSkipTP1IfUneconomic`.

## The presets

| # | File | Idea | Hard filters | Weights |
|---|---|---|---|---|
| 00 | `00_Pine_Baseline` | the indicator itself, no cost gates | none | Pine (25/20/25/30) |
| C1 | `C1_Trend_Momentum` | trend + momentum + volume | M15 trend, MACD | research (10/20/20/10/20/20) |
| C2 | `C2_Expansion_Breakout` | expansion breakout | fresh structure, 200-bar extreme, RVOL | research + MACD |
| C3 | `C3_CostGates_Only` | control: old score engine + cost gates | none (cost gates only) | Pine |
| C4 | `C4_Session_Expansion` | New York session expansion | M15 trend, MACD, NY session | research |

**The comparison is the product.** 00 versus C3 measures how much the geometry alone is worth;
C3 versus C1 measures how much the documented filter combination adds on top of that geometry.

### Common base of every preset

Identical in all files, so that a difference between two presets is a difference of filters:

- Sizing: `AX_SIZING_PINE_FIXED`, balance 100, risk 1.5%, lot value 10 USD per 1.0 move.
  **Switch to `AX_SIZING_BROKER` (value 0) or `AX_SIZING_RISK_PERCENT` on a live account.**
- Entry: `AX_ENTRY_MARKET` (same entry method everywhere -> the comparison is fair).
- `InpSLAnchor=AX_ANCHOR_RECENTER`, `InpKeepTP2OnOrder=true`.
- Cooldown 10 bars (5-12 in individual presets, always stated in the file header).
- Cost gates as listed above; score weights as listed above (except where a row says otherwise).

### 00 - Pine Baseline (reference, do not trade it)

Original score weights, no MACD, no volume scoring, original reference SL/TP, the original TP1
exit, `InpUseCostFilters=false`. It exists to answer one question: *what does the raw indicator
do under real costs?* The cost model says the answer is "lose slowly"; that number is the
starting point of the whole comparison.

### C1 - Trend + momentum (the documented combination)

The MACD alone has a win rate below 50% in the published tests; MACD combined with RSI reaches
0.84-0.86, and MACD combined with an ADX regime filter beats both the EMA crossover and buy and
hold in the Bitcoin study. C1 encodes exactly that:

- **Hard**: higher timeframe trend (M15 EMA 50) must agree, MACD histogram must agree.
- **Score**: 55/45 RSI levels, market regime (EMA 5/10/20), volume average.
- **Cost gates**: ATR(5) >= 1.0 USD, ADX in the strong regime, SL >= 2x spread, TP2 >= 3x spread.
- **Exit**: whole position at TP2, stop moved to break-even at the TP1 distance
  (`AX_EXIT_TP2_BE`), which is the only exit geometry the cost model leaves positive.

### C2 - Expansion breakout

Breakouts need expansion, so this preset requires it instead of penalising it (anti-whipsaw and
slope stay off):

- **Hard**: fresh BOS/CHoCH structure break, close at the 200-bar extreme, relative volume >= 1.2x.
- **Score**: MACD, RSI, EMA, EMA regime, the rebalanced weights.
- **Exit**: TP2 + break-even trigger, cooldown 5 bars because the structure break itself is the
  timing device.

### C3 - Cost gates only (the control)

The old score engine (fib 25 / structure 30 / EMA 25 / RSI 20), no extra indicator block, but
with the cost gates and the TP2 + break-even exit. This is the cleanest experiment in the set:
*what happens if we change nothing about the filters and only stop paying for trades that cannot
pay for themselves?*

### C4 - Session expansion (New York)

C1 restricted to the New York session (16:01-21:59 UTC, broker offset 3h) with a stricter ATR
gate (1.2 USD) and a 5 bar cooldown. Rationale: the spread is a fixed cost, so it should only be
paid in the window where the range actually expands - the session filter is a cost filter in
disguise, not a "trade only in London" superstition.

## Coherence rules (enforced by `generate_presets.py`)

1. **At most 2 hard filters per family** and **at most 5 hard filters in total.**
2. A breakout preset never runs the anti-whipsaw penalty or the slope filter.
3. A limit entry never runs `AX_STRUCT_REQUIRE_FRESH` and never has the market fallback enabled.
4. One idea per preset - trend, breakout, cost control or session - never two.
5. Every preset with the cost gates on must assume the 47 point spread, `InpMinATR >= 1.0`,
   `InpMinSLSpreadMult >= 2.0`, `InpMinTargetSpreadMult >= 3.0` and
   `InpSkipTP1IfUneconomic=true`.
6. The reference preset must keep the Pine weights, the TP1-only exit and the cost gates off.
7. `AX_EXIT_TP1_ONLY` is rejected outside the reference preset, because the cost model shows it
   cannot pay a 0.47 USD spread.
8. Research presets may not keep more than 15 points of weight on Fibonacci or on structure.

`generate_presets.py` refuses to write a preset that breaks a rule, so everything in this folder
is internally consistent. Run `python3 generate_presets.py` after changing EA inputs.

## How to compare the presets (the part that actually decides)

1. Same symbol, same period, **Every tick** with real M1 history, spread fixed at 47 points.
2. Run 00 first, then C3, then C1, C2, C4 - in that order, so every step has a clean control.
3. Judge with: trade count, profit factor, break-even win rate (as in the tables above), max
   drawdown, and the **average win / average loss** ratio. Ignore the shape of the curve on one week.
4. If a preset produces fewer than ~30 trades on the test period, the result is noise - extend
   the period before drawing conclusions.
5. Swap one thing at a time afterwards: the entry mode (`STOP` for C2), the exit multiplier
   `InpTP2Multiplier` (1.5 -> 2.0), or the ATR gate. The presets are starting points, not a
   finished optimisation.

## What is deliberately NOT in the presets

- Fibonacci levels and VWAP as **standalone** rules. The Fibonacci study (three markets) found the
  bounce probability on Fib zones statistically indistinguishable from non-Fib zones, and the
  VWAP evidence is institutional/industry level only. Both stay in the EA as adjustable inputs and
  are usable as score components, but no preset requires them.
- The fixed spread cap `InpMaxSpreadPoints` is left at 0 in the research presets, because the cost
  gates work with the fixed 47 point assumption instead. Set a cap on a live account if the broker
  widens the spread.
- Anything based on visual or display logic - out of scope by request.

## Notes and caveats

- The presets are **starting points, not optimised settings**, and the cost model uses
  equilibrium arithmetic (break-even win rates), not a backtest on your broker's history. The
  strategy tester on your own data is the final judge.
- `InpFixedSpreadPoints=47` is the *assumed* spread for the gates. Live orders still execute at the
  broker spread; set `InpFixedSpreadPoints=0` to let the gates use the live spread instead.
- `AX_EXIT_TP2_BE` moves the stop to the break-even price (`InpBEPlusPoints` above the entry) once
  the TP1 distance is reached, so the whole position runs to TP2. If you prefer a partial close,
  use `AX_EXIT_SPLIT_BE` - but note that its TP1 leg is exactly what the cost model calls
  unprofitable.
- Presets use a fixed broker offset (`InpBrokerGMTOffsetHrs=3`) for the session filter; a fixed
  offset does not follow daylight saving time. Set `InpUseManualGMTOffset=false` to use `TimeGMT()`.
- No MetaTrader compiler exists in the repository environment, so the EA is shipped as source:
  compile it once in MetaEditor (F7) and check the Experts log.
