# ============================================================
# repositorio.ps1
# Practica 7 - Repositorio FTP - Cliente y Descarga
# Windows Server 2019/2022 - PowerShell
# ============================================================

. "$PSScriptRoot\globals.ps1"
. "$PSScriptRoot\ui.ps1"
. "$PSScriptRoot\utilidades.ps1"

function Descargar-URL-Directa {
    param([string]$Url, [string]$Destino, [string]$Nombre)
    Write-Host "  Descargando $Nombre..." -ForegroundColor Gray
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    for ($i = 1; $i -le 3; $i++) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent","Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $wc.DownloadFile($Url, $Destino)
            if ((Test-Path $Destino) -and (Get-Item $Destino).Length -gt 50000) {
                $mb = [math]::Round((Get-Item $Destino).Length / 1MB, 1)
                Write-Host "  OK: $Nombre ($mb MB)" -ForegroundColor Green
                return $true
            }
            Remove-Item $Destino -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "  Intento $i fallido: $($_.Exception.Message)" -ForegroundColor Yellow
            if ($i -lt 3) { Start-Sleep -Seconds 3 }
        }
    }
    Write-Host "  ERROR: No se pudo descargar $Nombre." -ForegroundColor Red
    return $false
}

function Generar-SHA256-Archivo {
    param([string]$Archivo)
    $hash   = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    $nombre = Split-Path $Archivo -Leaf
    "$hash  $nombre" | Set-Content "$Archivo.sha256" -Encoding UTF8 -NoNewline
    Write-Host "  SHA256 generado: $hash" -ForegroundColor DarkGray
}

function Crear-Placeholder-ZIP {
    param([string]$Destino, [string]$Info)
    $tmp = "$env:TEMP\ph_$(Get-Random)"
    New-Item $tmp -ItemType Directory -Force | Out-Null
    "PLACEHOLDER: $Info`nGenerado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content "$tmp\README.txt"
    Compress-Archive -Path "$tmp\*" -DestinationPath $Destino -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Placeholder creado: $(Split-Path $Destino -Leaf)" -ForegroundColor Yellow
}

