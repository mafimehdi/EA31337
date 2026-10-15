# SMC XAUUSD M15: TradingView and MT4

This implementation is a **mechanical, repeatable definition** of an SMC-style setup. It does not claim to identify complete institutional order flow or real order-book liquidity.

## Files

| File | Purpose |
| --- | --- |
| `src/SMC_XAUUSD_M15_Strategy.pine` | Pine Script v6 TradingView strategy, with sweep/MSS/FVG visualization and alerts. |
| `src/SMC_XAUUSD_M15_EA.mq4` | Standalone MT4 expert advisor that executes the same core logic. |

## Entry model

For a long trade, each event below must occur in sequence. Short logic is the exact inverse.

1. The most recently closed H1 and H4 candles must satisfy `Close > EMA50 > EMA200`.
2. An M15 candle must sweep the lowest low of the preceding 12 M15 candles by at least `0.10 ATR`, then close bullishly back above that level. This is the mechanical sell-side liquidity-sweep definition.
3. Within eight M15 bars, price must close above the latest confirmed swing high. A swing requires five bars on each side to confirm. This is the market-structure shift (MSS).
4. Within three bars after MSS, a three-candle bullish FVG at least `0.20 ATR` wide must form. Only the **first** post-MSS FVG is the POI.
5. Within 12 bars, price must return to the FVG consequent encroachment (CE, the midpoint), avoid a full fill, and close the retest bar bullishly.
6. On that retest bar, price must be above the M15 EMA200, the ATR-scaled Range Filter must be bullish, and Choppiness must be below 58.

When `Require order-block overlap` is enabled, the FVG must overlap the last opposite-colour candle before the MSS. This is considerably more selective and is disabled by default.

## Trade management

- Default risk: `1%` of equity per trade.
- Stop loss: beyond the swept extreme, plus `0.10 ATR` buffer.
- Stops tighter than `0.50 ATR` are expanded to that distance; stops wider than `3.00 ATR` are rejected.
- Take profit: `2R`.
- Breakeven: stop moves to breakeven after `1R`.
- Only one EA position per symbol and magic number may be open at once.
- The session filter is disabled by default to match the all-market-hours selection. If enabled, it uses **broker server time**.

## TradingView setup

1. Paste `SMC_XAUUSD_M15_Strategy.pine` into TradingView Pine Editor and add it to the chart.
2. Use a standard-candle **XAUUSD M15** chart. Do not use Heikin-Ashi bars.
3. For alerts, choose **Order fills** or **Any alert() function call** in Create Alert, and use **Once Per Bar Close**.
4. Defaults match the selected profile: H1/H4 bias, M15 EMA200, `1.30 ATR` Range Filter and `58` Choppiness limit.
5. Verify the TradingView symbol's contract multiplier, commission and slippage before interpreting backtest position sizing. Pine quantity uses the feed's `syminfo.pointvalue`.

## MT4 setup

1. Copy `SMC_XAUUSD_M15_EA.mq4` to `MQL4/Experts/` and compile it in MetaEditor.
2. Attach the EA to an M15 chart and enable AutoTrading.
3. If the broker uses a different symbol name, edit only `InpSymbol`; examples include `XAUUSDm` and `GOLD`.
4. Before any live use, confirm in the Journal that `MODE_TICKVALUE` and `MODE_TICKSIZE` are valid. The EA uses them to calculate the 1% risk lot size.
5. `InpMaxSpreadPrice=0.80` is in **gold price units**, not broker points. Adjust it to the actual spread of the broker.

## Expected TradingView and MT4 differences

The signal logic is intentionally matched, but execution prices cannot be identical:

- Pine backtests with `process_orders_on_close=true`.
- The EA submits its market order on the first tick of the next M15 bar, at the broker's real Bid/Ask.
- Spread, slippage, feed differences and broker stop-distance rules naturally change fills and results.

Use Pine to validate the model, and use MT4 Strategy Tester plus a demo account to validate execution in the exact broker environment.

## Deliberate limitations

- There is no automatic news filter. MT4 has no dependable native economic-calendar feed. Stop or restrict the EA manually around NFP, CPI, FOMC and rate decisions.
- The FVG and sweep rules are algorithmic proxies. They are not a direct measurement of real order-book liquidity or institutional flow.
- The code does not guarantee profitability or future performance. Test it in Strategy Tester, then demo trade, before considering any live use.
