#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$MsiPath,

    [string]$MultiOtpPath = "C:\Program Files\multiOTP",
    [string]$VcRedistPath = "C:\vc_redist_2022.x64.exe",

    [hashtable]$Seeds = @{
        "administrator"   = "JBSWY3DPEHPK3PXP"
        "admin_identidad" = "JBSWY3DPEHPK3PXA"
        "admin_storage"   = "JBSWY3DPEHPK3PXB"
        "admin_politicas" = "JBSWY3DPEHPK3PXC"
        "admin_auditoria" = "JBSWY3DPEHPK3PXD"
    }
)

$ErrorActionPreference = "Stop"
$msi = (Resolve-Path $MsiPath).ProviderPath
$exe = Join-Path $MultiOtpPath "multiotp.exe"
$log = "C:\Practica09\multiotp_credential_provider_install.log"

if (-not (Test-Path "C:\Practica09")) {
    New-Item -Path "C:\Practica09" -ItemType Directory -Force | Out-Null
}

function Get-VcRuntimeState {
    $vc = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
    if (-not $vc) {
        return [PSCustomObject]@{
            Installed = $false
            Version = $null
            Major = 0
            Minor = 0
            Bld = 0
        }
    }

    return [PSCustomObject]@{
        Installed = ($vc.Installed -eq 1)
        Version = $vc.Version
        Major = [int]$vc.Major
        Minor = [int]$vc.Minor
        Bld = [int]$vc.Bld
    }
}

function Ensure-VcRuntime {
    param([string]$InstallerPath)

    $vcState = Get-VcRuntimeState
    $needsInstall = (-not $vcState.Installed) -or ($vcState.Major -lt 14) -or (($vcState.Major -eq 14) -and ($vcState.Minor -lt 40))

    if (-not $needsInstall) {
        Write-Host "[OK] Visual C++ x64 ya presente: $($vcState.Version)" -ForegroundColor Green
        return
    }

    Write-Host "[AVISO] Visual C++ x64 no esta presente o es anterior al runtime moderno requerido por multiOTP." -ForegroundColor Yellow

    $candidatePaths = @(
        $InstallerPath,
        "C:\vc_redist_2022.x64.exe",
        "C:\vc_redist.x64.exe"
    ) | Select-Object -Unique

    $installer = $candidatePaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $installer) {
        throw "Falta Visual C++ x64 y no se encontro instalador local. Copia vc_redist_2022.x64.exe a C:\ antes de ejecutar MFA."
    }

    Write-Host "> Instalando/actualizando Visual C++ x64..." -ForegroundColor Cyan
    $p = Start-Process $installer -ArgumentList "/install /quiet /norestart" -Wait -PassThru
    if ($p.ExitCode -notin 0, 1638, 3010) {
        throw "La instalacion de Visual C++ x64 fallo con ExitCode $($p.ExitCode)"
    }

    $vcAfter = Get-VcRuntimeState
    if (-not $vcAfter.Installed) {
        throw "Visual C++ x64 sigue sin aparecer instalado despues del instalador."
    }

    Write-Host "[OK] Visual C++ x64 listo: $($vcAfter.Version)" -ForegroundColor Green
}

Write-Host "Practica 09 - MFA Windows Logon con multiOTP Credential Provider" -ForegroundColor Green
Write-Host "Este script solo cumple la rubrica si el MSI instala un Credential Provider de Windows." -ForegroundColor Yellow

Write-Host "`n> Verificando runtime Visual C++ x64" -ForegroundColor Cyan
Ensure-VcRuntime -InstallerPath $VcRedistPath

Write-Host "`n> Instalando MSI" -ForegroundColor Cyan
$p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart /L*V `"$log`"" -Wait -PassThru
if ($p.ExitCode -notin 0,3010) {
    throw "La instalacion MSI fallo con ExitCode $($p.ExitCode). Revisa $log"
}

if (-not (Test-Path $exe)) {
    throw "No se encontro $exe. El MSI no instalo multiOTP en la ruta esperada."
}

Write-Host "`n> Configurando bloqueo MFA en multiOTP" -ForegroundColor Cyan
& $exe -config max-block-failures=3 | Out-Null
& $exe -config failure-delayed-time=1800 | Out-Null
& $exe -config display-log=1 | Out-Null

Write-Host "`n> Creando tokens TOTP" -ForegroundColor Cyan
foreach ($entry in $Seeds.GetEnumerator()) {
    $user = $entry.Key.ToLower()
    $seed = $entry.Value
    $db = Join-Path $MultiOtpPath "users\$user.db"
    if (Test-Path $db) {
        Remove-Item $db -Force
    }
    & $exe -createga $user $seed | Out-Null
    & $exe -set $user prefix-pin=0 | Out-Null
    Write-Host "[OK] $user Seed=$seed" -ForegroundColor Green
}

Write-Host "`n> Sincronizando hora para TOTP" -ForegroundColor Cyan
w32tm /config /manualpeerlist:"time.google.com,0x8" /syncfromflags:manual /update | Out-Null
Restart-Service w32time -Force
w32tm /resync /force | Out-Null

Write-Host "`n[OK] Motor multiOTP configurado." -ForegroundColor Green
Write-Host "Valida en consola/RDP que el Credential Provider pida el token despues del password." -ForegroundColor Yellow
Write-Host "Seeds para Google Authenticator:" -ForegroundColor White
$Seeds.GetEnumerator() | Sort-Object Key | ForEach-Object {
    Write-Host ("  {0,-16} {1}" -f $_.Key, $_.Value)
}
