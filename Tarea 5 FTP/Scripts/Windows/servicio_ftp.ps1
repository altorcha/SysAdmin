<#
    Tarea 5: Automatización de Servidor FTP
    Autor: Alberto Torres Chaparro
    Descripción: Este Script contiene las funciones para la instalación y  gestión del servicio FTP en Windows.
#>

function Estado-FTP {

    while ($true) {

        Clear-Host
        Write-Host "----------------------------------------"
        Write-Host "        ESTADO DEL SERVICIO FTP"
        Write-Host "----------------------------------------"
        #FTP esta instalado?
        Import-Module ServerManager
        $FtpInstalado = Get-WindowsFeature -Name Web-FTP-Server
        
        # Si no esta instalado
        if ($FtpInstalado.InstallState -ne "Installed") {
            Write-Host "[!] El servicio 'Servidor FTP' NO esta instalado." -ForegroundColor Red
            Write-Host "Por favor, use la opcion de instalacion."
            Read-Host "Presione Enter para volver..."
            return
        }

        # Obtenemos el servicio ftpsvc
        $servicio = Get-Service ftpsvc -ErrorAction SilentlyContinue

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
                    Write-Host "Deteniendo servicio FTP..." -ForegroundColor Yellow
                    Stop-Service ftpsvc -Force
                }
                else {
                    Write-Host "Iniciando servicio FTP..." -ForegroundColor Green
                    Start-Service ftpsvc
                }
                Start-Sleep -Seconds 2
            }

            "2" {
                if ($servicio.Status -eq "Running") {
                    Write-Host "Reiniciando servicio FTP..." -ForegroundColor Green
                    Restart-Service ftpsvc -Force
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

#Estado-FTP

function Instalar-FTP {
    Clear-Host
    Write-host "==========================================================="
    Write-Host "            INSTALACION DEL SERVICIO FTP"
    Write-host "==========================================================="
    Import-Module ServerManager

    $FtpInstalado = Get-WindowsFeature -Name Web-FTP-Server

    if ($FtpInstalado.InstallState -eq "Installed") {
        Write-Host "El servicio FTP ya esta instalado." -ForegroundColor Yellow
        Pause
        return
    }
    Write-Host "Iniciando instalacion del servicio FTP..."
    Install-WindowsFeature -Name Web-FTP-Server, Web-FTP-Ext, Web-FTP-Service, Web-Mgmt-Console | Out-Null

    # Volvemos a validar si se instalo correctamente
    $ftpCheck = Get-WindowsFeature -Name Web-FTP-Server

    if ($ftpCheck.InstallState -eq "Installed") {

        # Configurar el inicio automatico
        Set-Service -Name ftpsvc -StartupType 'Automatic'

        # Iniciar servicio FTP
        Start-Service ftpsvc

        
        # Verificar y habilitar regla puerto 21
        $fw21 = Get-NetFirewallRule -Name "FTP-Puerto21" -ErrorAction SilentlyContinue
        if (!$fw21) {
            New-NetFirewallRule -Name "FTP-Puerto21" -DisplayName "FTP (TCP 21)" -Protocol TCP -LocalPort 21 -Action Allow -Profile Any | Out-Null
        }

        # Verificar y habilitar regla puertos pasivos
        $fwPasivo = Get-NetFirewallRule -Name "FTP-Pasivo" -ErrorAction SilentlyContinue
        if (!$fwPasivo) {
            New-NetFirewallRule -Name "FTP-Pasivo" -DisplayName "FTP Pasivo (40000-40100)" -Protocol TCP -LocalPort 40000-40100 -Action Allow -Profile Any | Out-Null
        }

        # Registrar el rango pasivo en la configuración de IIS
        Import-Module WebAdministration
        Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.ftpServer/provider/options" -name "dataChannelPortRange" -value "40000-40100"

        # Reiniciar para aplicar configuración pasiva
        Restart-Service ftpsvc

        Write-Host "Instalacion completada, servicio configurado en automatico y firewall asegurado." -ForegroundColor Green
    }
    else {
        Write-Host "Error en la instalacion del Servidor FTP." -ForegroundColor Red
    }

    Pause
}
Instalar-FTP