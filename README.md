# Torre de control TIJ — Proyecto 22

| Materia | Programación Lineal |
|---|---|
| **Alumno** | Rodriguez Peraza Carlos Eliab |
| **No. de control** | 23212719 |
| **Grupo** | 2-3 |

Tablero de operaciones del Aeropuerto Internacional de Tijuana (TIJ / MMTJ)
construido en **Erlang/OTP 27** con **cowboy**. Cada vuelo es un proceso
`gen_statem` independiente, supervisado, con API HTTP, WebSocket en vivo,
persistencia en disco y un tablero web responsive.

---

## 1. Ejecutar

Requisitos: **Erlang/OTP 27 o superior** y **rebar3**. No se usa Node, Docker ni
base de datos externa.

```bash
rebar3 compile
rebar3 eunit
rebar3 shell
```

Abrir <http://localhost:8080>. La aplicación también puede ejecutarse como
release:

```bash
rebar3 release
_build/default/rel/p22_torre_de_control_tij/bin/p22_torre_de_control_tij foreground
```

---

## 2. Qué hace

- **Seis estados por vuelo:** `programado`, `demorado`, `abordando`, `despego`,
  `aterrizado`, `cancelado`.
- **Transiciones legales:** el `gen_statem` rechaza acciones fuera de orden; la
  API responde `409` y el tablero lo registra.
- **Cambio de puerta + hora en una sola operación:** conserva el estado actual,
  libera la puerta anterior y recalcula la hora estimada.
- **Cascada por aeronave:** un retraso puede propagarse a los vuelos siguientes
  de la misma aeronave.
- **Caos y recuperación:** se pueden matar procesos; el supervisor los
  reconstruye con su estado.
- **Reinicio de la VM:** respaldo en disco y recuperación de vuelos al arrancar.
- **Fuentes contradictorias y mensajes repetidos:** se detectan y se ignoran
  sin corromper el estado.
- **WebSocket:** snapshot inicial (`resync`) y eventos incrementales sin
  recargar el tablero.
- **Métricas:** `/metrics` con `recon` (procesos, memoria, puertas, clientes y
  eventos por minuto).

---

## 3. API

| Método | Ruta | Uso |
|---|---|---|
| `GET` | `/` | Tablero web |
| `GET` | `/api/vuelos` | Lista de vuelos |
| `POST` | `/api/vuelos` | Crea un vuelo de demostración |
| `GET` | `/api/vuelos/:id` | Detalle e historial |
| `POST` | `/api/vuelos/:id/estado` | Aplica una transición |
| `POST` | `/api/demo/:accion` | `niebla`, `caos`, `fuera_de_orden`, `pausar`, `reanudar` |
| `GET` | `/ws` | WebSocket del tablero |
| `GET` | `/metrics` | Métricas y estado del sistema |

Ejemplo de cambio de puerta y demora:

```bash
curl -X POST localhost:8080/api/vuelos/7/estado \
  -H 'content-type: application/json' \
  -d '{"accion":"cambiar_puerta","fuente":"torre","puerta":"puerta_5","minutos":15,"motivo":"cambio operativo"}'
```

---

## 4. Pruebas

```bash
rebar3 eunit
```

Resultado verificado en WSL2/Ubuntu con OTP 27 y rebar3 3.26.0:

```text
31 tests, 0 failures
```

Las pruebas cubren transiciones ilegales, mensajes fuera de orden, fuentes
contradictorias, cascada por aeronave, caos, reinicio, cambio de puerta y
asignación de puertas.

También se ejecutó una prueba local de **300 clientes WebSocket**:
300/300 conectados, 0 fallos y 300 `resync` iniciales. El detalle y las cifras
están en [`docs/CARGA_300.md`](docs/CARGA_300.md).

---

## 5. Interfaz

El tablero adopta el sistema de diseño exportado de **Google Stitch**:
superficies oscuras, tipografía Inter/JetBrains Mono, barra lateral, KPIs,
seis columnas por estado y modal de detalle con **Cambiar puerta**.

![Tablero de escritorio](design/capturas/tablero-escritorio.png)

![Detalle con cambio de puerta](design/capturas/detalle-cambio-puerta.png)

La vista móvil está en
[`design/capturas/tablero-movil.png`](design/capturas/tablero-movil.png).

- Sistema de diseño implementado: [`design/DESIGN.md`](design/DESIGN.md)
- Índice de capturas: [`design/CAPTURAS.md`](design/CAPTURAS.md)
- Mockups y ZIP de Stitch: [`design/stitch/`](design/stitch/)

---

## 6. Documentación

- **Manual de uso:** [`docs/GUIA_USO.md`](docs/GUIA_USO.md) — también publicado
  como Gist: <https://gist.github.com/CarlosEliab/da48ed12e3fbec9f22077040b8227f8d>
- **Montaje en VM y despliegue:** [`docs/VM_Y_DESPLIEGUE.md`](docs/VM_Y_DESPLIEGUE.md)
- **Prueba de carga:** [`docs/CARGA_300.md`](docs/CARGA_300.md)
- **Diseño UIX:** [`design/DESIGN.md`](design/DESIGN.md)

La unidad systemd de ejemplo está en
[`deploy/p22-torre-de-control-tij.service`](deploy/p22-torre-de-control-tij.service).

---

## 7. Estructura

```text
src/            módulos OTP, handlers cowboy, gen_statem y persistencia
test/           pruebas EUnit
priv/           tablero web (index.html)
config/         sys.config y vm.args
design/         sistema de diseño, capturas y mockups de Stitch
docs/           manual, despliegue y prueba de carga
deploy/         unidad systemd
scripts/        cliente de prueba de carga WebSocket
```

---

## 8. Notas

- La prueba de 300 clientes se hizo en loopback local, no a través de Internet
  ni TLS; el detalle está en `docs/CARGA_300.md`.
- La interfaz se verificó a 1440 px y 390 px en Chrome; no se probó en un
  teléfono físico.
- La unidad systemd se incluye como plantilla para la VM final.
