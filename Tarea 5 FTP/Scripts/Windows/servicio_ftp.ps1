<#
    Tarea 5: Automatización de Servidor FTP
    Autor: Alberto Torres Chaparro
    Descripción: Este Script contiene las funciones para la instalación y  gestión del servicio FTP en Windows.
#>
Set-ExecutionPolicy Bypass -Scope Process -Force
function Estado-FTP {

    while ($true) {

        Clear-Host
        Write-Host "----------------------------------------"
        Write-Host "        ESTADO DEL SERVICIO FTP"
        Write-Host "----------------------------------------"

        Import-Module ServerManager
        $FtpInstalado = Get-WindowsFeature Web-FTP-Server

        if ($FtpInstalado.InstallState -ne "Installed") {
            Write-Host "FTP NO esta instalado." -ForegroundColor Red
            Pause
            return
        }

        $servicio = Get-Service ftpsvc

        if ($servicio.Status -eq "Running") {

            Write-Host "Estado: ACTIVO" -ForegroundColor Green
            Write-Host ""
            Write-Host "1) Detener servicio"
            Write-Host "2) Reiniciar servicio"
            Write-Host "3) Volver"

        }
        else {

            Write-Host "Estado: DETENIDO" -ForegroundColor Red
            Write-Host ""
            Write-Host "1) Iniciar servicio"
            Write-Host "3) Volver"

        }

        $opcion = Read-Host "Seleccione opcion"

        switch ($opcion) {

            "1" {

                if ($servicio.Status -eq "Running") {
                    Stop-Service ftpsvc -Force
                }
                else {
                    Start-Service ftpsvc
                }

                Start-Sleep 2
            }

            "2" {

                Restart-Service ftpsvc -Force
                iisreset
                Start-Sleep 2
            }

            "3" { return }

        }
    }
}
#-------------------------------------------------
# FIREWALL
#-------------------------------------------------

