#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$TempPassword = "P@ssw0rd.Pr09!"
)

$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory
Import-Module GroupPolicy

$domain = Get-ADDomain
$domainDn = $domain.DistinguishedName
$netbios = $domain.NetBIOSName
$dnsRoot = $domain.DNSRoot
$securePassword = ConvertTo-SecureString $TempPassword -AsPlainText -Force
$delegatedOu = "OU=Administradores Delegados,$domainDn"
$targetOus = @("OU=Cuates,$domainDn", "OU=No Cuates,$domainDn")

function Ensure-DelegatedUser {
    param([string]$Sam, [string]$Display)
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue)) {
        New-ADUser `
            -Name $Display `
            -SamAccountName $Sam `
            -UserPrincipalName "$Sam@$dnsRoot" `
            -Path $delegatedOu `
            -AccountPassword $securePassword `
            -Enabled $true `
            -ChangePasswordAtLogon $false | Out-Null
        Write-Host "[OK] Usuario delegado creado: $Sam" -ForegroundColor Green
    }
}

function Add-ToBuiltinBySid {
    param([string]$Sid, [string]$MemberSam)
    $group = Get-ADGroup -Identity $Sid -ErrorAction Stop
    Add-ADGroupMember -Identity $group.DistinguishedName -Members $MemberSam -ErrorAction SilentlyContinue
    Write-Host "[OK] $MemberSam agregado a $($group.Name)" -ForegroundColor Green
}

Write-Host "Practica 09 - RBAC y delegacion" -ForegroundColor Green

Ensure-DelegatedUser "admin_identidad" "Admin Identidad"
Ensure-DelegatedUser "admin_storage" "Admin Storage"
Ensure-DelegatedUser "admin_politicas" "Admin Politicas"
Ensure-DelegatedUser "admin_auditoria" "Admin Auditoria"

Write-Host "`n> Rol 1: admin_identidad sobre usuarios de Cuates y No Cuates" -ForegroundColor Cyan
foreach ($ou in $targetOus) {
    dsacls $ou /I:T /G "$netbios\admin_identidad:CCDC;user" | Out-Null
    dsacls $ou /I:S /G "$netbios\admin_identidad:CA;Reset Password;user" | Out-Null
    dsacls $ou /I:S /G "$netbios\admin_identidad:RPWP;user" | Out-Null
    Write-Host "[OK] ACL aplicada en $ou" -ForegroundColor Green
}

Write-Host "`n> Rol 2: admin_storage para FSRM y denegacion de Reset Password" -ForegroundColor Cyan
Add-ToBuiltinBySid -Sid "S-1-5-32-549" -MemberSam "admin_storage"
dsacls $domainDn /I:T /D "$netbios\admin_storage:CA;Reset Password;user" | Out-Null
Write-Host "[OK] Deny Reset Password aplicado para admin_storage" -ForegroundColor Green

Write-Host "`n> Rol 3: admin_politicas para GPOs existentes y linking en OUs" -ForegroundColor Cyan
$domainSid = $domain.DomainSID.Value
Add-ADGroupMember -Identity "$domainSid-520" -Members "admin_politicas" -ErrorAction SilentlyContinue
foreach ($ou in $targetOus) {
    dsacls $ou /I:S /G "$netbios\admin_politicas:RPWP;gPLink" | Out-Null
    dsacls $ou /I:S /G "$netbios\admin_politicas:RPWP;gPOptions" | Out-Null
}
Get-GPO -All | ForEach-Object {
    Set-GPPermission -Name $_.DisplayName -TargetName "admin_politicas" -TargetType User -PermissionLevel GpoEdit -ErrorAction SilentlyContinue
}
Write-Host "[OK] Permisos de GPO aplicados a admin_politicas" -ForegroundColor Green

Write-Host "`n> Rol 4: admin_auditoria solo lectura y lectura de logs" -ForegroundColor Cyan
Add-ToBuiltinBySid -Sid "S-1-5-32-573" -MemberSam "admin_auditoria"
dsacls $domainDn /I:T /G "$netbios\admin_auditoria:GR" | Out-Null
Write-Host "[OK] admin_auditoria configurado como lectura" -ForegroundColor Green

Write-Host "`nPassword temporal de delegados: $TempPassword" -ForegroundColor White
