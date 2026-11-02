#!/bin/bash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

AUTH="acalaclavequeconfigurasteenopensmn"
BASE1="http://localhost:6942/smn/v1/weather/location"
BASE2="http://localhost:6942/smn/v1/forecast/location"
LOCATION=3884
CACHE_DIR="/home/usuario/scripts/syswatch/cache/o/donde/este/el/cache/de/syswatch"
ACTUAL="$CACHE_DIR/actual.json"
FORECAST="$CACHE_DIR/forecast.json"
CAP_TMP_DIR="${TMPDIR:-/tmp}/syswatch-cap"
CAP_RELEVANT_DIR="$CAP_TMP_DIR/relevant"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WEATHER_LAT=-35.81081
WEATHER_LON=-61.89897

json=$(curl -s \
    -H "Authorization: ${AUTH}" \
    "${BASE1}/${LOCATION}")

echo "$json" | jq >"$ACTUAL"

json=$(curl -s \
    -H "Authorization: ${AUTH}" \
    "${BASE2}/${LOCATION}")

echo "$json" | jq >"$FORECAST"

curl -L -o "${SCRIPT_DIR}/avisos.xml" \
    "https://ssl.smn.gob.ar/feeds/CAP/rss_alertaCAP_nuevo_2026.xml"

curl -L -o "${SCRIPT_DIR}/oladecalor.xml" \
    "https://ssl.smn.gob.ar/feeds/CAP/oladecalor/rss_ola_calor_nuevo.xml"

curl -L -o "${SCRIPT_DIR}/cortoplazo.xml" \
    "https://ssl.smn.gob.ar/feeds/CAP/avisocortoplazo/rss_acpCAP.xml"

curl -L -o "${SCRIPT_DIR}/muycortoplazo.rss" \
    "https://ssl.smn.gob.ar/CAP/AR.php"

XML_ORIGEN="${SCRIPT_DIR}/avisos.xml"

echo "Buscando enlaces XML..."

# ---------------------------------------------------------------------------
# Obtener los CAP actualmente publicados.
# ---------------------------------------------------------------------------

declare -A CAP_ACTUALES=()

while IFS= read -r url; do

    [[ "$url" == *.xml* ]] || continue

    cap_file="$(basename "$url")"
    CAP_ACTUALES["$cap_file"]=1

    if [[ -f "${SCRIPT_DIR}/${cap_file}" ]]; then
        echo "CAP existente: $cap_file"
    else
        echo "Descargando: $url"
        curl -s "$url" >"${SCRIPT_DIR}/${cap_file}"
    fi

done < <(
    grep -oP '(?<=<link>)[^<]+(?=</link>)' "$XML_ORIGEN"
)

# ---------------------------------------------------------------------------
# Eliminar CAP que ya no figuran en avisos.xml.
# ---------------------------------------------------------------------------

find "$SCRIPT_DIR" \
    -maxdepth 1 \
    -type f \
    -name 'CAP*.xml' \
    -print0 |
while IFS= read -r -d '' xml; do

    cap_file="$(basename "$xml")"

    if [[ -z "${CAP_ACTUALES[$cap_file]+x}" ]]; then
        echo "Eliminando CAP obsoleto: $cap_file"
        rm -f -- "$xml"
    fi

done

echo "¡Proceso finalizado! Los archivos están en la carpeta '$CACHE_DIR'."

#WEATHER_LAT=-30.11
#WEATHER_LON=-58.27

# ---------------------------------------------------------------------------
# Comprueba si un punto está dentro de un polígono.
#
# $1 = latitud del punto
# $2 = longitud del punto
# $3 = polígono: "lat,lon lat,lon ..."
#
# 0 = dentro
# 1 = fuera
# ---------------------------------------------------------------------------

