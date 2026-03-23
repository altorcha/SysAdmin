# ============================================================
# ftp_server.ps1
# Practica 7 - Servidor FTP Local - Administracion
# Windows Server 2019/2022 - PowerShell
# ============================================================

. "$PSScriptRoot\globals.ps1"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\utilidades.ps1"

function FTP-Log {
    param([string]$Msg)
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if (-not (Test-Path $global:FTP_DATA)) { New-Item $global:FTP_DATA -ItemType Directory -Force | Out-Null }
    Add-Content $global:FTP_LOG "$fecha - $Msg" -ErrorAction SilentlyContinue
}

# ── Instalar IIS + FTP ───────────────────────────────────────────────────────

function FTP-Instalar {
    Escribir-Titulo "INSTALAR SERVIDOR FTP (IIS-FTP)"
    Write-Host "  Instalando IIS + FTP Service..." -ForegroundColor Cyan

    $features = @("Web-Server","Web-FTP-Server","Web-FTP-Service","Web-FTP-Ext")
    foreach ($f in $features) {
        if (-not (Get-WindowsFeature $f -ErrorAction SilentlyContinue).Installed) {
            Install-WindowsFeature $f -IncludeManagementTools | Out-Null
        }
    }

    Start-Service W3SVC   -ErrorAction SilentlyContinue
    Start-Service ftpsvc  -ErrorAction SilentlyContinue
    Set-Service   ftpsvc  -StartupType Automatic -ErrorAction SilentlyContinue

    Write-Host "  FTP instalado correctamente." -ForegroundColor Green
    FTP-Log "FTP instalado"
    Registrar-Resumen -Servicio "IIS-FTP" -Accion "Instalacion" -Estado "OK"
}

# ── Firewall FTP ─────────────────────────────────────────────────────────────

function FTP-Configurar-Firewall {
    Escribir-Titulo "CONFIGURAR FIREWALL FTP"

    Remove-NetFirewallRule -DisplayName "FTP-Puerto-21"    -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "FTP-Pasivo-Rango" -ErrorAction SilentlyContinue

    New-NetFirewallRule -DisplayName "FTP-Puerto-21" `
        -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow | Out-Null

    New-NetFirewallRule -DisplayName "FTP-Pasivo-Rango" `
        -Direction Inbound -Protocol TCP -LocalPort 50000-51000 -Action Allow | Out-Null

    Write-Host "  Firewall configurado: puerto 21 y rango pasivo 50000-51000." -ForegroundColor Green
    FTP-Log "Firewall FTP configurado"
}

# ── Grupos ───────────────────────────────────────────────────────────────────

