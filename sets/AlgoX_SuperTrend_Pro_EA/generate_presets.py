#!/usr/bin/env python3
"""Generate coherent MT4 preset (.set) files for AlgoX_SuperTrend_Pro_EA.mq4.

"Coherent" means: inside one preset the filters belong to the same market
hypothesis (trend following, breakout, pullback/value, defensive, session) and
they do not fight each other. The coherence rule set is enforced by
`validate_coherence()` below, so an incoherent preset cannot be generated.

Use the script after changing the EA inputs:

    python3 generate_presets.py

The script parses `input` declarations and enum values straight from the .mq4
source, therefore the presets always stay in sync with the EA.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EA_PATH = os.path.normpath(
    os.path.join(HERE, "..", "..", "src", "AlgoX_SuperTrend_Pro_EA.mq4")
)

# --------------------------------------------------------------------------
# 1. Parse the EA source
# --------------------------------------------------------------------------
INPUT_RE = re.compile(
    r"^input\s+([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+);"
)
ENUM_RE = re.compile(r"^enum\s+([A-Za-z_][A-Za-z0-9_]*)\s*$")
ENUM_MEMBER_RE = re.compile(
    r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?\d+)\s*(?:,|//|$)"
)
COMMENT_RE = re.compile(r"//\s*(.*)$")


def parse_ea(path):
    """Return (inputs, enums).

    inputs: list of dicts {name, type, default, comment}
    enums:  dict enum_name -> {member_name: int_value}
    """
    inputs = []
    enums = {}
    current_enum = None

    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")

            enum_match = ENUM_RE.match(line.strip())
            if enum_match:
                current_enum = enum_match.group(1)
                enums[current_enum] = {}
                continue

            if current_enum:
                member = ENUM_MEMBER_RE.match(line)
                if member:
                    enums[current_enum][member.group(1)] = int(member.group(2))
                    continue
                if line.strip() in ("};", "}"):
                    current_enum = None
                    continue

            if not line.startswith("input"):
                continue

            match = INPUT_RE.match(line)
            if not match:
                raise ValueError("Cannot parse input line: " + line)

            var_type, name, default = match.groups()
            comment_match = COMMENT_RE.search(line)
            inputs.append(
                {
                    "name": name,
                    "type": var_type,
                    "default": default.strip(),
                    "comment": comment_match.group(1).strip() if comment_match else "",
                }
            )

    if not inputs:
        raise ValueError("No inputs found in " + path)
    return inputs, enums


# --------------------------------------------------------------------------
# 2. Filter families and the coherence rules
# --------------------------------------------------------------------------
# Every filter belongs to one family. Filters of different families measure
# different things, so they combine well; several hard (REQUIRE) filters of the
# same family add selectivity without adding information.
FAMILY = {
    # --- trend / direction ------------------------------------------------
    "InpTrendFilterMode": "trend",
    "InpSTUse": "trend",
    "InpRegimeMode": "trend",
    "InpStructMode": "trend",
    # --- momentum ---------------------------------------------------------
    "InpMACDMode": "momentum",
    "InpRSIMode": "momentum",
    # --- participation (volume) -------------------------------------------
    "InpVolAvgMode": "volume",
    "InpVolFilterMode": "volume",
    # --- location (value) -------------------------------------------------
    "InpVWAPMode": "location",
    "InpRange200Mode": "location",
    "InpExtraFibMode": "location",
    # --- market condition -------------------------------------------------
    "InpUseAntiWhipsaw": "condition",
    "InpUseSlopeFilter": "condition",
    # --- trading window ---------------------------------------------------
    "InpUseSessionFilter": "window",
    "InpSpreadCap": "window",  # virtual: InpMaxSpreadPoints > 0
    # --- signal quality gate ----------------------------------------------
    "InpStrongMode": "quality",
}

MAX_HARD_PER_FAMILY = 2
MAX_HARD_TOTAL = 5


def hard_filters(preset):
    """Return the list of (family, label) of the hard filters of a preset."""
    values = dict(BASE)
    values.update(preset["overrides"])

    hard = []
    for name, family in FAMILY.items():
        if name == "InpSpreadCap":
            if float(values.get("InpMaxSpreadPoints", "0")) > 0:
                hard.append((family, "InpMaxSpreadPoints>0"))
            continue

        value = values.get(name)
        if value is None:
            continue

        if name == "InpStrongMode":
            is_hard = (value == "AX_STRONG_ONLY")
        elif name == "InpRSIMode":
            is_hard = (value == "AX_RSI_REQUIRE_LEVELS")
        elif name == "InpStructMode":
            is_hard = value in ("AX_STRUCT_FILTER", "AX_STRUCT_REQUIRE_FRESH")
        elif name == "InpExtraFibMode":
            is_hard = value in ("AX_FIBEXTRA_50", "AX_FIBEXTRA_786", "AX_FIBEXTRA_BOTH")
        elif name in ("InpUseAntiWhipsaw", "InpUseSlopeFilter", "InpUseSessionFilter"):
            is_hard = (str(value).lower() == "true")
        else:
            is_hard = (value == "AX_MODE_REQUIRE")

        if is_hard:
            hard.append((family, name))
    return hard


ATR_GATE_MIN = {"M1": 1.0, "M5": 2.0, "M15": 3.0}


def validate_coherence(preset, inputs):
    """Raise ValueError when a preset breaks the research / safety rules."""
    values = dict(BASE)
    values.update(preset["overrides"])
    problems = []
    is_reference = (preset.get("family") == "reference")
    pine_weights = (preset.get("weights") == "pine")
    tf = preset.get("tf", "M5")

    def num(name):
        return float(values.get(name, "0"))

    def flag(name):
        return str(values.get(name, "false")).lower() == "true"

    # --- general coherence: no filter family measured twice ---------------
    hard = [] if is_reference else hard_filters(preset)
    per_family = {}
    for family, label in hard:
        per_family.setdefault(family, []).append(label)
    for family, labels in sorted(per_family.items()):
        if len(labels) > MAX_HARD_PER_FAMILY:
            problems.append("more than %d hard %s filters: %s" % (MAX_HARD_PER_FAMILY, family, labels))
    if len(hard) > MAX_HARD_TOTAL:
        problems.append("more than %d hard filters in total: %d" % (MAX_HARD_TOTAL, len(hard)))

    entry = values.get("InpEntryMode", "AX_ENTRY_MARKET")
    anti_whipsaw = flag("InpUseAntiWhipsaw")
    struct = values.get("InpStructMode", "AX_STRUCT_OFF")
    exit_mode = values.get("InpExitMode", "AX_EXIT_SPLIT_BE")
    strong = values.get("InpStrongMode", "AX_STRONG_OFF")

    if entry == "AX_ENTRY_STOP" and anti_whipsaw:
        problems.append("AX_ENTRY_STOP combined with InpUseAntiWhipsaw=true (they fight each other)")
    if entry == "AX_ENTRY_LIMIT" and struct == "AX_STRUCT_REQUIRE_FRESH":
        problems.append("AX_ENTRY_LIMIT combined with AX_STRUCT_REQUIRE_FRESH (contradiction)")
    if entry == "AX_ENTRY_LIMIT" and flag("InpPendingFallbackMkt"):
        problems.append("AX_ENTRY_LIMIT with InpPendingFallbackMkt=true (pullback preset turns into a market preset)")
    if exit_mode == "AX_EXIT_TP2_ONLY" and not flag("InpKeepTP2OnOrder"):
        problems.append("AX_EXIT_TP2_ONLY without a server side TP2")
    other_hard = [item for item in hard if item[0] != "quality"]
    if strong == "AX_STRONG_ONLY" and len(other_hard) > 4:
        problems.append("AX_STRONG_ONLY with more than 4 hard filters (practically no trades)")
    if flag("InpUsePineCancelRule"):
        problems.append("InpUsePineCancelRule is gold specific, keep it out of the presets")

    # --- the safety layer is obligatory in every preset --------------------
    if not flag("InpUseSafetyLimits"):
        problems.append("every preset must keep InpUseSafetyLimits=true")
    if values.get("InpSizingMode") != "AX_SIZING_BROKER":
        problems.append("presets must size from the real account (AX_SIZING_BROKER), "
                        "the fixed modes risk 10x more than intended on a 100 oz contract")
    if num("InpRiskPercent") > 0.75:
        problems.append("risk per trade must stay at or below 0.75% (got %s)" % values.get("InpRiskPercent"))
    if num("InpRiskPercentCap") > 1.0:
        problems.append("InpRiskPercentCap must be 1.0% or lower")
    if num("InpMaxMarginPercent") > 5.0:
        problems.append("InpMaxMarginPercent must be 5% or lower")
    if num("InpMaxSpreadPoints") <= 0.0:
        problems.append("every preset needs a live spread cap (InpMaxSpreadPoints)")
    if num("InpMaxTradesPerDay") <= 0:
        problems.append("every preset needs InpMaxTradesPerDay")
    if num("InpMaxDailyLossPercent") <= 0.0:
        problems.append("every preset needs InpMaxDailyLossPercent")
    if num("InpMaxConsecutiveLosses") <= 0:
        problems.append("every preset needs InpMaxConsecutiveLosses")
    if num("InpEquityStopPercent") <= 0.0:
        problems.append("every preset needs InpEquityStopPercent")
    if not flag("InpCloseOnEquityStop"):
        problems.append("the equity stop should close the open position")
    if num("InpMaxTradeLossPercent") <= 0.0:
        problems.append("every preset needs InpMaxTradeLossPercent (one trade must never "
                        "cost more than a few percent of the account)")
    if num("InpMaxTradeLossPercent") > 3.0:
        problems.append("InpMaxTradeLossPercent above 3% is too permissive for a single trade")
    if not flag("InpForceStopLoss"):
        problems.append("every preset must keep InpForceStopLoss=true")

    # --- timeframe calibration --------------------------------------------
    if tf not in ATR_GATE_MIN:
        problems.append("unknown timeframe tag: %s" % tf)
    else:
        minimum = ATR_GATE_MIN[tf]
        if is_reference:
            if num("InpMinATR") > minimum:
                problems.append("the reference preset should not gate on ATR (it measures the raw signal)")
        else:
            if not flag("InpUseCostFilters"):
                problems.append("research presets must enable InpUseCostFilters")
            if num("InpFixedSpreadPoints") != 47:
                problems.append("research presets must assume the 47 point spread")
            if num("InpMinATR") < minimum:
                problems.append("%s presets need InpMinATR >= %.1f" % (tf, minimum))
            if num("InpMinSLSpreadMult") < 2.0:
                problems.append("research presets need InpMinSLSpreadMult >= 2.0")
            if num("InpMinTargetSpreadMult") < 3.0:
                problems.append("research presets need InpMinTargetSpreadMult >= 3.0")
            if not flag("InpSkipTP1IfUneconomic"):
                problems.append("research presets must keep InpSkipTP1IfUneconomic=true")
            if values.get("InpMinADXRegime") in (None, "AX_REGIME_ANY"):
                problems.append("research presets must require at least the medium ADX regime")
            if exit_mode == "AX_EXIT_TP1_ONLY":
                problems.append("the TP1-only exit is structurally unprofitable with a 0.47 spread")
            if exit_mode == "AX_EXIT_SPLIT_BE" and num("InpTP1Portion") < 0.5:
                problems.append("a partial TP1 below 50% leaves too much size for a small target")
            if not pine_weights:
                if num("InpWeightFib") > 15 or num("InpWeightStruct") > 15:
                    problems.append("research presets must not keep the 55% weight on fib + structure")
                weight_sum = sum(num(n) for n in ("InpWeightFib", "InpWeightRSI", "InpWeightEMA",
                                                  "InpWeightStruct", "InpWeightMACD", "InpWeightVolume"))
                if weight_sum <= 0:
                    problems.append("score weights must not all be zero")

    # --- trend filter must stay above the chart timeframe ------------------
    tf_minutes = {"AX_TF_1": 1, "AX_TF_5": 5, "AX_TF_15": 15, "AX_TF_30": 30, "AX_TF_60": 60, "AX_TF_240": 240}
    chart_minutes = {"M1": 1, "M5": 5, "M15": 15}[tf]
    trend_tf = values.get("InpTrendTF")
    trend_mode = values.get("InpTrendFilterMode", "AX_MODE_OFF")
    if trend_mode not in ("AX_MODE_OFF",) and trend_tf in tf_minutes:
        if tf_minutes[trend_tf] <= chart_minutes:
            problems.append("the trend filter timeframe (%s) must be above the chart timeframe (%s)"
                            % (trend_tf, tf))

    known = {item["name"] for item in inputs}
    unknown = sorted(set(values) - known)
    if unknown:
        problems.append("unknown input names: %s" % unknown)

    if problems:
        raise ValueError(
            "Preset %s is not coherent:\n  - %s" % (preset["file"], "\n  - ".join(problems))
        )
    return hard




# 3. Execution base and the M5 / M15 research presets
# --------------------------------------------------------------------------
# Post mortem of the first live round (XAUUSD M1, 0.47 spread, 500 USD test
# account, four presets in parallel):
#   C1 -473 USD | PF 0.60 | 157 trades | 31.2% wins
#   C2 -347 USD | PF 0.87 | 528 trades | 38.3% wins   <- best of the four
#   C3 -463 USD | PF 0.64 | 256 trades | 34.0% wins
#   C4 -461 USD | PF 0.64 | 235 trades | 33.6% wins
# Every preset needed a 41.5-44.6% win rate to break even and delivered
# 31-38%; on M1 the spread is ~30-50% of the risk distance, and the fixed
# "(PINE) lot value" of the indicator assumed a 10 oz contract while the
# broker trades 100 oz - the effective risk per trade was ~10x the intended
# 1.5%, i.e. ~2.7% of a 500 USD account per trade, times four presets.
#
# This base therefore enforces, in every file:
#   - sizing from the REAL account (AX_SIZING_BROKER), 0.5% risk per trade,
#   - the account safety layer (margin cap, daily loss, trade count, loss
#     streak, equity stop) - it cannot be switched off by a preset,
#   - a live spread cap, so the 47 point assumption is never exceeded in
#     reality,
#   - the cost gates and the rebalanced score weights of the research,
#   - no TP1-only exit anywhere (it cannot pay a 0.47 spread).
# Only the ATR gate, the cooldown and the filters differ per timeframe.
BASE = {
    # real account sizing: 0.5% of the equity per trade, margin capped
    "InpSizingMode": "AX_SIZING_BROKER",
    "InpRiskPercent": "0.5",
    "InpPineBalance": "100",
    "InpPineLotValue": "10",
    # account safety layer (see the [SAFETY] inputs of the EA)
    "InpUseSafetyLimits": "true",
    "InpRiskPercentCap": "1.0",
    "InpMaxMarginPercent": "5.0",
    "InpMaxTradesPerDay": "3",
    "InpMaxDailyLossPercent": "3.0",
    "InpMaxConsecutiveLosses": "4",
    "InpEquityStopPercent": "20.0",
    "InpCloseOnEquityStop": "true",
    "InpMaxTradeLossPercent": "2.0",
    "InpForceStopLoss": "true",
    # execution base
    "InpEntryMode": "AX_ENTRY_MARKET",
    "InpSLAnchor": "AX_ANCHOR_RECENTER",
    "InpExitMode": "AX_EXIT_TP2_BE",
    "InpKeepTP2OnOrder": "true",
    "InpMoveToBEAtTP1": "true",
    "InpOneSignalPerMove": "true",
    "InpMaxSpreadPoints": "60",
    # cost gates (the 47 cent spread)
    "InpUseCostFilters": "true",
    "InpFixedSpreadPoints": "47",
    "InpMinATR": "2.0",
    "InpMinADXRegime": "AX_REGIME_STRONG",
    "InpMinSLSpreadMult": "2.0",
    "InpMinTargetSpreadMult": "3.0",
    "InpSkipTP1IfUneconomic": "true",
    # rebalanced score weights (documented components carry the weight)
    "InpWeightFib": "10",
    "InpWeightRSI": "20",
    "InpWeightEMA": "20",
    "InpWeightStruct": "10",
    "InpWeightMACD": "20",
    "InpWeightVolume": "20",
    "InpWeightHTF": "0",
}

PRESETS = [
    {
        "file": "00_Pine_Baseline",
        "status": "control",
        "title": "Reference: the raw indicator signal",
        "family": "reference",
        "weights": "pine",
        "tf": "M5",
        "theme": (
            "The raw signal: original Pine weights (fib 25, structure 30, EMA 25, RSI 20), no MACD "
            "and no volume scoring, the original reference SL/TP and the original TP1 exit, with the "
            "cost gates switched off - but with the same account sizing and the same safety layer as "
            "every other preset, so the comparison is about the signal and not about broken sizing. "
            "Run it twice: once with the tester spread at 47 (the real cost) and once at 0 (does the "
            "raw signal have any edge at all?). The pair of results tells you whether the problem is "
            "the signal or the cost."
        ),
        "overrides": {
            "InpMagicNumber": "20260100",
            "InpUseCostFilters": "false",
            "InpMinATR": "0",
            "InpMinADXRegime": "AX_REGIME_ANY",
            "InpSkipTP1IfUneconomic": "false",
            "InpWeightFib": "25",
            "InpWeightRSI": "20",
            "InpWeightEMA": "25",
            "InpWeightStruct": "30",
            "InpWeightMACD": "0",
            "InpWeightVolume": "0",
            "InpSLAnchor": "AX_ANCHOR_REFERENCE",
            "InpExitMode": "AX_EXIT_TP1_ONLY",
            "InpMoveToBEAtTP1": "false",
            "InpKeepTP2OnOrder": "false",
            "InpOneSignalPerMove": "false",
            "InpMaxSpreadPoints": "60",
            "InpMaxTradesPerDay": "5",
        },
    },
    {
        "file": "M15_A_Breakout_Volume",
        "status": "reference",
        "title": "M15: expansion breakout with volume (the best of the first round)",
        "family": "breakout",
        "tf": "M15",
        "theme": (
            "The only preset of the first round whose win rate came close to its break-even "
            "(38.3% against 41.5% needed): a fresh BOS/CHoCH structure break plus a close at the "
            "200-bar extreme, confirmed by relative volume (hard) and the MACD histogram (score), "
            "with the higher timeframe trend (H1) adding a bonus. Rebuilt on M15, where the spread "
            "is only ~9% of the risk distance instead of ~40%: ATR(5) gate 3.0 USD, ADX must be "
            "strong, geometry at least 2x (SL) and 3x (TP2) the spread, exit TP2 with the stop "
            "moved to break-even at the TP1 distance."
        ),
        "overrides": {
            "InpMagicNumber": "20260301",
            "InpMinATR": "3.0",
            "InpCooldownBars": "4",
            "InpStructMode": "AX_STRUCT_REQUIRE_FRESH",
            "InpRange200Mode": "AX_MODE_REQUIRE",
            "InpVolFilterMode": "AX_MODE_REQUIRE",
            "InpMACDMode": "AX_MODE_SCORE",
            "InpTrendFilterMode": "AX_MODE_BONUS",
            "InpTrendTF": "AX_TF_60",
            "InpTrendEMA": "50",
            "InpTrendBonus": "5",
            "InpRegimeMode": "AX_MODE_SCORE",
        },
    },
    {
        "file": "M15_B_Trend_Runner",
        "status": "rejected",
        "title": "M15: trend + momentum with an ATR trailing runner",
        "family": "trend",
        "tf": "M15",
        "theme": (
            "The trend continuation idea, kept from C1 but slimmed to two hard filters: the H1 "
            "trend must agree and the MACD histogram must agree, while the 55/45 RSI levels and the "
            "intraday regime add score. The exit is the runner variant: the stop moves to break-even "
            "at the TP1 distance and then trails 2x ATR, so a trend day is not cut by a fixed "
            "target - the first round showed that fixed targets smaller than 4-5x the spread cannot "
            "pay for the cost. ATR(5) gate 3.0 USD."
        ),
        "overrides": {
            "InpMagicNumber": "20260302",
            "InpMinATR": "3.0",
            "InpCooldownBars": "4",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpTrendTF": "AX_TF_60",
            "InpMACDMode": "AX_MODE_REQUIRE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpRegimeMode": "AX_MODE_SCORE",
            "InpExitMode": "AX_EXIT_TRAIL_AFTER_TP1",
            "InpTrailMode": "AX_TRAIL_BY_ATR",
            "InpTrailATRMult": "2.0",
            "InpTP2Multiplier": "2.0",
        },
    },
    {
        "file": "M15_C_NY_Expansion",
        "status": "watch",
        "title": "M15: New York session expansion",
        "family": "session",
        "tf": "M15",
        "theme": (
            "A15_A restricted to the New York session (16:01-21:59 UTC with a 3h broker offset) "
            "and a stricter ATR gate (3.5 USD): the spread is a fixed cost, so it is paid only in "
            "the window where the range actually expands. Structure break, 200-bar extreme and "
            "relative volume are hard, the H1 trend and the MACD add score."
        ),
        "overrides": {
            "InpMagicNumber": "20260303",
            "InpMinATR": "3.5",
            "InpCooldownBars": "3",
            "InpUseSessionFilter": "true",
            "InpTradingSession": "AX_SESSION_NEWYORK",
            "InpUseManualGMTOffset": "true",
            "InpBrokerGMTOffsetHrs": "3",
            "InpStructMode": "AX_STRUCT_REQUIRE_FRESH",
            "InpRange200Mode": "AX_MODE_REQUIRE",
            "InpVolFilterMode": "AX_MODE_REQUIRE",
            "InpMACDMode": "AX_MODE_SCORE",
            "InpTrendFilterMode": "AX_MODE_BONUS",
            "InpTrendTF": "AX_TF_60",
        },
    },
    {
        "file": "M5_A_Breakout_Volume",
        "status": "candidate",
        "title": "M5: expansion breakout with volume",
        "family": "breakout",
        "tf": "M5",
        "theme": (
            "The same hypothesis as M15_A one timeframe faster: a fresh structure break, a close at "
            "the 200-bar extreme and relative volume above 1.2x are hard, MACD scores, the M30 trend "
            "adds a bonus. The M5 spread share is ~13% of the risk distance (ATR gate 2.0 USD), so "
            "the cost handicap is much smaller than on M1 - but still twice the M15 one."
        ),
        "overrides": {
            "InpMagicNumber": "20260201",
            "InpMinATR": "2.0",
            "InpCooldownBars": "6",
            "InpStructMode": "AX_STRUCT_REQUIRE_FRESH",
            "InpRange200Mode": "AX_MODE_REQUIRE",
            "InpVolFilterMode": "AX_MODE_REQUIRE",
            "InpMACDMode": "AX_MODE_SCORE",
            "InpTrendFilterMode": "AX_MODE_BONUS",
            "InpTrendTF": "AX_TF_30",
            "InpRegimeMode": "AX_MODE_SCORE",
        },
    },
    {
        "file": "M5_B_Trend_Momentum",
        "status": "rejected",
        "title": "M5: trend + momentum (M30 filter)",
        "family": "trend",
        "tf": "M5",
        "theme": (
            "The trend + momentum combination on M5: the M30 trend is required, the MACD histogram "
            "is required, the 55/45 RSI levels and the intraday regime score, and the exit is TP2 "
            "with the break-even trigger. ATR(5) gate 2.0 USD and a 6 bar cooldown keep the trade "
            "count and the cost drag down."
        ),
        "overrides": {
            "InpMagicNumber": "20260202",
            "InpMinATR": "2.0",
            "InpCooldownBars": "6",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpTrendTF": "AX_TF_30",
            "InpMACDMode": "AX_MODE_REQUIRE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpRegimeMode": "AX_MODE_SCORE",
        },
    },
    {
        "file": "M5_C_NY_Expansion",
        "status": "watch",
        "title": "M5: New York session expansion",
        "family": "session",
        "tf": "M5",
        "theme": (
            "M5_A limited to the New York session with a stricter ATR gate (2.5 USD) and a 4 bar "
            "cooldown. Fewer entries, each of them in the part of the day that actually pays for "
            "the spread."
        ),
        "overrides": {
            "InpMagicNumber": "20260203",
            "InpMinATR": "2.5",
            "InpCooldownBars": "4",
            "InpUseSessionFilter": "true",
            "InpTradingSession": "AX_SESSION_NEWYORK",
            "InpUseManualGMTOffset": "true",
            "InpBrokerGMTOffsetHrs": "3",
            "InpStructMode": "AX_STRUCT_REQUIRE_FRESH",
            "InpRange200Mode": "AX_MODE_REQUIRE",
            "InpVolFilterMode": "AX_MODE_REQUIRE",
            "InpMACDMode": "AX_MODE_SCORE",
            "InpTrendFilterMode": "AX_MODE_BONUS",
            "InpTrendTF": "AX_TF_30",
        },
    },
]



# --------------------------------------------------------------------------
def format_value(value, var_type, enums):
    """Convert a python value / literal into the MT4 .set representation."""
    text = str(value).strip()

    if var_type == "bool":
        low = text.lower()
        if low in ("true", "1"):
            return "true"
        if low in ("false", "0"):
            return "false"
        raise ValueError("Bad bool value: " + text)

    if var_type in enums:
        if text in enums[var_type]:
            return str(enums[var_type][text])
        if re.fullmatch(r"-?\d+", text):
            return text
        raise ValueError("Bad enum value %s for %s" % (text, var_type))

    if var_type == "int":
        return str(int(float(text)))

    if var_type == "double":
        number = float(text)
        if number == int(number) and "." not in text and "e" not in text.lower():
            return "%.1f" % number
        return text

    raise ValueError("Unsupported input type: " + var_type)


def build_set_content(preset, inputs, enums, hard):
    """Return the full text of a .set file for one preset."""
    overrides = dict(BASE)
    overrides.update(preset["overrides"])

    lines = [
        "; AlgoX SuperTrend Pro EA - preset %s" % preset["file"],
        "; %s" % preset["title"],
        "; family: %s | hard filters: %s" % (
            preset["family"],
            ", ".join(label for _family, label in hard) if hard else "none",
        ),
        "; status: %s" % preset.get("status", "research"),
        "; %s" % preset["theme"],
        "; Generated by generate_presets.py - do not edit by hand.",
        "; Copy to MQL4/Presets and load it from the Inputs tab (Load button).",
        "; Coherence rules: max %d hard filters per family, max %d in total,"
        % (MAX_HARD_PER_FAMILY, MAX_HARD_TOTAL),
        "; everything else inside a family stays on score so the filters do not fight each other.",
        "",
    ]

    for item in inputs:
        name = item["name"]
        value = overrides.get(name, item["default"])
        lines.append("%s=%s" % (name, format_value(value, item["type"], enums)))

    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------
# 5. Main
# --------------------------------------------------------------------------
def main():
    inputs, enums = parse_ea(EA_PATH)
    print("Parsed %d inputs and %d enums from %s" % (len(inputs), len(enums), EA_PATH))
    print("Coherence rules: <=%d hard filters per family, <=%d in total"
          % (MAX_HARD_PER_FAMILY, MAX_HARD_TOTAL))

    written = []
    for preset in PRESETS:
        hard = validate_coherence(preset, inputs)
        content = build_set_content(preset, inputs, enums, hard)
        path = os.path.join(HERE, preset["file"] + ".set")
        with open(path, "w", encoding="ascii", newline="\n") as handle:
            handle.write(content)
        written.append(preset["file"] + ".set")
        print("  %-34s status=%-9s family=%-9s hard=%d  %s"
              % (preset["file"] + ".set", preset.get("status", "research"),
                 preset["family"], len(hard),
                 ",".join(label for _f, label in hard) if hard else "-"))

    # remove preset files that are no longer generated
    for name in sorted(os.listdir(HERE)):
        if name.endswith(".set") and name not in written:
            os.remove(os.path.join(HERE, name))
            print("  removed obsolete preset: %s" % name)

    return 0


if __name__ == "__main__":
    sys.exit(main())
