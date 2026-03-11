#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/servicio_http.sh" || {
    echo "  ERROR: No se encontro servicio_http.sh en ${SCRIPT_DIR}"
    exit 1
}

mostrar_banner() {
    clear
    echo ""
    echo "  ================================================"
    echo "                  Despliegue HTTP                 "
    echo "  ================================================"
    echo ""
}

submenu_estado() {
    while true; do
        mostrar_banner
        echo "  Estado de Servicios"
        echo ""
        echo "  [1] Apache"
        echo "  [2] Nginx"
        echo "  [3] Tomcat"
        echo "  [0] Volver"
        echo "  ================================================"
        read -rp "  Seleccione: " op
        case "$op" in
            1) estado_apache ;;
            2) estado_nginx  ;;
            3) estado_tomcat ;;
            0) return        ;;
            *) mensaje error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

submenu_instalar() {
    while true; do
        mostrar_banner
        echo "  Instalar Servidor HTTP"
        echo ""
        echo "  [1] Apache"
        echo "  [2] Nginx"
        echo "  [3] Tomcat"
        echo "  [0] Volver"
        echo ""
        read -rp "  Seleccione: " op
        case "$op" in
            1) instalar_apache ;;
            2) instalar_nginx  ;;
            3) instalar_tomcat ;;
            0) return          ;;
            *) mensaje error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

mostrar_menu() {
    echo "  [1] Estado del servicio"
    echo "  [2] Instalar servicio"
    echo "  [3] Gestionar servicios"
    echo "  [0] Salir"
    echo ""
}

leer_opcion() {
    local opcion
    while true; do
        read -rp "  Opcion: " opcion
        if [[ "$opcion" =~ ^[0-3]$ ]]; then
            echo "$opcion"
            return 0
        fi
        mensaje error "Opcion invalida."
    done
}

ejecutar_opcion() {
    case "$1" in
        1) submenu_estado           ;;
        2) submenu_instalar         ;;
        3) gestionar_servicios_http ;;
        0) exit 0                   ;;
    esac
}

main() {
    validar_root
    while true; do
        mostrar_banner
        mostrar_menu
        ejecutar_opcion "$(leer_opcion)"
    done
}

main "$@"