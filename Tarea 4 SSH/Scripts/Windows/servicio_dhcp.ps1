<#
    Tarea 3: Automatización del Servidor DNS
    Autor: Alberto Torres Chaparro
    Descripción: Este script automatiza la instalación y configuración 
#   del servicio DHCP en Windows Server 2022.
#>

# --- VERIFICAR PERMISOS DE ADMINISTRADOR ---
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Este script debe ejecutarse como Administrador."
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# --- FUNCIONES DE VALIDACION Y UTILIDADES ---

function Validar-IP {
    param ( [string]$IP )
    
    # 1. Validar formato basico IP
    $ipObj = $null
    if (![System.Net.IPAddress]::TryParse($IP, [ref]$ipObj)) { return $false }

    # 2. Desglosar octetos
    $octetos = $IP.Split('.')
    
    # 3. Validar IPs Reservadas Especificas
    if ($IP -eq "0.0.0.0") { Write-Host "Error: IP 0.0.0.0 no valida" -ForegroundColor Red; return $false }
    if ($IP.StartsWith("127.")) { Write-Host "Error: Localhost (127.x.x.x) no permitido" -ForegroundColor Red; return $false }

    # 4. Reglas generales de Red y Broadcast (.0 y .255)
    if ($octetos[3] -eq "0") { Write-Host "Error: IP de Red (termina en .0)" -ForegroundColor Red; return $false }
    if ($octetos[3] -eq "255") { Write-Host "Error: IP de Broadcast (termina en .255)" -ForegroundColor Red; return $false }

    return $true
}
# --- CONFIGURACION DE FIREWALL Y PERFIL DE RED ---
function Configurar-FirewallDHCP {

    param (
        [string]$InterfaceName
    )

    Write-Host "Configurando perfil de red y firewall..." -ForegroundColor Cyan

    try {
        # Cambiar perfil a Private (evita bloqueo en Public)
        Set-NetConnectionProfile -InterfaceAlias $InterfaceName -NetworkCategory Private -ErrorAction SilentlyContinue

        # Habilitar reglas del grupo DHCP Server
        Get-NetFirewallRule -DisplayGroup "DHCP Server" -ErrorAction SilentlyContinue | 
            Set-NetFirewallRule -Enabled True

        # Crear regla manual si no existe
        if (-not (Get-NetFirewallRule -DisplayName "DHCP UDP 67" -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule `
                -DisplayName "DHCP UDP 67" `
                -Direction Inbound `
                -Protocol UDP `
                -LocalPort 67 `
                -Action Allow `
                -Profile Any | Out-Null
        }

        Write-Host "[EXITO] Firewall y perfil configurados." -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] No se pudo configurar firewall o perfil." -ForegroundColor Red
    }
}
# --- 1. ESTADO DEL SERVICIO ---
function Estado-Servicio {
    while ($true) {
        Clear-Host
        Write-Host "----------------------------------------"
        Write-Host "        ESTADO DEL SERVICIO DHCP"
        Write-Host "----------------------------------------"

        # Verificar si el Rol DHCP esta instalado
        $dhcpInstalled = Get-WindowsFeature -Name DHCP
        if ($dhcpInstalled.InstallState -ne "Installed") {
            Write-Host "[!] El Rol 'DHCP Server' NO esta instalado." -ForegroundColor Red
            Write-Host "Por favor, use la opcion 2 para instalarlo."
            Read-Host "Presione Enter para volver..."
            return
        }

        $service = Get-Service DhcpServer
        
        if ($service.Status -eq "Running") {
            Write-Host "Estado Actual: " -NoNewline
            Write-Host "ACTIVO (Running)" -ForegroundColor Green
            Write-Host "----------------------------------------"
            Write-Host " [1] Detener el servicio"
            Write-Host " [2] Reiniciar y Limpiar Concesiones (Leases)"
            Write-Host " [3] Volver al menu principal"
        } else {
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
                    Write-Host "Deteniendo servicio DHCP..." -ForegroundColor Yellow
                    Stop-Service DhcpServer -Force
                } else {
                    Write-Host "Iniciando servicio DHCP..." -ForegroundColor Green
                    Start-Service DhcpServer
                }
                Start-Sleep -Seconds 2
            }
            "2" {
                if ($service.Status -eq "Running") {
                    Write-Host "Reiniciando DHCP y purgando concesiones..." -ForegroundColor Green
                    
                    try {
                        $scopes = Get-DhcpServerv4Scope
                        foreach ($scope in $scopes) {
                            Get-DhcpServerv4Lease -ScopeId $scope.ScopeId | Remove-DhcpServerv4Lease -Force
                            Write-Host " > Historial de IPs eliminado para el ambito $($scope.ScopeId)" -ForegroundColor Cyan
                        }
                    } catch {
                        Write-Host " > No hay ambitos activos o error al limpiar." -ForegroundColor DarkGray
                    }

                    Restart-Service DhcpServer -Force
                    Write-Host " > Servicio reiniciado correctamente."
                    Start-Sleep -Seconds 2
                } else {
                    Write-Host "El servicio no esta activo."
                }
            }
            "3" { return }
            Default { Write-Host "Opcion no valida." }
        }
    }
}

