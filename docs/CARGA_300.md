# Prueba de carga: 300 clientes WebSocket

Evidencia del escenario del enunciado (“300 clientes viendo el tablero”).

## Entorno

| Elemento | Valor |
|---|---|
| Máquina | WSL2 / Ubuntu sobre Windows |
| Erlang | OTP 27 (ERTS 15.2.7.4) |
| App | `rebar3 shell` equivalente, misma VM |
| Cliente | Python 3.14 + `websockets` 17.4 |
| URL | `ws://127.0.0.1:8080/ws` |
| Fecha | 10-nov-2026 |

## Comando

```bash
python3 scripts/prueba_carga.py --n 300 --segundos 20
```

El script abre 300 conexiones concurrentes, espera el `resync` inicial, cuenta
los eventos recibidos y consulta `/metrics` en caliente y en frío.

## Resultado

```json
{
  "solicitados": 300,
  "conectados": 300,
  "fallos": 0,
  "errores": [],
  "resync_ok": 300,
  "duracion_s": 20.18,
  "mensajes_totales": 24600,
  "mensajes_por_cliente": 82.0,
  "handshake_ms": { "p50": 86.5, "p95": 97.6, "max": 132.7 },
  "lag_evento_s": { "p50": 0.89, "p95": 0.92, "max": 0.93 },
  "metrics_en_caliente": {
    "clientes_tablero": 304,
    "eventos_por_minuto": 350,
    "memoria_total": 58823064,
    "procesos": 411
  },
  "metrics_en_frio": {
    "clientes_tablero": 4,
    "memoria_total": 40600352,
    "procesos": 120
  }
}
```

## Interpretación

- **300/300 conexiones** establecidas y **300 `resync`** correctos; ningún
  timeout ni error.
- **24 600 mensajes** entregados en 20 s: 82 por cliente, sin caídas.
- **Handshake p95: 97.6 ms** (máximo 132.7 ms) en loopback local.
- **Memoria:** 58.8 MB con 300 clientes y 411 procesos; baja a 40.6 MB y 120
  procesos al desconectarse. No se observó fuga en la ventana medida.
- `clientes_tablero: 304` incluye los 300 del script más 4 pestañas del
  navegador que quedaron abiertas; al cerrar, `/metrics` reporta 4 y luego 0.
- **Sobre `lag_evento_s`:** el evento trae `ts` en **segundos** (no
  milisegundos), así que el valor de ~0.9 s es un **límite superior** impuesto
  por la granularidad del timestamp, no una latencia real de entrega. Para una
  medición exacta habría que añadir un timestamp en microsegundos al evento.

## Conclusión

En esta VM, el diseño soporta **300 clientes concurrentes** con el feed activo:
el bus serializa una vez por evento y hace broadcast, y el tablero recibe el
`resync` inicial sin pérdidas. La prueba es local (loopback); no sustituye una
prueba de red real con latencia, proxy o TLS.

## Reproducir

```bash
# 1. app corriendo en 8080
rebar3 shell

# 2. en otra terminal
pip install websockets        # o: pip install --user --break-system-packages websockets
python3 scripts/prueba_carga.py --n 300 --segundos 20
```