function FTP-Crear-Grupos {
    Escribir-Titulo "CREAR GRUPOS FTP"

    foreach ($g in @("reprobados","recursadores","ftpusuarios")) {
        if (-not (Get-LocalGroup $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup $g | Out-Null
            Write-Host "  Grupo '$g' creado." -ForegroundColor Green
        } else {
            Write-Host "  Grupo '$g' ya existe." -ForegroundColor Yellow
        }
    }
    FTP-Log "Grupos verificados"
}

# ── Estructura de carpetas ───────────────────────────────────────────────────

function FTP-Crear-Estructura {
    Escribir-Titulo "CREAR ESTRUCTURA DE CARPETAS FTP"

    foreach ($carpeta in @("","general","reprobados","recursadores","usuarios")) {
        New-Item "$($global:FTP_DATA)\$carpeta" -ItemType Directory -Force | Out-Null
    }

    # Carpeta anonimo
    New-Item "$($global:FTP_ROOT)\LocalUser\Public" -ItemType Directory -Force | Out-Null

    # Junction para acceso anonimo a /general
    $linkGeneral = "$($global:FTP_ROOT)\LocalUser\Public\general"
    if (-not (Test-Path $linkGeneral)) {
        cmd /c mklink /J "$linkGeneral" "$($global:FTP_DATA)\general" | Out-Null
    }

    Write-Host "  Estructura de carpetas creada." -ForegroundColor Green
    FTP-Log "Estructura FTP creada"
}

# ── Permisos NTFS ────────────────────────────────────────────────────────────

function FTP-Aplicar-Permisos {
    Escribir-Titulo "APLICAR PERMISOS NTFS FTP"

    $sidSystem = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")).Translate([System.Security.Principal.NTAccount]).Value
    $sidAdmins = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate([System.Security.Principal.NTAccount]).Value

    # general: escritura para ftpusuarios, lectura para IUSR (anonimo)
    icacls "$($global:FTP_DATA)\general" /inheritance:r | Out-Null
    icacls "$($global:FTP_DATA)\general" /grant "${sidAdmins}:(OI)(CI)F"     | Out-Null
    icacls "$($global:FTP_DATA)\general" /grant "${sidSystem}:(OI)(CI)F"     | Out-Null
    icacls "$($global:FTP_DATA)\general" /grant "ftpusuarios:(OI)(CI)M"      | Out-Null
    icacls "$($global:FTP_DATA)\general" /grant "IUSR:(OI)(CI)RX"            | Out-Null

    # reprobados: solo grupo reprobados
    icacls "$($global:FTP_DATA)\reprobados" /inheritance:r | Out-Null
    icacls "$($global:FTP_DATA)\reprobados" /grant "${sidAdmins}:(OI)(CI)F"  | Out-Null
    icacls "$($global:FTP_DATA)\reprobados" /grant "${sidSystem}:(OI)(CI)F"  | Out-Null
    icacls "$($global:FTP_DATA)\reprobados" /grant "reprobados:(OI)(CI)M"    | Out-Null

    # recursadores: solo grupo recursadores
    icacls "$($global:FTP_DATA)\recursadores" /inheritance:r | Out-Null
    icacls "$($global:FTP_DATA)\recursadores" /grant "${sidAdmins}:(OI)(CI)F"  | Out-Null
    icacls "$($global:FTP_DATA)\recursadores" /grant "${sidSystem}:(OI)(CI)F"  | Out-Null
    icacls "$($global:FTP_DATA)\recursadores" /grant "recursadores:(OI)(CI)M"  | Out-Null

    # Public (anonimo): solo lectura
    icacls "$($global:FTP_ROOT)\LocalUser\Public" /inheritance:r | Out-Null
    icacls "$($global:FTP_ROOT)\LocalUser\Public" /grant "${sidAdmins}:(OI)(CI)F" | Out-Null
    icacls "$($global:FTP_ROOT)\LocalUser\Public" /grant "${sidSystem}:(OI)(CI)F" | Out-Null
    icacls "$($global:FTP_ROOT)\LocalUser\Public" /grant "IUSR:(OI)(CI)RX"        | Out-Null

    Write-Host "  Permisos NTFS aplicados correctamente." -ForegroundColor Green
    FTP-Log "Permisos NTFS aplicados"
}

# ── Configurar sitio FTP en IIS ──────────────────────────────────────────────

function FTP-Configurar-Sitio {
    Escribir-Titulo "CONFIGURAR SITIO FTP EN IIS"
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Eliminar sitio previo si existe
    if (Get-WebSite $global:FTP_SITE -ErrorAction SilentlyContinue) {
        Remove-WebSite $global:FTP_SITE -ErrorAction SilentlyContinue
    }

    # Crear sitio FTP apuntando a C:\Users (requerido por IsolateAllDirectories en Windows EN)
    New-WebFtpSite -Name $global:FTP_SITE -Port 21 -PhysicalPath $global:FTP_ROOT -Force | Out-Null

    # Insertar configuracion en applicationHost.config
    # (Set-ItemProperty falla en algunas versiones EN por encoding)
    $configPath = "C:\Windows\System32\inetsrv\config\applicationHost.config"
    $utf8NoBOM  = New-Object System.Text.UTF8Encoding $false
    $content    = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)

    $viejo = "</bindings>`r`n            </site>"
    $nuevo = "</bindings>`r`n                <ftpServer>`r`n                    <userIsolation mode=""IsolateAllDirectories"" />`r`n                    <security>`r`n                        <ssl controlChannelPolicy=""SslAllow"" dataChannelPolicy=""SslAllow"" />`r`n                        <authentication>`r`n                            <anonymousAuthentication enabled=""true"" />`r`n                            <basicAuthentication enabled=""true"" />`r`n                        </authentication>`r`n                    </security>`r`n                </ftpServer>`r`n            </site>"

    if ($content -notmatch "userIsolation") {
        $content = $content.Replace($viejo, $nuevo)
        [System.IO.File]::WriteAllText($configPath, $content, $utf8NoBOM)
    }

    # Reglas de autorizacion via appcmd
    $appcmd = "C:\Windows\System32\inetsrv\appcmd.exe"
    & $appcmd set config $global:FTP_SITE -section:system.ftpServer/security/authorization /+"[accessType='Allow',users='?',permissions='Read']" /commit:apphost 2>$null
    & $appcmd set config $global:FTP_SITE -section:system.ftpServer/security/authorization /+"[accessType='Allow',roles='ftpusuarios',permissions='Read,Write']" /commit:apphost 2>$null

    Restart-Service ftpsvc -ErrorAction SilentlyContinue

    Write-Host "  Sitio FTP configurado correctamente." -ForegroundColor Green
    Write-Host "    Raiz FTP   : $($global:FTP_ROOT)" -ForegroundColor Gray
    Write-Host "    Home user  : $($global:FTP_ROOT)\$($global:SERVER_NAME)\<usuario>" -ForegroundColor Gray
    Write-Host "    Home anon  : $($global:FTP_ROOT)\LocalUser\Public" -ForegroundColor Gray
    FTP-Log "Sitio FTP configurado"
    Registrar-Resumen -Servicio "IIS-FTP" -Accion "Configuracion" -Estado "OK" -Detalle "Puerto 21"
}

