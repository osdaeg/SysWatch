#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# funciones de timer para todos los scripts de syswatch
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

SW_TIMER_DONE=()
SW_TIMER_MODULE=""
SW_TIMER_STATE=""
SW_TIMER_FILE="${TIMER_DIR}/timers.txt"
TOTAL=""
ACTION=""
COUNT=""


# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# Timer helpers
# -----------------------------------------------------------------------------

sw_timer_create_raw() {

    local module=$1
    local dir=$2
    local total=$3
    local action=$4
    
    echo "${module}=TOTAL:${total}|ACTION:${action}|COUNT:${total}" > "${dir}/${module}.timer"

}

sw_timer_from_module() {

    local resultado

    resultado=$(( (MODULE_INTERVAL / 60) + 2 ))
    
    printf '%s' "$resultado"

}

sw_timer_state_file() {

    printf '%s/%s.state\n' \
        "${STATE_DIR}" \
        "${SW_TIMER_MODULE}"

}

sw_timer_use() {
    local key="$1"
    local state=""

    # Reset -- sin esto, si este timer no tiene línea propia todavía (o
    # no tiene .state), TOTAL/ACTION/COUNT quedarían con los valores del
    # ÚLTIMO timer que sí se haya cargado con éxito. Mismo mecanismo que
    # la contaminación de SW_STATE entre módulos, pero acá con variables
    # sueltas en vez de un array.
    TOTAL=""
    ACTION=""
    COUNT=""

    # 1. Verificar si el directorio y el archivo existen; si no, crearlos
    if [ ! -d "$TIMER_DIR" ]; then
        mkdir -p "$TIMER_DIR"
    fi
    if [ ! -f "$SW_TIMER_FILE" ]; then
        touch "$SW_TIMER_FILE"
    fi

    SW_TIMER_MODULE="$1"


    # comprueba si existe un .state asociado al timer
    state="$(sw_timer_state_file)"
    [[ -f "${state}" ]] || return 0
    SW_TIMER_STATE="${state}"


    # 2. Si no se pasa un argumento, salir silenciosamente
    if [ -z "$key" ]; then
        return 0
    fi

    # 3. Buscar la línea específica en el archivo (ej: modulo1=...)
    local line
    line=$(grep -E "^${key}=" "$SW_TIMER_FILE" 2>/dev/null)

    # 4. Si no se encuentra la línea, salir silenciosamente sin error
    if [ -z "$line" ]; then
        return 0
    fi

    # 5. Extraer la parte del contenido después del signo '='
    local content
    content="${line#*=}"

    # 6. Procesar los pares separados por '|'
    local old_ifs="$IFS"
    IFS='|'
    for par in $content; do
        IFS=':' read -r clave valor <<< "$par"

        # Asignar a las variables globales requeridas según la clave
        case "$clave" in
            TOTAL)  TOTAL="$valor" ;;
            ACTION) ACTION="$valor" ;;
            COUNT)  COUNT="$valor" ;;
        esac
    done
    IFS="$old_ifs"
}

sw_timer_delete() {
    local key="$SW_TIMER_MODULE"

    if [ -s "$SW_TIMER_FILE" ]; then
        sed -i "/^${key}=/d" "$SW_TIMER_FILE"
    fi
}

sw_timer_update() {

    COUNT=$((COUNT - 1))

    if [ "$COUNT" -le 0 ]; then
        return 1
    fi
    return 0

}

sw_timer_reset() {

    COUNT=$TOTAL

}

sw_timer_save() {

    local line="${SW_TIMER_MODULE}=TOTAL:${TOTAL}|ACTION:${ACTION}|COUNT:${COUNT}"

    if [ -z "$SW_TIMER_MODULE" ]; then
        return 0
    fi

    # grep -v + append instead of 'sed s|old|new|': the replacement text
    # always contains '|' itself (it's our own field separator), which
    # collides with sed's delimiter and breaks the substitution silently
    # -- sed just fails with a syntax error, and the line never actually
    # gets updated. This approach has no delimiter to collide with, and
    # handles "replace if present" and "add if missing" in one pass.
    local tmp_file="${SW_TIMER_FILE}.tmp"

    grep -v "^${SW_TIMER_MODULE}=" "$SW_TIMER_FILE" > "$tmp_file" 2>/dev/null || true

    echo "$line" >> "$tmp_file"

    mv "$tmp_file" "$SW_TIMER_FILE"

}

