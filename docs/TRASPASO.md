# 22 — Torre de control TIJ

**Dominio:** Aviación y transporte.
Tablero de vuelos del Aeropuerto Internacional de Tijuana (TIJ / MMTJ) con un
**proceso `gen_statem` por vuelo**, supervisor dinámico, bus de eventos con
WebSocket, feed simulado con fallas inyectadas y persistencia para reconstruir
el estado tras un reinicio de la VM.

> Repositorio: <https://github.com/CarlosEliab/p22-torre-de-control-tij-entrega>
> Manual en Gist:
> <https://gist.github.com/CarlosEliab/da48ed12e3fbec9f22077040b8227f8d>
> Enunciado: [`problema/readme.md`](problema/readme.md).
> Prompt de Stitch: [`design/PROMPT_STITCH.md`](design/PROMPT_STITCH.md).
> Decisiones de interfaz: [`design/DESIGN.md`](design/DESIGN.md).

> **Nota histórica:** este documento es la bitácora técnica original del
> proyecto. Los conteos de pruebas que aparecen aquí (**31**) corresponden al
> estado previo a la simulación configurable; el proyecto actual tiene **33
> pruebas**. Para el informe final y el manual actualizado usa
> [`README.md`](../README.md) y [`docs/GUIA_USO.md`](GUIA_USO.md).

**Este README es el documento de traspaso.** Contiene todo lo que se hizo, cómo
se verificó, qué falta y los pasos exactos para dejarlo funcionando en otra
computadora. Está escrito para que lo lea una persona o un agente (OpenCode) sin
contexto previo.

---

## 0. Resumen para retomar en 2 minutos

**¿Está listo?** Para **trasladarlo, compilarlo y ejecutarlo** en otra
computadora con Erlang/OTP 27+ y rebar3: **sí**. Compila, pasan **33 pruebas**,
el tablero y la API responden, el caos reconstruye vuelos, el reinicio de la VM
recupera el estado desde disco y el release arranca en Linux. Verificado en
Windows con OTP 29.1.2 y en WSL2/Ubuntu con OTP 27 + rebar3 3.26.0 (compile sin
warnings, 33 pruebas, HTTP 200 en `/`, `/api/vuelos` y `/metrics`, release
ensamblado y ejecutado, 10-nov-2026).

Para la **rúbrica al 100 %** el código está completo: el cambio de puerta +
hora ya está implementado y probado (§13.1), la prueba de **300 clientes** ya
se midió (§13.2), el ZIP real de **Stitch** está en `design/stitch/` (§13.3) y
el **Gist** del manual está publicado:
<https://gist.github.com/CarlosEliab/da48ed12e3fbec9f22077040b8227f8d>. El
equipo es individual (§19). Lo único que queda es instalar systemd en la VM
final. El resto de este documento dice exactamente qué se hizo y cómo se
verificó.

- El proyecto está **funcional en Windows con OTP 29.1.2 y en WSL2/Ubuntu con
  OTP 27**: compila, pasan 33 pruebas, el tablero y la API responden, el caos
  reconstruye vuelos y el reinicio de la VM recupera el estado desde disco.
- **No copies `_build/` ni `data/`** a la otra computadora. `_build` se generó
  aquí con OTP 29 y contiene un release de Windows; los `.beam` de OTP 29 no
  son compatibles con OTP 27. Borra `_build/` y recompila allá.
- En la otra computadora necesitas **Erlang/OTP 27 o superior** y **rebar3**.
  No se usa Node, npm, Docker ni base de datos.
- Comandos: `rebar3 compile`, `rebar3 eunit`, `rebar3 shell`; abrir
  <http://localhost:8080>.
- Lo que falta para la **rúbrica**: solo instalar systemd en la VM final. El
  ZIP de Stitch ya está en `design/stitch/`, el Gist en
  <https://gist.github.com/CarlosEliab/da48ed12e3fbec9f22077040b8227f8d> y el
  equipo es individual. Las capturas reales están en `design/capturas/`, el
  guion de demo en `docs/DEMO_Y_RUBRICA.md`, la prueba de 300 clientes en
  `docs/CARGA_300.md` y el cambio de puerta + hora en §13.1.

---

## 1. Estado actual

### Funcional (código)

- [x] Diseño OTP documentado: procesos, supervisores y quién reinicia a quién.
- [x] Un `gen_statem` por vuelo con transiciones legales explícitas.
- [x] API HTTP + WebSocket con cowboy.
- [x] Métricas `/metrics` con `recon`.
- [x] Feed simulado: niebla, caos, mensajes fuera de orden, cascada.
- [x] Prueba de caos (matar uno y matar cinco; reconstrucción con estado).
- [x] Reinicio de la VM: respaldo en disco y recuperación de vuelos.
- [x] **Cambio simultáneo de puerta + hora** (`cambiar_puerta`), con evento
  propio, API, botón en el tablero y pruebas.
- [x] `rebar3 compile` y `rebar3 eunit` en verde (33 pruebas, 0 fallos).
- [x] `rebar3 release` ensambla y **arranca en Linux** con ERTS y
  `priv/index.html`.
- [x] Unidad systemd de ejemplo en `deploy/` y guía en `docs/VM_Y_DESPLIEGUE.md`.
- [x] Capturas reales del tablero (escritorio y móvil) y del detalle en
  `design/capturas/`.
- [x] Manual publicado como Gist:
  <https://gist.github.com/CarlosEliab/da48ed12e3fbec9f22077040b8227f8d>.
  Guion de demo con mapeo de rúbrica en `docs/DEMO_Y_RUBRICA.md`.
- [x] **300 clientes WebSocket** medidos: 300/300, 0 fallos, 24 600 mensajes en
  20 s (`docs/CARGA_300.md`).

### Entrega / rúbrica

- [x] ZIP real de Google Stitch en `design/stitch/` (§13.3).
- [x] Manual publicado como Gist:
  <https://gist.github.com/CarlosEliab/da48ed12e3fbec9f22077040b8227f8d>.
- [x] Equipo individual en §19.
- [ ] Instalar systemd en la VM final (la unidad ya está en `deploy/`).

---

## 2. Requisitos

- **Erlang/OTP 27 o superior.** Se usa el módulo nativo `json` (OTP 27) y
  `warnings_as_errors`; el código se probó con **OTP 29.1.2 (Windows)** y
  **OTP 27 + rebar3 3.26.0 (WSL2/Ubuntu)**.
- **rebar3 3.24+** (probado con 3.28.0).
- Linux, macOS o Windows. Dependencias: `cowboy` y `recon` (las baja rebar3).
- Puerto **8080** libre (configurable).
- Escritura en el directorio del proyecto para `data/p22_respaldo.bin`.

