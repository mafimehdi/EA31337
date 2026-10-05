# XAUUSD AMD + GoldFusion v3.40 — TradingView Pine Port

A **zero-repaint Pine Script™ v6 indicator** for XAUUSD M15 that ports the MQL4 expert advisor
`XAUUSD_AMD_Fusion_v340.mq4` (HYBRID_04 spine + GoldFusion v6.3 modules) to TradingView.
It opens in **technical-analysis mode**: indicators and zones are on, while strategy
signals and trade simulation are off to keep chart use visual-first and lighter. The
signal engine, trade outcomes and statistics are available as an opt-in setting.

* File: [`XAUUSD_AMD_Fusion_v340.pine`](XAUUSD_AMD_Fusion_v340.pine)
* Type: `indicator()` (overlay) — **not** a `strategy()`. Its optional trade simulation
  runs inside the indicator when enabled; it does not send broker orders.
* Language: Pine Script™ v6.

---

## 1. Quick start

1. Open **XAUUSD (GOLD)** on a broker feed such as `OANDA:XAUUSD`, `FX:XAUUSD`,
   `TVC:GOLD` or your CFD broker's symbol.
2. Set the chart timeframe to **15 minutes** (the EA is an M15 system — a warning banner
   appears if you are on another timeframe).
3. TradingView → **Pine Editor** → paste the whole file → **Save** → **Add to chart**.
4. Open the indicator settings and set **`Broker Winter GMT Offset`** to your broker's
   offset (`2` for EET / GMT+2 winter + GMT+3 summer, which is what most MT4/MT5 gold
   brokers use, `3` for GMT+3 fixed feeds, `0` for a UTC feed).
   All killzones (16:00–18:15 NY_AM, 20:00–20:45 NY_PM, …) are expressed in **broker
   time**, exactly like the MQL source, so this offset is the single most important input.
5. The default **Technical analysis** layout shows the main chart layers: liquidity levels,
   sweep zones (latest 100), FVGs (latest 100 by default), killzone shading, EMA 20/50/200,
   UT-Bot and BB50. FVGs can be restricted to sweep-tracking hours in settings.
6. To add strategy-generated entries/exits and simulated P&L, enable **Enable strategy
   signals + trade simulation** in `5 · Chart Visualisation`. It is OFF by default; when
   enabled, the last 30 accepted labels are retained (configurable to 100), with explicit
   TP/SL/locked-SL and other outcomes. Statistics tables are then available as well.
7. Choose **Full analysis** to add the decision dashboard, trade-stage artwork and optional
   footprint. With the signal engine ON, it also shows the large ledger and performance
   breakdown. In `2 · Micro-Killzone Windows`, enable **24-hour trading (ignore time windows)**
   when the strategy engine is enabled to bypass session windows/caps and the time-of-day blocks.

### راهنمای سریع (فارسی)

* نمودار **XAUUSD** را روی تایم‌فریم **۱۵ دقیقه** باز کنید و اسکریپت را در Pine Editor
  کپی/Save و سپس Add to chart کنید.
* در تنظیمات، **Broker Winter GMT Offset** را مطابق بروکر خود (معمولاً `2`) وارد کنید؛
  تمام پنجره‌های زمانی (کیل‌زون‌ها) بر اساس **زمان بروکر** محاسبه می‌شوند.
* حالت پیش‌فرض **Technical analysis** است: سطوح نقدینگی، Sweep، FVG، Killzone، EMAهای
  ۲۰/۵۰/۲۰۰، UT-Bot و BB50 را نشان می‌دهد؛ بخش سیگنال‌دهی و شبیه‌سازی معامله خاموش است.
  نواحی Sweep تا ۱۰۰ مورد و FVG به‌صورت پیش‌فرض در همهٔ ساعات (تا ۱۰۰ مورد آخر) ترسیم می‌شوند.
* اگر لیبل ورود/خروج و آمار TP/SL و P&L را هم می‌خواهید، گزینهٔ **Enable strategy signals +
  trade simulation** را در تنظیمات روشن کنید. این بخش پیش‌فرض خاموش است؛ پس از روشن‌کردن،
  ۳۰ تا ۱۰۰ سیگنال پذیرفته‌شدهٔ آخر با نتیجهٔ مشخص روی نمودار می‌مانند.
