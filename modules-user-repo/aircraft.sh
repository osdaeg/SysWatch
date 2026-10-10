#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch - Aircraft module
#
# Monitors nearby aircraft using the OpenSky Network REST API and enriches
# the nearest aircraft using HexDB.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Aircraft"
readonly MODULE_DESCRIPTION="Nearby aircraft from OpenSky Network"
readonly MODULE_VERSION="0.2.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-180}
MODULE_ORDER=${MODULE_ORDER:-1200}
MODULE_REMOTE=${MODULE_REMOTE:-""}

readonly OPENSKY_API_URL="https://opensky-network.org/api/states/all"
readonly OPENSKY_TOKEN_URL="https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
readonly HEXDB_API_URL="https://hexdb.io/api/v1/aircraft"

readonly AIRCRAFT_INFO_RADIUS_KM="${AIRCRAFT_INFO_RADIUS_KM:-5}"
readonly AIRCRAFT_INFO_ALTITUDE_M="${AIRCRAFT_INFO_ALTITUDE_M:-1500}"

MODULE_INTERVAL_IF_AIRCRAFTS=30
AIRCRAFT_STATUS="${SW_STATUS_UNKNOWN}"
AIRCRAFT_COUNT=0
AIRCRAFT_INFO=0
AIRCRAFT_1_CLOSE=0

AIRCRAFT_1_ICAO=""
AIRCRAFT_1_CALLSIGN=""
AIRCRAFT_1_COUNTRY=""
AIRCRAFT_1_DISTANCE=""
AIRCRAFT_1_ALTITUDE=""
AIRCRAFT_1_SPEED=""
AIRCRAFT_1_TRACK=""

AIRCRAFT_1_MANUFACTURER=""
AIRCRAFT_1_TYPE=""
AIRCRAFT_1_OPERATOR=""

AIRCRAFT_2_ICAO=""
AIRCRAFT_2_CALLSIGN=""
AIRCRAFT_2_COUNTRY=""
AIRCRAFT_2_DISTANCE=""
AIRCRAFT_2_ALTITUDE=""
AIRCRAFT_2_SPEED=""
AIRCRAFT_2_TRACK=""

AIRCRAFT_2_MANUFACTURER=""
AIRCRAFT_2_TYPE=""
AIRCRAFT_2_OPERATOR=""

declare -A AIRCRAFT_COUNTRIES=()

# -----------------------------------------------------------------------------
# Countries
# -----------------------------------------------------------------------------

