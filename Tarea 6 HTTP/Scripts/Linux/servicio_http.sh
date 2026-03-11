#!/bin/bash

ROJO='\033[0;31m'
VERDE='\033[0;32m'
RESET='\033[0m'

mensaje() {
    local tipo="$1"
    local texto="$2"
    case "$tipo" in
        ok)    echo -e "  ${VERDE}${texto}${RESET}" ;;
        error) echo -e "  ${ROJO}${texto}${RESET}" ;;
        *)     echo -e "  ${texto}" ;;
    esac
}

validar_root() {
    if [[ $EUID -ne 0 ]]; then
        mensaje error "Este script debe ejecutarse como root (sudo)."
        exit 1
    fi
}

validar_puerto() {
    local puerto="$1"
    local reservados=(22 25 53 443 3306 5432 6379 27017)
    if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
        mensaje error "El puerto debe ser un numero entero."; return 1
    fi
    if (( puerto < 1 || puerto > 65535 )); then
        mensaje error "Puerto fuera de rango (1-65535)."; return 1
    fi
    for r in "${reservados[@]}"; do
        if (( puerto == r )); then
            mensaje error "Puerto $puerto reservado para otro servicio."; return 1
        fi
    done
    return 0
}

puerto_en_uso() {
    local puerto="$1"
    if ss -tlnp | grep -q ":${puerto} "; then
        mensaje error "El puerto $puerto ya esta en uso."; return 0
    fi
    return 1
}

solicitar_puerto() {
    local puerto
    while true; do
        read -rp "  Puerto de escucha: " puerto
        validar_puerto "$puerto" || continue
        puerto_en_uso "$puerto" && continue
        echo "$puerto"
        return 0
    done
}

configurar_firewall() {
    local puerto="$1"
    if ! systemctl is-active --quiet firewalld; then
        systemctl enable --now firewalld
    fi
    firewall-cmd --permanent --add-port="${puerto}/tcp" > /dev/null 2>&1
    local puertos_http=(80 8080 8888 8000 8008 3000 4000)
    for p in "${puertos_http[@]}"; do
        [[ "$p" == "$puerto" ]] && continue
        if firewall-cmd --query-port="${p}/tcp" --permanent > /dev/null 2>&1; then
            if ! ss -tlnp | grep -q ":${p} "; then
                firewall-cmd --permanent --remove-port="${p}/tcp" > /dev/null 2>&1
            fi
        fi
    done
    if [[ "$puerto" != "80" ]]; then
        firewall-cmd --permanent --remove-service=http > /dev/null 2>&1 || true
    fi
    firewall-cmd --reload > /dev/null 2>&1
}

configurar_selinux_puerto() {
    local puerto="$1"
    if ! command -v getenforce &>/dev/null || [[ "$(getenforce)" == "Disabled" ]]; then
        return 0
    fi
    if ! command -v semanage &>/dev/null; then
        dnf install -y policycoreutils-python-utils > /dev/null 2>&1
    fi
    if semanage port -l | grep -q "http_port_t.*tcp.*\b${puerto}\b"; then
        return 0
    fi
    semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null || \
        semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null || true
}

crear_usuario_servicio() {
    local usuario="$1"
    local directorio="$2"
    if ! id "$usuario" &>/dev/null; then
        useradd -r -s /sbin/nologin -d "$directorio" "$usuario"
    fi
    mkdir -p "$directorio"
    chown -R "${usuario}:${usuario}" "$directorio"
    chmod 750 "$directorio"
    chmod o-rx /root 2>/dev/null || true
}

