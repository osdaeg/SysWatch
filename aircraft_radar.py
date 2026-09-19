#!/usr/bin/env python3
#
# -----------------------------------------------------------------------------
# SysWatch - Aircraft radar renderer
#
# Generates a local aircraft radar image from:
#   - WEATHER_LAT / WEATHER_LON
#   - OpenSky cache
#   - Tracestrack raster tiles
#
# Requires:
#   - Python 3
#   - Pillow
#
# Configuration is read from SysWatch .env.
# -----------------------------------------------------------------------------

import time
import json
import math
import os
import sys
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

SYSWATCH_DIR = Path.home() / "scripts" / "syswatch"
CACHE_DIR = SYSWATCH_DIR / "cache"
HTML_DIR = SYSWATCH_DIR / "html" / "images"

ENV_FILE = SYSWATCH_DIR / ".env"
OPENSKY_FILE = CACHE_DIR / "opensky.json"

TILES_DIR = CACHE_DIR / "aircraft_map_tiles"
BASEMAP_FILE = CACHE_DIR / "aircraft_map_base.png"
OUTPUT_FILE = HTML_DIR / "mapa_aviones.png"


# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------

DEFAULT_WIDTH_KM = 100
DEFAULT_HEIGHT_KM = 100
DEFAULT_ZOOM = 9
DEFAULT_REFRESH_DAYS = 7

TILE_SIZE = 512

TILE_URL = (
    "https://tile.tracestrack.com/"
    "{mapname}/{z}/{x}/{y}.png"
    "?style={style}&key={key}"
)

MAP_NAME = "es"
MAP_STYLE = "dark2"


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

def die(message):
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def load_env(path):
    """
    Minimal .env parser.

    We intentionally don't depend on python-dotenv.
    """
    values = {}

    if not path.exists():
        die(f"No existe el archivo .env: {path}")

    with path.open("r", encoding="utf-8") as file:
        for raw_line in file:
            line = raw_line.strip()

            if not line or line.startswith("#") or "=" not in line:
                continue

            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()

            if (
                len(value) >= 2
                and value[0] == value[-1]
                and value[0] in ("'", '"')
            ):
                value = value[1:-1]

            values[key] = value

    return values


def env_float(env, key):
    try:
        return float(env[key])
    except (KeyError, ValueError):
        die(f"Variable inválida o ausente en .env: {key}")


def env_int(env, key, default):
    value = env.get(key)

    if value is None or value == "":
        return default

    try:
        return int(value)
    except ValueError:
        die(f"Variable inválida en .env: {key}")
        
def env_bool(env, key, default=False):
    value = env.get(key)

    if value is None:
        return default

    return value.strip().lower() in (
        "1",
        "true",
        "yes",
        "si",
        "sí",
        "on",
    )        


# -----------------------------------------------------------------------------
# Web Mercator
# -----------------------------------------------------------------------------

def latlon_to_world(lat, lon, zoom):
    """
    Converts latitude/longitude to global Web Mercator pixel coordinates.
    """

    lat = max(min(lat, 85.05112878), -85.05112878)

    scale = TILE_SIZE * (2 ** zoom)

    x = (lon + 180.0) / 360.0 * scale

    lat_rad = math.radians(lat)
    y = (
        1.0
        - math.asinh(math.tan(lat_rad)) / math.pi
    ) / 2.0 * scale

    return x, y


def world_to_latlon(x, y, zoom):
    """
    Converts global Web Mercator pixel coordinates back to latitude/longitude.
    """

    scale = TILE_SIZE * (2 ** zoom)

    lon = x / scale * 360.0 - 180.0

    n = math.pi - 2.0 * math.pi * y / scale
    lat = math.degrees(math.atan(math.sinh(n)))

    return lat, lon


# -----------------------------------------------------------------------------
# Geographic area
# -----------------------------------------------------------------------------

