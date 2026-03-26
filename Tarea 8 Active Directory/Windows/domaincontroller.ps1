function Promover-DomainController {

    Write-Header "PROMOVER A DOMAIN CONTROLLER"

    $adds = Get-WindowsFeature -Name "AD-Domain-Services"
    if ($adds.InstallState -ne "Installed") {
        Write-Fila "ERR" "AD-Domain-Services no esta instalado."
        Write-Host ""; Write-Sep; Write-Fila "INF" "Ejecuta primero la opcion 1."; Write-Host ""; return
    }

    try {
        $info = Get-ADDomain -ErrorAction Stop
        Write-Fila "AVS" "Este servidor ya es DC  ->  $($info.DNSRoot)"
        Write-Host ""; Write-Sep; Write-Fila "INF" "No es necesario volver a promoverlo."; Write-Host ""; return
    } catch {}

    Write-Host "  Parametros del nuevo bosque:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "Dominio         :  Active.Drectory"
    Write-Fila "INF" "NetBIOS         :  Tarea8"
    Write-Fila "INF" "Nivel de bosque :  Windows Server 2022"
    Write-Fila "INF" "DNS             :  Se instala en este servidor"
    Write-Fila "INF" "IP del servidor :  192.168.10.11"
    Write-Host ""
    Write-Host "  El servidor se reiniciara automaticamente al finalizar." -ForegroundColor DarkYellow
    Write-Host ""

    if (-not (Confirm-Accion "Deseas continuar?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    $dsrmPassword = Read-Host "  Contrasena DSRM (modo de restauracion)" -AsSecureString
    Write-Host ""

    Write-Host "  Configurando DNS estatico en el adaptador..." -ForegroundColor Gray

    $adaptador = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ip = Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ip.IPAddress -eq "192.168.10.11") { $_ }
    }

    if ($adaptador) {
        Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses "192.168.10.11"
        Write-Fila "OK" "DNS configurado  ->  $($adaptador.Name)"
    } else {
        Write-Fila "AVS" "No se encontro adaptador con IP 192.168.10.11  (continuando)"
    }

    Write-Host ""
    Write-Host "  Iniciando promocion, esto puede tardar varios minutos..." -ForegroundColor Gray
    Write-Host ""

    try {
        Install-ADDSForest `
            -DomainName "Active.Directory" `
            -DomainNetbiosName "Tarea8" `
            -ForestMode "WinThreshold" `
            -DomainMode "WinThreshold" `
            -InstallDns:$true `
            -SafeModeAdministratorPassword $dsrmPassword `
            -NoRebootOnCompletion:$false `
            -Force:$true

        Write-Fila "OK" "Promocion completada. Reiniciando servidor..."
    } catch {
        Write-Fila "ERR" "Fallo la promocion  :  $($_.Exception.Message)"
    }
    Write-Host ""
}
