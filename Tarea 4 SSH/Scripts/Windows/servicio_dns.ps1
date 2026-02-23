#========================================================================
#   Tarea 3: Automatización del Servidor DNS
#   Autor: Alberto Torres Chaparro
#   Descripción: Este script automatiza la instalación y configuración 
#   del servicio DNS en Windows Server 2022.
#========================================================================
. .\servicio_dhcp.ps1
function Estado-DNS {

    while ($true) {

        Clear-Host
        Write-Host "----------------------------------------"
        Write-Host "        ESTADO DEL SERVICIO DNS"
        Write-Host "----------------------------------------"

        # Verificar si el Rol DNS esta instalado
        $dnsInstalled = Get-WindowsFeature -Name DNS

        if ($dnsInstalled.InstallState -ne "Installed") {
            Write-Host "[!] El Rol 'DNS Server' NO esta instalado." -ForegroundColor Red
            Write-Host "Por favor, use la opcion de instalacion."
            Read-Host "Presione Enter para volver..."
            return
        }

        $service = Get-Service DNS

        if ($service.Status -eq "Running") {
            Write-Host "Estado Actual: " -NoNewline
            Write-Host "ACTIVO (Running)" -ForegroundColor Green
            Write-Host "----------------------------------------"
            Write-Host " [1] Detener el servicio"
            Write-Host " [2] Reiniciar el servicio"
            Write-Host " [3] Volver al menu principal"
        }
        else {
            Write-Host "Estado Actual: " -NoNewline
            Write-Host "DETENIDO (Stopped)" -ForegroundColor Red
            Write-Host "----------------------------------------"
            Write-Host " [1] Iniciar el servicio"
            Write-Host " [3] Volver al menu principal"
        }

        Write-Host "----------------------------------------"
        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {

            "1" {
                if ($service.Status -eq "Running") {
                    Write-Host "Deteniendo servicio DNS..." -ForegroundColor Yellow
                    Stop-Service DNS -Force
                }
                else {
                    Write-Host "Iniciando servicio DNS..." -ForegroundColor Green
                    Start-Service DNS
                }
                Start-Sleep -Seconds 2
            }

            "2" {
                if ($service.Status -eq "Running") {
                    Write-Host "Reiniciando servicio DNS..." -ForegroundColor Green
                    Restart-Service DNS -Force
                    Start-Sleep -Seconds 2
                }
            }

            "3" { return }

            Default {
                Write-Host "Opcion no valida." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    }
}


function Instalar-DNS {

    Clear-Host

    if ((Get-WindowsFeature -Name DNS).Installed) {
        Write-Host "DNS ya está instalado." -ForegroundColor Yellow
        Pause
        return
    }

    Write-Host "Instalando servicio DNS..."
    Install-WindowsFeature -Name DNS -IncludeManagementTools

    if ((Get-WindowsFeature -Name DNS).Installed) {

        # Iniciar servicio DNS
        Start-Service DNS

        # Cambiar red interna a Private automáticamente
        Set-NetConnectionProfile `
            -InterfaceAlias "Ethernet 2" `
            -NetworkCategory Private `
            -ErrorAction SilentlyContinue

        # Permitir tráfico DNS en firewall
        Enable-NetFirewallRule `
            -DisplayGroup "DNS Server" `
            -ErrorAction SilentlyContinue

        # Habilitar regla oficial de ICMPv4 (Ping)
        Enable-NetFirewallRule `
            -Name FPS-ICMP4-ERQ-In `
            -ErrorAction SilentlyContinue

        Write-Host "Instalacion completada y firewall configurado correctamente." -ForegroundColor Green
    }
    else {
        Write-Host "Error en instalación." -ForegroundColor Red
    }

    Pause
}

function Nuevo-Dominio {

    Clear-Host

    # ==============================
    # 1. Solicitar nombre de dominio
    # ==============================
    $dominio = Read-Host "Ingrese el nombre del dominio"

    if ([string]::IsNullOrWhiteSpace($dominio)) {
        Write-Host "Dominio invalido." -ForegroundColor Red
        Pause
        return
    }

    # ==============================
    # 2. Validar si ya existe el dominio
    # ==============================
    if (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue) {
        Write-Host "El dominio ya existe." -ForegroundColor Yellow
        Pause
        return
    }

    # ==============================
    # 3. Solicitar la dirección del dominio
    # ==============================
    do {
        $ipServidor = Read-Host "Ingrese la direccion IP que se asociara al dominio"

        $valida = -not [string]::IsNullOrWhiteSpace($ipServidor) -and (Validar-IP $ipServidor)

        if (-not $valida) {
            Write-Host "Debe ingresar una direccion IP valida." -ForegroundColor Red
        }

    } until ($valida)

    # ==============================
    # 4. Crear zona DNS
    # ==============================
    try {

        Write-Host "Creando zona DNS..."

        Add-DnsServerPrimaryZone `
            -Name $dominio `
            -ZoneFile "$dominio.dns" `
            -ErrorAction Stop

        # Registro A raiz (@)
        Add-DnsServerResourceRecordA `
            -ZoneName $dominio `
            -Name "@" `
            -IPv4Address $ipServidor `
            -ErrorAction Stop

        # Registro A www
        Add-DnsServerResourceRecordA `
            -ZoneName $dominio `
            -Name "www" `
            -IPv4Address $ipServidor `
            -ErrorAction Stop

        Write-Host "Dominio creado correctamente." -ForegroundColor Green
        Write-Host "IP asociada: $ipServidor"

    }
    catch {
        Write-Host "Error al crear el dominio: $($_.Exception.Message)" -ForegroundColor Red
    }

    Pause
}

function Borrar-Dominio {

    $dominio = Read-Host "Ingrese el dominio a eliminar"

    if (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $dominio -Force
        Write-Host "Dominio eliminado." -ForegroundColor Green
    }
    else {
        Write-Host "Dominio no existe." -ForegroundColor Red
    }

    Pause
}

function Consultar-Dominio {

    Clear-Host

    $zonas = Get-DnsServerZone | Where-Object { $_.ZoneType -eq "Primary" }

    if ($zonas.Count -eq 0) {
        Write-Host "No existen dominios configurados."
        Pause
        return
    }

    Write-Host "Dominios disponibles:"
    $i = 1
    foreach ($zona in $zonas) {
        Write-Host "$i) $($zona.ZoneName)"
        $i++
    }

    $seleccion = Read-Host "Seleccione numero"
    $dominio = $zonas[$seleccion - 1].ZoneName

    Write-Host ""
    Write-Host "Dominio seleccionado: $dominio"
    Write-Host "-----------------------------------"

    $registro = Get-DnsServerResourceRecord -ZoneName $dominio -RRType A |
                Where-Object { $_.HostName -eq "@" }

    if ($registro) {
        Write-Host "IP Asociada: $($registro.RecordData.IPv4Address)"
    }
    else {
        Write-Host "No se encontro registro A."
    }

    Pause
}

# ================= MENU =================
function Menu-DNS(){
    while ($true) {

    Clear-Host
    Write-Host "======================================="
    Write-Host "          SERVICIO DNS"
    Write-Host "======================================="
    Write-Host "1) Estado del servicio DNS"
    Write-Host "2) Instalar el servicio DNS"
    Write-Host "3) Nuevo Dominio"
    Write-Host "4) Borrar Dominio"
    Write-Host "5) Consultar Dominio"
    Write-Host "6) Salir"
    Write-Host "======================================="

    $opcion = Read-Host "Selecciona una opcion"

    switch ($opcion) {
        "1" { Estado-DNS }
        "2" { Instalar-DNS }
        "3" { Nuevo-Dominio }
        "4" { Borrar-Dominio }
        "5" { Consultar-Dominio }
        "6" { return }
        default { Write-Host "Opcion invalida"; Start-Sleep 1 }
    }
}
}

