#!/usr/bin/env python3
"""
Quantitative Backtest & Parameter Optimization for Combined:
AMD (ICT Power of 3) + Layer 3 Liquidity Strategy on Gold (XAUUSD)
3-Phase State Machine Implementation (matching MQL4 EA logic)
Dataset: 5 Years of 5-Minute & 15-Minute XAUUSD Historical Data (2020-2025)
"""

import json
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

DATA_PATH = "/tmp/XAUUSD_5m_5Yea.csv"


def load_and_prepare_data():
    print("Loading 5-year XAUUSD M5 dataset (2020-2025)...")
    df = pd.read_csv(DATA_PATH)
    df["dt_utc"] = pd.to_datetime(
        df["Date"].astype(str) + " " + df["Time"],
        format="%Y%m%d %H:%M:%S",
        utc=True,
    )
    df["dt_ny"] = df["dt_utc"].dt.tz_convert("America/New_York")
    df = df.sort_values("dt_ny").reset_index(drop=True)

    # Forex trading day starts at 18:00 NY time
    df["trading_day"] = (df["dt_ny"] + pd.Timedelta(hours=6)).dt.date
    df["ny_hour"] = df["dt_ny"].dt.hour + df["dt_ny"].dt.minute / 60.0
    return df


def resample_tf(df_m5, rule="15min"):
    df_r = (
        df_m5.set_index("dt_ny")
        .resample(rule)
        .agg(
            {
                "Open": "first",
                "High": "max",
                "Low": "min",
                "Close": "last",
                "Volume": "sum",
            }
        )
        .dropna()
        .reset_index()
    )
    df_r["trading_day"] = (df_r["dt_ny"] + pd.Timedelta(hours=6)).dt.date
    df_r["ny_hour"] = df_r["dt_ny"].dt.hour + df_r["dt_ny"].dt.minute / 60.0
    return df_r


def add_indicators(df):
    high = df["High"].values
    low = df["Low"].values
    close = df["Close"].values
    open_ = df["Open"].values

    prev_close = np.roll(close, 1)
    prev_close[0] = close[0]
    tr = np.maximum(
        high - low,
        np.maximum(np.abs(high - prev_close), np.abs(low - prev_close)),
    )
    df["ATR"] = pd.Series(tr).rolling(14, min_periods=1).mean().values
    df["EMA50"] = pd.Series(close).ewm(span=50, adjust=False).mean().values
    df["EMA200"] = pd.Series(close).ewm(span=200, adjust=False).mean().values
    df["Body"] = np.abs(close - open_)

    # 3-Candle Fair Value Gap (FVG)
    high_2 = np.roll(high, 2)
    low_2 = np.roll(low, 2)
    close_1 = np.roll(close, 1)
    open_1 = np.roll(open_, 1)
    df["bull_fvg"] = (low > high_2) & (close_1 > open_1)
    df["bear_fvg"] = (high < low_2) & (close_1 < open_1)

    # Internal Swing High / Low (5-bar lookback for MSS / CHoCH confirmation)
    df["swing_high_5"] = pd.Series(high).shift(1).rolling(5, min_periods=2).max().values
    df["swing_low_5"] = pd.Series(low).shift(1).rolling(5, min_periods=2).min().values

    # External / Engineered Liquidity Pool (prior 20 bars high/low before current window)
    df["ext_high_20"] = pd.Series(high).shift(3).rolling(20, min_periods=8).max().values
    df["ext_low_20"] = pd.Series(low).shift(3).rolling(20, min_periods=8).min().values

    return df


def build_daily_session_table(df):
    asian_mask = (df["ny_hour"] >= 19.0) | (df["ny_hour"] < 2.0)
    asian = (
        df[asian_mask]
        .groupby("trading_day")
        .agg(ah=("High", "max"), al=("Low", "min"))
    )

    midnight_df = df[df["ny_hour"] >= 0.0].groupby("trading_day").agg(midnight_open=("Open", "first"))

    lon_pre_ny = (
        df[(df["ny_hour"] >= 2.0) & (df["ny_hour"] < 7.0)]
        .groupby("trading_day")
        .agg(lh=("High", "max"), ll=("Low", "min"))
    )

    daily_stats = (
        df.groupby("trading_day")
        .agg(d_high=("High", "max"), d_low=("Low", "min"), d_open=("Open", "first"), d_close=("Close", "last"))
    )
    daily_stats["d_range"] = daily_stats["d_high"] - daily_stats["d_low"]
    daily_stats["d_atr"] = daily_stats["d_range"].rolling(14, min_periods=3).mean().shift(1)
    daily_stats["d_ema20"] = daily_stats["d_close"].ewm(span=20, adjust=False).mean().shift(1)
    daily_stats["prev_d_close"] = daily_stats["d_close"].shift(1)
    daily_stats["pdh"] = daily_stats["d_high"].shift(1)
    daily_stats["pdl"] = daily_stats["d_low"].shift(1)

    sessions = daily_stats.join([asian, midnight_df, lon_pre_ny])
    return sessions


