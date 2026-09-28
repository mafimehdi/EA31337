# AlgoX SuperTrend Pro EA - combined filter presets

Ready-made MT4 input presets for `src/AlgoX_SuperTrend_Pro_EA.mq4`.
Each preset is a **combination of filters that belong together**: they measure different things,
support the same market hypothesis and none of them cancels the other ones out.

## How to use

1. Copy the `.set` file(s) into `<Terminal Data Folder>/MQL4/Presets`.
2. Attach the EA, open its properties, switch to the **Inputs** tab.
3. Press **Load**, choose the preset, then **OK**.
4. Strategy Tester: `Strategy Tester -> Expert properties -> Inputs -> Load`.

Each file contains all 96 inputs, so loading it fully replaces the previous settings
(including the magic number, which is unique per preset - several presets can run side by side).

## Prebuilt archives (download)

Two ready-to-download archives are kept in `archive/`:

- `AlgoX_SuperTrend_Pro_EA_complete.zip` - EA source, all 12 presets, this README, the generator
  script and the Persian guide.
- `AlgoX_Set_Files_Only.zip` - only the `.set` files, flat, ready to be copied into `MQL4/Presets`.

Download (branch `arena/01a0e88e-ea31337`):

- complete:
  `https://github.com/mafimehdi/EA31337/raw/arena/01a0e88e-ea31337/sets/AlgoX_SuperTrend_Pro_EA/archive/AlgoX_SuperTrend_Pro_EA_complete.zip`
- set files only:
  `https://github.com/mafimehdi/EA31337/raw/arena/01a0e88e-ea31337/sets/AlgoX_SuperTrend_Pro_EA/archive/AlgoX_Set_Files_Only.zip`

## Filter families

The filters of the EA are grouped by what they actually measure. This is the base of every
combination below: **different families reinforce each other, the same family repeated only adds
selectivity**.

| Family | Inputs | What it measures |
|---|---|---|
| Trend / direction | `InpTrendFilterMode` (HTF EMA), `InpSTUse` (SuperTrend),
`InpRegimeMode` (EMA 5/10/20), `InpStructMode` (BOS/CHoCH) | where the price is heading
on a higher scale |
| Momentum | `InpMACDMode`, `InpRSIMode` (55/45) | how strong the current push is |
| Participation | `InpVolAvgMode`, `InpVolFilterMode` (relative volume) | whether real volume is behind the move |
| Location / value | `InpVWAPMode`, `InpExtraFibMode` (50% / 78.6%), `InpRange200Mode` |
whether the entry price is a good place to enter |
| Market condition | `InpUseAntiWhipsaw`, `InpUseSlopeFilter` | whether the market is tradable at all (chop, flat) |
| Trading window | `InpUseSessionFilter`, `InpMaxSpreadPoints` | when trading is allowed |
| Signal quality gate | `InpStrongMode` | how high the score must be |
| Execution | `InpEntryMode`, `InpPendingExpiryBars`, `InpSLAnchor`, `InpExitMode`,
trailing, sizing | how the trade is placed and closed |

## Coherence rules (enforced by `generate_presets.py`)

1. **At most 2 hard filters per family.** A third trend filter does not add information, it only
   removes trades. The third one is kept as a score bonus (`AX_MODE_SCORE`).
2. **At most 5 hard filters in total**, and with `AX_STRONG_ONLY` at most 4 (plus the strong gate).
   Beyond that the preset stops producing trades at all.
3. **A breakout entry never runs with the anti-whipsaw filter.** Breakouts happen when volatility
   expands, the anti-whipsaw penalty plus the longer cooldown would suppress exactly that move.
4. **A pullback (limit) entry never runs with `AX_STRUCT_REQUIRE_FRESH`.** By the time the price
   pulls back to the entry level, the structure break is no longer fresh.
5. **A limit entry never has the market fallback enabled**, otherwise the pullback preset silently
   turns into a market-entry preset.
6. **One idea per preset**: either the trade follows a trend, or breaks out of a range, or buys
   value in a balance, or defends capital. Mixing two of those ideas produces the worst of both.
7. Hard filters should live in **different families** where possible, so every filter adds a new
   piece of information instead of repeating the previous one.

