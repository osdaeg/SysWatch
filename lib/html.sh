#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# HTML dashboard generator
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly HTML_DIR="${PROJECT_DIR}/html"
readonly HTML_FILE="${HTML_DIR}/index.html"

readonly HTML_CSS_DIR="${HTML_DIR}/css"
readonly HTML_ICON_DIR="${HTML_DIR}/icons"
readonly HTML_JS_DIR="${HTML_DIR}/js"

readonly HTML_REFRESH="${HTML_REFRESH:-60}"

HTML_CURRENT_MODULE=""

# -----------------------------------------------------------------------------
# HTML
# -----------------------------------------------------------------------------

sw_html_begin() {

cat <<EOF
<!DOCTYPE html>

<html lang="en">

<head>

<meta charset="utf-8">

<meta http-equiv="refresh"
      content="${HTML_REFRESH}">

<title>SysWatch</title>

<link rel="stylesheet"
      href="css/syswatch.css">

</head>

<body>

<div class="dashboard">

EOF

}

sw_html_end() {

cat <<EOF

</div>

</body>

</html>

EOF

}

# -----------------------------------------------------------------------------
# Module rendering
# -----------------------------------------------------------------------------

sw_html_render_header() {

    local label="$1"
    local icon="$2"

    local status

    status="$(sw_state_get status)"
    status="${status,,}"

cat <<EOF

<div class="card status-${status}">

<div class="card-header">

<img class="module-icon status-${status}"
     src="icons/${icon}.svg"
     alt="">

<span>${label}</span>

</div>

EOF

}

# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Value formatting
# -----------------------------------------------------------------------------
#
# ".widget" decides which shape a field takes (text / gauge / line).
# ".render" decides how the raw number inside that shape is formatted
# (e.g. bytes -> "1.1GiB"). The two are independent: any widget can carry
# a ".render" hint, so this lives in one place instead of being duplicated
# (or half-duplicated) inside each widget renderer.
#
# NOTE: only DISPLAY strings should go through this. Anything used for
# geometry or threshold math (gauge --value, chart min/max/points) must
# keep using the raw numeric value.

sw_html_format_value() {

    local key="$1"
    local value="$2"

    local render

    render="$(sw_state_get "${key}.render")"

    case "${render}" in

        bytes)

            [[ -n "${value}" ]] && value="$(sw_human_bytes "${value}")"
            ;;

    esac

    printf '%s\n' "${value}"

}

# -----------------------------------------------------------------------------

sw_html_widget_text() {

    local key="$1"
    local value="$2"

    local label
    local unit

    local align
    local color

    label="$(sw_state_get "${key}.label")"
    unit="$(sw_state_get "${key}.unit")"

    align="$(sw_state_get "${key}.align")"
    color="$(sw_state_get "${key}.color")"

    [[ -n "${align}" ]] || align="right"
    [[ -n "${color}" ]] || color="white"

    [[ -n "${label}" ]] || label="${key}"

    case "${align}" in
        left|center|right)
            ;;
        *)
            align="right"
            ;;
    esac

    case "${color}" in
        white|black|yellow|red|green|orange|pink)
            ;;
        *)
            color="white"
            ;;
    esac

    value="$(sw_html_format_value "${key}" "${value}")"

cat <<EOF

<div class="field">

<div class="field-label">${label}</div>

<div class="field-value" style="text-align:${align}; color:${color};">${value}${unit:+ ${unit}}</div>

</div>

EOF

}

# -----------------------------------------------------------------------------

sw_html_widget_gauge() {

    local key="$1"
    local value="$2"

    local label
    local unit
    local warning
    local critical
    local display_value
    local status

    label="$(sw_state_get "${key}.label")"
    unit="$(sw_state_get "${key}.unit")"

    warning="$(sw_state_get "${key}.warning")"
    critical="$(sw_state_get "${key}.critical")"

    [[ -n "${label}" ]] || label="${key}"
    [[ -n "${warning}" ]] || warning=80
    [[ -n "${critical}" ]] || critical=95

    local color="var(--ok-color)"

    local value_int="${value%%.*}"
    local critical_int="${critical%%.*}"
    local warning_int="${warning%%.*}"

    if (( value_int >= critical_int )); then

        color="var(--critical-color)"

    elif (( value_int >= warning_int )); then

        color="var(--warning-color)"

    fi

    display_value="$(sw_html_format_value "${key}" "${value}")"

cat <<EOF

<div class="gauge-widget">

    <div
        class="gauge"
        style="
            --value:${value};
            --color:${color};
        ">

        <div class="gauge-center">

            <div class="gauge-value">${display_value}</div>
            <div class="gauge-unit">${unit}</div>

        </div>

    </div>

    <div class="gauge-label">

        ${label}

    </div>

</div>

EOF

}