# --- 2. INSTALACION ---
function Instalar-Servicio {
    Write-Host "----------------------------------------"
    Write-Host "        INSTALACION DEL SERVICIO"
    Write-Host "----------------------------------------"

    $check = Get-WindowsFeature -Name DHCP
    if ($check.InstallState -eq "Installed") {
        Write-Host "El servicio ya esta instalado."
        Read-Host "Presione Enter..."
        return
    }

    Write-Host "Iniciando instalacion del Rol DHCP... Por favor espere."
    
    try {
        Install-WindowsFeature -Name DHCP -IncludeManagementTools
        # Autorizar en AD (paso necesario en entornos Windows, aunque opcional en Standalone)
        Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -ErrorAction SilentlyContinue 
        Write-Host "[EXITO] Instalacion completada correctamente." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] La instalacion fallo." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    Read-Host "Presione Enter..."
}

# --- 4. CONFIGURACION DHCP ---
function Configurar-Servicio {
    Clear-Host
    Write-Host "========================================"
    Write-Host "   CONFIGURACION DE DHCP (WINDOWS)"
    Write-Host "========================================"

    if ((Get-WindowsFeature DHCP).InstallState -ne "Installed") {
        Write-Host "Error: Instale el servicio primero."
        Read-Host "Enter..."
        return
    }

    Write-Host "Interfaces disponibles:"
    $adapters = Get-NetAdapter | Where-Object Status -eq "Up"
    $adapters | Select-Object Name, InterfaceDescription, MacAddress | Format-Table -AutoSize
    Write-Host "----------------------------------------"
    
    # 1. Seleccionar Interfaz
    while ($true) {
        $ifaceName = Read-Host "1. Nombre exacto del Adaptador de red (ej. Ethernet)"
        if (Get-NetAdapter -Name $ifaceName -ErrorAction SilentlyContinue) { break }
        Write-Host " [!] La interfaz no existe." -ForegroundColor Red
    }

    $scopeName = Read-Host "2. Nombre del Ambito"

    # 3. Rango Inicial (IP del Servidor)
    while ($true) {
        $ipInicio = Read-Host "3. Rango inicial (IP Servidor)"
        if (Validar-IP $ipInicio) { break }
        Write-Host " [!] IP invalida" -ForegroundColor Red
    }

    # Calculos de red
    $ipObj = [System.Net.IPAddress]::Parse($ipInicio)
    $bytes = $ipObj.GetAddressBytes()
    # Aumentar el ultimo octeto en 1 para el inicio del pool
    $poolStartLastOctet = [int]$bytes[3] + 1
    $poolStart = "{0}.{1}.{2}.{3}" -f $bytes[0], $bytes[1], $bytes[2], $poolStartLastOctet
    $prefix = "{0}.{1}.{2}" -f $bytes[0], $bytes[1], $bytes[2]
    
    $subnetID = "$($prefix).0"

    # 4. Rango Final
    while ($true) {
        $ipFin = Read-Host "4. Rango final ($prefix.X)"
        if (-not (Validar-IP $ipFin)) { continue }
        
        if (-not $ipFin.StartsWith($prefix)) {
            Write-Host " [!] La IP debe estar en el segmento $prefix.x" -ForegroundColor Red
            continue
        }
        
        # Validar que fin > inicio
        $finLast = [int]$ipFin.Split('.')[3]
        if ($poolStartLastOctet -le $finLast) { break }
        Write-Host " [!] El rango final debe ser mayor a $poolStart" -ForegroundColor Red
    }

    # 5. Gateway
    while ($true) {
        $gateway = Read-Host "5. Gateway (Enter para omitir)"
        # Permitimos vacio (break)
        if ([string]::IsNullOrWhiteSpace($gateway)) { break }
        
        if (Validar-IP $gateway) {
            if ($gateway.StartsWith($prefix)) { break }
            Write-Host " [!] El Gateway debe pertenecer a la red $prefix.x" -ForegroundColor Red
        } else {
             Write-Host " [!] IP invalida" -ForegroundColor Red
        }
    }

    # 6. DNS
    $dns = Read-Host "6. DNS (Enter para omitir)"
    if (-not [string]::IsNullOrWhiteSpace($dns)) {
        if (-not (Validar-IP $dns)) { $dns = $null; Write-Host "DNS invalido, omitiendo." }
    }

    # 7. Tiempo de concesion
    while ($true) {
        $leaseTimeStr = Read-Host "7. Tiempo de concesion (segundos)"
        if ($leaseTimeStr -match "^\d+$") { break }
        Write-Host " [!] Debe ser un numero entero." -ForegroundColor Red
    }
    $leaseTimeSpan = New-TimeSpan -Seconds $leaseTimeStr

    # --- RESUMEN ---
    Clear-Host
    Write-Host "========================================"
    Write-Host "        RESUMEN DE CONFIGURACION"
    Write-Host "========================================"
    Write-Host "1- Adaptador:       $ifaceName"
    Write-Host "2- Ambito:          $scopeName"
    Write-Host "3- IP Servidor:     $ipInicio"
    Write-Host "4- Pool DHCP:       $poolStart - $ipFin"
    Write-Host "5- Gateway:         $($gateway)"
    Write-Host "6- DNS:             $($dns)"
    Write-Host "7- Concesion:       $leaseTimeStr segundos"
    Write-Host "========================================"
    $confirm = Read-Host "Confirmar configuracion (S/N)"

    if ($confirm -ne "s") { Write-Host "Cancelado."; return }

    # --- APLICACION DE CAMBIOS ---
    Write-Host "Configurando IP estatica en $ifaceName..." -ForegroundColor Cyan
    try {
        # Quitar IP anterior (si es dinamica o estatica vieja)
        Remove-NetIPAddress -InterfaceAlias $ifaceName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        
        # --- SOLUCION DEL ERROR ---
        # Validamos si $gateway tiene texto o esta vacio para ejecutar el comando correcto
        if ([string]::IsNullOrWhiteSpace($gateway)) {
            # Opcion A: Sin Gateway
            New-NetIPAddress -InterfaceAlias $ifaceName -IPAddress $ipInicio -PrefixLength 24 -Confirm:$false
        } else {
            # Opcion B: Con Gateway
            New-NetIPAddress -InterfaceAlias $ifaceName -IPAddress $ipInicio -PrefixLength 24 -DefaultGateway $gateway -Confirm:$false
        }

        if ($dns) { Set-DnsClientServerAddress -InterfaceAlias $ifaceName -ServerAddresses $dns }
    } catch {
        Write-Host "Nota: Error ajustando IP (quizas ya esta asignada), continuando..." -ForegroundColor Yellow
        Write-Host $_.Exception.Message
    }
    Start-Sleep -Seconds 2

    Write-Host "Configurando Servicio DHCP..." -ForegroundColor Cyan
    try {
        # Limpiar ambitos anteriores si existen
        Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue

        # Crear nuevo ambito
        Add-DhcpServerv4Scope -Name $scopeName -StartRange $poolStart -EndRange $ipFin -SubnetMask 255.255.255.0 -State Active -LeaseDuration $leaseTimeSpan

        # Configurar Opciones (Router = ID 3, DNS = ID 6)
        # Aquí verificamos de nuevo si $gateway existe antes de agregarlo como opción DHCP
        if (-not [string]::IsNullOrWhiteSpace($gateway)) { 
            Set-DhcpServerv4OptionValue -ScopeId $subnetID -OptionId 3 -Value $gateway 
        }
        
        if ($dns) { Set-DhcpServerv4OptionValue -ScopeId $subnetID -OptionId 6 -Value $dns -Force}
        # Asegurar binding DHCP a la IP configurada
        $serverIP = (Get-NetIPAddress -InterfaceAlias $ifaceName -AddressFamily IPv4).IPAddress
        Set-DhcpServerv4Binding -IPAddress $serverIP -BindingState $true -ErrorAction SilentlyContinue
        Restart-Service DhcpServer -Force
        Configurar-FirewallDHCP -InterfaceName $ifaceName
        Write-Host "[EXITO] Servicio configurado y activo." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Fallo la configuracion DHCP:" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    Read-Host "Presione Enter..."
}

# --- 5. MONITOREAR SERVICIO ---
function Monitorear-Servicio {
    while ($true) {
        Clear-Host
        Write-Host "=========================================================================="
        Write-Host "                  MONITOREAR SERVICIO DHCP (Windows)"
        Write-Host "=========================================================================="
        
        $service = Get-Service DhcpServer
        if ($service.Status -eq "Running") {
            Write-Host "Estado: ACTIVO" -ForegroundColor Green
        } else {
            Write-Host "Estado: INACTIVO" -ForegroundColor Red
        }

        Write-Host "--------------------------------------------------------------------------"
        Write-Host "Clientes Conectados:"
        Write-Host ("{0,-20} | {1,-20} | {2,-30}" -f 'DIRECCION IP', 'MAC ADDRESS', 'HOSTNAME')
        Write-Host "---------------------|----------------------|-----------------------------"

        try {
            # Se obtiene el ScopeId dinamicamente
            $scope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if ($scope) {
                $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
                if ($leases) {
                    foreach ($lease in $leases) {
                        Write-Host ("{0,-20} | {1,-20} | {2,-30}" -f $lease.IPAddress.IPAddressToString, $lease.ClientId, $lease.HostName)
                    }
                } else {
                    Write-Host "            Sin concesiones activas..." -ForegroundColor DarkGray
                }
            } else {
                 Write-Host "            No hay ambitos DHCP configurados." -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "Error leyendo base de datos (Servicio detenido?)" -ForegroundColor Red
        }

        Write-Host "`n(Presione CTRL+C para salir del monitoreo)"
        Start-Sleep -Seconds 2
    }
}

# --- MENU PRINCIPAL ---
function Menu-DHCP(){
    while ($true) {
        Clear-Host
        Write-Host "========================================"
        Write-Host "        GESTIONAR SERVICIO DHCP"
        Write-Host "========================================"
        Write-Host "1. Verificar Estado del Servicio"
        Write-Host "2. Instalar Servicio (Rol DHCP)"
        Write-Host "3. Configurar Servicio"
        Write-Host "4. Monitorear Servicio"
        Write-Host "5. Salir"
        Write-Host "========================================"
        $opcion = Read-Host "Opcion"

        switch ($opcion) {
            "1" { Estado-Servicio }
            "2" { Instalar-Servicio }
            "3" { Configurar-Servicio }
            "4" { Monitorear-Servicio }
            "5" { return }
            Default { Write-Host "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    }
}