`generate_presets.py` refuses to write a preset that breaks these rules, so the presets in this
folder are guaranteed to be internally consistent.

## The presets

| # | File | Idea | Hard filters (family) | Expectation |
|---|---|---|---|---|
| 00 | `00_Pine_Baseline` | the indicator itself | none | reference curve, most trades |
| 01 | `01_Trend_Pullback_Confluence` | trend + pullback location | trend 2, location 1, condition 2 | medium |
| 01 | `01_Trend_Pullback_Confluence` | trend + pullback location | trend 2, location 1,
condition 2 | medium |
| 03 | `03_London_Trend_Session` | London trend continuation | trend 2, condition 1, window 2 | medium |
| 04 | `04_Breakout_Expansion` | breakout + expansion | trend 1, momentum 1, volume 1, location 2 | low |
| 05 | `05_NY_Breakout_Momentum` | New York breakout | momentum 1, volume 1, window 2 | low-medium |
| 06 | `06_Confluence_Max_Quality` | everything confirmed | quality 1, trend 2, momentum 1, volume 1 | lowest |
| 07 | `07_Defensive_Low_Risk` | capital protection | quality 1, condition 2, window 1 | low |
| 08 | `08_Value_VWAP_Balance` | value entries, no trend mandate | location 2 | medium |
| 09 | `09_Asia_Range_Value` | Asian range value | location 2, window 2 | medium |
| 10 | `10_Trend_Rider_Trailing` | trend rider with a runner | trend 2, condition 1 | medium |
| 11 | `11_AllWeather_Score_Based` | one score, no blockers | condition 1 | high (close to baseline) |

Common base of every preset, so that only the filter combination differs:
`InpSizingMode=AX_SIZING_PINE_FIXED`, `InpPineBalance=100`, `InpRiskPercent=1.5`,
`InpPineLotValue=10`, `InpEntryMode=AX_ENTRY_MARKET` (except 01, 08, 09 limit and 04, 05 stop),
`InpSLAnchor=AX_ANCHOR_RECENTER`, `InpExitMode=AX_EXIT_SPLIT_BE`, `InpTP1Portion=0.5`,
`InpMoveToBEAtTP1=true` (exceptions are named below).
**Switch `InpSizingMode` to `AX_SIZING_BROKER` (value 0) on a live account.**

## What each combination does

### 00 - Pine Baseline (reference)

No filter, original thresholds (85/55), cooldown 10, original reference SL/TP
(`InpSLAnchor=AX_ANCHOR_REFERENCE`) and the original exit (whole position at TP1). The curve every
other preset is compared against, and the check that the EA reproduces the TradingView indicator.

### 01 - Trend + pullback location

Trend family: higher timeframe EMA (H1, EMA 50) **required**, structure bias as a filter, the
SuperTrend only adds score (a third trend vote would just delete trades).
Location family: the VWAP is **required** and the entry waits for a pullback - a limit order at the
30% level of the signal candle, valid three bars, with no market fallback.
Condition family: consolidation penalty (score x0.85, cooldown x1.25) and a slope requirement of
0.12%.

### 02 - Trend + momentum + volume expansion

Two independent trend measurements are required (higher timeframe EMA + SuperTrend), the EMA
regime adds score instead of a third requirement. Momentum is confirmed by the MACD histogram
(required) while the 55/45 RSI levels and the slope stay on score. Participation: relative volume
above 1.2x is required. Re-entries in the direction that just traded are suppressed.

### 03 - London session trend continuation

Trading window: London only (UTC 09:01-16:00) with a 50 point spread cap - the session where trends
usually develop. Trend requirement is limited to the higher timeframe EMA and the SuperTrend, the
market condition is guarded by the slope filter, and MACD, 55/45 RSI levels, relative volume and
the SuperTrend bonus are all on score. That keeps the signal count usable *inside* the session.

### 04 - Breakout expansion

Trend family: a fresh BOS/CHoCH structure break is required (not a bias filter, the break must be
recent). Location: a close at the 200-bar extreme and beyond the 78.6% Fibonacci level. Momentum:
MACD agreement. Participation: relative volume above 1.2x. Execution: a **stop order just beyond
the signal candle extreme** (`InpEntryPercent=90`), valid two bars, no market fallback - when the
price already ran away the signal is skipped instead of chased. Anti-whipsaw and slope are off on
purpose (they would suppress the expansion), and only one signal per move is allowed.