# ── Crear usuarios FTP ───────────────────────────────────────────────────────

function FTP-Crear-Usuarios {
    Escribir-Titulo "CREAR USUARIOS FTP"

    $cantidad = 0
    while ($cantidad -lt 1) {
        $raw = Leer-Texto -Prompt "Cuantos usuarios desea crear"
        if ($raw -match '^\d+$' -and [int]$raw -gt 0) { $cantidad = [int]$raw }
        else { Write-Host "  Ingrese un numero mayor a 0." -ForegroundColor Red }
    }

    for ($i = 1; $i -le $cantidad; $i++) {
        Write-Host ""
        Write-Host "  --- Usuario $i de $cantidad ---" -ForegroundColor Cyan

        $usuario = Leer-Texto -Prompt "  Nombre de usuario"
        Write-Host "  Contrasena: " -NoNewline
        $pass  = Read-Host -AsSecureString
        $grupo = ""
        while ($grupo -notin @("reprobados","recursadores")) {
            $grupo = Leer-Texto -Prompt "  Grupo (reprobados / recursadores)"
            if ($grupo -notin @("reprobados","recursadores")) {
                Write-Host "  Grupo invalido. Debe ser 'reprobados' o 'recursadores'." -ForegroundColor Red
            }
        }

        if (Get-LocalUser $usuario -ErrorAction SilentlyContinue) {
            Write-Host "  El usuario '$usuario' ya existe. Omitiendo." -ForegroundColor Yellow
            continue
        }

        # Crear usuario local
        New-LocalUser $usuario -Password $pass -PasswordNeverExpires | Out-Null
        Add-LocalGroupMember $grupo        -Member $usuario -ErrorAction SilentlyContinue
        Add-LocalGroupMember "ftpusuarios" -Member $usuario -ErrorAction SilentlyContinue

        # Home del usuario: C:\Users\<SERVIDOR>\<usuario>
        $userHome = "$($global:FTP_ROOT)\$($global:SERVER_NAME)\$usuario"
        New-Item $userHome -ItemType Directory -Force | Out-Null
        New-Item "$($global:FTP_DATA)\usuarios\$usuario" -ItemType Directory -Force | Out-Null

        # Junction links visibles al hacer login
        foreach ($link in @("general", $grupo, $usuario)) {
            if (Test-Path "$userHome\$link") { cmd /c rmdir "$userHome\$link" | Out-Null }
        }
        cmd /c mklink /J "$userHome\general"  "$($global:FTP_DATA)\general"           | Out-Null
        cmd /c mklink /J "$userHome\$grupo"   "$($global:FTP_DATA)\$grupo"            | Out-Null
        cmd /c mklink /J "$userHome\$usuario" "$($global:FTP_DATA)\usuarios\$usuario" | Out-Null

        # Permisos NTFS
        icacls $userHome                                    /grant "${usuario}:(OI)(CI)RX" | Out-Null
        icacls "$($global:FTP_DATA)\usuarios\$usuario"     /grant "${usuario}:(OI)(CI)F"  | Out-Null

        Write-Host "  Usuario '$usuario' creado en grupo '$grupo'." -ForegroundColor Green
        FTP-Log "Usuario $usuario creado en grupo $grupo"
    }

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "  Usuarios creados correctamente." -ForegroundColor Green
}

