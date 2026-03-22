source colores.sh
source utilidades.sh
servididor_instalado() {
    local servicio="$1"

    case "$servicio" in
        Apache)
            rpm -q httpd &>/dev/null && return 0
            ;;
        Nginx)
            rpm -q nginx &>/dev/null && return 0
            ;;
        Tomcat)
            [[ -d /opt/tomcat ]] && return 0
            ;;
        *)
            return 1
            ;;
    esac

    return 1
}
instalar_apache() {
    servididor_instalado "Apache" && return
    while true; do
        read -p "Ingrese el puerto para Apache: " PUERTO

        validar_puerto "$PUERTO" || continue

        if puerto_en_uso "$PUERTO"; then
            echo -e "${ROJO_CLARO}El puerto $PUERTO ya está en uso${RESET}"
            continue
        fi

        break
    done

    validar_repositorio "Apache" || return

    echo "Instalando Apache..."
    if ! dnf install -y $RAIZ_FTP/Apache/*.rpm &>/dev/null; then
        echo -e "${ROJO_CLARO}Falló la instalación de Apache${RESET}"
        return
    fi

    sed -i "s/^Listen .*/Listen $PUERTO/" /etc/httpd/conf/httpd.conf

    firewall-cmd --add-port=${PUERTO}/tcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null

    semanage port -a -t http_port_t -p tcp $PUERTO 2>/dev/null || \
    semanage port -m -t http_port_t -p tcp $PUERTO

    systemctl enable --now httpd &>/dev/null

    echo -e "${VERDE} Apache instalado en puerto $PUERTO${RESET}"
}

