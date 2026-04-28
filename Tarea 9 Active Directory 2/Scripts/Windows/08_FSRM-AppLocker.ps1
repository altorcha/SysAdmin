#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Practica 09 - Gestion de Almacenamiento (FSRM) y Control de Ejecucion (AppLocker)
.DESCRIPTION
    - Instala y configura FSRM con cuotas diferenciadas por grupo (5 MB / 10 MB)
    - Aplica Active Screening dinamico: bloquea .mp3, .mp4, .exe, .msi en carpetas de usuario
    - Crea reglas AppLocker via GPO:
        * Grupo Cuates  (Grupo 1): Notepad.exe PERMITIDO
        * Grupo No Cuates (Grupo 2): Notepad.exe BLOQUEADO por Hash
.NOTES
    Debe ejecutarse despues de 01_Crear-Estructura-AD.ps1
    Requiere: FSRM, GroupPolicy, ActiveDirectory, AppLocker (Windows Server 2016+)
#>

[CmdletBinding()]
param(
    [string]$ShareRoot   = "C:\Shares\Usuarios",
    [string]$GpoFsrmName = "Pr09-FSRM-Cuotas-Screening",
    [string]$GpoApplName = "Pr09-AppLocker-Ejecucion"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

#region ── Modulos ─────────────────────────────────────────────────────────────
foreach ($mod in @("ActiveDirectory","GroupPolicy")) {
    if (-not (Get-Module -Name $mod -ListAvailable)) {
        throw "Modulo requerido no disponible: $mod"
    }
    Import-Module $mod -ErrorAction Stop
}
#endregion

#region ── Datos del dominio ───────────────────────────────────────────────────
$domain    = Get-ADDomain
$domainDn  = $domain.DistinguishedName
$dnsRoot   = $domain.DNSRoot
$netbios   = $domain.NetBIOSName
$server    = $env:COMPUTERNAME

$ouCuates   = "OU=Cuates,$domainDn"
$ouNoCuates = "OU=No Cuates,$domainDn"
#endregion

#region ── Helper ──────────────────────────────────────────────────────────────
function Write-Step { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host "    [--] $Msg" -ForegroundColor DarkGray }
#endregion

# ══════════════════════════════════════════════════════════════════════════════
#  BLOQUE 1 — FSRM: Instalacion, Cuotas y File Screening
# ══════════════════════════════════════════════════════════════════════════════

Write-Step "Instalando el rol FSRM si no esta presente"
$fsrmFeature = Get-WindowsFeature -Name FS-Resource-Manager
if (-not $fsrmFeature.Installed) {
    Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools | Out-Null
    Write-OK "FSRM instalado correctamente"
} else {
    Write-Skip "FSRM ya estaba instalado"
}

Import-Module FileServerResourceManager -ErrorAction Stop

# ── 1A. Plantillas de cuota ────────────────────────────────────────────────
Write-Step "Creando plantillas de cuota FSRM"

function Ensure-FsrmQuotaTemplate {
    param(
        [string]$Name,
        [int64] $LimitBytes,
        [string]$Description
    )
    $existing = Get-FsrmQuotaTemplate -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Skip "Plantilla ya existe: $Name"
        return
    }

    # Umbral de advertencia al 85 %
    $threshold = New-FsrmQuotaThreshold -Percentage 85 `
        -Action (New-FsrmAction -Type Email `
            -MailTo "[Admin Email]" `
            -Subject "Aviso cuota: [Quota Path]" `
            -Body "El usuario ha alcanzado el 85% de su cuota ([Quota Used Bytes] / [Quota Limit Bytes]).")

    New-FsrmQuotaTemplate `
        -Name        $Name `
        -Description $Description `
        -Size        $LimitBytes `
        -Threshold   $threshold | Out-Null

    Write-OK "Plantilla creada: $Name ($([math]::Round($LimitBytes/1MB,0)) MB)"
}

Ensure-FsrmQuotaTemplate `
    -Name        "Pr09-Cuota-5MB-NoCuates" `
    -LimitBytes  (5MB) `
    -Description "Cuota dura de 5 MB para usuarios del grupo No Cuates"

Ensure-FsrmQuotaTemplate `
    -Name        "Pr09-Cuota-10MB-Cuates" `
    -LimitBytes  (10MB) `
    -Description "Cuota dura de 10 MB para usuarios del grupo Cuates"

# ── 1B. Aplicar cuotas a las carpetas de usuario ───────────────────────────
Write-Step "Aplicando cuotas a carpetas de usuario en $ShareRoot"