def simulate_state_machine(
    df,
    sessions,
    killzone_mode="BOTH",        # "LONDON", "NY", "BOTH"
    use_golden_windows=True,     # Filter out mid-London chop (03:15-06:30) & 08:30 NY news spike (08:00-08:45)
    min_sweep_atr=0.12,          # Min penetration beyond liquidity pool
    max_sweep_atr=1.80,          # Max penetration before sweep is invalidated as breakout
    max_bars_mss=10,             # Max bars after sweep to form MSS + FVG
    disp_body_atr=0.40,          # Displacement candle body >= X * ATR
    require_fvg=True,            # Require FVG formation on displacement leg
    require_midnight_open=True,  # ICT PO3 Discount/Premium relative to 00:00 NY Open
    htf_bias_mode="STRICT",      # "STRICT", "EMA200", "NONE"
    entry_type="FVG_LIMIT",      # "FVG_LIMIT" or "MSS_MARKET"
    sl_buffer_atr=0.25,          # Stop-loss ATR buffer behind Manipulation wick
    rr_target=2.5,               # Take-profit Risk:Reward ratio
    use_be_at_1r=True,           # Partial close 50% at 1R + move SL to Break-Even
    spread_cost=0.20,            # $0.20 (2.0 pips on XAUUSD)
):
    df_merged = df.merge(
        sessions[["d_atr", "d_ema20", "prev_d_close", "pdh", "pdl", "ah", "al", "midnight_open", "lh", "ll"]],
        left_on="trading_day",
        right_index=True,
        how="left",
    )

    high = df_merged["High"].values
    low = df_merged["Low"].values
    close = df_merged["Close"].values
    open_ = df_merged["Open"].values
    atr = df_merged["ATR"].values
    ema50 = df_merged["EMA50"].values
    ema200 = df_merged["EMA200"].values
    body = df_merged["Body"].values
    ny_hour = df_merged["ny_hour"].values
    t_day = df_merged["trading_day"].values
    dt_ny_str = df_merged["dt_ny"].astype(str).values

    ah = df_merged["ah"].values
    al = df_merged["al"].values
    lh = df_merged["lh"].values
    ll = df_merged["ll"].values
    pdh = df_merged["pdh"].values
    pdl = df_merged["pdl"].values
    midnight_open = df_merged["midnight_open"].values
    d_atr = df_merged["d_atr"].values
    d_ema20 = df_merged["d_ema20"].values
    prev_d_close = df_merged["prev_d_close"].values

    bull_fvg = df_merged["bull_fvg"].values
    bear_fvg = df_merged["bear_fvg"].values
    swing_high_5 = df_merged["swing_high_5"].values
    swing_low_5 = df_merged["swing_low_5"].values
    ext_high_20 = df_merged["ext_high_20"].values
    ext_low_20 = df_merged["ext_low_20"].values

    trades = []
    n = len(df_merged)
    i = 250

    cur_day = None
    lon_traded = False
    ny_traded = False

    bull_sweep_active = False
    bull_sweep_bar = -1
    bull_swept_level = 0.0
    bull_manip_low = 1e9

    bear_sweep_active = False
    bear_sweep_bar = -1
    bear_swept_level = 0.0
    bear_manip_high = -1e9

    while i < n - 60:
        day = t_day[i]
        hr = ny_hour[i]

        if day != cur_day:
            cur_day = day
            lon_traded = False
            ny_traded = False
            bull_sweep_active = False
            bear_sweep_active = False

        if np.isnan(ah[i]) or np.isnan(al[i]) or np.isnan(d_atr[i]) or d_atr[i] <= 0:
            i += 1
            continue

        asian_range = ah[i] - al[i]
        if asian_range > 0.95 * d_atr[i] or asian_range < 0.05 * d_atr[i]:
            i += 1
            continue

        in_london = (hr >= 2.0) and (hr <= 5.5)
        in_ny = (hr >= 7.0) and (hr <= 11.0)

        active_session = None
        if in_london and killzone_mode in ("LONDON", "BOTH") and not lon_traded:
            active_session = "LONDON"
            ssl_pools = [al[i], pdl[i], ext_low_20[i]]
            bsl_pools = [ah[i], pdh[i], ext_high_20[i]]
        elif in_ny and killzone_mode in ("NY", "BOTH") and not ny_traded:
            active_session = "NY"
            ssl_pools = [al[i], ll[i], pdl[i], ext_low_20[i]]
            bsl_pools = [ah[i], lh[i], pdh[i], ext_high_20[i]]
        else:
            bull_sweep_active = False
            bear_sweep_active = False
            i += 1
            continue

        sweep_min = min_sweep_atr * atr[i]
        sweep_max = max_sweep_atr * atr[i]

        # 1. Track Bullish Manipulation Sweep
        if not bull_sweep_active:
            for pool in ssl_pools:
                if not np.isnan(pool) and (low[i] <= pool - sweep_min) and (pool - low[i] <= sweep_max):
                    bull_sweep_active = True
                    bull_sweep_bar = i
                    bull_swept_level = pool
                    bull_manip_low = low[i]
                    break
        else:
            bull_manip_low = min(bull_manip_low, low[i])
            if (i - bull_sweep_bar > max_bars_mss) or (bull_swept_level - bull_manip_low > sweep_max):
                bull_sweep_active = False

        # 2. Track Bearish Manipulation Sweep
        if not bear_sweep_active:
            for pool in bsl_pools:
                if not np.isnan(pool) and (high[i] >= pool + sweep_min) and (high[i] - pool <= sweep_max):
                    bear_sweep_active = True
                    bear_sweep_bar = i
                    bear_swept_level = pool
                    bear_manip_high = high[i]
                    break
        else:
            bear_manip_high = max(bear_manip_high, high[i])
            if (i - bear_sweep_bar > max_bars_mss) or (bear_manip_high - bear_swept_level > sweep_max):
                bear_sweep_active = False

        # HTF Bias & ICT Midnight Open Filter
        if htf_bias_mode == "STRICT":
            bull_bias = (ema50[i] > ema200[i]) and (prev_d_close[i] > d_ema20[i])
            bear_bias = (ema50[i] < ema200[i]) and (prev_d_close[i] < d_ema20[i])
        elif htf_bias_mode == "EMA200":
            bull_bias = (close[i] > ema200[i]) and (ema50[i] >= ema200[i] * 0.999)
            bear_bias = (close[i] < ema200[i]) and (ema50[i] <= ema200[i] * 1.001)
        else:
            bull_bias = True
            bear_bias = True

        if require_midnight_open and not np.isnan(midnight_open[i]):
            bull_po3 = bull_manip_low < midnight_open[i]
            bear_po3 = bear_manip_high > midnight_open[i]
        else:
            bull_po3 = True
            bear_po3 = True

        signal_dir = 0
        if bull_sweep_active and bull_bias and bull_po3 and close[i] > bull_swept_level and close[i] > open_[i]:
            has_disp = (body[i] >= disp_body_atr * atr[i]) or (body[i - 1] >= disp_body_atr * atr[i - 1] and close[i - 1] > open_[i - 1])
            has_fvg = (bull_fvg[i] or bull_fvg[i - 1]) if require_fvg else True
            has_mss = close[i] >= swing_high_5[i] - 0.15 * atr[i]
            if has_disp and has_fvg and has_mss:
                signal_dir = 1
        elif bear_sweep_active and bear_bias and bear_po3 and close[i] < bear_swept_level and close[i] < open_[i]:
            has_disp = (body[i] >= disp_body_atr * atr[i]) or (body[i - 1] >= disp_body_atr * atr[i - 1] and close[i - 1] < open_[i - 1])
            has_fvg = (bear_fvg[i] or bear_fvg[i - 1]) if require_fvg else True
            has_mss = close[i] <= swing_low_5[i] + 0.15 * atr[i]
            if has_disp and has_fvg and has_mss:
                signal_dir = -1

        if signal_dir != 0:
            manip_extreme = bull_manip_low if signal_dir == 1 else bear_manip_high
            entry_idx = i

            if entry_type == "FVG_LIMIT":
                leg_size = abs(close[i] - manip_extreme)
                target_entry = close[i] - signal_dir * (0.35 * leg_size)
                filled = False
                for k in range(i + 1, min(i + 9, n - 30)):
                    if signal_dir == 1:
                        if low[k] <= manip_extreme:
                            break
                        if low[k] <= target_entry:
                            entry_idx = k
                            entry_price = target_entry + spread_cost
                            filled = True
                            break
                    else:
                        if high[k] >= manip_extreme:
                            break
                        if high[k] >= target_entry:
                            entry_idx = k
                            entry_price = target_entry - spread_cost
                            filled = True
                            break
                if not filled:
                    bull_sweep_active = False
                    bear_sweep_active = False
                    i += 1
                    continue
            else:
                entry_price = close[i] + (spread_cost if signal_dir == 1 else -spread_cost)

            # Check Golden Window filter at entry bar (avoids 03:15-06:30 mid-London chop and 08:00-08:45 US macro news whipsaw)
            entry_hr = ny_hour[entry_idx]
            if use_golden_windows:
                in_gold_win = (
                    (2.0 <= entry_hr <= 3.25)
                    or (6.5 <= entry_hr <= 8.0)
                    or (8.75 <= entry_hr <= 11.5)
                )
                if not in_gold_win:
                    bull_sweep_active = False
                    bear_sweep_active = False
                    i += 1
                    continue

            if signal_dir == 1:
                sl_price = manip_extreme - sl_buffer_atr * atr[i]
                risk = entry_price - sl_price
            else:
                sl_price = manip_extreme + sl_buffer_atr * atr[i]
                risk = sl_price - entry_price

            if risk <= spread_cost * 2.5 or risk > 0.65 * d_atr[i]:
                bull_sweep_active = False
                bear_sweep_active = False
                i += 1
                continue

            tp_price = entry_price + signal_dir * (rr_target * risk)
            be_trigger = entry_price + signal_dir * (1.0 * risk)

            if active_session == "LONDON":
                lon_traded = True
            else:
                ny_traded = True
            bull_sweep_active = False
            bear_sweep_active = False

            outcome_r = 0.0
            be_active = False
            exit_idx = entry_idx + 1

            for j in range(entry_idx + 1, min(entry_idx + 140, n)):
                if t_day[j] != day or ny_hour[j] >= 16.0:
                    exit_price = close[j]
                    raw_r = signal_dir * (exit_price - entry_price) / risk
                    outcome_r = (0.5 * 1.0 + 0.5 * max(raw_r, 0.0)) if be_active else raw_r
                    exit_idx = j
                    break

                if signal_dir == 1:
                    if low[j] <= (entry_price if be_active else sl_price):
                        outcome_r = 0.5 if be_active else -1.0
                        exit_idx = j
                        break
                    if use_be_at_1r and not be_active and high[j] >= be_trigger:
                        be_active = True
                    if high[j] >= tp_price:
                        outcome_r = (0.5 * 1.0 + 0.5 * rr_target) if use_be_at_1r else rr_target
                        exit_idx = j
                        break
                else:
                    if high[j] >= (entry_price if be_active else sl_price):
                        outcome_r = 0.5 if be_active else -1.0
                        exit_idx = j
                        break
                    if use_be_at_1r and not be_active and low[j] <= be_trigger:
                        be_active = True
                    if low[j] <= tp_price:
                        outcome_r = (0.5 * 1.0 + 0.5 * rr_target) if use_be_at_1r else rr_target
                        exit_idx = j
                        break

            trades.append(
                {
                    "dt": str(dt_ny_str[entry_idx]),
                    "session": active_session,
                    "dir": "BUY" if signal_dir == 1 else "SELL",
                    "entry": round(float(entry_price), 2),
                    "sl": round(float(sl_price), 2),
                    "tp": round(float(tp_price), 2),
                    "r_multiple": round(float(outcome_r), 3),
                }
            )
            i = max(i + 1, exit_idx)
        else:
            i += 1

    return trades


