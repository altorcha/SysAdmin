#!/bin/bash
source ./colores.sh
source ./servicio_ftps.sh

validar_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${NEGRITA}${FONDO_ROJO}${BLANCO_BRILLANTE} ERROR *** Este script debe ejecutarse como root ${RESET}"
        exit 1
    fi
}

Menu-Orquestador(){
    while true; do
        clear
        echo "=============================================================================="
        echo -e "${NEGRITA}${AZUL}           Despliegue de Servicios (FTP/WEB)          ${RESET}"
        echo "=============================================================================="
        echo "1) Menu FTP (vsftpd)"
        echo "2) Salir"
        echo "==============================="
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1)
                menu-ftps
                ;;
            2)
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
Menu-Orquestador