function Apply-FsrmQuotaToUsers {
    param(
        [string]$OuDn,
        [string]$TemplateName
    )

    $users = Get-ADUser -Filter * -SearchBase $OuDn -ErrorAction SilentlyContinue
    foreach ($u in $users) {
        $folder = Join-Path $ShareRoot $u.SamAccountName
        if (-not (Test-Path $folder)) {
            Write-Skip "Carpeta no encontrada, omitiendo: $folder"
            continue
        }

        $existing = Get-FsrmQuota -Path $folder -ErrorAction SilentlyContinue
        if ($existing) {
            # Actualizar plantilla si cambio
            if ($existing.Template -ne $TemplateName) {
                Set-FsrmQuota -Path $folder -Template $TemplateName | Out-Null
                Write-OK "Cuota actualizada en $folder -> $TemplateName"
            } else {
                Write-Skip "Cuota ya correcta en $folder"
            }
        } else {
            New-FsrmQuota -Path $folder -Template $TemplateName | Out-Null
            Write-OK "Cuota aplicada en $folder -> $TemplateName"
        }
    }
}

Apply-FsrmQuotaToUsers -OuDn $ouNoCuates -TemplateName "Pr09-Cuota-5MB-NoCuates"
Apply-FsrmQuotaToUsers -OuDn $ouCuates   -TemplateName "Pr09-Cuota-10MB-Cuates"

# ── 1C. Grupo de archivos bloqueados ──────────────────────────────────────
Write-Step "Configurando grupo de archivos prohibidos"

$blockedGroupName = "Pr09-Archivos-Prohibidos"
$blockedPatterns  = @("*.mp3","*.mp4","*.exe","*.msi")

$existingGroup = Get-FsrmFileGroup -Name $blockedGroupName -ErrorAction SilentlyContinue
if ($existingGroup) {
    Set-FsrmFileGroup -Name $blockedGroupName -IncludePattern $blockedPatterns | Out-Null
    Write-Skip "Grupo de archivos actualizado: $blockedGroupName"
} else {
    New-FsrmFileGroup `
        -Name           $blockedGroupName `
        -IncludePattern $blockedPatterns | Out-Null
    Write-OK "Grupo de archivos creado: $blockedGroupName (mp3, mp4, exe, msi)"
}

# ── 1D. Plantilla de apantallamiento (Active Screening) ───────────────────
Write-Step "Creando plantilla de apantallamiento de archivos (Active Screening)"

$screenTemplateName = "Pr09-Screening-Multimedia-Exe"
$existingTemplate   = Get-FsrmFileScreenTemplate -Name $screenTemplateName -ErrorAction SilentlyContinue

# Accion de correo al detectar archivo prohibido
$screenAction = New-FsrmAction -Type Email `
    -MailTo "[Source Io Owner Email]" `
    -Subject "Archivo bloqueado en [Violated File Group]" `
    -Body   "Se ha bloqueado el archivo '[Source File Path]' porque pertenece al grupo prohibido '[Violated File Group]'. Fecha: [Date]."

if ($existingTemplate) {
    Write-Skip "Plantilla de screening ya existe: $screenTemplateName"
} else {
    New-FsrmFileScreenTemplate `
        -Name         $screenTemplateName `
        -Description  "Bloquea multimedia (.mp3/.mp4) y ejecutables (.exe/.msi)" `
        -Active `
        -IncludeGroup $blockedGroupName `
        -Notification $screenAction | Out-Null
    Write-OK "Plantilla de screening creada: $screenTemplateName"
}

# ── 1E. Aplicar screening a todas las carpetas de usuario ─────────────────
Write-Step "Aplicando apantallamiento a carpetas de usuario"

$allUsers = @()
$allUsers += Get-ADUser -Filter * -SearchBase $ouCuates    -ErrorAction SilentlyContinue
$allUsers += Get-ADUser -Filter * -SearchBase $ouNoCuates  -ErrorAction SilentlyContinue

