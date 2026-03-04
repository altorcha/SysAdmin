#!/bin/bash
# =====================================================================================================================
# Tarea 5: Automatización de Servidor FTP
# Autor: Alberto Torres Chaparro
# Update: Funciones para la gestión de usuarios FTP.
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

#===========================================================
#           FUNCIONES DE GESTIÓN DE USUARIOS FTP
#===========================================================
crear_usuarios_ftp() {
    read -p "¿Cuántos usuarios desea crear?: " n
    BASE_DIR="/srv/ftp"

    for ((i=1; i<=n; i++)); do
        echo -e "\n--- Datos del Usuario #$i ---"
        read -p "Nombre de usuario: " usuario
        read -s -p "Contraseña: " pass
        echo "Seleccione el grupo del usuario:"
        echo " [1] Reprobados"
        echo " [2] Recursadores"
        echo " =================================="
        read -p "Seleccion: " g_opt
        
        grupo=$([ "$g_opt" == "1" ] && echo "reprobados" || echo "recursadores")

        # 1. Crear usuario si no existe
        if id "$usuario" &>/dev/null; then
            echo -e "${YELLOW}[!] El usuario $usuario ya existe. Verificando estructura...${NC}"
        else
            useradd -m -d $BASE_DIR/$usuario -s /sbin/nologin $usuario
            echo "$usuario:$pass" | chpasswd
            usermod -aG $grupo $usuario
            echo -e "${GREEN}[EXITO] Usuario $usuario creado.${NC}"
        fi

        # 2. Crear carpetas
        mkdir -p $BASE_DIR/$usuario/{general,$grupo,$usuario}

        # 3. Montajes Bind con validación
        if ! mountpoint -q $BASE_DIR/$usuario/general; then
            mount --bind $BASE_DIR/general $BASE_DIR/$usuario/general
        fi

        if ! mountpoint -q $BASE_DIR/$usuario/$grupo; then
            mount --bind $BASE_DIR/$grupo $BASE_DIR/$usuario/$grupo
        fi

        # 4. Permisos segmentados
        # Carpeta Personal (Solo dueño)
        chown -R $usuario:$grupo $BASE_DIR/$usuario/$usuario
        chmod 700 $BASE_DIR/$usuario/$usuario
        
        # Carpeta de Grupo
        chown :$grupo $BASE_DIR/$usuario/$grupo
        chmod 775 $BASE_DIR/$usuario/$grupo
        
        echo -e "${CYAN}Estructura actualizada para $usuario: [general, $grupo, $usuario]${NC}"
    done
    read -p "Presione Enter para continuar..."
}

# --- FUNCIÓN: CONSULTAR USUARIOS ---
consultar_usuarios_ftp() {
    echo -e "\nLista de usuarios FTP (Home en /srv/ftp):"
    echo "------------------------------------------------"
    # Extrae el nombre de usuario y busca su grupo en texto plano
    awk -F: '$6 ~ /\/srv\/ftp/ {print $1}' /etc/passwd | while read u; do
        grupo=$(id -gn "$u")
        printf "Usuario: %-12s | Grupo Principal: %-10s\n" "$u" "$grupo"
    done
    echo "------------------------------------------------"
    read -p "Presione Enter para continuar..."
}