### 05 - New York session breakout momentum

Same breakout idea adapted to the New York session (16:01-21:59 UTC, spread cap 60 points) with
softer gates: volume above its 20-bar average and MACD are hard, the 200-bar extremes, SuperTrend
and relative volume add score. Stop entry beyond the signal candle, no fallback.

### 06 - Maximum confluence

Quality gate: only scores at or above 85. Direction: higher timeframe trend required and the
structure bias must agree. Confirmation: MACD histogram and volume above its average are required;
the relative volume bonus, the EMA regime and the 55/45 RSI levels add score. One signal per move,
and the same direction is traded at most once per day. This is the deliberate "four hard filters
plus the strong gate" limit - going further stops trading.

### 07 - Defensive low risk

Quality gate: score >= 85 only. Condition: consolidation (Bollinger width below the 25th
percentile) penalises score by 0.8 and multiplies the cooldown by 1.5, the slope must be at least
0.2%. Window: spread capped at 40 points. Execution: cooldown 20 bars, one signal per move, **risk
halved to 0.75%** and the position is closed completely at TP1 - no runner and no open risk in
quiet markets.

### 08 - Value entries (VWAP + Fibonacci)

Two-way preset with no trend mandate: the location family carries it. A close beyond both the 50%
and the 78.6% Fibonacci levels and on the right side of the VWAP are required, the entry is a
**limit** order at the 30% level of the signal candle (three bars, no fallback). The higher
timeframe trend only adds a bonus, volume adds score, and the anti-whipsaw penalty is off because
this combo accepts ranging conditions.

### 09 - Asian session range value

Trading window: Asia (00:00-09:00 and 22:00-24:00 UTC, spread cap 50 points). Location: VWAP and
both extra Fibonacci levels are required, the entry is a limit order valid four bars (no fallback).
The 55/45 RSI levels and volume add score, there is no trend requirement, and the whole position is
closed at TP1 - a range target, not a runner.

### 10 - Trend rider with a trailing runner

Direction: higher timeframe trend required and the structure bias must agree, with the SuperTrend,
MACD, regime, volume and slope on score. Exit: part at TP1, stop to break-even and then an **ATR
trailing stop** (2x ATR) for the rest, so the runner is not cut by a fixed target. Strong signals
(score >= 85) get 1.5x the normal risk, because a runner needs room to work.

### 11 - All-weather score based

One unified score with no hard blockers: the higher timeframe trend adds a bonus, the SuperTrend,
MACD, 55/45 RSI levels, relative volume, 200-bar extremes and the market regime add score
(`InpExtraWeight=10`), and only the consolidation penalty (score x0.9, cooldown x1.2) protects
against choppy conditions. The trade count stays close to the baseline, the quality is filtered by
the score itself. Use it when you dislike filter stacking but still want the extra information.

## Combinations to avoid (and why)

These are the traps the coherence rules exist for:

- **Stop entry + anti-whipsaw**: the breakout happens exactly when volatility expands; the penalty
  and the longer cooldown suppress that move.
- **Limit entry + `AX_STRUCT_REQUIRE_FRESH`**: waiting for a pullback while demanding a fresh break.
- **Limit entry + market fallback**: the pullback preset quietly becomes a market preset, with a
  worse entry than the signal candle.
- **Trend required + regime required + MACD required + RSI required**: four votes for the same
  question (direction), each one deletes trades without adding information.
- **`AX_STRONG_ONLY` + five hard filters**: multiplicative selectivity, practically no trades left.
- **`AX_EXIT_TP2_ONLY` with the weak-ADX regime**: TP2 is 1.5x TP1 while the R:R of that regime is
  only 0.65 - the target is unrealistic, use the split exit or a runner instead.
- **Anti-whipsaw in a range/value preset**: the penalty fights the very conditions the preset trades.
- **Fixed lot together with a risk percent preset**: inconsistent risk between presets, the
  comparison between them becomes meaningless.

## Suggested workflow

