# SysWatch State Specification

Version: 1.0

---

# Objetivo

El archivo `.state` es el único contrato entre un módulo y la interfaz de usuario.

Los módulos generan datos.

La interfaz interpreta datos.

Ninguno conoce la implementación del otro.

---

# Filosofía

Cada módulo debe ser completamente independiente.

La interfaz nunca debe contener lógica específica para un módulo determinado.

No debe existir código como:

```bash
if module == cpu
```

o

```bash
if module == network
```

Toda la información necesaria para representar una ficha debe estar presente dentro del `.state`.

---

# Notas

Implementado
    El frontend lo interpreta actualmente.

Experimental
    Puede cambiar en versiones futuras.

Futuro
    Reservado para una implementación posterior.
    
---

# Estructura

Cada módulo genera un archivo `.state` por entidad monitoreada.

Ejemplos:

```
cpu.state
memory.state
eth0.state
wlan0.state
sda.state
nvme0n1.state
```

---

# Sintaxis

El archivo utiliza pares:

```
clave=valor
```

Ejemplo:

```
temperature=41
usage=17
status=OK
```

---

# Campos obligatorios

Todo módulo debe definir los siguientes campos.

## module.label

Nombre mostrado como título.

Ejemplo

```
module.label=CPU
```

---

## module.icon

Icono utilizado por la interfaz.

Ejemplo

```
module.icon=lucide/cpu
```

---

## module.order

Orden de aparición.

Ejemplo

```
module.order=20
```

---

## module_version

Versión del módulo.

Ejemplo

```
module_version=0.1.0
```

---

## status

Estado general.

Valores permitidos:

```
OK
WARNING
CRITICAL
UNKNOWN
```

---

# Campos de datos

Los módulos pueden generar cualquier cantidad de datos.

Ejemplo

```
temperature=42
usage=18
speed=1000
rx_rate=215468
```

No existe una lista fija de nombres.

Cada módulo define los suyos.

---

# Metadatos

Todo dato puede tener metadatos asociados utilizando el mismo nombre seguido de un sufijo.

Ejemplo

```
temperature.label=Temperatura
temperature.unit=°C
temperature.render=text
```

---

## .label

Texto visible.

Ejemplo

```
temperature.label=Temperatura
```

---

## .unit

Unidad de medida.

Ejemplo

```
temperature.unit=°C
```

```
usage.unit=%
```

```
speed.unit=Mbps
```

---

## .icon

Icono específico para ese dato.

Ejemplo

```
temperature.icon=lucide/thermometer
```

---

## .render

Indica al frontend cómo representar el dato.

Valores actualmente definidos:

```
text
number (futuro)
bytes (futuro)
percentage (futuro)
sparkline
progress (futuro)
gauge
```

Ejemplo

```
usage.render=sparkline
```

---

## .hidden

Oculta el dato.

El dato continúa existiendo.

Puede utilizarse para cálculos o por otros componentes.

Ejemplo

```
peak_rx.hidden=true
```

La interfaz nunca debe mostrar un dato oculto.

---

## .color

Color preferido.

Opcional.

Ejemplo

```
temperature.color=warning
```

---

# Sparkline

Las sparklines son completamente declarativas.

Ejemplo

```
usage=42

usage.render=sparkline

usage.history=usage

usage.min=18

usage.max=87
```

El frontend únicamente interpreta esos campos.

Nunca debe conocer el origen de los datos.

---

# Gauge

Los gauges son completamente declarativos.

Ejemplo

```ini
temperature=47

temperature.render=gauge

temperature.min=0
temperature.max=100

temperature.warning=70
temperature.critical=85

temperature.unit=°C
```

Donde:

- `.render` indica el tipo de representación.
- `.min` y `.max` definen la escala del indicador.
- `.warning` marca el comienzo de la zona de advertencia.
- `.critical` marca el comienzo de la zona crítica.
- `.unit` es opcional y se muestra junto al valor.

El frontend únicamente interpreta esos campos.

Nunca debe conocer el origen de los datos.

---

# Históricos

Los históricos no forman parte del `.state`.

Se almacenan en los archivos CSV.

El `.state` únicamente referencia el nombre del histórico.

Ejemplo

```
usage.history=usage

rx_rate.history=rx_rate
```

---

# Datos internos

Los módulos pueden almacenar datos auxiliares.

Todos los datos internos comienzan con:

```
_internal.
```

Ejemplo

```
_internal.prev_rx
_internal.prev_tx
_internal.prev_time
```

Estos campos nunca deben mostrarse.

---

# Extensibilidad

El formato está pensado para crecer.

Nuevos metadatos pueden agregarse sin romper compatibilidad.

Ejemplos:

```
temperature.decimals=1

usage.graph_color=auto

speed.warning=100

speed.critical=10
```

Los renderizadores que no conozcan un metadato simplemente lo ignorarán.

---

# Compatibilidad

Los módulos no deben depender de la implementación del frontend.

El frontend no debe depender de la implementación de los módulos.

El único contrato válido es el contenido del `.state`.

---

# Regla de oro

Los módulos producen datos.

La interfaz interpreta datos.

Ninguno conoce la implementación del otro.