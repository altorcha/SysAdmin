# ============================================================
# web_servidores.ps1
# Practica 7 - Servidores Web - IIS, Apache, Nginx
# Windows Server 2019/2022 - PowerShell
# ============================================================

. "$PSScriptRoot\globals.ps1"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\utilidades.ps1"
. "$PSScriptRoot\repositorio.ps1"

function Instalar-Desde-ZIP {
    param([string]$Archivo, [string]$Servicio)

    Write-Host ""
    Write-Host "  Extrayendo e instalando $Servicio desde ZIP..." -ForegroundColor Cyan

    $tmpExtract = "$env:TEMP\extract_$(Get-Random)"
    New-Item $tmpExtract -ItemType Directory -Force | Out-Null

    try {
        Expand-Archive -Path $Archivo -DestinationPath $tmpExtract -Force
    } catch {
        Write-Host "  ERROR al extraer ZIP: $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    switch ($Servicio) {
        "Apache" {
            # El ZIP de Chocolatey empaqueta todo el contenido de Apache24 directamente
            # (bin/, conf/, htdocs/, etc.) sin subcarpeta Apache24 en el primer nivel.
            # Detectar si hay carpeta Apache24 o si el contenido esta directo en la raiz.
            $apacheDir = Get-ChildItem $tmpExtract -Recurse -Directory -Filter "Apache24" | Select-Object -First 1
            $destino   = "C:\Apache24"

            if (Test-Path $destino) {
                & "$destino\bin\httpd.exe" -k stop 2>&1 | Out-Null
                Stop-Service "Apache2.4" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Remove-Item $destino -Recurse -Force -ErrorAction SilentlyContinue
            }

            if ($apacheDir) {
                # ZIP con subcarpeta Apache24 dentro
                Move-Item $apacheDir.FullName $destino
            } else {
                # ZIP con contenido directo (bin/, conf/, htdocs/ en raiz)
                # Verificar que hay bin/httpd.exe en la raiz del ZIP extraido
                if (Test-Path "$tmpExtract\bin\httpd.exe") {
                    Move-Item $tmpExtract $destino -ErrorAction SilentlyContinue
                    $tmpExtract = $null  # ya fue movido, no intentar borrar
                } else {
                    # Intentar con subcarpeta de primer nivel
                    $subDir = Get-ChildItem $tmpExtract -Directory | Select-Object -First 1
                    if ($subDir -and (Test-Path "$($subDir.FullName)\bin\httpd.exe")) {
                        Move-Item $subDir.FullName $destino
                    } else {
                        Write-Host "  ERROR: No se encontro httpd.exe en el ZIP." -ForegroundColor Red
                        Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
                        return $false
                    }
                }
            }
            Write-Host "  Apache extraido en $destino" -ForegroundColor Green
        }
        "Nginx" {
            $nginxDir = Get-ChildItem $tmpExtract -Directory | Where-Object { $_.Name -match "nginx" } | Select-Object -First 1
            if (-not $nginxDir) {
                Write-Host "  ERROR: No se encontro carpeta nginx en el ZIP." -ForegroundColor Red
                Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
                return $false
            }
            $destino = "C:\nginx"
            if (Test-Path $destino) {
                taskkill /f /im nginx.exe 2>&1 | Out-Null
                Start-Sleep -Seconds 1
                Remove-Item $destino -Recurse -Force -ErrorAction SilentlyContinue
            }
            Move-Item $nginxDir.FullName $destino
            Write-Host "  Nginx extraido en $destino" -ForegroundColor Green
        }
        "IIS" {
            Write-Host "  IIS es un rol de Windows. El placeholder fue verificado correctamente." -ForegroundColor Yellow
            Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
            return $true
        }
        default {
            Write-Host "  Servicio '$Servicio' no reconocido." -ForegroundColor Red
            Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
    }

    if ($tmpExtract -and (Test-Path $tmpExtract)) {
        Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $true
}

# ================================================================
# SECCION 5 - INSTALACION DE SERVICIOS HTTP
# ================================================================

function Crear-Index-HTML {
    param(
        [string]$Directorio,
        [string]$Servicio,
        [string]$Version,
        [int]$Puerto,
        [string]$Fuente = "WEB"
    )

    if (-not (Test-Path $Directorio)) {
        New-Item $Directorio -ItemType Directory -Force | Out-Null
    }

    $FuenteBg = if ($Fuente -eq "FTP") { "#8957e5" } else { "#238636" }

    @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>$Servicio</title>
<style>
  body{font-family:'Segoe UI',sans-serif;background:#0d1117;color:#c9d1d9;
       display:flex;justify-content:center;align-items:center;height:100vh;margin:0}
  .card{background:#161b22;border:1px solid #30363d;border-radius:12px;
        padding:2rem 3rem;text-align:center;max-width:480px}
  h1{color:#58a6ff;margin-bottom:.5rem}
  .badge{display:inline-block;background:#238636;color:#fff;
         border-radius:20px;padding:.3rem 1rem;font-size:.9rem;margin:.3rem}
  .port{background:#1f6feb}
  .fuente{background:$FuenteBg}
  p{color:#8b949e;font-size:.85rem;margin-top:1.5rem}
</style>
</head>
<body>
  <div class="card">
    <h1>$Servicio</h1>
    <span class="badge">Version: $Version</span>
    <span class="badge port">Puerto: $Puerto</span>
    <span class="badge fuente">$Fuente</span>
    <p>Practica 7 - Infraestructura de Despliegue Seguro</p>
  </div>
</body>
</html>
"@ | Set-Content "$Directorio\index.html" -Encoding UTF8

    Write-Host "  index.html creado en $Directorio (fuente: $Fuente)" -ForegroundColor Gray
}

# ── IIS ──────────────────────────────────────────────────────────────────────

function Obtener-Puerto-IIS-P7 {
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $b = Get-WebBinding -Name "Default Web Site" -Protocol "http" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($b) { return [int]($b.bindingInformation -split ":")[-2] }
    } catch {}
    return 80
}

function Instalar-IIS-P7 {
    param([int]$Puerto, [string]$Fuente = "WEB")
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $yaInstalado = (Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue).Installed

    if ($yaInstalado) {
        $version     = (Get-Item "C:\Windows\System32\inetsrv\inetinfo.exe" -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
        if (-not $version) { $version = "10.0" }
        $puertoActual = Obtener-Puerto-IIS-P7
        Write-Host "  IIS ya instalado (v$version). Puerto actual: $puertoActual" -ForegroundColor Yellow

        if ($puertoActual -ne $Puerto) {
            Write-Host "  Cambiando puerto $puertoActual -> $Puerto..." -ForegroundColor Cyan
            Remove-WebBinding -Name "Default Web Site" -Protocol "http" -ErrorAction SilentlyContinue
            New-WebBinding -Name "Default Web Site" -Protocol "http" -Port $Puerto -IPAddress "*" | Out-Null
            Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "IIS-HTTP-$Puerto"
            Crear-Index-HTML -Directorio "C:\inetpub\wwwroot" -Servicio "IIS" -Version $version -Puerto $Puerto -Fuente $Fuente
            iisreset /restart | Out-Null
            Registrar-Resumen -Servicio "IIS" -Accion "Puerto-Cambiado" -Estado "OK" -Detalle "$puertoActual -> $Puerto"
            Write-Host "  Puerto actualizado a $Puerto." -ForegroundColor Green
        } else {
            Write-Host "  Puerto ya configurado en $Puerto. Nada que cambiar." -ForegroundColor Green
        }
        return
    }

    # Instalacion nueva
    Write-Host "  Instalando IIS (Internet Information Services)..." -ForegroundColor Cyan
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    Install-WindowsFeature -Name Web-Http-Redirect, Web-Http-Logging, Web-Security | Out-Null

    $version = (Get-Item "C:\Windows\System32\inetsrv\inetinfo.exe" -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
    if (-not $version) { $version = "10.0" }

    Remove-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue
    New-WebBinding -Name "Default Web Site" -Protocol "http" -Port $Puerto -IPAddress "*" | Out-Null
    Crear-Index-HTML -Directorio "C:\inetpub\wwwroot" -Servicio "IIS" -Version $version -Puerto $Puerto -Fuente $Fuente

    # Seguridad: ocultar headers de version
    try {
        Set-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.webServer/security/requestFiltering" -Name "removeServerHeader" -Value $true -ErrorAction SilentlyContinue
        Remove-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -AtElement @{name="X-Powered-By"} -ErrorAction SilentlyContinue
        foreach ($hdr in @(@{n="X-Frame-Options";v="SAMEORIGIN"}, @{n="X-Content-Type-Options";v="nosniff"})) {
            Add-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -Value @{name=$hdr.n;value=$hdr.v} -ErrorAction SilentlyContinue
        }
        foreach ($m in @("TRACE","TRACK","DELETE")) {
            Add-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.webServer/security/requestFiltering/verbs" -Name "." -Value @{verb=$m;allowed="false"} -ErrorAction SilentlyContinue
        }
    } catch {}

    Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "IIS-HTTP-$Puerto"
    iisreset /restart | Out-Null
    Start-Sleep -Seconds 2

    $test   = Test-NetConnection -ComputerName localhost -Port $Puerto -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }

    Registrar-Resumen -Servicio "IIS" -Accion "Instalacion" -Estado $estado -Detalle "v$version puerto $Puerto"
    Write-Host "  IIS instalado. v$version | Puerto: $Puerto | Estado: $estado" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
}

# ── Apache ───────────────────────────────────────────────────────────────────

function Encontrar-Base-Apache-P7 {
    # Identica a Encontrar-Base-Apache de P6
    # Busca httpd.exe en las ubicaciones donde Chocolatey suele instalarlo
    $apacheBase = "C:\Apache24"

    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        $encontrado = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse -Depth 5 -ErrorAction SilentlyContinue |
                      Select-Object -First 1
        if ($encontrado) {
            $apacheBase = Split-Path $encontrado.DirectoryName -Parent
        }
    }

    # Chocolatey a veces deja una subcarpeta extra (Apache24 dentro de Apache24)
    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        $sub = Get-ChildItem $apacheBase -Directory -ErrorAction SilentlyContinue |
               Where-Object { Test-Path "$($_.FullName)\bin\httpd.exe" } |
               Select-Object -First 1
        if ($sub) { $apacheBase = $sub.FullName }
    }

    return $apacheBase
}

function Configurar-Apache-Puerto {
    param([string]$ApacheBase, [int]$Puerto)
    $conf = "$ApacheBase\conf\httpd.conf"
    if (Test-Path $conf) {
        # Reemplazar TODOS los Listen existentes con uno solo del puerto correcto
        $lines = Get-Content $conf
        $puesto = $false
        $lines = $lines | ForEach-Object {
            if ($_ -match "^Listen \d+") {
                if (-not $puesto) {
                    "Listen $Puerto"
                    $puesto = $true
                }
                # omitir las demas lineas Listen (no las retorna)
            } else {
                $_
            }
        }
        $lines | Set-Content $conf
    }
}

function Instalar-Apache-P7 {
    param([int]$Puerto, [string]$ArchivoZip = "", [string]$Version = "", [string]$Fuente = "WEB")

    $apacheBase = "C:\Apache24"

    # Usar la misma logica de busqueda de P6 para encontrar httpd.exe
    # sin importar donde lo haya instalado Chocolatey
    $apacheBase = Encontrar-Base-Apache-P7

    # Detectar si ya esta instalado
    if (Test-Path "$apacheBase\bin\httpd.exe") {
        $vOut = (& "$apacheBase\bin\httpd.exe" -v 2>&1) | Out-String
        if ($vOut -match "Apache/([0-9.]+)") {
            $vIns = $matches[1].Trim()
            Write-Host "  Apache ya instalado (v$vIns)." -ForegroundColor Yellow

            $confActual = Get-Content "$apacheBase\conf\httpd.conf" -Raw -ErrorAction SilentlyContinue
            $pActual = if ($confActual -match "(?m)^Listen (\d+)") { [int]$matches[1] } else { 80 }

            if ($pActual -ne $Puerto) {
                Write-Host "  Cambiando puerto $pActual -> $Puerto..." -ForegroundColor Cyan
                Configurar-Apache-Puerto -ApacheBase $apacheBase -Puerto $Puerto
                Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "Apache-HTTP-$Puerto"
                Restart-Service "Apache2.4" -ErrorAction SilentlyContinue
                Registrar-Resumen -Servicio "Apache" -Accion "Puerto-Cambiado" -Estado "OK" -Detalle "$pActual -> $Puerto"
                Write-Host "  Puerto actualizado a $Puerto." -ForegroundColor Green
            } else {
                Write-Host "  Puerto ya configurado en $Puerto." -ForegroundColor Green
            }
            # Siempre actualizar index con la fuente actual
            Crear-Index-HTML -Directorio "$apacheBase\htdocs" -Servicio "Apache" -Version $vIns -Puerto $Puerto -Fuente $Fuente
            return
        }
    }

    # Instalar
    if ($ArchivoZip) {
        $ok = Instalar-Desde-ZIP -Archivo $ArchivoZip -Servicio "Apache"
        if (-not $ok) { return }
    } else {
        Refrescar-PATH
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Host "  ERROR: Chocolatey no instalado. Use la opcion de dependencias primero." -ForegroundColor Red
            return
        }
        Write-Host "  Instalando Apache via Chocolatey (puede tardar varios minutos)..." -ForegroundColor Cyan

        # Instalar la version disponible actualmente en Chocolatey (sin fijar version)
        $chocoArgs = @(
            "install", "apache-httpd",
            "--params", "/installLocation:$apacheBase /noService",
            "--yes", "--no-progress", "--accept-license", "--force"
        )
        $chocoOut = & choco @chocoArgs 2>&1

        # Usar Encontrar-Base-Apache (igual que P6) para localizar httpd.exe
        # sin importar donde lo haya puesto Chocolatey
        $apacheBase = Encontrar-Base-Apache-P7

        if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
            Write-Host "  ERROR: httpd.exe no encontrado tras instalacion." -ForegroundColor Red
            Write-Host "  Ultimas lineas de Chocolatey:" -ForegroundColor Gray
            $chocoOut | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            return
        }
    }

    # Configurar puerto
    Configurar-Apache-Puerto -ApacheBase $apacheBase -Puerto $Puerto

    # Corregir ServerRoot si es necesario
    $confPath    = "$apacheBase\conf\httpd.conf"
    $confContent = Get-Content $confPath -Raw
    if ($confContent -match 'Define SRVROOT "([^"]+)"') {
        $srvrootActual = $matches[1]
        if ($srvrootActual -ne $apacheBase) {
            $confContent = $confContent -replace [regex]::Escape("Define SRVROOT `"$srvrootActual`""), "Define SRVROOT `"$apacheBase`""
            [System.IO.File]::WriteAllText($confPath, $confContent)
        }
    }

    $vOut    = (& "$apacheBase\bin\httpd.exe" -v 2>&1) | Out-String
    $version = if ($vOut -match "Apache/([0-9.]+)") { $matches[1] } else { "2.4" }

    Crear-Index-HTML -Directorio "$apacheBase\htdocs" -Servicio "Apache" -Version $version -Puerto $Puerto -Fuente $Fuente

    # Seguridad
    $secConf = "$apacheBase\conf\extra\httpd-security.conf"
    @"
ServerTokens Prod
ServerSignature Off
TraceEnable Off
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</IfModule>
<Directory "`${SRVROOT}/htdocs">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>
"@ | Set-Content $secConf -Encoding UTF8

    if (-not (Select-String -Path $confPath -Pattern "httpd-security.conf" -Quiet)) {
        Add-Content $confPath "`nInclude conf/extra/httpd-security.conf"
    }
    (Get-Content $confPath) -replace "#LoadModule headers_module", "LoadModule headers_module" | Set-Content $confPath

    & "$apacheBase\bin\httpd.exe" -k install 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    Start-Service "Apache2.4" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "Apache-HTTP-$Puerto"

    $test   = Test-NetConnection -ComputerName localhost -Port $Puerto -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }

    Registrar-Resumen -Servicio "Apache" -Accion "Instalacion" -Estado $estado -Detalle "v$version puerto $Puerto"
    Write-Host "  Apache instalado. v$version | Puerto: $Puerto | Estado: $estado" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
}

# ── Nginx ────────────────────────────────────────────────────────────────────

function Configurar-Nginx-Puerto {
    param([int]$Puerto, [string]$NginxBase = "C:\nginx")
    $confPath = "$NginxBase\conf\nginx.conf"
    $conf = @"
worker_processes  1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;
    server {
        listen $Puerto;
        server_name _;
        root html;
        location / { index index.html index.htm; }
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
    }
}
"@
    [System.IO.File]::WriteAllText($confPath, $conf, [System.Text.UTF8Encoding]::new($false))
}