1. `00` first: confirm that the EA reproduces the indicator (trade count, curve shape).
2. `11` next: the "soft" combination - it shows how much the score engine alone already filters.
3. Then the directional combos in this order: `01`, `02`, `03`, `10` and the breakout ones
   `04`, `05`. Compare each with `00` on the **same period and symbol**.
4. `06` and `07` are the low-frequency variants; `08` and `09` the value variants for ranging
   sessions.
5. Keep the combinations that improve the profit factor or the drawdown - not the ones with the
   prettiest equity curve on a single week.

## Which timeframe?

Everything in this EA is bar based and the SL/TP distance is built from ATR multiples, so the mechanics
work on any timeframe and scale automatically. The timeframe choice changes three things: **how much of
the risk the spread eats**, **how noisy ADX and the structure detection are**, and **how many signals
you get**.

| Goal | Symbol | Chart TF | Trend filter TF | Presets |
|---|---|---|---|---|
| Original behaviour (gold scalping) | XAUUSD | M1 | M15 | 00, 04, 05, 09 |
| Balance - recommended starting point | XAUUSD, indices, FX | M5 | M30 or H1 | 00, 01, 02, 11 |
| Fewer, steadier trades | same | M15 | H1 | 01, 03, 06, 10 |
| Session based | same | M5-M15 | H1 | 03, 05, 09 |
| Semi-swing | same | H1 | H4 | 07, 10 |

- **M1**: on gold ATR(5) is roughly 0.5-1.5 USD, so the risk distance is 1-2.5 USD while the spread is
  0.2-0.4 USD - that is **10-30% of the risk paid as cost**. ADX(14) is noisy on M1 and the 10/10 pivot
  only sees a 20 minute structure. Use it only with a raw-spread (ECN) account and fast execution.
- **M5 (recommended)**: the same structure, ATR two to four times larger, spread share down to 5-10%,
  and ADX plus the structure detection become meaningful.
- **M15/M30**: structure breaks and the 233-bar Fibonacci levels (about 2.5 days on M15) turn into real
  support/resistance; the quality presets (06, 07) and the runner preset (10) behave best here.
- **H1 and above**: signal count drops sharply. The cooldown counts bars (10 H1 bars = 10 hours), so
  lower it to 2-3, move the trend filter to H4/D1 and expect overnight trades.

Always remember:

1. `InpTrendTF` must be **higher than the chart timeframe**. The default H1 fits M1-M30 charts; on an H1
   chart use H4 or D1.
2. The cooldown is in bars: M1 -> 10 (default), M5 -> 5-10, M15 -> 3-5, H1 -> 2-3.
3. The session presets (03 London, 05 New York, 09 Asia) are meant for M1-M15; on higher timeframes there
   are too few bars inside a session and the filter simply stops trading.
4. In the MT4 strategy tester always use **Every tick** with good M1 history - the EA manages the position
   on every tick, so `Open prices only` gives wrong results.
5. Every timeframe needs its own tuning: the thresholds (relative volume 1.2x, slope 0.12-0.2%, strong
   score 85, spread caps) mean different things on different timeframes. Do not transfer M5 settings to M1.
6. Running one preset on several timeframes is fine (each preset has its own magic number), but never run
   the same preset twice on the same symbol and timeframe.

## Notes and caveats

- The presets are **starting points, not optimised settings**. The thresholds (volume 1.2x, slope
  0.12-0.2%, strong score 85, spread 40-60 points) are reasonable defaults, not universal truths;
  symbols and brokers differ. Tune them per instrument.
- The session presets use a fixed broker offset (`InpBrokerGMTOffsetHrs=3`, usually 2 or 3).
  A fixed offset does not follow daylight saving time; when trading live you can set
  `InpUseManualGMTOffset=false` to use `TimeGMT()` instead.
- Presets `01`, `08`, `09` (limit) and `04`, `05` (stop) need a broker with a small `StopsLevel`,
  otherwise the pending order is rejected and - with the fallback disabled - the signal is skipped.
- Every preset keeps the indicator's SL/TP logic (ADX driven multipliers, ATR based distance) and
  the score engine untouched, so a comparison between the presets is a comparison of filters only.
- Regenerate the files after changing the EA inputs: `python3 generate_presets.py`
  (it parses the `input` declarations from the `.mq4` source and validates the coherence rules).
