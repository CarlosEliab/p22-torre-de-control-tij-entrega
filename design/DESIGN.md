# Diseño — Tablero Torre de control TIJ

Este documento describe la interfaz **implementada** en `priv/index.html`
(servida por cowboy) y su relación con el diseño de Google Stitch. El paquete
exportado está en [`stitch/`](stitch/).

## Concepto

Una torre de control se lee de un vistazo: el operador necesita ver **qué está
pasando ahora**, no navegar menús. La pantalla principal es un tablero kanban
por estado, con una bitácora de eventos siempre visible y el detalle de cada
vuelo en un diálogo.

Principios:

1. **Estado = color.** Cada estado tiene un color estable en toda la app.
2. **Densidad legible.** Tarjetas compactas, tipografía pequeña pero con
   contraste alto; el tablero debe funcionar en celular.
3. **Sin parpadeo.** Las actualizaciones llegan por WebSocket y se aplican sin
   recargar; si el socket cae, se reconecta y se resincroniza.
4. **Acciones seguras.** El detalle solo ofrece las transiciones legales para
   el estado actual; el backend igual las valida.

## Paleta

La app usa los tokens exportados por Stitch (`torre_de_control_tij/DESIGN.md`):

| Token | Hex | Uso |
|---|---|---|
| `--surface` | `#0b1326` | fondo de la app (modo oscuro de sala de operaciones) |
| `--surface-low` | `#131b2e` | barra lateral y pie del modal |
| `--surface-container` | `#171f33` | columnas, toolbar, bitácora |
| `--surface-high` | `#222a3d` | tarjetas y cabecera del modal |
| `--on-surface` | `#dae2fd` | texto principal |
| `--on-surface-variant` | `#bdc8d1` | metadatos y texto secundario |
| `--outline` | `#87929a` | etiquetas y texto atenuado |
| `--primary` | `#8ed5ff` | acento principal y foco |
| `--primary-container` | `#38bdf8` | botón primario y estado Programado |
| `--secondary` | `#4edea3` | estado en línea y puertas |
| `--tertiary` | `#e1bfff` | eventos |
| `--programado` | `#38bdf8` | azul |
| `--demorado` | `#f59e0b` | ámbar (atención) |
| `--abordando` | `#a855f7` | violeta |
| `--despego` | `#06b6d4` | cian |
| `--aterrizado` | `#10b981` | verde (éxito) |
| `--cancelado` | `#f43f5e` | rojo (falla) |

El color se usa en el punto y el borde de la columna, y en el borde izquierdo
de cada tarjeta; no se depende solo del color: cada columna lleva su nombre y
contador.

## Tipografía y espaciado

- **Inter** para la interfaz y **JetBrains Mono** para llamadas, horas, puertas,
  contadores y etiquetas. Se cargan desde Google Fonts con fallback a fuentes
  del sistema (`system-ui` / `ui-monospace`), así que la app sigue funcionando
  sin red.
- Título 1.55 rem; encabezados de columna 0.58 rem en mayúsculas; metadatos
  0.66 rem; cifras KPI 1.55 rem con `tabular-nums`.
- Radios de 4 px para controles y 8 px para módulos; separación de 0.55 rem
  entre columnas.

## Estructura

```
┌ sidebar ─────┬ topbar ────────────────────────────────────────────┐
│ TIJ          │ Aeropuerto · Torre de control TIJ      ● EN VIVO  │
│ Panel        ├ KPIs: vuelos · puertas · eventos/min · tableros    │
│ Tablero      ├ toolbar: Crear vuelo · Niebla · Caos · Orden       │
│ Bitácora     ├ Programado │ Demorado │ Abordando │ Despegó │ ...  │
│              │  tarjetas  │ tarjetas │ tarjetas  │ ...            │
│              ├ bitácora de eventos y alertas                      │
└──────────────┴───────────────────────────────────────────────────┘
```