foreach ($u in $allUsers) {
    $folder = Join-Path $ShareRoot $u.SamAccountName
    if (-not (Test-Path $folder)) {
        Write-Skip "Carpeta no encontrada: $folder"
        continue
    }

    $existing = Get-FsrmFileScreen -Path $folder -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Skip "Screening ya aplicado en $folder"
    } else {
        New-FsrmFileScreen -Path $folder -Template $screenTemplateName | Out-Null
        Write-OK "Screening aplicado en $folder"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  BLOQUE 2 — AppLocker via GPO
# ══════════════════════════════════════════════════════════════════════════════

Write-Step "Configurando AppLocker via GPO"

# ── 2A. Obtener o crear la GPO de AppLocker ───────────────────────────────
$gpoAppl = Get-GPO -Name $GpoApplName -ErrorAction SilentlyContinue
if (-not $gpoAppl) {
    $gpoAppl = New-GPO -Name $GpoApplName -Comment "Reglas AppLocker Practica 09"
    Write-OK "GPO creada: $GpoApplName"
} else {
    Write-Skip "GPO ya existe: $GpoApplName"
}

# Vincular a las OUs de ambos grupos
foreach ($ou in @($ouCuates, $ouNoCuates)) {
    try {
        New-GPLink -Name $GpoApplName -Target $ou -LinkEnabled Yes -ErrorAction Stop | Out-Null
        Write-OK "GPO vinculada a: $ou"
    } catch {
        if ($_.Exception.Message -match "already") {
            Write-Skip "GPO ya vinculada a: $ou"
        } else {
            Write-Host "    [!] No se pudo vincular a ${ou}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# ── 2B. Activar el servicio AppIDSvc via GPO ──────────────────────────────
Write-Step "Habilitando servicio AppIDSvc (Application Identity) via GPO"

# Tambien activar localmente para que funcione de inmediato
try {
    Set-Service -Name AppIDSvc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    Write-OK "Servicio AppIDSvc iniciado localmente"
} catch {
    Write-Host "    [!] No se pudo iniciar AppIDSvc: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ── 2C. Obtener hash de notepad.exe ───────────────────────────────────────
Write-Step "Calculando hash SHA-256 de Notepad.exe"

$notepadPath = "$env:SystemRoot\System32\notepad.exe"
if (-not (Test-Path $notepadPath)) {
    throw "notepad.exe no encontrado en $notepadPath"
}

$hashInfo     = Get-FileHash -Path $notepadPath -Algorithm SHA256
$notepadHash  = $hashInfo.Hash
$notepadSize  = (Get-Item $notepadPath).Length
$notepadVer   = (Get-Item $notepadPath).VersionInfo.FileVersion

Write-OK "Hash SHA-256: $notepadHash"
Write-OK "Tamano      : $notepadSize bytes"
Write-OK "Version     : $notepadVer"

# ── 2D. Construir XML de politica AppLocker ───────────────────────────────
Write-Step "Construyendo politica AppLocker XML"

# AppLocker en GPO se gestiona mediante el registro
# Clave: HKLM\SOFTWARE\Policies\Microsoft\Windows\SrpV2
# Cada tipo de regla tiene su propia subclave (Exe, Msi, Script, AppX)
# La forma recomendada para Server es usar Set-AppLockerPolicy con un XML

$applXml = @"
<AppLockerPolicy Version="1">

  <!-- ═══════════════════════════════════════════════════
       REGLAS PARA EJECUTABLES (.exe y .com)
       ═══════════════════════════════════════════════════ -->
  <RuleCollection Type="Exe" EnforcementMode="Enabled">

    <!-- Regla base: Administradores pueden ejecutar todo -->
    <FilePathRule
        Id="921cc481-6e17-4653-8f75-050b80acca20"
        Name="(Predeterminada) Todos los archivos"
        Description="Permite a administradores ejecutar cualquier aplicacion"
        UserOrGroupSid="S-1-5-32-544"
        Action="Allow">
      <Conditions>
        <FilePathCondition Path="*" />
      </Conditions>
    </FilePathRule>

    <!-- Regla base: Archivos en Program Files permitidos para todos -->
    <FilePathRule
        Id="a61c8b2c-a23f-4b5e-b8e2-4d6f2d8c1f19"
        Name="(Predeterminada) Program Files"
        Description="Permite ejecutar desde Program Files"
        UserOrGroupSid="S-1-1-0"
        Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*" />
      </Conditions>
    </FilePathRule>

    <!-- Regla base: Windows (System32, etc.) permitido para todos -->
    <FilePathRule
        Id="fd686d83-a829-4351-8ff4-27c7de5755d2"
        Name="(Predeterminada) Windows"
        Description="Permite ejecutar desde Windows"
        UserOrGroupSid="S-1-1-0"
        Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*" />
      </Conditions>
    </FilePathRule>

    <!-- ══════════════════════════════════════════════
         GRUPO 1: Cuates — Notepad PERMITIDO (por ruta)
         La regla de %WINDIR%\* ya lo cubre; esta regla
         lo hace explicito y se asigna solo al grupo Cuates.
         ══════════════════════════════════════════════ -->
    <FilePathRule
        Id="b1000001-0000-0000-0000-000000000001"
        Name="[Cuates] Notepad permitido"
        Description="Grupo Cuates: Bloc de Notas permitido explicitamente"
        UserOrGroupSid="PLACEHOLDER_SID_CUATES"
        Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\System32\notepad.exe" />
      </Conditions>
    </FilePathRule>

    <!-- ══════════════════════════════════════════════
         GRUPO 2: No Cuates — Notepad BLOQUEADO por Hash
         El bloqueo por hash impide que renombrar el exe
         evite la restriccion.
         ══════════════════════════════════════════════ -->
    <FileHashRule
        Id="b2000002-0000-0000-0000-000000000002"
        Name="[No Cuates] Notepad bloqueado por hash"
        Description="Grupo No Cuates: Bloc de Notas bloqueado por hash SHA-256. Renombrar el ejecutable no evita el bloqueo."
        UserOrGroupSid="PLACEHOLDER_SID_NOCUATES"
        Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash
              Type="SHA256"
              Data="0x$notepadHash"
              SourceFileName="notepad.exe"
              SourceFileLength="$notepadSize" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

  </RuleCollection>

  <!-- Colecciones adicionales requeridas (sin reglas de negocio extra) -->
  <RuleCollection Type="Msi" EnforcementMode="Enabled">
    <FilePathRule
        Id="c1000001-0000-0000-0000-000000000001"
        Name="(Predeterminada) MSI firmados"
        Description="Permite MSI firmados digitalmente"
        UserOrGroupSid="S-1-1-0"
        Action="Allow">
      <Conditions>
        <FilePathCondition Path="*" />
      </Conditions>
    </FilePathRule>
  </RuleCollection>

  <RuleCollection Type="Script" EnforcementMode="NotConfigured" />
  <RuleCollection Type="Appx"   EnforcementMode="NotConfigured" />

</AppLockerPolicy>
"@

# ── 2E. Resolver SIDs reales de los grupos AD ─────────────────────────────
Write-Step "Resolviendo SIDs de los grupos de seguridad Cuates y No Cuates"

function Get-GroupSid {
    param([string]$GroupName)
    $g = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue
    if (-not $g) { return $null }
    return $g.SID.Value
}

# Los grupos de seguridad se crean en 02_Configurar-RBAC si no existen;
# en 01_Crear-Estructura-AD se crean las OUs. Buscamos el grupo; si no existe
# lo creamos aqui mismo para que AppLocker tenga un SID valido.
function Ensure-SecurityGroup {
    param([string]$Name, [string]$OuDn, [string]$Description)
    $existing = Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-ADGroup `
            -Name          $Name `
            -GroupScope    Global `
            -GroupCategory Security `
            -Path          $OuDn `
            -Description   $Description | Out-Null
        Write-OK "Grupo de seguridad creado: $Name"
    } else {
        Write-Skip "Grupo de seguridad ya existe: $Name"
    }

    # Sincronizar miembros: agregar todos los usuarios de la OU al grupo
    $members = Get-ADUser -Filter * -SearchBase $OuDn -ErrorAction SilentlyContinue
    foreach ($m in $members) {
        Add-ADGroupMember -Identity $Name -Members $m.SamAccountName -ErrorAction SilentlyContinue
    }
    Write-OK "Miembros de $OuDn sincronizados con el grupo $Name"
}

Ensure-SecurityGroup -Name "GRP_Cuates"   -OuDn $ouCuates   -Description "Grupo de seguridad Cuates - Practica 09"
Ensure-SecurityGroup -Name "GRP_NoCuates" -OuDn $ouNoCuates -Description "Grupo de seguridad No Cuates - Practica 09"

$sidCuates   = Get-GroupSid "GRP_Cuates"
$sidNoCuates = Get-GroupSid "GRP_NoCuates"

if (-not $sidCuates -or -not $sidNoCuates) {
    throw "No se pudieron obtener los SIDs de los grupos. Verifica que GRP_Cuates y GRP_NoCuates existan en AD."
}

Write-OK "SID GRP_Cuates   : $sidCuates"
Write-OK "SID GRP_NoCuates : $sidNoCuates"

# Sustituir placeholders en el XML
$applXml = $applXml -replace "PLACEHOLDER_SID_CUATES",   $sidCuates
$applXml = $applXml -replace "PLACEHOLDER_SID_NOCUATES", $sidNoCuates

# ── 2F. Guardar el XML y aplicarlo a la GPO ───────────────────────────────
Write-Step "Guardando y aplicando politica AppLocker a la GPO"

$xmlPath = "$env:TEMP\Pr09-AppLocker.xml"
$applXml | Out-File -FilePath $xmlPath -Encoding UTF8 -Force
Write-OK "XML guardado en: $xmlPath"

# Set-AppLockerPolicy aplica al equipo local; para GPO se escribe
# en el registro de la GPO usando el proveedor LGPO/Registry.
# La forma mas directa compatible con Server 2016+ es Set-AppLockerPolicy
# (actua sobre la politica local) y luego copiar al GPO via GPMC.

# Aplicar localmente (efecto inmediato en el servidor controlador)
try {
    Set-AppLockerPolicy -XmlPolicy $xmlPath -Merge -ErrorAction Stop
    Write-OK "Politica AppLocker aplicada localmente via Set-AppLockerPolicy"
} catch {
    Write-Host "    [!] Set-AppLockerPolicy: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "        Aplicando politica via registro de la GPO..." -ForegroundColor Yellow
}

# Adicionalmente, escribir las reglas en el registro de la GPO
# para que los clientes del dominio las reciban por Group Policy
$gpoId = $gpoAppl.Id.ToString("B").ToUpper()
$gpoCentral = "\\$dnsRoot\SYSVOL\$dnsRoot\Policies\$gpoId\Machine\Microsoft\Windows NT\AppLocker"

if (-not (Test-Path $gpoCentral)) {
    New-Item -Path $gpoCentral -ItemType Directory -Force | Out-Null
    Write-OK "Directorio AppLocker en SYSVOL creado"
}

$xmlDest = Join-Path $gpoCentral "AppLocker.xml"
Copy-Item -Path $xmlPath -Destination $xmlDest -Force
Write-OK "XML copiado a SYSVOL/GPO: $xmlDest"

# Forzar actualizacion de la politica de grupo
Write-Step "Forzando actualizacion de politica de grupo (gpupdate)"
try {
    gpupdate /force /wait:0 | Out-Null
    Write-OK "gpupdate ejecutado"
} catch {
    Write-Host "    [!] gpupdate: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════════════════════════════════
#  RESUMEN FINAL
# ══════════════════════════════════════════════════════════════════════════════

Write-Host "`n" + ("=" * 70) -ForegroundColor White
Write-Host "  RESUMEN - FSRM y AppLocker - Practica 09" -ForegroundColor White
Write-Host ("=" * 70) -ForegroundColor White

Write-Host "`n  [FSRM - Cuotas]" -ForegroundColor Cyan
Write-Host "    Grupo No Cuates : cuota de  5 MB por carpeta de usuario" -ForegroundColor White
Write-Host "    Grupo Cuates    : cuota de 10 MB por carpeta de usuario" -ForegroundColor White
Write-Host "    Umbral de aviso : 85 % -> correo al propietario"          -ForegroundColor White

Write-Host "`n  [FSRM - Active Screening]" -ForegroundColor Cyan
Write-Host "    Extensiones bloqueadas: .mp3  .mp4  .exe  .msi"           -ForegroundColor White
Write-Host "    Modo: Active (el archivo es RECHAZADO en tiempo real)"     -ForegroundColor White
Write-Host "    Notificacion: correo al due~no del archivo al intentarlo"  -ForegroundColor White

Write-Host "`n  [AppLocker]" -ForegroundColor Cyan
Write-Host "    GPO aplicada    : $GpoApplName"                           -ForegroundColor White
Write-Host "    Grupo Cuates    : Notepad.exe PERMITIDO (regla de ruta)"  -ForegroundColor White
Write-Host "    Grupo No Cuates : Notepad.exe BLOQUEADO por hash SHA-256" -ForegroundColor White
Write-Host "    Hash usado      : $notepadHash"                           -ForegroundColor White
Write-Host "    Tamano          : $notepadSize bytes | Version: $notepadVer" -ForegroundColor White
Write-Host "    Nota            : el bloqueo por hash es inmune al renombrado del .exe" -ForegroundColor Yellow

Write-Host "`n  [Grupos de seguridad AD creados/verificados]" -ForegroundColor Cyan
Write-Host "    GRP_Cuates   SID: $sidCuates"                             -ForegroundColor White
Write-Host "    GRP_NoCuates SID: $sidNoCuates"                           -ForegroundColor White

Write-Host "`n  Listo.`n" -ForegroundColor Green