instalar_nginx() {
    servididor_instalado "Nginx" && return
    while true; do
        read -p "Ingrese el puerto para Nginx: " PUERTO

        validar_puerto "$PUERTO" || continue

        if puerto_en_uso "$PUERTO"; then
            echo -e "${ROJO_CLARO}El puerto $PUERTO ya está en uso${RESET}"
            continue
        fi

        break
    done

    validar_repositorio "Nginx" || return

    echo "Instalando Nginx..."
    if ! dnf install -y $RAIZ_FTP/Nginx/*.rpm &>/dev/null; then
        echo -e "${ROJO_CLARO}Falló la instalación de Nginx${RESET}"
        return
    fi

    sed -i "s/listen\s\+80;/listen $PUERTO;/" /etc/nginx/nginx.conf

    firewall-cmd --add-port=${PUERTO}/tcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null

    semanage port -a -t http_port_t -p tcp $PUERTO 2>/dev/null || \
    semanage port -m -t http_port_t -p tcp $PUERTO

    systemctl enable --now nginx &>/dev/null

    echo -e "${VERDE} Nginx instalado en puerto $PUERTO${RESET}"
}

instalar_tomcat() {
    servididor_instalado "Tomcat" && return
    while true; do
        read -p "Ingrese el puerto para Tomcat: " PUERTO

        validar_puerto "$PUERTO" || continue

        if puerto_en_uso "$PUERTO"; then
            echo -e "${ROJO_CLARO}El puerto $PUERTO ya está en uso${RESET}"
            continue
        fi

        break
    done

    validar_repositorio "Tomcat" || return

    echo "Instalando Java..."
    if ! dnf install -y java-21-openjdk &>/dev/null; then
        echo -e "${ROJO_CLARO}Falló la instalación de Java${RESET}"
        return
    fi

    echo "Instalando Tomcat..."
    mkdir -p /opt/tomcat

    if ! tar -xzf $RAIZ_FTP/Tomcat/apache-tomcat-*.tar.gz \
        -C /opt/tomcat --strip-components=1; then
        echo -e "${ROJO_CLARO}Falló la extracción de Tomcat${RESET}"
        return
    fi

    sed -i "s/port=\"8080\"/port=\"$PUERTO\"/" /opt/tomcat/conf/server.xml

    chmod +x /opt/tomcat/bin/*.sh

    export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))

    firewall-cmd --add-port=${PUERTO}/tcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null

    /opt/tomcat/bin/startup.sh &>/dev/null

    echo -e "${VERDE} Tomcat instalado en puerto $PUERTO${RESET}"
}

estado_apache() {
    while true; do
        clear
        echo "----------------------------------------"
        echo -e "${NEGRITA}${AZUL}        ESTADO DEL SERVICIO APACHE${RESET}"
        echo "----------------------------------------"

        if ! rpm -q httpd &>/dev/null; then
            echo -e "${AMARILLO_CLARO}[!] Apache NO está instalado${RESET}"
            read -p "Presione Enter para volver..."
            return
        fi

        ESTADO=$(systemctl is-active httpd)

        if [ "$ESTADO" == "active" ]; then
            echo -e "Estado: ${VERDE}ACTIVO${RESET}"
            echo "----------------------------------------"
            echo "[1]   Detener"
            echo "[2]   Reiniciar"
            echo "[3]   Volver"
        else
            echo -e "Estado: ${ROJO}DETENIDO${RESET}"
            echo "----------------------------------------"
            echo "[1]   Iniciar"
            echo "[3]   Volver"
        fi

        read -p "Seleccione: " op

        case $op in
            1)
                if [ "$ESTADO" == "active" ]; then
                    systemctl stop httpd
                else
                    systemctl start httpd
                fi
                ;;
            2)
                systemctl restart httpd
                ;;
            3) return ;;
            *) echo -e "${NEGRITA}${ROJO_CLARO}Opción inválida, intente nuevamente.${RESET}" ; sleep 1 ;;
        esac

        sleep 2
    done
}

estado_nginx() {
    while true; do
        clear
        echo "----------------------------------------"
        echo -e "${NEGRITA}${AZUL}        ESTADO DEL SERVICIO NGINX${RESET}"
        echo "----------------------------------------"

        if ! rpm -q nginx &>/dev/null; then
            echo -e "${AMARILLO_CLARO}[!] Nginx NO está instalado${RESET}"
            read -p "Presione Enter para volver..."
            return
        fi

        ESTADO=$(systemctl is-active nginx)

        if [ "$ESTADO" == "active" ]; then
            echo -e "Estado: ${VERDE}ACTIVO${RESET}"
            echo "----------------------------------------"
            echo "[1]   Detener"
            echo "[2]   Reiniciar"
            echo "[3]   Volver"
        else
            echo -e "Estado: ${ROJO}DETENIDO${RESET}"
            echo "----------------------------------------"
            echo "[1]   Iniciar"
            echo "[3]   Volver"
        fi

        read -p "Seleccione: " op

        case $op in
            1)
                if [ "$ESTADO" == "active" ]; then
                    systemctl stop nginx
                else
                    systemctl start nginx
                fi
                ;;
            2)
                systemctl restart nginx
                ;;
            3) return ;;
            *) echo -e "${NEGRITA}${ROJO_CLARO}Opción inválida, intente nuevamente.${RESET}" ; sleep 1 ;;
        esac

        sleep 2
    done
}

estado_tomcat() {
    while true; do
        clear
        echo "----------------------------------------"
        echo -e "${NEGRITA}${AZUL}        ESTADO DEL SERVICIO TOMCAT${RESET}"
        echo "----------------------------------------"

        if [ ! -d "/opt/tomcat" ]; then
            echo -e "${AMARILLO_CLARO}[!] Tomcat NO está instalado${RESET}"
            read -p "Presione Enter para volver..."
            return
        fi

        if pgrep -f tomcat &>/dev/null; then
            echo -e "Estado: ${VERDE}ACTIVO${RESET}"
            echo "----------------------------------------"
            echo "[1]   Detener"
            echo "[2]   Reiniciar"
            echo "[3]   Volver"
        else
            echo -e "Estado: ${ROJO}DETENIDO${RESET}"
            echo "----------------------------------------"
            echo "[1]   Iniciar"
            echo "[3]   Volver"
        fi

        read -p "Seleccione: " op

        case $op in
            1)
                if pgrep -f tomcat &>/dev/null; then
                    /opt/tomcat/bin/shutdown.sh
                else
                    /opt/tomcat/bin/startup.sh
                fi
                ;;
            2)
                /opt/tomcat/bin/shutdown.sh
                sleep 2
                /opt/tomcat/bin/startup.sh
                ;;
            3) return ;;
            *) echo -e "${NEGRITA}${ROJO_CLARO}Opción inválida, intente nuevamente.${RESET}" ; sleep 1 ;;
        esac

        sleep 2
    done
}

status_srvweb() {
    while true; do
        clear
        echo "========================================"
        echo -e "${NEGRITA}${AZUL}      ESTADO DE SERVICIOS WEB${RESET}"
        echo "========================================"
        echo "[1]   Apache"
        echo "[2]   Nginx"
        echo "[3]   Tomcat"
        echo "[4]   Volver"
        echo "========================================"
        read -p "Seleccione opción: " op

        case $op in
            1) estado_apache ;;
            2) estado_nginx ;;
            3) estado_tomcat ;;
            4) return ;;
            *) echo -e "${NEGRITA}${ROJO_CLARO}Opción inválida, intente nuevamente.${RESET}" ; sleep 1 ;;
        esac
    done
}
instalar_apache_online() {
    if servididor_instalado "Apache"; then
        echo -e "${AMARILLO} Apache ya está instalado.${RESET}"
        read -p "Presione Enter para continuar..."
        return
    fi
    while true; do
        read -p "Puerto Apache: " PUERTO
        validar_puerto "$PUERTO" || continue
        puerto_en_uso "$PUERTO" && continue
        break
    done

    echo "Instalando Apache desde repositorios..."
    dnf install -y httpd &>/dev/null

    sed -i "s/^Listen .*/Listen $PUERTO/" /etc/httpd/conf/httpd.conf

    firewall-cmd --add-port=${PUERTO}/tcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null

    semanage port -a -t http_port_t -p tcp $PUERTO 2>/dev/null || \
    semanage port -m -t http_port_t -p tcp $PUERTO

    systemctl enable --now httpd &>/dev/null

    echo -e "${VERDE} Apache online en puerto $PUERTO${RESET}"
}

