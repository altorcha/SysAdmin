#!/bin/bash
# ==========================================
# LIBRERÍA DE COLORES PARA BASH
# ==========================================

# ---------- RESET ----------
RESET="\033[0m"

# ---------- ESTILOS ----------
NEGRITA="\033[1m"
SUBRAYADO="\033[4m"
PARPADEO="\033[5m"
INVERTIDO="\033[7m"

# ---------- COLORES TEXTO ----------
NEGRO="\033[30m"
ROJO="\033[31m"
VERDE="\033[32m"
AMARILLO="\033[33m"
AZUL="\033[34m"
MAGENTA="\033[35m"
CIAN="\033[36m"
BLANCO="\033[37m"

# ---------- COLORES BRILLANTES ----------
GRIS="\033[90m"
ROJO_CLARO="\033[91m"
VERDE_CLARO="\033[92m"
AMARILLO_CLARO="\033[93m"
AZUL_CLARO="\033[94m"
MAGENTA_CLARO="\033[95m"
CIAN_CLARO="\033[96m"
BLANCO_BRILLANTE="\033[97m"

# ---------- FONDOS ----------
FONDO_NEGRO="\033[40m"
FONDO_ROJO="\033[41m"
FONDO_VERDE="\033[42m"
FONDO_AMARILLO="\033[43m"
FONDO_AZUL="\033[44m"
FONDO_MAGENTA="\033[45m"
FONDO_CIAN="\033[46m"
FONDO_BLANCO="\033[47m"

# ==========================================
# FUNCIONES BÁSICAS
# ==========================================

color_texto() {
    local color="$1"
    local texto="$2"
    echo -e "${color}${texto}${RESET}"
}

color_fondo() {
    local fondo="$1"
    local texto="$2"
    echo -e "${fondo}${texto}${RESET}"
}

estilo_texto() {
    local estilo="$1"
    local texto="$2"
    echo -e "${estilo}${texto}${RESET}"
}

color_personalizado() {
    local codigo="$1"
    local texto="$2"
    echo -e "\033[${codigo}m${texto}${RESET}"
}

# ==========================================
# FUNCIONES TIPO LOG (IDEAL PARA SCRIPTS)
# ==========================================

log_info() {
    echo -e "${AZUL}[INFO]${RESET} $1"
}

log_ok() {
    echo -e "${VERDE}[OK]${RESET} $1"
}

log_warning() {
    echo -e "${AMARILLO}[WARNING]${RESET} $1"
}

log_error() {
    echo -e "${ROJO}[ERROR]${RESET} $1"
}

log_debug() {
    echo -e "${MAGENTA}[DEBUG]${RESET} $1"
}

# ==========================================
# FUNCIONES AVANZADAS
# ==========================================

titulo() {
    echo -e "\n${NEGRITA}${AZUL}==== $1 ====${RESET}\n"
}

subtitulo() {
    echo -e "${NEGRITA}${CIAN}-- $1 --${RESET}"
}

# Barra separadora
separador() {
    echo -e "${GRIS}----------------------------------------${RESET}"
}

# ==========================================
# 256 COLORES
# ==========================================

color_256() {
    local codigo="$1"
    local texto="$2"
    echo -e "\033[38;5;${codigo}m${texto}${RESET}"
}

fondo_256() {
    local codigo="$1"
    local texto="$2"
    echo -e "\033[48;5;${codigo}m${texto}${RESET}"
}