#!/bin/bash
# ============================================================
# unir_oracle_linux10.sh - Une Oracle Linux 10 al dominio
# Dominio  : practica.local
# Servidor : 192.168.10.11
#
# Uso:
#   sudo bash unir_oracle_linux10.sh
# ============================================================

set -u

ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
CYAN='\033[0;36m'
BLANCO='\033[1;37m'
RESET='\033[0m'

DOMINIO="practica.local"
DOMINIO_UPPER="PRACTICA.LOCAL"
DOMINIO_NETBIOS="PRACTICA"
SERVIDOR_IP="192.168.10.11"
DNS_PRIMARIO="192.168.10.11"
ADMIN_JOIN_DEFAULT="Administrator"

if [ "$EUID" -ne 0 ]; then
    echo ""
    echo -e "  ${ROJO}[ERROR] Este script debe ejecutarse como root.${RESET}"
    echo -e "  Usa: sudo bash unir_oracle_linux10.sh"
    echo ""
    exit 1
fi

if ! command -v dnf >/dev/null 2>&1; then
    echo ""
    echo -e "  ${ROJO}[ERROR] Este script esta pensado para Oracle Linux / RHEL-like con dnf.${RESET}"
    echo ""
    exit 1
fi

clear
echo ""
echo -e "  ${CYAN}+===================================================+${RESET}"
echo -e "  ${CYAN}|    UNIR ORACLE LINUX 10 AL DOMINIO                |${RESET}"
echo -e "  ${CYAN}|    practica.local | 192.168.10.11                |${RESET}"
echo -e "  ${CYAN}+===================================================+${RESET}"
echo ""

echo -e "  ${AMARILLO}Verificando conectividad con el servidor AD...${RESET}"
if ! ping -c 2 -W 2 "$SERVIDOR_IP" >/dev/null 2>&1; then
    echo -e "  ${ROJO}[ERROR] No se puede contactar al servidor $SERVIDOR_IP${RESET}"
    echo ""
    exit 1
fi
echo -e "  ${VERDE}[OK] Servidor alcanzable.${RESET}"

echo ""
echo -e "  ${AMARILLO}Verificando estado actual del dominio...${RESET}"
if realm list 2>/dev/null | grep -qi "^domain-name: $DOMINIO$"; then
    echo -e "  ${AMARILLO}[INFO] Esta maquina ya esta unida al dominio $DOMINIO.${RESET}"
    echo ""
    exit 0
fi

echo ""
echo -e "  ${AMARILLO}Instalando dependencias para Oracle Linux 10...${RESET}"
PAQUETES=(
    realmd
    sssd
    sssd-tools
    adcli
    oddjob
    oddjob-mkhomedir
    samba-common-tools
    krb5-workstation
    chrony
    authselect
)

dnf install -y "${PAQUETES[@]}"
if [ $? -ne 0 ]; then
    echo -e "  ${ROJO}[ERROR] No se pudieron instalar las dependencias.${RESET}"
    exit 1
fi
echo -e "  ${VERDE}[OK] Dependencias instaladas.${RESET}"

echo ""
echo -e "  ${AMARILLO}Configurando DNS hacia el controlador de dominio...${RESET}"

if command -v nmcli >/dev/null 2>&1; then
    CONEXION_ACTIVA=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$2 != "" {print $1; exit}')
    if [ -n "${CONEXION_ACTIVA:-}" ]; then
        nmcli connection modify "$CONEXION_ACTIVA" ipv4.dns "$DNS_PRIMARIO"
        nmcli connection modify "$CONEXION_ACTIVA" ipv4.ignore-auto-dns yes
        nmcli connection modify "$CONEXION_ACTIVA" ipv4.dns-search "$DOMINIO"
        nmcli connection up "$CONEXION_ACTIVA" >/dev/null 2>&1 || true
        echo -e "  ${VERDE}[OK] DNS configurado por NetworkManager en: $CONEXION_ACTIVA${RESET}"
    else
        echo -e "  ${AMARILLO}[AVISO] No se detecto conexion activa en NetworkManager. Se usara /etc/resolv.conf.${RESET}"
        cat > /etc/resolv.conf <<EOF
search $DOMINIO
nameserver $DNS_PRIMARIO
EOF
    fi
else
    cat > /etc/resolv.conf <<EOF
search $DOMINIO
nameserver $DNS_PRIMARIO
EOF
    echo -e "  ${VERDE}[OK] /etc/resolv.conf actualizado.${RESET}"
fi

echo ""
echo -e "  ${AMARILLO}Sincronizando hora...${RESET}"
systemctl enable --now chronyd >/dev/null 2>&1 || true
chronyc -a makestep >/dev/null 2>&1 || true
echo -e "  ${VERDE}[OK] Hora sincronizada o servicio chronyd iniciado.${RESET}"

echo ""
echo -e "  ${AMARILLO}Verificando resolucion DNS del dominio y sus registros SRV...${RESET}"

if command -v host >/dev/null 2>&1; then
    if ! host -t SRV "_ldap._tcp.$DOMINIO" >/dev/null 2>&1; then
        echo -e "  ${ROJO}[ERROR] No se pudieron resolver los registros SRV LDAP de $DOMINIO${RESET}"
        echo -e "  ${AMARILLO}Pruebas manuales:${RESET}"
        echo -e "    host -t SRV _ldap._tcp.$DOMINIO"
        echo -e "    host -t SRV _kerberos._tcp.$DOMINIO"
        echo -e "    realm discover $DOMINIO"
        exit 1
    fi
