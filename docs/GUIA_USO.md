# Torre de control TIJ — manual de uso

> **Materia:** Programación Lógica y Funcional  
> **Docente:** René Solís Reyes  
> **Alumno:** Rodriguez Peraza Carlos Eliab  
> **No. Control:** 23212719  
> **Grupo:** 2-3

**Repositorio:** <https://github.com/CarlosEliab/p22-torre-de-control-tij-entrega>

Tablero en tiempo real de los vuelos del Aeropuerto Internacional de Tijuana
(TIJ / MMTJ). Cada vuelo es un proceso Erlang (`gen_statem`) y el tablero se
actualiza por WebSocket, sin recargar la página.

Este manual está pensado para el cliente que va a instalar, ejecutar y usar el
sistema. No necesitas saber Erlang para operarlo.

---

## 1. Qué hace

- Muestra los vuelos agrupados por estado: **Programado, Demorado, Abordando,
  Despegó, Aterrizó y Cancelado**.
- Publica los cambios a todos los tableros conectados en tiempo real.
- Controla un recurso finito: **20 puertas** (configurable).
- Permite operar como torre: abordar, demorar, despegar, aterrizar, cancelar y
  **cambiar de puerta y de hora en una sola operación**.
- Inyecta fallas para la demo: niebla (+20 min), caos (mata un proceso y lo
  reconstruye), mensajes fuera de orden y pausa/reanudación del feed.
- **Ajusta la velocidad de la simulación en caliente** (Muy lento, Lento,
  Normal, Rápido o Personalizado) y permite crear vuelos con una hora de
  entrada definida.
- Guarda el estado en disco: si se reinicia la máquina, los vuelos se recuperan.
- Expone métricas y diagnóstico con `recon` en `/metrics`.

---

## 2. Requisitos

| Componente | Versión / nota |
|---|---|
| Erlang/OTP | **27 o superior** |
| rebar3 | 3.24 o superior (probado con 3.26 y 3.28) |
| Sistema | Linux, macOS o Windows. También WSL2 con Ubuntu |
| Puerto | **8080** libre (se cambia en `config/sys.config`) |
| Disco | permiso de escritura para `data/p22_respaldo.bin` |

No usa Node, npm, Docker, PostgreSQL ni servicios externos.

### Instalación en Ubuntu / WSL

```bash
sudo apt update
sudo apt install -y erlang rebar3
erl -version        # debe decir OTP 27 o mayor
rebar3 version
```

