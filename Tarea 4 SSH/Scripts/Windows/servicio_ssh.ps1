<#
    Tarea 4: Acceso remoto mediante SSH
    Autor: Alberto Torres Chaparro
    Descripción: Este Script contiene las funciones para la instalación
    automatizada del servicio SSH y la visualización del estado del servicio.
#>
function Estado-SSH {

    while ($true) {

        Clear-Host
        Write-Host "----------------------------------------"
        Write-Host "        ESTADO DEL SERVICIO SSH"
        Write-Host "----------------------------------------"

        # SSH esta instalado?
        $SshInstalado = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        #Si no esta instalado
        if ($SshInstalado.State -ne "Installed") {
            Write-Host "[!] El servicio 'OpenSSH Server' NO esta instalado." -ForegroundColor Red
            Write-Host "Por favor, use la opcion de instalacion."
            Read-Host "Presione Enter para volver..."
            return
        }

        # Obtenemos el servicio
        $servicio = Get-Service sshd -ErrorAction SilentlyContinue

        if ($servicio -and $servicio.Status -eq "Running") {
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
                if ($servicio.Status -eq "Running") {
                    Write-Host "Deteniendo servicio SSH..." -ForegroundColor Yellow
                    Stop-Service sshd -Force
                }
                else {
                    Write-Host "Iniciando servicio SSH..." -ForegroundColor Green
                    Start-Service sshd
                }
                Start-Sleep -Seconds 2
            }

            "2" {
                if ($servicio.Status -eq "Running") {
                    Write-Host "Reiniciando servicio SSH..." -ForegroundColor Green
                    Restart-Service sshd -Force
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


function Instalar-SSH {

    Clear-Host

    $SshInstalado = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

    if ($SshInstalado.State -eq "Installed") {
        Write-Host "OpenSSH Server ya está instalado." -ForegroundColor Yellow
        Pause
        return
    }

    Write-Host "Instalando servicio OpenSSH Server... (Esto puede tardar un momento)"
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null

    # Volvemos a validar si se instalo correctamente
    $sshCheck = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

    if ($sshCheck.State -eq "Installed") {

        # Configurar el inicio automatico
        Set-Service -Name sshd -StartupType 'Automatic'

        # Iniciar servicio SSH
        Start-Service sshd

        # Verificar y habilitar la regla de Firewall
        $firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
        
        if (!$firewallRule) {
            # Si la regla no se creo durante la instalacion, la creamos manualmente
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        } else {
            # Si existe pero esta deshabilitada, la habilitamos
            Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
        }

        Write-Host "Instalacion completada, servicio configurado en automatico y firewall asegurado." -ForegroundColor Green
    }
    else {
        Write-Host "Error en la instalación de OpenSSH." -ForegroundColor Red
    }

    Pause
}

function Menu-SSH {
    while ($true) {

        Clear-Host
        Write-Host "======================================="
        Write-Host "          SERVICIO SSH"
        Write-Host "======================================="
        Write-Host "1) Estado del servicio SSH"
        Write-Host "2) Instalar el servicio SSH"
        Write-Host "3) Salir"
        Write-Host "======================================="

        $opcion = Read-Host "Selecciona una opcion"

        switch ($opcion) {
            "1" { Estado-SSH }
            "2" { Instalar-SSH }
            "3" { return }
            default { Write-Host "Opcion invalida" -ForegroundColor Yellow; Start-Sleep 1 }
        }
    }
}

