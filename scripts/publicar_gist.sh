#!/usr/bin/env bash
# =====================================================================
# publicar_gist.sh — actualiza el Gist del proyecto con el README y el
# codigo clave, con enlaces absolutos al repositorio.
#
# Uso (desde WSL o Linux con gh autenticado):
#   ./scripts/publicar_gist.sh
#
# Variables opcionales:
#   GIST_ID   id del gist (por defecto el del proyecto)
#   GH_BIN    ruta explicita al binario de gh
# =====================================================================
set -euo pipefail

PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GIST_ID="${GIST_ID:-da48ed12e3fbec9f22077040b8227f8d}"
REPO_URL="https://github.com/CarlosEliab/p22-torre-de-control-tij-entrega"
RAW_URL="https://raw.githubusercontent.com/CarlosEliab/p22-torre-de-control-tij-entrega/main"
BLOB_URL="${REPO_URL}/blob/main"
GIST_DIR="${PROYECTO}/docs/gist"

# --- localizar gh ----------------------------------------------------
GH="${GH_BIN:-}"
if [[ -z "${GH}" ]]; then
    if [[ -x "/mnt/c/Program Files/GitHub CLI/gh.exe" ]]; then
        GH="/mnt/c/Program Files/GitHub CLI/gh.exe"
    elif command -v gh >/dev/null 2>&1; then
        GH="$(command -v gh)"
    else
        echo "ERROR: no se encontro gh (GitHub CLI)." >&2
        exit 1
    fi
fi

"${GH}" auth status >/dev/null 2>&1 || {
    echo "ERROR: gh no esta autenticado. Ejecuta: gh auth login" >&2
    exit 1
}

ruta_gh() {
    if [[ "${GH}" == *.exe ]]; then
        wslpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

# --- preparar carpeta del gist --------------------------------------
mkdir -p "${GIST_DIR}"

# README con enlaces e imagenes absolutas (el gist no resuelve rutas
# relativas del repositorio).
python3 - "${PROYECTO}/README.md" "${GIST_DIR}/README.md" \
          "${RAW_URL}" "${BLOB_URL}" <<'PY'
import sys
origen, destino, raw, blob = sys.argv[1:5]
texto = open(origen, encoding="utf-8").read()
texto = texto.replace("](design/capturas/", f"]({raw}/design/capturas/")
texto = texto.replace("](docs/", f"]({blob}/docs/")
texto = texto.replace("](design/", f"]({blob}/design/")
texto = texto.replace("](problema/", f"]({blob}/problema/")
open(destino, "w", encoding="utf-8").write(texto)
PY

cp "${PROYECTO}/docs/GUIA_USO.md" "${GIST_DIR}/GUIA_USO.md"
cp "${PROYECTO}/docs/VM_Y_DESPLIEGUE.md" "${GIST_DIR}/VM_Y_DESPLIEGUE.md"
cp "${PROYECTO}/src/p22_vuelo_statem.erl" "${GIST_DIR}/p22_vuelo_statem.erl"
cp "${PROYECTO}/src/p22_feed.erl" "${GIST_DIR}/p22_feed.erl"
cp "${PROYECTO}/src/p22_torre_de_control_tij_sup.erl" "${GIST_DIR}/p22_torre_de_control_tij_sup.erl"
cp "${PROYECTO}/src/p22_puertas.erl" "${GIST_DIR}/p22_puertas.erl"
cp "${PROYECTO}/src/p22_respaldo.erl" "${GIST_DIR}/p22_respaldo.erl"
cp "${PROYECTO}/src/p22_h_simulacion.erl" "${GIST_DIR}/p22_h_simulacion.erl"
cp "${PROYECTO}/priv/index.html" "${GIST_DIR}/index.html"
cp "${PROYECTO}/config/sys.config" "${GIST_DIR}/sys.config"
cp "${PROYECTO}/test/p22_caos_tests.erl" "${GIST_DIR}/p22_caos_tests.erl"

ARCHIVOS=(
    README.md
    GUIA_USO.md
    VM_Y_DESPLIEGUE.md
    p22_vuelo_statem.erl
    p22_feed.erl
    p22_torre_de_control_tij_sup.erl
    p22_puertas.erl
    p22_respaldo.erl
    p22_h_simulacion.erl
    index.html
    sys.config
    p22_caos_tests.erl
)

EXISTENTES="$("${GH}" gist view "${GIST_ID}" --files 2>/dev/null || true)"

echo "==> Publicando Gist ${GIST_ID}"
for archivo in "${ARCHIVOS[@]}"; do
    origen="${GIST_DIR}/${archivo}"
    [[ -f "${origen}" ]] || {
        echo "ERROR: falta ${origen}" >&2
        exit 1
    }
    if grep -qxF "${archivo}" <<<"${EXISTENTES}"; then
        "${GH}" gist edit "${GIST_ID}" \
            --filename "${archivo}" "$(ruta_gh "${origen}")" >/dev/null
        echo "    actualizado: ${archivo}"
    else
        "${GH}" gist edit "${GIST_ID}" \
            --add "$(ruta_gh "${origen}")" >/dev/null
        echo "    agregado:    ${archivo}"
    fi
done

# `gh gist edit --desc` sin --filename abre el editor; la API es directa.
"${GH}" api -X PATCH "/gists/${GIST_ID}" \
    -f description="Torre de control TIJ — Proyecto 22 · ITT · Programación Lógica y Funcional" \
    >/dev/null

echo
echo "OK: https://gist.github.com/CarlosEliab/${GIST_ID}"
