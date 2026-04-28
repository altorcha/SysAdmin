#!/usr/bin/env bash
set -euo pipefail

OWNER_USER="${SUDO_USER:-$USER}"
OWNER_HOME="$(getent passwd "${OWNER_USER}" | cut -d: -f6)"
PROJECT_DIR="${OWNER_HOME}/contenedores"
cd "${PROJECT_DIR}"

echo "=== Evidencia: contenedores activos ==="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
echo

echo "=== Evidencia: limites de recursos ==="
docker stats --no-stream
echo

echo "=== Evidencia: volumenes persistentes ==="
docker volume ls | grep -E 'db_data|web_content' || true
echo

echo "=== Evidencia: red bridge personalizada ==="
docker network inspect infra_red --format 'Nombre={{.Name}} Driver={{.Driver}} Subred={{range .IPAM.Config}}{{.Subnet}}{{end}}'
echo

echo "=== Evidencia: usuario del servidor web ==="
docker exec web_principal whoami
echo

echo "=== Evidencia: server_tokens desactivado ==="
docker exec web_principal nginx -T 2>/dev/null | grep 'server_tokens off'
echo

echo "=== Evidencia: respaldos PostgreSQL ==="
ls -lh db/backups
