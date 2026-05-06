#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '\n[setup] %s\n' "$1"
}

fail() {
  printf '\n[setup][ERROR] %s\n' "$1" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Ejecuta este script como root: sudo ./setup.sh"
  fi
}

detect_os() {
  if [[ ! -r /etc/os-release ]]; then
    fail "No se pudo leer /etc/os-release."
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID:-}" != "ol" ]]; then
    printf '[setup][WARN] Sistema detectado: %s. Este paquete fue diseñado para Oracle Linux 10.\n' "${PRETTY_NAME:-desconocido}"
  fi

  if [[ "${VERSION_ID%%.*}" != "10" ]]; then
    printf '[setup][WARN] Version detectada: %s. Objetivo esperado: Oracle Linux 10.\n' "${VERSION_ID:-desconocida}"
  fi
}

dnf_config_add_repo() {
  local repo_url="$1"

  if dnf config-manager --help 2>&1 | grep -q -- '--add-repo'; then
    dnf config-manager --add-repo "${repo_url}"
  else
    dnf config-manager addrepo --from-repofile="${repo_url}"
  fi
}

install_docker() {
  log "Actualizando el sistema operativo."
  dnf update -y

  log "Instalando prerequisitos de DNF, red y firewall."
  dnf install -y dnf-plugins-core ca-certificates curl gnupg firewalld iputils tar

  log "Eliminando paquetes conflictivos de Docker si existieran."
  dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine podman-docker || true

  log "Configurando repositorio oficial de Docker para RHEL compatible con Oracle Linux."
  dnf_config_add_repo "https://download.docker.com/linux/rhel/docker-ce.repo"
  dnf makecache -y

  log "Instalando Docker Engine, Buildx y Docker Compose plugin."
  dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  log "Habilitando y arrancando Docker."
  systemctl enable --now docker
}

configure_permissions() {
  local target_user="${SUDO_USER:-${USER:-}}"

  log "Configurando grupo docker."
  groupadd -f docker

  if [[ -n "${target_user}" && "${target_user}" != "root" ]]; then
    usermod -aG docker "${target_user}"
    printf '[setup] Usuario agregado al grupo docker: %s\n' "${target_user}"
    printf '[setup] Nota: cierra y vuelve a iniciar sesion SSH para usar docker sin sudo.\n'
  else
    printf '[setup] No se detecto usuario no-root via sudo; puedes agregarlo despues con: sudo usermod -aG docker <usuario>\n'
  fi
}

configure_firewall() {
  log "Configurando firewalld: solo SSH(22) y HTTP(80) publicos."
  systemctl enable --now firewalld

  firewall-cmd --permanent --zone=public --set-target=DROP
  firewall-cmd --permanent --zone=public --add-service=ssh
  firewall-cmd --permanent --zone=public --add-service=http

  firewall-cmd --permanent --zone=public --remove-service=https || true
  firewall-cmd --permanent --zone=public --remove-port=5432/tcp || true
  firewall-cmd --permanent --zone=public --remove-port=5050/tcp || true
  firewall-cmd --permanent --zone=public --remove-port=8080/tcp || true

  firewall-cmd --reload
  firewall-cmd --list-all --zone=public
}

verify_installation() {
  log "Verificando Docker y Compose."
  docker --version
  docker compose version
  systemctl is-active --quiet docker || fail "Docker no esta activo."

  log "Ejecutando prueba hello-world."
  docker run --rm hello-world >/tmp/docker-hello-world.log
  tail -n 5 /tmp/docker-hello-world.log

  log "Setup completado correctamente."
}

main() {
  require_root
  detect_os
  install_docker
  configure_permissions
  configure_firewall
  verify_installation
}

main "$@"
