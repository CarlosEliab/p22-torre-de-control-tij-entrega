#!/usr/bin/env bash
# =====================================================================
# empaquetar.sh — genera un .tar.gz limpio para subir por scp a la VM.
#
# Uso (desde cualquier ruta):
#   ./deploy/empaquetar.sh
#
# Resultado:
#   dist/p22-torre-de-control-tij.tar.gz
#
# Excluye _build/, data/, dist/, .git/ y archivos de crash. El paquete
# conserva src/, priv/, config/, deploy/, docs/, test/, design/,
# problema/, rebar.config y README.md.
# =====================================================================
set -euo pipefail

PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PADRE="$(dirname "${PROYECTO}")"
NOMBRE="$(basename "${PROYECTO}")"
SALIDA="${PROYECTO}/dist/p22-torre-de-control-tij.tar.gz"

mkdir -p "${PROYECTO}/dist"

echo "==> Empaquetando ${NOMBRE}"
tar \
    --exclude="${NOMBRE}/_build" \
    --exclude="${NOMBRE}/data" \
    --exclude="${NOMBRE}/dist" \
    --exclude="${NOMBRE}/.git" \
    --exclude="${NOMBRE}/erl_crash.dump" \
    --exclude="${NOMBRE}/**/erl_crash.dump" \
    -czf "${SALIDA}" \
    -C "${PADRE}" "${NOMBRE}"

echo "==> Listo: ${SALIDA} ($(du -h "${SALIDA}" | cut -f1))"
echo
echo "Subir a la VM:"
echo "  scp -i llave.pem '${SALIDA}' ubuntu@<IP-PUBLICA>:~/"
echo
echo "En la VM:"
echo "  tar xzf p22-torre-de-control-tij.tar.gz"
echo "  cd p22-torre-de-control-tij"
echo "  sudo ./deploy/instalar_servicio.sh"
