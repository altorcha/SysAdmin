#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$IdentityAdminUser = "admin_identidad",
    [string]$IdentityAdminPassword = "PasswordLarga09!",
    [string]$StorageAdminUser = "admin_storage",
    [string]$StorageAdminPassword = "P@ssw0rd.Pr09!",
    [string]$TargetUser = "atorres",
    [string]$TargetUserCurrentPassword = "NuevaPrueba09!",
    [string]$RoamingProfileUser = "asilva",
    [switch]$SkipPasswordResetTests
)

$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

$multiOtpExe = "C:\Program Files\multiOTP\multiotp.exe"
$auditScript = "C:\Practica09\Exportar-Eventos-Denegados.ps1"
$profileRoot = "C:\PerfilesMoviles"
$reportRows = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Test,
        [string]$Status,
        [string]$Detail
    )
    $reportRows.Add([PSCustomObject]@{
        Test   = $Test
        Status = $Status
        Detail = $Detail
    }) | Out-Null
}

function New-DomainCredential {
    param(
        [string]$Sam,
        [string]$Password
    )
    $domain = (Get-ADDomain).NetBIOSName
    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential ("$domain\$Sam", $secure)
}

function Invoke-PasswordReset {
    param(
        [string]$Identity,
        [string]$NewPassword,
        [pscredential]$Credential
    )
    Set-ADAccountPassword $Identity -Reset -NewPassword (ConvertTo-SecureString $NewPassword -AsPlainText -Force) -Credential $Credential
}

function Get-MultiOtpUserInfo {
    param([string]$User)
    if (-not (Test-Path $multiOtpExe)) {
        return $null
    }
    Push-Location (Split-Path $multiOtpExe)
    try {
        return (& $multiOtpExe -user-info $User 2>&1 | Out-String)
    } finally {
        Pop-Location
    }
}

Write-Host "Practica 09 - Ejecucion de tests" -ForegroundColor Green