Si el repositorio de tu distribución trae una versión anterior a OTP 27,
instala con [asdf](https://asdf-vm.com/) o
[kerl](https://github.com/kerl/kerl) y selecciona OTP 27+.

En Windows puedes usar WSL2:

```bash
wsl --install -d Ubuntu
```

---

## 3. Instalación del proyecto

1. Copia la carpeta del proyecto (sin `_build/` ni `data/`).
2. Entra a la carpeta:

```bash
cd "/ruta/a/22-torre-de-control-tij"
rm -rf _build data
```

> **Importante:** no copies `_build/` de otra computadora. Los `.beam` y el
> release dependen del sistema operativo y de la versión de Erlang. Se genera
> de nuevo con `rebar3`.

3. Compila y verifica:

```bash
rebar3 compile     # debe terminar sin warnings
rebar3 eunit       # 33 pruebas, 0 fallos
```

---

## 4. Arrancar

```bash
rebar3 shell
```

Abre el navegador en:

**http://localhost:8080**

Si usas WSL2, el puerto se reenvía solo a Windows. Si no responde, ejecuta el
navegador dentro del entorno o revisa la sección de problemas.

Para detener la aplicación: `Ctrl+C` dos veces, o cierra la terminal.

### Arranque como release (sin rebar3)

```bash
rebar3 release
_build/default/rel/p22_torre_de_control_tij/bin/p22_torre_de_control_tij foreground
```

El release incluye Erlang, las dependencias y el tablero. Debe generarse en el
mismo sistema operativo donde se va a ejecutar (Linux para Linux).

---

## 5. La pantalla

### Encabezado

- **WebSocket:** punto verde si el tablero está conectado; si se cae, el
  cliente reintenta cada 2 segundos.
- **Vuelos:** total de vuelos en memoria.
- **Puertas libres:** de las 20 configuradas.
- **Eventos/min:** eventos publicados en el bus de la torre en los
  últimos 60 segundos (cambios de estado, puertas, alertas y caos).
- **Demora promedio:** promedio de minutos de demora de los vuelos
  demorados (`demoras.promedio_min` en `/metrics`).
- **Tableros conectados:** clientes WebSocket activos.

### Columnas

Cada columna es un estado. Cada tarjeta muestra:

- Identificación del vuelo (por ejemplo `TJ-101`).
- Hora estimada (o programada si no hay demora).
- Aerolínea y destino.
- Badges: `🚪 puerta_5`, `⏱ +15 min`, `respaldo` si el dato viene del respaldo
  porque el proceso está reconstruyéndose.

### Panel de simulación

Encima del tablero hay un panel para controlar el ritmo sin reiniciar:

| Control | Qué hace |
|---|---|
| **Velocidad** | Cambia entre `Muy lento`, `Lento`, `Normal`, `Rápido` y `Personalizado`. |
| **Nuevo vuelo cada X s** | Intervalo entre altas automáticas (se aplica con perfil personalizado). |
| **Aplicar ritmo** | Envía el cambio al servidor en caliente. |
| **Pausar / Reanudar** | Congela o reactiva la simulación. |
| **Crear vuelo** | Alta manual con destino, aerolínea y **“entra en X s”**. |

La línea de estado muestra el perfil activo, el próximo vuelo automático y los
vuelos vivos. Las tarjetas de vuelos que aún no entran muestran **“entra en N
s/min”**.

### Botones de demo

| Botón | Qué hace |
|---|---|
| **Niebla +20** | Demora 20 min todas las salidas programadas. |
| **Caos** | Mata un proceso de vuelo; el supervisor lo reconstruye con su estado y puerta. |
| **Fuera de orden** | Envía una secuencia vieja; el sistema la ignora y lo registra. |
| **Refrescar** | Vuelve a leer la API (el WebSocket sigue vivo). |

La **bitácora** de abajo muestra los eventos y alertas en vivo.

---

## 6. Operar un vuelo

1. Haz clic en una tarjeta.
2. Se abre el detalle con puerta, horas, demora, motivos, acciones legales y la
   bitácora del vuelo.
3. Pulsa una acción. Solo aparecen las legales para ese estado.

### Ciclo normal

```
Programado → Abordando → Despegó → Aterrizó
```

- **Abordar** asigna una puerta libre. Si no hay, el vuelo pasa a **Demorado**
  con +15 min y motivo `sin_puerta`.
- **Despegar** libera la puerta.
- **Cancelar** libera la puerta y cancela el siguiente vuelo de la misma
  aeronave (efecto cascada).

### Cambiar puerta y hora a la vez

En el detalle, usa la fila **Cambiar puerta**:

1. Escribe la puerta destino, por ejemplo `puerta_5` (si la dejas vacía, el
   sistema asigna una libre).
2. Escribe los minutos a sumar, por ejemplo `15`.
3. Pulsa **Aplicar**.

El sistema, en una sola operación:

- libera la puerta anterior;
- ocupa la nueva (si está ocupada por otro vuelo, rechaza el cambio con un
  mensaje claro);
- suma los minutos a la demora y recalcula la hora estimada;
- conserva el estado del vuelo (si estaba abordando, sigue abordando);
- publica el evento `cambio_puerta` a todos los tableros.

La bitácora del vuelo registra `cambio de puerta a puerta_5 (+15 min)`.

---

## 7. API para integraciones

Base: `http://localhost:8080`

| Método | Ruta | Para qué |
|---|---|---|
| GET | `/api/vuelos` | Lista de vuelos. |
| POST | `/api/vuelos` | Crea un vuelo (`destino`, `aerolinea`, `entrada_seg`, `hora_programada`). |
| GET | `/api/vuelos/:id` | Detalle con historial. |
| POST | `/api/vuelos/:id/estado` | Aplica una transición. |
| GET | `/api/simulacion` | Perfil, pausa, tiempos y vuelos vivos. |
| POST | `/api/simulacion/ritmo` | Cambia perfil y/o tiempos en caliente. |
| POST | `/api/simulacion/pausar` | Congela el feed. |
| POST | `/api/simulacion/reanudar` | Reanuda el feed. |
| POST | `/api/demo/niebla` | Demora +20 min a los programados. |
| POST | `/api/demo/caos` | Mata un vuelo al azar. |
| POST | `/api/demo/fuera_de_orden` | Envía una secuencia vieja. |
| POST | `/api/demo/pausar` | Congela el feed (alias). |
| POST | `/api/demo/reanudar` | Reanuda el feed (alias). |
| GET | `/metrics` | Métricas y diagnóstico. |
| GET | `/health` | Sonda simple para AWS/systemd. |
| GET | `/ws` | WebSocket de eventos. |

### Ejemplos

```bash
# Abordar el vuelo 7
curl -X POST localhost:8080/api/vuelos/7/estado \
  -H 'content-type: application/json' \
  -d '{"accion":"empezar_abordaje","fuente":"torre"}'

# Cambiar puerta y hora en una sola operación
curl -X POST localhost:8080/api/vuelos/7/estado \
  -H 'content-type: application/json' \
  -d '{"accion":"cambiar_puerta","fuente":"torre",
       "puerta":"puerta_5","minutos":15,"motivo":"cambio operativo"}'

# Demorar 20 min
curl -X POST localhost:8080/api/vuelos/7/estado \
  -H 'content-type: application/json' \
  -d '{"accion":"demorar","fuente":"torre","minutos":20,"motivo":"niebla"}'

# Crear un vuelo que entra en 90 segundos
curl -X POST localhost:8080/api/vuelos \
  -H 'content-type: application/json' \
  -d '{"destino":"CUN","aerolinea":"Volaris","entrada_seg":90}'

# Cambiar la velocidad en caliente
curl -X POST localhost:8080/api/simulacion/ritmo \
  -H 'content-type: application/json' -d '{"perfil":"muy_lento"}'

# Cambiar solo el intervalo entre vuelos nuevos
curl -X POST localhost:8080/api/simulacion/ritmo \
  -H 'content-type: application/json' -d '{"nuevo_vuelo_cada_seg":120}'

# Pausar y reanudar
curl -X POST localhost:8080/api/simulacion/pausar
curl -X POST localhost:8080/api/simulacion/reanudar
```

### Códigos de error

| Código | Significado |
|---|---|
| 400 | Cuerpo o id inválido; puerta con formato incorrecto. |
| 404 | El vuelo no existe. |
| 409 | Transición ilegal, secuencia repetida, autoridad insuficiente, puerta ocupada o sin puertas. |
| 503 | El vuelo está ocupado o el feed se está reiniciando; reintenta. |

Cuando una puerta está ocupada, la respuesta incluye `vuelo_ocupante`:

```json
{"error":"la puerta ya esta ocupada por otro vuelo","ok":false,"vuelo_ocupante":32}
```

---

## 8. Persistencia y reinicio

Con `persistir = true` (por defecto), cada cambio se guarda en
`data/p22_respaldo.bin`. Al arrancar de nuevo:

```
p22_respaldo foto recuperada de data/p22_respaldo.bin
feed: N vuelos recuperados del respaldo
```

Los vuelos conservan identificación, destino, estado, puerta, demora e
historial.

Para empezar limpio:

```bash
rm -rf data
```

---

## 9. Capturas

En `design/capturas/`:

- `tablero-escritorio.png` — tablero 1440 px con sidebar, KPIs, seis columnas
  y bitácora.
- `tablero-simulacion.png` — panel de simulación con selector de velocidad,
  pausa y alta de vuelo con `entrada_seg`.
- `tablero-movil.png` — la misma app en 390 px, con columnas apiladas.
- `detalle-cambio-puerta.png` — modal de `TJ-423` con **Cambiar puerta**,
  `puerta_5` y +15 min ya aplicados.

---

## 10. Problemas comunes

| Síntoma | Causa | Solución |
|---|---|---|
| `rebar3: command not found` | no está en PATH | instala rebar3 o usa `escript rebar3`. |
| `undefined function json:encode/1` | OTP menor a 27 | actualiza Erlang/OTP. |
| `.beam` con `badfile` | copiaste `_build` de otra versión | `rm -rf _build` y recompila. |
| `eaddrinuse` en 8080 | otra instancia | cierra la otra app o cambia `puerto` en `config/sys.config`. |
| La página da 500 por `priv/index.html` | no se copió `priv/` | vuelve a copiar el proyecto y compila. |
| El tablero dice “conexión perdida” | WebSocket caído | espera 2 s (reconecta) o revisa que la app siga viva. |
| `data/p22_respaldo.bin` corrupto | se cortó la escritura | bórralo; arranca limpio. |
| El release dice `configuration file not found` | `vm.args` con `-config` duplicado | usa el `config/vm.args` de este proyecto (sin `-config`). |
| Los vuelos se mueven muy rápido | perfil `Rápido` o `Normal` | selecciona **Lento**/**Muy lento** o sube el intervalo entre vuelos. |
| Un vuelo no avanza | su `hora_programada` todavía no llega | espera la etiqueta “entra en N s” o usa `entrada_seg` menor. |
| WSL no responde en `localhost` | reenvío de puerto | prueba `curl localhost:8080` dentro de WSL; reinicia WSL con `wsl --shutdown`. |

---

## 11. Verificación rápida

```bash
rebar3 compile
rebar3 eunit          # 33 tests, 0 failures
rebar3 shell
```

En otra terminal:

```bash
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/          # 200
curl -s localhost:8080/api/vuelos | head -c 200                  # {"ok":true,...}
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/metrics   # 200
```

Listo. El resto de la documentación técnica está en el `README.md` del
proyecto.
