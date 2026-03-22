validar_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${NEGRITA}${FONDO_ROJO}${BLANCO_BRILLANTE} ERROR *** Este script debe ejecutarse como root ${RESET}"
        exit 1
    fi
}

validar_ip() {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

validar_puerto() {
    local puerto="$1"
    local reservados=(22 25 53 443 3306 5432 6379 27017)

    if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
        echo -e "${ROJO_CLARO}Puerto inválido${RESET}"
        return 1
    fi

    if (( puerto < 1 || puerto > 65535 )); then
        echo -e "${ROJO_CLARO}Puerto fuera de rango${RESET}"
        return 1
    fi

    for r in "${reservados[@]}"; do
        (( puerto == r )) && {
            echo -e "${ROJO_CLARO}Puerto reservado${RESET}"
            return 1
        }
    done

    return 0
}

puerto_en_uso() {
    ss -tln | grep -q ":$1 " && return 0 || return 1
}