# -----------------------------------------------------------------------------

sw_html_widget_line() {

    local key="$1"
    local value="$2"

    local module
    local history
    local label
    local unit
    local scale

    module="${HTML_CURRENT_MODULE}"

    history="$(sw_state_get "${key}.history")"
    [[ -n "${history}" ]] || history="${key}"

    label="$(sw_state_get "${key}.label")"
    unit="$(sw_state_get "${key}.unit")"

    scale="$(sw_state_get "${key}.scale")"
    [[ -n "${scale}" ]] || scale="dynamic"

    mapfile -t values < <(

        sw_csv_last_values \
            "${module}" \
            "${history}" \
            10

    )

    ((${#values[@]} == 0)) && values=(0)

    local history_min="${values[0]}"
    local history_max="${values[0]}"

    local v

    for v in "${values[@]}"
    do

        (( v < history_min )) && history_min="$v"
        (( v > history_max )) && history_max="$v"

    done

    local min
    local max

    case "${scale}" in

        fixed)

            min="$(sw_state_get "${key}.min")"
            max="$(sw_state_get "${key}.max")"
            ;;

        zero)

            min=0
            max="${history_max}"
            ;;

        dynamic|*)

            min="${history_min}"
            max="${history_max}"
            ;;

    esac

    (( max == min )) && max=$((min + 1))
    
    local v

    for v in "${values[@]}"
    do

        (( v < min )) && min="$v"
        (( v > max )) && max="$v"

    done

    (( max == min )) && max=$((min + 1))

    local width=300
    local height=70

    local left=4
    local right=4
    local bottom=$height

    local points=""

    local count="${#values[@]}"

    local i
    local x
    local y

    for (( i=0; i<count; i++ ))
    do

        if (( count > 1 )); then
            x=$(( left + i * ((width-left-right)/(count-1)) ))
        else
            x=$(( left + (width-left-right)/2 ))
        fi    

        if (( max == min )); then
            y=$(( height / 2 ))
        else
            y=$(( height - ((values[i]-min) * height / (max-min)) ))
        fi

        points+="${x},${y} "

    done

    local first_y
    local last_x
    local last_y

    first_y=$(( height - ((values[0]-min) * height / (max-min)) ))

    last_x="$x"
    last_y="$y"

    local polygon_points

    polygon_points="${left},${bottom}"
    polygon_points+=" ${left},${first_y}"
    polygon_points+=" ${points}"
    polygon_points+=" ${last_x},${bottom}"

    case "$(sw_state_get status)" in

        OK)

            chart_color="var(--ok-color)"
            chart_fill="var(--ok-fill)"
            ;;

        WARNING)

            chart_color="var(--warning-color)"
            chart_fill="var(--warning-fill)"
            ;;

        CRITICAL)

            chart_color="var(--critical-color)"
            chart_fill="var(--critical-fill)"
            ;;

        INFO)

            chart_color="var(--info-color)"
            chart_fill="var(--info-fill)"
            ;;    

        *)

            chart_color="var(--ok-color)"
            chart_fill="var(--ok-fill)"
            ;;

    esac

    local display

    display="$(sw_state_get "${key}.display")"

    if [[ -z "${display}" ]]; then
        display="$(sw_html_format_value "${key}" "${value}")${unit:+ ${unit}}"
    fi

cat <<EOF

<div class="line-widget">

<div class="sparkline-header">

    <span>${label}</span>

    <span
        class="sparkline-value"
        style="color:${chart_color}">

        ${display}

    </span>

</div>

<svg
    class="line-chart"
    viewBox="0 0 300 70"
    preserveAspectRatio="none">

<g class="grid">

    <line x1="0" y1="15" x2="300" y2="15"/>
    <line x1="0" y1="35" x2="300" y2="35"/>
    <line x1="0" y1="55" x2="300" y2="55"/>

    <line x1="60"  y1="0" x2="60"  y2="70"/>
    <line x1="120" y1="0" x2="120" y2="70"/>
    <line x1="180" y1="0" x2="180" y2="70"/>
    <line x1="240" y1="0" x2="240" y2="70"/>

</g>

<polygon
    points="${polygon_points}"
    fill="${chart_fill}"
    class="sparkline-fill"/>

<polyline
    points="${points}"
    stroke="${chart_color}"
    fill="none"
    stroke-width="3"
    stroke-linejoin="round"
    stroke-linecap="round"/>

<circle
    cx="${last_x}"
    cy="${last_y}"
    r="3"
    fill="${chart_color}"/>

</svg>

