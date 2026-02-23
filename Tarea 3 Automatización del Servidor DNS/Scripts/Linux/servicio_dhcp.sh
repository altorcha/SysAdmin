#!/bin/bash
# ======================================================================================
# Tarea 2: Automatizacion y Gestion del Servidor DHCP (KEA)
# Autor: Alberto Torres Chaparro
# Script: Automatiza la instalación, configuración y monitoreo de DHCP en Oracle Linux
# ======================================================================================

# --- VARIABLES GLOBALES PARA COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# --- FUNCIONES DE VALIDACION ---

ip_to_int() {
    local IFS=.
    read -r i1 i2 i3 i4 <<< "$1"
    echo $(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))
}

validar_formato_ip() {
    if [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 0; fi
    return 1
}

# Función ajustada: Permite 127.x.x.x excepto .1, .0 y .255
validar_ip_utilizable() {
    local IP=$1
    
    # 1. Validar formato básico x.x.x.x
    if ! validar_formato_ip "$IP"; then return 1; fi

    # 2. Desglosar octetos
    IFS='.' read -r o1 o2 o3 o4 <<< "$IP"

    # 3. Validaciones de rango numérico (0-255)
    for octeto in $o1 $o2 $o3 $o4; do
        if [ "$octeto" -lt 0 ] || [ "$octeto" -gt 255 ]; then return 1; fi
    done

    # 4. Validar IPs Reservadas Específicas
    
    # Bloquear 0.0.0.0
    if [ "$IP" == "0.0.0.0" ]; then echo "Error: IP 0.0.0.0 no válida"; return 1; fi
    
    # Bloquear Localhost exacto
    if [ "$IP" == "127.0.0.1" ]; then echo "Error: Localhost (127.0.0.1) no permitido como servidor"; return 1; fi

    # 5. Reglas generales de Red y Broadcast (.0 y .255)
    if [ "$o4" -eq 0 ]; then echo "Error: IP de Red (termina en .0)"; return 1; fi
    if [ "$o4" -eq 255 ]; then echo "Error: IP de Broadcast (termina en .255)"; return 1; fi

    return 0
}

# --- 1. ESTADO DEL SERVICIO ---
estado_servicio() {
    while true; do
        clear
        echo "----------------------------------------"
        echo "        ESTADO DEL SERVICIO DHCP"
        echo "----------------------------------------"

        if ! rpm -q kea &> /dev/null; then
            echo -e "${RED}[!] El paquete 'kea' NO está instalado.${NC}"
            echo "Por favor, use la opción 2 para instalarlo."
            read -p "Presione Enter para volver..."
            return
        fi

        # Verificamos estado y mostramos opciones dinámicas
        if systemctl is-active --quiet kea-dhcp4; then
            echo -e "Estado Actual: ${GREEN}ACTIVO (Running)${NC}"
            systemctl status kea-dhcp4 --no-pager | grep "Active:"
            echo "----------------------------------------"
            echo " [1] Detener el servicio"
            echo " [2] Reiniciar el servicio" 
            echo " [3] Volver al menú principal"
        else
            echo -e "Estado Actual: ${RED}DETENIDO (Stopped)${NC}"
            echo "----------------------------------------"
            echo " [1] Iniciar el servicio"
            echo " [3] Volver al menú principal"
        fi

        echo "----------------------------------------"
        read -p "Seleccione una opción: " sub_opcion

        case $sub_opcion in
            1)
                if systemctl is-active --quiet kea-dhcp4; then
                    echo -e "${RED}Deteniendo servicio KEA...${NC}"
                    systemctl stop kea-dhcp4
                else
                    echo -e "${GREEN}Iniciando servicio KEA...${NC}"
                    systemctl start kea-dhcp4
                fi
                sleep 1.5
                ;;
            2)
                if systemctl is-active --quiet kea-dhcp4; then
                    echo -e "${GREEN}Reiniciando KEA y purgando base de datos...${NC}"
                    
                    # 1. Detenemos primero para liberar el archivo
                    systemctl stop kea-dhcp4
                    
                    # 2. Borramos el archivo de "memoria"
                    if [ -f /var/lib/kea/kea-leases4.csv ]; then
                        rm -f /var/lib/kea/kea-leases4.csv
                        echo " > Historial de IPs (leases) eliminado."
                    fi
                    
                    systemctl start kea-dhcp4
                    
                    if systemctl is-active --quiet kea-dhcp4; then
                        echo " > Servicio reiniciado correctamente."
                    else
                        echo -e "${RED} > Error al reiniciar el servicio.${NC}"
                    fi
                    sleep 2
                else
                    echo "El servicio no está activo, no se puede reiniciar."
                    sleep 1.5
                fi
                ;;
            3)
                return ;;
            *)
                echo "Opción no válida."
                sleep 1
                ;;
        esac
    done
}

