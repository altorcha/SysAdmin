#!/bin/bash
# ======================================================================================
# Tarea 4: Acceso remoto mediante SSH
# Autor: Alberto Torres Chaparro
# Descripción: Este Script contiene las funciones para la instalación
# automatizada del servicio SSH y la visualización del estado del servicio.
# ======================================================================================

#Variables de color
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

#Función para ver el estado del servicio SSH
estado_ssh() {
    while true; do
        clear
        echo "----------------------------------------"
        echo "        ESTADO DEL SERVICIO SSH"
        echo "----------------------------------------"

        # El servicio SSH esta instaldo?
        if ! rpm -qa | grep -q openssh-server; then
            echo -e "${RED}[!] El paquete 'openssh-server' NO está instalado.${NC}"
            echo "Por favor, use la opción de instalación."
            read -p "Presione Enter para volver..."
            return
        fi

        # Obtener el estado del servicio
        ESTADO=$(systemctl is-active sshd)

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
                    echo -e "${YELLOW}Deteniendo servicio SSH...${NC}"
                    sudo systemctl stop sshd
                else
                    echo -e "${GREEN}Iniciando servicio SSH...${NC}"
                    sudo systemctl start sshd
                fi
                sleep 2
                ;;
            2)
                if [ "$ESTADO" == "active" ]; then
                    echo -e "${GREEN}Reiniciando servicio SSH...${NC}"
                    sudo systemctl restart sshd
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

#Función para instalar el servicio SSH
instalar_ssh() {
    clear
    #El servicio SSH ya esta instalado?
    if rpm -qa | grep -q openssh-server; then
        echo -e "${YELLOW}OpenSSH Server ya está instalado.${NC}"
        read -p "Presione Enter para continuar..."
        return
    fi

    echo "Instalando servicio OpenSSH Server (dnf)... Esto puede tardar un momento."
    # Instalamos el servicio
    sudo dnf install -y openssh-server > /dev/null 2>&1

    # Validamos si la instalación fue exitosa
    if rpm -qa | grep -q openssh-server; then
        
        # Configurar inicio automático
        sudo systemctl enable sshd

        # Iniciar servicio SSH
        sudo systemctl start sshd

        # Configurar Firewall
        sudo firewall-cmd --permanent --add-service=ssh > /dev/null 2>&1
        sudo firewall-cmd --reload > /dev/null 2>&1

        echo -e "${GREEN}Instalación completada, servicio configurado en automático y firewall asegurado.${NC}"
    else
        echo -e "${RED}Error en la instalación de OpenSSH.${NC}"
    fi

    read -p "Presione Enter para continuar..."
}

Menu-SSH(){
while true; do
        clear
        echo "======================================="
        echo "          SERVICIO SSH (LINUX)"
        echo "======================================="
        echo "1) Estado del servicio SSH"
        echo "2) Instalar el servicio SSH"
        echo "3) Salir"
        echo "======================================="

        read -p "Selecciona una opción: " opcion

        case $opcion in
            1) estado_ssh ;;
            2) instalar_ssh ;;
            3) return ;;
            *) 
                echo -e "${YELLOW}Opción inválida${NC}"
                sleep 1 
                ;;
        esac
    done    
}