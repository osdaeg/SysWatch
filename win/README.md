# syswatch.exe (SysWatch para Windows)

Ejecutable residente en la bandeja del sistema que genera archivos `.state`, `.timer` y `.csv`
con el mismo formato que usa SysWatch en Linux. Sin administrador, sin instalador.

## Uso

1. Copiar `syswatch.exe` a una carpeta del usuario (por ejemplo `%LOCALAPPDATA%\syswatch-win`).
2. Ejecutarlo. La primera vez crea `%APPDATA%\syswatch-win\config.json` y lo abre para editarlo.
3. Poner `output_dir` apuntando a la carpeta `import/` compartida del SysWatch receptor
   (se recomienda ruta UNC: `\\servidor\import`). El exe solo escribe si en esa carpeta existe `.import`.
4. El exe recarga la configuración solo al guardar el archivo (o desde el menú de la bandeja).

Archivos del exe en `%APPDATA%\syswatch-win\`: `config.json`, `syswatch.log` (rota a 1 MB),
`runtime.json` (status_since y totales de red) y, opcional, `lang\*.conf` con traducciones.

## Archivos generados

| Archivo | Contenido |
|---|---|
| `<estado>-<host>.state` | claves en orden alfabético, UTF-8 sin BOM, fin de línea LF |
| `<estado>-<host>.timer` | `<estado>-<host>=TOTAL:n|ACTION:deletestate|COUNT:n`, n = intervalo/60+5 |
| `<estado>-<host>.<clave>.csv` | `timestamp,value` con epoch y enteros, últimos `csv_points` valores |

Estados: `cpu`, `memory`, `disk_<letra>`, `smart_<n>`, `about`, uno por adaptador de red
(`ethernet`, `wi_fi`, ...), `network_total`, y las fichas efímeras `cpu_top` / `memory_top`
(los 8 procesos que más consumen cuando se llega a warning; se borran al bajar).

## Compilar

```sh
./build.sh          # genera dist/syswatch.exe (Go 1.22+, desde cualquier sistema)
go test ./...       # las pruebas corren en Linux/macOS/Windows
```

## Idioma

Los textos visibles están en inglés en el código y pasan por el mismo mecanismo que `sw_translate`
(pares `en=...` / `es=...`). `language` vacío usa el idioma de la interfaz de Windows.
`internal/i18n/lang/es.conf` va embebido; un `.conf` en `lang\` junto a la config lo amplía o reemplaza.

## Red

Cada adaptador físico tiene su state; si Windows lo detecta pero no está en uso se escribe con `status=NONE`.
La decisión "conectado" combina WMI (`Status`, `InterfaceOperationalStatus`, `MediaConnectState`) con la lista de
interfaces del sistema (activa y con IPv4). El motivo de cada decisión queda en `syswatch.log`
(`network adapter "...": physical=... connected=...`). En adaptadores Wi-Fi conectados se agrega `ssid`
(API WLAN, sin procesos hijos; Windows 11 24H2+ puede ocultarlo sin el permiso de ubicación).

## Orden de los módulos

Cada módulo acepta `"order": N` en el `config.json` para fijar su `module.order` (0 u omitido = valor por defecto:
about 10, cpu 30, memory 40, network 50, network_total 55 (= order de network + 5), disk 60, smart 70).
Las fichas de procesos usan 900.

## Carga estimada

Windows no tiene load average. El exe toma una muestra de uso de CPU cada 5 segundos y calcula la cantidad de
núcleos ocupados (uso × núcleos) suavizada a 1, 5 y 15 minutos, que se comporta como el load average de Linux
para cargas que consumen CPU. También usa esas muestras para promediar `usage` entre dos ciclos.

## Fichas de procesos

Formato igual al de Linux: una clave por nombre de proceso, valor en % (CPU normalizada por núcleos, o % de la RAM
total en la ficha de memoria), etiqueta `nombre (PID)` y orden de 10 en 10 (50 en memoria, 70 en CPU). Si un
mismo nombre tiene varias instancias se suman y la etiqueta es `nombre (×N)`.

## SMART

Salud, modelo, tipo, bus y tamaño. Temperatura, desgaste y horas de uso aparecen solo si Windows las entrega
sin admin para ese disco; el log (`smart: ...`) indica si se pudieron leer.

## Límites conocidos de esta versión

- Las fichas de procesos usan los tiempos de CPU de cada proceso; los procesos protegidos del sistema
  que niegan el acceso sin admin no aparecen.
- Pendiente de ajustar contra los módulos Linux: texto de `.unit` de las velocidades.
