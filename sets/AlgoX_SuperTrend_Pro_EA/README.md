# AlgoX SuperTrend Pro EA - preset files

Ready-made MT4 input presets for `src/AlgoX_SuperTrend_Pro_EA.mq4`.
They differ almost exclusively in the **filter configuration**, so the effect of every filter group can be
measured against the baseline.

## How to use

1. Copy the wanted `.set` file(s) into
   `<Terminal Data Folder>/MQL4/Presets`
   (in MetaTrader 4: `File -> Open Data Folder`, then `MQL4\Presets`).
2. Attach the EA to a chart, open its properties and switch to the **Inputs** tab.
3. Press **Load**, pick the preset file, then **OK**.
4. For the Strategy Tester: `Strategy Tester -> Expert properties -> Inputs -> Load`.

Every `.set` file contains all 96 inputs, so loading it fully overwrites the previous settings.

## The presets

| # | File | Filter group | Hard filters | Selectivity |
|---|---|---|---|---|
| 01 | `01_Pine_Baseline.set` | none (reference) | 0 | highest (all signals) |
| 02 | `02_Trend_Alignment.set` | direction agreement | 3 | low |
| 03 | `03_Momentum_Volume.set` | momentum + participation | 4 | low-medium |
| 04 | `04_Structure_Breakout.set` | structure + breakout entry | 3 | low |
| 05 | `05_Pullback_Value.set` | pullback entry + value | 2 | medium |
| 06 | `06_AntiChop_Quiet_Market.set` | anti-chop (score based) | 1 | medium |
| 07 | `07_High_Quality_Few_Trades.set` | everything confirmed | 4 | lowest |
| 08 | `08_Session_NewYork_Scalp.set` | session + spread | 0 | medium |
| 09 | `09_Aggressive_Max_Signals.set` | none (frequency upper bound) | 0 | highest |

Common base of every preset (so that only the filters differ):

- `InpSizingMode=AX_SIZING_PINE_FIXED` with `InpPineBalance=100`, `InpRiskPercent=1.5`, `InpPineLotValue=10`
  -> deterministic lots, comparable to the original indicator numbers.
  **Switch to `AX_SIZING_BROKER` (value 0) when trading a live account.**
- `InpEntryMode=AX_ENTRY_MARKET`, `InpSLAnchor=AX_ANCHOR_RECENTER`,
  `InpExitMode=AX_EXIT_SPLIT_BE`, `InpTP1Portion=0.5`, `InpMoveToBEAtTP1=true`.
- Different `InpMagicNumber` per preset (20260101 ... 20260109) so several presets can run side by side.

## Preset details

### 01 - Pine Baseline

Nothing is filtered: exactly the score engine, thresholds (85/55), cooldown (10 bars) and
`TP1` exit of the original indicator. Use it as the reference curve and to verify that the EA
reproduces the TradingView script.

Changed: `InpSLAnchor=AX_ANCHOR_REFERENCE`, `InpExitMode=AX_EXIT_TP1_ONLY`, `InpMoveToBEAtTP1=false`,
`InpKeepTP2OnOrder=false`.

### 02 - Trend alignment

Blocks any signal that fights the higher timeframe trend, the SuperTrend or the EMA market regime,
and suppresses a re-entry in the direction that was just traded.

Changed: `InpTrendFilterMode=AX_MODE_REQUIRE` (H1, EMA 50), `InpSTUse=AX_MODE_REQUIRE`,
`InpRegimeMode=AX_MODE_REQUIRE`, `InpStructMode=AX_STRUCT_FILTER`, `InpReEntryMode=AX_REENTRY_BLOCK_SAME_DIR`.

### 03 - Momentum and participation

The signal must be backed by momentum and by real market activity.

Changed: `InpMACDMode=AX_MODE_REQUIRE`, `InpRSIMode=AX_RSI_REQUIRE_LEVELS` (55/45),
`InpVolAvgMode=AX_MODE_REQUIRE` (tick volume above its 20-bar average),
`InpVolFilterMode=AX_MODE_REQUIRE` (relative volume above 1.2x), `InpUseSlopeFilter=true`, `InpSlopeMin=0.15`.

### 04 - Structure breakout

Trade only fresh breaks, and enter with a stop order beyond the signal candle
(`InpEntryPercent=90` puts the buy level just below the candle high and the sell level just below the
candle low), so the position opens only when the breakout is real. When the price already passed the
level at the next open, the signal is skipped instead of chased (`InpPendingFallbackMkt=false`).

Changed: `InpStructMode=AX_STRUCT_REQUIRE_FRESH`, `InpExtraFibMode=AX_FIBEXTRA_786`,
`InpRange200Mode=AX_MODE_REQUIRE`, `InpEntryMode=AX_ENTRY_STOP`, `InpEntryPercent=90`,
`InpPendingExpiryBars=2`, `InpPendingFallbackMkt=false`, `InpOneSignalPerMove=true`.

