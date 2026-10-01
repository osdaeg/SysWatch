#!/bin/bash

while true; do
    # Generar latitud y longitud aleatorias entre -90 y 90
    WEATHER_LAT=$(( RANDOM % 181 - 90 ))
    WEATHER_LON=$(( RANDOM % 361 - 180 ))

    # Modificar el archivo .env usando sed
    sed -i "s/^WEATHER_LAT=.*/WEATHER_LAT=$WEATHER_LAT/" .env
    sed -i "s/^WEATHER_LON=.*/WEATHER_LON=$WEATHER_LON/" .env

    # Esperar 60 segundos antes de la siguiente iteración
    sleep 60
done
