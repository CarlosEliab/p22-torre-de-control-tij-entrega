# Capturas y paquete de diseño

## Capturas reales de la aplicación

Tomadas de la app corriendo en WSL2/Ubuntu (OTP 27), desde un Chrome headless
conectado al WebSocket real (indicador **EN VIVO** y bitácora con eventos). El
modal se capturó con el feed pausado para conservar el vuelo en `Programado`.

| Archivo | Qué muestra |
|---|---|
| [`capturas/tablero-escritorio.png`](capturas/tablero-escritorio.png) | Tablero de 1440 px: barra lateral, topbar con estado en vivo, cuatro KPIs, toolbar, seis columnas con scroll interno y bitácora. |
| [`capturas/tablero-movil.png`](capturas/tablero-movil.png) | La misma app a 390 px: navegación horizontal, KPIs en dos columnas, acciones apiladas y columnas a una sola fila. |
| [`capturas/detalle-cambio-puerta.png`](capturas/detalle-cambio-puerta.png) | Modal de `TJ-423`: estado, puerta `puerta_5`, demora de 15 min, acciones legales, fila **Cambiar puerta** (puerta + minutos) y bitácora del cambio. |

Las imágenes son evidencia de la **app real**; no son mockups.

## Google Stitch

Las decisiones de interfaz están en [`DESIGN.md`](DESIGN.md) y el paquete
exportado en [`stitch/`](stitch/).

**Estado: entregado.** El ZIP real exportado desde Google Stitch está en
[`stitch/p22-torre-de-control-tij.zip`](stitch/p22-torre-de-control-tij.zip)
(1.1 MB) y descomprimido en `stitch/stitch_torre_de_control_tij/`.

| Pantalla | Archivo | Qué muestra |
|---|---|---|
| Tablero principal | [`stitch/.../tablero_principal_torre_de_control_tij/screen.png`](stitch/stitch_torre_de_control_tij/tablero_principal_torre_de_control_tij/screen.png) | Vista de operaciones en vivo: seis columnas, indicadores, METAR, pista y bitácora. |
| Detalle del vuelo | [`stitch/.../detalle_del_vuelo_modal_tj_101_torre_de_control_tij/screen.png`](stitch/stitch_torre_de_control_tij/detalle_del_vuelo_modal_tj_101_torre_de_control_tij/screen.png) | Modal de `TJ-101` con acciones legales, **Cambiar puerta y demora** y auditoría. |
| Tablero móvil | [`stitch/.../tablero_m_vil_390px_torre_de_control_tij/screen.png`](stitch/stitch_torre_de_control_tij/tablero_m_vil_390px_torre_de_control_tij/screen.png) | Tarjetas a una columna, 390 px, con puerta y demora visibles. |

Cada pantalla incluye su `code.html` y su `screen.png`. El sistema de diseño
completo está en
[`stitch/stitch_torre_de_control_tij/torre_de_control_tij/DESIGN.md`](stitch/stitch_torre_de_control_tij/torre_de_control_tij/DESIGN.md).

La implementación adopta los tokens de Stitch (superficies `#0b1326`,
`#171f33` y `#222a3d`; acentos `#8ed5ff`/`#38bdf8`; tipografía Inter y
JetBrains Mono) y su estructura de sidebar, topbar, KPIs, toolbar, seis
columnas y modal. El HTML de producción sigue siendo `priv/index.html`; Stitch
es la referencia de diseño y la comparación se puede hacer lado a lado.
