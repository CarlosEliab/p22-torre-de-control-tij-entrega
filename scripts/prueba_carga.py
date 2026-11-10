#!/usr/bin/env python3
"""
Prueba de carga del tablero: abre N clientes WebSocket contra /ws, mantiene la
conexión unos segundos y mide handshake, resync, mensajes y latencia de evento.

Uso:
    python3 scripts/prueba_carga.py --n 300 --segundos 20
    python3 scripts/prueba_carga.py --url ws://127.0.0.1:8080/ws \
        --http http://127.0.0.1:8080

Requiere: pip install websockets
"""

import argparse
import asyncio
import json
import statistics
import time
import urllib.request

import websockets


def percentil(valores, p):
    if not valores:
        return None
    orden = sorted(valores)
    k = max(0, min(len(orden) - 1, int(round((p / 100.0) * (len(orden) - 1)))))
    return orden[k]


def metricas(http):
    try:
        with urllib.request.urlopen(http + "/metrics", timeout=5) as r:
            return json.load(r)
    except Exception as exc:  # noqa: BLE001
        return {"error": type(exc).__name__}


async def cliente(uri, segundos, res):
    inicio = time.perf_counter()
    try:
        async with websockets.connect(uri, open_timeout=15, max_size=2**20) as ws:
            primero = await asyncio.wait_for(ws.recv(), timeout=15)
            res["conectados"] += 1
            res["handshake_ms"].append((time.perf_counter() - inicio) * 1000.0)
            try:
                if json.loads(primero).get("tipo") == "resync":
                    res["resync_ok"] += 1
            except json.JSONDecodeError:
                pass

            fin = time.monotonic() + segundos
            while time.monotonic() < fin:
                restante = fin - time.monotonic()
                if restante <= 0:
                    break
                try:
                    mensaje = await asyncio.wait_for(ws.recv(), timeout=restante)
                except asyncio.TimeoutError:
                    break
                res["mensajes"] += 1
                try:
                    evento = json.loads(mensaje)
                    ts = evento.get("ts")
                    if isinstance(ts, (int, float)):
                        res["lag_s"].append(max(0.0, time.time() - ts))
                except json.JSONDecodeError:
                    pass
    except Exception as exc:  # noqa: BLE001
        res["fallos"] += 1
        res["errores"].append(type(exc).__name__)


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="ws://127.0.0.1:8080/ws")
    ap.add_argument("--http", default="http://127.0.0.1:8080")
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--segundos", type=float, default=20.0)
    args = ap.parse_args()

    res = {
        "conectados": 0,
        "fallos": 0,
        "resync_ok": 0,
        "mensajes": 0,
        "handshake_ms": [],
        "lag_s": [],
        "errores": [],
    }

    t0 = time.perf_counter()
    tareas = [
        asyncio.create_task(cliente(args.url, args.segundos, res))
        for _ in range(args.n)
    ]
    # Deja que se establezcan las conexiones antes de leer /metrics.
    await asyncio.sleep(min(5.0, max(1.0, args.segundos / 3)))
    en_caliente = metricas(args.http)
    await asyncio.gather(*tareas)
    duracion = time.perf_counter() - t0
    en_frio = metricas(args.http)

    def pct(valores):
        return {
            "p50": percentil(valores, 50),
            "p95": percentil(valores, 95),
            "max": max(valores) if valores else None,
        }

    salida = {
        "solicitados": args.n,
        "conectados": res["conectados"],
        "fallos": res["fallos"],
        "errores": sorted(set(res["errores"])),
        "resync_ok": res["resync_ok"],
        "duracion_s": round(duracion, 2),
        "mensajes_totales": res["mensajes"],
        "mensajes_por_cliente": round(res["mensajes"] / max(1, res["conectados"]), 2),
        "handshake_ms": pct(res["handshake_ms"]),
        "lag_evento_s": pct(res["lag_s"]),
        "metrics_en_caliente": {
            "clientes_tablero": en_caliente.get("clientes_tablero"),
            "eventos_por_minuto": en_caliente.get("eventos_por_minuto"),
            "memoria_total": (en_caliente.get("sistema") or {}).get("memoria_total"),
            "procesos": (en_caliente.get("sistema") or {}).get("procesos"),
        },
        "metrics_en_frio": {
            "clientes_tablero": en_frio.get("clientes_tablero"),
            "memoria_total": (en_frio.get("sistema") or {}).get("memoria_total"),
            "procesos": (en_frio.get("sistema") or {}).get("procesos"),
        },
    }
    print(json.dumps(salida, ensure_ascii=False, indent=2))
    return 0 if res["conectados"] == args.n else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