# ── Eliminar usuario FTP ─────────────────────────────────────────────────────

function FTP-Eliminar-Usuario {
    Escribir-Titulo "ELIMINAR USUARIO FTP"
    FTP-Ver-Usuarios

    $usuario = Leer-Texto -Prompt "Nombre del usuario a eliminar"

    if (-not (Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "  El usuario '$usuario' no existe." -ForegroundColor Yellow
        return
    }

    Remove-LocalUser $usuario -ErrorAction SilentlyContinue
    Remove-Item "$($global:FTP_ROOT)\$($global:SERVER_NAME)\$usuario" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$($global:FTP_DATA)\usuarios\$usuario"               -Recurse -Force -ErrorAction SilentlyContinue

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "  Usuario '$usuario' eliminado." -ForegroundColor Green
    FTP-Log "Usuario eliminado: $usuario"
}

# ── Cambiar grupo de usuario FTP ─────────────────────────────────────────────

function FTP-Cambiar-Grupo {
    Escribir-Titulo "CAMBIAR GRUPO DE USUARIO FTP"
    FTP-Ver-Usuarios

    $usuario = Leer-Texto -Prompt "Nombre del usuario"
    if (-not (Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
        Write-Host "  El usuario '$usuario' no existe." -ForegroundColor Yellow
        return
    }

    $grupo = ""
    while ($grupo -notin @("reprobados","recursadores")) {
        $grupo = Leer-Texto -Prompt "Nuevo grupo (reprobados / recursadores)"
        if ($grupo -notin @("reprobados","recursadores")) {
            Write-Host "  Grupo invalido." -ForegroundColor Red
        }
    }

    # Quitar de grupos anteriores
    Remove-LocalGroupMember -Group "reprobados"   -Member $usuario -ErrorAction SilentlyContinue
    Remove-LocalGroupMember -Group "recursadores" -Member $usuario -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $grupo         -Member $usuario -ErrorAction SilentlyContinue

    # Actualizar junction links
    $userHome = "$($global:FTP_ROOT)\$($global:SERVER_NAME)\$usuario"
    foreach ($g in @("reprobados","recursadores")) {
        if (Test-Path "$userHome\$g") { cmd /c rmdir "$userHome\$g" | Out-Null }
    }
    cmd /c mklink /J "$userHome\$grupo" "$($global:FTP_DATA)\$grupo" | Out-Null

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "  Usuario '$usuario' movido al grupo '$grupo'." -ForegroundColor Green
    FTP-Log "Usuario $usuario cambiado al grupo $grupo"
}

# ── Ver usuarios FTP ─────────────────────────────────────────────────────────

function FTP-Ver-Usuarios {
    Write-Host ""
    Write-Host "  Usuarios FTP registrados:" -ForegroundColor Cyan
    Write-Host ""
    $miembros = Get-LocalGroupMember "ftpusuarios" -ErrorAction SilentlyContinue
    if (-not $miembros) {
        Write-Host "  (No hay usuarios en el grupo ftpusuarios)" -ForegroundColor DarkGray
        return
    }
    foreach ($m in $miembros) {
        $u      = $m.Name.Split("\")[-1]
        $grupos = @()
        if (Get-LocalGroupMember "reprobados"   -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$u" }) { $grupos += "reprobados" }
        if (Get-LocalGroupMember "recursadores" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$u" }) { $grupos += "recursadores" }
        Write-Host ("    {0,-20} Grupo: {1}" -f $u, ($grupos -join ", ")) -ForegroundColor Gray
    }
    Write-Host ""
}

# ── Estado del servidor FTP ──────────────────────────────────────────────────

function FTP-Ver-Estado {
    Write-Host ""
    Write-Host "  Servicio ftpsvc:" -ForegroundColor Cyan
    $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if ($svc) {
        $color = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host ("    Estado: {0}" -f $svc.Status) -ForegroundColor $color
    } else {
        Write-Host "    FTP no instalado." -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  Puerto 21:" -ForegroundColor Cyan
    $escucha = netstat -an 2>$null | Select-String ":21 "
    if ($escucha) { $escucha | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray } }
    else          { Write-Host "    No hay nada escuchando en puerto 21." -ForegroundColor DarkGray }

    Write-Host ""
    Write-Host "  Sitios IIS:" -ForegroundColor Cyan
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Get-WebSite -ErrorAction SilentlyContinue | Format-Table Name, State, PhysicalPath -AutoSize
}

# ── Reiniciar FTP ────────────────────────────────────────────────────────────

function FTP-Reiniciar {
    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "  Servicio FTP reiniciado." -ForegroundColor Green
}

# ── Menu de administracion FTP ───────────────────────────────────────────────

function Menu-Administrar-FTP {
    while ($true) {
        Escribir-Titulo "ADMINISTRAR SERVIDOR FTP LOCAL"
        Write-Host "  -- CONFIGURACION INICIAL (ejecutar en orden la primera vez) --" -ForegroundColor Yellow
        Write-Host "   1) Instalar IIS + FTP Service"
        Write-Host "   2) Configurar Firewall (puertos 21 y 50000-51000)"
        Write-Host "   3) Crear grupos (reprobados, recursadores, ftpusuarios)"
        Write-Host "   4) Crear estructura de carpetas"
        Write-Host "   5) Aplicar permisos NTFS"
        Write-Host "   6) Configurar sitio FTP en IIS"
        Write-Host ""
        Write-Host "  -- GESTION DE USUARIOS --" -ForegroundColor Yellow
        Write-Host "   7) Crear usuario(s) FTP"
        Write-Host "   8) Eliminar usuario FTP"
        Write-Host "   9) Cambiar grupo de usuario"
        Write-Host "  10) Ver usuarios FTP"
        Write-Host ""
        Write-Host "  -- UTILIDADES --" -ForegroundColor Yellow
        Write-Host "  11) Ver estado del servidor FTP"
        Write-Host "  12) Reiniciar servicio FTP"
        Write-Host "   0) Volver al menu principal"
        Write-Host ""

        $op = Leer-Opcion -Prompt "Seleccione" -Validas @("0","1","2","3","4","5","6","7","8","9","10","11","12")

        switch ($op) {
            "1"  { FTP-Instalar }
            "2"  { FTP-Configurar-Firewall }
            "3"  { FTP-Crear-Grupos }
            "4"  { FTP-Crear-Estructura }
            "5"  { FTP-Aplicar-Permisos }
            "6"  { FTP-Configurar-Sitio }
            "7"  { FTP-Crear-Usuarios }
            "8"  { FTP-Eliminar-Usuario }
            "9"  { FTP-Cambiar-Grupo }
            "10" { FTP-Ver-Usuarios }
            "11" { FTP-Ver-Estado }
            "12" { FTP-Reiniciar }
            "0"  { return }
        }
    }
}