# --- FUNCIÓN: ELIMINAR USUARIOS ---
eliminar_usuario_ftp() {
    read -p "Nombre del usuario a eliminar: " usuario_del
    if id "$usuario_del" &>/dev/null; then
        echo "Desmontando directorios vinculados..."
        umount /srv/ftp/$usuario_del/general 2>/dev/null
        umount /srv/ftp/$usuario_del/reprobados 2>/dev/null
        umount /srv/ftp/$usuario_del/recursadores 2>/dev/null
        
        userdel -r "$usuario_del" &>/dev/null
        echo -e "${GREEN}[EXITO] Usuario $usuario_del eliminado correctamente.${NC}"
    else
        echo -e "${RED}[ERROR] El usuario no existe.${NC}"
    fi
    read -p "Presione Enter para continuar..."
}
# --- FUNCIÓN: CAMBIAR DE GRUPO ---
cambiar_grupo_usuario() {
    echo -e "\n--- CAMBIO DE GRUPO ---"
    read -p "Ingrese el nombre del usuario a modificar (ej. u1): " usuario
    
    # Verificamos que el usuario exista
    if id "$usuario" &>/dev/null; then
        echo -e "Seleccione el NUEVO grupo para $usuario:"
        echo "[1] reprobados"
        echo "[2] recursadores"
        read -p "Seleccion: " opcion
        
        if [ "$opcion" == "1" ]; then
            nuevo_grupo="reprobados"
        elif [ "$opcion" == "2" ]; then
            nuevo_grupo="recursadores"
        else
            echo -e "Opción no válida."
            sleep 2
            return
        fi
        
        # 1. Identificar a qué grupo pertenece actualmente
        if id -nG "$usuario" | grep -qw "reprobados"; then
            grupo_viejo="reprobados"
        elif id -nG "$usuario" | grep -qw "recursadores"; then
            grupo_viejo="recursadores"
        else
            grupo_viejo=""
        fi

        # Validar que no elija el mismo grupo
        if [ "$grupo_viejo" == "$nuevo_grupo" ]; then
            echo -e "[!] El usuario ya pertenece al grupo $nuevo_grupo."
            read -p "Presione Enter para continuar..."
            return cambiar_grupo_usuario
        fi

        # 2. Cambiar grupos 
        if [ -n "$grupo_viejo" ]; then
            gpasswd -d $usuario $grupo_viejo &>/dev/null # Lo sacamos del viejo
        fi
        usermod -aG $nuevo_grupo $usuario # Lo metemos al nuevo

        # 3. Actualizar la estructura de carpetas 
        if [ -n "$grupo_viejo" ]; then
            echo "Desmontando carpeta anterior ($grupo_viejo)..."
            
            # Bucle para destruir TODAS las capas de montajes apilados
            while grep -qs "/srv/ftp/$usuario/$grupo_viejo" /proc/mounts; do
                sudo umount -l /srv/ftp/$usuario/$grupo_viejo &>/dev/null
                sleep 0.5
            done
            
            sudo rm -rf /srv/ftp/$usuario/$grupo_viejo 
        fi

        echo "Montando nueva carpeta compartida ($nuevo_grupo)..."
        mkdir -p /srv/ftp/$usuario/$nuevo_grupo
        mount --bind /srv/ftp/$nuevo_grupo /srv/ftp/$usuario/$nuevo_grupo

        # 4. Ajustar permisos
        chown :$nuevo_grupo /srv/ftp/$usuario/$nuevo_grupo
        chmod 775 /srv/ftp/$usuario/$nuevo_grupo

        echo -e "[EXITO] Usuario $usuario movido a $nuevo_grupo exitosamente."
        echo -e "La nueva estructura es: [general, $nuevo_grupo, $usuario]"
    else
        echo -e "[ERROR] El usuario no existe."
    fi
    read -p "Presione Enter para continuar..."
}

Gestionar-Usuarios-FTP() {
    while true; do
        clear
        echo "================================================"
        echo "       GESTIÓN DE USUARIOS Y PERMISOS FTP"
        echo "================================================"
        echo " [1] Crear Usuarios"
        echo " [2] Consultar Usuarios Actuales"
        echo " [3] Eliminar Usuario"
        echo " [4] Cambiar Grupo de Usuario"    
        echo " [5] Volver al Menú FTP"
        echo "================================================"
        read -p "Seleccione una opción: " subopcion

        case $subopcion in
            1) crear_usuarios_ftp ;;
            2) consultar_usuarios_ftp ;;
            3) eliminar_usuario_ftp ;;
            4) cambiar_grupo_usuario ;;
            5) return ;;
            *) echo -e "${YELLOW}Opción no válida.${NC}"; sleep 1 ;;
        esac
    done
}