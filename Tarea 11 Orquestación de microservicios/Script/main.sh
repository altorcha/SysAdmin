#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${PROJECT_DIR}/logs"
SETUP_LOG="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"
TUNNEL_FILE="${PROJECT_DIR}/docker-compose.tunnel.yml"

cd "${PROJECT_DIR}"
mkdir -p "${LOG_DIR}"

info() {
  printf '\n[main] %s\n' "$1"
}

warn() {
  printf '\n[main][WARN] %s\n' "$1"
}

fail() {
  printf '\n[main][ERROR] %s\n' "$1" >&2
}

pause() {
  printf '\nPresiona Enter para continuar... '
  read -r _
}

docker_cli() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

compose() {
  docker_cli compose "$@"
}

compose_tunnel() {
  docker_cli compose -f docker-compose.yml -f docker-compose.tunnel.yml "$@"
}

need_compose_file() {
  if [[ ! -f "${PROJECT_DIR}/docker-compose.yml" ]]; then
    fail "No existe docker-compose.yml en ${PROJECT_DIR}."
    exit 1
  fi
}

run_setup_hidden() {
  if [[ "${SKIP_SETUP:-0}" == "1" ]]; then
    warn "SKIP_SETUP=1 detectado; no se ejecuta setup.sh."
    return 0
  fi

  if [[ ! -x "${PROJECT_DIR}/setup.sh" ]]; then
    chmod +x "${PROJECT_DIR}/setup.sh"
  fi

  info "Ejecutando setup.sh en modo silencioso. Log: ${SETUP_LOG}"
  info "Si sudo solicita password, escribela una vez. El resto quedara oculto en el log."

  if [[ "${EUID}" -eq 0 ]]; then
    "${PROJECT_DIR}/setup.sh" >"${SETUP_LOG}" 2>&1 &
  else
    sudo -v
    sudo "${PROJECT_DIR}/setup.sh" >"${SETUP_LOG}" 2>&1 &
  fi

  local pid=$!
  local spin='|/-\'
  local i=0

  while kill -0 "${pid}" 2>/dev/null; do
    i=$(( (i + 1) % 4 ))
    printf '\r[main] Preparando servidor... %s' "${spin:${i}:1}"
    sleep 1
  done

  printf '\r[main] Preparando servidor... listo.        \n'

  if ! wait "${pid}"; then
    fail "setup.sh fallo. Revisa el log: ${SETUP_LOG}"
    tail -n 40 "${SETUP_LOG}" || true
    exit 1
  fi

  info "setup.sh termino correctamente."
}

deploy_stack() {
  need_compose_file
  info "Construyendo y levantando servicios."
  compose up -d --build
}

show_status() {
  need_compose_file
  compose ps
}

test_http() {
  local target="${1:-http://127.0.0.1/}"
  info "Probando HTTP: ${target}"
  curl -i --connect-timeout 5 "${target}"
}

test_blocked_ports() {
  local server_ip
  printf 'IP o hostname del servidor para probar desde aqui: '
  read -r server_ip

  if [[ -z "${server_ip}" ]]; then
    warn "No se ingreso IP/hostname."
    return 0
  fi

  info "Probando PostgreSQL externo bloqueado: ${server_ip}:5432"
  if curl -v --connect-timeout 5 "telnet://${server_ip}:5432"; then
    warn "El puerto 5432 respondio. Revisa firewall y compose."
  else
    info "OK: 5432 no es accesible externamente."
  fi

  info "Probando PgAdmin externo bloqueado: ${server_ip}:8080"
  if curl -v --connect-timeout 5 "http://${server_ip}:8080"; then
    warn "El puerto 8080 respondio. Revisa firewall y compose."
  else
    info "OK: 8080 no es accesible externamente."
  fi

  info "Probando PgAdmin externo bloqueado: ${server_ip}:5050"
  if curl -v --connect-timeout 5 "http://${server_ip}:5050"; then
    warn "El puerto 5050 respondio. Revisa firewall y compose."
  else
    info "OK: 5050 no es accesible externamente."
  fi
}