sw_cleanup_cap_xml() {

    local cache_dir="${SCRIPT_DIR}"
    local tmp_dir="${CAP_TMP_DIR:-/tmp/syswatch-cap}"
    local relevant_dir="${CAP_RELEVANT_DIR:-${tmp_dir}/relevant}"

    local weather_lat="${WEATHER_LAT}"
    local weather_lon="${WEATHER_LON}"

    local xml
    local polygon
    local found=0

    # -------------------------------------------------------------------------
    # Preparar directorio temporal
    # -------------------------------------------------------------------------

    mkdir -p "$relevant_dir" || {
        echo "ERROR: No se pudo crear: $relevant_dir" >&2
        return 1
    }

    # Limpiar resultados anteriores.
    find "$relevant_dir" \
        -maxdepth 1 \
        -type f \
        -name 'CAP*.xml' \
        -delete

    # -------------------------------------------------------------------------
    # Comprueba si un punto está dentro de un polygon completo.
    #
    # $1 = latitud
    # $2 = longitud
    # $3 = "lat,lon lat,lon lat,lon ..."
    #
    # 0 = dentro
    # 1 = fuera
    #
    # También considera dentro los puntos que caen exactamente sobre el borde.
    # -------------------------------------------------------------------------

    sw_point_in_polygon() {

        local point_lat="$1"
        local point_lon="$2"
        local polygon="$3"

        awk \
            -v y="$point_lat" \
            -v x="$point_lon" \
            -v poly="$polygon" '
            BEGIN {

                n = split(poly, p, " ")

                inside = 0
                j = n

                for (i = 1; i <= n; i++) {

                    split(p[i], a, ",")
                    xi = a[2]
                    yi = a[1]

                    split(p[j], b, ",")
                    xj = b[2]
                    yj = b[1]

                    # Punto sobre el segmento
                    cross = (x - xi) * (yj - yi) - (y - yi) * (xj - xi)

                    if (cross == 0) {

                        if (x >= (xi < xj ? xi : xj) &&
                            x <= (xi > xj ? xi : xj) &&
                            y >= (yi < yj ? yi : yj) &&
                            y <= (yi > yj ? yi : yj)) {

                            exit 0
                        }
                    }

                    # Ray casting
                    if (((yi > y) != (yj > y)) &&
                        (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) {

                        inside = !inside
                    }

                    j = i
                }

                exit !inside
            }'
    }

    # -------------------------------------------------------------------------
    # Recorrer CAP*.xml
    # -------------------------------------------------------------------------

    while IFS= read -r -d '' xml; do

        found=0

        # ---------------------------------------------------------------------
        # Extraer TODOS los <polygon> del XML.
        #
        # Cada polygon es un polígono completo.
        # ---------------------------------------------------------------------

        while IFS= read -r polygon; do

            # Normalizar espacios.
            polygon=$(
                printf '%s\n' "$polygon" |
                    tr '\n\r\t' '   ' |
                    sed 's/  */ /g; s/^ //; s/ $//'
            )

            # -----------------------------------------------------------------
            # Comprobar el polygon COMPLETO.
            # -----------------------------------------------------------------

            if sw_point_in_polygon \
                "$weather_lat" \
                "$weather_lon" \
                "$polygon"; then

                found=1

                echo
                echo "CAP OK: $xml"
                echo "  Punto: $weather_lat,$weather_lon"
                echo "  Polygon contiene el punto."
                echo "  Copiando a: $relevant_dir"

                cp -- "$xml" "$relevant_dir/" || {
                    echo "ERROR: No se pudo copiar: $xml" >&2
                    return 1
                }

                break

            fi

        done < <(
            awk '
                BEGIN {
                    RS = "</polygon>"
                }

                /<polygon[^>]*>/ {

                    block = $0

                    sub(/^.*<polygon[^>]*>/, "", block)

                    gsub(/\n/, " ", block)
                    gsub(/\r/, " ", block)
                    gsub(/[[:space:]]+/, " ", block)

                    sub(/^ /, "", block)
                    sub(/ $/, "", block)

                    print block
                }
            ' "$xml"
        )

        # ---------------------------------------------------------------------
        # Si ningún polygon contiene el punto, no hacer nada.
        #
        # El CAP ORIGINAL permanece en el cache.
        # ---------------------------------------------------------------------

        if ((!found)); then

            echo "CAP FUERA: $xml"

        fi

    done < <(
        find "$cache_dir" \
            -maxdepth 1 \
            -type f \
            -name 'CAP*.xml' \
            -print0
    )

    return 0
}

sw_cap_extract_info() {

    local xml="$1"
    local content

    CAP_HEADLINE=""
    CAP_DESCRIPTION=""
    CAP_INSTRUCTION=""

    CAP_URGENCY=""
    CAP_SEVERITY=""
    CAP_CERTAINTY=""

    CAP_SENT=""
    CAP_ONSET=""
    CAP_EXPIRES=""

    [[ -f "$xml" ]] || return 1

    # -------------------------------------------------------------------------
    # El XML puede contener saltos de línea entre las etiquetas.
    # Lo convertimos temporalmente en una sola línea.
    # -------------------------------------------------------------------------

    content=$(
        tr '\n\r\t' '   ' <"$xml" |
            sed 's/  */ /g'
    )

    # -------------------------------------------------------------------------
    # Extraer información.
    # -------------------------------------------------------------------------

    CAP_HEADLINE="${content#*<headline>}"
    CAP_HEADLINE="${CAP_HEADLINE%%</headline>*}"

    CAP_DESCRIPTION="${content#*<description>}"
    CAP_DESCRIPTION="${CAP_DESCRIPTION%%</description>*}"

    CAP_INSTRUCTION="${content#*<instruction>}"
    CAP_INSTRUCTION="${CAP_INSTRUCTION%%</instruction>*}"

    CAP_URGENCY="${content#*<urgency>}"
    CAP_URGENCY="${CAP_URGENCY%%</urgency>*}"

    CAP_SEVERITY="${content#*<severity>}"
    CAP_SEVERITY="${CAP_SEVERITY%%</severity>*}"

    CAP_CERTAINTY="${content#*<certainty>}"
    CAP_CERTAINTY="${CAP_CERTAINTY%%</certainty>*}"

    CAP_SENT="${content#*<sent>}"
    CAP_SENT="${CAP_SENT%%</sent>*}"

    CAP_ONSET="${content#*<onset>}"
    CAP_ONSET="${CAP_ONSET%%</onset>*}"

    CAP_EXPIRES="${content#*<expires>}"
    CAP_EXPIRES="${CAP_EXPIRES%%</expires>*}"

    # -------------------------------------------------------------------------
    # Decodificar entidades XML.
    # -------------------------------------------------------------------------

    CAP_HEADLINE=$(
        printf '%s' "$CAP_HEADLINE" |
            sed \
                -e 's/&#xE1;/á/g' \
                -e 's/&#xE9;/é/g' \
                -e 's/&#xED;/í/g' \
                -e 's/&#xF3;/ó/g' \
                -e 's/&#xFA;/ú/g' \
                -e 's/&#xFC;/ü/g' \
                -e 's/&#xC1;/Á/g' \
                -e 's/&#xC9;/É/g' \
                -e 's/&#xCD;/Í/g' \
                -e 's/&#xD3;/Ó/g' \
                -e 's/&#xDA;/Ú/g' \
                -e 's/&#xDC;/Ü/g' \
                -e 's/&#xF1;/ñ/g' \
                -e 's/&#xD1;/Ñ/g'
    )

    CAP_DESCRIPTION=$(
        printf '%s' "$CAP_DESCRIPTION" |
            sed \
                -e 's/&#xE1;/á/g' \
                -e 's/&#xE9;/é/g' \
                -e 's/&#xED;/í/g' \
                -e 's/&#xF3;/ó/g' \
                -e 's/&#xFA;/ú/g' \
                -e 's/&#xFC;/ü/g' \
                -e 's/&#xC1;/Á/g' \
                -e 's/&#xC9;/É/g' \
                -e 's/&#xCD;/Í/g' \
                -e 's/&#xD3;/Ó/g' \
                -e 's/&#xDA;/Ú/g' \
                -e 's/&#xDC;/Ü/g' \
                -e 's/&#xF1;/ñ/g' \
                -e 's/&#xD1;/Ñ/g'
    )

    CAP_INSTRUCTION=$(
        printf '%s' "$CAP_INSTRUCTION" |
            sed \
                -e 's/&#xE1;/á/g' \
                -e 's/&#xE9;/é/g' \
                -e 's/&#xED;/í/g' \
                -e 's/&#xF3;/ó/g' \
                -e 's/&#xFA;/ú/g' \
                -e 's/&#xFC;/ü/g' \
                -e 's/&#xC1;/Á/g' \
                -e 's/&#xC9;/É/g' \
                -e 's/&#xCD;/Í/g' \
                -e 's/&#xD3;/Ó/g' \
                -e 's/&#xDA;/Ú/g' \
                -e 's/&#xDC;/Ü/g' \
                -e 's/&#xF1;/ñ/g' \
                -e 's/&#xD1;/Ñ/g'
    )

    return 0
}

sw_cap_match_short_term() {

    local xml="$1"
    local short_term_xml="$2"
    local cap_name
    local content
    local item
    local link
    local description
    local title

    CAP_SHORT_TERM=false
    CAP_SHORT_TERM_TITLE=""
    CAP_SHORT_TERM_DESCRIPTION=""

    [[ -f "$xml" ]] || return 1
    [[ -f "$short_term_xml" ]] || return 1

    cap_name="$(basename "$xml")"

    # -------------------------------------------------------------------------
    # Convertir el XML de corto plazo en una línea por <item>.
    # -------------------------------------------------------------------------

    content=$(
        tr '\n\r\t' '   ' <"$short_term_xml" |
            sed 's/  */ /g; s/<item>/\n<item>/g'
    )

    while IFS= read -r item; do

        [[ "$item" == *"$cap_name"* ]] || continue

        # ---------------------------------------------------------------------
        # Encontramos el CAP.
        # ---------------------------------------------------------------------

        CAP_SHORT_TERM=true

        # ---------------------------------------------------------------------
        # Extraer title.
        # ---------------------------------------------------------------------

        title="${item#*<title>}"
        title="${title%%</title>*}"

        # ---------------------------------------------------------------------
        # Extraer description.
        # ---------------------------------------------------------------------

        description="${item#*<description>}"
        description="${description%%</description>*}"

        CAP_SHORT_TERM_TITLE="$title"
        CAP_SHORT_TERM_DESCRIPTION="$description"

        # ---------------------------------------------------------------------
        # Decodificar entidades XML.
        # ---------------------------------------------------------------------

        CAP_SHORT_TERM_TITLE=$(
            printf '%s' "$CAP_SHORT_TERM_TITLE" |
                sed \
                    -e 's/&#xE1;/á/g' \
                    -e 's/&#xE9;/é/g' \
                    -e 's/&#xED;/í/g' \
                    -e 's/&#xF3;/ó/g' \
                    -e 's/&#xFA;/ú/g' \
                    -e 's/&#xFC;/ü/g' \
                    -e 's/&#xC1;/Á/g' \
                    -e 's/&#xC9;/É/g' \
                    -e 's/&#xCD;/Í/g' \
                    -e 's/&#xD3;/Ó/g' \
                    -e 's/&#xDA;/Ú/g' \
                    -e 's/&#xDC;/Ü/g' \
                    -e 's/&#xF1;/ñ/g' \
                    -e 's/&#xD1;/Ñ/g'
        )

        CAP_SHORT_TERM_DESCRIPTION=$(
            printf '%s' "$CAP_SHORT_TERM_DESCRIPTION" |
                sed \
                    -e 's/&#xE1;/á/g' \
                    -e 's/&#xE9;/é/g' \
                    -e 's/&#xED;/í/g' \
                    -e 's/&#xF3;/ó/g' \
                    -e 's/&#xFA;/ú/g' \
                    -e 's/&#xFC;/ü/g' \
                    -e 's/&#xC1;/Á/g' \
                    -e 's/&#xC9;/É/g' \
                    -e 's/&#xCD;/Í/g' \
                    -e 's/&#xD3;/Ó/g' \
                    -e 's/&#xDA;/Ú/g' \
                    -e 's/&#xDC;/Ü/g' \
                    -e 's/&#xF1;/ñ/g' \
                    -e 's/&#xD1;/Ñ/g'
        )

        return 0

    done <<<"$content"

    return 0
}

sw_cap_analyze() {

    CAP_STATUS="OK"
    CAP_STATUS_REASON=""

    case "$CAP_SEVERITY" in
    Extreme | Severe)
        CAP_STATUS="CRITICAL"
        CAP_STATUS_REASON="severity=$CAP_SEVERITY"
        ;;

    Moderate)
        CAP_STATUS="WARNING"
        CAP_STATUS_REASON="severity=$CAP_SEVERITY"
        ;;

    Minor)
        CAP_STATUS="OK"
        CAP_STATUS_REASON="severity=$CAP_SEVERITY"
        ;;

    *)
        CAP_STATUS="OK"
        CAP_STATUS_REASON="severity=unknown"
        ;;
    esac

    # -------------------------------------------------------------------------
    # Un aviso de muy corto plazo refuerza la situación.
    # -------------------------------------------------------------------------

    if [[ "$CAP_SHORT_TERM" == "true" ]]; then

        case "$CAP_STATUS" in
        NORMAL)
            CAP_STATUS="WARNING"
            CAP_STATUS_REASON="${CAP_STATUS_REASON};short_term=true"
            ;;

        WARNING)
            CAP_STATUS="CRITICAL"
            CAP_STATUS_REASON="${CAP_STATUS_REASON};short_term=true"
            ;;
        esac

    fi

    return 0
}

