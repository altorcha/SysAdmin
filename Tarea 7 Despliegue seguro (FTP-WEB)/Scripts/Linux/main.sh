#!/bin/bash
source ./colores.sh
source ./servicio_ftps.sh
source ./servicio_http.sh
source ./utilidades.sh
Menu_Principal(){
    while true; do
        clear
        echo "=============================================================================="
        echo -e "${NEGRITA}${AZUL}           Despliegue de Servicios (FTP/WEB)          ${RESET}"
        echo "=============================================================================="
        echo "[1]   Menu FTP"
        echo "[2]   Instalación de Servidores Web (Apache/Nginx/Tomcat)"
        echo "[3]   Estado de Servidores Web"
        echo "[4]   Salir"
        echo "==============================="
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1)
                menu_ftps
                ;;
            2)
                menu_instalacion_web
                ;;
            3)
                status_srvweb
                ;;
            4)
                echo -e "${NEGRITA}${VERDE}Saliendo...${RESET}"
                exit 0
                ;;
            *)
                echo -e "${NEGRITA}${ROJO_CLARO}Opción inválida. Intente nuevamente.${RESET}";
                sleep 2
                ;;
        esac
    done
}
validar_root
Menu_Principal