* `Full analysis` داشبورد تصمیم، جزئیات معامله و فوت‌پرینت اختیاری را اضافه می‌کند؛ جدول‌های
  بزرگ آمار هم وقتی موتور سیگنال روشن باشد نمایش داده می‌شوند. برای اجرای موتور در تمام ساعات،
  گزینهٔ **24-hour trading (ignore time windows)** را روشن کنید؛
  خاموش بودن آن، پنجره‌ها و محدودیت‌های زمانی فعلی را نگه می‌دارد.
* برای دیدن فوت‌پرینت تقریبی، ابتدا `Chart Layout` را روی **Full analysis** بگذارید و سپس گزینهٔ **Show Footprint Columns** را روشن کنید.
* اسکریپت **ریپینت ندارد**: همه‌چیز فقط روی کندل بسته‌شده محاسبه و با
  `barstate.isconfirmed` قفل می‌شود.

---

## 2. Chart-first mode, optional signals, and 24H mode

* `Chart Layout = Technical analysis` is the default. It shows the technical layers without
  the large statistics panels. Liquidity, sweep, FVG, killzone, EMA, UT-Bot and BB50 layers
  each have a visibility input; the latest 100 FVG zones are retained by default.
* `Enable strategy signals + trade simulation` is OFF by default, so entry detection and
  simulated trade management/ledger are skipped. The lightweight sweep tracking needed to
  draw zones stays active. Turn the option on to get persistent setup labels, active Entry/SL/TP
  levels, closed outcomes (`TP HIT`, `SL HIT`, `LOCKED SL HIT`,
  `SHIELD EXIT`, `SESSION CLOSE`, or no-fill statuses), plus simulated R and dollar P&L.
  Retain 30–100 accepted signal labels. The statistics and performance tables are available
  when this engine is enabled; they represent simulation, not broker orders.
* `Full analysis` adds the decision dashboard, trade-stage artwork and optional footprint.
  The large ledger and performance breakdown appear only when the signal engine is enabled;
  the dashboard states clearly when it is disabled.
* `24-hour trading (ignore time windows)` makes sweep tracking all-day and, when the
  strategy engine is enabled, bypasses session windows/caps, the NY_PM-only Engine-4 gate,
  NY whip/late-buy time blocks and NY end-of-session auto-closing. Cooldown, one-position,
  strategy filters and risk checks remain active when signals are enabled.

---

## 3. What was ported (1:1 with the MQL source)

| MQL4 component | Pine implementation |
|---|---|
| `GetNewYorkTime()` / `GetBrokerDecimalHour()` / `GetTradingDayID()` | `f_nyHour()`, `f_brokerHour()`, `f_dayKey()` — broker winter GMT + auto-DST (Apr–Oct), NY via `America/New_York` (automatic US DST), trading day rolls at 18:00 NY |
| `UpdateSessionLiquidityLevels()` | Asian (NY 18:00–02:00), London (NY 02:00–07:00), Midnight Open, PDH/PDL, day high/low, 32-bar cold-start fallback |
| Sweep state machine (6 SSL + 6 BSL pools, `Min/Max_Sweep_ATR`, `Max_Bars_For_MSS`) | identical pools (Asian, PDH/PDL, ext20, ind10, swing4, London), same ATR-gated penetration and same expiry logic |
| **Engine 1** AMD sweep + displacement + MSS | identical (`body ≥ 0.25·ATR` or previous-bar displacement, MSS via swing4 / FVG / `close > high[1]`) |
| **Engine 2** Layer-3 internal swing sweep (Turtle Soup) | identical (wick or body ≥ 0.30·ATR, reclaim of the 3-bar extreme) |
| **Engine 3** NY Silver Bullet FVG continuation | identical, off by default (`eng3On`, `allowSbSell`) |
| **Engine 4** GoldFusion SP2L | `f_sp2l()` — 2-bar spike ≥ 1.2×ATR21, body ≥ 45%, FVG gap, 2-leg pullback that holds the spike origin, breakout close; single-use spike timestamp; NY_PM-only by default |
| UT-Bot filter (`KeyValue=1.0`, `ATR=21`) + 120-bar warm-up replay | recursive `utStop` over the whole dataset — the cold-start bug the EA had to patch simply cannot occur |
| BB50 basis + slope filter | `f_bbAllow()` |
| Filter scope (Off / Engine4 / Long-only / All) | `f_gfAllow()` with the same 4-way logic |
| Pre-Step1 reversal-quorum shield (PB vote + opposite sweep + UT + BB50, ≥3/4) | `f_pbVote()` + shield phase; only touches un-locked, underwater positions |
| Micro-killzones, NYSE whip bars (16:45/17:45), late-buy block (18:15+, 20:35+), per-window caps | identical, with all window bounds exposed as inputs |
| Sweep-tracking hours gate | identical (London / PRE_NY / 15:15–20:45 extensions) |
| Cooldown + post-loss cooldown | identical (`cooldownBars`, `postLossCooldown`) |
| 15% shallow-FVG limit entry, 1-bar expiry, invalidation at the manipulation extreme, market fallback | identical two-phase execution (signal on bar *t*, order sent at the open of bar *t+1*) |
| Structural SL (wick + 0.22·ATR + spread, clamped to 0.27 %–0.482 % of price) and 1.95R TP | identical |
| 3-stage Step-Lock (+0.92R→+0.60R & 50 % partial, +1.30R→+1.15R, +1.62R→+1.50R) | identical, with the same `if/else-if` highest-stage-wins resolution |
| Step compounding (+0.01 lot / $165, 3 % risk floor, lot normalisation) | `f_calcLots()` / `f_normLots()` with a running simulated balance |
| `Close_At_NY_End` | identical (NY 16:00–18:00 or broker ≥ 22:50) |
| Presets (`M15_ULTRA_TUNED_PF384`, `M15_NY_PLUS_LONDON`, custom) | `M15 Preset` input, same overrides |

