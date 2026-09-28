#!/usr/bin/env python3
"""Generate MT4 preset (.set) files for AlgoX_SuperTrend_Pro_EA.mq4.

The script parses the `input` declarations (and the enum values) directly from
the EA source, so every generated preset always matches the EA inputs.

Usage:
    python3 generate_presets.py

Output: NN_Name.set files next to this script. Copy them into
        <Terminal Data Folder>/MQL4/Presets and load them from the
        "Inputs" tab of the expert properties dialog.
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
# 2. Presets
# --------------------------------------------------------------------------
# The "BASE" overrides are applied to every preset (identical execution
# settings, so that only the filters differ between the presets).
BASE = {
    # Same deterministic position sizing in every preset, so the presets can
    # be compared with each other and with the original indicator numbers.
    # Switch InpSizingMode to AX_SIZING_BROKER when trading a live account.
    "InpSizingMode": "AX_SIZING_PINE_FIXED",
    "InpPineBalance": "100",
    "InpRiskPercent": "1.5",
    "InpPineLotValue": "10",
    # Common execution base: market entry, SL/TP re-centred on the fill,
    # split exit with a break-even move after TP1.
    "InpEntryMode": "AX_ENTRY_MARKET",
    "InpSLAnchor": "AX_ANCHOR_RECENTER",
    "InpExitMode": "AX_EXIT_SPLIT_BE",
    "InpTP1Portion": "0.5",
    "InpMoveToBEAtTP1": "true",
    "InpKeepTP2OnOrder": "true",
}

PRESETS = [
    {
        "file": "01_Pine_Baseline",
        "title": "Pine Baseline - exact replica of the indicator",
        "theme": (
            "All filters off, original market entry, original reference SL/TP and the "
            "original 'whole position at TP1' exit. Use it to verify that the EA "
            "reproduces the TradingView indicator before adding any filter."
        ),
        "overrides": {
            "InpMagicNumber": "20260101",
            "InpSLAnchor": "AX_ANCHOR_REFERENCE",
            "InpExitMode": "AX_EXIT_TP1_ONLY",
            "InpMoveToBEAtTP1": "false",
            "InpKeepTP2OnOrder": "false",
            "InpSensitivity": "AX_SENS_BALANCED",
            "InpStrongMode": "AX_STRONG_OFF",
        },
    },
    {
        "file": "02_Trend_Alignment",
        "title": "Trend alignment - direction must be confirmed everywhere",
        "theme": (
            "Only trades whose direction is confirmed by the higher timeframe trend, "
            "the SuperTrend, the EMA market regime and the market structure bias. "
            "Re-entries in the just-traded direction are suppressed."
        ),
        "overrides": {
            "InpMagicNumber": "20260102",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpTrendTF": "AX_TF_60",
            "InpTrendEMA": "50",
            "InpSTUse": "AX_MODE_REQUIRE",
            "InpRegimeMode": "AX_MODE_REQUIRE",
            "InpStructMode": "AX_STRUCT_FILTER",
            "InpReEntryMode": "AX_REENTRY_BLOCK_SAME_DIR",
        },
    },
    {
        "file": "03_Momentum_Volume",
        "title": "Momentum and participation confirmation",
        "theme": (
            "The signal must be backed by momentum and by real market participation: "
            "MACD agree, RSI beyond the 55/45 levels, volume above its average, "
            "relative volume above the strong threshold and a minimum price slope."
        ),
        "overrides": {
            "InpMagicNumber": "20260103",
            "InpMACDMode": "AX_MODE_REQUIRE",
            "InpRSIMode": "AX_RSI_REQUIRE_LEVELS",
            "InpVolAvgMode": "AX_MODE_REQUIRE",
            "InpVolFilterMode": "AX_MODE_REQUIRE",
            "InpUseSlopeFilter": "true",
            "InpSlopeMin": "0.15",
        },
    },
    {
        "file": "04_Structure_Breakout",
        "title": "Structure breakout - trade only fresh breaks",
        "theme": (
            "Requires a fresh BOS/CHoCH break in the signal direction, a close beyond "
            "the 78.6% Fibonacci level and a close at the 200-bar extreme. The entry is "
            "a stop order just beyond the signal candle extreme (InpEntryPercent=90), so "
            "the trade only opens once the price really breaks out."
        ),
        "overrides": {
            "InpMagicNumber": "20260104",
            "InpStructMode": "AX_STRUCT_REQUIRE_FRESH",
            "InpSwingLookback": "5",
            "InpStructFreshBars": "10",
            "InpExtraFibMode": "AX_FIBEXTRA_786",
            "InpRange200Mode": "AX_MODE_REQUIRE",
            "InpEntryMode": "AX_ENTRY_STOP",
            "InpEntryPercent": "90",
            "InpPendingExpiryBars": "2",
            "InpPendingFallbackMkt": "false",
            "InpOneSignalPerMove": "true",
        },
    },
    {
        "file": "05_Pullback_Value",
        "title": "Pullback entry at value",
        "theme": (
            "Waits for the price to come back: limit entry at the 30% level of the "
            "signal candle, close beyond both the 50% and the 78.6% Fibonacci levels "
            "and price on the right side of the VWAP. RSI is scored with the 55/45 levels."
        ),
        "overrides": {
            "InpMagicNumber": "20260105",
            "InpEntryMode": "AX_ENTRY_LIMIT",
            "InpPendingExpiryBars": "3",
            "InpPendingFallbackMkt": "false",
            "InpExtraFibMode": "AX_FIBEXTRA_BOTH",
            "InpVWAPMode": "AX_MODE_REQUIRE",
            "InpRSIMode": "AX_RSI_SCORE_LEVELS",
            "InpUseAntiWhipsaw": "true",
        },
    },
    {
        "file": "06_AntiChop_Quiet_Market",
        "title": "Anti-chop - avoid ranging and whipsaw conditions",
        "theme": (
            "Detects Bollinger consolidation (width below the 25th percentile of the "
            "last 100 bars) and reacts with a score penalty, a longer cooldown and a "
            "slope requirement, while the trend and volume blocks only add score bonuses. "
            "InpConsolThreshold=0 keeps the automatic, symbol independent threshold."
        ),
        "overrides": {
            "InpMagicNumber": "20260106",
            "InpUseAntiWhipsaw": "true",
            "InpConsolThreshold": "0.0",
            "InpConsolMultiplier": "0.85",
            "InpConsolCDMultiplier": "1.5",
            "InpUseSlopeFilter": "true",
            "InpSlopeMin": "0.2",
            "InpCooldownBars": "15",
            "InpOneSignalPerMove": "true",
            "InpTrendFilterMode": "AX_MODE_BONUS",
            "InpTrendBonus": "5",
            "InpSTUse": "AX_MODE_SCORE",
            "InpVolFilterMode": "AX_MODE_SCORE",
        },
    },
    {
        "file": "07_High_Quality_Few_Trades",
        "title": "High quality - only strong, fully confirmed signals",
        "theme": (
            "The most selective preset: only signals above the strong threshold (85), "
            "aligned with the higher timeframe trend and the structure bias, with strong "
            "relative volume, and only one trading day in the same direction."
        ),
        "overrides": {
            "InpMagicNumber": "20260107",
            "InpStrongMode": "AX_STRONG_ONLY",
            "InpStrongThreshold": "85",
            "InpSensitivity": "AX_SENS_BALANCED",
            "InpTrendFilterMode": "AX_MODE_REQUIRE",
            "InpStructMode": "AX_STRUCT_FILTER",
            "InpVolFilterMode": "AX_MODE_REQUIRE",
            "InpReEntryMode": "AX_REENTRY_BLOCK_SAME_DAY",
            "InpCooldownBars": "12",
        },
    },
    {
        "file": "08_Session_NewYork_Scalp",
        "title": "New York session scalp",
        "theme": (
            "Only trades during the New York session (UTC 16:01-21:59), with an "
            "aggressive threshold, a shorter cooldown, a spread limit and score bonuses "
            "from the SuperTrend and the relative volume."
        ),
        "overrides": {
            "InpMagicNumber": "20260108",
            "InpUseSessionFilter": "true",
            "InpTradingSession": "AX_SESSION_NEWYORK",
            "InpUseManualGMTOffset": "true",
            "InpBrokerGMTOffsetHrs": "3",
            "InpMaxSpreadPoints": "60",
            "InpSensitivity": "AX_SENS_AGGRESSIVE",
            "InpCooldownBars": "5",
            "InpSTUse": "AX_MODE_SCORE",
            "InpVolFilterMode": "AX_MODE_SCORE",
        },
    },
    {
        "file": "09_Aggressive_Max_Signals",
        "title": "Aggressive - maximum number of signals",
        "theme": (
            "Every filter off, the aggressive threshold (80/50), a very short cooldown "
            "and a trailing stop after TP1 instead of a fixed TP2. Highest trade count, "
            "lowest selectivity - useful as the upper bound of the frequency range."
        ),
        "overrides": {
            "InpMagicNumber": "20260109",
            "InpSensitivity": "AX_SENS_AGGRESSIVE",
            "InpCooldownBars": "3",
            "InpOneSignalPerMove": "false",
            "InpExitMode": "AX_EXIT_TRAIL_AFTER_TP1",
            "InpTrailMode": "AX_TRAIL_BY_R",
            "InpTrailDistR": "0.5",
            "InpKeepTP2OnOrder": "false",
        },
    },
]


# --------------------------------------------------------------------------
# 3. Value formatting
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


def build_set_content(preset, inputs, enums):
    """Return the full text of a .set file for one preset."""
    overrides = dict(BASE)
    overrides.update(preset["overrides"])

    known = {item["name"] for item in inputs}
    unknown = sorted(set(overrides) - known)
    if unknown:
        raise ValueError("Unknown inputs in preset %s: %s" % (preset["file"], unknown))

    lines = [
        "; AlgoX SuperTrend Pro EA - preset %s" % preset["file"],
        "; %s" % preset["title"],
        "; %s" % preset["theme"],
        "; Generated by generate_presets.py - do not edit by hand.",
        "; Copy to MQL4/Presets and load it from the Inputs tab (Load button).",
        "",
    ]

    for item in inputs:
        name = item["name"]
        value = overrides.get(name, item["default"])
        lines.append("%s=%s" % (name, format_value(value, item["type"], enums)))

    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------
# 4. Main
# --------------------------------------------------------------------------
def main():
    inputs, enums = parse_ea(EA_PATH)
    print("Parsed %d inputs and %d enums from %s" % (len(inputs), len(enums), EA_PATH))

    for preset in PRESETS:
        content = build_set_content(preset, inputs, enums)
        path = os.path.join(HERE, preset["file"] + ".set")
        with open(path, "w", encoding="ascii", newline="\n") as handle:
            handle.write(content)
        print("  written: %s (%d lines)" % (os.path.basename(path), content.count("\n")))

    return 0


if __name__ == "__main__":
    sys.exit(main())