sw_cap_generate_json() {

    local cap_dir="$1"
    local short_term_xml="$2"
    local output="$3"

    local xml

    [[ -d "$cap_dir" ]] || return 1
    [[ -f "$short_term_xml" ]] || return 1

    command -v jq >/dev/null 2>&1 || {
        echo "ERROR: jq no está instalado" >&2
        return 1
    }

    # -------------------------------------------------------------------------
    # JSON inicial
    # -------------------------------------------------------------------------

    printf '%s\n' '{"alerts":[]}' >"$output"

    # -------------------------------------------------------------------------
    # Procesar CAPs
    # -------------------------------------------------------------------------

    for xml in "$cap_dir"/CAP*.xml; do

        [[ -f "$xml" ]] || continue

        # ---------------------------------------------------------------------
        # Extraer información del CAP
        # ---------------------------------------------------------------------

        sw_cap_extract_info "$xml" || continue

        # ---------------------------------------------------------------------
        # Buscar coincidencia en muycortoplazo.rss
        # ---------------------------------------------------------------------

        sw_cap_match_short_term \
            "$xml" \
            "$short_term_xml" || continue

        # ---------------------------------------------------------------------
        # Analizar severidad
        # ---------------------------------------------------------------------

        sw_cap_analyze || continue

        # ---------------------------------------------------------------------
        # Construir objeto JSON
        # ---------------------------------------------------------------------

        jq \
            --arg file "$(basename "$xml")" \
            --arg headline "$CAP_HEADLINE" \
            --arg description "$CAP_DESCRIPTION" \
            --arg instruction "$CAP_INSTRUCTION" \
            --arg urgency "$CAP_URGENCY" \
            --arg severity "$CAP_SEVERITY" \
            --arg certainty "$CAP_CERTAINTY" \
            --arg short_term_description "$CAP_SHORT_TERM_DESCRIPTION" \
            --arg status "$CAP_STATUS" \
            --arg status_reason "$CAP_STATUS_REASON" \
            --arg sent "$CAP_SENT" \
            --arg onset "$CAP_ONSET" \
            --arg expires "$CAP_EXPIRES" \
            --argjson short_term "$CAP_SHORT_TERM" \
            '
            .alerts += [{
                file: $file,
                headline: $headline,
                description: $description,
                instruction: $instruction,
                urgency: $urgency,
                severity: $severity,
                certainty: $certainty,
                short_term: $short_term,
                status: $status,
                sent: $sent,
onset: $onset,
expires: $expires,
                status_reason: $status_reason
            }
            + (
                if $short_term and
                   $short_term_description != "" and
                   $short_term_description != $description
                then
                    {
                        short_term_description: $short_term_description
                    }
                else
                    {}
                end
            )]
            ' \
            "$output" >"${output}.tmp" || return 1

        mv -- "${output}.tmp" "$output"

    done

    return 0
}

