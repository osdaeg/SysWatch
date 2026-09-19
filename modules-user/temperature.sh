#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Temperature monitoring module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Temperature"
readonly MODULE_DESCRIPTION="Temperature sensor monitoring (lm-sensors or thermal_zone)"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-180}
MODULE_ORDER=${MODULE_ORDER:-44}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# "sensors" (lm-sensors, richer, may need sensors-detect) or "thermal_zone"
# (/sys/class/thermal, no dependencies, usually just CPU package/ACPI zones).
readonly TEMP_SOURCE="${TEMP_SOURCE:-sensors}"

readonly TEMP_WARNING="${TEMP_WARNING:-75}"
readonly TEMP_CRITICAL="${TEMP_CRITICAL:-90}"

# Prior readings (besides the current one) that must also breach the
# threshold before the status actually flips -- same debounce pattern as
# cpu.sh/disk.sh, using sw_csv_all_above().
readonly TEMP_SUSTAINED_SAMPLES="${TEMP_SUSTAINED_SAMPLES:-3}"

# Comma-separated list of substrings to skip (matched against "chip label",
# case-insensitive), e.g. "SYSTIN,PCH" to ignore motherboard sensors that
# don't matter to you.
readonly TEMP_EXCLUDE_SENSORS="${TEMP_EXCLUDE_SENSORS:-}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

TEMP_KEYS=()
TEMP_LABEL=()
TEMP_VALUE=()
TEMP_STATUS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

temp_sanitize_key() {

    local raw="$1"

    local key="${raw,,}"
    key="${key// /_}"
    key="${key//[^a-z0-9_]/_}"

    printf '%s\n' "${key}"

}

temp_is_excluded() {

    local label="$1"

    [[ -z "${TEMP_EXCLUDE_SENSORS}" ]] && return 1

    local IFS=','
    local pattern

    for pattern in ${TEMP_EXCLUDE_SENSORS}; do

        [[ "${label,,}" == *"${pattern,,}"* ]] && return 0

    done

    return 1

}

temp_discover_sensors() {

    local chip
    local label
    local value

    while IFS='|' read -r chip label value
    do

        [[ -z "${chip}" || -z "${value}" ]] && continue

        local full_label="${chip%%-*} ${label}"

        temp_is_excluded "${full_label}" && continue

        value="${value#+}"

        TEMP_KEYS+=("$(temp_sanitize_key "${chip%%-*}_${label}")")
        TEMP_LABEL+=("${full_label}")
        TEMP_VALUE+=("${value}")

    done < <(
        sensors 2>/dev/null |
        awk '
            /^Adapter:/  { next }
            /^$/         { next }

            # No colon at all: either a chip header ("k10temp-pci-00c3",
            # unindented) or a wrapped continuation line like
            # "(crit = +100.0 C, hyst = +99.0 C)" (indented). Only the
            # unindented ones are chip headers.
            !/:/ {

                if ($0 ~ /^[ \t]/) { next }

                chip = $0
                next

            }

            {
                colon = index($0, ":")
                label = substr($0, 1, colon - 1)
                gsub(/^[ \t]+|[ \t]+$/, "", label)

                rest = substr($0, colon + 1)

                # Strip the degree sign (and any other stray punctuation)
                # by exclusion rather than trying to match it directly --
                # some awk implementations (mawk) do not reliably match
                # that multi-byte UTF-8 character inside a regex.
                gsub(/[^0-9A-Za-z .+-]/, "", rest)

                # A temperature reading is now a plain decimal number
                # followed by an optional space and a bare "C" (handles
                # both "+32.0°C" and "+32.0 C" once the degree sign is
                # stripped). This naturally excludes mV/V/W/mW/MHz/RPM
                # readings from other sensors on the same chip (amdgpu,
                # fam15h_power, fans).
                if (match(rest, /[-+]?[0-9]+\.[0-9]+[ \t]?C/)) {

                    frag = substr(rest, RSTART, RLENGTH)
                    gsub(/[ \t]?C$/, "", frag)

                    if (frag != "") {
                        printf "%s|%s|%s\n", chip, label, frag
                    }

                }
            }
        '
    )

}

