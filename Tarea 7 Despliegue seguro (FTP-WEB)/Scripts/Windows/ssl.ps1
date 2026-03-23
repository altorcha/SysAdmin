# ============================================================
# ssl.ps1
# Practica 7 - SSL/TLS - Certificados y HTTPS
# Windows Server 2019/2022 - PowerShell
# ============================================================

. "$PSScriptRoot\globals.ps1"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\utilidades.ps1"

function Pedir-Dominio {
    if ($global:DOMINIO_SSL) {
        $cambiar = Leer-Opcion -Prompt "  Dominio actual: '$($global:DOMINIO_SSL)' ¿Cambiar? [S/N]" -Validas @("S","N","s","n")
        if ($cambiar -match "^[Ss]$") {
            $global:DOMINIO_SSL = Leer-Texto -Prompt "  Nuevo dominio SSL"
        }
    } else {
        $global:DOMINIO_SSL = Leer-Texto -Prompt "  Dominio para el certificado" -Default "www.reprobados.com"
    }
    return $global:DOMINIO_SSL
}

function Generar-Certificado-Windows {
    param([string]$Dominio)

    # Verificar si ya existe un certificado valido con O=Practica7
    $certExistente = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -like "*$Dominio*" -and $_.Subject -like "*Practica7*" -and $_.NotAfter -gt (Get-Date) } |
        Select-Object -First 1

    if ($certExistente) {
        Write-Host "  Certificado para '$Dominio' ya existe y es valido." -ForegroundColor Green
        Write-Host "    Thumbprint : $($certExistente.Thumbprint)" -ForegroundColor Gray
        Write-Host "    Expira     : $($certExistente.NotAfter)"   -ForegroundColor Gray
        return $certExistente.Thumbprint
    }

    Write-Host "  Generando certificado con OpenSSL para '$Dominio'..." -ForegroundColor Cyan

    # Eliminar certificados anteriores del dominio
    Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$Dominio*" } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # Usar OpenSSL igual que Linux: incluye CN, O y OU
    $sslDir = "C:\Apache24\conf\ssl"
    New-Item -ItemType Directory -Force -Path $sslDir | Out-Null
    $keyFile = "$sslDir\server_temp.key"
    $crtFile = "$sslDir\server_temp.crt"
    $pfxFile = "$sslDir\server_temp.pfx"
    $pfxPass = "P7SSL2024"

    & openssl req -x509 -nodes -days 365 -newkey rsa:2048 `
        -keyout $keyFile `
        -out $crtFile `
        -subj "/CN=$Dominio/O=Practica7/OU=SSL" 2>$null

    if (-not (Test-Path $crtFile)) {
        Write-Host "  OpenSSL fallo, usando New-SelfSignedCertificate como fallback..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate `
            -DnsName $Dominio `
            -CertStoreLocation "Cert:\LocalMachine\My" `
            -NotAfter (Get-Date).AddDays(365) `
            -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
            -FriendlyName "P7-SSL-$Dominio" `
            -Subject "CN=$Dominio, O=Practica7, OU=SSL"
        Registrar-Resumen -Servicio $Dominio -Accion "Cert-Generado" -Estado "OK" -Detalle $cert.Thumbprint
        return $cert.Thumbprint
    }

    # Convertir PEM a PFX e importar al store de Windows
    $secPw = ConvertTo-SecureString $pfxPass -AsPlainText -Force
    & openssl pkcs12 -export -in $crtFile -inkey $keyFile -out $pfxFile `
        -passout "pass:$pfxPass" -name "P7-SSL-$Dominio" 2>$null

    $cert = Import-PfxCertificate -FilePath $pfxFile `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -Password $secPw -Exportable

    Remove-Item $pfxFile -Force -ErrorAction SilentlyContinue

    Write-Host "  Certificado generado:" -ForegroundColor Green
    Write-Host "    Thumbprint : $($cert.Thumbprint)" -ForegroundColor Gray
    Write-Host "    Sujeto     : $($cert.Subject)"    -ForegroundColor Gray
    Write-Host "    Expira     : $($cert.NotAfter)"   -ForegroundColor Gray
    Registrar-Resumen -Servicio $Dominio -Accion "Cert-Generado" -Estado "OK" -Detalle $cert.Thumbprint
    return $cert.Thumbprint
}

