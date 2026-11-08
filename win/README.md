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

## Límites conocidos de esta versión

- SMART básico: salud, modelo, tipo, bus y tamaño. Temperatura, desgaste y horas de uso quedan para más adelante.
- Las fichas de procesos usan los tiempos de CPU de cada proceso; los procesos protegidos del sistema
  que niegan el acceso sin admin no aparecen.
- Pendiente de ajustar contra los módulos Linux: `module.order` de network/about/smart, texto de `.unit`
  de las velocidades y formato de la ficha de memoria.