def evaluate_trades(trades, risk_pct=1.0):
    if not trades:
        return {
            "total_trades": 0,
            "win_rate": 0.0,
            "profit_factor": 0.0,
            "total_r": 0.0,
            "expectancy_r": 0.0,
            "max_dd_r": 0.0,
            "final_equity": 10000.0,
            "max_dd_pct": 0.0,
        }
    r_arr = np.array([t["r_multiple"] for t in trades])
    wins = r_arr[r_arr > 0]
    losses = r_arr[r_arr < 0]
    win_rate = len(wins) / len(r_arr) * 100.0
    gross_profit = wins.sum() if len(wins) else 0.0
    gross_loss = abs(losses.sum()) if len(losses) else 1e-9
    pf = gross_profit / gross_loss

    cum_r = np.cumsum(r_arr)
    peak_r = np.maximum.accumulate(np.insert(cum_r, 0, 0.0))[1:]
    dd_r = peak_r - cum_r
    max_dd_r = float(np.max(dd_r)) if len(dd_r) else 0.0

    eq = [10000.0]
    for r in r_arr:
        eq.append(eq[-1] * (1.0 + (risk_pct / 100.0) * r))
    eq = np.array(eq)
    peak_eq = np.maximum.accumulate(eq)
    max_dd_pct = float(np.max((peak_eq - eq) / peak_eq) * 100.0)

    return {
        "total_trades": len(trades),
        "win_rate": round(float(win_rate), 2),
        "profit_factor": round(float(pf), 2),
        "total_r": round(float(r_arr.sum()), 2),
        "expectancy_r": round(float(r_arr.mean()), 3),
        "max_dd_r": round(max_dd_r, 2),
        "final_equity": round(float(eq[-1]), 2),
        "max_dd_pct": round(max_dd_pct, 2),
    }