function Exportar-Cert-A-PEM {
    param([string]$Thumbprint, [string]$Dir)
    if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
        Write-Host "  ERROR: OpenSSL no instalado. Instale las dependencias primero (opcion 1)." -ForegroundColor Red
        return $false
    }
    New-Item $Dir -ItemType Directory -Force | Out-Null
    $pfxPath  = "$Dir\cert.pfx"
    $pfxPass  = "P7Temp2024!"
    $secPw    = ConvertTo-SecureString $pfxPass -AsPlainText -Force
    Export-PfxCertificate -Cert "Cert:\LocalMachine\My\$Thumbprint" -FilePath $pfxPath -Password $secPw | Out-Null
    & openssl pkcs12 -in $pfxPath -clcerts -nokeys -out "$Dir\server.crt" -password "pass:$pfxPass" 2>&1 | Out-Null
    & openssl pkcs12 -in $pfxPath -nocerts -nodes  -out "$Dir\server.key" -password "pass:$pfxPass" 2>&1 | Out-Null
    if ((Test-Path "$Dir\server.crt") -and (Test-Path "$Dir\server.key")) {
        Write-Host "  Exportado a PEM: $Dir\server.crt / server.key" -ForegroundColor Green
        return $true
    }
    Write-Host "  ERROR: No se pudieron exportar los archivos PEM." -ForegroundColor Red
    return $false
}

function Activar-SSL-IIS {
    Escribir-Titulo "ACTIVAR SSL/TLS EN IIS"
    if (-not (Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue).Installed) {
        Write-Host "  ERROR: IIS no instalado. Instale IIS primero." -ForegroundColor Red; return
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Detectar puerto HTTP actual de IIS
    $puertoHTTP = Obtener-Puerto-IIS-P7
    Write-Host "  Puerto HTTP actual de IIS: $puertoHTTP" -ForegroundColor Cyan

    # Sugerir puerto HTTPS = puerto HTTP + 1
    $puertoHTTPSSugerido = $puertoHTTP + 1
    $puertoHTTPS = Leer-Puerto -Prompt "  Puerto HTTPS para IIS (sugerido: $puertoHTTPSSugerido)" -Default $puertoHTTPSSugerido

    $dominio = Pedir-Dominio
    $thumb   = Generar-Certificado-Windows -Dominio $dominio

    try {
        # Eliminar todos los bindings HTTPS anteriores para evitar conflictos
        Get-WebBinding -Name "Default Web Site" -Protocol "https" -ErrorAction SilentlyContinue |
            Remove-WebBinding -ErrorAction SilentlyContinue

        # Eliminar SslBindings del puerto HTTPS elegido si ya existe
        $bp = "IIS:\SslBindings\0.0.0.0!$puertoHTTPS"
        if (Test-Path $bp) { Remove-Item $bp -Force }

        New-WebBinding -Name "Default Web Site" -Protocol "https" -Port $puertoHTTPS -IPAddress "*" -SslFlags 0 | Out-Null
        Get-Item "Cert:\LocalMachine\My\$thumb" | New-Item $bp | Out-Null
        Write-Host "  Binding HTTPS:$puertoHTTPS configurado en IIS." -ForegroundColor Green
    } catch {
        Write-Host "  ERROR configurando HTTPS en IIS: $($_.Exception.Message)" -ForegroundColor Red
        Registrar-Resumen -Servicio "IIS" -Accion "SSL-$puertoHTTPS" -Estado "ERROR" -Detalle $_.Exception.Message
        return
    }

    # Cabeceras HSTS en web.config (sin URL Rewrite para evitar error 500)
    @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <httpProtocol>
      <customHeaders>
        <add name="Strict-Transport-Security" value="max-age=31536000; includeSubDomains" />
        <add name="X-Frame-Options" value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@ | Set-Content "C:\inetpub\wwwroot\web.config" -Encoding UTF8

    Abrir-Puerto-Firewall -Puerto $puertoHTTPS -Nombre "IIS-HTTPS-$puertoHTTPS"
    iisreset /restart | Out-Null
    Start-Sleep -Seconds 3

    $test   = Test-NetConnection -ComputerName localhost -Port $puertoHTTPS -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }
    Write-Host "  IIS HTTPS $puertoHTTPS`: $estado | Dominio: $dominio" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
    Write-Host "  Acceso: https://$($(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress):$puertoHTTPS" -ForegroundColor Gray
    Registrar-Resumen -Servicio "IIS" -Accion "SSL-$puertoHTTPS" -Estado $estado -Detalle "Dominio: $dominio | Thumb: $thumb"
}

