#!/usr/bin/env bash
# =====================================================================
# instalar_servicio.sh — compila, arma el release e instala systemd.
#
# Uso (en la VM, desde la raiz del proyecto):
#   sudo ./deploy/instalar_servicio.sh
#
# Variables opcionales:
#   P22_USUARIO=p22          usuario del servicio
#   P22_DESTINO=/opt/p22     ruta de instalacion
#   P22_PUERTO=8080          puerto para la comprobacion /health
#   P22_SALTAR_PRUEBAS=1     no ejecutar rebar3 eunit
#
# El respaldo data/p22_respaldo.bin NO se borra entre actualizaciones.
# =====================================================================
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: ejecuta este script con sudo." >&2
    exit 1
fi

PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USUARIO="${P22_USUARIO:-p22}"
DESTINO="${P22_DESTINO:-/opt/p22}"
PUERTO="${P22_PUERTO:-8080}"
SERVICIO="p22-torre-de-control-tij"
RELEASE="${PROYECTO}/_build/default/rel/${SERVICIO}"

cd "${PROYECTO}"

# --- comprobaciones previas -----------------------------------------
command -v erl >/dev/null 2>&1 || {
    echo "ERROR: no se encontro erl. Instala Erlang/OTP 27+ (ver docs/AWS.md)." >&2
    exit 1
}
command -v rebar3 >/dev/null 2>&1 || {
    echo "ERROR: no se encontro rebar3. Instala rebar3 (ver docs/AWS.md)." >&2
    exit 1
}

OTP_MAJOR="$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().')"
if [[ "${OTP_MAJOR}" -lt 27 ]]; then
    echo "ERROR: se requiere Erlang/OTP 27 o superior; tienes ${OTP_MAJOR}." >&2
    echo "       Sigue la seccion de kerl en docs/AWS.md." >&2
    exit 1
fi

echo "==> Proyecto: ${PROYECTO}"
echo "==> OTP ${OTP_MAJOR} / rebar3 $(rebar3 version 2>/dev/null | head -1)"

# --- compilar y probar ----------------------------------------------
echo "==> Compilando"
rebar3 compile

if [[ "${P22_SALTAR_PRUEBAS:-0}" != "1" ]]; then
    echo "==> Ejecutando pruebas EUnit"
    rebar3 eunit
fi

echo "==> Armando release"
rebar3 release

[[ -d "${RELEASE}" ]] || {
    echo "ERROR: no se genero el release en ${RELEASE}" >&2
    exit 1
}

# --- usuario y directorio -------------------------------------------
if ! id -u "${USUARIO}" >/dev/null 2>&1; then
    echo "==> Creando usuario de sistema ${USUARIO}"
    useradd --system --home "${DESTINO}" --shell /usr/sbin/nologin "${USUARIO}"
fi

install -d -o "${USUARIO}" -g "${USUARIO}" "${DESTINO}"
install -d -o "${USUARIO}" -g "${USUARIO}" "${DESTINO}/data"

echo "==> Deteniendo servicio anterior (si existe)"
systemctl stop "${SERVICIO}" 2>/dev/null || true

echo "==> Copiando release a ${DESTINO}"
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude 'data/' "${RELEASE}/" "${DESTINO}/"
else
    cp -a "${RELEASE}/." "${DESTINO}/"
fi

# El release se copia como root; el usuario del servicio necesita leerlo.
chown -R root:root "${DESTINO}"
chown -R "${USUARIO}:${USUARIO}" "${DESTINO}/data"

# --- unidad systemd --------------------------------------------------
echo "==> Instalando unidad systemd"
install -m 0644 "${PROYECTO}/deploy/${SERVICIO}.service" \
    "/etc/systemd/system/${SERVICIO}.service"

systemctl daemon-reload
systemctl enable "${SERVICIO}" >/dev/null
systemctl restart "${SERVICIO}"

# --- comprobacion ----------------------------------------------------
echo "==> Esperando a que responda /health"
for _ in $(seq 1 25); do
    if curl -fsS --max-time 2 "http://127.0.0.1:${PUERTO}/health" >/dev/null 2>&1; then
        echo "OK: ${SERVICIO} responde en http://127.0.0.1:${PUERTO}"
        echo
        echo "Tablero:  http://<IP-PUBLICA-DE-LA-VM>:${PUERTO}"
        echo "Logs:     journalctl -u ${SERVICIO} -f"
        echo "Respaldo: ${DESTINO}/data/p22_respaldo.bin"
        exit 0
    fi
    sleep 1
done

echo "ERROR: el servicio no respondio en /health." >&2
systemctl status "${SERVICIO}" --no-pager || true
journalctl -u "${SERVICIO}" -n 40 --no-pager || true
exit 1