crear_index() {
    local webroot="$1"
    local servicio="$2"
    local version="$3"
    local puerto="$4"
    mkdir -p "$webroot"
    cat > "${webroot}/index.html" <<EOF
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>${servicio}</title>
<style>
  body{font-family:'Segoe UI',sans-serif;background:#0d1117;color:#c9d1d9;
       display:flex;justify-content:center;align-items:center;height:100vh;margin:0}
  .card{background:#161b22;border:1px solid #30363d;border-radius:12px;
        padding:2rem 3rem;text-align:center;max-width:480px}
  h1{color:#58a6ff;margin-bottom:.5rem}
  .badge{display:inline-block;background:#238636;color:#fff;
         border-radius:20px;padding:.3rem 1rem;font-size:.9rem;margin:.3rem}
  .port{background:#1f6feb}
  p{color:#8b949e;font-size:.85rem;margin-top:1.5rem}
</style>
</head>
<body>
  <div class="card">
    <h1>${servicio}</h1>
    <span class="badge">Version: ${version}</span>
    <span class="badge port">Puerto: ${puerto}</span>
    <p>Desplegado automaticamente - Tarea 6 Administracion de Sistemas</p>
  </div>
</body>
</html>
EOF
}

obtener_versiones_dnf() {
    local paquete="$1"
    mapfile -t VERSIONES < <(
        dnf list --showduplicates "$paquete" 2>/dev/null \
        | awk -v pkg="$paquete" '$1 ~ "^"pkg"[.@]" {print $2}' \
        | grep -E '^[0-9]+\.[0-9]+' \
        | sort -V \
        | uniq
    )
}

seleccionar_version() {
    local paquete="$1"
    obtener_versiones_dnf "$paquete"
    if [[ ${#VERSIONES[@]} -eq 0 ]]; then
        mensaje error "Sin versiones disponibles. Verifique conectividad y repositorios."
        return 1
    fi
    local total=${#VERSIONES[@]}
    echo ""
    echo "  Versiones disponibles:"
    echo ""
    local i=0
    for v in "${VERSIONES[@]}"; do
        if (( i == total - 1 )); then
            echo "    [$((i+1))] $v  (reciente)"
        elif (( i == total - 2 )); then
            echo "    [$((i+1))] $v  (estable)"
        else
            echo "    [$((i+1))] $v"
        fi
        (( i++ ))
    done
    echo ""
    local opcion
    while true; do
        read -rp "  Seleccione [1-${total}]: " opcion
        if [[ "$opcion" =~ ^[0-9]+$ ]] && (( opcion >= 1 && opcion <= total )); then
            VERSION_ELEGIDA="${VERSIONES[$((opcion-1))]}"
            return 0
        fi
        mensaje error "Opcion invalida."
    done
}

obtener_version_nginx() {
    local rama="$1"
    local repo
    [[ "$rama" == "mainline" ]] && repo="nginx-mainline" || repo="nginx-stable"
    dnf list --showduplicates --enablerepo="$repo" nginx 2>/dev/null \
        | awk '/^nginx/{print $2}' \
        | grep -E '^[0-9]+' \
        | sort -V | tail -1
}

obtener_versiones_tomcat() {
    mapfile -t VERSIONES_TOMCAT < <(
        curl -s --retry 3 "https://dlcdn.apache.org/tomcat/" \
        | grep -oP 'tomcat-\K[0-9]+' \
        | sort -Vu
    )
    if [[ ${#VERSIONES_TOMCAT[@]} -eq 0 ]]; then
        VERSIONES_TOMCAT=("9" "10" "11")
    fi
}

obtener_subversion_tomcat() {
    local major="$1"
    local subver
    subver=$(curl -s --retry 3 "https://dlcdn.apache.org/tomcat/tomcat-${major}/" \
             | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    echo "${subver:-${major}.0.0}"
}

instalar_apache() {
    echo ""
    mensaje info "[ Apache ]"
    echo ""
    seleccionar_version "httpd" || return 1
    local version="$VERSION_ELEGIDA"
    local puerto
    puerto=$(solicitar_puerto)
    echo ""
    echo "  Servicio : Apache"
    echo "  Version  : $version"
    echo "  Puerto   : $puerto"
    echo ""
    read -rp "  Confirmar instalacion [S/N]: " confirm
    [[ ! "$confirm" =~ ^[sS]$ ]] && return
    echo ""
    mensaje info "Instalando Apache..."
    dnf install -y "httpd-${version}" > /dev/null 2>&1 || \
        dnf install -y httpd > /dev/null 2>&1
    local ver_real
    ver_real=$(httpd -v 2>/dev/null | awk '/Server version/{print $3}' | cut -d'/' -f2)
    crear_usuario_servicio "apache" "/var/www/html"
    sed -i "s/^Listen .*/Listen ${puerto}/" /etc/httpd/conf/httpd.conf
    cat > /etc/httpd/conf.d/security.conf <<'SECEOF'
ServerTokens Prod
ServerSignature Off
TraceEnable Off
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"

<Directory "/var/www/html">
    <LimitExcept GET POST HEAD>
        deny from all
    </LimitExcept>
</Directory>
SECEOF
    if ! grep -q "mod_headers" /etc/httpd/conf.modules.d/*.conf 2>/dev/null; then
        echo "LoadModule headers_module modules/mod_headers.so" \
            >> /etc/httpd/conf.modules.d/00-base.conf
    fi
    crear_index "/var/www/html" "Apache" "${ver_real:-$version}" "$puerto"
    configurar_selinux_puerto "$puerto"
    configurar_firewall "$puerto"
    systemctl enable --now httpd > /dev/null 2>&1
    systemctl restart httpd
    mensaje ok "Apache instalado correctamente en puerto ${puerto}."
    echo ""
    read -rp "  Presione Enter para continuar..." _
}

instalar_nginx() {
    echo ""
    mensaje info "[ Nginx ]"
    echo ""
    if ! command -v yum-config-manager &>/dev/null; then
        dnf install -y yum-utils > /dev/null 2>&1
    fi
    cat > /etc/yum.repos.d/nginx.repo <<'REPOEOF'
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=https://nginx.org/packages/mainline/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
REPOEOF
    dnf makecache --repo nginx-stable --repo nginx-mainline -q 2>/dev/null || true
    local ver_stable ver_mainline
    ver_stable=$(obtener_version_nginx "stable")
    ver_mainline=$(obtener_version_nginx "mainline")
    local opciones=() ramas=() i=1
    echo "  Versiones disponibles:"
    echo ""
    if [[ -n "$ver_stable" ]]; then
        echo "    [$i] $ver_stable  (estable)"
        opciones+=("$ver_stable"); ramas+=("nginx-stable"); (( i++ ))
    fi
    if [[ -n "$ver_mainline" ]]; then
        echo "    [$i] $ver_mainline  (reciente)"
        opciones+=("$ver_mainline"); ramas+=("nginx-mainline")
    fi
    if [[ ${#opciones[@]} -eq 0 ]]; then
        mensaje error "No se pudieron obtener versiones de nginx.org."
        return 1
    fi
    echo ""
    local opcion
    while true; do
        read -rp "  Seleccione [1-${#opciones[@]}]: " opcion
        if [[ "$opcion" =~ ^[0-9]+$ ]] && (( opcion >= 1 && opcion <= ${#opciones[@]} )); then
            break
        fi
        mensaje error "Opcion invalida."
    done
    local version="${opciones[$((opcion-1))]}"
    local repo_elegido="${ramas[$((opcion-1))]}"
    local puerto
    puerto=$(solicitar_puerto)
    echo ""
    echo "  Servicio : Nginx"
    echo "  Version  : $version"
    echo "  Puerto   : $puerto"
    echo ""
    read -rp "  Confirmar instalacion [S/N]: " confirm
    [[ ! "$confirm" =~ ^[sS]$ ]] && return
    echo ""
    mensaje info "Instalando Nginx..."
    dnf config-manager --disable nginx-stable nginx-mainline > /dev/null 2>&1
    dnf config-manager --enable "$repo_elegido" > /dev/null 2>&1
    dnf install -y nginx > /dev/null 2>&1
    local ver_real
    ver_real=$(nginx -v 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')
    crear_usuario_servicio "nginx" "/usr/share/nginx/html"
    sed -i "s/listen\s*80\b/listen ${puerto}/" /etc/nginx/conf.d/default.conf 2>/dev/null || \
    sed -i "s/listen\s*80\b/listen ${puerto}/" /etc/nginx/nginx.conf
    cat > /etc/nginx/conf.d/security.conf <<SECEOF
server_tokens off;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
SECEOF
    if ! grep -q "TRACE\|TRACK" /etc/nginx/nginx.conf; then
        sed -i '/server {/a \    if ($request_method !~ ^(GET|POST|HEAD)$) { return 405; }' \
            /etc/nginx/nginx.conf 2>/dev/null || true
    fi
    crear_index "/usr/share/nginx/html" "Nginx" "${ver_real:-$version}" "$puerto"
    configurar_selinux_puerto "$puerto"
    configurar_firewall "$puerto"
    systemctl enable --now nginx > /dev/null 2>&1
    systemctl restart nginx
    mensaje ok "Nginx instalado correctamente en puerto ${puerto}."
    echo ""
    read -rp "  Presione Enter para continuar..." _
}

instalar_tomcat() {
    echo ""
    mensaje info "[ Tomcat ]"
    echo ""
    if ! command -v java &>/dev/null; then
        mensaje info "Instalando Java..."
        dnf install -y java-21-openjdk-devel 2>/dev/null || \
        dnf install -y java-17-openjdk-devel 2>/dev/null || \
        dnf install -y java-latest-openjdk-devel > /dev/null 2>&1
    fi
    obtener_versiones_tomcat
    local total_tc=${#VERSIONES_TOMCAT[@]}
    echo "  Versiones disponibles:"
    echo ""
    local i=0
    for v in "${VERSIONES_TOMCAT[@]}"; do
        if (( i == total_tc - 1 )); then
            echo "    [$((i+1))] Tomcat ${v}.x  (reciente)"
        elif (( i == total_tc - 2 )); then
            echo "    [$((i+1))] Tomcat ${v}.x  (estable)"
        else
            echo "    [$((i+1))] Tomcat ${v}.x"
        fi
        (( i++ ))
    done
    echo ""
    local opcion
    while true; do
        read -rp "  Seleccione [1-${total_tc}]: " opcion
        if [[ "$opcion" =~ ^[0-9]+$ ]] && (( opcion >= 1 && opcion <= total_tc )); then
            break
        fi
        mensaje error "Opcion invalida."
    done
    local major="${VERSIONES_TOMCAT[$((opcion-1))]}"
    local version
    version=$(obtener_subversion_tomcat "$major")
    local puerto
    puerto=$(solicitar_puerto)
    echo ""
    echo "  Servicio : Tomcat"
    echo "  Version  : $version"
    echo "  Puerto   : $puerto"
    echo ""
    read -rp "  Confirmar instalacion [S/N]: " confirm
    [[ ! "$confirm" =~ ^[sS]$ ]] && return
    echo ""
    mensaje info "Instalando Tomcat..."
    local install_dir="/opt/tomcat"
    local tarball="apache-tomcat-${version}.tar.gz"
    local url="https://dlcdn.apache.org/tomcat/tomcat-${major}/v${version}/bin/${tarball}"
    if ! curl -fL --retry 3 -o "/tmp/${tarball}" "$url" 2>/dev/null; then
        if ! curl -fL --insecure --retry 3 -o "/tmp/${tarball}" "$url"; then
            mensaje error "Fallo en la descarga. Verifique conectividad."
            return 1
        fi
    fi
    mkdir -p "$install_dir"
    tar -xzf "/tmp/${tarball}" -C "$install_dir" --strip-components=1
    rm -f "/tmp/${tarball}"
    crear_usuario_servicio "tomcat" "$install_dir"
    chown -R tomcat:tomcat "$install_dir"
    chmod -R 750 "$install_dir"
    chmod +x "${install_dir}/bin/"*.sh
    local java_bin=""
    for candidate in \
        /usr/lib/jvm/java-21-openjdk/bin/java \
        /usr/lib/jvm/java-21/bin/java \
        /usr/lib/jvm/java-17-openjdk/bin/java \
        /usr/lib/jvm/java-17/bin/java \
        /usr/lib/jvm/jre-17/bin/java \
        /usr/lib/jvm/java-17-openjdk-amd64/bin/java; do
        if [[ -x "$candidate" ]]; then java_bin="$candidate"; break; fi
    done
    if [[ -z "$java_bin" ]]; then
        java_bin=$(find /usr/lib/jvm -name "java" -type f -executable 2>/dev/null | head -1)
    fi
    if [[ -z "$java_bin" ]]; then
        mensaje error "No se encontro Java. Verifique la instalacion."
        return 1
    fi
    local java_home
    java_home=$(dirname "$(dirname "$(readlink -f "$java_bin")")")
    cat > /etc/profile.d/tomcat.sh <<ENVEOF
export CATALINA_HOME=${install_dir}
export JAVA_HOME=${java_home}
export PATH=\$JAVA_HOME/bin:\$PATH
ENVEOF
    sed -i "s/port=\"8080\"/port=\"${puerto}\"/" "${install_dir}/conf/server.xml"
    sed -i 's/<Connector port="8009"/<Connector port="8009" secure="true" address="::1"/' \
        "${install_dir}/conf/server.xml" 2>/dev/null || true
    cat > /etc/systemd/system/tomcat.service <<SVCEOF
[Unit]
Description=Apache Tomcat ${version}
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=${java_home}"
Environment="CATALINA_HOME=${install_dir}"
Environment="CATALINA_PID=${install_dir}/temp/tomcat.pid"
ExecStart=${install_dir}/bin/startup.sh
ExecStop=${install_dir}/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
SVCEOF
    crear_index "${install_dir}/webapps/ROOT" "Tomcat" "$version" "$puerto"
    configurar_selinux_puerto "$puerto"
    configurar_firewall "$puerto"
    systemctl daemon-reload
    systemctl enable --now tomcat
    mensaje ok "Tomcat ${version} instalado correctamente en puerto ${puerto}."
    echo ""
    read -rp "  Presione Enter para continuar..." _
}

detectar_servicios_http() {
    HTTP_SERVICIOS=()
    HTTP_NOMBRES=()
    if command -v httpd &>/dev/null || rpm -qa | grep -q "^httpd-[0-9]"; then
        HTTP_SERVICIOS+=("httpd");  HTTP_NOMBRES+=("Apache")
    fi
    if command -v nginx &>/dev/null || rpm -qa | grep -q "^nginx-[0-9]"; then
        HTTP_SERVICIOS+=("nginx");  HTTP_NOMBRES+=("Nginx")
    fi
    if systemctl list-unit-files | grep -q "^tomcat.service"; then
        HTTP_SERVICIOS+=("tomcat"); HTTP_NOMBRES+=("Tomcat")
    fi
}

estado_color() {
    local estado
    estado=$(systemctl is-active "$1" 2>/dev/null)
    case "$estado" in
        active)   echo -e "${VERDE}ACTIVO${RESET}"   ;;
        inactive) echo -e "${ROJO}DETENIDO${RESET}"  ;;
        failed)   echo -e "${ROJO}FALLIDO${RESET}"   ;;
        *)        echo "DESCONOCIDO" ;;
    esac
}

obtener_puerto_servicio() {
    local puerto
    case "$1" in
        httpd)  puerto=$(grep -E "^Listen" /etc/httpd/conf/httpd.conf 2>/dev/null \
                         | awk '{print $2}' | head -1) ;;
        nginx)  puerto=$(grep -E "listen\s+[0-9]+" /etc/nginx/conf.d/default.conf \
                         /etc/nginx/nginx.conf 2>/dev/null \
                         | grep -oP '\d+' | head -1) ;;
        tomcat) puerto=$(ss -tlnp 2>/dev/null \
                         | grep -i tomcat \
                         | grep -oP ':\K[0-9]+(?=\s)' | head -1)
                if [[ -z "$puerto" ]]; then
                    local xml="/opt/tomcat/conf/server.xml"
                    puerto=$(grep -A2 '<Connector' "$xml" 2>/dev/null \
                             | grep -B2 'HTTP/1.1' \
                             | grep -oP 'port="\K[0-9]+' | head -1)
                fi
                if [[ -z "$puerto" ]]; then
                    puerto=$(grep -oP 'port="\K[0-9]+' /opt/tomcat/conf/server.xml 2>/dev/null \
                             | grep -vE '^(8005|8009|8443)$' | head -1)
                fi ;;
    esac
    echo "${puerto:-N/A}"
}

desinstalar_servicio() {
    local servicio="$1" nombre="$2"
    echo ""
    read -rp "  Confirma desinstalar ${nombre}? [S/N]: " confirm
    [[ ! "$confirm" =~ ^[sS]$ ]] && return
    mensaje info "Desinstalando ${nombre}..."
    systemctl stop "$servicio" 2>/dev/null || true
    systemctl disable "$servicio" 2>/dev/null || true
    case "$servicio" in
        httpd)  dnf remove -y httpd > /dev/null 2>&1; rm -f /etc/httpd/conf.d/security.conf ;;
        nginx)  dnf remove -y nginx > /dev/null 2>&1; rm -f /etc/nginx/conf.d/security.conf ;;
        tomcat) rm -rf /opt/tomcat
                rm -f /etc/systemd/system/tomcat.service /etc/profile.d/tomcat.sh
                systemctl daemon-reload
                userdel tomcat 2>/dev/null || true ;;
    esac
    mensaje ok "${nombre} desinstalado correctamente."
    sleep 2
}

menu_acciones_servicio() {
    local servicio="$1" nombre="$2"
    while true; do
        clear
        local estado puerto
        estado=$(systemctl is-active "$servicio" 2>/dev/null)
        puerto=$(obtener_puerto_servicio "$servicio")
        echo ""
        echo "  ================================================"
        echo "   $nombre"
        echo "  ================================================"
        echo ""
        echo "  Estado  : $(estado_color "$servicio")"
        echo "  Puerto  : $puerto"
        echo ""
        echo "  ------------------------------------------------"
        if [[ "$estado" == "active" ]]; then
            echo "  [1] Detener"
            echo "  [2] Reiniciar"
        else
            echo "  [1] Iniciar"
        fi
        echo "  [3] Desinstalar"
        echo "  [0] Volver"
        echo ""
        read -rp "  Seleccione: " opcion
        case "$opcion" in
            1) if [[ "$estado" == "active" ]]; then
                   systemctl stop "$servicio"
               else
                   systemctl start "$servicio"
               fi; sleep 2 ;;
            2) if [[ "$estado" == "active" ]]; then
                   systemctl restart "$servicio"; sleep 2
               else
                   mensaje error "El servicio no esta activo."; sleep 2
               fi ;;
            3) desinstalar_servicio "$servicio" "$nombre"; return ;;
            0) return ;;
            *) mensaje error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

gestionar_servicios_http() {
    while true; do
        clear
        detectar_servicios_http
        echo ""
        echo "  ================================================"
        echo "   Gestion de Servicios HTTP"
        echo "  ================================================"
        echo ""
        if [[ ${#HTTP_SERVICIOS[@]} -eq 0 ]]; then
            mensaje info "No hay servidores HTTP instalados."
            echo ""
            read -rp "  Presione Enter para volver..." _
            return
        fi
        printf "  %-4s  %-20s  %-12s  %s\n" "N" "Servicio" "Estado" "Puerto"
        echo "  ------------------------------------------------"
        local i=0
        for svc in "${HTTP_SERVICIOS[@]}"; do
            printf "  %2d)   %-20s  %-22b  %s\n" \
                "$((i+1))" "${HTTP_NOMBRES[$i]}" "$(estado_color "$svc")" "$(obtener_puerto_servicio "$svc")"
            (( i++ ))
        done
        echo ""
        echo "  [0] Volver"
        echo ""
        read -rp "  Seleccione: " opcion
        if [[ "$opcion" == "0" ]]; then
            return
        elif [[ "$opcion" =~ ^[0-9]+$ ]] && (( opcion >= 1 && opcion <= ${#HTTP_SERVICIOS[@]} )); then
            menu_acciones_servicio "${HTTP_SERVICIOS[$((opcion-1))]}" "${HTTP_NOMBRES[$((opcion-1))]}"
        else
            mensaje error "Opcion invalida."; sleep 1
        fi
    done
}

_estado_servicio_http() {
    local servicio="$1"
    local nombre="$2"
    local paquete="$3"
    while true; do
        clear
        echo ""
        echo "  ================================================"
        echo "   Estado: ${nombre}"
        echo "  ================================================"
        echo ""
        if ! rpm -q "$paquete" &>/dev/null && \
           ! systemctl list-unit-files | grep -q "^${servicio}.service"; then
            mensaje error "${nombre} no esta instalado."
            echo ""
            read -rp "  Presione Enter para volver..." _
            return
        fi
        local estado puerto
        estado=$(systemctl is-active "$servicio" 2>/dev/null)
        puerto=$(obtener_puerto_servicio "$servicio")
        if [[ "$estado" == "active" ]]; then
            mensaje ok "Estado: ACTIVO"
        else
            mensaje error "Estado: DETENIDO"
        fi
        echo "  Puerto : ${puerto}"
        echo ""
        echo "  ------------------------------------------------"
        if [[ "$estado" == "active" ]]; then
            echo "  [1] Detener"
            echo "  [2] Reiniciar"
        else
            echo "  [1] Iniciar"
        fi
        echo "  [0] Volver"
        echo ""
        read -rp "  Seleccione: " opcion
        case $opcion in
            1) if [[ "$estado" == "active" ]]; then
                   systemctl stop "$servicio"
               else
                   systemctl start "$servicio"
               fi; sleep 2 ;;
            2) if [[ "$estado" == "active" ]]; then
                   systemctl restart "$servicio"; sleep 2
               else
                   mensaje error "El servicio no esta activo."; sleep 1
               fi ;;
            0) return ;;
            *) mensaje error "Opcion invalida."; sleep 1 ;;
        esac
    done
}

estado_apache() { _estado_servicio_http "httpd" "Apache" "httpd"; }
estado_nginx()  { _estado_servicio_http "nginx" "Nginx"  "nginx"; }
estado_tomcat() { _estado_servicio_http "tomcat" "Tomcat" "tomcat"; }