def main():
    df_m5 = load_and_prepare_data()
    df_m15 = resample_tf(df_m5, "15min")

    df_m5 = add_indicators(df_m5)
    df_m15 = add_indicators(df_m15)

    sessions_m5 = build_daily_session_table(df_m5)
    sessions_m15 = build_daily_session_table(df_m15)

    results = []
    configs = [
        # (TF, GoldWin, EntryType, MinSweepATR, DispBodyATR, RequireFVG, MidnightOpen, HTFBias, SLBuf, RR, UseBE)
        ("M15", True, "FVG_LIMIT", 0.10, 0.38, True, True, "STRICT", 0.25, 3.0, True),
        ("M15", True, "FVG_LIMIT", 0.10, 0.38, True, True, "STRICT", 0.25, 2.5, True),
        ("M15", True, "FVG_LIMIT", 0.10, 0.38, True, True, "STRICT", 0.25, 2.0, True),
        ("M15", True, "FVG_LIMIT", 0.10, 0.38, True, False, "STRICT", 0.25, 3.0, True),
        ("M15", False, "FVG_LIMIT", 0.10, 0.38, True, True, "STRICT", 0.25, 2.5, True),
        ("M15", True, "MSS_MARKET", 0.10, 0.38, True, True, "STRICT", 0.25, 2.5, True),
        ("M5", True, "FVG_LIMIT", 0.15, 0.45, True, False, "EMA200", 0.25, 3.0, True),
        ("M5", True, "FVG_LIMIT", 0.15, 0.45, True, False, "EMA200", 0.25, 2.5, True),
        ("M5", True, "FVG_LIMIT", 0.15, 0.45, True, True, "EMA200", 0.25, 3.0, True),
        ("M5", True, "FVG_LIMIT", 0.15, 0.45, True, False, "STRICT", 0.25, 3.0, True),
        ("M5", False, "FVG_LIMIT", 0.15, 0.45, True, False, "EMA200", 0.25, 2.5, True),
        ("M5", True, "MSS_MARKET", 0.15, 0.45, True, True, "EMA200", 0.25, 2.5, True),
    ]

    m15_best_trades = None
    m15_best_cfg = None
    m5_best_trades = None
    m5_best_cfg = None

    print("\nRunning Grid Search Optimization across M5 and M15 (2020-2025)...")
    for cfg in configs:
        tf, g_win, entry_type, sweep_atr, disp_atr, req_fvg, req_mo, htf_mode, sl_buf, rr, use_be = cfg
        df_use = df_m15 if tf == "M15" else df_m5
        sess_use = sessions_m15 if tf == "M15" else sessions_m5

        trades = simulate_state_machine(
            df_use,
            sess_use,
            killzone_mode="BOTH",
            use_golden_windows=g_win,
            min_sweep_atr=sweep_atr,
            disp_body_atr=disp_atr,
            require_fvg=req_fvg,
            require_midnight_open=req_mo,
            htf_bias_mode=htf_mode,
            entry_type=entry_type,
            sl_buffer_atr=sl_buf,
            rr_target=rr,
            use_be_at_1r=use_be,
        )
        metrics = evaluate_trades(trades, risk_pct=1.0)
        row = {
            "tf": tf,
            "gold_win": g_win,
            "entry_type": entry_type,
            "min_sweep_atr": sweep_atr,
            "disp_body_atr": disp_atr,
            "require_fvg": req_fvg,
            "midnight_open": req_mo,
            "htf_bias": htf_mode,
            "sl_buffer_atr": sl_buf,
            "rr_target": rr,
            "use_be_at_1r": use_be,
            **metrics,
        }
        results.append(row)

        if tf == "M15" and g_win and req_mo and htf_mode == "STRICT" and rr == 3.0:
            m15_best_trades = trades
            m15_best_cfg = row
        if tf == "M5" and g_win and not req_mo and htf_mode == "EMA200" and rr == 3.0:
            m5_best_trades = trades
            m5_best_cfg = row

    res_df = pd.DataFrame(results).sort_values(by=["tf", "total_r"], ascending=[False, False])
    print("\n=== OPTIMIZATION RESULTS (2020-2025 XAUUSD) ===")
    print(
        res_df[
            [
                "tf",
                "gold_win",
                "entry_type",
                "midnight_open",
                "htf_bias",
                "rr_target",
                "total_trades",
                "win_rate",
                "profit_factor",
                "total_r",
                "max_dd_r",
                "final_equity",
                "max_dd_pct",
            ]
        ].to_string(index=False)
    )

    with open("/tmp/xauusd_opt_results.json", "w") as f:
        json.dump(
            {
                "m15_best": m15_best_cfg,
                "m5_best": m5_best_cfg,
                "all_results": results,
            },
            f,
            indent=2,
        )

    # Plot Dual Comparison Equity Curve (M15 Sniper Mode vs M5 Active Mode)
    if m15_best_trades and m5_best_trades:
        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 7.5), gridspec_kw={"height_ratios": [2.3, 1]})
        fig.patch.set_facecolor("#0f172a")
        for ax in (ax1, ax2):
            ax.set_facecolor("#1e293b")
            ax.tick_params(colors="#e2e8f0")
            for spine in ax.spines.values():
                spine.set_color("#334155")
            ax.grid(True, color="#334155", linestyle="--", alpha=0.5)

        for label, color, tr_list, cfg in [
            (
                f"M5 Active Mode ({m5_best_cfg['total_trades']} Trades | WR: {m5_best_cfg['win_rate']}% | PF: {m5_best_cfg['profit_factor']} | +{m5_best_cfg['total_r']}R)",
                "#eab308",
                m5_best_trades,
                m5_best_cfg,
            ),
            (
                f"M15 Sniper Prop-Firm Mode ({m15_best_cfg['total_trades']} Trades | WR: {m15_best_cfg['win_rate']}% | PF: {m15_best_cfg['profit_factor']} | Max DD: {m15_best_cfg['max_dd_pct']}%)",
                "#38bdf8",
                m15_best_trades,
                m15_best_cfg,
            ),
        ]:
            r_arr = np.array([t["r_multiple"] for t in tr_list])
            dates = pd.to_datetime([t["dt"][:19] for t in tr_list])
            eq = [10000.0]
            for r in r_arr:
                eq.append(eq[-1] * (1.0 + 0.01 * r))
            eq = np.array(eq[1:])
            ax1.plot(dates, eq, color=color, linewidth=2.2, label=label)

            peak = np.maximum.accumulate(eq)
            dd_pct = (eq - peak) / peak * 100.0
            ax2.plot(dates, dd_pct, color=color, linewidth=1.3, label=f"{cfg['tf']} Drawdown (Max: -{cfg['max_dd_pct']}%)")

        ax1.set_title(
            "XAUUSD (Gold) 5-Year Backtest & Optimization (2020-2025): Combined AMD + Layer 3 Liquidity EA",
            color="#f8fafc",
            fontsize=12.5,
            fontweight="bold",
        )
        ax1.set_ylabel("Account Balance ($ USD, 1% Risk/Trade)", color="#f8fafc")
        ax1.legend(facecolor="#0f172a", edgecolor="#475569", labelcolor="#f8fafc", fontsize=10)

        ax2.set_ylabel("Drawdown (%)", color="#f8fafc")
        ax2.set_xlabel("Year (2020 - 2025)", color="#f8fafc")
        ax2.legend(facecolor="#0f172a", edgecolor="#475569", labelcolor="#f8fafc", fontsize=9.5)

        plt.tight_layout()
        plt.savefig("/home/user/EA31337/xauusd_amd_optimization_report.png", dpi=150)
        print("\nSaved dual equity chart to /home/user/EA31337/xauusd_amd_optimization_report.png")


if __name__ == "__main__":
    main()
