#!/usr/bin/env bash
set -euo pipefail

OWNER_USER="${SUDO_USER:-$USER}"
OWNER_HOME="$(getent passwd "${OWNER_USER}" | cut -d: -f6)"
PROJECT_DIR="${OWNER_HOME}/contenedores"

cd "${PROJECT_DIR}"

echo "=== Estado inicial de contenedores ==="
docker ps
echo

echo "=== Prueba 10.1: persistencia de base de datos ==="
docker exec postgres_db psql -U admin -d usuarios -c "CREATE TABLE IF NOT EXISTS alumnos (id SERIAL PRIMARY KEY, nombre TEXT NOT NULL);"
docker exec postgres_db psql -U admin -d usuarios -c "INSERT INTO alumnos (nombre) VALUES ('altorcha') ON CONFLICT DO NOTHING;"
docker exec postgres_db psql -U admin -d usuarios -c "SELECT * FROM alumnos;"

echo "Eliminando contenedor postgres_db para validar persistencia del volumen db_data..."
docker rm -f postgres_db
docker compose up -d db
echo "Esperando a que PostgreSQL vuelva a aceptar conexiones..."
sleep 10
docker exec postgres_db psql -U admin -d usuarios -c "SELECT * FROM alumnos;"
echo

echo "=== Prueba 10.2: aislamiento/red por nombre de servicio ==="
docker exec web_principal ping -c 4 db
echo

echo "=== Prueba 10.3: permisos FTP y volumen compartido ==="
printf "Archivo de prueba subido por FTP al volumen compartido FTP/Web\n" | docker run --rm -i --network host curlimages/curl:latest \
  --fail \
  --ftp-pasv \
  --ftp-create-dirs \
  -T - \
  ftp://127.0.0.1:21/uploads/prueba_ftp.txt \
  --user webuser:FtpPractica10
docker exec web_principal ls -l /usr/share/nginx/html/uploads
echo "Verifica en navegador: http://192.168.10.10:8080/uploads/prueba_ftp.txt"
echo

echo "=== Respaldo automatizado de PostgreSQL ==="
docker exec postgres_backup sh -c "PGPASSWORD=AdminPractica10 pg_dumpall -h db -U admin > /backups/backup_manual_validacion.sql"
ls -lh db/backups
echo

echo "=== Prueba 10.4: limites de recursos ==="
docker stats --no-stream
echo

echo "=== Volumenes requeridos ==="
docker volume ls | grep -E 'db_data|web_content' || true
echo

echo "=== Red requerida ==="
docker network inspect infra_red --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}}'
echo

echo "Pruebas terminadas. Usa las salidas anteriores para capturas de evidencia."
