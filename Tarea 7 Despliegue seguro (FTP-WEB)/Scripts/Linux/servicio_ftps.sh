source ./colores.sh
source ./utilidades.sh
RAIZ_FTP="/var/ftp/pub/http"

SERVICIOS=("Apache" "Nginx" "Tomcat")

instalar_vsftpd() {
    if rpm -q vsftpd &> /dev/null; then
        echo -e "${NEGRITA}${AMARILLO_CLARO}El servicio FTP ya está instalado.${RESET}"
        echo "================================================"
        read -p "Presione Enter para continuar..."
        return
    fi

    echo "Instalando vsftpd..."
    dnf install -y vsftpd &> /dev/null

    if [ $? -eq 0 ]; then
        echo -e "${NEGRITA}${VERDE}Instalación completada.${RESET}"
        systemctl enable --now vsftpd &> /dev/null
    else
        echo -e "${NEGRITA}${ROJO_CLARO} ERROR *** Falló la instalación de ${RESET} ${NEGRITA}${MAGENTA_CLARO}vsftpd${RESET}"
    fi

    read -p "Presiona Enter para continuar..."
}

configurar_ftps() {
    generar_certificado_ssl
    sleep 2
    configurar_vsftpd_ssl
    sleep 2
    configurar_pam_vsftpd
    sleep 2
    crear_estructura_ftp
    sleep 2
    configurar_permisos
    sleep 2
    poblar_repositorio
    sleep 2

    read -p "Presione Enter para continuar..."
}

estado_ftp() {
    while true; do
        clear
        echo "----------------------------------------"
        echo "        ESTADO DEL SERVICIO FTP"
        echo "----------------------------------------"

        # ¿El servicio vsftpd está instalado?
        if ! rpm -q vsftpd &>/dev/null; then
            echo -e "${NEGRITA}${AMARILLO_CLARO}[!] El servicio FTP NO está instalado.${RESET}"
            echo -e "${NEGRITA}${AMARILLO_CLARO}Use la opción de instalación primero.${RESET}"
            echo "----------------------------------------"
            read -p "Presione Enter para volver..."
            return
        fi

        # Obtener el estado del servicio
        ESTADO=$(systemctl is-active vsftpd)

        if [ "$ESTADO" == "active" ]; then
            echo -n "Estado Actual: "
            echo -e "${VERDE}ACTIVO (Running)${RESET}"
            echo "----------------------------------------"
            echo " [1] Detener el servicio"
            echo " [2] Reiniciar el servicio"
            echo " [3] Volver al menú principal"
        else
            echo -n "Estado Actual: "
            echo -e "${ROJO}DETENIDO (Stopped)${RESET}"
            echo "----------------------------------------"
            echo " [1] Iniciar el servicio"
            echo " [3] Volver al menú principal"
        fi

        echo "----------------------------------------"
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1)
                if [ "$ESTADO" == "active" ]; then
                    echo "Deteniendo servicio FTP..."
                    sudo systemctl stop vsftpd
                else
                    echo "Iniciando servicio FTP..."
                    sudo systemctl start vsftpd
                fi
                sleep 2
                ;;
            2)
                if [ "$ESTADO" == "active" ]; then
                    echo "Reiniciando servicio FTP..."
                    sudo systemctl restart vsftpd
                    sleep 2
                fi
                ;;
            3)
                return
                ;;
            *)
                echo "Opción no válida."
                sleep 1
                ;;
        esac
    done
}

crear_usuario_ftp() {
    read -p "Ingrese el nombre de usuario: " usuario
    read -s -p "Ingrese la contraseña: " password
    echo ""

    echo -e "${NEGRITA}${AZUL}Configurando usuario FTP...${RESET}"

    if id "$usuario" &>/dev/null; then
        echo -e "${NEGRITA}${VERDE}El usuario ya existe${RESET}"
    else
        useradd -m "$usuario"
        echo "$usuario:$password" | chpasswd
        usermod -s /sbin/nologin "$usuario"
        echo -e "${NEGRITA}${VERDE_CLARO}Usuario creado${RESET}"
    fi
    echo "pruebe la conexion al repositorio FTP con el usuario $usuario"
    echo -e "${FONDO_MAGENTA}${NEGRITA}${BLANCO_BRILLANTE}curl -k --ssl-reqd -u ususario:contraseña ftp://IP_SERVIDOR/http/${RESET}"
    read -p "Presione Enter para continuar..."
}

generar_certificado_ssl() {
    echo -e "${NEGRITA}${AZUL}Generando certificado SSL...${RESET}"

    mkdir -p /etc/ssl/private

    openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/ssl/private/vsftpd.key \
    -out /etc/ssl/private/vsftpd.crt \
    -subj "/C=MX/ST=Sinaloa/L=LosMochis/O=Reprobados/OU=TI/CN=reprobados.com"

    cat /etc/ssl/private/vsftpd.key /etc/ssl/private/vsftpd.crt > /etc/ssl/private/vsftpd.pem

    chmod 600 /etc/ssl/private/vsftpd.*

    echo -e "${NEGRITA}${VERDE}Certificado generado${RESET}"
}

configurar_vsftpd_ssl() {
    echo -e "${NEGRITA}${AZUL}Configurando FTPS...${RESET}"

    cat > /etc/vsftpd/vsftpd.conf <<EOF
anonymous_enable=NO
local_enable=YES
write_enable=NO
chroot_local_user=YES
allow_writeable_chroot=YES
check_shell=NO

pam_service_name=vsftpd

# FTP pasivo
pasv_enable=YES
pasv_min_port=30000
pasv_max_port=31000

# SSL
ssl_enable=YES
rsa_cert_file=/etc/ssl/private/vsftpd.pem
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH

# Seguridad
local_root=/var/ftp/pub
EOF

    systemctl restart vsftpd

    echo -e "${NEGRITA}${VERDE}FTPS configurado${RESET}"
}