test_internal_dns() {
  need_compose_file
  info "Probando resolucion interna app -> nginx."
  compose exec app ping -c 3 nginx

  info "Probando resolucion interna postgres -> pgadmin."
  compose exec postgres ping -c 3 pgadmin
}

test_postgres_health() {
  need_compose_file
  local container_id
  container_id="$(compose ps -q postgres)"

  if [[ -z "${container_id}" ]]; then
    fail "No se encontro el contenedor postgres."
    return 1
  fi

  docker_cli inspect --format='Estado PostgreSQL: {{.State.Health.Status}}' "${container_id}"
}

test_persistence() {
  need_compose_file
  info "Insertando dato de prueba en PostgreSQL."
  compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE TABLE IF NOT EXISTS persist_test (id serial PRIMARY KEY, created_at timestamptz DEFAULT now()); INSERT INTO persist_test DEFAULT VALUES;"'

  info "Reiniciando servicios sin borrar volumenes."
  compose down
  compose up -d

  info "Verificando que el dato persiste."
  compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT count(*) AS registros_persistentes FROM persist_test;"'
}

enable_pgadmin_tunnel() {
  need_compose_file
  info "Creando override temporal para exponer PgAdmin solo en 127.0.0.1:8080 del servidor."

  cat > "${TUNNEL_FILE}" <<'EOF'
services:
  pgadmin:
    ports:
      - "127.0.0.1:8080:80"
    networks:
      - red_datos
      - red_tunnel

networks:
  red_tunnel:
    driver: bridge
EOF

  compose_tunnel up -d --force-recreate pgadmin

  info "Probando PgAdmin en loopback del servidor."
  curl -I --connect-timeout 5 http://127.0.0.1:8080

  cat <<EOF

ssh -N -L 127.0.0.1:8081:127.0.0.1:8080 ${USER}@$(hostname -I | awk '{print $1}')

Luego abre:

http://127.0.0.1:8081

EOF
}

disable_pgadmin_tunnel() {
  need_compose_file
  info "Quitando override temporal del tunel PgAdmin."
  rm -f "${TUNNEL_FILE}"
  compose up -d --force-recreate pgadmin
  info "PgAdmin vuelve a quedar sin puerto publicado."
}

show_ssh_command() {
  local server_ip
  server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  cat <<EOF

Comando recomendado desde PowerShell en tu laptop:

ssh -N -L 127.0.0.1:8081:127.0.0.1:8080 ${USER}@${server_ip:-ip_servidor}

URL local:

http://127.0.0.1:8081

Si quieres usar 8080 local, primero verifica que este libre:

netstat -ano | findstr :8080

EOF
}

show_logs() {
  need_compose_file
  compose logs --tail=120
}

menu() {
  while true; do
  clear
    cat <<'EOF'

================ Tarea11 Microservicios ================
1) Desplegar stack: docker compose up -d --build
2) Ver estado de contenedores
3) Probar HTTP publico/local
4) Probar puertos bloqueados: 5432, 8080, 5050
5) Probar DNS interno con ping por servicio
6) Ver healthcheck de PostgreSQL
7) Probar persistencia tras reinicio
8) Activar acceso PgAdmin por tunel SSH
9) Mostrar comando SSH para la laptop
10) Desactivar acceso temporal PgAdmin
11) Ver logs recientes
0) Salir
=========================================================
EOF

    printf 'Selecciona una opcion: '
    read -r option

    case "${option}" in
      1) deploy_stack; pause ;;
      2) show_status; pause ;;
      3)
        printf 'URL a probar [http://127.0.0.1/]: '
        read -r url
        test_http "${url:-http://127.0.0.1/}"
        pause
        ;;
      4) test_blocked_ports; pause ;;
      5) test_internal_dns; pause ;;
      6) test_postgres_health; pause ;;
      7) test_persistence; pause ;;
      8) enable_pgadmin_tunnel; pause ;;
      9) show_ssh_command; pause ;;
      10) disable_pgadmin_tunnel; pause ;;
      11) show_logs; pause ;;
      0) exit 0 ;;
      *) warn "Opcion invalida."; pause ;;
    esac
  done
}

main() {
  need_compose_file
  run_setup_hidden
  menu
}

main "$@"