### One-bar index shift

The EA runs *at the open of bar N* and reads *Bar[1]*. This port runs *at the close of
bar N* and reads *Bar[0]*. Every MQL `Bar[k]` therefore becomes Pine `Bar[k-1]`, and the
order it sends is executed on the **next** bar's open/high/low — the same information set,
the same fills, no lookahead.

---

## 4. Zero-repaint guarantees

* nothing runs per tick: the whole state machine lives inside `if barstate.isconfirmed and bar_index >= 250`; **no** `request.security()`, **no** `lookahead`,
  **no** negative `offset`, **no** `security()`-based higher-timeframe data.
* The entire state machine runs inside `if barstate.isconfirmed`, so a signal, marker,
  level or statistic is written **only** when a bar has closed and can never be redrawn.
* Session levels, sweeps, counters, balance and the ledger live in `var` state updated
  once per closed bar.
* Drawings use `xloc.bar_time` and are only created/extended on confirmed bars.
* The footprint panel is re-rendered on the last bar only (it is a *view* of the last N
  closed bars, not a historical claim).
* Session shading is pure clock arithmetic (bar open time → broker/NY hour) and cannot
  depend on future prices.

Because it is an indicator, TradingView's built-in "bar magnifier"/deep backtesting of
`strategy()` is not available; intra-bar fill order inside a single bar is therefore an
assumption you control with **`Intra-Bar Fill Assumption`**:

| Mode | Meaning |
|---|---|
| `Pessimistic (SL first)` *(default)* | if one bar contains both a trigger and a stop, the stop is assumed to be hit first — never overstates the backtest |
| `Optimistic (trigger first)` | assumes the profitable path first |
| `No same-bar exit` | a position can never open and close on the same bar |

---

## 5. Statistics tables

These tables require **Enable strategy signals + trade simulation** to be ON; with it OFF,
the script stays in chart-only technical-analysis mode and skips simulated trades.

**SIMULATION LEDGER** — trades, win rate, wins, losses, TP hits, SL hits, Step-Lock exits,
shield exits, session-end exits, expired limits, partials taken, average R, net profit,
return %, gross profit/loss, profit factor, expectancy, average win/loss in $ and R,
payoff, best/worst R, max drawdown ($ and %), max consecutive wins/losses, balance,
equity with floating P&L, BUY vs SELL split, and the live position/pending/context block.

**PERFORMANCE BREAKDOWN** — trades, win rate and net $ per engine and per killzone window,
which is how the EA's own forensic report (e.g. "Engine 4 loses in NY_AM, wins 80 % in
NY_PM") can be reproduced on TradingView data.

