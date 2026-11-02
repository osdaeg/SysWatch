#!/bin/bash

swdir="/home/daniel/scripts/syswatch"
cachedir="${swdir}/cache"
remotedir="${swdir}/remote"

remotes=$(
    source $swdir/.env
    echo "$REMOTES"
)

user=$USER

read -p "Introduce tu nombre [$user]: " name

name="${name:-$user}"

read -r -p "Escribe el mensaje: " message

IFS=',' read -ra options <<<"$remotes"

for i in "${!options[@]}"; do
    options[$i]=$(echo "${options[$i]}" | xargs)
done

options=("Ninguno" "${options[@]}")

echo "Por favor, elige una opción:"

select remote in "${options[@]}"; do
    if [[ -n "$remote" ]]; then
        if [[ "$remote" == "Ninguno" ]]; then
            echo "Has decidido no elegir ninguna opción."
            remote=""
            break
        else
            echo "Has elegido: $remote"
            break
        fi
    else
        echo "Opción no válida. Por favor, elige un número del 0 al $((${#options[@]} - 1))."
    fi
done

timestamp="$(date +"%d/%m/%Y %H:%M:%S")"
hostname=$(hostname)

echo "==============================================================="
echo "From: $name"
echo "Date: $timestamp"
echo "Message: $message"
echo "Remote: $remote"
echo "==============================================================="

while true; do
    read -p "¿Estás seguro de que deseas continuar? (s/n): " response

    case $response in
    [sS]*)
        echo "Enviando mensaje..."
file="${cachedir}/$(date +%s%N).message"

{
    printf 'hostname=%s\n' "$(printf '%s' "$hostname" | base64 -w 0)"
    printf 'sender=%s\n' "$(printf '%s' "$name" | base64 -w 0)"
    printf 'date=%s\n' "$(printf '%s' "$timestamp" | base64 -w 0)"
    printf 'message=%s\n' "$(printf '%s' "$message" | base64 -w 0)"
} > "$file" || {
    echo "Error al crear el mensaje."
    exit 1
}

if [[ -n "$remote" ]]; then
    cp "$file" "${remotedir}/${remote}/" || {
        echo "Error al copiar el mensaje al remoto."
        exit 1
    }
fi
        break
        ;;
    [nN]*)
        echo "Operación cancelada."
        exit 0
        ;;
    *)
        echo "Por favor, responde 's' (sí) o 'n' (no)."
        ;;
    esac
done
