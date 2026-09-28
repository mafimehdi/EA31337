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


def validate_coherence(preset, inputs):
    """Raise ValueError when a preset mixes filters that fight each other."""
    values = dict(BASE)
    values.update(preset["overrides"])
    problems = []

    hard = hard_filters(preset)
    per_family = {}
    for family, label in hard:
        per_family.setdefault(family, []).append(label)

    for family, labels in sorted(per_family.items()):
        if len(labels) > MAX_HARD_PER_FAMILY:
            problems.append(
                "more than %d hard %s filters: %s" % (MAX_HARD_PER_FAMILY, family, labels)
            )
    if len(hard) > MAX_HARD_TOTAL:
        problems.append("more than %d hard filters in total: %d" % (MAX_HARD_TOTAL, len(hard)))

    entry = values.get("InpEntryMode", "AX_ENTRY_MARKET")
    anti_whipsaw = str(values.get("InpUseAntiWhipsaw", "false")).lower() == "true"
    struct = values.get("InpStructMode", "AX_STRUCT_OFF")
    exit_mode = values.get("InpExitMode", "AX_EXIT_SPLIT_BE")
    strong = values.get("InpStrongMode", "AX_STRONG_OFF")

    # A breakout entry cannot live together with an anti-whipsaw penalty:
    # breakouts happen exactly when volatility expands and the cooldown doubles.
    if entry == "AX_ENTRY_STOP" and anti_whipsaw:
        problems.append("AX_ENTRY_STOP combined with InpUseAntiWhipsaw=true (they fight each other)")

    # Waiting for a pullback while demanding a fresh structure break is a
    # contradiction: by the time the price pulls back the break is no longer fresh.
    if entry == "AX_ENTRY_LIMIT" and struct == "AX_STRUCT_REQUIRE_FRESH":
        problems.append("AX_ENTRY_LIMIT combined with AX_STRUCT_REQUIRE_FRESH (contradiction)")

    # A single runner target makes no sense when the exit is a split/trail exit.
    if exit_mode == "AX_EXIT_TP2_ONLY" and str(values.get("InpKeepTP2OnOrder", "true")).lower() == "false":
        problems.append("AX_EXIT_TP2_ONLY without a server side TP2")

    # Too many hard filters together with the strong-only gate leaves (almost) no trades.
    other_hard = [item for item in hard if item[0] != "quality"]
    if strong == "AX_STRONG_ONLY" and len(other_hard) > 4:
        problems.append("AX_STRONG_ONLY with more than 4 hard filters (practically no trades)")

    # Mixing a limit entry with a stop entry is impossible by design (one input),
    # but a limit entry with market fallback changes the strategy silently.
    if entry == "AX_ENTRY_LIMIT" and str(values.get("InpPendingFallbackMkt", "true")).lower() == "true":
        problems.append("AX_ENTRY_LIMIT with InpPendingFallbackMkt=true (pullback preset turns into a market preset)")

    if str(values.get("InpUsePineCancelRule", "false")).lower() == "true":
        problems.append("InpUsePineCancelRule is gold specific, keep it out of the presets")

    known = {item["name"] for item in inputs}
    unknown = sorted(set(values) - known)
    if unknown:
        problems.append("unknown input names: %s" % unknown)

    if problems:
        raise ValueError(
            "Preset %s is not coherent:\n  - %s" % (preset["file"], "\n  - ".join(problems))
        )
    return hard


# --------------------------------------------------------------------------
# 3. Common execution base and the combined presets
# --------------------------------------------------------------------------
# Identical in every preset, so that only the filter combination differs:
BASE = {
    # Deterministic position sizing (100 USD balance, 1.5% risk, 10 USD per
    # 1.0 price move per lot) - keeps the presets comparable with the
    # original indicator numbers. Use AX_SIZING_BROKER on a live account.
    "InpSizingMode": "AX_SIZING_PINE_FIXED",
    "InpPineBalance": "100",
    "InpRiskPercent": "1.5",
    "InpPineLotValue": "10",
    # Execution base: market entry, SL/TP re-centred on the real fill, split
    # exit with a break-even move after TP1.
    "InpEntryMode": "AX_ENTRY_MARKET",
    "InpSLAnchor": "AX_ANCHOR_RECENTER",
    "InpExitMode": "AX_EXIT_SPLIT_BE",
    "InpTP1Portion": "0.5",
    "InpMoveToBEAtTP1": "true",
    "InpKeepTP2OnOrder": "true",
}