sw_cap_global_status() {

    local json="$1"

    CAP_GLOBAL_STATUS="NORMAL"
    CAP_GLOBAL_REASON=""
    CAP_GLOBAL_HEADLINE=""
    CAP_GLOBAL_EXPIRES=""
    CAP_GLOBAL_COUNT=0

    [[ -f "$json" ]] || return 1

    command -v jq >/dev/null 2>&1 || {
        echo "ERROR: jq no está instalado" >&2
        return 1
    }

    # -------------------------------------------------------------------------
    # Hora actual en epoch
    # -------------------------------------------------------------------------

    local now

    now="$(date +%s)" || return 1

    # -------------------------------------------------------------------------
    # Recorrer alertas y determinar el mayor estado vigente.
    # -------------------------------------------------------------------------

    local status
    local reason
    local headline
    local expires
    local expires_epoch
    local priority
    local best_priority=0

    while IFS=$'\t' read -r status reason headline expires; do

        [[ -n "$status" ]] || continue

        # -------------------------------------------------------------
        # Convertir expires ISO-8601 -> epoch
        # -------------------------------------------------------------

        expires_epoch="$(date -d "$expires" +%s 2>/dev/null)" || {
            echo "WARNING: fecha expires inválida: $expires" >&2
            continue
        }

        # -------------------------------------------------------------
        # Ignorar alertas vencidas
        # -------------------------------------------------------------

        if ((expires_epoch <= now)); then
            continue
        fi

        # -------------------------------------------------------------
        # Prioridad del estado
        # -------------------------------------------------------------

        case "$status" in
        CRITICAL)
            priority=3
            ;;
        WARNING)
            priority=2
            ;;
        *)
            priority=1
            ;;
        esac

        # -------------------------------------------------------------
        # Quedarnos con la alerta de mayor prioridad
        # -------------------------------------------------------------

        if ((priority > best_priority)); then

            best_priority="$priority"

            CAP_GLOBAL_STATUS="$status"
            CAP_GLOBAL_REASON="$reason"
            CAP_GLOBAL_HEADLINE="$headline"
            CAP_GLOBAL_EXPIRES="$expires"

        fi

        ((CAP_GLOBAL_COUNT++))

    done < <(
        jq -r '
            .alerts[]
            | [
                (.status // "NORMAL"),
                (.status_reason // ""),
                (.headline // ""),
                (.expires // "")
            ]
            | @tsv
        ' "$json"
    )

    return 0
}

sw_cap_run() {

    local cache_dir="${CACHE_DIR}"
    local relevant_dir="${CAP_RELEVANT_DIR:-/tmp/syswatch-cap/relevant}"
    local short_term_rss="$SCRIPT_DIR/muycortoplazo.rss"
    local output="$cache_dir/cap_alerts.json"

    # -------------------------------------------------------------------------
    # 1. Filtrar CAP por coordenadas
    # -------------------------------------------------------------------------

    sw_cleanup_cap_xml || return 1

    # -------------------------------------------------------------------------
    # 2. Generar JSON solamente con los CAP relevantes
    # -------------------------------------------------------------------------

    sw_cap_generate_json \
        "$relevant_dir" \
        "$short_term_rss" \
        "$output" || return 1

    # -------------------------------------------------------------------------
    # 3. Determinar estado global
    # -------------------------------------------------------------------------

    sw_cap_global_status \
        "$output" || return 1

    return 0
}

sw_cap_run

echo
echo "STATUS:   $CAP_GLOBAL_STATUS"
echo "REASON:   $CAP_GLOBAL_REASON"
echo "HEADLINE: $CAP_GLOBAL_HEADLINE"
echo "EXPIRES:  $CAP_GLOBAL_EXPIRES"
echo "COUNT:    $CAP_GLOBAL_COUNT"