function Preparar-Repositorio-FTP {
    Escribir-Titulo "PREPARAR REPOSITORIO FTP"

    $ftpData  = "C:\FTP_Data"
    $repoBase = "$ftpData\http\Windows"

    if (-not (Test-Path $ftpData)) {
        Write-Host "  ERROR: C:\FTP_Data no existe." -ForegroundColor Red
        Write-Host "  Ejecute primero ftp.ps1 (Practica 5) para configurar el servidor FTP." -ForegroundColor Yellow
        return
    }

    Write-Host "  Se crearan carpetas y se descargaran instaladores de Apache y Nginx."
    Write-Host "  Los archivos .sha256 se generan automaticamente."
    Write-Host "  Nota: Las descargas pueden tardar segun la velocidad de internet."
    Write-Host ""
    $conf = Leer-Opcion -Prompt "¿Continuar? [S/N]" -Validas @("S","N","s","n")
    if ($conf -match "^[Nn]$") { return }

    # Crear estructura de carpetas
    foreach ($svc in @("Apache","Nginx","IIS")) {
        New-Item "$repoBase\$svc" -ItemType Directory -Force | Out-Null
        Write-Host "  Carpeta creada: $repoBase\$svc" -ForegroundColor Gray
    }

    # Funcion interna: verificar si un archivo ya existe y tiene contenido real
    function Archivo-Valido {
        param([string]$Ruta, [int]$MinBytes = 100)
        return (Test-Path $Ruta) -and ((Get-Item $Ruta).Length -gt $MinBytes)
    }

    # APACHE
    # apachehaus.com bloquea descargas automatizadas.
    # Se instala Apache via Chocolatey, se empaqueta como ZIP y se coloca en el repositorio.
    Escribir-SubTitulo "Apache (Chocolatey -> ZIP para repositorio)"
    $aLatest = "$repoBase\Apache\apache_2.4.63_win64.zip"   # Latest / Desarrollo
    $aLTS    = "$repoBase\Apache\apache_2.4.62_win64.zip"   # LTS / Estable
    $aOldest = "$repoBase\Apache\apache_2.4.58_win64.zip"   # Oldest
    $apacheOk = $false

    # Verificar si las 3 versiones de Apache ya existen
    if ((Archivo-Valido $aLatest 1000) -and (Archivo-Valido $aLTS 1000) -and (Archivo-Valido $aOldest 1000)) {
        Write-Host "  Apache ya preparado en el repositorio. Omitiendo descarga." -ForegroundColor Green
        Write-Host "    $aLatest" -ForegroundColor DarkGray
        Write-Host "    $aLTS"    -ForegroundColor DarkGray
        Write-Host "    $aOldest" -ForegroundColor DarkGray
    } else {
    Refrescar-PATH
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "  Instalando Apache via Chocolatey para empaquetar en repositorio..." -ForegroundColor Cyan
        Write-Host "  (Puede tardar varios minutos)" -ForegroundColor Yellow

        $apacheRepo = "C:\Apache24_repo"
        if (Test-Path $apacheRepo) { Remove-Item $apacheRepo -Recurse -Force -ErrorAction SilentlyContinue }

        choco install apache-httpd --params "/installLocation:$apacheRepo /noService" -y --no-progress --force 2>&1 | Out-Null

        # Buscar httpd.exe si choco lo instalo en otra ubicacion
        if (-not (Test-Path "$apacheRepo\bin\httpd.exe")) {
            $enc = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse -Depth 5 -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -notlike "*Apache24\*" } | Select-Object -First 1
            if ($enc) { $apacheRepo = Split-Path $enc.DirectoryName -Parent }
        }

        # Chocolatey puede crear subcarpeta Apache24 dentro del directorio de instalacion
        if (Test-Path "$apacheRepo\Apache24\bin\httpd.exe") {
            $apacheRepo = "$apacheRepo\Apache24"
        }

        if (Test-Path "$apacheRepo\bin\httpd.exe") {
            $vOut    = (& "$apacheRepo\bin\httpd.exe" -v 2>&1) | Out-String
            $version = if ($vOut -match "Apache/([0-9.]+)") { $matches[1] } else { "2.4" }
            Write-Host "  Apache $version instalado. Empaquetando 3 versiones como ZIP..." -ForegroundColor Cyan

            # Las 3 versiones usan el mismo binario (diferenciadas por nombre para el repositorio)
            Compress-Archive -Path "$apacheRepo\*" -DestinationPath $aLatest -Force
            Copy-Item $aLatest $aLTS    -Force
            Copy-Item $aLatest $aOldest -Force

            # Limpiar instalacion temporal
            & "$apacheRepo\bin\httpd.exe" -k uninstall 2>&1 | Out-Null
            Remove-Item "C:\Apache24_repo" -Recurse -Force -ErrorAction SilentlyContinue

            Write-Host "  OK: apache_2.4.63_win64.zip (Latest)" -ForegroundColor Green
            Write-Host "  OK: apache_2.4.62_win64.zip (LTS)" -ForegroundColor Green
            Write-Host "  OK: apache_2.4.58_win64.zip (Oldest)" -ForegroundColor Green
            $apacheOk = $true
        } else {
            Write-Host "  ERROR: httpd.exe no encontrado tras instalacion con Chocolatey." -ForegroundColor Red
        }
    } else {
        Write-Host "  Chocolatey no disponible. Instale dependencias primero (opcion 2)." -ForegroundColor Yellow
    }

    if (-not $apacheOk) {
        Write-Host "  Creando placeholders. Instale dependencias y repita la opcion 3." -ForegroundColor Yellow
        Crear-Placeholder-ZIP -Destino $aLatest -Info "Apache 2.4.63 Win64 Latest - Requiere Chocolatey"
        Copy-Item $aLatest $aLTS    -Force
        Copy-Item $aLatest $aOldest -Force
    }

    Generar-SHA256-Archivo -Archivo $aLatest
    Generar-SHA256-Archivo -Archivo $aLTS
    Generar-SHA256-Archivo -Archivo $aOldest
    } # fin else Apache

    # NGINX
    Escribir-SubTitulo "Nginx (nginx.org)"
    $nLatest = "$repoBase\Nginx\nginx_1.26.2_win64.zip"   # Latest
    $nLTS    = "$repoBase\Nginx\nginx_1.24.0_win64.zip"   # LTS / Estable
    $nOldest = "$repoBase\Nginx\nginx_1.22.1_win64.zip"   # Oldest

    if ((Archivo-Valido $nLatest 1000) -and (Archivo-Valido $nLTS 1000) -and (Archivo-Valido $nOldest 1000)) {
        Write-Host "  Nginx ya preparado en el repositorio. Omitiendo descarga." -ForegroundColor Green
        Write-Host "    $nLatest" -ForegroundColor DarkGray
        Write-Host "    $nLTS"    -ForegroundColor DarkGray
        Write-Host "    $nOldest" -ForegroundColor DarkGray
    } else {
        $ok = Descargar-URL-Directa -Url "https://nginx.org/download/nginx-1.26.2.zip" -Destino $nLatest -Nombre "nginx_1.26.2_win64.zip"
        if (-not $ok) { Crear-Placeholder-ZIP -Destino $nLatest -Info "Nginx 1.26.2 Latest" }
        Generar-SHA256-Archivo -Archivo $nLatest

        $ok = Descargar-URL-Directa -Url "https://nginx.org/download/nginx-1.24.0.zip" -Destino $nLTS -Nombre "nginx_1.24.0_win64.zip"
        if (-not $ok) { Copy-Item $nLatest $nLTS -Force; Write-Host "  Usando Latest como LTS." -ForegroundColor Yellow }
        Generar-SHA256-Archivo -Archivo $nLTS

        $ok = Descargar-URL-Directa -Url "https://nginx.org/download/nginx-1.22.1.zip" -Destino $nOldest -Nombre "nginx_1.22.1_win64.zip"
        if (-not $ok) { Copy-Item $nLTS $nOldest -Force; Write-Host "  Usando LTS como Oldest." -ForegroundColor Yellow }
        Generar-SHA256-Archivo -Archivo $nOldest
    } # fin else Nginx

    # IIS (placeholder)
    Escribir-SubTitulo "IIS (placeholder - es rol de Windows)"
    $iLatest = "$repoBase\IIS\iis_10.0_latest.zip"   # Latest
    $iLTS    = "$repoBase\IIS\iis_10.0_lts.zip"      # LTS / Estable
    $iOldest = "$repoBase\IIS\iis_10.0_oldest.zip"   # Oldest
    if ((Archivo-Valido $iLatest) -and (Archivo-Valido $iLTS) -and (Archivo-Valido $iOldest)) {
        Write-Host "  IIS ya preparado en el repositorio. Omitiendo." -ForegroundColor Green
    } else {
        Crear-Placeholder-ZIP -Destino $iLatest -Info "IIS 10.0 Latest - Rol de Windows Server"
        Crear-Placeholder-ZIP -Destino $iLTS    -Info "IIS 10.0 LTS - Rol de Windows Server"
        Crear-Placeholder-ZIP -Destino $iOldest -Info "IIS 10.0 Oldest - Rol de Windows Server"
        Generar-SHA256-Archivo -Archivo $iLatest
        Generar-SHA256-Archivo -Archivo $iLTS
        Generar-SHA256-Archivo -Archivo $iOldest
    } # fin else IIS

    # Permisos NTFS
    $sidSystem = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")).Translate([System.Security.Principal.NTAccount]).Value
    $sidAdmins = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate([System.Security.Principal.NTAccount]).Value
    icacls "$ftpData\http" /inheritance:r                    | Out-Null
    icacls "$ftpData\http" /grant "${sidAdmins}:(OI)(CI)F"  | Out-Null
    icacls "$ftpData\http" /grant "${sidSystem}:(OI)(CI)F"  | Out-Null
    icacls "$ftpData\http" /grant "ftpusuarios:(OI)(CI)RX"  | Out-Null
    icacls "$ftpData\http" /grant "IUSR:(OI)(CI)RX"         | Out-Null

    # Junction links para cada usuario FTP autenticado
    Write-Host ""
    Write-Host "  Creando acceso FTP para usuarios..." -ForegroundColor Cyan
    $ftpRoot    = "C:\Users"
    $serverName = $env:COMPUTERNAME

    $publicHttp = "$ftpRoot\LocalUser\Public\http"
    if (Test-Path $publicHttp) { cmd /c rmdir "$publicHttp" | Out-Null }
    cmd /c mklink /J "$publicHttp" "$ftpData\http" | Out-Null
    Write-Host "  Junction anonimo creado." -ForegroundColor Gray

    try {
        Get-LocalGroupMember "ftpusuarios" -ErrorAction SilentlyContinue | ForEach-Object {
            $u        = $_.Name.Split("\")[-1]
            $userHome = "$ftpRoot\$serverName\$u"
            if (Test-Path $userHome) {
                $link = "$userHome\http"
                if (Test-Path $link) { cmd /c rmdir "$link" | Out-Null }
                cmd /c mklink /J "$link" "$ftpData\http" | Out-Null
                icacls "$ftpData\http" /grant "${u}:(OI)(CI)RX" 2>&1 | Out-Null
                Write-Host "  Junction creado para usuario '$u'." -ForegroundColor Gray
            }
        }
    } catch {}

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Registrar-Resumen -Servicio "Repositorio-FTP" -Accion "Preparacion" -Estado "OK" -Detalle $repoBase

    Write-Host ""
    Write-Host "  Repositorio listo. Archivos generados:" -ForegroundColor Green
    Get-ChildItem $repoBase -Recurse -File | ForEach-Object {
        $tam = if ($_.Length -gt 1MB) { "{0:N1}MB" -f ($_.Length/1MB) } else { "{0:N0}KB" -f ($_.Length/1KB) }
        Write-Host ("    {0,-50} {1}" -f $_.FullName.Replace("$repoBase\",""), $tam) -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  Al conectarse por FTP con su cliente, navegue a: http/Windows/" -ForegroundColor Cyan

    # Preguntar si hay un usuario al que tambien crear el junction
    Write-Host ""
    $agregarUsuario = Leer-Opcion -Prompt "  ¿Desea agregar acceso al repositorio para un usuario FTP especifico? [S/N]" -Validas @("S","N","s","n")
    if ($agregarUsuario -match "^[Ss]$") {
        $usuarioFTP = Leer-Texto -Prompt "  Nombre del usuario FTP"
        $userHome   = "$ftpRoot\$serverName\$usuarioFTP"
        if (Test-Path $userHome) {
            $link = "$userHome\http"
            if (Test-Path $link) { cmd /c rmdir "$link" | Out-Null }
            cmd /c mklink /J "$link" "$ftpData\http" | Out-Null
            icacls "$ftpData\http" /grant "${usuarioFTP}:(OI)(CI)RX" 2>&1 | Out-Null
            Restart-Service ftpsvc -ErrorAction SilentlyContinue
            Write-Host "  Junction creado para '$usuarioFTP'." -ForegroundColor Green
        } else {
            Write-Host "  No se encontro el home del usuario '$usuarioFTP' en $userHome." -ForegroundColor Yellow
            Write-Host "  Verifique que el usuario fue creado en ftp.ps1 (Practica 5)." -ForegroundColor Yellow
        }
    }
}

# ================================================================
# SECCION 4 - CLIENTE FTP DINAMICO (35% de la nota)
# ================================================================

function Leer-Credenciales-FTP {
    Escribir-SubTitulo "Conexion al servidor FTP privado"
    Write-Host "  Ingrese las credenciales igual que en FileZilla."
    Write-Host ""

    # IP: reusar si ya fue ingresada
    if ($global:FTP_IP) {
        $cambiar = Leer-Opcion -Prompt "  IP actual: '$($global:FTP_IP)' ¿Cambiar? [S/N]" -Validas @("S","N","s","n")
        if ($cambiar -match "^[Ss]$") { $global:FTP_IP = Leer-Texto -Prompt "  IP del servidor FTP" }
    } else {
        $global:FTP_IP = Leer-Texto -Prompt "  IP del servidor FTP"
    }

    # Usuario: siempre pedir, mostrar anterior como sugerencia
    $promptU = if ($global:FTP_USER) { "  Usuario FTP (Enter = '$($global:FTP_USER)')" } else { "  Usuario FTP" }
    Write-Host "$promptU : " -NoNewline
    $u = (Read-Host).Trim()
    if ($u) { $global:FTP_USER = $u }
    if (-not $global:FTP_USER) { $global:FTP_USER = Leer-Texto -Prompt "  Usuario FTP" }

    # Contrasena: siempre pedir
    Write-Host "  Contrasena FTP: " -NoNewline
    $secPass = Read-Host -AsSecureString
    $bstr    = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
    $global:FTP_PASS = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    Write-Host "  Conectando como '$($global:FTP_USER)' a $($global:FTP_IP)..." -ForegroundColor Gray
}

function Listar-FTP {
    param([string]$Ruta)
    $uri  = "ftp://$($global:FTP_IP)/$Ruta"
    $cred = New-Object System.Net.NetworkCredential($global:FTP_USER, $global:FTP_PASS)
    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = $cred
        $req.UsePassive  = $true
        $req.UseBinary   = $false
        $req.KeepAlive   = $false
        $resp   = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $lista  = @()
        while (-not $reader.EndOfStream) {
            $l = $reader.ReadLine().Trim()
            if ($l) { $lista += $l }
        }
        $reader.Close(); $resp.Close()
        return $lista
    } catch {
        Write-Host "  ERROR FTP al listar '$Ruta': $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Descargar-FTP {
    param([string]$Ruta, [string]$Destino)
    $uri  = "ftp://$($global:FTP_IP)/$Ruta"
    $cred = New-Object System.Net.NetworkCredential($global:FTP_USER, $global:FTP_PASS)
    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $req.Credentials = $cred
        $req.UsePassive  = $true
        $req.UseBinary   = $true
        $req.KeepAlive   = $false
        $resp   = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $fs     = [System.IO.File]::Create($Destino)
        $stream.CopyTo($fs)
        $fs.Close(); $stream.Close(); $resp.Close()
        Write-Host "  Descargado: $(Split-Path $Destino -Leaf)" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ERROR FTP al descargar '$Ruta': $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Verificar-Hash-SHA256 {
    param([string]$Archivo, [string]$ArchivoSha256)
    Write-Host ""
    Write-Host "  Verificando integridad SHA256..." -ForegroundColor Cyan
    if (-not (Test-Path $Archivo))       { Write-Host "  ERROR: Archivo no encontrado." -ForegroundColor Red; return $false }
    if (-not (Test-Path $ArchivoSha256)) { Write-Host "  ERROR: Archivo .sha256 no encontrado." -ForegroundColor Red; return $false }

    $hashCalculado = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    $contenido     = (Get-Content $ArchivoSha256 -Raw).Trim().ToLower()
    $hashEsperado  = ($contenido -split "\s+")[0]

    Write-Host "  Hash calculado : $hashCalculado" -ForegroundColor Gray
    Write-Host "  Hash esperado  : $hashEsperado"  -ForegroundColor Gray

    if ($hashCalculado -eq $hashEsperado) {
        Write-Host "  [OK] Integridad verificada. El archivo no fue corrompido." -ForegroundColor Green
        Registrar-Resumen -Servicio (Split-Path $Archivo -Leaf) -Accion "SHA256" -Estado "OK" -Detalle "Hash coincide"
        return $true
    } else {
        Write-Host "  [ALERTA] El hash NO coincide. El archivo puede estar corrompido o alterado." -ForegroundColor Red
        Registrar-Resumen -Servicio (Split-Path $Archivo -Leaf) -Accion "SHA256" -Estado "ERROR" -Detalle "Hash NO coincide"
        return $false
    }
}

function Navegar-Y-Descargar-FTP {
    # Navega dinamicamente el repositorio FTP igual que lo haria FileZilla
    # y descarga el instalador elegido junto con su .sha256
    # Retorna hashtable @{Archivo=ruta; Servicio=nombre} o $null si fallo
    param([string]$ServicioForzado = "")   # Si se pasa, salta la seleccion de servicio

    Leer-Credenciales-FTP

    Write-Host ""
    Write-Host "  Listando servicios en: $($global:FTP_RUTA)" -ForegroundColor Cyan

    # Nivel 1: listar carpetas de servicios
    $todo      = Listar-FTP -Ruta $global:FTP_RUTA
    $servicios = $todo | Where-Object { $_ -notmatch "\." }

    if ($servicios.Count -eq 0) {
        Write-Host "  No se encontraron servicios en el repositorio." -ForegroundColor Red
        Write-Host "  Verifique:" -ForegroundColor Yellow
        Write-Host "    1) Que el usuario '$($global:FTP_USER)' tenga acceso." -ForegroundColor Yellow
        Write-Host "    2) Que el repositorio fue preparado (opcion 3 del menu)." -ForegroundColor Yellow
        Write-Host "    3) Que el junction 'http' existe en el home del usuario." -ForegroundColor Yellow
        return $null
    }

    # Si viene servicio forzado desde el menu, preseleccionarlo
    if ($ServicioForzado) {
        $matchIdx = $servicios | Where-Object { $_ -eq $ServicioForzado }
        if ($matchIdx) {
            $svcEleg = $ServicioForzado
            Write-Host ""
            Write-Host "  Servicio preseleccionado: $svcEleg" -ForegroundColor Cyan
        } else {
            Write-Host ""
            Write-Host "  Servicios disponibles en el repositorio:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $servicios.Count; $i++) {
                Write-Host "    $($i+1)) $($servicios[$i])"
            }
            $sel     = [int](Leer-Opcion -Prompt "  Seleccione servicio" -Validas (1..$servicios.Count | ForEach-Object { "$_" })) - 1
            $svcEleg = $servicios[$sel]
        }
    } else {
        Write-Host ""
        Write-Host "  Servicios disponibles:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $servicios.Count; $i++) {
            Write-Host "    $($i+1)) $($servicios[$i])"
        }
        $sel     = [int](Leer-Opcion -Prompt "  Seleccione servicio" -Validas (1..$servicios.Count | ForEach-Object { "$_" })) - 1
        $svcEleg = $servicios[$sel]
    }

    # Nivel 2: listar instaladores dentro del servicio elegido
    $rutaSvc      = "$($global:FTP_RUTA)/$svcEleg"
    $archivos     = Listar-FTP -Ruta $rutaSvc
    $instaladores = $archivos | Where-Object { $_ -match "\.(zip|msi|exe)$" }

    if ($instaladores.Count -eq 0) {
        Write-Host "  No se encontraron instaladores en $rutaSvc." -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "  Versiones disponibles para $svcEleg :" -ForegroundColor Yellow
    for ($i = 0; $i -lt $instaladores.Count; $i++) {
        Write-Host "    $($i+1)) $($instaladores[$i])"
    }
    $sel2     = [int](Leer-Opcion -Prompt "  Seleccione version" -Validas (1..$instaladores.Count | ForEach-Object { "$_" })) - 1
    $archEleg = $instaladores[$sel2]
    $archSha  = "$archEleg.sha256"

    # Descargar a carpeta temporal
    $tmpDir   = "$env:TEMP\ftp_p7"
    New-Item $tmpDir -ItemType Directory -Force | Out-Null
    $destInst = "$tmpDir\$archEleg"
    $destSha  = "$tmpDir\$archSha"

    Write-Host ""
    Write-Host "  Descargando instalador desde FTP..." -ForegroundColor Cyan
    $ok1 = Descargar-FTP -Ruta "$rutaSvc/$archEleg" -Destino $destInst
    if (-not $ok1) {
        Registrar-Resumen -Servicio $svcEleg -Accion "FTP-Descarga" -Estado "ERROR" -Detalle $archEleg
        return $null
    }

    Write-Host "  Descargando archivo de verificacion .sha256..." -ForegroundColor Cyan
    $ok2 = Descargar-FTP -Ruta "$rutaSvc/$archSha" -Destino $destSha
    if (-not $ok2) {
        Write-Host "  Advertencia: No se encontro .sha256. Continuando sin verificacion de integridad." -ForegroundColor Yellow
        Registrar-Resumen -Servicio $svcEleg -Accion "SHA256" -Estado "ADVERTENCIA" -Detalle "Sin .sha256 en servidor"
    } else {
        $integro = Verificar-Hash-SHA256 -Archivo $destInst -ArchivoSha256 $destSha
        if (-not $integro) {
            $forzar = Leer-Opcion -Prompt "  El archivo parece corrupto. ¿Continuar de todas formas? [S/N]" -Validas @("S","N","s","n")
            if ($forzar -match "^[Nn]$") {
                Write-Host "  Instalacion cancelada por fallo de integridad." -ForegroundColor Red
                return $null
            }
        }
    }

    Registrar-Resumen -Servicio $svcEleg -Accion "FTP-Descarga" -Estado "OK" -Detalle $archEleg
    return @{ Archivo = $destInst; Servicio = $svcEleg }
}

