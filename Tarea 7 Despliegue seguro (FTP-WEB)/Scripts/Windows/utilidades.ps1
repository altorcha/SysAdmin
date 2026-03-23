# ============================================================
# utilidades.ps1
# Practica 7 - Utilidades del Sistema
# Windows Server 2019/2022 - PowerShell
# ============================================================

. "$PSScriptRoot\globals.ps1"
. "$PSScriptRoot\ui.ps1"

function Abrir-Puerto-Firewall {
    param([int]$Puerto, [string]$Nombre)
    Remove-NetFirewallRule -DisplayName $Nombre -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $Nombre -Direction Inbound -Protocol TCP -LocalPort $Puerto -Action Allow | Out-Null
    Write-Host "  Firewall: puerto $Puerto abierto." -ForegroundColor Gray
}

function Detectar-Puerto-Libre {
    param([int[]]$Sugeridos)
    foreach ($p in $Sugeridos) {
        $t = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
        if (-not $t.TcpTestSucceeded) { return $p }
    }
    return $Sugeridos[-1]
}

# ================================================================
# SECCION 2 - DEPENDENCIAS
# ================================================================

function Refrescar-PATH {
    # Refresca el PATH de la sesion actual para que los programas
    # recien instalados (Chocolatey, OpenSSL) sean encontrados
    # sin necesidad de cerrar y reabrir PowerShell
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    # Ruta especifica de Chocolatey por si acaso
    $chocoBin = "C:\ProgramData\chocolatey\bin"
    if ((Test-Path $chocoBin) -and ($env:Path -notlike "*$chocoBin*")) {
        $env:Path = "$chocoBin;$env:Path"
    }
}

function Instalar-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "  Chocolatey ya esta instalado." -ForegroundColor Green
        Registrar-Resumen -Servicio "Chocolatey" -Accion "Verificacion" -Estado "OK" -Detalle "Ya instalado"
        return $true
    }
    Write-Host "  Instalando Chocolatey..." -ForegroundColor Cyan
    Write-Host "  (Esto puede tardar varios minutos segun la velocidad de internet)" -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Refrescar-PATH
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "  Chocolatey instalado correctamente." -ForegroundColor Green
            Registrar-Resumen -Servicio "Chocolatey" -Accion "Instalacion" -Estado "OK"
            return $true
        }
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "  ERROR: No se pudo instalar Chocolatey." -ForegroundColor Red
    Registrar-Resumen -Servicio "Chocolatey" -Accion "Instalacion" -Estado "ERROR"
    return $false
}

function Instalar-OpenSSL {
    if (Get-Command openssl -ErrorAction SilentlyContinue) {
        Write-Host "  OpenSSL ya esta instalado." -ForegroundColor Green
        Registrar-Resumen -Servicio "OpenSSL" -Accion "Verificacion" -Estado "OK" -Detalle "Ya instalado"
        return $true
    }
    Refrescar-PATH
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "  ERROR: Chocolatey no disponible. Instale Chocolatey primero (opcion 1)." -ForegroundColor Red
        return $false
    }
    Write-Host "  Instalando OpenSSL via Chocolatey..." -ForegroundColor Cyan
    Write-Host "  (Esto puede tardar varios minutos)" -ForegroundColor Yellow
    choco install openssl -y --no-progress 2>&1 | Out-Null
    Refrescar-PATH
    if (Get-Command openssl -ErrorAction SilentlyContinue) {
        Write-Host "  OpenSSL instalado correctamente." -ForegroundColor Green
        Registrar-Resumen -Servicio "OpenSSL" -Accion "Instalacion" -Estado "OK"
        return $true
    }
    Write-Host "  ERROR: No se pudo instalar OpenSSL." -ForegroundColor Red
    Registrar-Resumen -Servicio "OpenSSL" -Accion "Instalacion" -Estado "ERROR"
    return $false
}

function Menu-Dependencias {
    Escribir-Titulo "INSTALACION DE DEPENDENCIAS"
    Write-Host "  Chocolatey: necesario para instalar Apache via WEB."
    Write-Host "  OpenSSL   : necesario para activar SSL en Apache y Nginx."
    Write-Host "  Nota: Si la conexion es lenta esta operacion puede tardar varios minutos."
    Write-Host ""
    Write-Host "  1) Instalar Chocolatey"
    Write-Host "  2) Instalar OpenSSL  (requiere Chocolatey)"
    Write-Host "  3) Instalar ambos"
    Write-Host "  0) Volver"
    Write-Host ""
    $op = Leer-Opcion -Prompt "Seleccione" -Validas @("0","1","2","3")
    switch ($op) {
        "1" { Instalar-Chocolatey }
        "2" { Instalar-OpenSSL }
        "3" { Instalar-Chocolatey; Instalar-OpenSSL }
    }
}

# ================================================================
# SECCION 3 - REPOSITORIO FTP
# ================================================================