function Configurar-Firewall {

    if (-not (Get-NetFirewallRule -DisplayName "FTP Server Port 21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Server Port 21" -Direction Inbound -LocalPort 21 -Protocol TCP -Action Allow -Profile Any
    }

    if (-not (Get-NetFirewallRule -DisplayName "FTP Passive Ports" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Passive Ports" -Direction Inbound -LocalPort 40000-40100 -Protocol TCP -Action Allow -Profile Any
    }

    Write-Host "Firewall configurado para FTP."
}

#-------------------------------------------------
# INSTALAR FTP
#-------------------------------------------------

function Instalar-FTP {

    Write-Host "`nVerificando instalación de IIS + FTP..."

    $features = @("Web-Server","Web-FTP-Server","Web-FTP-Service","Web-FTP-Ext")

    foreach ($feature in $features) {

        $estado = Get-WindowsFeature $feature

        if (-not $estado.Installed) {

            Write-Host "Instalando $feature ..."
            Install-WindowsFeature $feature -IncludeManagementTools

        } else {

            Write-Host "$feature ya está instalado."

        }
    }

    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Set-Service ftpsvc -StartupType Automatic

    Start-Service W3SVC -ErrorAction SilentlyContinue
    Set-Service W3SVC -StartupType Automatic

    Configurar-Firewall

    Write-Host "`nInstalación completada."
}

#-------------------------------------------------
# CONFIGURAR FTP
#-------------------------------------------------
function Configurar-FTP {

    Import-Module WebAdministration

    $ftpSiteName = "FTP_Servidor"
    $ftpRoot = "C:\ftp"

    if (-not (Test-Path $ftpRoot)) {
        New-Item -Path $ftpRoot -ItemType Directory | Out-Null
    }

    if (Get-WebSite -Name $ftpSiteName -ErrorAction SilentlyContinue) {
        Remove-WebSite $ftpSiteName
    }

    Write-Host "Creando sitio FTP..."

    New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $ftpRoot -Force

    Write-Host "Configurando autenticación..."

    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
    -Name ftpServer.security.authentication.anonymousAuthentication.enabled `
    -Value $true

    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
    -Name ftpServer.security.authentication.anonymousAuthentication.userName `
    -Value "IUSR"

    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
    -Name ftpServer.security.authentication.basicAuthentication.enabled `
    -Value $true

    Write-Host "Configurando aislamiento de usuarios..."

    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.userIsolation.mode `
        -Value 3

    Write-Host "Configurando puertos pasivos..."

    C:\Windows\System32\inetsrv\appcmd.exe set config `
        -section:system.ftpServer/firewallSupport `
        /lowDataChannelPort:40000 `
        /highDataChannelPort:40100 `
        /commit:apphost

    Write-Host "Desactivando SSL obligatorio..."

    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.ssl.controlChannelPolicy `
        -Value 0

    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.ssl.dataChannelPolicy `
        -Value 0

    Write-Host "Configurando reglas de acceso..."

    Clear-WebConfiguration `
        -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\" `
        -Location $ftpSiteName

    Add-WebConfiguration `
        -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\" `
        -Location $ftpSiteName `
        -Value @{accessType="Allow"; roles="ftpusuarios"; permissions="Read,Write"}

    Add-WebConfiguration `
        -Filter "system.ftpServer/security/authorization" `
        -PSPath "IIS:\" `
        -Location $ftpSiteName `
        -Value @{accessType="Allow"; users="?"; permissions="Read"}

    Restart-Service ftpsvc

    Write-Host "FTP configurado correctamente."
}
#-------------------------------------------------
# CREAR GRUPOS
#-------------------------------------------------

function Crear-Grupos {

    $grupos = @("reprobados","recursadores","ftpusuarios")

    foreach ($g in $grupos) {

        if (-not (Get-LocalGroup $g -ErrorAction SilentlyContinue)) {

            New-LocalGroup $g
            Write-Host "Grupo $g creado."

        } else {

            Write-Host "Grupo $g ya existe."

        }
    }
}

#-------------------------------------------------
# CREAR ESTRUCTURA
#-------------------------------------------------

function Crear-Estructura {

    $raiz = "C:\ftp"

    $dirs = @(
        "$raiz",
        "$raiz\general",
        "$raiz\reprobados",
        "$raiz\recursadores",
        "$raiz\LocalUser",
        "$raiz\LocalUser\Public"
    )

    foreach ($d in $dirs) {

        if (-not (Test-Path $d)) {

            New-Item -Path $d -ItemType Directory | Out-Null

        }
    }

    $jGeneral = "$raiz\LocalUser\Public\general"

    if (-not (Test-Path $jGeneral)) {

        cmd /c "mklink /J `"$jGeneral`" `"$raiz\general`"" | Out-Null

    }

    Write-Host "Estructura creada."
}

#-------------------------------------------------
# PERMISOS
#-------------------------------------------------

function Asignar-Permisos {

    $raiz = "C:\ftp"

    icacls $raiz /inheritance:r `
        /grant:r "Administrators:(OI)(CI)F" `
        /grant:r "SYSTEM:(OI)(CI)F" `
        /grant:r "IUSR:(RX)" `
        /grant:r "IIS_IUSRS:(RX)" `
        /grant:r "Users:(RX)"

    icacls "$raiz\general" /inheritance:r `
        /grant:r "Administrators:(OI)(CI)F" `
        /grant:r "SYSTEM:(OI)(CI)F" `
        /grant:r "ftpusuarios:(OI)(CI)M" `
        /grant:r "IUSR:(OI)(CI)RX"

    foreach ($g in @("reprobados","recursadores")) {

        icacls "$raiz\$g" /inheritance:r `
            /grant:r "Administrators:(OI)(CI)F" `
            /grant:r "SYSTEM:(OI)(CI)F" `
            /grant:r "${g}:(OI)(CI)M" `
            /grant:r "CREATOR OWNER:(OI)(CI)F"

    }

    icacls "$raiz\LocalUser" /inheritance:r `
        /grant:r "Administrators:(OI)(CI)F" `
        /grant:r "SYSTEM:(OI)(CI)F" `
        /grant:r "IUSR:(RX)" `
        /grant:r "IIS_IUSRS:(RX)" `
        /grant:r "Users:(RX)"

    icacls "$raiz\LocalUser\Public" /inheritance:r `
        /grant:r "Administrators:(OI)(CI)F" `
        /grant:r "SYSTEM:(OI)(CI)F" `
        /grant:r "IUSR:(OI)(CI)RX"

    Write-Host "Permisos aplicados correctamente."
}

#-------------------------------------------------
# VISTA FTP USUARIO
#-------------------------------------------------

function Agregar-VirtualDirs-Usuario {

    param(
        [string]$nombre,
        [string]$grupo
    )

    $raiz = "C:\ftp"
    $userHome = "$raiz\LocalUser\$nombre"

    if (-not (Test-Path $userHome)) {
        New-Item -Path $userHome -ItemType Directory | Out-Null
    }

    # carpeta personal
    $personal = "$userHome\$nombre"
    if (-not (Test-Path $personal)) {
        New-Item -Path $personal -ItemType Directory | Out-Null
    }

    icacls $userHome /inheritance:r `
        /grant:r "${nombre}:(OI)(CI)M" `
        /grant:r "Administrators:(OI)(CI)F" `
        /grant:r "SYSTEM:(OI)(CI)F" `
        /grant:r "IIS_IUSRS:(RX)" `
        /grant:r "Users:(RX)"

    # enlace a general
    $jGeneral = "$userHome\general"
    if (-not (Test-Path $jGeneral)) {
        cmd /c "mklink /J `"$jGeneral`" `"$raiz\general`"" | Out-Null
    }

    # enlace a grupo
    $jGrupo = "$userHome\$grupo"
    if (-not (Test-Path $jGrupo)) {
        cmd /c "mklink /J `"$jGrupo`" `"$raiz\$grupo`"" | Out-Null
    }

    Write-Host "Vista FTP creada para $nombre."
}
#-------------------------------------------------
# CREAR USUARIOS
#-------------------------------------------------

function Crear-Usuarios {

    $num = Read-Host "Número de usuarios a crear"

    for ($i=1; $i -le $num; $i++) {

        $nombre = Read-Host "Usuario"

        if (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue) {

            Write-Host "Usuario ya existe."
            continue

        }

        $pass = Read-Host -AsSecureString "Contraseña"
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {

            Write-Host "Grupo inválido."
            continue

        }

        New-LocalUser -Name $nombre -Password $pass -FullName $nombre

        Add-LocalGroupMember -Group $grupo -Member $nombre
        Add-LocalGroupMember -Group "ftpusuarios" -Member $nombre

        Agregar-VirtualDirs-Usuario -nombre $nombre -grupo $grupo

        Write-Host "Usuario $nombre creado."
    }
}

#-------------------------------------------------
# CAMBIAR GRUPO
#-------------------------------------------------

function Cambiar-Grupo-Usuario {

    $nombre = Read-Host "Usuario"
    $grupo = Read-Host "Nuevo grupo (reprobados/recursadores)"

    foreach ($g in @("reprobados","recursadores")) {

        Remove-LocalGroupMember -Group $g -Member $nombre -ErrorAction SilentlyContinue

    }

    Add-LocalGroupMember -Group $grupo -Member $nombre

    Agregar-VirtualDirs-Usuario -nombre $nombre -grupo $grupo

    Restart-Service ftpsvc

    Write-Host "Grupo actualizado."
}

#-------------------------------------------------
# MENU
#-------------------------------------------------

function Menu-FTP {

    while ($true) {
        Clear-Host
        Write-Host "=================================================="
        Write-Host "            GESTION DEL SERVICIO FTP"
        Write-Host "=================================================="
        Write-Host "1) Estado del servicio"
        Write-Host "2) Instalar FTP"
        Write-Host "3) Configurar FTP"
        Write-Host "4) Crear grupos"
        Write-Host "5) Crear estructura"
        Write-Host "6) Permisos"
        Write-Host "7) Crear usuarios"
        Write-Host "8) Cambiar grupo"
        Write-Host "9) Salir"
        Write-Host "=================================================="

        $op = Read-Host "Seleccione una opcion"

        switch ($op) {
            "1" { Estado-FTP }
            "2" { Instalar-FTP }
            "3" { Configurar-FTP }
            "4" { Crear-Grupos }
            "5" { Crear-Estructura }
            "6" { Asignar-Permisos }
            "7" { Crear-Usuarios }
            "8" { Cambiar-Grupo-Usuario }
            "9" { break }
            default { Write-Host "Opcion invalida." -ForegroundColor Red; Start-Sleep 2 }

        }
    }
}
