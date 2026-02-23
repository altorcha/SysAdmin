#!/bin/bash
source servicio_dhcp.sh
source servicio_dns.sh
while true; do
    clear
    echo "========================================"
    echo "      MENU DE SERVICIOS DEL SERVIDOR"
    echo "========================================"
    echo "1. Servicio DHCP"
    echo "2. Servicio DNS"
    echo "3. Salir"
    echo "========================================"
    read -p "Seleccione una opción: " op

    case $op in
        1) menu_dhcp ;;
        2) menu_dns ;;
        3) exit 0 ;;
        *) echo "Opción inválida" ; sleep 1 ;;
    esac
done