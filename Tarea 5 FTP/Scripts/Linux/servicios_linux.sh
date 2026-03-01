#!/bin/bash
source servicio_dhcp.sh
source servicio_dns.sh
source servicio_ssh.sh
source servicio_ftp.sh
while true; do
    clear
    echo "========================================"
    echo "      MENU DE SERVICIOS DEL SERVIDOR"
    echo "========================================"
    echo "1. Servicio DHCP"
    echo "2. Servicio DNS"
    echo "3. Servicio SSH"
    echo "4. Servicio FTP"
    echo "5. Salir"
    echo "========================================"
    read -p "Seleccione una opción: " op

    case $op in
        1) menu_dhcp ;;
        2) menu_dns ;;
        3) Menu-SSH ;;
        4) Menu-FTP ;;
        5) exit 0 ;;
        *) echo "Opción inválida" ; sleep 1 ;;
    esac
done