else
    if ! realm discover "$DOMINIO" >/dev/null 2>&1; then
        echo -e "  ${ROJO}[ERROR] No se pudo descubrir el dominio despues de configurar DNS.${RESET}"
        echo -e "  ${AMARILLO}Prueba manual:${RESET} realm discover $DOMINIO"
        exit 1
    fi
fi

echo -e "  ${VERDE}[OK] DNS y registros SRV del dominio disponibles.${RESET}"

echo ""
echo -e "  ${AMARILLO}Descubriendo el dominio...${RESET}"
if ! realm discover "$DOMINIO" >/tmp/realm_discover.out 2>&1; then
    echo -e "  ${ROJO}[ERROR] realm discover fallo.${RESET}"
    cat /tmp/realm_discover.out
    exit 1
fi
echo -e "  ${VERDE}[OK] Dominio descubierto correctamente.${RESET}"

echo ""
echo -e "  ${BLANCO}Se unira esta maquina al dominio $DOMINIO.${RESET}"
echo -e "  ${BLANCO}Se te pedira la contrasena de $ADMIN_JOIN_DEFAULT o de otra cuenta con permisos para unir equipos.${RESET}"
read -r -p "  Deseas continuar? (s/n): " CONFIRMAR
if [ "$CONFIRMAR" != "s" ] && [ "$CONFIRMAR" != "S" ]; then
    echo -e "  ${AMARILLO}Operacion cancelada.${RESET}"
    exit 0
fi

read -r -p "  Usuario para unir al dominio [$ADMIN_JOIN_DEFAULT]: " ADMIN_JOIN
ADMIN_JOIN=${ADMIN_JOIN:-$ADMIN_JOIN_DEFAULT}

echo ""
echo -e "  ${AMARILLO}Uniendo Oracle Linux 10 al dominio...${RESET}"
realm join "$DOMINIO" --user="$ADMIN_JOIN" --computer-ou=""
if [ $? -ne 0 ]; then
    echo -e "  ${ROJO}[ERROR] No se pudo unir al dominio.${RESET}"
    exit 1
fi
echo -e "  ${VERDE}[OK] Maquina unida al dominio $DOMINIO.${RESET}"

echo ""
echo -e "  ${AMARILLO}Configurando SSSD...${RESET}"
cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = $DOMINIO
config_file_version = 2
services = nss, pam, sudo

[domain/$DOMINIO]
ad_domain = $DOMINIO
krb5_realm = $DOMINIO_UPPER
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = False
fallback_homedir = /home/%u
access_provider = ad
EOF

chmod 600 /etc/sssd/sssd.conf
restorecon /etc/sssd/sssd.conf >/dev/null 2>&1 || true
echo -e "  ${VERDE}[OK] /etc/sssd/sssd.conf actualizado.${RESET}"

echo ""
echo -e "  ${AMARILLO}Habilitando creacion automatica de home...${RESET}"
authselect select sssd with-mkhomedir --force >/dev/null 2>&1 || true
echo -e "  ${VERDE}[OK] authselect configurado con with-mkhomedir.${RESET}"

echo ""
echo -e "  ${AMARILLO}Configurando sudo para Domain Admins...${RESET}"
mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/ad-domain-admins <<EOF
# Generado por unir_oracle_linux10.sh
%domain\ admins@$DOMINIO ALL=(ALL) ALL
EOF
chmod 440 /etc/sudoers.d/ad-domain-admins
echo -e "  ${VERDE}[OK] sudo para Domain Admins habilitado.${RESET}"

echo ""
echo -e "  ${AMARILLO}Reiniciando y habilitando servicios...${RESET}"
systemctl enable --now sssd >/dev/null 2>&1
systemctl enable --now oddjobd >/dev/null 2>&1
systemctl restart sssd
systemctl restart oddjobd
echo -e "  ${VERDE}[OK] Servicios activos.${RESET}"

echo ""
echo -e "  ${AMARILLO}Verificacion final...${RESET}"
realm list
id "Administrator@$DOMINIO" >/dev/null 2>&1 || true

echo ""
echo -e "  ${CYAN}+===================================================+${RESET}"
echo -e "  ${CYAN}| Union al dominio completada                        |${RESET}"
echo -e "  ${CYAN}+---------------------------------------------------+${RESET}"
echo -e "  ${VERDE}| Dominio   : $DOMINIO${RESET}"
echo -e "  ${VERDE}| DNS       : $DNS_PRIMARIO${RESET}"
echo -e "  ${VERDE}| Home dir  : /home/%u${RESET}"
echo -e "  ${VERDE}| Login     : usuario o usuario@$DOMINIO${RESET}"
echo -e "  ${CYAN}+===================================================+${RESET}"
echo ""
echo -e "  ${AMARILLO}Pruebas sugeridas:${RESET}"
echo -e "  ${AMARILLO}  id Administrator@$DOMINIO${RESET}"
echo -e "  ${AMARILLO}  getent passwd Administrator@$DOMINIO${RESET}"
echo -e "  ${AMARILLO}  su - usuario_del_dominio${RESET}"
echo ""