No hace falta Erlang instalado globalmente si usas un release; para compilar sí.

### Instalación rápida (Linux/macOS)

```bash
# Opción 1: gestor de paquetes (versión >= 27)
sudo apt install erlang rebar3        # Debian/Ubuntu (verifica la versión)
brew install erlang rebar3            # macOS

# Opción 2: asdf / kerl (recomendado si el repo trae una versión vieja)
```

### Instalación en Windows

Instala el instalador oficial de Erlang/OTP 27+ y rebar3 (o descarga el
`rebar3` escript y ejecútalo con `escript`). Verifica:

```bash
erl -version
rebar3 version
```

### Uso con WSL (Erlang dentro de Linux)

Si tu Erlang vive en WSL, ejecuta **todo dentro de WSL**, no desde Git Bash:

```bash
cd "/mnt/c/ruta/al/proyecto"
rm -rf _build data
rebar3 compile && rebar3 eunit
rebar3 shell          # http://localhost:8080 (WSL2 lo reenvía a Windows)
```

No mezcles entornos: un `_build` generado en WSL (Linux, OTP 27) no sirve para
el Erlang de Windows, y viceversa. Si cambias de uno a otro, borra `_build/`.
Para más velocidad, copia el proyecto a `~/` dentro de WSL en vez de compilar
sobre `/mnt/c` (OneDrive es lento).

> En la máquina donde se desarrolló **no había Erlang instalado** en Windows.
> Para compilar y probar se usó un toolchain **portátil y temporal** en
> `%TEMP%\otp_toolchain` (OTP 29.1.2 + rebar3 3.28.0), invocado así:
>
> ```bash
> export PATH="$TEMP/otp_toolchain/otp/bin:$PATH"
> "$TEMP/otp_toolchain/otp/bin/escript.exe" "$TEMP/otp_toolchain/rebar3" compile
> ```
>
> Ese directorio **no es parte del proyecto** y no se debe copiar. En la otra
> computadora usa `rebar3` normal.

---

## 3. Traslado a otra computadora (leer antes de copiar)

1. **Detén la app** si está corriendo (no copies el archivo de respaldo a medio
   escribir).
2. **Borra `_build/`** antes o después de copiar:
   ```bash
   rm -rf _build data
   ```
   Motivos:
   - `_build` se generó en Windows con OTP 29; los `.beam` no cargan en OTP 27.
   - Contiene un release de Windows (`erts-*.exe`, scripts `.cmd`).
   - El `_build` original venía de Linux con enlaces simbólicos rotos
     (`src`, `include`, `priv` de 0 bytes); rebar los recrea al compilar.
3. Copia el resto: `src/`, `test/`, `config/`, `priv/`, `design/`, `deploy/`,
   `docs/`, `scripts/`, `problema/`, `rebar.config`, `rebar.lock`, `README.md`,
   `.gitignore`.
4. En el destino:
   ```bash
   rebar3 compile
   rebar3 eunit
   ```
5. Si `data/p22_respaldo.bin` existía y quieres empezar limpio, bórralo (o
   renómbralo). La app crea `data/` sola si `persistir = true`.

**No copies** `erl_crash.dump`, `rebar3.crashdump` ni `data/`.

---

## 4. Arranque y verificación mínima

```bash
rebar3 compile          # debe terminar sin warnings (warnings_as_errors)
rebar3 eunit            # 33 tests, 0 failures
rebar3 shell            # arranca la app y el tablero
```

Abrir <http://localhost:8080>. En otra terminal:

```bash
curl -s localhost:8080/api/vuelos | head -c 400
curl -s localhost:8080/metrics | head -c 600
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/   # 200
```

Parámetros en [`config/sys.config`](config/sys.config):

| Clave | Valor | Significado |
|---|---|---|
| `puerto` | 8080 | HTTP, WebSocket, API |
| `puertas_total` | 20 | puertas físicas |
| `feed_ms` | 2000 | tick simulado (tiempo comprimido) |
| `max_vuelos_vivos` | 14 | tope de vuelos operativos |
| `caos` | true | caos automático (~3 % por tick) |
| `persistir` | true | respaldo en disco |
| `archivo_respaldo` | `data/p22_respaldo.bin` | ruta de la foto |

> El tick de 2 s **comprime el tiempo** para la demo. Las demoras siguen siendo
> minutos reales. Para un ritmo realista usa `feed_ms = 60000`.

---

## 5. Qué se hizo (bitácora literal)

Esta sección lista los cambios reales, con el síntoma que los motivó. Sirve
para que nadie "vuelva a arreglar" algo ya resuelto y para entender por qué el
código tiene ciertas guardas.

### 5.1 Preparación y artefactos

1. Se detectó que Erlang **no estaba instalado** (`erl` no existe en PATH). Se
   usó OTP 29.1.2 portátil en `%TEMP%\otp_toolchain` y rebar3 3.28.0, sin
   privilegios de administrador. No se modificó el sistema.
2. El `_build` original venía de Linux con **symlinks rotos** (`src`, `include`,
   `priv` de 0 bytes). Se borraron
   `_build/default/rel/p22_torre_de_control_tij` y
   `_build/{default,test}/lib/p22_torre_de_control_tij` para forzar a rebar a
   recrearlos. El release volvió a incluir `priv/index.html`.
3. Se agregó **persistencia en disco** para que el caso "reinicio del sistema"
   sea real ( `persistent_term` solo sobrevive procesos, no la VM).

### 5.2 `src/p22_vuelo_statem.erl` (núcleo del dominio)

4. **Bug crítico de reconstrucción:** `merge_guardado/3` devolvía **solo los
   datos**; `init/1` hacía `{Estado, Datos2} = merge_guardado(...)`, así que
   `Estado` quedaba como un mapa. Cualquier transición fallaba y el vuelo
   entraba en **bucle de reinicios**. Ahora devuelve `{Estado, Datos}` y el
   estado es un átomo de la máquina.
5. **Identidad al recuperar la VM:** al re-arrancar solo se conocía el `id`; se
   perdían `identificacion`, `aeronave`, `aerolinea`, `destino`, `origen` y
   `hora_programada`. `merge_guardado/3` ahora mezcla esos campos desde la foto
   guardada (y conserva `historial`, `motivos`, `fuentes_seq`, autoridad, etc.).
6. **Dedupe de secuencias:** `fuentes_seq` no se guardaba en el estado y `Seq=0`
   se colaba como primer mensaje. Ahora se compara `Seq =< UltimaSeq` (default
   0, las secuencias arrancan en 1) y se persiste
   `fuentes_seq => #{Fuente => Seq}` al aplicar.
