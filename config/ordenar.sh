#!/bin/bash

# Nombre del archivo original y del archivo de salida
ARCHIVO_ENTRADA="modules.conf"
ARCHIVO_SALIDA="modules_viejo.conf"

# Verificar si el archivo existe
if [ ! -f "$ARCHIVO_ENTRADA" ]; then
    echo "Error: El archivo $ARCHIVO_ENTRADA no existe."
    exit 1
fi

cp "$ARCHIVO_ENTRADA" "$ARCHIVO_SALIDA"

# Ordenar por el segundo campo usando '|' como delimitador
sort -t'|' -k2,2n "$ARCHIVO_SALIDA" > "$ARCHIVO_ENTRADA"

echo "Archivo ordenado con éxito. Backup guardado en: $ARCHIVO_SALIDA"
