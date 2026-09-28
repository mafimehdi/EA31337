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
    """Raise ValueError when a preset breaks the research / coherence rules."""
    values = dict(BASE)
    values.update(preset["overrides"])
    problems = []
    is_reference = (preset.get("family") == "reference")
    pine_weights = (preset.get("weights") == "pine")

    # --- general coherence: no filter family measured twice ---------------
    hard = hard_filters(preset)
    per_family = {}
    for family, label in hard:
        per_family.setdefault(family, []).append(label)
    for family, labels in sorted(per_family.items()):
        if len(labels) > MAX_HARD_PER_FAMILY:
            problems.append("more than %d hard %s filters: %s" % (MAX_HARD_PER_FAMILY, family, labels))
    if len(hard) > MAX_HARD_TOTAL:
        problems.append("more than %d hard filters in total: %d" % (MAX_HARD_TOTAL, len(hard)))

    entry = values.get("InpEntryMode", "AX_ENTRY_MARKET")
    anti_whipsaw = str(values.get("InpUseAntiWhipsaw", "false")).lower() == "true"
    struct = values.get("InpStructMode", "AX_STRUCT_OFF")
    exit_mode = values.get("InpExitMode", "AX_EXIT_SPLIT_BE")
    strong = values.get("InpStrongMode", "AX_STRONG_OFF")

    if entry == "AX_ENTRY_STOP" and anti_whipsaw:
        problems.append("AX_ENTRY_STOP combined with InpUseAntiWhipsaw=true (they fight each other)")
    if entry == "AX_ENTRY_LIMIT" and struct == "AX_STRUCT_REQUIRE_FRESH":
        problems.append("AX_ENTRY_LIMIT combined with AX_STRUCT_REQUIRE_FRESH (contradiction)")
    if entry == "AX_ENTRY_LIMIT" and str(values.get("InpPendingFallbackMkt", "true")).lower() == "true":
        problems.append("AX_ENTRY_LIMIT with InpPendingFallbackMkt=true (pullback preset turns into a market preset)")
    if exit_mode == "AX_EXIT_TP2_ONLY" and str(values.get("InpKeepTP2OnOrder", "true")).lower() == "false":
        problems.append("AX_EXIT_TP2_ONLY without a server side TP2")
    other_hard = [item for item in hard if item[0] != "quality"]
    if strong == "AX_STRONG_ONLY" and len(other_hard) > 4:
        problems.append("AX_STRONG_ONLY with more than 4 hard filters (practically no trades)")
    if str(values.get("InpUsePineCancelRule", "false")).lower() == "true":
        problems.append("InpUsePineCancelRule is gold specific, keep it out of the presets")

    # --- cost gates (the 0.47 USD spread research) -------------------------
    def num(name):
        return float(values.get(name, "0"))

    if is_reference:
        if str(values.get("InpUseCostFilters", "true")).lower() != "false":
            problems.append("the reference preset must keep InpUseCostFilters=false")
        if not pine_weights:
            problems.append("the reference preset must use the original Pine weights")
        if exit_mode != "AX_EXIT_TP1_ONLY":
            problems.append("the reference preset must keep the original TP1-only exit")
    else:
        if str(values.get("InpUseCostFilters", "true")).lower() != "true":
            problems.append("research presets must enable InpUseCostFilters")
        if num("InpFixedSpreadPoints") != 47:
            problems.append("research presets must assume the 47 point spread")
        if num("InpMinATR") < 1.0:
            problems.append("research presets need InpMinATR >= 1.0 (cost/risk ratio)")
        if num("InpMinSLSpreadMult") < 2.0:
            problems.append("research presets need InpMinSLSpreadMult >= 2.0")
        if num("InpMinTargetSpreadMult") < 3.0:
            problems.append("research presets need InpMinTargetSpreadMult >= 3.0")
        if str(values.get("InpSkipTP1IfUneconomic", "false")).lower() != "true":
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
        if values.get("InpTrendTF") == "AX_TF_5":
            problems.append("the trend filter timeframe must stay above the M1 chart")

    known = {item["name"] for item in inputs}
    unknown = sorted(set(values) - known)
    if unknown:
        problems.append("unknown input names: %s" % unknown)

    if problems:
        raise ValueError(
            "Preset %s is not coherent:\n  - %s" % (preset["file"], "\n  - ".join(problems))
        )
    return hard