PRESETS = [
    {
        "file": "00_Pine_Baseline",
        "title": "Reference: the indicator itself, no filters",
        "family": "reference",
        "theme": (
            "Nothing is filtered: the plain score engine with the original thresholds, cooldown "
            "and the original TP1 exit. This is the curve every combination is measured against."
        ),
        "overrides": {
            "InpMagicNumber": "20260100",
            "InpSLAnchor": "AX_ANCHOR_REFERENCE",
            "InpExitMode": "AX_EXIT_TP1_ONLY",
            "InpMoveToBEAtTP1": "false",
            "InpKeepTP2OnOrder": "false",
        },
    },
    {
        "file": "01_Trend_Pullback_Confluence",
        "title": "Trend + pullback location (limit entry)",
        "family": "trend",
        "theme": (
            "Direction comes from the higher timeframe trend plus the structure bias, the entry "
            "comes from a pullback: a limit order at the 30% level of the signal candle, valid for "
            "three bars and only while the price is on the right side of the VWAP. Choppy, flat "
            "conditions are skipped. The SuperTrend, the Fibonacci levels, volume and the 55/45 RSI "
            "levels add score instead of blocking, so the same information is not required twice."
        ),
        "overrides": {
            "InpMagicNumber": "20260101",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpStructMode": "AX_STRUCT_FILTER",
            "InpSTUse": "AX_MODE_SCORE",
            "InpEntryMode": "AX_ENTRY_LIMIT",
            "InpPendingExpiryBars": "3",
            "InpPendingFallbackMkt": "false",
            "InpVWAPMode": "AX_MODE_REQUIRE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpVolFilterMode": "AX_MODE_SCORE",
            "InpUseAntiWhipsaw": "true",
            "InpConsolMultiplier": "0.85",
            "InpConsolCDMultiplier": "1.25",
            "InpUseSlopeFilter": "true",
            "InpSlopeMin": "0.12",
            "InpCooldownBars": "10",
        },
    },
    {
        "file": "02_Trend_Continuation_Momentum",
        "title": "Trend + momentum + volume expansion",
        "family": "trend",
        "theme": (
            "The direction must be confirmed by two independent trend measurements (higher "
            "timeframe EMA and the SuperTrend) and the move must be backed by momentum (MACD "
            "histogram) and by rising participation (relative volume above 1.2x). The EMA regime, "
            "the 55/45 RSI levels and the slope only add score, because they measure the same thing "
            "the two trend filters already measure."
        ),
        "overrides": {
            "InpMagicNumber": "20260102",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpSTUse": "AX_MODE_REQUIRE",
            "InpRegimeMode": "AX_MODE_SCORE",
            "InpMACDMode": "AX_MODE_REQUIRE",
            "InpVolFilterMode": "AX_MODE_REQUIRE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpUseSlopeFilter": "true",
            "InpSlopeMin": "0.15",
            "InpTrendBonus": "5",
            "InpCooldownBars": "10",
            "InpReEntryMode": "AX_REENTRY_BLOCK_SAME_DIR",
        },
    },
    {
        "file": "03_London_Trend_Session",
        "title": "London session trend continuation",
        "family": "session",
        "theme": (
            "The trend filters are only required from the higher timeframe and the SuperTrend, and "
            "the preset trades the London session only, where trends develop: everything else "
            "(MACD, 55/45 RSI levels, slope, relative volume, SuperTrend bonus) is a score "
            "adjustment, so the session restriction does not kill the signal count."
        ),
        "overrides": {
            "InpMagicNumber": "20260103",
            "InpUseSessionFilter": "true",
            "InpTradingSession": "AX_SESSION_LONDON",
            "InpUseManualGMTOffset": "true",
            "InpBrokerGMTOffsetHrs": "3",
            "InpMaxSpreadPoints": "50",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpSTUse": "AX_MODE_REQUIRE",
            "InpMACDMode": "AX_MODE_SCORE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpVolFilterMode": "AX_MODE_SCORE",
            "InpUseSlopeFilter": "true",
            "InpSlopeMin": "0.1",
            "InpCooldownBars": "8",
        },
    },
    {
        "file": "04_Breakout_Expansion",
        "title": "Breakout + volume expansion + new extremes",
        "family": "breakout",
        "theme": (
            "A pure expansion combo: a fresh BOS/CHoCH break, a close at the 200-bar extreme, a "
            "MACD agreement and relative volume above 1.2x, entered with a stop order just beyond "
            "the signal candle extreme (InpEntryPercent=90), so the position opens only when the "
            "break really happens. Anti-whipsaw and the slope filter stay out on purpose: they "
            "would suppress exactly the expansion this combo trades."
        ),
        "overrides": {
            "InpMagicNumber": "20260104",
            "InpStructMode": "AX_STRUCT_REQUIRE_FRESH",
            "InpRange200Mode": "AX_MODE_REQUIRE",
            "InpMACDMode": "AX_MODE_REQUIRE",
            "InpVolFilterMode": "AX_MODE_REQUIRE",
            "InpExtraFibMode": "AX_FIBEXTRA_786",
            "InpEntryMode": "AX_ENTRY_STOP",
            "InpEntryPercent": "90",
            "InpPendingExpiryBars": "2",
            "InpPendingFallbackMkt": "false",
            "InpOneSignalPerMove": "true",
            "InpCooldownBars": "5",
        },
    },
    {
        "file": "05_NY_Breakout_Momentum",
        "title": "New York session breakout momentum",
        "family": "session",
        "theme": (
            "The same breakout idea, tuned for the New York session (the most volatile window) and "
            "with softer quality gates: participation above its average and MACD as hard filters, "
            "200-bar extremes, SuperTrend and relative volume as score, plus a spread cap. Stop "
            "entry beyond the signal candle keeps the entry adaptive."
        ),
        "overrides": {
            "InpMagicNumber": "20260105",
            "InpUseSessionFilter": "true",
            "InpTradingSession": "AX_SESSION_NEWYORK",
            "InpUseManualGMTOffset": "true",
            "InpBrokerGMTOffsetHrs": "3",
            "InpMaxSpreadPoints": "60",
            "InpVolAvgMode": "AX_MODE_REQUIRE",
            "InpMACDMode": "AX_MODE_REQUIRE",
            "InpRange200Mode": "AX_MODE_SCORE",
            "InpSTUse": "AX_MODE_SCORE",
            "InpVolFilterMode": "AX_MODE_SCORE",
            "InpEntryMode": "AX_ENTRY_STOP",
            "InpEntryPercent": "90",
            "InpPendingExpiryBars": "2",
            "InpPendingFallbackMkt": "false",
            "InpCooldownBars": "5",
        },
    },
    {
        "file": "06_Confluence_Max_Quality",
        "title": "Maximum confluence (few, fully confirmed trades)",
        "family": "quality",
        "theme": (
            "Only signals at or above the strong threshold (85) are traded, and they must be "
            "aligned with the higher timeframe trend, the structure bias, the MACD histogram and "
            "the volume average (participation). The remaining confirmations (relative volume "
            "bonus, regime, 55/45 RSI levels) add score instead of blocking, and the same direction "
            "is traded once per day - four hard filters plus the strong gate is the practical limit "
            "before a preset stops trading altogether."
        ),
        "overrides": {
            "InpMagicNumber": "20260106",
            "InpStrongMode": "AX_STRONG_ONLY",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpStructMode": "AX_STRUCT_FILTER",
            "InpMACDMode": "AX_MODE_REQUIRE",
            "InpVolAvgMode": "AX_MODE_REQUIRE",
            "InpVolFilterMode": "AX_MODE_SCORE",
            "InpRegimeMode": "AX_MODE_SCORE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpOneSignalPerMove": "true",
            "InpReEntryMode": "AX_REENTRY_BLOCK_SAME_DAY",
            "InpCooldownBars": "12",
        },
    },
    {
        "file": "07_Defensive_Low_Risk",
        "title": "Defensive: trade rarely, small, take profits early",
        "family": "quality",
        "theme": (
            "Capital protection combo: only strong signals (score >= 85), consolidation and flat "
            "moves are skipped, the cooldown is long, one signal per move, the spread is capped, "
            "the risk per trade is halved (0.75%) and the position is closed completely at TP1 - no "
            "runner, no open risk while the market is quiet."
        ),
        "overrides": {
            "InpMagicNumber": "20260107",
            "InpStrongMode": "AX_STRONG_ONLY",
            "InpUseAntiWhipsaw": "true",
            "InpConsolMultiplier": "0.8",
            "InpConsolCDMultiplier": "1.5",
            "InpUseSlopeFilter": "true",
            "InpSlopeMin": "0.2",
            "InpMaxSpreadPoints": "40",
            "InpCooldownBars": "20",
            "InpOneSignalPerMove": "true",
            "InpRiskPercent": "0.75",
            "InpExitMode": "AX_EXIT_TP1_ONLY",
            "InpMoveToBEAtTP1": "false",
            "InpKeepTP2OnOrder": "false",
        },
    },
    {
        "file": "08_Value_VWAP_Balance",
        "title": "Value entries: VWAP + Fibonacci, no trend mandate",
        "family": "value",
        "theme": (
            "A two-way combo for balanced markets: no trend filter at all, the location filters do "
            "the work (close beyond the 50% and the 78.6% Fibonacci levels, on the right side of "
            "the VWAP) and the entry waits for a pullback with a limit order. The trend and volume "
            "blocks add score only, and the anti-whipsaw penalty stays off because this combo "
            "accepts ranging conditions."
        ),
        "overrides": {
            "InpMagicNumber": "20260108",
            "InpEntryMode": "AX_ENTRY_LIMIT",
            "InpPendingExpiryBars": "3",
            "InpPendingFallbackMkt": "false",
            "InpExtraFibMode": "AX_FIBEXTRA_BOTH",
            "InpVWAPMode": "AX_MODE_REQUIRE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpVolFilterMode": "AX_MODE_SCORE",
            "InpTrendFilterMode": "AX_MODE_BONUS",
            "InpTrendBonus": "5",
            "InpCooldownBars": "8",
        },
    },
    {
        "file": "09_Asia_Range_Value",
        "title": "Asian session range value",
        "family": "session",
        "theme": (
            "The Asian session usually ranges instead of trending, so this combo trades value "
            "inside the balance: limit entry on the pullback, VWAP and both extra Fibonacci levels "
            "as hard location filters, the 55/45 RSI levels and volume as score, no trend "
            "requirement, and the whole position is closed at TP1 (a range target, not a runner)."
        ),
        "overrides": {
            "InpMagicNumber": "20260109",
            "InpUseSessionFilter": "true",
            "InpTradingSession": "AX_SESSION_ASIA",
            "InpUseManualGMTOffset": "true",
            "InpBrokerGMTOffsetHrs": "3",
            "InpMaxSpreadPoints": "50",
            "InpEntryMode": "AX_ENTRY_LIMIT",
            "InpPendingExpiryBars": "4",
            "InpPendingFallbackMkt": "false",
            "InpExtraFibMode": "AX_FIBEXTRA_BOTH",
            "InpVWAPMode": "AX_MODE_REQUIRE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpVolFilterMode": "AX_MODE_SCORE",
            "InpExitMode": "AX_EXIT_TP1_ONLY",
            "InpMoveToBEAtTP1": "false",
            "InpKeepTP2OnOrder": "false",
            "InpCooldownBars": "8",
        },
    },
    {
        "file": "10_Trend_Rider_Trailing",
        "title": "Trend rider with a trailing runner",
        "family": "trend",
        "theme": (
            "Built for long trends: direction from the higher timeframe trend and the structure "
            "bias, soft confirmations from the SuperTrend, MACD, volume and slope, a partial exit "
            "at TP1 with the stop moved to break-even and then an ATR trailing stop for the rest. "
            "Strong signals (score >= 85) get 1.5x the normal risk, because the runner needs room."
        ),
        "overrides": {
            "InpMagicNumber": "20260110",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpStructMode": "AX_STRUCT_FILTER",
            "InpSTUse": "AX_MODE_SCORE",
            "InpMACDMode": "AX_MODE_SCORE",
            "InpRegimeMode": "AX_MODE_SCORE",
            "InpVolFilterMode": "AX_MODE_SCORE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpUseSlopeFilter": "true",
            "InpSlopeMin": "0.12",
            "InpExitMode": "AX_EXIT_TRAIL_AFTER_TP1",
            "InpTrailMode": "AX_TRAIL_BY_ATR",
            "InpTrailATRMult": "2.0",
            "InpKeepTP2OnOrder": "false",
            "InpStrongMode": "AX_STRONG_BOOST_RISK",
            "InpStrongRiskMult": "1.5",
            "InpCooldownBars": "10",
        },
    },
    {
        "file": "11_AllWeather_Score_Based",
        "title": "All-weather: one score, no hard blockers",
        "family": "hybrid",
        "theme": (
            "For traders who dislike filter stacking: every confirmation of the EA contributes "
            "score instead of blocking (higher timeframe trend bonus, SuperTrend, MACD, 55/45 RSI "
            "levels, relative volume, 200-bar extremes, market regime) and only the consolidation "
            "penalty (score x0.9 and a 1.2x cooldown) protects against choppy conditions. The "
            "single threshold decides, so the trade count stays close to the baseline."
        ),
        "overrides": {
            "InpMagicNumber": "20260111",
            "InpTrendFilterMode": "AX_MODE_BONUS",
            "InpTrendBonus": "5",
            "InpSTUse": "AX_MODE_SCORE",
            "InpMACDMode": "AX_MODE_SCORE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpVolFilterMode": "AX_MODE_SCORE",
            "InpRange200Mode": "AX_MODE_SCORE",
            "InpRegimeMode": "AX_MODE_SCORE",
            "InpExtraWeight": "10",
            "InpUseAntiWhipsaw": "true",
            "InpConsolMultiplier": "0.9",
            "InpConsolCDMultiplier": "1.2",
            "InpCooldownBars": "12",
        },
    },
]


# --------------------------------------------------------------------------
# 4. Value formatting
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
        print("  %-34s family=%-9s hard=%d  %s"
              % (preset["file"] + ".set", preset["family"], len(hard),
                 ",".join(label for _f, label in hard) if hard else "-"))

    # remove preset files that are no longer generated
    for name in sorted(os.listdir(HERE)):
        if name.endswith(".set") and name not in written:
            os.remove(os.path.join(HERE, name))
            print("  removed obsolete preset: %s" % name)

    return 0


if __name__ == "__main__":
    sys.exit(main())
