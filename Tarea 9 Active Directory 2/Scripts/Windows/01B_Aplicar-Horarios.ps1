#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

$domain = Get-ADDomain
$domainDn = $domain.DistinguishedName
$ouCuates = "OU=Cuates,$domainDn"
$ouNoCuates = "OU=No Cuates,$domainDn"

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

function Apply-LogonHoursToOu {
    param(
        [Parameter(Mandatory)]
        [string]$SearchBase,
        [Parameter(Mandatory)]
        [byte[]]$Hours,
        [Parameter(Mandatory)]
        [string]$Label
    )

    $users = Get-ADUser -Filter * -SearchBase $SearchBase -ErrorAction SilentlyContinue
    if (-not $users) {
        Write-Host "[AVISO] No se encontraron usuarios en $Label" -ForegroundColor Yellow
        return
    }

    foreach ($user in $users) {
        Set-ADUser -Identity $user.SamAccountName -Replace @{logonHours = $Hours}
        Write-Host "[OK] $($user.SamAccountName) -> $Label" -ForegroundColor Green
    }
}

$hoursCuates = Convert-GroupScheduleToLogonHours -StartHourLocal 8 -EndHourLocal 15
$hoursNoCuates = Convert-GroupScheduleToLogonHours -StartHourLocal 15 -EndHourLocal 2

Write-Host "Practica 09 - Aplicar horarios por grupo" -ForegroundColor Green
Write-Host "Cuates    -> 08:00 a 15:00" -ForegroundColor White
Write-Host "No Cuates -> 15:00 a 02:00" -ForegroundColor White

Apply-LogonHoursToOu -SearchBase $ouCuates -Hours $hoursCuates -Label "Cuates (08:00-15:00)"
Apply-LogonHoursToOu -SearchBase $ouNoCuates -Hours $hoursNoCuates -Label "No Cuates (15:00-02:00)"

Write-Host ""
Write-Host "[OK] Horarios aplicados." -ForegroundColor Green
Write-Host "[RECUERDA] Si esto forma parte de tu evidencia final, toma una instantanea antes o despues segun tu estrategia." -ForegroundColor Yellow