function Instalar-Nginx-P7 {
    param(
        [int]$Puerto,
        [string]$ArchivoZip = "",
        [string]$Version = "1.24.0",
        [string]$Fuente = "WEB"
    )

    if (-not $Version -or $Version -eq "") {
        $Version = "1.24.0"
    }

    function Encontrar-Nginx {
        $candidatas = @("C:\nginx", "C:\tools\nginx")

        foreach ($r in $candidatas) {
            if (Test-Path "$r\nginx.exe") { return $r }
        }

        $enc = Get-ChildItem "C:\tools" -Filter "nginx.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($enc) { return $enc.DirectoryName }

        $enc = Get-ChildItem "C:\" -Filter "nginx.exe" -Recurse -Depth 5 -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($enc) { return $enc.DirectoryName }

        return $null
    }

    $nginxBase = Encontrar-Nginx

    # ───────── YA INSTALADO ─────────
    if ($nginxBase) {
        Write-Host "  Nginx ya instalado en $nginxBase" -ForegroundColor Yellow
        Configurar-Nginx-Puerto -Puerto $Puerto -NginxBase $nginxBase

        Remove-Item "$nginxBase\html\index.html" -ErrorAction SilentlyContinue
        Crear-Index-HTML `
            -Directorio "$nginxBase\html" `
            -Servicio "Nginx" `
            -Version $Version `
            -Puerto $Puerto `
            -Fuente $Fuente

        # 🔥 reiniciar para aplicar cambios
        Write-Host "  Reiniciando Nginx..." -ForegroundColor Cyan
        taskkill /f /im nginx.exe 2>$null
        Start-Sleep 1
        Start-Process "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase

        return
    }

    # ───────── INSTALACIÓN ─────────
    if ($ArchivoZip) {
        $ok = Instalar-Desde-ZIP -Archivo $ArchivoZip -Servicio "Nginx"
        if (-not $ok) {
            Write-Host "  ERROR: Fallo instalacion desde ZIP." -ForegroundColor Red
            return
        }

    } else {

        Refrescar-PATH
        $instalado = $false

        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "  Intentando instalar con Chocolatey..." -ForegroundColor Cyan

            $chocoOut = & choco install nginx --yes --no-progress --force 2>&1
            $chocoOut | Select-Object -Last 6 | ForEach-Object { Write-Host "    $_" }

            if ($chocoOut -match "failed" -or $chocoOut -match "error") {
                Write-Host "  Chocolatey fallo. Usando instalacion directa..." -ForegroundColor Yellow
                $instalado = $false
            } else {
                $instalado = $true
            }
        }

        if (-not $instalado) {

            $zipPath = "C:\tools\nginx.zip"
            $url = "https://nginx.org/download/nginx-$Version.zip"

            Write-Host "  Preparando directorio..." -ForegroundColor DarkGray

            if (-not (Test-Path "C:\tools")) {
                New-Item -ItemType Directory -Path "C:\tools" -Force | Out-Null
            }

            Write-Host "  Descargando Nginx desde: $url" -ForegroundColor Cyan

            try {
                curl.exe -L $url -o $zipPath

                if (-not (Test-Path $zipPath)) {
                    throw "Descarga fallida"
                }
            }
            catch {
                Write-Host "  ERROR: No se pudo descargar Nginx (curl)." -ForegroundColor Red
                return
            }

            Expand-Archive $zipPath -DestinationPath "C:\tools" -Force

            $extraido = "C:\tools\nginx-$Version"

            if (Test-Path $extraido) {
                Rename-Item $extraido "C:\tools\nginx" -ErrorAction SilentlyContinue
            } else {
                Write-Host "  ERROR: No se encontro carpeta extraida." -ForegroundColor Red
                return
            }
        }
    }

    # ───────── VALIDAR INSTALACIÓN ─────────
    $nginxBase = Encontrar-Nginx

    if (-not $nginxBase) {
        Write-Host "  ERROR: nginx.exe no encontrado tras la instalacion." -ForegroundColor Red
        return
    }

    Write-Host "  Nginx instalado en: $nginxBase" -ForegroundColor Green

    # 🔥 CREAR INDEX PERSONALIZADO
    Remove-Item "$nginxBase\html\index.html" -ErrorAction SilentlyContinue
    Crear-Index-HTML `
        -Directorio "$nginxBase\html" `
        -Servicio "Nginx" `
        -Version $Version `
        -Puerto $Puerto `
        -Fuente $Fuente

    # ───────── CONFIGURAR ─────────
    Configurar-Nginx-Puerto -Puerto $Puerto -NginxBase $nginxBase
    Abrir-Puerto-Firewall -Puerto $Puerto -Nombre "Nginx-HTTP-$Puerto"

    # 🔥 INICIO LIMPIO (FIX FINAL)
    Write-Host "  Iniciando Nginx..." -ForegroundColor Cyan
    taskkill /f /im nginx.exe 2>$null
    Start-Sleep 1
    Start-Process "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase
    Start-Sleep 2

    $test = Test-NetConnection localhost -Port $Puerto -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }

    Write-Host "  Nginx | Puerto $Puerto | Estado: $estado" `
        -ForegroundColor $(if ($estado -eq "OK") { "Green" } else { "Yellow" })
}

function Flujo-Instalar-Servicio {
    param([string]$Servicio)
    Escribir-Titulo "INSTALAR $($Servicio.ToUpper())"

    # Elegir fuente
    Write-Host "  Fuente de instalacion:"
    Write-Host "    1) WEB - Repositorio oficial (Chocolatey / descarga directa)"
    Write-Host "    2) FTP - Repositorio privado (requiere repositorio preparado)"
    Write-Host ""
    $fuente = Leer-Opcion -Prompt "  Seleccione fuente [1/2]" -Validas @("1","2")

    $archivoZip   = ""
    $versionEleg  = ""
    $servicioReal = $Servicio

    if ($fuente -eq "1") {
        # ── WEB: instalar la version disponible en Chocolatey directamente ────
        # No se solicita version especifica para evitar errores por paquetes
        # que ya no estan disponibles en el repositorio de Chocolatey.
        switch ($Servicio) {
            "IIS"    { Write-Host "" ; Write-Host "  Nota: IIS es un rol de Windows. La version depende del OS." -ForegroundColor Yellow }
            "Apache" { Write-Host "" ; Write-Host "  Se instalara la version disponible de Apache en Chocolatey." -ForegroundColor Cyan }
            "Nginx"  { Write-Host "" ; Write-Host "  Se instalara la version disponible de Nginx en Chocolatey."  -ForegroundColor Cyan }
        }
        $versionEleg = ""   # sin version fija: Chocolatey elige la ultima disponible
    } else {
        # ── FTP: navegar repositorio y descargar ──────────────────────────────
        $resultado = Navegar-Y-Descargar-FTP -ServicioForzado $Servicio
        if (-not $resultado) { Write-Host "  Instalacion cancelada." -ForegroundColor Red; return }
        $archivoZip   = $resultado.Archivo
        $servicioReal = $resultado.Servicio
        Write-Host "  Servicio a instalar: $servicioReal" -ForegroundColor Cyan
        if ($servicioReal -eq "IIS") {
            Write-Host "  Nota: IIS es un rol de Windows. El placeholder fue verificado via SHA256." -ForegroundColor Yellow
            Write-Host "        Se procedera a instalar/activar el rol IIS normalmente." -ForegroundColor Yellow
        }
    }

    # Puerto sugerido segun el servicio
    $sugeridos = switch ($servicioReal) {
        "IIS"    { @(80, 8080, 8181, 8282) }
        "Apache" { @(8080, 80, 8181, 8282) }
        "Nginx"  { @(8181, 8080, 80, 8282) }
        default  { @(8080, 8181, 8282) }
    }
    $puertoSugerido = Detectar-Puerto-Libre -Sugeridos $sugeridos
    Write-Host ""
    $puerto = Leer-Puerto -Prompt "  Puerto de escucha (sugerido: $puertoSugerido)" -Default $puertoSugerido

    switch ($servicioReal) {
        "IIS"    { Instalar-IIS-P7    -Puerto $puerto -Fuente $(if($archivoZip){"FTP"}else{"WEB"}) }
        "Apache" { Instalar-Apache-P7 -Puerto $puerto -ArchivoZip $archivoZip -Version $versionEleg -Fuente $(if($archivoZip){"FTP"}else{"WEB"}) }
        "Nginx"  { Instalar-Nginx-P7  -Puerto $puerto -ArchivoZip $archivoZip -Version $versionEleg -Fuente $(if($archivoZip){"FTP"}else{"WEB"}) }
        default  { Write-Host "  Servicio '$servicioReal' no reconocido." -ForegroundColor Yellow }
    }
}

# ================================================================
# SECCION 6 - SSL/TLS (35% de la nota)
# ================================================================

function Gestionar-Servicios-HTTP {
    Escribir-Titulo "GESTIONAR SERVICIOS HTTP"

    Write-Host "  Estado actual:" -ForegroundColor Cyan
    Write-Host ""

    # IIS
    $iisOk = (Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue).Installed
    $iisEst = if ($iisOk) {
        $svc = Get-Service W3SVC -ErrorAction SilentlyContinue
        if ($svc.Status -eq "Running") { "ACTIVO" } else { "DETENIDO" }
    } else { "NO INSTALADO" }

    # Apache
    $apacheBase = Encontrar-Base-Apache-P7
    $apacheEst = if (Test-Path "$apacheBase\bin\httpd.exe") {
        $svc = Get-Service "Apache2.4" -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") { "ACTIVO" } else { "DETENIDO" }
    } else { "NO INSTALADO" }

    # Nginx
    $nginxProc = Get-Process nginx -ErrorAction SilentlyContinue
    $nginxEst = if (Test-Path "C:\nginx\nginx.exe") {
        if ($nginxProc) { "ACTIVO" } else { "DETENIDO" }
    } else { "NO INSTALADO" }

    # FTP
    $ftpSvc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    $ftpEst = if ($ftpSvc) {
        if ($ftpSvc.Status -eq "Running") { "ACTIVO" } else { "DETENIDO" }
    } else { "NO INSTALADO" }

    Write-Host ("    {0,-10} {1}" -f "IIS",    $iisEst)    -ForegroundColor $(if($iisEst -eq "ACTIVO"){"Green"}elseif($iisEst -eq "DETENIDO"){"Yellow"}else{"DarkGray"})
    Write-Host ("    {0,-10} {1}" -f "Apache", $apacheEst) -ForegroundColor $(if($apacheEst -eq "ACTIVO"){"Green"}elseif($apacheEst -eq "DETENIDO"){"Yellow"}else{"DarkGray"})
    Write-Host ("    {0,-10} {1}" -f "Nginx",  $nginxEst)  -ForegroundColor $(if($nginxEst -eq "ACTIVO"){"Green"}elseif($nginxEst -eq "DETENIDO"){"Yellow"}else{"DarkGray"})
    Write-Host ("    {0,-10} {1}" -f "FTP",    $ftpEst)    -ForegroundColor $(if($ftpEst -eq "ACTIVO"){"Green"}elseif($ftpEst -eq "DETENIDO"){"Yellow"}else{"DarkGray"})
    Write-Host ""
    Write-Host "  Acciones:" -ForegroundColor Yellow
    Write-Host "    1) Detener IIS"
    Write-Host "    2) Iniciar IIS"
    Write-Host "    3) Detener Apache"
    Write-Host "    4) Iniciar Apache"
    Write-Host "    5) Detener Nginx"
    Write-Host "    6) Iniciar Nginx"
    Write-Host "    7) Detener FTP"
    Write-Host "    8) Iniciar FTP"
    Write-Host "    9) Detener TODOS (para demostrar un servicio a la vez)"
    Write-Host "    0) Volver"
    Write-Host ""

    $op = Leer-Opcion -Prompt "  Seleccione" -Validas @("0","1","2","3","4","5","6","7","8","9")

    switch ($op) {
        "1" {
            Write-Host "  Deteniendo IIS..." -ForegroundColor Yellow
            iisreset /stop | Out-Null
            Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
            Write-Host "  IIS detenido." -ForegroundColor Green
            Registrar-Resumen -Servicio "IIS" -Accion "Detenido" -Estado "OK"
        }
        "2" {
            Write-Host "  Iniciando IIS..." -ForegroundColor Cyan
            Start-Service W3SVC -ErrorAction SilentlyContinue
            iisreset /start | Out-Null
            Start-Sleep -Seconds 2
            Write-Host "  IIS iniciado." -ForegroundColor Green
            Registrar-Resumen -Servicio "IIS" -Accion "Iniciado" -Estado "OK"
        }
        "3" {
            Write-Host "  Deteniendo Apache..." -ForegroundColor Yellow
            Stop-Service "Apache2.4" -Force -ErrorAction SilentlyContinue
            Get-Process httpd -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Host "  Apache detenido." -ForegroundColor Green
            Registrar-Resumen -Servicio "Apache" -Accion "Detenido" -Estado "OK"
        }
        "4" {
            Write-Host "  Iniciando Apache..." -ForegroundColor Cyan
            Start-Service "Apache2.4" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Write-Host "  Apache iniciado." -ForegroundColor Green
            Registrar-Resumen -Servicio "Apache" -Accion "Iniciado" -Estado "OK"
        }
        "5" {
            Write-Host "  Deteniendo Nginx..." -ForegroundColor Yellow
            taskkill /f /im nginx.exe 2>&1 | Out-Null
            Write-Host "  Nginx detenido." -ForegroundColor Green
            Registrar-Resumen -Servicio "Nginx" -Accion "Detenido" -Estado "OK"
        }
        "6" {
            Write-Host "  Iniciando Nginx..." -ForegroundColor Cyan
            $nginxBase = "C:\nginx"
            if (Test-Path "$nginxBase\nginx.exe") {

                Start-Process -FilePath "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase -WindowStyle Hidden


                Start-Sleep -Seconds 2
                Write-Host "  Nginx iniciado." -ForegroundColor Green
                Registrar-Resumen -Servicio "Nginx" -Accion "Iniciado" -Estado "OK"
            } else {
                Write-Host "  ERROR: Nginx no instalado." -ForegroundColor Red
            }
        }
        "7" {
            Write-Host "  Deteniendo FTP..." -ForegroundColor Yellow
            Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
            Write-Host "  FTP detenido." -ForegroundColor Green
        }
        "8" {
            Write-Host "  Iniciando FTP..." -ForegroundColor Cyan
            Start-Service ftpsvc -ErrorAction SilentlyContinue
            Write-Host "  FTP iniciado." -ForegroundColor Green
        }
        "9" {
            Write-Host ""
            Write-Host "  Deteniendo TODOS los servicios HTTP..." -ForegroundColor Yellow
            iisreset /stop 2>&1 | Out-Null
            Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
            Stop-Service "Apache2.4" -Force -ErrorAction SilentlyContinue
            Get-Process httpd  -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            taskkill /f /im nginx.exe 2>&1 | Out-Null
            Write-Host "  Todos los servicios HTTP detenidos." -ForegroundColor Green
            Write-Host "  Ahora puede iniciar el servicio que desea demostrar (opciones 2, 4 o 6)." -ForegroundColor Cyan
        }
    }
}

# ================================================================
# SECCION 8 - ESTADO Y RESUMEN (evidencias para el profesor)
# ================================================================

function Ver-Estado-Servicios {
    Escribir-Titulo "ESTADO DE SERVICIOS"

    # Detectar puertos reales de cada servicio
    $puertoIIS = 80
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $b = Get-WebBinding -Name "Default Web Site" -Protocol "http" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($b) { $puertoIIS = [int]($b.bindingInformation -split ":")[-2] }
    } catch {}

    $puertoApache = 8080
    try {
        $apacheBase = Encontrar-Base-Apache-P7
        $confApache = Get-Content "$apacheBase\conf\httpd.conf" -Raw -ErrorAction SilentlyContinue
        if ($confApache -match "(?m)^Listen (\d+)") { $puertoApache = [int]$matches[1] }
    } catch {}

    $puertoNginx = 8181
    try {
        $confNginx = Get-Content "C:\nginx\conf\nginx.conf" -Raw -ErrorAction SilentlyContinue
        if ($confNginx -match "listen\s+(\d+)") { $puertoNginx = [int]$matches[1] }
    } catch {}

    $checks = @(
        @{ Nombre = "IIS HTTP    "; Puerto = $puertoIIS   },
        @{ Nombre = "IIS HTTPS   "; Puerto = 443          },
        @{ Nombre = "Apache HTTP "; Puerto = $puertoApache },
        @{ Nombre = "Apache HTTPS"; Puerto = 443          },
        @{ Nombre = "Nginx HTTP  "; Puerto = $puertoNginx  },
        @{ Nombre = "Nginx HTTPS "; Puerto = 443          },
        @{ Nombre = "FTP         "; Puerto = 21           },
        @{ Nombre = "FTPS        "; Puerto = 990          }
    )

    Write-Host ("  {0,-16} {1,-8} {2}" -f "Servicio","Puerto","Estado") -ForegroundColor Cyan
    Write-Host ("  {0,-16} {1,-8} {2}" -f "--------","------","------") -ForegroundColor DarkGray

    foreach ($c in $checks) {
        $test   = Test-NetConnection -ComputerName localhost -Port $c.Puerto -WarningAction SilentlyContinue
        $estado = if ($test.TcpTestSucceeded) { "ACTIVO  " } else { "INACTIVO" }
        $color  = if ($test.TcpTestSucceeded) { "Green" } else { "DarkGray" }
        Write-Host ("  {0,-16} {1,-8} {2}" -f $c.Nombre, $c.Puerto, $estado) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  Certificados SSL instalados (P7):" -ForegroundColor Cyan
    $certs = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -like "P7-SSL*" }
    if ($certs) {
        $certs | ForEach-Object {
            Write-Host ("    Sujeto: {0,-40} Expira: {1}" -f $_.Subject, $_.NotAfter) -ForegroundColor Gray
        }
    } else {
        Write-Host "    (No hay certificados P7 instalados aun)" -ForegroundColor DarkGray
    }
}

function Mostrar-Resumen-Final {
    Escribir-Titulo "RESUMEN FINAL - PRACTICA 7"

    if ($global:RESUMEN.Count -eq 0) {
        Write-Host "  No hay acciones registradas aun." -ForegroundColor Yellow
        Ver-Estado-Servicios
        return
    }

    $global:RESUMEN | Format-Table -AutoSize -Property Servicio, Accion, Estado, Detalle

    $ok  = ($global:RESUMEN | Where-Object { $_.Estado -eq "OK" }).Count
    $adv = ($global:RESUMEN | Where-Object { $_.Estado -eq "ADVERTENCIA" }).Count
    $err = ($global:RESUMEN | Where-Object { $_.Estado -eq "ERROR" }).Count

    Write-Host ("  OK          : {0}" -f $ok)  -ForegroundColor Green
    Write-Host ("  ADVERTENCIA : {0}" -f $adv) -ForegroundColor Yellow
    Write-Host ("  ERROR       : {0}" -f $err) -ForegroundColor Red

    Ver-Estado-Servicios

    Write-Host ""
    Write-Host "  Comandos para verificar SSL desde cliente (evidencias):" -ForegroundColor Cyan
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
    Write-Host "    # Verificar HTTPS - IIS / Apache / Nginx:" -ForegroundColor DarkGray
    Write-Host "    curl -k -I https://$ip" -ForegroundColor Gray
    Write-Host "    openssl s_client -connect ${ip}:443 -servername $($global:DOMINIO_SSL)" -ForegroundColor Gray
    Write-Host "    # Verificar FTPS:" -ForegroundColor DarkGray
    Write-Host "    openssl s_client -connect ${ip}:990" -ForegroundColor Gray
}