sw_timer_get() {

    printf '%s\n' "${COUNT}"

}

sw_timer_update_all() {

    local archivo_temporal="${TIMER_DIR}/timers.tmp"

    # 1. Validar que el archivo exista y no esté vacío
    if [ ! -f "$SW_TIMER_FILE" ] || [ ! -s "$SW_TIMER_FILE" ]; then
        return 0
    fi

    # Limpiar o crear el archivo temporal para esta ejecución
    > "$archivo_temporal"

    # 2. Leer el archivo línea por línea de forma segura
    while IFS= read -r line || [ -n "$line" ]; do
        # Omitir líneas vacías
        [ -z "$line" ] && continue

        # Separar el módulo del contenido de datos
        local modulo="${line%%=*}"
        local datos="${line#*=}"

        # Inicializar variables para extraer los componentes internos
        local v_time="" v_action="" v_count=""
        local old_ifs="$IFS"

        # Parsear las claves internas
        IFS='|'
        for par in $datos; do
            IFS=':' read -r clave valor <<< "$par"
            case "$clave" in
                TOTAL)  v_time="$valor" ;;
                ACTION) v_action="$valor" ;;
                COUNT)  v_count="$valor" ;;
            esac
        done
        IFS="$old_ifs"

        # 3. Restar 1 al valor de COUNT
        local new_count=$((v_count - 1))

        # 4. Evaluar el estado del contador
        if [ "$new_count" -le 0 ]; then
            # Si expira, se agrega la combinación "MODULO:ACTION" al array global
            SW_TIMER_DONE+=("${modulo}:${v_action}")
            # Al no escribir esta línea en el temporal, efectivamente queda BORRADA
        else
            # Si sigue activo, se arma la cadena actualizada y se guarda en el temporal
            local new_line="${modulo}=TOTAL:${v_time}|ACTION:${v_action}|COUNT:${new_count}"
            echo "$new_line" >> "$archivo_temporal"
        fi

    done < "$SW_TIMER_FILE"

    # 5. Reemplazar el archivo original con la versión actualizada
    mv "$archivo_temporal" "$SW_TIMER_FILE"
}

sw_timer_create() {
    local modulo="$1"
    local total="$2"
    local action="${3,,}"
    local state=""

    # 1. Asegurar la existencia del directorio y el archivo (soporta tmpfs)
    if [ ! -d "$TIMER_DIR" ]; then
        mkdir -p "$TIMER_DIR"
    fi
    if [ ! -f "$SW_TIMER_FILE" ]; then
        touch "$SW_TIMER_FILE"
    fi

    SW_TIMER_MODULE="$1"

    # A diferencia de sw_timer_use(), crear un timer NO requiere que el
    # .state asociado ya exista -- el módulo puede crear el timer y
    # recién después escribir su propio .state en la misma corrida.
    state="$(sw_timer_state_file)"
    SW_TIMER_STATE="${state}"

    # 2. Validar que los parámetros mínimos obligatorios no estén vacíos
    if [ -z "$modulo" ] || [ -z "$total" ] || [ -z "$action" ]; then
        return 1
    fi

    case "$action" in
        statusok|statuswarning|statuscritical|deletestate|statusinfo)
            # Acción válida, continuar con el script
            ;;
        *)
            return 1
            ;;
    esac

    # 3. Armar la cadena con el formato solicitado
    # Usamos COUNT con el valor inicial de $total ($2)
    local nueva_linea="${modulo}=TOTAL:${total}|ACTION:${action}|COUNT:${total}"

    # 4. Reemplazar si ya existe, agregar si no -- grep -v + append en
    # vez de 'sed s|old|new|', que rompe porque nueva_linea siempre
    # contiene '|' (nuestro propio separador de campos), colisionando
    # con el delimitador de sed.
    local tmp_file="${SW_TIMER_FILE}.tmp"

    grep -v "^${modulo}=" "$SW_TIMER_FILE" > "$tmp_file" 2>/dev/null || true

    echo "$nueva_linea" >> "$tmp_file"

    mv "$tmp_file" "$SW_TIMER_FILE"
}

sw_timer_actions() {
    printf '%s\n' "${SW_TIMER_DONE[@]}"
}