function Activar-SSL-Apache {
    Escribir-Titulo "ACTIVAR SSL/TLS EN APACHE"

    $apacheBase = Encontrar-Base-Apache-P7
    if (-not (Test-Path "$apacheBase\bin\httpd.exe")) {
        Write-Host "  ERROR: Apache no encontrado." -ForegroundColor Red
        return
    }

    $httpdConf = "$apacheBase\conf\httpd.conf"
    $sslConf   = "$apacheBase\conf\extra\httpd-ssl.conf"

    # Detectar puerto HTTP
    $confActual = Get-Content $httpdConf -Raw
    $pHttp = if ($confActual -match "(?m)^Listen (\d+)") { [int]$matches[1] } else { 80 }

    Write-Host "  Puerto HTTP actual: $pHttp" -ForegroundColor Cyan

    $puertoHTTPS = Leer-Puerto -Prompt "  Puerto HTTPS" -Default ($pHttp + 1)

    $dominio = Pedir-Dominio
    $thumb   = Generar-Certificado-Windows -Dominio $dominio

    $sslDir = "$apacheBase\conf\ssl"
    if (-not (Exportar-Cert-A-PEM -Thumbprint $thumb -Dir $sslDir)) { return }

    $sslFwd = $sslDir -replace '\\','/'

    $conf = $confActual
    foreach ($mod in @("mod_ssl.so","mod_socache_shmcb.so","mod_rewrite.so","mod_headers.so")) {
        $conf = $conf -replace "#(LoadModule\s+\S+\s+modules/$mod)",'$1'
    }
    $conf = $conf -replace "#(Include conf/extra/httpd-ssl.conf)",'$1'
    [System.IO.File]::WriteAllText($httpdConf, $conf)

    @"
SSLPassPhraseDialog builtin
SSLSessionCache "shmcb:$($apacheBase -replace '\\','/')/logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost *:$puertoHTTPS>
    ServerName $dominio
    DocumentRoot "$($apacheBase -replace '\\','/')/htdocs"

    SSLEngine on
    SSLCertificateFile "$sslFwd/server.crt"
    SSLCertificateKeyFile "$sslFwd/server.key"

    Header always set Strict-Transport-Security "max-age=31536000"
</VirtualHost>

<VirtualHost *:$pHttp>
    ServerName $dominio
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}:$puertoHTTPS`$1 [R=301,L]
</VirtualHost>
"@ | Set-Content $sslConf -Encoding UTF8

    $lines = Get-Content $httpdConf | Where-Object { $_ -notmatch "^\s*Listen\s+\d+" }

    # Agregar solo los correctos
    $lines += "Listen $pHttp"
    $lines += "Listen $puertoHTTPS"

    $lines | Set-Content $httpdConf

    Write-Host "  Puertos configurados: $pHttp y $puertoHTTPS" -ForegroundColor Green

    # Validar config
    $apacheExe = "$apacheBase\bin\httpd.exe"
    $test = & $apacheExe -t 2>&1

    if ($test -notmatch "Syntax OK") {
        Write-Host "ERROR en Apache:" -ForegroundColor Red
        Write-Host $test
        return
    }

    Restart-Service Apache2.4 -ErrorAction SilentlyContinue

    Write-Host "  Apache HTTPS OK en puerto $puertoHTTPS" -ForegroundColor Green
}

function Obtener-NginxPath {
    $rutas = @("C:\nginx","C:\tools","C:\Program Files")

    foreach ($ruta in $rutas) {
        $candidato = Get-ChildItem $ruta -Directory -Filter "nginx*" -ErrorAction SilentlyContinue |
                     Where-Object { Test-Path "$($_.FullName)\nginx.exe" } |
                     Select-Object -First 1
        if ($candidato) { return $candidato.FullName }
    }

    return $null
}

function Activar-SSL-Nginx {
    Escribir-Titulo "ACTIVAR SSL/TLS EN NGINX"

    $nginxBase = Obtener-NginxPath

    if (-not $nginxBase) {
        Write-Host "ERROR: Nginx no encontrado." -ForegroundColor Red
        return
    }

    Write-Host "  Nginx detectado en: $nginxBase" -ForegroundColor Green

    $confPath = "$nginxBase\conf\nginx.conf"
    $confAct  = Get-Content $confPath -Raw -ErrorAction SilentlyContinue

    # Detectar puerto HTTP actual
    $pHttp = if ($confAct -match "listen\s+(\d+)") { [int]$matches[1] } else { 80 }

    # Puerto HTTPS
    $puertoHTTPS = Leer-Puerto -Prompt "Puerto HTTPS" -Default ($pHttp + 1)

    # Certificado
    $dominio = Pedir-Dominio
    $thumb   = Generar-Certificado-Windows -Dominio $dominio

    $sslDir = "$nginxBase\ssl"
    if (-not (Exportar-Cert-A-PEM -Thumbprint $thumb -Dir $sslDir)) { return }

    $sslFwd = $sslDir -replace '\\','/'

    # ───────── CONFIGURACIÓN NGINX ─────────
    $conf = @"
worker_processes  1;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;

    # HTTP → HTTPS
    server {
        listen 0.0.0.0:$pHttp;
        server_name $dominio;
        return 301 https://`$host:$puertoHTTPS`$request_uri;
    }

    # HTTPS
    server {
        listen 0.0.0.0:$puertoHTTPS ssl;
        server_name $dominio;

        root html;

        ssl_certificate     $sslFwd/server.crt;
        ssl_certificate_key $sslFwd/server.key;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";

        location / {
            index index.html index.htm;
        }
    }
}
"@

    # Guardar SIN BOM (CRÍTICO)
    [System.IO.File]::WriteAllText(
        $confPath,
        $conf,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "  Configuración SSL escrita correctamente" -ForegroundColor Cyan

    # ───────── VALIDAR CONFIG ─────────
    Write-Host "  Validando configuración..." -ForegroundColor Cyan
    $test = & "$nginxBase\nginx.exe" -t 2>&1

    if ($test -match "successful") {
        Write-Host "  Configuración válida" -ForegroundColor Green
    } else {
        Write-Host "  ERROR en configuración:" -ForegroundColor Red
        $test | ForEach-Object { Write-Host "    $_" }
        return
    }


    Write-Host "  Abriendo puerto en firewall ($puertoHTTPS)..." -ForegroundColor Cyan

    New-NetFirewallRule `
        -DisplayName "Nginx-HTTPS-$puertoHTTPS" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $puertoHTTPS `
        -Action Allow `
        -ErrorAction SilentlyContinue | Out-Null

    # ───────── REINICIAR NGINX ─────────
    Write-Host "  Reiniciando Nginx..." -ForegroundColor Cyan
    taskkill /f /im nginx.exe 2>$null
    Start-Sleep 1

    Start-Process "$nginxBase\nginx.exe" -WorkingDirectory $nginxBase
    Start-Sleep 2

    # ───────── VALIDACIÓN FINAL ─────────
    $testConn = Test-NetConnection localhost -Port $puertoHTTPS -WarningAction SilentlyContinue
    $estado = if ($testConn.TcpTestSucceeded) { "OK" } else { "FALLO" }

    Write-Host "  Nginx HTTPS $puertoHTTPS`: $estado" `
        -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Red"})
}

function Activar-FTPS-IIS {
    Escribir-Titulo "ACTIVAR FTPS EN IIS-FTP"
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $sitioFTP = "FTP_SERVER"
    if (-not (Get-WebSite -Name $sitioFTP -ErrorAction SilentlyContinue)) {
        Write-Host "  ERROR: Sitio FTP '$sitioFTP' no encontrado." -ForegroundColor Red
        Write-Host "  Ejecute primero ftp.ps1 (Practica 5)." -ForegroundColor Yellow; return
    }
    $dominio = Pedir-Dominio
    $thumb   = Generar-Certificado-Windows -Dominio $dominio

    $appcmd = "C:\Windows\System32\inetsrv\appcmd.exe"
    & $appcmd set config $sitioFTP `
        -section:system.ftpServer/security/ssl `
        /serverCertHash:$thumb `
        /controlChannelPolicy:"SslRequire" `
        /dataChannelPolicy:"SslRequire" `
        /commit:apphost 2>&1 | Out-Null

    Abrir-Puerto-Firewall -Puerto 990 -Nombre "FTPS-990"
    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $test   = Test-NetConnection -ComputerName localhost -Port 21 -WarningAction SilentlyContinue
    $estado = if ($test.TcpTestSucceeded) { "OK" } else { "ADVERTENCIA" }
    Write-Host "  FTPS configurado: $estado | Dominio: $dominio" -ForegroundColor $(if($estado -eq "OK"){"Green"}else{"Yellow"})
    Registrar-Resumen -Servicio "IIS-FTP" -Accion "FTPS-SSL" -Estado $estado -Detalle "Dominio: $dominio | Thumb: $thumb"
}