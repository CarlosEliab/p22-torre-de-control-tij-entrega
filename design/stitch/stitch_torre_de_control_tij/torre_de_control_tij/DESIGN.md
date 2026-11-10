---
name: Torre de Control TIJ
colors:
  surface: '#0b1326'
  surface-dim: '#0b1326'
  surface-bright: '#31394d'
  surface-container-lowest: '#060e20'
  surface-container-low: '#131b2e'
  surface-container: '#171f33'
  surface-container-high: '#222a3d'
  surface-container-highest: '#2d3449'
  on-surface: '#dae2fd'
  on-surface-variant: '#bdc8d1'
  inverse-surface: '#dae2fd'
  inverse-on-surface: '#283044'
  outline: '#87929a'
  outline-variant: '#3e484f'
  surface-tint: '#7bd0ff'
  primary: '#8ed5ff'
  on-primary: '#00354a'
  primary-container: '#38bdf8'
  on-primary-container: '#004965'
  inverse-primary: '#00668a'
  secondary: '#4edea3'
  on-secondary: '#003824'
  secondary-container: '#00a572'
  on-secondary-container: '#00311f'
  tertiary: '#e1bfff'
  on-tertiary: '#490080'
  tertiary-container: '#ce9bff'
  on-tertiary-container: '#6400ac'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#c4e7ff'
  primary-fixed-dim: '#7bd0ff'
  on-primary-fixed: '#001e2c'
  on-primary-fixed-variant: '#004c69'
  secondary-fixed: '#6ffbbe'
  secondary-fixed-dim: '#4edea3'
  on-secondary-fixed: '#002113'
  on-secondary-fixed-variant: '#005236'
  tertiary-fixed: '#f0dbff'
  tertiary-fixed-dim: '#ddb7ff'
  on-tertiary-fixed: '#2c0051'
  on-tertiary-fixed-variant: '#6900b3'
  background: '#0b1326'
  on-background: '#dae2fd'
  surface-variant: '#2d3449'
typography:
  headline-xl:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
  headline-xl-mobile:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  headline-md:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  telemetry-lg:
    fontFamily: JetBrains Mono
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 26px
  telemetry-md:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
  telemetry-sm:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
  label-caps:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-desktop: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1.25rem
  space-xl: 2rem
---

## Brand & Style

This design system establishes a high-density, mission-critical operational cockpit for Tijuana International Airport (TIJ / MMTJ). Engineered for air traffic controllers, apron management, and airfield dispatchers, the aesthetic balances the rigor of avionic flight instruments with modern ergonomic data density. 

The design draws from modern avionics and high-contrast tactical displays:
- **Zero Ambiguity:** Ultra-crisp boundaries, distinct chromatic semantic states, and strict visual hierarchy eliminate split-second cognitive lag.
- **Cockpit Immersion:** Deep slate and charcoal surfaces minimize ocular fatigue over 12-hour operational shifts, allowing luminous operational telemetry (runway occupancy, flight corridors, transponder telemetry) to command visual focus.
- **Utilitarian Elegance:** Tactile feedback, crisp divider lines, monospaced tabular alignments, and structured telemetry blocks replace frivolous ornamentation.

## Colors

The palette utilizes a tailored dark spectrum that emulates radar displays and modern glass cockpits, paired with unambiguous signal colors for aeronautical operations.

### Core Canvas & Surfaces
- **Root Ground:** `#0f172a` (Slate 900) provides the base canvas depth.
- **Instrument Surface:** `#1e293b` (Slate 800) for telemetry cards, operational strips, and modal surfaces.
- **Structural Borders:** `#334155` (Slate 700) for rigid element boundaries and structural dividers.
- **Subtle Surface:** `#0b1120` (Sub-deck) for recessed data tables and radar map viewports.

### Primary Typography & Readings
- **High-Contrast Text:** `#f8fafc` (Slate 50) for critical flight identifiers, runway numbers, and urgent alerts.
- **Standard Telemetry Text:** `#e2e8f0` (Slate 200) for standard operational data and active parameters.
- **Muted / Inactive Labels:** `#94a3b8` (Slate 400) for metadata headers, field descriptions, and deactivated actions.

### Flight Status Tokens
- **Programado (Scheduled):** `#38bdf8` (Sky Blue) — Standard pipeline state, calm and forward-looking.
- **Demorado (Delayed):** `#f59e0b` (Amber) — Heightened awareness state, requiring gate and slot attention.
- **Abordando (Boarding):** `#a855f7` (Violet) — Active ground operation transition.
- **Despegó (Departed / Airborne):** `#06b6d4` (Cyan) — Active climb-out and airspace handoff.
- **Aterrizó (Landed):** `#10b981` (Emerald Green) — Successful touch-down, runway clearance, taxi-in status.
- **Cancelado (Cancelled / Emergency Alert):** `#f43f5e` (Rose Red) — Immediate attention, slot cancellation, or runway conflict.

## Typography

Typography in this system serves two distinct functions: human interface management and precision data telemetry.