# --- Función para instalar el servicio ---
instalar_servicio() {
    echo "----------------------------------------"
    echo "        INSTALACIÓN DEL SERVICIO"
    echo "----------------------------------------"

    if rpm -q kea &> /dev/null; then
        echo "El servicio ya está instalado."
        read -p "Presione Enter..."
        return
    fi

    echo "Iniciando instalación desatendida... Por favor espere."
    
    (
        dnf install -y epel-release oracle-epel-release-el10
        dnf install -y kea
    ) &> /dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[EXITO] Instalación completada correctamente.${NC}"
    else
        echo -e "${RED}[ERROR] La instalación falló.${NC}"
    fi
    read -p "Presione Enter..."
}

# --- Función para configurar el servicio DHCP ---
configurar_servicio() {
    clear
    echo "========================================"
    echo "   CONFIGURACION DE DHCP"
    echo "========================================"

    if ! rpm -q kea &> /dev/null; then
        echo "Error: Instale el servicio primero."
        read -p "Enter..."
        return
    fi

    echo "Interfaces disponibles:"
    ip -o link show | awk -F': ' '{print " - " $2}'
    echo "----------------------------------------"
    
    while true; do
        read -p "1. Adaptador de red: " INTERFAZ
        if ip link show "$INTERFAZ" &> /dev/null; then break; fi
        echo -e "${RED}   [!] La interfaz no existe.${NC}"
    done

    if command -v nmcli &> /dev/null; then
        nmcli device set "$INTERFAZ" managed no &> /dev/null
    fi

    read -p "2. Nombre del Ámbito: " SCOPE_NAME

    # --- RANGO INICIAL ---
    while true; do
        read -p "3. Rango inicial: " IP_INICIO
        # Validamos usando la nueva lógica
        if validar_ip_utilizable "$IP_INICIO"; then break; fi
        echo -e "${RED}   [!] IP inválida${NC}"
    done

    PREFIX=$(echo "$IP_INICIO" | cut -d'.' -f1-3)
    LAST_OCTET=$(echo "$IP_INICIO" | cut -d'.' -f4)
    
    POOL_START_OCTET=$((LAST_OCTET + 1))
    POOL_START="$PREFIX.$POOL_START_OCTET"
    SUBNET="$PREFIX.0"

    # --- RANGO FINAL ---
    while true; do
        read -p "4. Rango final ($PREFIX.X): " IP_FIN
        
        if ! validar_ip_utilizable "$IP_FIN"; then 
            echo -e "${RED}   [!] IP inválida.${NC}"; continue
        fi

        PREFIX_FIN=$(echo "$IP_FIN" | cut -d'.' -f1-3)
        if [ "$PREFIX" != "$PREFIX_FIN" ]; then
            echo -e "${RED}   [!] La IP debe estar en el segmento $PREFIX.x${NC}"; continue
        fi

        INT_POOL_START=$(ip_to_int "$POOL_START")
        INT_FIN=$(ip_to_int "$IP_FIN")

        if [ $INT_POOL_START -le $INT_FIN ]; then
            break
        else
            echo -e "${RED}   [!] Error: El rango final debe ser mayor o igual a $POOL_START.${NC}"
        fi
    done

    # --- GATEWAY ---
    while true; do
        read -p "5. Gateway (Enter para omitir): " GATEWAY
        
        # Opción 1: Usuario presiona Enter (vacío) -> Se permite y sale del bucle
        if [ -z "$GATEWAY" ]; then 
            break 
        fi
        
        # Opción 2: Usuario ingresa algo -> Se valida IP y Segmento
        if validar_ip_utilizable "$GATEWAY"; then
            GW_PREFIX=$(echo "$GATEWAY" | cut -d'.' -f1-3)
            if [ "$GW_PREFIX" == "$PREFIX" ]; then
                break
            else
                echo -e "${RED}   [!] El Gateway debe pertenecer a la red $PREFIX.x${NC}"
            fi
        else
            echo -e "${RED}   [!] IP inválida.${NC}"
        fi
    done

    DNS_SERVER="$IP_INICIO"
    if [ -n "$DNS_SERVER" ] && ! validar_formato_ip "$DNS_SERVER"; then
        echo "   [!] DNS inválido, se omitirá."
        DNS_SERVER=""
    fi

    while true; do
        read -p "7. Tiempo de concesión (segundos): " LEASE_TIME
        if [[ "$LEASE_TIME" =~ ^[0-9]+$ ]]; then break; fi
        echo -e "${RED}   [!] Debe ser un número entero.${NC}"
    done

    # --- RESUMEN ---
    clear
    echo "========================================"
    echo "        RESUMEN DE CONFIGURACIÓN"
    echo "========================================"
    echo "1- Adaptador de red:    $INTERFAZ"
    echo "2- Nombre del ambito:   $SCOPE_NAME"
    echo "3- Rango inicial:       $IP_INICIO"
    echo "4- Rango final:         $IP_FIN"

    if [ -z "$GATEWAY" ]; then
        echo "5- GateWay:"
    else
        echo "5- GateWay:             $GATEWAY"
    fi

    echo "6- DNS:                 $DNS_SERVER"
    echo "7- Tiempo de concesión: $LEASE_TIME"
    echo "========================================"
    read -p "Confirmar configuración (S/N): " CONFIRM
    
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        echo "Configuración cancelada."
        return
    fi

    echo "Configurando IP estática en $INTERFAZ..."
    sudo ip link set "$INTERFAZ" down
    sudo ip addr flush dev "$INTERFAZ"
    sudo ip addr add "$IP_INICIO/24" dev "$INTERFAZ"
    sudo ip link set "$INTERFAZ" up
    sleep 2

    echo "Generando archivo de configuración Kea..."
    
    OPTIONS_BLOCK=""
    # Solo agrega la opción routers si GATEWAY no está vacío
    if [ -n "$GATEWAY" ]; then OPTIONS_BLOCK="$OPTIONS_BLOCK { \"name\": \"routers\", \"data\": \"$GATEWAY\" },"; fi
    
    if [ -n "$DNS_SERVER" ]; then OPTIONS_BLOCK="$OPTIONS_BLOCK { \"name\": \"domain-name-servers\", \"data\": \"$DNS_SERVER\" },"; fi
    OPTIONS_BLOCK=$(echo "$OPTIONS_BLOCK" | sed 's/,$//')

    [ -f /etc/kea/kea-dhcp4.conf ] && cp /etc/kea/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf.bak

    cat <<EOF > /etc/kea/kea-dhcp4.conf
{
    "Dhcp4": {
        "interfaces-config": { "interfaces": [ "$INTERFAZ" ] },
        "lease-database": {
            "type": "memfile",
            "persist": true,
            "name": "/var/lib/kea/kea-leases4.csv"
        },
        "valid-lifetime": $LEASE_TIME,
        "max-valid-lifetime": $(($LEASE_TIME * 2)),
        "subnet4": [
            {
                "id": 1,
                "subnet": "$SUBNET/24",
                "user-context": { "name": "$SCOPE_NAME" }, 
                "pools": [ { "pool": "$POOL_START - $IP_FIN" } ],
                "option-data": [ $OPTIONS_BLOCK ]
            }
        ]
    }
}
EOF

    echo "Reiniciando servicio..."
    firewall-cmd --add-service=dhcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null
    systemctl restart kea-dhcp4
    
    if systemctl is-active --quiet kea-dhcp4; then
        echo -e "${GREEN}[EXITO] Servicio configurado y activo.${NC}"
    else
        echo -e "${RED}[ERROR] Kea no pudo iniciar.${NC}"
    fi
    read -p "Presione Enter..."
}

