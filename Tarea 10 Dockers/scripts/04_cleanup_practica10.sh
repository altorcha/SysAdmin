#!/usr/bin/env bash
set -euo pipefail

OWNER_USER="${SUDO_USER:-$USER}"
OWNER_HOME="$(getent passwd "${OWNER_USER}" | cut -d: -f6)"
PROJECT_DIR="${OWNER_HOME}/contenedores"

if [ ! -d "${PROJECT_DIR}" ]; then
  echo "No existe ${PROJECT_DIR}; no hay proyecto que limpiar."
  exit 0
fi

cd "${PROJECT_DIR}"

echo "Deteniendo y eliminando contenedores de la practica..."
docker compose down

echo
echo "Los volumenes db_data y web_content NO se eliminaron para conservar evidencia de persistencia."
echo "Si tu profesor te pide reiniciar desde cero, ejecuta:"
echo "docker volume rm db_data web_content"