7. **Consultas seguras:** `llamar_seguro/2` usa `try/catch` alrededor de
   `gen_statem:call`. Antes, un `whereis` exitoso seguido de la muerte del
   proceso (justo lo que hace el caos) producía `noproc` y tumbaba al handler
   HTTP o al feed.
8. **Transiciones ilegales:** se mantienen rechazadas por la tabla `legal/1`,
   con respuesta `{error, {transicion_no_legal, Estado, Accion}}` (HTTP 409).
9. **Efectos:** `empezar_abordaje` asigna puerta o demora +15 min con motivo
   `sin_puerta`; `despegar`/`cancelar` liberan puerta; `cancelar` avisa al feed
   para la cascada por aeronave.
10. Se corrigió el comentario que afirmaba publicar `vuelo_reconstruido` (no se
    publica; el tablero se apoya en el respaldo y en el resync).

### 5.3 `src/p22_feed.erl` (simulación y controles)

11. **Caos roto:** `inyectar_caos_base/0` hacía `exit(Id, kill)` con un entero
    (los `vivos_operativos()` son IDs), lo que provocaba `badarg`. Por eso el
    caos automático no mataba nada y el endpoint devolvía 503. Ahora resuelve
    `p22_vuelo_statem:pid_de(Id)` y solo mata si hay PID.
12. **Autoridad congelada:** el feed emitía como `sistema`; después de una
    demora de la torre, la jerarquía lo rechazaba **para siempre**. Ahora emite
    como `torre` (es la torre simulada).
13. **Altas mentirosas:** `nuevo_vuelo` respondía `{ok, Id}` aunque el proceso
    no se hubiera creado (nombre registrado). `crear_uno/1` devuelve
    `{ok, Id}` solo si `crear_vuelo/2` devolvió el Id, y `siguiente_id/0` salta
    nombres ya registrados.
14. **Recuperación:** `init/1` llama a `arrancar_vuelos_guardados/0`: si hay
    foto, crea un `gen_statem` por vuelo (cada `init` restaura estado/datos);
    si está vacía, siembra los vuelos 1..8. Se registra
    `feed: N vuelos recuperados del respaldo`.
15. **Limpieza:** `limpiar_terminales/0` retira del supervisor y del respaldo
    los vuelos `aterrizado`/`cancelado` con más de 120 s, máximo 20 por tick.
16. **Pausa/reanudación:** se guarda la referencia del `send_after`; `pausar`
    cancela la cadena y `reanudar` arranca **una sola**. Antes, reanudar dos
    veces duplicaba los ticks. Se protege `cancel_timer(undefined)`.
17. **Cascada:** `{aeronave_cancelada, ...}` busca el siguiente `programado` de
    la misma matrícula y lo cancela como `torre`.
18. Se corrigió una comprensión de listas ilegal
    (`Datos = maps:get(...)` dentro de `[... || ...]`) en
    `regreso_de_aeronave/1`.

### 5.4 `src/p22_respaldo.erl` (resiliencia)

19. Se agregó **respaldo en disco** además de ETS + `persistent_term`:
    `data/p22_respaldo.bin` (configurable). `tomar_foto/0` guarda
    `#{vuelos, puertas, stats}` y `persistir_foto/1` escribe con
    `term_to_binary(..., [compressed])` si `persistir = true`.
20. **Bug de recuperación:** el archivo se leía pero
    `binary_to_term(Bin, [safe])` lo rechazaba porque la foto contiene átomos
    creados en runtime (`puerta_7`, estados) que **aún no existen** en una VM
    nueva. El log decía "archivo de respaldo corrupto" y arrancaba limpio.
    Ahora se usa `binary_to_term(Bin)` (archivo local propio, no entrada de
    usuario) y se valida la forma `#{vuelos, puertas, stats}`.
21. `limpiar/0` borra también el archivo; `borrar_archivo/0` respeta
    `persistir` (en pruebas no toca disco).
22. `p22_feed` re-arranca un proceso por vuelo guardado y cada `init` restaura
    estado, puerta, demora, secuencias e historial.

### 5.5 API y handlers

23. **`p22_h_vuelos`:** `POST /api/vuelos` acepta cuerpo JSON **opcional**
    (`destino`, `aerolinea`, `aeronave`, `identificacion`); solo campos
    conocidos y binarios no vacíos. Responde 201 con `{ok, Id}` o 503 si el
    vuelo no arrancó. `GET` ordena por id y usa el estado vivo; si el proceso
    está entre reinicios, devuelve la imagen del respaldo con
    `de_respaldo: true`.
24. **`p22_h_vuelo_estado`:** usa `binary_to_existing_atom/2` (no crea átomos
    desde HTTP), valida `fuente` (`torre|aerolinea|sistema`), acepta `motivo`,
    `minutos` y `mensaje`, y mapea errores a 400/404/409/503. `seq_nueva()` usa
    microsegundos para no chocar con el dedupe.
25. **`p22_h_vuelo`:** 404 si no existe, 503 si el proceso está ocupado/timeout.
26. **`p22_h_metrics`:** `recon:proc_count/2` devuelve `{Pid, Valor, Info}`; el
    código anterior esperaba tuplas de 2 y fallaba. Ahora usa el tercer campo
    como `_Info`. Se agregó `diagnostico/0` (procesos, memoria, top 5 por
    memoria y reducciones) y llamadas seguras para que `/metrics` no se caiga
    durante el caos.
27. **`p22_h_index`:** en Windows el `priv` de `_build` podía ser un symlink
    roto. Se prueban varias rutas: `code:priv_dir/1`, `AppDir/priv`, cuatro
    niveles arriba (`_build/<perfil>/lib/<app>` → raíz del proyecto) y
    `priv/index.html` del cwd. La primera legible gana.
28. **`p22_h_demo` (nuevo):** `POST /api/demo/:accion` con
    `niebla|caos|fuera_de_orden|pausar|reanudar`. Traduce HTTP ↔ dominio y
    protege contra el feed en reinicio (503).
29. **`p22_web`:** se agregó la ruta `/api/demo/:accion` antes de las de vuelos
    y se mantiene el orden de cowboy.
30. **`p22_h_ws`:** el `resync` y las vistas del respaldo ahora incluyen
    `de_respaldo: true|false`, igual que `/api/vuelos`.

### 5.6 Utilidades y JSON

