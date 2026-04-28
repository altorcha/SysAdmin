#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
Import-Module ActiveDirectory
Import-Module GroupPolicy

$domain = Get-ADDomain
$domainDn = $domain.DistinguishedName

Write-Host "Practica 09 - Verificacion" -ForegroundColor Green

Write-Host "`n> OUs" -ForegroundColor Cyan
"Cuates","No Cuates","Administradores Delegados" | ForEach-Object {
    $ok = Get-ADOrganizationalUnit -Filter "Name -eq '$_'" -ErrorAction SilentlyContinue
    Write-Host ("{0,-30} {1}" -f $_, $(if ($ok) { "OK" } else { "FALTA" }))
}

Write-Host "`n> Usuarios delegados" -ForegroundColor Cyan
"admin_identidad","admin_storage","admin_politicas","admin_auditoria" | ForEach-Object {
    $u = Get-ADUser -Identity $_ -Properties LockedOut -ErrorAction SilentlyContinue
    Write-Host ("{0,-30} {1}" -f $_, $(if ($u) { "OK LockedOut=$($u.LockedOut)" } else { "FALTA" }))
}

Write-Host "`n> Politicas de password resultantes" -ForegroundColor Cyan
$sampleUsers = @("admin_identidad")
$sampleUsers += Get-ADUser -Filter * -SearchBase "OU=Cuates,$domainDn" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty SamAccountName
$sampleUsers += Get-ADUser -Filter * -SearchBase "OU=No Cuates,$domainDn" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty SamAccountName
$sampleUsers | Where-Object { $_ } | ForEach-Object {
    $policy = Get-ADUserResultantPasswordPolicy -Identity $_ -ErrorAction SilentlyContinue
    if ($policy) {
        Write-Host ("{0,-30} {1} MinLength={2} Lockout={3}" -f $_, $policy.Name, $policy.MinPasswordLength, $policy.LockoutThreshold)
    } else {
        Write-Host ("{0,-30} Sin FGPP resultante" -f $_)
    }
}

Write-Host "`n> GPOs visibles" -ForegroundColor Cyan
Get-GPO -All | Select-Object DisplayName, GpoStatus | Format-Table -AutoSize

Write-Host "`n> Auditoria" -ForegroundColor Cyan
auditpol /get /category:* | Select-String -Pattern "Logon|Inicio|File System|Sistema de archivos|Directory Service|servicio de directorio|Account Lockout|Bloqueo"

Write-Host "`n> Script de eventos" -ForegroundColor Cyan
if (Test-Path "C:\Practica09\Exportar-Eventos-Denegados.ps1") {
    Write-Host "OK C:\Practica09\Exportar-Eventos-Denegados.ps1"
} else {
    Write-Host "FALTA C:\Practica09\Exportar-Eventos-Denegados.ps1"
}