aircraft_load_countries() {

    local -a fields
    local country
    local flag

    AIRCRAFT_COUNTRIES=()

    if ! sw_cache_exists "countries.map"; then
        return 0
    fi

    while IFS='|' read -r -a fields; do

        country="${fields[0]:-}"

        [[ -n "${country}" ]] || continue

        # Support both:
        #
        #   OpenSky name | ISO | flag
        #
        # and:
        #
        #   OpenSky name | official name | ISO | flag
        #
        if ((${#fields[@]} >= 4)); then
            flag="${fields[3]:-}"
        else
            flag="${fields[2]:-}"
        fi

        [[ -n "${flag}" ]] || continue

        AIRCRAFT_COUNTRIES["${country}"]="${flag} ${country}"

    done < <(sw_cache_read "countries.map")
}

aircraft_country_display() {

    local country="$1"

    if [[ -n "${AIRCRAFT_COUNTRIES[$country]:-}" ]]; then

        printf '%s' "${AIRCRAFT_COUNTRIES[$country]}"

    else

        printf '%s' "${country}"

    fi
}

# -----------------------------------------------------------------------------
# OpenSky token
# -----------------------------------------------------------------------------

aircraft_token_get() {

    local token_file
    local token
    local expires_at
    local now

    token_file="$(sw_cache_file "opensky.token")"

    if [[ -r "${token_file}" ]]; then

        token="$(sed -n '1p' "${token_file}")"
        expires_at="$(sed -n '2p' "${token_file}")"
        now="$(date +%s)"

        if [[ -n "${token}" &&
            "${expires_at}" =~ ^[0-9]+$ &&
            "${expires_at}" -gt "${now}" ]]; then

            printf '%s\n' "${token}"
            return 0

        fi

    fi

    [[ -n "${OPENSKY_CLIENT_ID:-}" ]] || {

        sw_log_info \
            "${MODULE_NAME}" \
            "OPENSKY_CLIENT_ID no configurado"

        return 1
    }

    [[ -n "${OPENSKY_CLIENT_SECRET:-}" ]] || {

        sw_log_info \
            "${MODULE_NAME}" \
            "OPENSKY_CLIENT_SECRET no configurado"

        return 1
    }

    token="$(
        curl -sS --fail \
            --connect-timeout 10 \
            --max-time 20 \
            -X POST \
            -H 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode 'grant_type=client_credentials' \
            --data-urlencode "client_id=${OPENSKY_CLIENT_ID}" \
            --data-urlencode "client_secret=${OPENSKY_CLIENT_SECRET}" \
            "${OPENSKY_TOKEN_URL}" |
            jq -er '.access_token'
    )" || {

        sw_log_info \
            "${MODULE_NAME}" \
            "No se pudo obtener el token de OpenSky"

        return 1
    }

    # OpenSky tokens duran aproximadamente 30 minutos.
    # Dejamos margen para evitar reutilizar uno cerca de su expiración.
    expires_at="$(($(date +%s) + 1500))"

    umask 077

    {
        printf '%s\n' "${token}"
        printf '%s\n' "${expires_at}"
    } >"${token_file}"

    printf '%s\n' "${token}"
}

# -----------------------------------------------------------------------------
# OpenSky request
# -----------------------------------------------------------------------------

aircraft_opensky_request() {

    local token="$1"
    local lamin="$2"
    local lomin="$3"
    local lamax="$4"
    local lomax="$5"

    curl -sS --fail \
        --connect-timeout 10 \
        --max-time 20 \
        -H "Authorization: Bearer ${token}" \
        --get \
        --data-urlencode "lamin=${lamin}" \
        --data-urlencode "lomin=${lomin}" \
        --data-urlencode "lamax=${lamax}" \
        --data-urlencode "lomax=${lomax}" \
        --data-urlencode "extended=1" \
        "${OPENSKY_API_URL}"
}

# -----------------------------------------------------------------------------
# Distance - Haversine
# -----------------------------------------------------------------------------

aircraft_distance_km() {

    local lat="$1"
    local lon="$2"

    awk \
        -v lat1="${WEATHER_LAT}" \
        -v lon1="${WEATHER_LON}" \
        -v lat2="${lat}" \
        -v lon2="${lon}" '

        function rad(x) {
            return x * atan2(0, -1) / 180
        }

        BEGIN {

            r = 6371.0

            p1 = rad(lat1)
            p2 = rad(lat2)

            dp = rad(lat2 - lat1)
            dl = rad(lon2 - lon1)

            a = sin(dp / 2)^2 + \
                cos(p1) * cos(p2) * sin(dl / 2)^2

            c = 2 * atan2(sqrt(a), sqrt(1 - a))

            printf "%.2f\n", r * c
        }
    '
}

# -----------------------------------------------------------------------------
# OpenSky bounding box
# -----------------------------------------------------------------------------

aircraft_bbox() {

    local lat="${WEATHER_LAT}"
    local lon="${WEATHER_LON}"
    local radius="${OPENSKY_RADIUS_KM:-40}"

    awk \
        -v lat="${lat}" \
        -v lon="${lon}" \
        -v radius="${radius}" '

        BEGIN {

            lat_delta = radius / 111.32

            cos_lat = cos(lat * atan2(0, -1) / 180)

            if (cos_lat < 0.01)
                cos_lat = 0.01

            lon_delta = radius / (111.32 * cos_lat)

            printf "%.6f %.6f %.6f %.6f\n",
                lat - lat_delta,
                lon - lon_delta,
                lat + lat_delta,
                lon + lon_delta
        }
    '
}

# -----------------------------------------------------------------------------
# HexDB cache
# -----------------------------------------------------------------------------

aircraft_hexdb_cache_file() {

    local icao="$1"

    printf '%s\n' "$(sw_cache_file "aircraft-hex-${icao}.json")"
}

aircraft_hexdb_get() {

    local icao="$1"
    local cache_file
    local json

    cache_file="$(aircraft_hexdb_cache_file "${icao}")"

    # -------------------------------------------------------------------------
    # Cache hit
    # -------------------------------------------------------------------------

    if sw_cache_exists "aircraft-hex-${icao}.json"; then

        if jq -e . "${cache_file}" >/dev/null 2>&1; then
            cat "${cache_file}"
            return 0
        fi

        rm -f "${cache_file}"
    fi

    # -------------------------------------------------------------------------
    # Cache miss
    # -------------------------------------------------------------------------

    json="$(
        curl -sS --fail \
            --connect-timeout 10 \
            --max-time 20 \
            "${HEXDB_API_URL}/${icao}"
    )" || {

        return 1
    }

    if ! jq -e . >/dev/null 2>&1 <<<"${json}"; then
        return 1
    fi

    umask 077

    printf '%s\n' "${json}" >"${cache_file}"

    printf '%s\n' "${json}"
}