31. **`p22_util:map_a_json/1`:** una lista de binarios (`motivos => [<<"niebla">>]`)
    se convertía en el texto `"niebla"` en vez de `["niebla"]`, y el tablero no
    podía recorrerla. Ahora `es_cadena/1` solo trata como texto las listas de
    enteros; las listas de binarios/átomos/mapas van como arreglo. Se movió el
    manejo de `nil`/`null` antes de la cláusula genérica de átomos.
32. **`p22_util`** serializa con el módulo `json` nativo de OTP 27.

### 5.7 Pruebas

33. `test/p22_integracion_tests.erl` tolera `no_encontrado` en la primera
    vuelta: el guardado inicial del vuelo viaja como `cast` y puede no estar
    procesado cuando la prueba empieza a mirar.
34. Se reemplazaron usos de `catch Expr` por `try/catch` (OTP 29 marca el
    primero como obsoleto y `warnings_as_errors` rompe la compilación).
35. Resultado final: **33 tests, 0 failures** (ver §10).

### 5.8 Interfaz (`priv/index.html`)

36. `refrescarTodo` leía `{ok, vuelos}` como si fuera un arreglo; ahora usa
    `datos.vuelos`. Sin esto, el refresco REST rompía el tablero.
37. Se agregaron botones de demo: **Niebla +20**, **Caos**, **Fuera de orden**
    (y la API de pausar/reanudar).
38. El modal de detalle muestra **solo las acciones legales** según el estado
    (`LEGAL`/`ETIQUETA`) y renderiza `motivos` con `lista()`.
39. Se actualizan por WebSocket `hora_estimada`, `motivos`, `demora_min`,
    `puerta` y `de_respaldo`.
40. Se corrigió el refresco tras una acción y el manejo del 409 (transición
    ilegal) sin errores JS no controlados.

### 5.9 Documentación y operación

41. Se creó `design/DESIGN.md` (sistema de diseño implementado).
42. Se creó `deploy/p22-torre-de-control-tij.service` (unidad systemd).
43. Se actualizó `.gitignore` con `data/` y `rebar3.crashdump`.
44. Se reescribió este README con la bitácora y el checklist.
45. **Caso difícil “cambia de puerta y de hora a la vez” implementado:**
    `p22_puertas:asignar/2`, `liberar/2` y `es_puerta/1`; acción
    `cambiar_puerta` en `legal/1`; efecto que toma la nueva puerta antes de
    liberar la vieja, conserva el estado y acumula minutos; evento
    `cambio_puerta` con puerta/hora anterior y nueva; validación en
    `p22_h_vuelo_estado`; fila **Cambiar puerta** en el modal. Tres pruebas
    nuevas de la máquina de estados y una del asignador.
46. **Bug del release en Linux:** `config/vm.args` traía `-config sys.config`,
    pero relx ya pasa su propio `sys.config`; el kernel buscaba `./sys.config`
    y abortaba con `configuration file not found`. Se quitó esa línea y se
    añadieron los argumentos recomendados del repo
    (`+S 4:4 +SDcpu 4:4 +SDio 10 +K true +P 1048576`).
47. **Verificación en WSL2/Ubuntu (OTP 27):** compile sin warnings, 33 tests,
    app con HTTP 200 y release ensamblado y ejecutado con `/`, `/api/vuelos` y
    `/metrics` en 200.
48. **Entregables de rúbrica:** capturas reales en `design/capturas/`, manual
    para Gist en `docs/GUIA_USO.md`, guía de VM en `docs/VM_Y_DESPLIEGUE.md`,
    guion de demo y mapeo de rúbrica en `docs/DEMO_Y_RUBRICA.md`, e índice de
    Stitch en `design/CAPTURAS.md`.

---

## 6. Arquitectura OTP

```
p22_torre_de_control_tij_sup   (rest_for_one, 10 reinicios / 60 s)
├── p22_respaldo               gen_server  ETS públicas + persistent_term + archivo
├── p22_eventos                gen_server  bus de eventos y suscripciones WS
├── p22_puertas                gen_server  asignador de 20 puertas
├── p22_vuelos_sup             supervisor  simple_one_for_one
│   └── p22_vuelo_statem × N   gen_statem  un proceso por vuelo
├── p22_feed                   gen_server  simulación (tick) y escenarios
└── p22_web                    gen_server  cowboy: API, tablero, WS, métricas
```

**`rest_for_one`:** el orden expresa dependencias. Los vuelos necesitan
respaldo, bus y puertas; la web necesita el bus. Si cae `p22_respaldo`, se
reinicia todo lo que depende de él en orden y cada vuelo relee su estado. Si
solo cae `p22_web`, los vuelos no se tocan.

**`simple_one_for_one`:** el número de vuelos cambia (120/día). Todos comparten
módulo y arranque; `permanent` hace que un vuelo muerto se reconstruya.

**Un proceso por vuelo:** las reglas del ciclo de vida quedan aisladas; una
transición ilegal se rechaza en el `gen_statem`, no en el handler. La caída de
un vuelo no afecta a los demás y el caos es significativo.

**Dónde vive el estado:**

1. El `gen_statem` es la verdad en caliente.
2. Antes de publicar cada cambio, `p22_respaldo:guardar_vuelo/3` lo escribe en
   ETS y en `persistent_term` (sobrevive a la caída del proceso/árbol OTP).
3. Si `persistir = true`, también en `data/p22_respaldo.bin` (sobrevive a la
   VM). Al arrancar, el feed crea un proceso por vuelo guardado.

La API y el WebSocket consultan al proceso; si está entre reinicios, responden
con la imagen del respaldo (`de_respaldo: true`). Por eso el tablero no
parpadea.

---

## 7. Máquina de estados

| Estado | Acciones legales | Efectos |
|---|---|---|
| `programado` | `empezar_abordaje`, `demorar`, `cambiar_puerta`, `cancelar` | — |
| `demorado` | `empezar_abordaje`, `fin_demora`, `cambiar_puerta`, `cancelar` | acumula `demora_min`, `hora_estimada`, motivos |
| `abordando` | `despegar`, `cambiar_puerta`, `cancelar` | ocupa una puerta |
| `despego` | `aterrizar` | libera la puerta al despegar |
| `aterrizado` | — (terminal) | — |
| `cancelado` | — (terminal) | libera puerta y avisa al feed (cascada) |

Reglas transversales:

- **Fuera de orden:** cada evento trae `{Fuente, Seq}`; se guarda la última
  secuencia **por fuente**. Si `Seq =< última`, se ignora con
  `secuencia_repetida`. Las secuencias arrancan en 1; `0` siempre es vieja.
- **Fuentes contradictorias:** `torre(3) > aerolinea(2) > sistema(1)`. Un
  cambio de menor autoridad se rechaza con `autoridad_insuficiente`.
