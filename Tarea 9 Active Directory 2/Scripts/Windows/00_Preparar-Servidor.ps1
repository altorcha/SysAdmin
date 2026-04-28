#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$DomainName = "practica.local",
    [string]$NetbiosName = "PRACTICA",
    [switch]$PromoteForest
)

$ErrorActionPreference = "Stop"

function Write-Step($Text) {
    Write-Host "`n> $Text" -ForegroundColor Cyan
}

Write-Host "Practica 09 - Preparacion de Windows Server 2022 Core" -ForegroundColor Green

Write-Step "Instalando roles y herramientas base"
Install-WindowsFeature AD-Domain-Services, GPMC, RSAT-AD-PowerShell, FS-Resource-Manager -IncludeManagementTools | Out-Null

Write-Step "Verificando rol actual del servidor"
$role = (Get-CimInstance Win32_ComputerSystem).DomainRole
if ($role -ge 4) {
    Write-Host "[OK] Este servidor ya es Controlador de Dominio." -ForegroundColor Green
    exit 0
}

if (-not $PromoteForest) {
    Write-Host "[INFO] El servidor aun no es Controlador de Dominio." -ForegroundColor Yellow
    Write-Host "Ejecuta de nuevo con -PromoteForest para crear el bosque $DomainName." -ForegroundColor Yellow
    Write-Host "Ejemplo: .\00_Preparar-Servidor.ps1 -DomainName $DomainName -NetbiosName $NetbiosName -PromoteForest"
    exit 0
}

Write-Step "Promoviendo a Controlador de Dominio"
Write-Host "Se solicitara la contrasena DSRM. El servidor reiniciara al terminar." -ForegroundColor Yellow
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetbiosName `
    -InstallDns `
    -Force