- **Interface Primary (`Inter`):** Selected for structural headers, status messaging, modal content, and contextual notifications. Its tall x-height and clean geometric forms ensure fatigue-free parsing under low-light operating conditions.
- **Flight & Telemetry Monospace (`JetBrains Mono`):** Dedicated to callsigns (`AMX184`, `VOI512`), ICAO/IATA waypoint codes (`MMTJ / TIJ`, `MMMX / MEX`), transponder Squawk codes (`7700`, `1200`), UTC timestamps, gate allocations, and flight level indicators. Tabular numerals prevent layout jitter during live telemetry updates.
- **All-Caps Telemetry Protocol:** Flight codes, runway designations (e.g., `RWY 09/27`), and status labels must be rendered in uppercase with tight letter-spacing for rapid cognitive capture.

## Layout & Spacing

The operational interface implements a structured fluid-docking grid optimized for multi-monitor radar stations and mission-critical multi-pane layouts.

- **Grid Architecture:** 24-column granular desktop grid allowing simultaneous presentation of the live runway schematic, flight strip queue, weather station telemetry (METAR/TAF), and gate matrix.
- **Layout Rhythm:** A tight base-4 vertical rhythm maintains high information density without visual crowding. Compact component padding (`space-xs` and `space-sm`) is utilized within flight strip rows and status badges to maximize screen real estate.
- **Multi-Monitor Adaptation:** 
  - **Large Workstations (>= 1920px):** 3-panel split view (Radar Track / Runway Monitor on the left; Dual Flight Board Arrival/Departure central; Detail Inspector right).
  - **Standard Desktop / Laptops (1024px - 1440px):** Two-pane modular view with collapsible telemetry sidebars.
  - **Field Tablet / Mobile (< 1024px):** Single-column stacked telemetry cards with persistent fixed quick-filter tabs for Runway/Airborne/Gate views.

## Elevation & Depth

Visual hierarchy is achieved through structured planar layering and low-contrast perimeter definition rather than soft, diffuse drop-shadows, which cause screen glare on dark command consoles.

- **Layer 0 (Canvas Base):** `#0f172a` — The baseline operational environment.
- **Layer 1 (Card & Module Decks):** `#1e293b` outlined with a uniform `1px` border of `#334155`. Cards do not hover or use ambient blur; they are strictly planar modules.
- **Layer 2 (Overlays, Flight Strips In-Hand, Dropdowns):** Background `#1e293b` elevated by a direct `0 4px 16px rgba(0, 0, 0, 0.65)` shadow with a lighter boundary border (`#475569`).
- **Tactile Emissive Glow:** For urgent flight warnings or critical status transitions (e.g., Squawk 7700 or Cancelado), elements leverage a subtle colored emissive ring (`box-shadow: 0 0 10px rgba(244, 63, 94, 0.35)`) against the slate surface.

## Shapes

The design system enforces a precision, hardware-inspired architectural shape language:
- **Base Components:** 4px (`roundedness: 1`) border radius for buttons, inputs, flight status strips, and badges. This maintains an instrument-grade, hardware-like discipline.
- **Containers & Paneling:** 8px (`rounded-lg`) for major cockpit modules, radar viewport containers, and modal dialogs.
- **Pill Exceptions:** Rounded-full styling is reserved exclusively for numerical transponder indicators, live radar sweep dots, and radio frequency pill tags.

## Components

### 1. Flight Status Badges & Chips
- **Structure:** Monospaced label text (`label-caps`), compact vertical padding (`2px 8px`), `border-radius: 4px`.
- **Styling:** Semi-transparent tinted background (`12%` opacity of the semantic status color), solid `1px` border at `30%` opacity, and full-intensity foreground text.
- **Active Pulse:** Live statuses like *Abordando* and *Despegó* incorporate a `6px` solid status pip with a CSS breathing-glow animation.

### 2. Flight Strip Card (Ficha de Vuelo)
- **Structure:** Tabular grid displaying callsign, aircraft type (e.g., `A320`, `B738`), origin/destination code (`TIJ -> MEX`), assigned runway (`RWY 27`), gate, and assigned slot time.
- **Color Accent:** Left border `4px` solid bar carrying the semantic status color token.
- **Background:** `#1e293b` resting; `#28364d` when selected or dragged across the dispatch pipeline.

### 3. Primary & Tactical Action Buttons
- **Primary:** High-visibility Sky Blue (`#38bdf8`) fill with slate-950 text (`#020617`), bold weight. For irreversible operations (e.g., Hold, Divert), an emergency variant uses Rose Red (`#f43f5e`).
- **Tactical Secondary:** `#1e293b` surface with `#334155` border, text `#e2e8f0`. Hover switches border to `#64748b` with subtle internal brightening.

### 4. Input Fields & Search Bars
- **Surface:** Recessed `#0b1120` with `#334155` border.
- **Focus:** Crisp `1px` border in `#38bdf8` with no offset blur.
- **Input Typography:** All flight filter search fields use `JetBrains Mono` with uppercase conversion for instant IATA/ICAO code lookups.

### 5. Telemetry & Data Tables
- **Rows:** Alternating subtle row backgrounds (`#1e293b` and `#172033`) separated by crisp `#334155` horizontal rules.
- **Numerals:** All altitudes, speeds (knots), transponder codes, and timestamps must use tabular figures (`font-variant-numeric: tabular-nums`).

### 6. Runway Occupancy Bar
- Compact horizontal strip module representing TIJ Runway 09/27 with color-coded block sectors (Available: `#10b981`, Occupied / Rolling: `#06b6d4`, Maintenance / Alert: `#f43f5e`).