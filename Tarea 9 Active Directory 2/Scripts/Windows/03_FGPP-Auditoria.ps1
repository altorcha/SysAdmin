#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

$domain = Get-ADDomain
$domainDn = $domain.DistinguishedName
$adminGroup = "FGPP_Privilegiados_12"
$standardGroup = "FGPP_Estandar_8"
$reportDir = "C:\Practica09"

function Ensure-Group {
    param([string]$Name)
    if (-not (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $Name -GroupScope Global -GroupCategory Security -Path "CN=Users,$domainDn" | Out-Null
        Write-Host "[OK] Grupo creado: $Name" -ForegroundColor Green
    }
}

Write-Host "Practica 09 - FGPP y auditoria" -ForegroundColor Green

Ensure-Group $adminGroup
Ensure-Group $standardGroup

"admin_identidad","admin_storage","admin_politicas","admin_auditoria" | ForEach-Object {
    Add-ADGroupMember -Identity $adminGroup -Members $_ -ErrorAction SilentlyContinue
}

foreach ($ou in "OU=Cuates,$domainDn","OU=No Cuates,$domainDn") {
    Get-ADUser -Filter * -SearchBase $ou -ErrorAction SilentlyContinue | ForEach-Object {
        Add-ADGroupMember -Identity $standardGroup -Members $_ -ErrorAction SilentlyContinue
    }
}

if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'FGPP_Admins_Min12'" -ErrorAction SilentlyContinue)) {
    New-ADFineGrainedPasswordPolicy `
        -Name "FGPP_Admins_Min12" `
        -Precedence 10 `
        -MinPasswordLength 12 `
        -ComplexityEnabled $true `
        -PasswordHistoryCount 5 `
        -MaxPasswordAge (New-TimeSpan -Days 90) `
        -MinPasswordAge (New-TimeSpan -Days 0) `
        -LockoutThreshold 3 `
        -LockoutObservationWindow (New-TimeSpan -Minutes 30) `
        -LockoutDuration (New-TimeSpan -Minutes 30) | Out-Null
}
Add-ADFineGrainedPasswordPolicySubject -Identity "FGPP_Admins_Min12" -Subjects $adminGroup -ErrorAction SilentlyContinue

if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'FGPP_Usuarios_Min8'" -ErrorAction SilentlyContinue)) {
    New-ADFineGrainedPasswordPolicy `
        -Name "FGPP_Usuarios_Min8" `
        -Precedence 20 `
        -MinPasswordLength 8 `
        -ComplexityEnabled $true `
        -PasswordHistoryCount 3 `
        -MaxPasswordAge (New-TimeSpan -Days 90) `
        -MinPasswordAge (New-TimeSpan -Days 0) `
        -LockoutThreshold 3 `
        -LockoutObservationWindow (New-TimeSpan -Minutes 30) `
        -LockoutDuration (New-TimeSpan -Minutes 30) | Out-Null
}
Add-ADFineGrainedPasswordPolicySubject -Identity "FGPP_Usuarios_Min8" -Subjects $standardGroup -ErrorAction SilentlyContinue

Write-Host "`n> Habilitando auditoria" -ForegroundColor Cyan
function Enable-AuditSubcategory {
    param(
        [string]$FriendlyName,
        [string[]]$Patterns
    )

    $available = auditpol /list /subcategory:* 2>$null |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -notmatch "^The command|^Use|^-+$" }

    $matches = foreach ($pattern in $Patterns) {
        $available | Where-Object { $_ -match $pattern }
    }

    $matches = $matches | Select-Object -Unique
    if (-not $matches) {
        Write-Host "[AVISO] No se encontro subcategoria auditpol para: $FriendlyName" -ForegroundColor Yellow
        return
    }

    foreach ($sub in $matches) {
        $null = auditpol /set /subcategory:"$sub" /success:enable /failure:enable 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Auditoria habilitada: $sub" -ForegroundColor Green
        } else {
            Write-Host "[AVISO] auditpol no acepto: $sub" -ForegroundColor Yellow
        }
    }
}

Enable-AuditSubcategory -FriendlyName "Logon" -Patterns @("(?i)^Logon$", "(?i)inicio.*sesi")
Enable-AuditSubcategory -FriendlyName "Logoff" -Patterns @("(?i)^Logoff$", "(?i)cierre.*sesi")
Enable-AuditSubcategory -FriendlyName "File System" -Patterns @("(?i)^File System$", "(?i)sistema.*archivos")
Enable-AuditSubcategory -FriendlyName "Directory Service Access" -Patterns @("(?i)^Directory Service Access$", "(?i)servicio.*directorio")
Enable-AuditSubcategory -FriendlyName "Account Lockout" -Patterns @("(?i)^Account Lockout$", "(?i)bloqueo.*cuenta")
Enable-AuditSubcategory -FriendlyName "User Account Management" -Patterns @("(?i)^User Account Management$", "(?i)administr.*cuentas.*usuario")

if (-not (Test-Path $reportDir)) {
    New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
}

$auditScript = @'
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out = "C:\Practica09\Reporte_Eventos_$stamp.csv"

$events = Get-WinEvent -FilterHashtable @{
    LogName = "Security"
    Id = 4625, 4740, 4663, 4656
} -MaxEvents 10 -ErrorAction SilentlyContinue

$report = $events | ForEach-Object {
    [PSCustomObject]@{
        Fecha = $_.TimeCreated
        Id = $_.Id
        Proveedor = $_.ProviderName
        Equipo = $_.MachineName
        Mensaje = ($_.Message -replace "`r|`n", " ")
    }
}

$report | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
$report | Format-Table -AutoSize
Write-Host "`nReporte generado: $out" -ForegroundColor Green
'@

$auditScript | Out-File "C:\Practica09\Exportar-Eventos-Denegados.ps1" -Encoding UTF8 -Force

Write-Host "`n[OK] FGPP y auditoria configuradas." -ForegroundColor Green
Write-Host "[OK] Script generado: C:\Practica09\Exportar-Eventos-Denegados.ps1" -ForegroundColor Green
