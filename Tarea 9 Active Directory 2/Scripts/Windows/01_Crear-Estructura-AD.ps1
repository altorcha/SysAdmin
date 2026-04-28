#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$TempPassword = "P@ssw0rd.Pr09!",
    [string]$CsvPath
)

$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

$domain = Get-ADDomain
$domainDn = $domain.DistinguishedName
$dnsRoot = $domain.DNSRoot
$server = $env:COMPUTERNAME
$securePassword = ConvertTo-SecureString $TempPassword -AsPlainText -Force

function Convert-GroupScheduleToLogonHours {
    param(
        [Parameter(Mandatory)]
        [int]$StartHourLocal,
        [Parameter(Mandatory)]
        [int]$EndHourLocal
    )

    [byte[]]$hours = New-Object byte[] 21
    $offset = [System.TimeZoneInfo]::Local.BaseUtcOffset.Hours
    $startUtc = ($StartHourLocal - $offset + 24) % 24
    $endUtc = ($EndHourLocal - $offset + 24) % 24

    for ($day = 0; $day -lt 7; $day++) {
        for ($hour = 0; $hour -lt 24; $hour++) {
            $allowed = if ($startUtc -lt $endUtc) {
                ($hour -ge $startUtc -and $hour -lt $endUtc)
            } else {
                ($hour -ge $startUtc -or $hour -lt $endUtc)
            }

            if ($allowed) {
                $byteIndex = ($day * 3) + [math]::Floor($hour / 8)
                $bitIndex = $hour % 8
                $hours[$byteIndex] = $hours[$byteIndex] -bor (1 -shl $bitIndex)
            }
        }
    }

    return $hours
}

function Ensure-OU {
    param([string]$Name, [string]$Path)
    $dn = "OU=$Name,$Path"
    $exists = $false
    try {
        $null = Get-ADOrganizationalUnit -Identity $dn -ErrorAction Stop
        $exists = $true
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $exists = $false
    }

    if (-not $exists) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $false | Out-Null
        Write-Host "[OK] OU creada: $Name" -ForegroundColor Green
    } else {
        Write-Host "[OK] OU existente: $Name" -ForegroundColor DarkGray
    }
}

function Ensure-User {
    param(
        [string]$Sam,
        [string]$Name,
        [string]$OuDn,
        [securestring]$Password = $securePassword
    )
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue)) {
        New-ADUser `
            -Name $Name `
            -SamAccountName $Sam `
            -UserPrincipalName "$Sam@$dnsRoot" `
            -Path $OuDn `
            -AccountPassword $Password `
            -Enabled $true `
            -ChangePasswordAtLogon $false | Out-Null
        Write-Host "[OK] Usuario creado: $Sam" -ForegroundColor Green
    } else {
        Write-Host "[OK] Usuario existente: $Sam" -ForegroundColor DarkGray
    }
}

Write-Host "Practica 09 - Estructura base de AD" -ForegroundColor Green

Ensure-OU -Name "Cuates" -Path $domainDn
Ensure-OU -Name "No Cuates" -Path $domainDn
Ensure-OU -Name "Administradores Delegados" -Path $domainDn

$ouCuates = "OU=Cuates,$domainDn"
$ouNoCuates = "OU=No Cuates,$domainDn"
$logonHoursCuates = Convert-GroupScheduleToLogonHours -StartHourLocal 8 -EndHourLocal 15
$logonHoursNoCuates = Convert-GroupScheduleToLogonHours -StartHourLocal 15 -EndHourLocal 2

$shareRoot = "C:\Shares\Usuarios"
if (-not (Test-Path $shareRoot)) {
    New-Item -Path $shareRoot -ItemType Directory -Force | Out-Null
}

if (-not (Get-SmbShare -Name "Usuarios" -ErrorAction SilentlyContinue)) {
    $authenticatedUsers = ([System.Security.Principal.SecurityIdentifier]"S-1-5-11").Translate([System.Security.Principal.NTAccount]).Value
    $administrators = ([System.Security.Principal.SecurityIdentifier]"S-1-5-32-544").Translate([System.Security.Principal.NTAccount]).Value
    New-SmbShare -Name "Usuarios" -Path $shareRoot -ChangeAccess $authenticatedUsers -FullAccess $administrators | Out-Null
}

if ($CsvPath) {
    $resolvedCsv = (Resolve-Path $CsvPath).ProviderPath
    $rows = Import-Csv -Path $resolvedCsv
    foreach ($row in $rows) {
        $sam = $row.Usuario.Trim()
        $fullName = "$($row.Nombre.Trim()) $($row.Apellido.Trim())"
        $department = $row.Departamento.Trim()
        $ouDn = switch -Regex ($department) {
            "^Cuates$" { $ouCuates; break }
            "^No\s*Cuates$|^NoCuates$|^No_Cuates$" { $ouNoCuates; break }
            default { throw "Departamento no reconocido para ${sam}: $department" }
        }
        $rowPassword = ConvertTo-SecureString $row.Password -AsPlainText -Force
        Ensure-User -Sam $sam -Name $fullName -OuDn $ouDn -Password $rowPassword
        Set-ADUser -Identity $sam -GivenName $row.Nombre -Surname $row.Apellido -Department $department
        if ($ouDn -eq $ouCuates) {
            Set-ADUser -Identity $sam -Replace @{logonHours = $logonHoursCuates}
        } else {
            Set-ADUser -Identity $sam -Replace @{logonHours = $logonHoursNoCuates}
        }
    }
} else {
    Ensure-User -Sam "usuario_cuates01" -Name "Usuario Cuates 01" -OuDn $ouCuates
    Ensure-User -Sam "usuario_nocuates01" -Name "Usuario No Cuates 01" -OuDn $ouNoCuates
    Set-ADUser -Identity "usuario_cuates01" -Replace @{logonHours = $logonHoursCuates}
    Set-ADUser -Identity "usuario_nocuates01" -Replace @{logonHours = $logonHoursNoCuates}
}

$createdUsers = Get-ADUser -Filter * -SearchBase $ouCuates | Select-Object -ExpandProperty SamAccountName
$createdUsers += Get-ADUser -Filter * -SearchBase $ouNoCuates | Select-Object -ExpandProperty SamAccountName

foreach ($u in $createdUsers) {
    $homePath = Join-Path $shareRoot $u
    if (-not (Test-Path $homePath)) {
        New-Item -Path $homePath -ItemType Directory -Force | Out-Null
    }
    Set-ADUser -Identity $u -HomeDrive "H:" -HomeDirectory "\\$server\Usuarios\$u"
}

Write-Host "`nListo." -ForegroundColor White
if ($CsvPath) {
    Write-Host "Usuarios importados desde: $resolvedCsv" -ForegroundColor White
} else {
    Write-Host "Password temporal: $TempPassword" -ForegroundColor White
}
Write-Host "Horario Cuates    : 08:00 - 15:00" -ForegroundColor White
Write-Host "Horario No Cuates : 15:00 - 02:00" -ForegroundColor White
