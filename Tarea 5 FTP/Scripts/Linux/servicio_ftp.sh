#!/bin/bash
# ======================================================================================
# Tarea 5: Automatización de Servidor FTP
# Autor: Alberto Torres Chaparro
# Descripción: Este Script Contiene la funcion para la instalación del servicio FTP.
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

instalar_ftp