### 05 - Pullback entry at value

Buys the pullback instead of the breakout: a limit order at the 30% level of the signal candle,
valid for 3 bars, and the signal is dropped (not converted to a market order) when the level is invalid.
Price must also be beyond the 50% and the 78.6% Fibonacci levels and on the correct side of the VWAP.

Changed: `InpEntryMode=AX_ENTRY_LIMIT`, `InpPendingExpiryBars=3`, `InpPendingFallbackMkt=false`,
`InpExtraFibMode=AX_FIBEXTRA_BOTH`, `InpVWAPMode=AX_MODE_REQUIRE`, `InpRSIMode=AX_RSI_SCORE_LEVELS`,
`InpUseAntiWhipsaw=true`.

### 06 - Anti-chop / quiet market

Consolidation (Bollinger width below the 25th percentile of the last 100 bars) costs score, stretches the
cooldown and requires a steeper slope, while the trend and volume blocks only add score bonuses instead of
hard blocking.

Changed: `InpUseAntiWhipsaw=true`, `InpConsolThreshold=0.0` (automatic percentile),
`InpConsolMultiplier=0.85`, `InpConsolCDMultiplier=1.5`, `InpUseSlopeFilter=true`, `InpSlopeMin=0.2`,
`InpCooldownBars=15`, `InpOneSignalPerMove=true`, `InpTrendFilterMode=AX_MODE_BONUS`,
`InpSTUse=AX_MODE_SCORE`, `InpVolFilterMode=AX_MODE_SCORE`.

### 07 - High quality, few trades

The most selective preset: only scores at or above the strong threshold (85), aligned with the higher
timeframe trend and the structure bias, with strong relative volume, and only one trade per direction per day.

Changed: `InpStrongMode=AX_STRONG_ONLY`, `InpTrendFilterMode=AX_MODE_REQUIRE`,
`InpStructMode=AX_STRUCT_FILTER`, `InpVolFilterMode=AX_MODE_REQUIRE`,
`InpReEntryMode=AX_REENTRY_BLOCK_SAME_DAY`, `InpCooldownBars=12`.

### 08 - New York session scalp

Restricts trading to the New York session, caps the spread, shortens the cooldown and uses the aggressive
threshold with SuperTrend and volume score bonuses.

Changed: `InpUseSessionFilter=true`, `InpTradingSession=AX_SESSION_NEWYORK`,
`InpUseManualGMTOffset=true`, `InpBrokerGMTOffsetHrs=3`, `InpMaxSpreadPoints=60`,
`InpSensitivity=AX_SENS_AGGRESSIVE`, `InpCooldownBars=5`, `InpSTUse=AX_MODE_SCORE`,
`InpVolFilterMode=AX_MODE_SCORE`.

> Adjust `InpBrokerGMTOffsetHrs` to your broker (usually 2 or 3) and remember that a fixed offset does not
> follow daylight saving time. When trading live you can set `InpUseManualGMTOffset=false` to use `TimeGMT()`.

### 09 - Aggressive, maximum signals

The frequency upper bound: aggressive threshold (80/50), cooldown of 3 bars, no filters, and a trailing
stop after TP1 instead of a fixed TP2.

Changed: `InpSensitivity=AX_SENS_AGGRESSIVE`, `InpCooldownBars=3`, `InpOneSignalPerMove=false`,
`InpExitMode=AX_EXIT_TRAIL_AFTER_TP1`, `InpTrailMode=AX_TRAIL_BY_R`, `InpTrailDistR=0.5`,
`InpKeepTP2OnOrder=false`.

## Suggested workflow

1. `01` on the strategy tester (M1, XAUUSD, "Every tick") - confirm the baseline trade count and curve.
2. Then `09` - the maximum frequency for the same period; the two together bracket the possible range.
3. Test the filter groups one by one (`02`, `03`, `04`, `05`, `06`) against the baseline and keep the groups
   that improve the profit factor / reduce the drawdown rather than the ones that merely look good.
4. `07` as the "few, high quality trades" variant, `08` if only a part of the day is tradable.

## Notes and caveats

- The presets are **starting points, not optimised settings**: the filter thresholds (volume 1.2x,
  slope 0.15-0.2%, strong score 85, spread 60 points) are reasonable defaults, not universal truths.
- Everything else (SL/TP multipliers, ATR period, score weights) stays at the indicator defaults in every
  preset, so a filter comparison is not polluted by different money management.
- With `AX_SIZING_PINE_FIXED` the balance is a fixed 100 USD, which is what the original indicator simulates.
  On a real account use `AX_SIZING_BROKER` and a realistic risk percent.
- Entry presets `04` and `05` need a broker without a large `StopsLevel`, otherwise the pending order is
  rejected and (with `InpPendingFallbackMkt=false`) the signal is simply skipped.
- Regenerate the files after changing the EA inputs: `python3 generate_presets.py`
  (the script reads the `input` declarations straight from the `.mq4` source).