temp_discover_thermal_zone() {

    local zone
    local type
    local millidegrees
    local value

    for zone in /sys/class/thermal/thermal_zone*
    do

        [[ -d "${zone}" ]] || continue
        [[ -r "${zone}/temp" ]] || continue

        type="$(cat "${zone}/type" 2>/dev/null)"
        millidegrees="$(cat "${zone}/temp" 2>/dev/null)"

        [[ -z "${millidegrees}" ]] && continue

        temp_is_excluded "${type}" && continue

        value="$(awk -v m="${millidegrees}" 'BEGIN { printf "%.1f", m / 1000 }')"

        TEMP_KEYS+=("$(temp_sanitize_key "$(basename "${zone}")_${type}")")
        TEMP_LABEL+=("${type}")
        TEMP_VALUE+=("${value}")

    done

}

temp_collect() {

    TEMP_KEYS=()
    TEMP_LABEL=()
    TEMP_VALUE=()

    case "${TEMP_SOURCE}" in

        sensors)

            sw_require_command sensors || return 127
            temp_discover_sensors
            ;;

        thermal_zone)

            temp_discover_thermal_zone
            ;;

        *)

            sw_log_error \
                "${MODULE_NAME}" \
                "Unknown TEMP_SOURCE: ${TEMP_SOURCE} (expected 'sensors' or 'thermal_zone')"

            return 1
            ;;

    esac

}

temp_analyze() {

    local i
    local value
    local key

    for (( i=0; i<${#TEMP_KEYS[@]}; i++ ))
    do

        value="${TEMP_VALUE[$i]%%.*}"
        key="${TEMP_KEYS[$i]}"

        TEMP_STATUS[$i]="${SW_STATUS_OK}"

        if (( value >= TEMP_CRITICAL )) &&
           sw_csv_all_above "${key}" value "${TEMP_CRITICAL}" "${TEMP_SUSTAINED_SAMPLES}"
        then

            TEMP_STATUS[$i]="${SW_STATUS_CRITICAL}"

        elif (( value >= TEMP_WARNING )) &&
             sw_csv_all_above "${key}" value "${TEMP_WARNING}" "${TEMP_SUSTAINED_SAMPLES}"
        then

            TEMP_STATUS[$i]="${SW_STATUS_WARNING}"

        fi

    done

}

temp_update_state() {

    local i
    local key

    for (( i=0; i<${#TEMP_KEYS[@]}; i++ )); do

        key="${TEMP_KEYS[$i]}"

        sw_state_use "${key}"
        sw_state_load

        sw_status_update "${TEMP_STATUS[$i]}" "${key}" || continue

        sw_state_set "module_version" "${MODULE_VERSION}"

        sw_state_set "module.label" "${TEMP_LABEL[$i]}"
        sw_state_set "module.icon" "lucide/thermometer"
        sw_state_set "module.order" "$MODULE_ORDER"

        sw_state_set "value" "${TEMP_VALUE[$i]}"
        sw_state_set "value.label" "Temperatura"
        sw_state_set "value.widget" "gauge"
        sw_state_set "value.unit" "°C"
        sw_state_set "value.warning" "${TEMP_WARNING}"
        sw_state_set "value.critical" "${TEMP_CRITICAL}"

        sw_state_save

        sw_csv_append \
            "${key}" \
            "value" \
            "${TEMP_VALUE[$i]%%.*}"

    done

}

temp_report() {

    local i
    local summary=""

    for (( i=0; i<${#TEMP_KEYS[@]}; i++ )); do

        summary+="${TEMP_LABEL[$i]}=${TEMP_VALUE[$i]}°C (${TEMP_STATUS[$i]}) "

    done

    sw_log_info \
        "${MODULE_NAME}" \
        "Temperature (${TEMP_SOURCE}): ${#TEMP_KEYS[@]} sensor(s): ${summary}"

}

sw_module_run() {

    temp_collect || return 1

    temp_analyze

    temp_update_state

    temp_report

}