<div class="sparkline-footer">

    <span>

        Mín

        <strong>$(sw_html_format_value "${key}" "${min}")${unit:+ ${unit}}</strong>

    </span>

    <span>

        Máx

        <strong>$(sw_html_format_value "${key}" "${max}")${unit:+ ${unit}}</strong>

    </span>

</div>

</div>

EOF

}

# -----------------------------------------------------------------------------

sw_html_render_widget() {

    local key="$1"
    local value="$2"

    local widget

    widget="$(sw_state_get "${key}.widget")"

    case "${widget}" in

        gauge)

            sw_html_widget_gauge "$@"
            ;;

        image)

            sw_html_widget_image "$@"
            ;;
    

        line)

            sw_html_widget_line "$@"
            ;;

        *)

            sw_html_widget_text "$@"
            ;;

    esac

}

# -----------------------------------------------------------------------------

sw_html_widget_image() {

    local key="$1"
    local value="$2"

    local label
    label="$(sw_state_get "${key}.label")"

    if [[ -z "${value}" ]]; then

cat <<EOF

<div class="image-widget">

<div class="image-missing">Sin imagen</div>

EOF

        [[ -n "${label}" ]] && printf '<div class="image-label">%s</div>\n' "${label}"

        printf '</div>\n'

        return

    fi

cat <<EOF

<div class="image-widget">

<img
    class="image-widget-img"
    src="images/${value}"
    alt="${label:-${key}}"
    loading="lazy">

EOF

    [[ -n "${label}" ]] && printf '<div class="image-label">%s</div>\n' "${label}"

cat <<EOF

</div>

EOF

}

sw_html_render_fields() {

    local state_file="$1"

    local fields=()

    local key
    local value
    local order

    while IFS='=' read -r key value
    do

        [[ -z "${key}" ]] && continue

        #
        # Ignore metadata
        #

        case "${key}" in

            _internal.*)

                continue
                ;;

            module.*|*.label|*.display|*.widget|*.unit|*.warning|*.critical|*.order|*.hidden|*.scale|*.min|*.max|*.history|*.render|*.align|*.color)

                continue
                ;;

            module_version|status|status_since|timestamp)

                continue
                ;;

        esac
        
        #
        # Hidden field
        #

        if [[ "$(sw_state_get "${key}.hidden")" == "true" ]]; then
            continue
        fi

        order="$(sw_state_get "${key}.order")"

        [[ -n "${order}" ]] || order=9999

        fields+=("${order}:${key}")

    done < "${state_file}"

    # printf with a %s directive still emits one line even with zero
    # arguments (it doesn't just print nothing), so without this guard
    # an empty ${fields[@]} would feed the loop below one blank line and
    # it would render a bogus empty-key field.
    if (( ${#fields[@]} == 0 )); then

        return

    fi

    while IFS=: read -r order key
    do

        value="$(sw_state_get "${key}")"

        sw_html_render_widget \
            "${key}" \
            "${value}"

    done < <(

        printf '%s\n' "${fields[@]}" |
            sort -t: -k1,1n

    )

}

# -----------------------------------------------------------------------------

sw_html_render_module() {

    local state_file="$1"

    local module

    HTML_CURRENT_MODULE="$(basename "${state_file}" .state)"

    sw_state_use "${HTML_CURRENT_MODULE}"
    sw_state_load

    
    sw_html_render_header \
        "$(sw_state_get module.label)" \
        "$(sw_state_get module.icon)"

    sw_html_render_fields "${state_file}"

cat <<EOF

</div>

EOF

}

# -----------------------------------------------------------------------------
# Generator
# -----------------------------------------------------------------------------

sw_html_module_sort_key() {

    local state="$1"

    local module
    local status
    local order
    local priority

    module="$(basename "${state}" .state)"

    sw_state_use "${module}"
    sw_state_load

    status="$(sw_state_get status)"
    order="$(sw_state_get module.order)"

    case "${status}" in

        CRITICAL) priority=1 ;;
        WARNING)  priority=2 ;;
        UNKNOWN)  priority=3 ;;
        INFO)     priority=4 ;;
        OK)       priority=5 ;;
        PASSED)   priority=6 ;;
        DISABLED) priority=7 ;;
        *)        priority=9 ;;

    esac

    printf "%d|%03d|%s\n" \
        "${priority}" \
        "${order:-999}" \
        "${state}"

}

sw_html_sorted_states() {

    local state

    for state in "${STATE_DIR}"/*.state
    do

        sw_html_module_sort_key "${state}"

    done | sort

}

sw_html_generate() {

    {

        sw_html_begin

        local state

        while IFS='|' read -r _ _ state
        do

            sw_html_render_module "${state}"

        done < <(sw_html_sorted_states)

        sw_html_end

    } > "${HTML_FILE}"

}