instalar_nginx_online() {
    if servididor_instalado "Nginx"; then
        echo -e "${AMARILLO} Nginx ya está instalado.${RESET}"
        read -p "Presione Enter para continuar..."
        return
    fi
    while true; do
        read -p "Puerto Nginx: " PUERTO
        validar_puerto "$PUERTO" || continue
        puerto_en_uso "$PUERTO" && continue
        break
    done

    echo "Instalando Nginx..."
    dnf install -y nginx &>/dev/null

    sed -i "s/listen\s\+80;/listen $PUERTO;/" /etc/nginx/nginx.conf

    firewall-cmd --add-port=${PUERTO}/tcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null

    semanage port -a -t http_port_t -p tcp $PUERTO 2>/dev/null || \
    semanage port -m -t http_port_t -p tcp $PUERTO

    systemctl enable --now nginx &>/dev/null

    echo -e "${VERDE} Nginx online en puerto $PUERTO${RESET}"
}

instalar_tomcat_online() {
    if servididor_instalado "Tomcat"; then
        echo -e "${AMARILLO} Tomcat ya está instalado.${RESET}"
        read -p "Presione Enter para continuar..."
        return
    fi

    while true; do
        read -p "Puerto Tomcat: " PUERTO
        validar_puerto "$PUERTO" || continue
        puerto_en_uso "$PUERTO" && continue
        break
    done

    echo "Instalando Java..."
    dnf install -y java-21-openjdk &>/dev/null

    echo "Descargando Tomcat..."
    cd /tmp || return

    if ! curl -s -O https://archive.apache.org/dist/tomcat/tomcat-10/v10.1.28/bin/apache-tomcat-10.1.28.tar.gz; then
        echo -e "${ROJO} Falló la descarga de Tomcat${RESET}"
        return
    fi

    mkdir -p /opt/tomcat
    rm -rf /opt/tomcat/*

    TOMCAT_FILE=$(ls apache-tomcat-*.tar.gz | head -n 1)

    tar -xzf "$TOMCAT_FILE" -C /opt/tomcat --strip-components=1

    sed -i "s/port=\"8080\"/port=\"$PUERTO\"/" /opt/tomcat/conf/server.xml

    chmod +x /opt/tomcat/bin/*.sh

    export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))

    firewall-cmd --add-port=${PUERTO}/tcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null

    /opt/tomcat/bin/startup.sh &>/dev/null

    sleep 2
    if ! ss -tulnp | grep -q ":$PUERTO "; then
        echo -e "${ROJO} Tomcat no inició correctamente${RESET}"
        return
    fi

    echo -e "${VERDE} Tomcat online en puerto $PUERTO${RESET}"
}
instalar_srvweb_FTP() {
    configurar_conexion_ftp
    while true; do
        clear
        echo "=============================================================="
        echo -e "${NEGRITA}${AZUL}      INSTALACIÓN LOCAL DE SERVIDORES WEB ${RESET}"
        echo "=============================================================="
        echo "[1]   Instalar Apache"
        echo "[2]   Instalar Nginx"
        echo "[3]   Instalar Tomcat"
        echo "[4]   Volver"
        echo "=============================================================="
        read -p "Seleccione opción: " op

        case $op in
            1) instalar_apache ;;
            2) instalar_nginx ;;
            3) instalar_tomcat ;;
            4) return ;;
            *) echo -e "${NEGRITA}${ROJO_CLARO}Opción inválida, intente nuevamente.${RESET}" ; sleep 1 ;;
        esac

        read -p "Presione Enter para continuar..."
    done
}
instalar_srvweb_online() {
    while true; do
        clear
        echo "=============================================================="
        echo -e "${NEGRITA}${AZUL}          INSTALACIÓN ONLINE DE SERVIDORES WEB${RESET}"
        echo "=============================================================="
        echo "[1]   Instalar Apache"
        echo "[2]   Instalar Nginx"
        echo "[3]   Instalar Tomcat"
        echo "[4]   Volver"
        echo "=============================================================="
        read -p "Seleccione opción: " op

        case $op in
            1) instalar_apache_online ;;
            2) instalar_nginx_online ;;
            3) instalar_tomcat_online ;;
            4) return ;;
            *) echo -e "${ROJO}Opción inválida${RESET}"; sleep 1 ;;
        esac

        read -p "Presione Enter para continuar..."
    done
}

menu_instalacion_web() {
    while true; do
        clear
        echo "=============================================================="
        echo -e "${NEGRITA}${AZUL}   INSTALACIÓN DE SERVICIOS WEB   ${RESET}"
        echo "=============================================================="
        echo "[1]   Instalación desde repositorio FTP (local)"
        echo "[2]   Instalación directa (online)"
        echo "[3]   Volver"
        echo "=============================================================="
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1)
                instalar_srvweb_FTP
                ;;
            2)
                instalar_srvweb_online
                ;;
            3)
                return
                ;;
            *)
                echo -e "${ROJO_CLARO}Opción inválida${RESET}"
                sleep 1
                ;;
        esac
    done
}