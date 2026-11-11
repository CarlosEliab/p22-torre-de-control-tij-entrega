# Prompt para Google Stitch — #22 Torre de control TIJ

Copia este prompt en <https://stitch.withgoogle.com/>. Genera una interfaz
oscura, operativa y legible en celular, en **español**.

---

## Contexto

Diseña la interfaz de **Torre de control TIJ**, el tablero de vuelos del
Aeropuerto Internacional de Tijuana (TIJ / MMTJ). Es una herramienta para
personal de torre y aerolínea: debe mostrar el estado de decenas de vuelos en
tiempo real, permitir operar solo acciones legales y resistir fallas (caos,
reinicio, mensajes fuera de orden).

## Pantallas

### 1. Tablero principal (escritorio)

- Encabezado: título “Torre de control TIJ”, subtítulo “Aeropuerto
  Internacional de Tijuana — tablero en vivo”.
- Indicadores: WebSocket (punto verde/rojo), vuelos, puertas libres,
  eventos/min, tableros conectados.
- Botones de demo: **+ Crear vuelo**, **Niebla +20**, **Caos**, **Fuera de
  orden**, **Refrescar**.
- Tablero kanban con seis columnas y contador: **Programado** (azul),
  **Demorado** (ámbar), **Abordando** (violeta), **Despegó** (cian),
  **Aterrizó** (verde), **Cancelado** (rojo).
- Tarjeta de vuelo: identificación (`TJ-101`), hora estimada, aerolínea,
  destino y badges: `🚪 puerta_5`, `⏱ +15 min`, `respaldo`.
- Bitácora inferior “Bitácora de eventos y alertas (en vivo)”.

### 2. Detalle del vuelo (modal)

- Título: `TJ-101 → SEA`.
- Tabla: estado, aerolínea, aeronave, puerta, hora programada, hora estimada,
  demora acumulada, motivos.
- Acciones legales según el estado (Abordar, Despegar, Aterrizar, +20 min,
  Quitar demora, Cancelar).
- **Cambiar puerta:** campo de texto (`puerta_5`), campo numérico de minutos
  (15), botón **Aplicar** y texto de ayuda: “Si dejas la puerta vacía se asigna
  una libre; los minutos se suman a la demora y recalculan la hora estimada.”
- Bitácora del vuelo con hora y detalle.
- Botón **Cerrar**.

### 3. Tablero móvil (390 px)

- Una columna por fila, tarjetas a ancho completo.
- Indicadores en dos filas; botones de demo con wrap.
- Texto mínimo 14 px; no ocultar la puerta ni la demora.

## Requisitos visuales

- Tema oscuro (fondo `#0f172a`, paneles `#1e293b`, texto `#e2e8f0`).
- Acento por estado; rojo solo para cancelado/error, ámbar para demora.
- Tipografía sans legible; jerarquía clara; sin gradientes fuertes.
- Componentes consistentes: tarjeta, badge, botón primario/secundario, modal,
  campos de formulario.
- Accesibilidad: contraste alto, foco visible, textos en español, botones con
  verbos claros.
- Navegación: una sola vista con modal; el estado se actualiza en vivo sin
  recargar.

## Entregable

Exporta las pantallas desde Stitch y descomprime el ZIP en `design/stitch/`.
Incluye las capturas en `design/stitch/capturas/` y actualiza
`design/CAPTURAS.md` con la ruta. No se considera entregado hasta que el ZIP
esté en el repositorio.

---

## Cómo generarlo y exportarlo (paso a paso)

1. Entra a <https://stitch.withgoogle.com/> con una cuenta de Google y pulsa
   **Try now**. Stitch es gratis y no necesita tarjeta.
2. Crea un proyecto nuevo, elige **Web** (el tablero es web, no una app nativa)
   y pega el prompt de este archivo. Si Stitch genera solo una pantalla, pídele
   en el chat las otras dos: “genera el modal de detalle con cambiar puerta” y
   “genera la versión móvil a 390 px”.
3. Revisa que aparezcan los seis estados, la fila **Cambiar puerta** y la
   bitácora. Itera en el chat (“más contraste”, “tabla legible en móvil”, “no
   ocultes la puerta”).
4. Selecciona las tres pantallas en el lienzo con las casillas y pulsa
   **Export** → formato **.zip** → **Export**. Si no aparece el botón, abre el
   menú **☰** del proyecto y usa **Download**: baja el HTML, una captura por
   pantalla y `DESIGN.md`.
5. Guarda el ZIP como `design/stitch/p22-torre-de-control-tij.zip` y
descomprímelo en `design/stitch/`. Añade una captura del lienzo de Stitch en
`design/stitch/capturas/`.
6. Si el ZIP solo trae `DESIGN.md` y capturas, usa el icono de código `< >` de
   cada pantalla y descarga su HTML; no es motivo para no entregar.

> “Copy to Figma” solo aparece en modo **Standard**; para esta entrega no hace
> falta Figma, basta el ZIP y las capturas.