- **Barra lateral:** marca, navegación a panel/tablero/bitácora y estado del
  sistema. En móvil se convierte en una fila horizontal.
- **Topbar:** identidad, subtítulo e indicador WebSocket con estado textual
  (`Conectando`, `En vivo`, `Reconectando`), no solo color.
- **KPIs:** cuatro tarjetas con borde de acento y cifras monoespaciadas.
- **Toolbar:** acciones de demo agrupadas; “Crear vuelo” es la acción primaria.
- **Columnas:** grid de 6 columnas en escritorio ancho, 3 a ≤1280 px, 2 a ≤760
  px y 1 a ≤560 px. Cada columna tiene altura máxima y scroll interno, de modo
  que 60 vuelos aterrizados no alargan toda la página.
- **Tarjeta de vuelo:** llamada IATA-like (`TJ-128`), hora, aerolínea, ruta,
  badges de puerta/demora/respaldo. Es un botón accesible (Enter/Espacio).
- **Bitácora:** últimas 80 líneas, la más reciente arriba; hora y mensaje en
  columnas separadas.
- **Diálogo de detalle:** tabla de datos, motivos, acciones legales, fila
  **Cambiar puerta** (puerta destino + minutos en una sola operación) y
  bitácora del vuelo (12 entradas).
- **Alerta flotante:** banner inferior para niebla, caos y errores de acción.

## Estados e interacción

| Estado | Color | Acciones ofrecidas |
|---|---|---|
| Programado | azul | Abordar, +20 min, Cambiar puerta, Cancelar |
| Demorado | ámbar | Abordar, Quitar demora, Cambiar puerta, Cancelar |
| Abordando | violeta | Despegar, Cambiar puerta, Cancelar |
| Despegó | cian | Aterrizar |
| Aterrizó | verde | — |
| Cancelado | rojo | — |

El modal se cierra al aplicar una acción y el tablero se refresca; el evento de
WebSocket llega igual y actualiza la tarjeta. Si el backend rechaza la acción
(409), se muestra el error en el banner.

## Accesibilidad

- Contraste alto texto/fondo en modo oscuro.
- La alerta usa `role="alert"` y el estado del socket `aria-live="polite"`.
- Botones nativos, foco visible y tarjetas operables con teclado.
- La información no depende solo del color: hay texto de estado y contadores.
- `lang="es"`, `viewport` y `prefers-reduced-motion` para celular y movimiento
  reducido.

## Responsive

- 6 columnas en escritorio ancho; 3, 2 y 1 en anchos menores.
- Barra lateral horizontal y topbar no fija en ≤900 px.
- KPIs en 2 columnas y luego 1; acciones a ancho completo en ≤560 px.
- El diálogo ocupa 96 % del ancho en celular, con scroll interno.

## Correspondencia con el código

- `priv/index.html`: estilos, estructura y toda la interacción.
- `p22_h_index.erl`: sirve el archivo (con rutas de respaldo para Windows).
- `p22_h_ws.erl`: snapshot inicial y eventos en vivo.
- `p22_h_vuelo_estado.erl`: acciones del modal, incluida `cambiar_puerta`.
- `p22_puertas.erl`: asignación de una puerta concreta y liberación por puerta.
- `p22_h_demo.erl`: botones de niebla/caos/fuera de orden.

## Entrega de Stitch

El ZIP real está en `design/stitch/` y descomprimido en
`design/stitch/stitch_torre_de_control_tij/`; incluye tablero, modal de detalle
y móvil 390 px, con su HTML y `DESIGN.md`. El índice está en
[`CAPTURAS.md`](CAPTURAS.md).

La implementación adoptó los tokens de color, la tipografía Inter/JetBrains
Mono, la barra lateral, la topbar con estado en vivo, los KPIs y el modal de
Stitch, manteniendo el HTML de producción en `priv/index.html`. No se copiaron
los defectos del mockup móvil (encabezado encimado ni título cortado).
