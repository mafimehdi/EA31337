# XAUUSD AMD + Smart Money Swing Map

A chart-first Pine Script v6 **indicator** for XAUUSD M15, focused on confirmed Swing structure, AMD session levels/manipulation, and Smart Money liquidity/FVG zones. The strategy signal engine, simulated trades, TP/SL management, statistics tables, and trade alerts have been removed.

Use [`XAUUSD_AMD_Fusion_v340.ascii.pine`](XAUUSD_AMD_Fusion_v340.ascii.pine) in TradingView's Pine Editor. The readable Unicode source is [`XAUUSD_AMD_Fusion_v340.pine`](XAUUSD_AMD_Fusion_v340.pine); the ASCII-safe companion uses UP/DOWN in place of arrow glyphs but keeps the same indicator logic.

## Quick start

1. Open **XAUUSD** on **15-minute** candles.
2. Copy the complete ASCII file into TradingView → **Pine Editor**, then Save and Add to chart.
3. Set **Broker Winter GMT Offset** to your feed's winter offset (commonly `2`). Disable **Broker Auto-DST** for fixed-offset or UTC feeds.
4. Start with the defaults. They show session/liquidity levels, confirmed Swing structure, BSL/SSL sweeps, and recent FVG zones. EMA, UT-Bot, and BB50 are available but off by default.
5. To track sweeps at every hour, enable **24-hour sweep tracking**. Otherwise adjust the broker-time start/end inputs.

## What the chart shows

- **Swing structure:** confirmed swing highs/lows (`SWH` / `SWL`), plus **BOS** and **CHoCH** labels. A pivot is confirmed only after the chosen number of bars has closed to its right; the label is drawn at the pivot after confirmation. BOS/CHoCH are structure annotations, not entry signals.
- **AMD:** the Asian range is the accumulation reference; Asian/London highs and lows, Midnight Open, and previous-day high/low remain visible. A reclaimed sweep is marked as **BSL/SSL SWEEP · AMD MANIPULATION**. If a matching BOS/CHoCH follows within the configured bars, it is tagged **AMD DISTRIBUTION**.
- **Smart Money zones:** liquidity sweeps use Asian/London, previous-day, confirmed Swing, and rolling 20-bar highs/lows. Three-candle bullish/bearish Fair Value Gaps are drawn as bounded boxes only after the third candle closes. By default it keeps the most recent 80 FVG zones and 60 sweep zones; the oldest are removed when each history limit is exceeded.
- **Sessions:** optional Asia, London, New York AM and PM background shading.
- **Optional overlays:** EMA 20/50/200, UT-Bot ATR trail, and BB50 basis. These are off by default so the core map stays readable; enable only the ones useful to your analysis.

## Main settings

- **Time & Sessions:** broker offset/DST, broker-time sweep window, or 24-hour sweep tracking; session shading.
- **AMD, Smart Money & Swing Structure:** session levels, previous-day levels, sweep zones, FVG visibility/history/length.
- **Swing & Market Structure:** pivot strength, number of retained marks, sweep depth in ATR, and the time allowed for an AMD distribution confirmation.
- **Optional Indicators:** EMA ribbon, UT-Bot, and BB50 visibility and periods.

## Repaint behavior and scope

- Session levels and all persistent boxes/labels update only on confirmed bars.
- Swing pivots use right-side confirmation bars; BOS/CHoCH and sweep annotations use closed-bar prices.
- There is no `request.security()`, lookahead, negative plot offset, strategy order, or hidden entry/exit engine.
- This is a visual analysis aid. It does **not** issue trade entries, exits, TP/SL levels, orders, or performance statistics. Traders must decide and manage trades themselves.

The session-time calculations use broker offset inputs and New York's selected timezone. Check the offset against your data feed before relying on session levels. This script is for research/education and is not financial advice.