if (-not $SkipPasswordResetTests) {
    Write-Host "`n> Test 1 - RBAC" -ForegroundColor Cyan
    try {
        $credIdentidad = New-DomainCredential -Sam $IdentityAdminUser -Password $IdentityAdminPassword
        Invoke-PasswordReset -Identity $TargetUser -NewPassword "NuevaPrueba09!" -Credential $credIdentidad
        Add-Result -Test "RBAC admin_identidad" -Status "PASS" -Detail "$IdentityAdminUser pudo resetear la contrasena de $TargetUser."
        Write-Host "[PASS] admin_identidad puede resetear contrasena." -ForegroundColor Green
    } catch {
        Add-Result -Test "RBAC admin_identidad" -Status "FAIL" -Detail $_.Exception.Message
        Write-Host "[FAIL] admin_identidad no pudo resetear contrasena: $($_.Exception.Message)" -ForegroundColor Red
    }

    try {
        $credStorage = New-DomainCredential -Sam $StorageAdminUser -Password $StorageAdminPassword
        Invoke-PasswordReset -Identity $TargetUser -NewPassword "OtraPrueba09!" -Credential $credStorage
        Add-Result -Test "RBAC admin_storage" -Status "FAIL" -Detail "$StorageAdminUser logro resetear la contrasena de $TargetUser y no debia."
        Write-Host "[FAIL] admin_storage logro resetear contrasena." -ForegroundColor Red
    } catch {
        if ($_.Exception.Message -match "Access is denied|denied|Unauthorized") {
            Add-Result -Test "RBAC admin_storage" -Status "PASS" -Detail "admin_storage recibio acceso denegado."
            Write-Host "[PASS] admin_storage fue bloqueado como se esperaba." -ForegroundColor Green
        } else {
            Add-Result -Test "RBAC admin_storage" -Status "WARN" -Detail $_.Exception.Message
            Write-Host "[WARN] admin_storage fallo con mensaje no esperado: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host "`n> Test 2 - FGPP" -ForegroundColor Cyan
    try {
        Set-ADAccountPassword $IdentityAdminUser -Reset -NewPassword (ConvertTo-SecureString "Corta09!" -AsPlainText -Force)
        Add-Result -Test "FGPP corta" -Status "FAIL" -Detail "Se acepto una contrasena corta para $IdentityAdminUser."
        Write-Host "[FAIL] Se acepto contrasena corta para admin_identidad." -ForegroundColor Red
    } catch {
        if ($_.Exception.Message -match "length|complexity|history requirement|requisit") {
            Add-Result -Test "FGPP corta" -Status "PASS" -Detail "La contrasena corta fue rechazada."
            Write-Host "[PASS] La contrasena corta fue rechazada." -ForegroundColor Green
        } else {
            Add-Result -Test "FGPP corta" -Status "WARN" -Detail $_.Exception.Message
            Write-Host "[WARN] Respuesta inesperada al probar FGPP: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    try {
        Set-ADAccountPassword $IdentityAdminUser -Reset -NewPassword (ConvertTo-SecureString $IdentityAdminPassword -AsPlainText -Force)
        Add-Result -Test "FGPP valida" -Status "PASS" -Detail "Se pudo establecer una contrasena valida para $IdentityAdminUser."
        Write-Host "[PASS] Contrasena valida aceptada para admin_identidad." -ForegroundColor Green
    } catch {
        Add-Result -Test "FGPP valida" -Status "FAIL" -Detail $_.Exception.Message
        Write-Host "[FAIL] No se pudo restaurar la contrasena valida: $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($TargetUserCurrentPassword) {
        try {
            Set-ADAccountPassword $TargetUser -Reset -NewPassword (ConvertTo-SecureString $TargetUserCurrentPassword -AsPlainText -Force)
            Add-Result -Test "Restore target user" -Status "PASS" -Detail "Se restauro la contrasena original de $TargetUser."
            Write-Host "[PASS] Contrasena de $TargetUser restaurada." -ForegroundColor Green
        } catch {
            Add-Result -Test "Restore target user" -Status "WARN" -Detail $_.Exception.Message
            Write-Host "[WARN] No se pudo restaurar la contrasena de ${TargetUser}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} else {
    Add-Result -Test "RBAC/FGPP" -Status "SKIP" -Detail "Se omitieron pruebas de reset de contrasenas por parametro."
}

Write-Host "`n> Test 5 - Script de auditoria" -ForegroundColor Cyan
if (Test-Path $auditScript) {
    try {
        & $auditScript | Out-Null
        $latestReport = Get-ChildItem C:\Practica09\Reporte_Eventos_*.csv -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestReport) {
            Add-Result -Test "Auditoria automatizada" -Status "PASS" -Detail "Reporte generado: $($latestReport.FullName)"
            Write-Host "[PASS] Reporte generado: $($latestReport.Name)" -ForegroundColor Green
        } else {
            Add-Result -Test "Auditoria automatizada" -Status "FAIL" -Detail "El script corrio pero no encontro CSV generado."
            Write-Host "[FAIL] No se encontro CSV generado." -ForegroundColor Red
        }
    } catch {
        Add-Result -Test "Auditoria automatizada" -Status "FAIL" -Detail $_.Exception.Message
        Write-Host "[FAIL] El script de auditoria fallo: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Add-Result -Test "Auditoria automatizada" -Status "FAIL" -Detail "No existe $auditScript"
    Write-Host "[FAIL] No existe el script de auditoria." -ForegroundColor Red
}

Write-Host "`n> Test 6/7 - Verificacion general y Credential Provider" -ForegroundColor Cyan
try {
    $provider = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers" |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath
            [PSCustomObject]@{
                Guid = $_.PSChildName
                Name = $p.'(default)'
            }
        } | Where-Object Name -eq "multiOTPCredentialProvider"

    if ($provider) {
        Add-Result -Test "Credential Provider" -Status "PASS" -Detail "$($provider.Guid) multiOTPCredentialProvider"
        Write-Host "[PASS] Credential Provider multiOTP presente." -ForegroundColor Green
    } else {
        Add-Result -Test "Credential Provider" -Status "FAIL" -Detail "No se encontro multiOTPCredentialProvider."
        Write-Host "[FAIL] No se encontro multiOTPCredentialProvider." -ForegroundColor Red
    }
} catch {
    Add-Result -Test "Credential Provider" -Status "FAIL" -Detail $_.Exception.Message
}

Write-Host "`n> Test 8 - Tokens y estado multiOTP" -ForegroundColor Cyan
if (Test-Path $multiOtpExe) {
    $dbs = Get-ChildItem "C:\Program Files\multiOTP\users" -Filter *.db -ErrorAction SilentlyContinue
    if ($dbs) {
        Add-Result -Test "multiOTP users" -Status "PASS" -Detail (($dbs.Name | Sort-Object) -join ", ")
        Write-Host "[PASS] Tokens presentes: $($dbs.Count)" -ForegroundColor Green
    } else {
        Add-Result -Test "multiOTP users" -Status "FAIL" -Detail "No se encontraron .db en C:\Program Files\multiOTP\users"
        Write-Host "[FAIL] No se encontraron tokens .db." -ForegroundColor Red
    }

    $adminInfo = Get-MultiOtpUserInfo -User "administrator"
    if ($adminInfo) {
        Add-Result -Test "multiOTP administrator" -Status "INFO" -Detail (($adminInfo -replace "`r|`n", " ") -replace "\s+", " ").Trim()
        Write-Host "[INFO] Estado multiOTP de administrator capturado." -ForegroundColor Cyan
    }
} else {
    Add-Result -Test "multiOTP executable" -Status "FAIL" -Detail "No existe $multiOtpExe"
    Write-Host "[FAIL] No existe multiotp.exe." -ForegroundColor Red
}

Write-Host "`n> Test adicional - Perfil movil" -ForegroundColor Cyan
$profileCandidates = @(
    (Join-Path $profileRoot "$RoamingProfileUser.V6"),
    (Join-Path $profileRoot $RoamingProfileUser)
)
$existingProfile = $profileCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($existingProfile) {
    $desktop = Join-Path $existingProfile "Desktop"
    $documents = Join-Path $existingProfile "Documents"
    $desktopCount = @(Get-ChildItem $desktop -Force -ErrorAction SilentlyContinue).Count
    $docCount = @(Get-ChildItem $documents -Force -ErrorAction SilentlyContinue).Count
    Add-Result -Test "Perfil movil" -Status "PASS" -Detail "$existingProfile | Desktop=$desktopCount | Documents=$docCount"
    Write-Host "[PASS] Perfil movil encontrado: $existingProfile" -ForegroundColor Green
} else {
    Add-Result -Test "Perfil movil" -Status "WARN" -Detail "No se encontro carpeta de perfil para $RoamingProfileUser."
    Write-Host "[WARN] No se encontro perfil movil para $RoamingProfileUser." -ForegroundColor Yellow
}

Write-Host "`nResumen" -ForegroundColor Cyan
$reportRows | Format-Table -AutoSize

$outDir = "C:\Practica09"
if (-not (Test-Path $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outCsv = Join-Path $outDir "Resumen_Tests_Practica09_$stamp.csv"
$reportRows | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "[OK] Resumen exportado a: $outCsv" -ForegroundColor Green
Write-Host "[NOTA] El Test 3 de MFA en LogonUI sigue siendo una evidencia manual por pantalla." -ForegroundColor Yellow