# -----------------------------------------------------------------------------
# Enrich aircraft from HexDB
# -----------------------------------------------------------------------------

aircraft_enrich() {

    local prefix="$1"
    local icao="$2"

    local json
    local value

    # Reset enrichment fields.
    printf -v "${prefix}_MANUFACTURER" '%s' ""
    printf -v "${prefix}_TYPE" '%s' ""
    printf -v "${prefix}_OPERATOR" '%s' ""

    [[ -n "${icao}" ]] || return 0

    json="$(aircraft_hexdb_get "${icao}")" || return 0

    value="$(jq -r '.Manufacturer // empty' <<<"${json}")"
    printf -v "${prefix}_MANUFACTURER" '%s' "${value}"

    value="$(jq -r '.Type // empty' <<<"${json}")"
    printf -v "${prefix}_TYPE" '%s' "${value}"

    value="$(jq -r '.RegisteredOwners // empty' <<<"${json}")"
    printf -v "${prefix}_OPERATOR" '%s' "${value}"
}

# -----------------------------------------------------------------------------
# Collect aircraft
# -----------------------------------------------------------------------------

aircraft_collect() {

    local token
    local lamin
    local lomin
    local lamax
    local lomax
    local json
    local states_count

    token="$(aircraft_token_get)" || return 1

    read -r lamin lomin lamax lomax <<<"$(aircraft_bbox)"

    # -------------------------------------------------------------------------
    # First request
    # -------------------------------------------------------------------------

    json="$(
        aircraft_opensky_request \
            "${token}" \
            "${lamin}" \
            "${lomin}" \
            "${lamax}" \
            "${lomax}"
    )"

    # -------------------------------------------------------------------------
    # Token may have expired server-side before our local expiry time.
    #
    # If OpenSky rejects the token, obtain a fresh one and retry once.
    # -------------------------------------------------------------------------

    if [[ $? -ne 0 ]]; then

        rm -f "$(sw_cache_file "opensky.token")"

        token="$(aircraft_token_get)" || return 1

        json="$(
            aircraft_opensky_request \
                "${token}" \
                "${lamin}" \
                "${lomin}" \
                "${lamax}" \
                "${lomax}"
        )" || {

            sw_log_info \
                "${MODULE_NAME}" \
                "Error consultando OpenSky"

            return 1
        }
    fi

    states_count="$(
        jq -r '.states // [] | length' <<<"${json}"
    )"

    if [[ ! "${states_count}" =~ ^[0-9]+$ ]]; then

        sw_log_info \
            "${MODULE_NAME}" \
            "Respuesta inválida de OpenSky"

        return 1
    fi

    echo "$json" | jq . >"${CACHE_DIR}/opensky.json"

    # -------------------------------------------------------------------------
    # Reset current data
    # -------------------------------------------------------------------------

    AIRCRAFT_COUNT=0
    AIRCRAFT_INFO=0
    AIRCRAFT_1_CLOSE=0

    AIRCRAFT_1_ICAO=""
    AIRCRAFT_1_CALLSIGN=""
    AIRCRAFT_1_COUNTRY=""
    AIRCRAFT_1_DISTANCE=""
    AIRCRAFT_1_ALTITUDE=""
    AIRCRAFT_1_SPEED=""
    AIRCRAFT_1_TRACK=""

    AIRCRAFT_1_MANUFACTURER=""
    AIRCRAFT_1_TYPE=""
    AIRCRAFT_1_OPERATOR=""

    AIRCRAFT_2_ICAO=""
    AIRCRAFT_2_CALLSIGN=""
    AIRCRAFT_2_COUNTRY=""
    AIRCRAFT_2_DISTANCE=""
    AIRCRAFT_2_ALTITUDE=""
    AIRCRAFT_2_SPEED=""
    AIRCRAFT_2_TRACK=""

    AIRCRAFT_2_MANUFACTURER=""
    AIRCRAFT_2_TYPE=""
    AIRCRAFT_2_OPERATOR=""

    # -------------------------------------------------------------------------
    # Extract airborne aircraft.
    #
    # OpenSky state vector indexes:
    #
    # 0  ICAO24
    # 1  callsign
    # 2  origin country
    # 5  longitude
    # 6  latitude
    # 7  barometric altitude
    # 8  on ground
    # 9  velocity
    # 10 true track
    # -------------------------------------------------------------------------

    local aircraft_list

    aircraft_list="$(
        jq -r '
            (.states // [])
            | map(select(.[8] == false))
            | .[]
            | [
                .[0],
                (.[1] // "" | gsub("^\\s+|\\s+$"; "")),
                (.[2] // ""),
                .[5],
                .[6],
                (.[7] // null),
                (.[9] // null),
                (.[10] // null)
            ]
            | @tsv
        ' <<<"${json}"
    )"

    # No airborne aircraft.
    [[ -n "${aircraft_list}" ]] || {
        MODULE_INTERVAL=180
        return 0
    }

    # -------------------------------------------------------------------------
    # Calculate distances
    # -------------------------------------------------------------------------

    local sorted_list=""

    local icao
    local callsign
    local country
    local lon
    local lat
    local altitude
    local speed
    local track
    local distance

    while IFS=$'\t' read -r \
        icao \
        callsign \
        country \
        lon \
        lat \
        altitude \
        speed \
        track; do

        [[ -n "${lat}" && -n "${lon}" ]] || continue

        distance="$(
            aircraft_distance_km "${lat}" "${lon}"
        )"

        [[ "${distance}" =~ ^[0-9]+([.][0-9]+)?$ ]] || continue

        sorted_list+="${distance}"$'\t'"${icao}"$'\t'"${callsign}"$'\t'"${country}"$'\t'"${altitude}"$'\t'"${speed}"$'\t'"${track}"$'\n'

    done <<<"${aircraft_list}"

    AIRCRAFT_COUNT="$(
        grep -c '.' <<<"${sorted_list}"
    )"

    [[ "${AIRCRAFT_COUNT}" =~ ^[0-9]+$ ]] || AIRCRAFT_COUNT=0

    ((AIRCRAFT_COUNT > 0)) || {
        MODULE_INTERVAL=180
        return 0
    }

    MODULE_INTERVAL=$MODULE_INTERVAL_IF_AIRCRAFTS

    # -------------------------------------------------------------------------
    # Sort by distance and keep only the two nearest.
    # -------------------------------------------------------------------------

    local index=0

    while IFS=$'\t' read -r \
        distance \
        icao \
        callsign \
        country \
        altitude \
        speed \
        track; do

        ((index++))

        if ((index == 1)); then

            AIRCRAFT_1_ICAO="${icao}"
            AIRCRAFT_1_CALLSIGN="${callsign}"
            AIRCRAFT_1_COUNTRY="${country}"
            AIRCRAFT_1_DISTANCE="${distance}"
            AIRCRAFT_1_ALTITUDE="${altitude}"
            AIRCRAFT_1_SPEED="${speed}"
            AIRCRAFT_1_TRACK="${track}"

        elif ((index == 2)); then

            AIRCRAFT_2_ICAO="${icao}"
            AIRCRAFT_2_CALLSIGN="${callsign}"
            AIRCRAFT_2_COUNTRY="${country}"
            AIRCRAFT_2_DISTANCE="${distance}"
            AIRCRAFT_2_ALTITUDE="${altitude}"
            AIRCRAFT_2_SPEED="${speed}"
            AIRCRAFT_2_TRACK="${track}"

            break
        fi

    done < <(
        printf '%s' "${sorted_list}" |
            sort -n -k1,1
    )

    # -------------------------------------------------------------------------
    # Only now query HexDB.
    #
    # This means a large OpenSky response produces at most two HexDB requests,
    # and usually fewer because aircraft information is cached.
    # -------------------------------------------------------------------------

    aircraft_enrich "AIRCRAFT_1" "${AIRCRAFT_1_ICAO}"

    if ((AIRCRAFT_COUNT >= 2)); then
        aircraft_enrich "AIRCRAFT_2" "${AIRCRAFT_2_ICAO}"
    fi

    # -------------------------------------------------------------------------
    # INFO is determined ONLY by the nearest aircraft.
    #
    # Both conditions must be satisfied:
    #
    #   distance <= AIRCRAFT_INFO_RADIUS_KM
    #   altitude <= AIRCRAFT_INFO_ALTITUDE_M
    #
    # If altitude is null, the aircraft cannot trigger INFO.
    # -------------------------------------------------------------------------

    if [[ "${AIRCRAFT_1_DISTANCE}" =~ ^[0-9]+([.][0-9]+)?$ &&
        "${AIRCRAFT_1_ALTITUDE}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then

        if awk \
            -v distance="${AIRCRAFT_1_DISTANCE}" \
            -v radius="${AIRCRAFT_INFO_RADIUS_KM}" \
            -v altitude="${AIRCRAFT_1_ALTITUDE}" \
            -v max_altitude="${AIRCRAFT_INFO_ALTITUDE_M}" '

            BEGIN {
                exit !(distance <= radius && altitude <= max_altitude)
            }
        '; then

            AIRCRAFT_INFO=1
            AIRCRAFT_1_CLOSE=1

        fi
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Analyze
# -----------------------------------------------------------------------------

aircraft_analyze() {

    AIRCRAFT_STATUS="${SW_STATUS_OK}"

    if ((AIRCRAFT_INFO == 1)); then
        AIRCRAFT_STATUS="${SW_STATUS_INFO}"
    fi
}

# -----------------------------------------------------------------------------
# Delete state keys
# -----------------------------------------------------------------------------

aircraft_delete_nearest_state() {

    sw_state_delete_key "nearest.title"

    sw_state_delete_key "nearest.icao"
    sw_state_delete_key "nearest.icao.label"
    sw_state_delete_key "nearest.icao.order"

    sw_state_delete_key "nearest.callsign"
    sw_state_delete_key "nearest.callsign.label"
    sw_state_delete_key "nearest.callsign.order"

    sw_state_delete_key "nearest.country"
    sw_state_delete_key "nearest.country.label"
    sw_state_delete_key "nearest.country.order"

    sw_state_delete_key "nearest.distance"
    sw_state_delete_key "nearest.distance.label"
    sw_state_delete_key "nearest.distance.unit"
    sw_state_delete_key "nearest.distance.order"

    sw_state_delete_key "nearest.altitude"
    sw_state_delete_key "nearest.altitude.label"
    sw_state_delete_key "nearest.altitude.unit"
    sw_state_delete_key "nearest.altitude.order"

    sw_state_delete_key "nearest.speed"
    sw_state_delete_key "nearest.speed.label"
    sw_state_delete_key "nearest.speed.unit"
    sw_state_delete_key "nearest.speed.order"

    sw_state_delete_key "nearest.track"
    sw_state_delete_key "nearest.track.label"
    sw_state_delete_key "nearest.track.unit"
    sw_state_delete_key "nearest.track.order"

    sw_state_delete_key "nearest.close"
    sw_state_delete_key "nearest.close.label"

    sw_state_delete_key "nearest.manufacturer"
    sw_state_delete_key "nearest.manufacturer.label"
    sw_state_delete_key "nearest.manufacturer.order"

    sw_state_delete_key "nearest.type"
    sw_state_delete_key "nearest.type.label"
    sw_state_delete_key "nearest.type.order"

    sw_state_delete_key "nearest.operator"
    sw_state_delete_key "nearest.operator.label"
    sw_state_delete_key "nearest.operator.order"
}

aircraft_delete_second_state() {

    sw_state_delete_key "second.title"

    sw_state_delete_key "second.icao"
    sw_state_delete_key "second.icao.label"
    sw_state_delete_key "second.icao.order"

    sw_state_delete_key "second.callsign"
    sw_state_delete_key "second.callsign.label"
    sw_state_delete_key "second.callsign.order"

    sw_state_delete_key "second.country"
    sw_state_delete_key "second.country.label"
    sw_state_delete_key "second.country.order"

    sw_state_delete_key "second.distance"
    sw_state_delete_key "second.distance.label"
    sw_state_delete_key "second.distance.unit"
    sw_state_delete_key "second.distance.order"

    sw_state_delete_key "second.altitude"
    sw_state_delete_key "second.altitude.label"
    sw_state_delete_key "second.altitude.unit"
    sw_state_delete_key "second.altitude.order"

    sw_state_delete_key "second.speed"
    sw_state_delete_key "second.speed.label"
    sw_state_delete_key "second.speed.unit"
    sw_state_delete_key "second.speed.order"

    sw_state_delete_key "second.track"
    sw_state_delete_key "second.track.label"
    sw_state_delete_key "second.track.unit"
    sw_state_delete_key "second.track.order"

    sw_state_delete_key "second.manufacturer"
    sw_state_delete_key "second.manufacturer.label"
    sw_state_delete_key "second.manufacturer.order"

    sw_state_delete_key "second.type"
    sw_state_delete_key "second.type.label"
    sw_state_delete_key "second.type.order"

    sw_state_delete_key "second.operator"
    sw_state_delete_key "second.operator.label"
    sw_state_delete_key "second.operator.order"
}

# -----------------------------------------------------------------------------
# Update state
# -----------------------------------------------------------------------------

aircraft_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "$(sw_translate "Aircraft")"
    sw_state_set "module.icon" "lucide/plane"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Count
    # -------------------------------------------------------------------------

    sw_state_set "count" "${AIRCRAFT_COUNT}"
    sw_state_set "count.label" "$(sw_translate "Total aircrafts")"
    sw_state_set "count.widget" "number"
    sw_state_set "count.order" "10"

    # -------------------------------------------------------------------------
    # No aircraft
    # -------------------------------------------------------------------------

    if ((AIRCRAFT_COUNT == 0)); then

        aircraft_delete_nearest_state
        aircraft_delete_second_state

        return 0
    fi

    # -------------------------------------------------------------------------
    # Nearest aircraft
    # -------------------------------------------------------------------------

    echo "$(date) pasa un avion" >> ~/scripts/syswatch/avioncitos.txt

    sw_state_set "nearest.title" "=========="
    sw_state_set "nearest.title.label" "$(sw_translate "Nearest")"
    sw_state_set "nearest.title.order" "20"

    sw_state_set "nearest.icao" "${AIRCRAFT_1_ICAO}"
    sw_state_set "nearest.icao.label" "$(sw_translate "ICAO")"
    sw_state_set "nearest.icao.order" "70"

    sw_state_set "nearest.callsign" "${AIRCRAFT_1_CALLSIGN}"
    sw_state_set "nearest.callsign.label" "$(sw_translate "Call Sign")"
    sw_state_set "nearest.callsign.order" "80"

    sw_state_set \
        "nearest.country" \
        "$(aircraft_country_display "${AIRCRAFT_1_COUNTRY}")"

    sw_state_set "nearest.country.label" "$(sw_translate "Country")"
    sw_state_set "nearest.country.order" "90"

    sw_state_set "nearest.distance" "${AIRCRAFT_1_DISTANCE}"
    sw_state_set "nearest.distance.label" "$(sw_translate "Distance")"
    sw_state_set "nearest.distance.unit" "km"
    sw_state_set "nearest.distance.order" "30"

    sw_state_set "nearest.altitude" "${AIRCRAFT_1_ALTITUDE}"
    sw_state_set "nearest.altitude.label" "$(sw_translate "Altitude")"
    sw_state_set "nearest.altitude.unit" "m"
    sw_state_set "nearest.altitude.order" "40"

    sw_state_set "nearest.speed" "${AIRCRAFT_1_SPEED}"
    sw_state_set "nearest.speed.label" "$(sw_translate "Speed")"
    sw_state_set "nearest.speed.unit" "m/s"
    sw_state_set "nearest.speed.order" "50"

    sw_state_set "nearest.track" "${AIRCRAFT_1_TRACK}"
    sw_state_set "nearest.track.label" "$(sw_translate "Track")"
    sw_state_set "nearest.track.unit" "°"
    sw_state_set "nearest.track.order" "60"

    if ((AIRCRAFT_1_CLOSE == 1)); then

        sw_state_set "nearest.close" "1"
        sw_state_set "nearest.close.label" "$(sw_translate "Más cercano")"
        sw_state_set "nearest.close.color" "blue"

    else

        sw_state_delete_key "nearest.close"
        sw_state_delete_key "nearest.close.label"

    fi

    # -------------------------------------------------------------------------
    # HexDB information
    # -------------------------------------------------------------------------

    if [[ -n "${AIRCRAFT_1_MANUFACTURER}" ]]; then

        sw_state_set "nearest.manufacturer" "${AIRCRAFT_1_MANUFACTURER}"
        sw_state_set "nearest.manufacturer.label" "$(sw_translate "Manufacturer")"
        sw_state_set "nearest.manufacturer.order" "95"

    else

        sw_state_delete_key "nearest.manufacturer"
        sw_state_delete_key "nearest.manufacturer.label"
        sw_state_delete_key "nearest.manufacturer.order"

    fi

    if [[ -n "${AIRCRAFT_1_TYPE}" ]]; then

        sw_state_set "nearest.type" "${AIRCRAFT_1_TYPE}"
        sw_state_set "nearest.type.label" "$(sw_translate "Type")"
        sw_state_set "nearest.type.order" "96"

    else

        sw_state_delete_key "nearest.type"
        sw_state_delete_key "nearest.type.label"
        sw_state_delete_key "nearest.type.order"

    fi

    if [[ -n "${AIRCRAFT_1_OPERATOR}" ]]; then

        sw_state_set "nearest.operator" "${AIRCRAFT_1_OPERATOR}"
        sw_state_set "nearest.operator.label" "$(sw_translate "Operator")"
        sw_state_set "nearest.operator.order" "97"

    else

        sw_state_delete_key "nearest.operator"
        sw_state_delete_key "nearest.operator.label"
        sw_state_delete_key "nearest.operator.order"

    fi

    # -------------------------------------------------------------------------
    # Second nearest aircraft
    # -------------------------------------------------------------------------

    if ((AIRCRAFT_COUNT >= 2)); then

        sw_state_set "second.title" "=========="
        sw_state_set "second.title.label" "$(sw_translate "Second nearest")"
        sw_state_set "second.title.order" "99"

        sw_state_set "second.icao" "${AIRCRAFT_2_ICAO}"
        sw_state_set "second.icao.label" "$(sw_translate "ICAO")"
        sw_state_set "second.icao.order" "140"

        sw_state_set "second.callsign" "${AIRCRAFT_2_CALLSIGN}"
        sw_state_set "second.callsign.label" "$(sw_translate "Call Sign")"
        sw_state_set "second.callsign.order" "150"

        sw_state_set \
            "second.country" \
            "$(aircraft_country_display "${AIRCRAFT_2_COUNTRY}")"

        sw_state_set "second.country.label" "$(sw_translate "Country")"
        sw_state_set "second.country.order" "160"

        sw_state_set "second.distance" "${AIRCRAFT_2_DISTANCE}"
        sw_state_set "second.distance.label" "$(sw_translate "Distance")"
        sw_state_set "second.distance.unit" "km"
        sw_state_set "second.distance.order" "100"

        sw_state_set "second.altitude" "${AIRCRAFT_2_ALTITUDE}"
        sw_state_set "second.altitude.label" "$(sw_translate "Altitude")"
        sw_state_set "second.altitude.unit" "m"
        sw_state_set "second.altitude.order" "110"

        sw_state_set "second.speed" "${AIRCRAFT_2_SPEED}"
        sw_state_set "second.speed.label" "$(sw_translate "Speed")"
        sw_state_set "second.speed.unit" "m/s"
        sw_state_set "second.speed.order" "120"

        sw_state_set "second.track" "${AIRCRAFT_2_TRACK}"
        sw_state_set "second.track.label" "$(sw_translate "Track")"
        sw_state_set "second.track.unit" "°"
        sw_state_set "second.track.order" "130"

        # ---------------------------------------------------------------------
        # HexDB information
        # ---------------------------------------------------------------------

        if [[ -n "${AIRCRAFT_2_MANUFACTURER}" ]]; then

            sw_state_set "second.manufacturer" "${AIRCRAFT_2_MANUFACTURER}"
            sw_state_set "second.manufacturer.label" "$(sw_translate "Manufacturer")"
            sw_state_set "second.manufacturer.order" "165"

        else

            sw_state_delete_key "second.manufacturer"
            sw_state_delete_key "second.manufacturer.label"
            sw_state_delete_key "second.manufacturer.order"

        fi

        if [[ -n "${AIRCRAFT_2_TYPE}" ]]; then

            sw_state_set "second.type" "${AIRCRAFT_2_TYPE}"
            sw_state_set "second.type.label" "$(sw_translate "Type")"
            sw_state_set "second.type.order" "166"

        else

            sw_state_delete_key "second.type"
            sw_state_delete_key "second.type.label"
            sw_state_delete_key "second.type.order"

        fi

        if [[ -n "${AIRCRAFT_2_OPERATOR}" ]]; then

            sw_state_set "second.operator" "${AIRCRAFT_2_OPERATOR}"
            sw_state_set "second.operator.label" "$(sw_translate "Operator")"
            sw_state_set "second.operator.order" "167"

        else

            sw_state_delete_key "second.operator"
            sw_state_delete_key "second.operator.label"
            sw_state_delete_key "second.operator.order"

        fi

    else

        aircraft_delete_second_state

    fi
}

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------

aircraft_report() {

    if ((AIRCRAFT_INFO == 1)); then

        sw_log_info \
            "${MODULE_NAME}" \
            "INFO: ${AIRCRAFT_1_CALLSIGN:-unknown} a ${AIRCRAFT_1_DISTANCE} km / ${AIRCRAFT_1_ALTITUDE} m"

    else

        sw_log_info \
            "${MODULE_NAME}" \
            "Aeronaves en vuelo: ${AIRCRAFT_COUNT}; próximas: ${AIRCRAFT_1_CALLSIGN:-ninguna}, ${AIRCRAFT_2_CALLSIGN:-ninguna}"

    fi
}

# -----------------------------------------------------------------------------
# Module entry point
# -----------------------------------------------------------------------------

sw_module_run() {

    sw_state_use "aircraft"
    sw_state_load

    local previous_status="${status:-${SW_STATUS_UNKNOWN}}"

    # -------------------------------------------------------------------------
    # Load countries map
    # -------------------------------------------------------------------------

    aircraft_load_countries

    # -------------------------------------------------------------------------
    # OpenSky failure
    # -------------------------------------------------------------------------

    if ! aircraft_collect; then

        AIRCRAFT_STATUS="${SW_STATUS_WARNING}"

        sw_status_update "${AIRCRAFT_STATUS}" || return 1

        aircraft_update_state
        sw_state_save

        sw_log_info \
            "${MODULE_NAME}" \
            "No se pudo actualizar OpenSky"

        return 0
    fi

    # -------------------------------------------------------------------------
    # Analyze
    # -------------------------------------------------------------------------

    aircraft_analyze

    # -------------------------------------------------------------------------
    # INFO timer
    #
    # Create it only when entering INFO.
    # Repeated calls reset the timer by design, so we deliberately do not
    # recreate it while the module remains in INFO.
    # -------------------------------------------------------------------------

    if [[ "${AIRCRAFT_STATUS}" == "${SW_STATUS_INFO}" &&
        "${previous_status}" != "${SW_STATUS_INFO}" ]]; then

        sw_timer_create "aircraft" "5" "statusok"

    fi

    # -------------------------------------------------------------------------
    # Status + state
    # -------------------------------------------------------------------------

    sw_status_update "${AIRCRAFT_STATUS}" || return 1

    aircraft_update_state
    sw_state_save

    aircraft_report
}
