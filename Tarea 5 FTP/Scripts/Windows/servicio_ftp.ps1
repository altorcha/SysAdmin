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

Estado-FTP