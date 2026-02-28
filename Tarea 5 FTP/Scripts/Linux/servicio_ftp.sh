#!/bin/bash
# ======================================================================================
# Tarea 5: Automatización de Servidor FTP
# Autor: Alberto Torres Chaparro
# Update: Este Script contiene la función para verificar el estado del servicio FTP y controlarlo.
# ======================================================================================
#Variables de color
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

instalar_ftp() {
    echo "================================================"
    echo "      Instalación del Servicio FTP (vsftpd)"
    echo "================================================"
    if rpm -q vsftpd &> /dev/null; then
        echo -e "${YELLOW}El servicio FTP ya está instalado.${NC}"
        read -p "Enter..."
        return
    fi

    echo "Instalando vsftpd..."
    dnf install -y vsftpd &> /dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[EXITO] Instalación completada.${NC}"
        systemctl enable vsftpd &> /dev/null
    else
        echo -e "${RED}[ERROR] Falló la instalación.${NC}"
    fi

    read -p "Presiona Enter para continuar..."
}

#instalar_ftp

estado_ftp() {
    while true; do
        clear
        echo "----------------------------------------"
        echo "        ESTADO DEL SERVICIO FTP"
        echo "----------------------------------------"

        # ¿El servicio vsftpd está instalado?
        if ! rpm -q vsftpd &>/dev/null; then
            echo -e "${RED}[!] El paquete 'vsftpd' NO está instalado.${NC}"
            echo "Use la opción de instalación primero."
            echo "----------------------------------------"
            read -p "Presione Enter para volver..."
            return
        fi

        # Obtener el estado del servicio
        ESTADO=$(systemctl is-active vsftpd)

        if [ "$ESTADO" == "active" ]; then
            echo -n "Estado Actual: "
            echo -e "${GREEN}ACTIVO (Running)${NC}"
            echo "----------------------------------------"
            echo " [1] Detener el servicio"
            echo " [2] Reiniciar el servicio"
            echo " [3] Volver al menú principal"
        else
            echo -n "Estado Actual: "
            echo -e "${RED}DETENIDO (Stopped)${NC}"
            echo "----------------------------------------"
            echo " [1] Iniciar el servicio"
            echo " [3] Volver al menú principal"
        fi

        echo "----------------------------------------"
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1)
                if [ "$ESTADO" == "active" ]; then
                    echo -e "${YELLOW}Deteniendo servicio FTP...${NC}"
                    sudo systemctl stop vsftpd
                else
                    echo -e "${GREEN}Iniciando servicio FTP...${NC}"
                    sudo systemctl start vsftpd
                fi
                sleep 2
                ;;
            2)
                if [ "$ESTADO" == "active" ]; then
                    echo -e "${GREEN}Reiniciando servicio FTP...${NC}"
                    sudo systemctl restart vsftpd
                    sleep 2
                fi
                ;;
            3)
                return
                ;;
            *)
                echo -e "${YELLOW}Opción no válida.${NC}"
                sleep 1
                ;;
        esac
    done
}

estado_ftp