monitorear_servicio() {
    LEASE_FILE="/var/lib/kea/kea-leases4.csv"
    
    # CORRECCIÓN IMPORTANTE: Agregamos '--color' después de watch
    watch --color -n 2 -t "
      echo '==========================================================================';
      echo '                   MONITOREAR SERVICIO DHCP';
      echo '==========================================================================';
      
      # Usamos printf para asegurar compatibilidad con los colores
      if systemctl is-active --quiet kea-dhcp4; then 
          printf 'Estado: \033[1;32mACTIVO\033[0m\n';   # Verde
      else 
          printf 'Estado: \033[1;31mINACTIVO\033[0m\n'; # Rojo
      fi
      
      echo '--------------------------------------------------------------------------';
      echo 'Clientes Conectados:';
      printf '%-20s | %-20s | %-30s\n' 'DIRECCION IP' 'MAC ADDRESS' 'HOSTNAME';
      echo '---------------------|----------------------|-----------------------------';
      
      if [ -f $LEASE_FILE ]; then
         tail -n +2 $LEASE_FILE | awk -F, '{ 
            host = \$9;
            gsub(/\"/, \"\", host); # Eliminar comillas extra si las hay
            if (host == \"\" || host == \" \") host = \"---\";
            
            # Guardamos en el array usando la MAC (\$2) como clave
            formato = sprintf(\"%-20s | %-20s | %-30s\", \$1, \$2, host);
            clientes[\$2] = formato;
         }
         END {
            for (mac in clientes) {
               print clientes[mac];
            }
         }' | sort -V
      else
         echo '             Sin base de datos de concesiones...'
      fi
    "
}

menu_dhcp() {
    while true; do
        clear
        echo "========================================"
        echo "        GESTIONAR SERVICIO DHCP"
        echo "========================================"
        echo "1. Verificar Estado del Servicio"
        echo "2. Instalar Servicio"
        echo "4. Configurar Servicio"
        echo "5. Monitorear Servicio"
        echo "6. Volver al menú principal"
        echo "========================================"
        read -p "Opción: " OPCION
        
        case $OPCION in
            1) estado_servicio ;;
            2) instalar_servicio ;;
            4) configurar_servicio ;;
            5) monitorear_servicio ;;
            6) break ;;
            *) echo "Opción no válida." ; sleep 1 ;;
        esac
    done
}