configurar_pam_vsftpd() {
    sed -i 's/^auth.*pam_shells.so/#&/' /etc/pam.d/vsftpd
    systemctl restart vsftpd
}

crear_estructura_ftp() {
    echo -e "${NEGRITA}${AZUL}Creando estructura FTP...${RESET}"

    for servicio in "${SERVICIOS[@]}"; do
        mkdir -p "$RAIZ_FTP/$servicio"
    done

    echo -e "${NEGRITA}${VERDE}Estructura creada${RESET}"
}

configurar_permisos() {
    echo -e "${NEGRITA}${AZUL}Configurando permisos...${RESET}"

    chown -R "$USUARIO_FTP:$USUARIO_FTP" /var/ftp/pub
    chmod -R 755 /var/ftp/pub

    echo -e "${NEGRITA}${VERDE}Permisos aplicados${RESET}"
}

poblar_repositorio() {
    echo -e "${NEGRITA}${AZUL}Poblando repositorio FTP... (/var/ftp/pub/http)${RESET}"

    # --- APACHE ---
    echo -e "${AMARILLO_CLARO}Descargando paquete de Apache...${RESET}"
    cd "$RAIZ_FTP/Apache" || exit

    rm -f *.rpm *.sha256

    dnf download httpd -y &> /dev/null

    for file in httpd*.rpm; do
        sha256sum "$file" > "$file.sha256"
    done

    # --- NGINX ---
    echo -e "${AMARILLO_CLARO}Descargando paquete de Nginx...${RESET}"
    cd "$RAIZ_FTP/Nginx" || exit

    rm -f *.rpm *.sha256

    dnf download nginx -y &> /dev/null

    for file in nginx*.rpm; do
        sha256sum "$file" > "$file.sha256"
    done

    # --- TOMCAT ---
    echo -e "${AMARILLO_CLARO}Descargando paquete de Tomcat...${RESET}"
    cd "$RAIZ_FTP/Tomcat" || exit

    rm -f *.tar.gz *.sha256
                
    TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-10/v10.1.28/bin/apache-tomcat-10.1.28.tar.gz"
    ARCHIVO_TOMCAT=$(basename "$TOMCAT_URL")

    curl -s -O "$TOMCAT_URL"

    sha256sum "$ARCHIVO_TOMCAT" > "$ARCHIVO_TOMCAT.sha256"

    echo -e "${NEGRITA}${VERDE}Repositorio poblado correctamente${RESET}"
    tree /var/ftp/pub/http

    echo 
}

validar_repositorio() {
    local SERVICIO=$1

    echo -e "${AZUL}Verificando repositorio $SERVICIO...${RESET}"

    if ! curl -k --ssl-reqd -u $USUARIO_FTP:$PASSWORD_FTP \
        ftp://$IP_SERVIDOR/http/$SERVICIO/ &>/dev/null; then
        echo -e "${ROJO_CLARO}No se puede acceder al repositorio${RESET}"
        return 1
    fi

    if ! find "$RAIZ_FTP/$SERVICIO" -name "*.sha256" -execdir sha256sum -c {} \; &>/dev/null; then
        echo -e "${ROJO_CLARO}Falló la validación SHA256${RESET}"
        return 1
    fi

    echo -e "${VERDE} Repositorio validado${RESET}"
}

configurar_conexion_ftp() {

    echo -e "${NEGRITA}${AZUL}Configuración de conexión al repositorio FTP${RESET}"

    # IP
    while true; do
        read -p "Ingrese la IP del servidor FTP: " IP_SERVIDOR
        if validar_ip "$IP_SERVIDOR"; then
            break
        else
            echo -e "${ROJO_CLARO}IP inválida${RESET}"
        fi
    done

    # Usuario
    while true; do
        read -p "Ingrese el usuario FTP: " USUARIO_FTP
        [[ -n "$USUARIO_FTP" ]] && break
        echo -e "${ROJO_CLARO}Usuario no puede estar vacío${RESET}"
    done

    # Password
    while true; do
        read -s -p "Ingrese la contraseña FTP: " PASSWORD_FTP
        echo ""
        [[ -n "$PASSWORD_FTP" ]] && break
        echo -e "${ROJO_CLARO}Contraseña no puede estar vacía${RESET}"
    done

    echo -e "${VERDE} Datos de conexión configurados${RESET}"
    sleep 1
}

menu_ftps() {
    while true; do
        clear
        echo "=============================================================================="
        echo -e "${NEGRITA}${AZUL}                                 Menu FTPS${RESET}"
        echo "=============================================================================="
        echo "[1]    Estado vsftpd"
        echo "[2]    Instalar vsftpd"
        echo "[3]    Configurar FTPS"
        echo "[4]    Crear usuario FTP"
        echo "[5]    Salir"
        echo "=============================================================================="
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1) estado_ftp
                ;;
            2) instalar_vsftpd
                ;;
            3) configurar_ftps
                ;;
            4) crear_usuario_ftp
                ;;
            5)
                read -p "Presione Enter para continuar..."
                return
                ;;
            *) echo -e "${NEGRITA}${ROJO_CLARO}Opción inválida, intente nuevamente.${RESET}" ;;
        esac
    done
}