# 3. Execution base and the research presets
# --------------------------------------------------------------------------
# The base is identical in every preset so that a comparison measures the
# filter combination and nothing else. It encodes the research conclusions for
# XAUUSD M1 with a fixed 0.47 USD spread (see docs/AlgoX_M1_Filter_Research_fa.md):
#   - target the TP2/runner, never the small TP1 (the spread eats it),
#   - require a minimum ATR and a strong ADX regime,
#   - require the geometry to be at least a few times the spread,
#   - score the documented indicators (MACD, RSI, volume) and down-weight
#     Fibonacci and the pivot structure break.
BASE = {
    # deterministic sizing (100 USD balance, 1.5% risk, 10 USD per 1.0 move per lot)
    # -> keeps the presets comparable with the original indicator numbers.
    # Use AX_SIZING_BROKER on a live account.
    "InpSizingMode": "AX_SIZING_PINE_FIXED",
    "InpPineBalance": "100",
    "InpRiskPercent": "1.5",
    "InpPineLotValue": "10",
    # execution base
    "InpEntryMode": "AX_ENTRY_MARKET",
    "InpSLAnchor": "AX_ANCHOR_RECENTER",
    "InpExitMode": "AX_EXIT_TP2_BE",
    "InpKeepTP2OnOrder": "true",
    "InpMoveToBEAtTP1": "true",
    "InpOneSignalPerMove": "true",
    "InpCooldownBars": "10",
    # cost gates (the 47 cent spread)
    "InpUseCostFilters": "true",
    "InpFixedSpreadPoints": "47",
    "InpMinATR": "1.0",
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
        "title": "Reference: the indicator itself, no cost gates",
        "family": "reference",
        "weights": "pine",
        "theme": (
            "Faithful copy of the TradingView indicator: original score weights (fib 25, "
            "structure 30, EMA 25, RSI 20), no MACD and no volume scoring, the original TP1 "
            "exit with the reference SL/TP and no cost gates. Only kept as the comparison "
            "baseline - the research shows this geometry cannot survive a 0.47 USD spread."
        ),
        "overrides": {
            "InpMagicNumber": "20260100",
            "InpUseCostFilters": "false",
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
        },
    },
    {
        "file": "C1_Trend_Momentum",
        "title": "Trend + momentum (ADX regime, MACD, RSI, volume)",
        "family": "trend",
        "theme": (
            "The documented combination: the higher timeframe trend (M15 EMA 50) is required and "
            "the MACD histogram must agree, while RSI (55/45 levels), the intraday regime "
            "(EMA 5/10/20) and the relative volume carry the rebalanced score weight. The trade targets TP2 with the "
            "stop moved to break-even at the TP1 distance, and it only fires when ATR(5) >= 1.0 "
            "USD, ADX is strong and the geometry is at least 3x the spread - the research "
            "thresholds for a 0.47 USD spread on gold M1."
        ),
        "overrides": {
            "InpMagicNumber": "20260101",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpTrendTF": "AX_TF_15",
            "InpMACDMode": "AX_MODE_REQUIRE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpRegimeMode": "AX_MODE_SCORE",
            "InpVolAvgMode": "AX_MODE_OFF",
            "InpVolFilterMode": "AX_MODE_OFF",
            "InpCooldownBars": "12",
        },
    },
    {
        "file": "C2_Expansion_Breakout",
        "title": "Expansion breakout (fresh structure + new extremes + volume)",
        "family": "breakout",
        "theme": (
            "The other documented combination: a fresh BOS/CHoCH structure break plus a close at "
            "the 200-bar extreme, confirmed by relative volume (hard) and the MACD histogram "
            "(score). Momentum is scored with the rebalanced weights, the entry is at market to "
            "keep the entry method identical across the research presets, and the exit is TP2 "
            "with the break-even trigger. Expansion trades only, so the anti-whipsaw penalty "
            "stays off."
        ),
        "overrides": {
            "InpMagicNumber": "20260102",
            "InpStructMode": "AX_STRUCT_REQUIRE_FRESH",
            "InpRange200Mode": "AX_MODE_REQUIRE",
            "InpVolFilterMode": "AX_MODE_REQUIRE",
            "InpMACDMode": "AX_MODE_SCORE",
            "InpWeightMACD": "20",
            "InpCooldownBars": "5",
        },
    },
    {
        "file": "C3_CostGates_Only",
        "title": "Control: original score engine plus the cost gates only",
        "family": "cost",
        "weights": "pine",
        "theme": (
            "The control group: the original score engine (fib 25 / structure 30 / EMA 25 / RSI 20) "
            "with no extra indicator block, but with the cost gates and the TP2 + break-even exit. "
            "The difference against 00_Pine_Baseline isolates how much of the improvement comes "
            "from the geometry alone (target size, ATR and ADX gates) instead of the filters."
        ),
        "overrides": {
            "InpMagicNumber": "20260103",
            "InpWeightFib": "25",
            "InpWeightRSI": "20",
            "InpWeightEMA": "25",
            "InpWeightStruct": "30",
            "InpWeightMACD": "0",
            "InpWeightVolume": "0",
            "InpCooldownBars": "10",
        },
    },
    {
        "file": "C4_Session_Expansion",
        "title": "Session expansion (New York open, stricter ATR gate)",
        "family": "session",
        "theme": (
            "C1 restricted to the New York session (16:01-21:59 UTC) with a stricter ATR gate "
            "(1.2 USD) and a shorter cooldown, because the spread is paid in the window where "
            "volatility actually expands. Trend (M15) and MACD are hard filters, RSI, regime and "
            "volume score, exit is TP2 with the break-even trigger."
        ),
        "overrides": {
            "InpMagicNumber": "20260104",
            "InpUseSessionFilter": "true",
            "InpTradingSession": "AX_SESSION_NEWYORK",
            "InpUseManualGMTOffset": "true",
            "InpBrokerGMTOffsetHrs": "3",
            "InpMinATR": "1.2",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpTrendTF": "AX_TF_15",
            "InpMACDMode": "AX_MODE_REQUIRE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpRegimeMode": "AX_MODE_SCORE",
            "InpCooldownBars": "5",
        },
    },
]



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