Money is calculated as `price move × lots × contract size` (default 100 oz per lot for
XAUUSD) with an optional round-turn commission, on a compounding simulated balance that
starts at **`Simulated Starting Balance`** ($500 by default, matching the EA's base).

---

## 6. Footprint (optional module)

TradingView publishes **one aggregate (tick) volume per bar** — there is no bid/ask tape —
so a true footprint is impossible. The module therefore builds an honest approximation:

1. Each bar's volume is redistributed over `Price Rows per Bar` buckets by walking the
   bar's OHLC travel path (`open → far extreme → near extreme → close`) and weighting
   every bucket by how much of that path lies inside it.
2. Buy/sell split per bucket = Close-Location-Value baseline (`0.5 + 0.35·CLV`) plus a
   directional tilt across the bar (`Delta Tilt Across the Bar`).
3. **POC** = the highest-volume bucket (yellow border, `●`), **diagonal imbalances** use
   the classic bid/ask diagonal comparison with `Diagonal Imbalance Ratio` (default 3×,
   marked `▲`/`▼` and a white border).
4. Column delta of the last bar and cumulative delta (CVD) over the footprint window are
   reported in the LIVE DECISION ENGINE panel.

It is order-flow *colouring* to help read absorption at the sweep levels — it is **not**
exchange data, and it is off by default.

---

## 7. Known differences from MT4

| Area | Difference |
|---|---|
| Bid/Ask | TradingView has no Bid/Ask stream. One simulated spread (`Simulated Spread`, in points = `syminfo.mintick`) is added to long entries / subtracted from short stops and used as the cost of market and partial fills. Short-side trailing triggers are evaluated on chart price instead of Ask (≤ one spread of difference). |
| Spread rejection | The EA's live `Max_Spread_Points` rejection cannot be reproduced (no real spread); the simulated spread is used for cost only. |
| Broker `MODE_STOPLEVEL` | replaced by `2 × simulated spread + 1 tick` in the minimum-SL clamp. |
| Free-margin loop | `AccountFreeMarginCheck()` lot de-gearing is not simulated (no margin model); lot size follows the risk/step-compounding formula. |
| Partials | MT4 reports a 50 % partial as a separate deal; here one *position* = one trade and the partial is folded into that trade's P&L (a counter shows how many partials were taken). |
| Pending expiry | the limit is deleted at the **open** of the bar after its last valid bar (the EA deletes it on the second tick of that bar) — a sub-bar difference. |
| Volume | CFD tick volume, not futures volume. |
| Swap | not modelled; use the commission input for round-turn costs. |

Because of the data differences, absolute dollar figures will not match an MT4 backtest
tick-for-tick; the **structure of the decisions** (which bar, which engine, which window,
which stop/target/stage) is identical.

---

## 8. Input groups

| Group | Contents |
|---|---|
| `0 · Preset, Broker & Session Time` | M15 preset, broker winter GMT + auto-DST, NY timezone, timeframe warning |
| `1 · Risk, Compounding & 3-Stage Step-Lock` | step compounding, $ per 0.01 lot, risk %, 1.95R target, the three trigger/lock stages, partial size, SL buffer and % clamps |
| `1b · Simulation Accounting` | starting balance, contract size, lot step/min/max, commission, simulated spread, intra-bar fill assumption |
| `2 · Micro-Killzone Windows` | 24H override, entry mode, pullback ratio, pending expiry, whip/late-buy skips, per-window caps, London session, cooldowns, session-end close, and every window boundary in broker hours |
| `3 · M15 Core Engines` | strict EMA slope, min/max sweep ATR, MSS bars, displacement body, engine 1/2/3 switches |
| `4 · GoldFusion v6.3 Modules` | Engine 4 SP2L parameters, NY_PM-only switch, PRE_NY window + cap, UT-Bot, BB50, filter scope, reversal shield |
| `5 · Chart Visualisation` | technical/full layout, optional signal engine, 30–100 retained signal outcomes, indicator/zone visibility, FVG time scope/history, active trade ladder and result artwork |
| `6 · Approximated Footprint` | enable, bars back, rows, imbalance ratio, delta tilt, min volume, cell text |
| `7 · Statistics Tables & Live Dashboard` | table/dashboard switches, positions, text size, colours |

---

## 9. Alerts

`alertcondition()` entries are provided for: setup detected, order filled, Step-1 partial,
position closed, reversal-shield exit, and UT-Bot flips (long/short). Strategy alerts require
**Enable strategy signals + trade simulation** to be ON; UT-Bot flip alerts remain independent.
Create the alert with **"Once per bar close"** so it stays in sync with the non-repaint logic.

---

## 10. Disclaimer

This is a research/educational port of an MQL4 expert advisor to Pine Script™. It
**simulates** the strategy on chart data for visualisation and statistics; it does not
place orders, and its results depend on the feed, the broker offset, the simulated spread
and the intra-bar assumption. Past performance — simulated or real — is not indicative of
future results.