def calculate_bounds(center_lat, center_lon, width_km, height_km):
    """
    Calculates an approximate geographic bounding box centered on the
    configured location.

    The calculation is used only to determine the area that must be covered
    by raster tiles.
    """

    earth_radius_km = 6371.0088

    half_width = width_km / 2.0
    half_height = height_km / 2.0

    lat_delta = math.degrees(half_height / earth_radius_km)

    # Longitude degrees vary with latitude.
    lon_delta = math.degrees(
        half_width /
        (earth_radius_km * math.cos(math.radians(center_lat)))
    )

    return (
        center_lat - lat_delta,
        center_lon - lon_delta,
        center_lat + lat_delta,
        center_lon + lon_delta,
    )


# -----------------------------------------------------------------------------
# Tile handling
# -----------------------------------------------------------------------------

def required_tiles(bounds, zoom):
    """
    Returns all XYZ tiles intersecting the requested geographic area.
    """

    min_lat, min_lon, max_lat, max_lon = bounds

    x1, y1 = latlon_to_world(max_lat, min_lon, zoom)
    x2, y2 = latlon_to_world(min_lat, max_lon, zoom)

    tile_min_x = int(x1 // TILE_SIZE)
    tile_max_x = int(x2 // TILE_SIZE)

    tile_min_y = int(y1 // TILE_SIZE)
    tile_max_y = int(y2 // TILE_SIZE)

    max_tile = (2 ** zoom) - 1

    tile_min_x = max(0, min(tile_min_x, max_tile))
    tile_max_x = max(0, min(tile_max_x, max_tile))

    tile_min_y = max(0, min(tile_min_y, max_tile))
    tile_max_y = max(0, min(tile_max_y, max_tile))

    tiles = []

    for y in range(tile_min_y, tile_max_y + 1):
        for x in range(tile_min_x, tile_max_x + 1):
            tiles.append((zoom, x, y))

    return tiles


def tile_path(z, x, y):
    path = TILES_DIR / str(z) / str(x) / f"{y}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path

def basemap_is_fresh(refresh_days):
    """
    Returns True if the cached base map exists and is still fresh.
    """

    if not BASEMAP_FILE.exists():
        return False

    if refresh_days <= 0:
        return False

    age_seconds = time.time() - BASEMAP_FILE.stat().st_mtime
    max_age_seconds = refresh_days * 86400

    return age_seconds < max_age_seconds


def download_tile(z, x, y, api_key, force_refresh=False):
    path = tile_path(z, x, y)

    if (
        path.exists()
        and path.stat().st_size > 0
        and not force_refresh
    ):
        return path

    url = TILE_URL.format(
        mapname=MAP_NAME,
        style=MAP_STYLE,
        z=z,
        x=x,
        y=y,
        key=api_key,
    )

    if force_refresh:
        print(f"Actualizando tile {z}/{x}/{y}")
    else:
        print(f"Descargando tile {z}/{x}/{y}")

    temp_path = path.with_suffix(".tmp")

    try:
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": "SysWatch aircraft radar/0.1"
            },
        )

        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()

        if not data:
            raise RuntimeError("respuesta vacía")

        with temp_path.open("wb") as file:
            file.write(data)

        temp_path.replace(path)

    except Exception as exc:
        if temp_path.exists():
            temp_path.unlink()

        raise RuntimeError(
            f"No se pudo descargar {url}: {exc}"
        ) from exc

    return path

# -----------------------------------------------------------------------------
# Base map
# -----------------------------------------------------------------------------

def build_base_map(
    center_lat,
    center_lon,
    width_km,
    height_km,
    zoom,
    api_key,
    force_refresh=False,
):
    """
    Downloads the necessary raster tiles, joins them and crops the result
    to the requested geographic area.
    """

    bounds = calculate_bounds(
        center_lat,
        center_lon,
        width_km,
        height_km,
    )

    tiles = required_tiles(bounds, zoom)

    if not tiles:
        die("No se encontraron tiles para el área solicitada.")

    print(
        f"Área: {width_km} x {height_km} km | "
        f"zoom {zoom} | "
        f"tiles: {len(tiles)}"
    )

    # Determine tile rectangle.
    tile_xs = [x for _, x, _ in tiles]
    tile_ys = [y for _, _, y in tiles]

    min_x = min(tile_xs)
    max_x = max(tile_xs)
    min_y = min(tile_ys)
    max_y = max(tile_ys)

    canvas_width = (max_x - min_x + 1) * TILE_SIZE
    canvas_height = (max_y - min_y + 1) * TILE_SIZE

    canvas = Image.new(
        "RGB",
        (canvas_width, canvas_height),
    )

    for z, x, y in tiles:
        path = download_tile(
            z,
            x,
            y,
            api_key,
            force_refresh=force_refresh,
        )

        with Image.open(path) as tile:
            tile = tile.convert("RGB")

            px = (x - min_x) * TILE_SIZE
            py = (y - min_y) * TILE_SIZE

            canvas.paste(tile, (px, py))

    # Convert geographic bounds to pixels relative to our tile canvas.
    world_min_x, world_max_y = latlon_to_world(
        bounds[0],
        bounds[1],
        zoom,
    )

    world_max_x, world_min_y = latlon_to_world(
        bounds[2],
        bounds[3],
        zoom,
    )

    origin_x = min_x * TILE_SIZE
    origin_y = min_y * TILE_SIZE

    crop_left = int(world_min_x - origin_x)
    crop_top = int(world_min_y - origin_y)
    crop_right = int(world_max_x - origin_x)
    crop_bottom = int(world_max_y - origin_y)

    crop_left = max(0, crop_left)
    crop_top = max(0, crop_top)
    crop_right = min(canvas.width, crop_right)
    crop_bottom = min(canvas.height, crop_bottom)

    base = canvas.crop(
        (
            crop_left,
            crop_top,
            crop_right,
            crop_bottom,
        )
    )

    # The geographic aspect ratio is not necessarily exactly 1:1 in pixels.
    # Keep the map proportional and resize to a useful SysWatch image size.
    target_width = 1200
    target_height = int(
        target_width * base.height / base.width
    )

    base = base.resize(
        (target_width, target_height),
        Image.Resampling.LANCZOS,
    )

    base.save(BASEMAP_FILE, "PNG", optimize=True)

    print(f"Mapa base generado: {BASEMAP_FILE}")

    return base


# -----------------------------------------------------------------------------
# Aircraft rendering
# -----------------------------------------------------------------------------

def aircraft_points(cx, cy, heading, scale=1.0):
    """
    Returns a simple aircraft silhouette rotated according to heading.

    The shape points are defined pointing north and rotated clockwise.
    """

    # Simple aircraft silhouette.
    points = [
        (0, -15),
        (-3, -4),
        (-13, 4),
        (-12, 8),
        (-3, 6),
        (-4, 16),
        (0, 14),
        (4, 16),
        (3, 6),
        (12, 8),
        (13, 4),
        (3, -4),
    ]

    angle = math.radians(heading)

    result = []

    for x, y in points:
        x *= scale
        y *= scale

        rx = x * math.cos(angle) - y * math.sin(angle)
        ry = x * math.sin(angle) + y * math.cos(angle)

        result.append(
            (
                cx + rx,
                cy + ry,
            )
        )

    return result


def draw_aircraft(draw, x, y, heading, on_ground=False):
    if on_ground:
        fill = "#b8b8b8"
    else:
        fill = "#FFDE00"

    points = aircraft_points(
        x,
        y,
        heading,
        scale=1.0,
    )

    draw.polygon(
        points,
        fill=fill,
        outline="#0b1116",
    )

def load_aircraft():
    if not OPENSKY_FILE.exists():
        print(
            f"Aviso: no existe {OPENSKY_FILE}; "
            "se generará solamente el mapa base."
        )
        return []

    try:
        with OPENSKY_FILE.open("r", encoding="utf-8") as file:
            data = json.load(file)

    except (OSError, json.JSONDecodeError) as exc:
        print(f"Aviso: no se pudo leer OpenSky: {exc}")
        return []

    states = data.get("states")

    if not states:
        return []

    return states


def render_aircraft(
    base,
    center_lat,
    center_lon,
    zoom,
    states,
    show_labels,
):
    """
    Places OpenSky aircraft on the rendered map.
    """

    width, height = base.size

    bounds = calculate_bounds(
        center_lat,
        center_lon,
        MAP_WIDTH_KM,
        MAP_HEIGHT_KM,
    )

    min_lat, min_lon, max_lat, max_lon = bounds

    world_min_x, world_min_y = latlon_to_world(
        max_lat,
        min_lon,
        zoom,
    )

    world_max_x, world_max_y = latlon_to_world(
        min_lat,
        max_lon,
        zoom,
    )

    world_width = world_max_x - world_min_x
    world_height = world_max_y - world_min_y

    draw = ImageDraw.Draw(base)

    # Fuente para las etiquetas
    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            14,
        )
    except OSError:
        font = ImageFont.load_default()

    count = 0

    for state in states:
        if len(state) < 11:
            continue

        try:
            lon = state[5]
            lat = state[6]
            altitude = state[7]
            on_ground = state[8] is True
            velocity = state[9]
            heading = state[10]

            if lat is None or lon is None:
                continue

            if heading is None:
                heading = 0

            lon = float(lon)
            lat = float(lat)
            heading = float(heading)

        except (TypeError, ValueError):
            continue

        # Solamente dibujamos aviones dentro del mapa.
        if not (
            min_lat <= lat <= max_lat
            and min_lon <= lon <= max_lon
        ):
            continue

        world_x, world_y = latlon_to_world(
            lat,
            lon,
            zoom,
        )

        px = (
            (world_x - world_min_x)
            / world_width
            * width
        )

        py = (
            (world_y - world_min_y)
            / world_height
            * height
        )

        # ------------------------------------------------------------------
        # Avión
        # ------------------------------------------------------------------

        draw_aircraft(
            draw,
            px,
            py,
            heading,
            on_ground,
        )

        # ------------------------------------------------------------------
        # Etiqueta
        # ------------------------------------------------------------------

        if show_labels:
            callsign = str(state[1] or "").strip()

            if not callsign:
                callsign = str(state[0] or "UNKNOWN")

            if on_ground:
                detail = "EN TIERRA"

            else:
                if altitude is not None:
                    try:
                        flight_level = int(float(altitude) * 3.28084 / 100)
                        detail = f"FL{flight_level:03d}"
                    except (TypeError, ValueError):
                        detail = "EN VUELO"
                else:
                    detail = "EN VUELO"

            if velocity is not None:
                try:
                    speed_kmh = int(float(velocity) * 3.6)
                    detail += f" · {speed_kmh} km/h"
                except (TypeError, ValueError):
                    pass

            label = f"{callsign}\n{detail}"

            # Aviones amarillos → texto amarillo.
            # Aviones en tierra → texto gris claro.
            if on_ground:
                text_color = "#cccccc"
            else:
                text_color = "#FFDE00"

            # La etiqueta queda desplazada hacia arriba/derecha
            # para no tapar el avión.
            text_x = px + 14
            text_y = py - 18

            # Fondo oscuro semitransparente simulado con un rectángulo.
            bbox = draw.multiline_textbbox(
                (text_x, text_y),
                label,
                font=font,
                spacing=1,
            )

            padding = 3

            draw.rectangle(
                (
                    bbox[0] - padding,
                    bbox[1] - padding,
                    bbox[2] + padding,
                    bbox[3] + padding,
                ),
                fill="#0b1116",
            )

            draw.multiline_text(
                (text_x, text_y),
                label,
                font=font,
                fill=text_color,
                spacing=1,
            )

        count += 1

    return count

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def main():
    global MAP_WIDTH_KM
    global MAP_HEIGHT_KM

    env = load_env(ENV_FILE)

    center_lat = env_float(env, "WEATHER_LAT")
    center_lon = env_float(env, "WEATHER_LON")
    
    show_labels = env_bool(
        env,
        "AIRCRAFT_RADAR_LABEL",
        False,
    )

    MAP_WIDTH_KM = env_int(
        env,
        "AIRCRAFT_MAP_WIDTH_KM",
        DEFAULT_WIDTH_KM,
    )

    MAP_HEIGHT_KM = env_int(
        env,
        "AIRCRAFT_MAP_HEIGHT_KM",
        DEFAULT_HEIGHT_KM,
    )

    zoom = env_int(
        env,
        "AIRCRAFT_MAP_ZOOM",
        DEFAULT_ZOOM,
    )

    refresh_days = env_int(
        env,
        "AIRCRAFT_MAP_REFRESH_DAYS",
        DEFAULT_REFRESH_DAYS,
    )

    api_key = env.get("TRACESTRACK_API", "").strip()

    if not api_key:
        die("TRACESTRACK_API no está configurada en .env")

    print("SysWatch Aircraft Radar")
    print("-----------------------")
    print(f"Centro: {center_lat}, {center_lon}")
    print(f"Área:   {MAP_WIDTH_KM} x {MAP_HEIGHT_KM} km")
    print(f"Zoom:   {zoom}")
    print(f"Refresh: {refresh_days} días")

    # For v0.1 we always make sure the required tiles exist.
    # Refresh-age logic will be added after the first visual test.
    # ------------------------------------------------------------------
    # Base map cache
    # ------------------------------------------------------------------

    if basemap_is_fresh(refresh_days):
        age_days = (
            time.time() - BASEMAP_FILE.stat().st_mtime
        ) / 86400

        print(
            f"Mapa base cacheado: "
            f"{age_days:.1f} días de antigüedad"
        )

        base = Image.open(BASEMAP_FILE).convert("RGB")

    else:
        if BASEMAP_FILE.exists():
            print(
                "Mapa base vencido; "
                "actualizando tiles de Tracestrack..."
            )
        else:
            print(
                "Mapa base inexistente; "
                "descargando tiles de Tracestrack..."
            )

        try:
            base = build_base_map(
                center_lat,
                center_lon,
                MAP_WIDTH_KM,
                MAP_HEIGHT_KM,
                zoom,
                api_key,
                force_refresh=True,
            )

        except Exception as exc:
            if BASEMAP_FILE.exists():
                print(
                    "Aviso: no se pudo actualizar el mapa base: "
                    f"{exc}"
                )
                print(
                    "Se utilizará el mapa base anterior."
                )

                base = Image.open(
                    BASEMAP_FILE
                ).convert("RGB")

            else:
                raise

    states = load_aircraft()

    aircraft_count = render_aircraft(
        base,
        center_lat,
        center_lon,
        zoom,
        states,
        show_labels,
    )

    # Attribution required by the map provider / source data.
    draw = ImageDraw.Draw(base)

    attribution = "© OpenStreetMap contributors · Tracestrack"

    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            13,
        )
    except OSError:
        font = ImageFont.load_default()

    bbox = draw.textbbox(
        (0, 0),
        attribution,
        font=font,
    )

    padding = 6

    x = base.width - (bbox[2] - bbox[0]) - padding
    y = base.height - (bbox[3] - bbox[1]) - padding

    draw.rectangle(
        (
            x - 4,
            y - 3,
            base.width,
            y + (bbox[3] - bbox[1]) + 3,
        ),
        fill="#0b1116",
    )

    draw.text(
        (x, y),
        attribution,
        font=font,
        fill="#cccccc",
    )

    base.save(
        OUTPUT_FILE,
        "PNG",
        optimize=True,
    )

    print(f"Aviones dibujados: {aircraft_count}")
    print(f"Radar generado: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