- **Sin puertas:** `empezar_abordaje` pasa a `demorado` con +15 min y motivo
  `sin_puerta`.
- **Cambio de puerta:** `cambiar_puerta` toma la nueva puerta **antes** de
  liberar la vieja. Si la nueva está ocupada por otro vuelo, devuelve
  `{puerta_ocupada, Otro}` y el vuelo conserva la anterior. Conserva el estado
  actual y, si trae `minutos`, actualiza `demora_min`/`hora_estimada`.
- **Cascada:** al cancelar, el feed cancela el siguiente `programado` de la
  misma aeronave.
- **Persistencia antes de publicar:** si matan el proceso justo después de la
  transición, el respaldo ya tiene el estado nuevo.

### Simplificación deliberada de estados

El enunciado lista estados reales (check-in, última llamada, puerta cerrada,
rodando, en vuelo...). El modelo usa **6 estados** que agrupan esos matices:

- `programado` ≈ programado + check-in abierto.
- `abordando` ≈ abordando + última llamada + puerta cerrada.
- `despego` ≈ rodando + despegue + en vuelo.
- `aterrizado`, `demorado`, `cancelado` son explícitos.

Es una decisión de alcance, no un olvido: la máquina cubre las transiciones
legales del ciclo y los casos difíciles del enunciado. Si la rúbrica exige los
estados intermedios, hay que extender `legal/1`, `base_tabla/0`, el tablero y
las pruebas.

---

## 8. API

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/` | tablero (kanban en vivo) |
| GET | `/api/vuelos` | lista de vuelos |
| POST | `/api/vuelos` | crea un vuelo; cuerpo opcional |
| GET | `/api/vuelos/:id` | detalle con historial |
| POST | `/api/vuelos/:id/estado` | transición manual |
| POST | `/api/demo/:accion` | `niebla`, `caos`, `fuera_de_orden`, `pausar`, `reanudar` |
| GET | `/metrics` | métricas + diagnóstico `recon` |
| GET | `/ws` | WebSocket de eventos |

Ejemplos:

```bash
# Niebla: +20 min a todos los programados
curl -X POST localhost:8080/api/demo/niebla

# Demora como torre
curl -X POST localhost:8080/api/vuelos/7/estado \
  -H 'content-type: application/json' \
  -d '{"accion":"demorar","minutos":20,"motivo":"niebla","fuente":"torre"}'

# Cambiar puerta Y hora en una sola operacion
curl -X POST localhost:8080/api/vuelos/7/estado \
  -H 'content-type: application/json' \
  -d '{"accion":"cambiar_puerta","fuente":"torre",
       "puerta":"puerta_5","minutos":15,"motivo":"cambio operativo"}'

# Despegar sin abordar: 409
curl -i -X POST localhost:8080/api/vuelos/7/estado \
  -H 'content-type: application/json' \
  -d '{"accion":"despegar"}'

# Crear un vuelo con datos propios
curl -X POST localhost:8080/api/vuelos \
  -H 'content-type: application/json' \
  -d '{"destino":"CUN","aerolinea":"Volaris"}'

