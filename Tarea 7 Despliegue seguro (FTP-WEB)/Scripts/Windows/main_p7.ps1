# Verificar Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecutar este script como Administrador." -ForegroundColor Red
    exit 1
}

# ── Cargar modulos en orden de dependencia ───────────────────────
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$modulos = @(
    "globals.ps1",
    "ui.ps1",
    "utilidades.ps1",
    "repositorio.ps1",
    "web_servidores.ps1",
    "ssl.ps1",
    "ftp_server.ps1"
)

foreach ($mod in $modulos) {
    $ruta = "$scriptDir\$mod"
    if (-not (Test-Path $ruta)) {
        Write-Host "ERROR: No se encuentra $mod en $scriptDir" -ForegroundColor Red
        exit 1
    }
    . $ruta
}

# ================================================================
# SUBMENU 1 - FTP
# Agrupa: servidor FTP local, repositorio y FTPS
# ================================================================
function Menu-FTP {
    while ($true) {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "  [1] FTP - Servidor y Repositorio                            " -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  -- SERVIDOR FTP LOCAL --" -ForegroundColor Yellow
        Write-Host "  1) Administrar servidor FTP"
        Write-Host "     (Instalar, configurar, usuarios, grupos)"
        Write-Host ""
        Write-Host "  -- REPOSITORIO --" -ForegroundColor Yellow
        Write-Host "  2) Preparar repositorio FTP"
        Write-Host "     (Descargar ZIPs de Apache/Nginx, generar .sha256)"
        Write-Host ""
        Write-Host "  -- SEGURIDAD --" -ForegroundColor Yellow
        Write-Host "  3) Activar FTPS en IIS-FTP"
        Write-Host ""
        Write-Host "  0) Volver al menu principal"
        Write-Host ""

        $op = Leer-Opcion -Prompt "Seleccione opcion" -Validas @("0","1","2","3")

        switch ($op) {
            "1" { Menu-Administrar-FTP }
            "2" { Preparar-Repositorio-FTP }
            "3" { Activar-FTPS-IIS }
            "0" { return }
        }
    }
}

# ================================================================
# SUBMENU 2 - SERVIDORES WEB
# Agrupa: dependencias e instalacion de IIS / Apache / Nginx
# ================================================================
function Menu-ServidoresWeb {
    while ($true) {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "  [2] Servidores Web                                           " -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  -- DEPENDENCIAS --" -ForegroundColor Yellow
        Write-Host "  1) Instalar dependencias (Chocolatey / OpenSSL)"
        Write-Host ""
        Write-Host "  -- INSTALACION (web directa o desde repositorio FTP) --" -ForegroundColor Yellow
        Write-Host "  2) Instalar IIS"
        Write-Host "  3) Instalar Apache"
        Write-Host "  4) Instalar Nginx"
        Write-Host ""
        Write-Host "  0) Volver al menu principal"
        Write-Host ""

        $op = Leer-Opcion -Prompt "Seleccione opcion" -Validas @("0","1","2","3","4")

        switch ($op) {
            "1" { Menu-Dependencias }
            "2" { Flujo-Instalar-Servicio -Servicio "IIS" }
            "3" { Flujo-Instalar-Servicio -Servicio "Apache" }
            "4" { Flujo-Instalar-Servicio -Servicio "Nginx" }
            "0" { return }
        }
    }
}

# ================================================================
# SUBMENU 3 - SSL / TLS
# Agrupa: activacion de HTTPS en IIS, Apache y Nginx
# ================================================================
function Menu-SSL {
    while ($true) {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "  [3] SSL / TLS - Activar HTTPS                               " -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1) Activar SSL en IIS    (HTTPS puerto personalizado + binding)"
        Write-Host "  2) Activar SSL en Apache (HTTPS puerto personalizado + redireccion)"
        Write-Host "  3) Activar SSL en Nginx  (HTTPS puerto personalizado + redireccion)"
        Write-Host ""
        Write-Host "  0) Volver al menu principal"
        Write-Host ""

        $op = Leer-Opcion -Prompt "Seleccione opcion" -Validas @("0","1","2","3")

        switch ($op) {
            "1" { Activar-SSL-IIS }
            "2" { Activar-SSL-Apache }
            "3" { Activar-SSL-Nginx }
            "0" { return }
        }
    }
}

# ================================================================
# SUBMENU 4 - UTILIDADES
# Agrupa: estado, gestion de servicios y resumen final
# ================================================================
function Menu-Utilidades {
    while ($true) {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "  [4] Utilidades                                               " -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1) Ver estado de todos los servicios"
        Write-Host "  2) Iniciar / Detener servicios"
        Write-Host "  3) Mostrar resumen final (evidencias)"
        Write-Host ""
        Write-Host "  0) Volver al menu principal"
        Write-Host ""

        $op = Leer-Opcion -Prompt "Seleccione opcion" -Validas @("0","1","2","3")

        switch ($op) {
            "1" { Ver-Estado-Servicios }
            "2" { Gestionar-Servicios-HTTP }
            "3" { Mostrar-Resumen-Final }
            "0" { return }
        }
    }
}

# ================================================================
# MENU PRINCIPAL
# ================================================================
while ($true) {

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  PRACTICA 7 - Despliegue Seguro e Instalacion Hibrida         " -ForegroundColor Cyan
    Write-Host "  Windows Server 2019/2022 | FTP + HTTP + SSL/TLS              " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) FTP              - Servidor, repositorio y FTPS" -ForegroundColor White
    Write-Host "  2) Servidores Web   - Dependencias, IIS, Apache, Nginx" -ForegroundColor White
    Write-Host "  3) SSL / TLS        - Activar HTTPS en IIS, Apache, Nginx" -ForegroundColor White
    Write-Host "  4) Utilidades       - Estado, gestionar servicios, resumen" -ForegroundColor White
    Write-Host ""
    Write-Host "  0) Salir" -ForegroundColor DarkGray
    Write-Host ""

    $op = Leer-Opcion -Prompt "Seleccione opcion" -Validas @("0","1","2","3","4")

    switch ($op) {
        "1" { Menu-FTP }
        "2" { Menu-ServidoresWeb }
        "3" { Menu-SSL }
        "4" { Menu-Utilidades }
        "0" {
            Write-Host ""
            Write-Host "Generando resumen antes de salir..." -ForegroundColor Cyan
            Mostrar-Resumen-Final
            Write-Host "Saliendo." -ForegroundColor Yellow
            exit 0
        }
    }
}