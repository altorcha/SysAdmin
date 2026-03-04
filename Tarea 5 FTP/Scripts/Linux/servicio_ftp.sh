#!/bin/bash
# =====================================================================================================================
# Tarea 5: Automatización de Servidor FTP
# Autor: Alberto Torres Chaparro
# Update: Implementacion de las funciones de reglas de firewall y configuración del servicio FTP
# =====================================================================================================================
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
        echo "================================================"
        read -p "Presione Enter para continuar..."
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
            echo -e "${RED}[!] El servicio FTP NO está instalado.${NC}"
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
configurar_firewall_ftp() {
    # 1. Verificar e iniciar firewalld en silencio
    if ! systemctl is-active firewalld &>/dev/null; then
        sudo systemctl start firewalld &>/dev/null
        sudo systemctl enable firewalld &>/dev/null
    fi
    # 2. Agregar servicio FTP y puertos pasivos en silencio
    sudo firewall-cmd --permanent --add-service=ftp &>/dev/null
    sudo firewall-cmd --permanent --add-port=40000-40100/tcp &>/dev/null
    # 3. Recargar y aplicar SELinux en silencio
    sudo firewall-cmd --reload &>/dev/null
    sudo setsebool -P ftpd_full_access 1 &>/dev/null
    
    # 4. Mostrar solo el resultado final
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[EXITO] Reglas de Firewall y SELinux aplicadas.${NC}"
    else
        echo -e "${RED}[ERROR] Falló la configuración de red.${NC}"
    fi
    sleep 1
}
#estado_ftp

Menu-FTP(){
    while true; do
        clear
        echo "================================================"
        echo "                 SERVICIO FTP"
        echo "================================================"
        echo " [1] Instalar Servicio FTP"
        echo " [2] Verificar Estado del Servicio FTP"
        echo " [3] Volver al Menu Principal"
        echo "================================================"
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1)
                instalar_ftp;;
            2)
                estado_ftp;;
            3)
                return;;
            *)
                echo -e "${YELLOW}Opción no válida.${NC}"
                sleep 1
                ;;
        esac
    done
}