# Caos y fuera de orden
curl -X POST localhost:8080/api/demo/caos
curl -X POST localhost:8080/api/demo/fuera_de_orden
```

Respuestas de error esperadas: 400 (cuerpo/id inválido o puerta con formato
incorrecto), 404 (vuelo inexistente), 409 (transición ilegal, secuencia
repetida, autoridad insuficiente, puerta ocupada o sin puertas), 503 (servicio
ocupado o feed en reinicio). Una puerta ocupada responde con `vuelo_ocupante`.

`cambiar_puerta` acepta `puerta` (opcional; si se omite, asigna una libre) y
`minutos` (opcional; se suman a la demora y recalculan `hora_estimada`).

### Eventos WebSocket

`resync` (snapshot inicial), `vuelo_creado`, `cambio_estado`,
`cambio_puerta` (con `puerta_anterior`, `puerta_nueva`, `hora_anterior` y
`hora_nueva`), `puerta_asignada`, `puerta_liberada`, `evento_ignorado`,
`transicion_rechazada`, `alerta`, `caos`.

El cliente reconecta cada 2 s y, al abrir, recibe `resync` con la lista
completa. El bus serializa **una vez** por evento y hace broadcast a todos los
suscriptores. Cada suscriptor se monitorea y se elimina solo al morir.

### `/metrics`

Incluye `vuelos.por_estado`, `puertas` (libres/ocupadas/total),
`eventos_por_minuto`, `clientes_tablero`, contadores por tipo, estado del bus,
`uptime_segundos` y `sistema` con `recon` (procesos, memoria, top 5 por memoria
y reducciones).

---

## 9. Cómo demostrar el escenario

1. `rebar3 shell` y abrir el tablero.
2. **Niebla +20:** demora todas las salidas programadas y publica una alerta.
3. **Caos:** mata un proceso; el supervisor lo reconstruye con su estado y
   puerta (evento `caos` en la bitácora).
4. **Fuera de orden:** envía una secuencia vieja; el vuelo responde
   `secuencia_repetida` y el tablero lo registra como ignorado.
5. **Detalle:** puerta, horas, demora, motivos, bitácora y solo las acciones
   legales.
6. **Cambio de puerta + hora:** en el detalle de un vuelo `abordando`, escribir
   `puerta_5` y `15` minutos, pulsar **Aplicar** y mostrar que la puerta vieja
   queda libre, la nueva ocupada, la hora se corre 15 min y el estado se
   conserva. Intentar la puerta de otro vuelo debe dar **409**.
7. `POST /api/demo/pausar` congela el feed; `reanudar` lo retoma.

---

## 10. Pruebas y resultados

```bash
rebar3 eunit
# 33 tests, 0 failures
```

La misma corrida se hizo en **WSL2/Ubuntu con OTP 27 y rebar3 3.26.0**
(10-nov-2026), sobre una copia sin `_build/` ni `data/`: `rebar3 compile` sin
warnings y **33 tests, 0 failures**. También se arrancó la app y se comprobó
con HTTP real: `GET /` → **200**, `GET /api/vuelos` → **200**, `GET /metrics`
→ **200**. El **release se ensambló y arrancó en Linux** con esos mismos tres
endpoints en **200**.

Cobertura:

- ciclo de vida legal completo y rechazo de transiciones ilegales;
- deduplicación por secuencia y jerarquía de fuentes;
- asignación/liberación/agotamiento de puertas, asignación de una puerta
  concreta y demora automática sin puerta;
- **cambio de puerta + hora en una sola transición** (libera la vieja, ocupa la
  nueva, acumula minutos y conserva el estado);
- rechazo del cambio a una puerta ocupada por otro vuelo y de una puerta
  inexistente;
- cascada de cancelación por aeronave;
- reconstrucción tras `exit(Pid, kill)` (estado, puerta, demora, PID nuevo);
- caos en serie: 5 vuelos muertos y el árbol/bus sigue vivo;
- API HTTP real (`GET /api/vuelos`, `/metrics`, `/`, POST de estados) con
  puerto efímero;
- estructura del árbol de supervisión y re-hidratación del respaldo.

### 10.1 Prueba de caos (qué se mató, qué se esperaba, qué ocurrió)

**En pruebas (`test/p22_caos_tests.erl`):**

| Qué se mató | Qué se esperaba | Qué ocurrió |
|---|---|---|
| Vuelo 808 en `abordando` | PID nuevo, mismo estado y puerta; respaldo igual | Pasó: PID distinto, `abordando`, puerta conservada |
| Vuelo 809 en `demorado` (30 min, motivo `niebla`) | Recuperar 30 min y motivo | Pasó |
| 5 vuelos (701–705) en serie | El bus y el árbol siguen vivos; los 5 vuelven | Pasó: `pong`, puertas/respaldo vivos, 5 vuelos `programado` |

**En vivo:** `POST /api/demo/caos` mató el vuelo 7 (estaba en `despego`); el log
mostró **una sola** reconstrucción (`vuelo 7 en estado despego`) y el vuelo
siguió operando. No hubo bucle de reinicios.

### 10.2 Carga: 300 clientes WebSocket

Se abrieron **300 conexiones concurrentes** contra `/ws` durante 20 s con el
feed activo, desde la misma VM (WSL2/Ubuntu, OTP 27):

| Métrica | Resultado |
|---|---|
| Conexiones establecidas | **300/300** |
| Fallos / errores | **0** |
| `resync` recibidos | **300** |
| Mensajes entregados | **24 600** (82 por cliente) |
| Handshake p95 | **97.6 ms** (máx. 132.7 ms) |
| Memoria en caliente | **58.8 MB**, 411 procesos |
| Memoria al desconectar | **40.6 MB**, 120 procesos |

Detalle, interpretación y comando reproducible en
[`docs/CARGA_300.md`](docs/CARGA_300.md). El `lag` reportado (~0.9 s) es un
límite superior por la granularidad de `ts` en segundos, no una latencia real.

### 10.3 Reinicio de la VM (persistencia)

Se mató el nodo completo y se reinició con el mismo `data/p22_respaldo.bin`.
El log mostró:

```
p22_respaldo foto recuperada de data/p22_respaldo.bin
feed: 65 vuelos recuperados del respaldo
```

Los vuelos conservaron id, identificación, destino e historial. Ejemplo
verificado: el `109` seguía siendo `TJ-209 → SJD`, con 4 entradas de bitácora
(había avanzado a `aterrizado` por el feed tras recuperarse).

> La foto se reescribe en cada cambio con `file:write_file/2` (no atómica). Si
> el kill coincide exactamente con la escritura, el archivo puede quedar
> parcial: la app lo detecta, registra "archivo de respaldo corrupto" y arranca
> limpio. Para producción, escribir a un `.tmp` y renombrar.

---

## 11. Supuestos y cifras

Del enunciado (no verificadas contra una fuente externa; el propio documento
dice que son órdenes de magnitud):

- TIJ, **una sola pista**, ~**120 vuelos/día**, picos de **10 movimientos/hora**.
- **300 clientes** viendo el tablero.
- Niebla matutina que demora **20 min** todas las salidas.
- Un vuelo que cambia de puerta y de hora a la vez.

Supuestos propios:

- **20 puertas** (configurable) y **14 vuelos vivos** como tope de simulación.
- La **pista no se modela como recurso separado**; se asume que la puerta y el
  turno de despegue bastan para el alcance. Modelarla sería el siguiente paso.
- Los vuelos son **simulados**; no se consume OpenSky/AviationStack ni el FIDS.
- El tiempo de la demo está **comprimido** (tick 2 s).
- **Autoridad:** una vez que la torre fija un estado, ni la aerolínea ni el
  sistema lo revierten.
- Los estados reales se agrupan en 6 (ver §7).

---

## 12. Limitaciones conocidas

- Un átomo por vuelo (`p22_vuelo_<id>`): aceptable para 120/día; para corridas
  muy largas conviene un registro (`via`/`gproc`).
- Un solo nodo, sin distribución ni réplica.
- Sin autenticación: la API es de demo interna.
- `persistent_term:put` en cada cambio recorre/actualiza la foto completa;
  para volúmenes mayores conviene un debounce o DETS/Mnesia.
- La escritura del respaldo no es atómica (§10.3).
- La prueba de **300 clientes** se hizo en **loopback local** (misma VM); no se
  probó a través de Internet, proxy o TLS. El `lag` está limitado por la
  granularidad de `ts` en segundos (`docs/CARGA_300.md`).
- **Stitch:** el ZIP real está en `design/stitch/` (tres pantallas, HTML,
  capturas y `DESIGN.md`); las capturas de la app real están en
  `design/capturas/`. La app se alineó a mano con su paleta, tipografía y
  estructura; el HTML de producción no se generó desde Stitch.
- **No se probó** en un teléfono físico; el CSS es responsive y se revisó en
  el navegador a 390 px (`design/capturas/tablero-movil.png`).
- La **unidad systemd** se incluye como plantilla; en esta máquina se probó el
  release en foreground, no la instalación con `systemctl` (requiere root).
- El cambio de puerta conserva el estado actual (no pasa a `demorado`): es una
  decisión para no perder el abordaje; la hora sí se actualiza.
- OTP 28 no se probó. OTP 27 sí (WSL2/Ubuntu, rebar3 3.26.0), OTP 29.1.2
  (Windows); release en Linux verificado.

---

## 13. Estado de entrega y pendientes

### 13.1 Cambio de puerta + hora simultáneo — IMPLEMENTADO

Ya no es un pendiente. La acción `cambiar_puerta` está en `legal/1` para
`programado`, `demorado` y `abordando` y hace, en una sola transición:

1. valida que la puerta exista (`p22_puertas:es_puerta/1`);
2. toma la nueva puerta (`asignar/2`) **antes** de liberar la vieja;
3. si la nueva está ocupada por otro vuelo, devuelve `{puerta_ocupada, Otro}`
   y no toca nada;
4. libera la puerta anterior con `liberar/2` (por puerta, no por vuelo);
5. si trae `minutos`, acumula `demora_min`, recalcula `hora_estimada` y agrega
   el motivo;
6. conserva el estado actual (si estaba `abordando`, sigue `abordando`);
7. publica `cambio_puerta` con `puerta_anterior`, `puerta_nueva`,
   `hora_anterior` y `hora_nueva`.

La API acepta `{"accion":"cambiar_puerta","puerta":"puerta_5","minutos":15}`
y el modal tiene la fila **Cambiar puerta**. Pruebas nuevas:

- `cambio_puerta_y_hora_test`: A→B y +15 min; A libre, B ocupada, estado igual.
- `cambio_puerta_ocupada_test`: puerta de otro vuelo → error y nada cambia.
- `cambio_puerta_rechazos_test`: puerta inexistente y acción ilegal tras
  despegar.
- `asignar_puerta_concreta_test`: asignación idempotente, liberación por puerta
  y validación de existencia.

### 13.2 Evidencia de 300 clientes — MEDIDO

Se ejecutó [`scripts/prueba_carga.py`](scripts/prueba_carga.py) con 300
conexiones durante 20 s: **300/300 conectados, 0 fallos, 300 `resync`, 24 600
mensajes**, handshake p95 de 97.6 ms y 58.8 MB de memoria en caliente. El
detalle y la interpretación están en [`docs/CARGA_300.md`](docs/CARGA_300.md).

Pendiente opcional: repetirlo a través de red real/TLS y con un timestamp en
microsegundos para medir latencia exacta de entrega.

### 13.3 Entrega visual

Hecho:

- Capturas reales en `design/capturas/`: tablero de escritorio, tablero móvil a
  390 px y modal de detalle con **Cambiar puerta**.
- **Pase visual alineado a Stitch:** tokens de color, tipografía Inter/JetBrains
  Mono, barra lateral, topbar con estado en vivo, KPIs, seis columnas y modal.
- `design/CAPTURAS.md` describe cada imagen.

![Tablero de escritorio](design/capturas/tablero-escritorio.png)

![Detalle con cambio de puerta](design/capturas/detalle-cambio-puerta.png)

La versión móvil está en
[`design/capturas/tablero-movil.png`](design/capturas/tablero-movil.png).

**Google Stitch — entregado:** el ZIP real está en
[`design/stitch/p22-torre-de-control-tij.zip`](design/stitch/p22-torre-de-control-tij.zip)
y descomprimido en `design/stitch/stitch_torre_de_control_tij/`. Incluye las
tres pantallas (tablero, modal y móvil 390 px), su HTML, capturas y
`DESIGN.md`.

![Tablero diseñado en Google Stitch](design/stitch/stitch_torre_de_control_tij/tablero_principal_torre_de_control_tij/screen.png)

El detalle del vuelo con **Cambiar puerta** está en
[`.../detalle_del_vuelo_modal_tj_101_torre_de_control_tij/screen.png`](design/stitch/stitch_torre_de_control_tij/detalle_del_vuelo_modal_tj_101_torre_de_control_tij/screen.png)
y la versión móvil en
[`.../tablero_m_vil_390px_torre_de_control_tij/screen.png`](design/stitch/stitch_torre_de_control_tij/tablero_m_vil_390px_torre_de_control_tij/screen.png).

### 13.4 Otros

- Instalar y probar la unidad systemd en el servidor Linux definitivo
  (`docs/VM_Y_DESPLIEGUE.md`); el release ya se probó en Linux.
- Opcional: modelar la pista como recurso (`p22_pista`) y pruebas de contención.
- Opcional: autenticación si se despliega fuera de una red interna.

---

## 14. Checklist de aceptación (para OpenCode)

Copia el proyecto **sin `_build/` ni `data/`** y ejecuta en orden. No marques
un paso sin ver su salida.

### A. Toolchain

- [ ] `erl -version` muestra OTP **27+**.
- [ ] `rebar3 version` funciona.
- [ ] Si usas WSL, ejecutas los comandos **dentro de WSL** y no mezclas su
      `_build` con el de Windows.

### B. Compilación y pruebas

- [ ] `rebar3 compile` termina con exit 0 y **sin warnings**.
- [ ] `rebar3 eunit` imprime `33 tests, 0 failures` (exit 0).
- [ ] Si agregas pruebas, actualiza el número en este README.

### C. Arranque

- [ ] `rebar3 shell` arranca sin crash.
- [ ] `curl -o /dev/null -w '%{http_code}' localhost:8080/` → `200`.
- [ ] El HTML contiene `Torre de control TIJ`.
- [ ] El log muestra `p22_web escuchando` y `feed ... listo`.

### D. API

- [ ] `GET /api/vuelos` → 200 con `ok: true` y al menos 8 vuelos.
- [ ] `GET /api/vuelos/1` → 200 con `historial`.
- [ ] `POST /api/vuelos/1/estado` con `{"accion":"empezar_abordaje"}` → 200.
- [ ] La misma petición con `{"accion":"aterrizar"}` → 409.
- [ ] `POST /api/vuelos/1/estado` con `{"accion":"cambiar_puerta",
      "puerta":"puerta_5","minutos":15}` → 200; el detalle muestra la nueva
      puerta, +15 min y el estado sin cambiar.
- [ ] Intentar `cambiar_puerta` a la puerta de otro vuelo → 409 con
      `vuelo_ocupante`.
- [ ] `GET /api/vuelos/99999` → 404.
- [ ] `POST /api/demo/niebla` → 200 y vuelos `demorado` con +20.
- [ ] `POST /api/demo/fuera_de_orden` → 200 con `resultado` que menciona
      `secuencia_repetida`.
- [ ] `GET /metrics` → 200; incluye `vuelos`, `puertas`, `sistema` y
      `top_memoria`.

### E. WebSocket

- [ ] La consola del navegador no tiene errores (salvo el 409 esperado si se
      prueba una transición ilegal).
- [ ] El punto de WebSocket está en verde y llegan eventos.
- [ ] Al refrescar, el tablero se repinta con `resync` (sin parpadeo).
- [ ] `clientes_tablero` en `/metrics` coincide con las pestañas abiertas.

### F. Caos

- [ ] `POST /api/demo/caos` → 200 con `vuelo: Id`.
- [ ] El log muestra **una** reconstrucción (`vuelo N en estado ...`).
- [ ] `GET /api/vuelos/:id` sigue devolviendo el mismo estado/datos.
- [ ] No hay bucle de reinicios en el log.

### G. Reinicio de VM (persistencia)

- [ ] Con `persistir = true`, espera 20 s y confirma que existe
      `data/p22_respaldo.bin` (tamaño > 0).
- [ ] Anota `id`, `identificacion` y `destino` de 3 vuelos.
- [ ] Mata el proceso de la VM (no un `Ctrl+C` suave, si quieres probar el
      caso duro):
      - Linux: `ss -ltnp | grep 8080` y `kill -9 <pid>`.
      - Windows: `Get-NetTCPConnection -LocalPort 8080 -State Listen` y
        `Stop-Process -Id <pid> -Force` (por PID, no por nombre).
- [ ] Vuelve a arrancar.
- [ ] El log muestra `foto recuperada` y `feed: N vuelos recuperados`.
- [ ] Los 3 vuelos conservan id, identificación, destino e historial.

### H. Release

- [ ] `rebar3 release` termina con `Release successfully assembled`.
- [ ] `_build/default/rel/p22_torre_de_control_tij/bin/p22_torre_de_control_tij foreground`
      arranca y responde 200.
- [ ] El release incluye `priv/index.html` (el tablero no da 500).
- [ ] En Linux, `/`, `/api/vuelos` y `/metrics` responden 200 desde el release
      (verificado).
- [ ] En el servidor definitivo, `systemd` con
      `deploy/p22-torre-de-control-tij.service`.

### I. Entrega

- [x] ZIP de Stitch exportado en `design/stitch/` y capturas de Stitch.
- [x] Capturas de la app real en `design/capturas/`.
- [x] Gist publicado: <https://gist.github.com/CarlosEliab/da48ed12e3fbec9f22077040b8227f8d>.
- [ ] Equipo lleno.
- [x] Resultados reales de 300 clientes en `docs/CARGA_300.md` y §10.3.

---

## 15. Troubleshooting

| Síntoma | Causa probable | Solución |
|---|---|---|
| `rebar3: command not found` | no está en PATH | instala rebar3 o usa el escript |
| `undefined function json:encode/1` | OTP < 27 | actualiza Erlang/OTP |
| `.beam` con "badfile"/"not a BEAM file" | copiaste `_build` de otra versión | `rm -rf _build` y recompila |
| `eaddrinuse` en 8080 | otra instancia | cambia `puerto` o mata el PID del puerto |
| `/` responde 500 "falta priv/index.html" | `priv` no se copió o el symlink está roto | recompila; verifica `priv/index.html` |
| El tablero no se actualiza | WebSocket caído | revisa la consola; el cliente reconecta cada 2 s |
| `data/p22_respaldo.bin` corrupto | kill durante la escritura | bórralo; arranca limpio (ver §10.3) |
| `/metrics` sin `top_memoria` | `recon` no arrancó | revisa `rebar.lock`/dependencias |
| Release de Windows no corre en Linux | binarios/scripts de otra plataforma | genera el release en el destino |
| Release: `configuration file not found` | `vm.args` con `-config sys.config` duplicado | usa el `config/vm.args` sin `-config` |

---

## 16. Release y systemd

```bash
rebar3 release
# Linux/macOS:
_build/default/rel/p22_torre_de_control_tij/bin/p22_torre_de_control_tij foreground
```

El release incluye ERTS, dependencias y `priv/index.html`. **Genéralo en el
mismo sistema operativo donde se despliega**: relx crea el script de esa
plataforma.

> `config/vm.args` **no** debe traer `-config sys.config`: relx ya pasa su
> propio `sys.config`. Si lo duplicas, el kernel busca `./sys.config` y aborta
> con `configuration file not found`. Ya está corregido y probado en Linux
> (ver §13.1 y `docs/VM_Y_DESPLIEGUE.md`).

Unidad de ejemplo en
[`deploy/p22-torre-de-control-tij.service`](deploy/p22-torre-de-control-tij.service):

```bash
sudo useradd --system --home /opt/p22 p22
sudo mkdir -p /opt/p22 && sudo chown p22:p22 /opt/p22
sudo cp -r _build/default/rel/p22_torre_de_control_tij/* /opt/p22/
sudo cp deploy/p22-torre-de-control-tij.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now p22-torre-de-control-tij
```

El respaldo queda en `/opt/p22/data/p22_respaldo.bin` (el usuario `p22`
necesita escritura ahí).

---

## 17. Estructura

```
config/         sys.config y vm.args
deploy/         unidad systemd de ejemplo
design/         prompt de Stitch, DESIGN.md, CAPTURAS.md y capturas/
docs/           manual para Gist, guía de VM, demo, rúbrica y carga de 300
scripts/        prueba_carga.py (300 clientes WebSocket)
priv/           index.html (tablero)
problema/       enunciado
src/            aplicación, supervisores, dominio, API y handlers
test/           eunit: dominio, puertas, caos, integración y árbol
```

Mapa rápido de módulos:

| Módulo | Responsabilidad |
|---|---|
| `p22_torre_de_control_tij_app/sup` | arranque y árbol OTP |
| `p22_respaldo` | ETS, `persistent_term`, archivo |
| `p22_eventos` | bus, contadores, suscripciones |
| `p22_puertas` | asignación de puertas |
| `p22_vuelos_sup` | supervisor dinámico |
| `p22_vuelo_statem` | máquina de estados por vuelo |
| `p22_feed` | simulación, caos, niebla, cascada, recuperación |
| `p22_web` + `p22_h_*` | cowboy, API, WS, tablero, métricas |
| `p22_util` | JSON y fechas |

---

## 18. Guión sugerido para OpenCode

Puedes pegarle esto tal cual:

> Lee `README.md` completo, en especial §5 (bitácora), §13 (pendientes) y §14
> (checklist). El proyecto es Erlang/OTP con rebar3; no agregues Node ni
> servicios externos. Primero borra `_build/` y `data/`, luego ejecuta
> `rebar3 compile` y `rebar3 eunit` (deben pasar **31** pruebas). Arranca con
> `rebar3 shell` y verifica el checklist §14 contra <http://localhost:8080>.
> El cambio de puerta + hora ya está implementado (§13.1): no lo rehagas; si lo
> tocas, actualiza `test/p22_vuelo_statem_tests.erl` y la tabla del README.
> El ZIP de Stitch ya está en `design/stitch/` y la prueba de 300 clientes en
> `docs/CARGA_300.md`. El Gist ya está publicado y el ZIP de Stitch ya está en
> `design/stitch/`; solo falta instalar systemd en la VM final. No inventes
> capturas ni cifras: si no existen, deja el pendiente marcado.

---

## 19. Equipo

Proyecto **individual**: la misma persona cubre los tres roles.

| Rol | Integrante |
|---|---|
| Backend (OTP) | Carlos |
| Frontend (Stitch + cowboy) | Carlos |
| Ops/QA | Carlos |
