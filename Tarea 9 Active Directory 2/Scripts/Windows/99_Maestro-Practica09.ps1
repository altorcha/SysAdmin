#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateSet("Menu","00","01","02","03","04","05","01-04")]
    [string]$Phase = "Menu",

    [string]$DomainName = "practica.local",
    [string]$NetbiosName = "PRACTICA",
    [string]$CsvPath = (Join-Path $PSScriptRoot "usuarios.csv"),
    [string]$MsiPath = (Join-Path $PSScriptRoot "MFA_Install.msi")
)

$ErrorActionPreference = "Stop"

function Write-Banner {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host " Practica 09 - Active Directory 2              " -ForegroundColor White
    Write-Host "===============================================" -ForegroundColor Cyan
}

function Show-Config {
    $role = (Get-CimInstance Win32_ComputerSystem).DomainRole
    Write-Host ""
    Write-Host "Configuracion actual" -ForegroundColor Yellow
    Write-Host "  Fase seleccionada : $Phase" -ForegroundColor DarkGray
    Write-Host "  DomainRole        : $role" -ForegroundColor DarkGray
    Write-Host "  DomainName        : $DomainName" -ForegroundColor DarkGray
    Write-Host "  NetbiosName       : $NetbiosName" -ForegroundColor DarkGray
    Write-Host "  CsvPath           : $CsvPath" -ForegroundColor DarkGray
    Write-Host "  MsiPath           : $MsiPath" -ForegroundColor DarkGray
}

function Pause-ForSnapshot {
    param(
        [string]$PhaseLabel,
        [string]$SnapshotName
    )

    Write-Host ""
    Write-Host "[IMPORTANTE] Fase completada: $PhaseLabel" -ForegroundColor Green
    Write-Host "[RECUERDA] Toma una instantanea de la VM ahora." -ForegroundColor Yellow
    Write-Host "           Nombre sugerido: $SnapshotName" -ForegroundColor White
    Write-Host "           VirtualBox > Maquina > Tomar instantanea" -ForegroundColor DarkGray
    Read-Host "Presiona Enter cuando ya hayas tomado la instantanea"
}

function Invoke-ChildScript {
    param(
        [string]$Path,
        [hashtable]$Parameters = @{}
    )

    if (-not (Test-Path $Path)) {
        throw "No se encontro el script: $Path"
    }

    Write-Host ""
    Write-Host ">> Ejecutando $(Split-Path $Path -Leaf)" -ForegroundColor Cyan
    & $Path @Parameters
}

function Invoke-Phase00 {
    $roleBefore = (Get-CimInstance Win32_ComputerSystem).DomainRole
    if ($roleBefore -ge 4) {
        Invoke-ChildScript -Path (Join-Path $PSScriptRoot "00_Preparar-Servidor.ps1") -Parameters @{
            DomainName = $DomainName
            NetbiosName = $NetbiosName
        }
        Pause-ForSnapshot -PhaseLabel "00 - Servidor base / DC ya presente" -SnapshotName "P09_Fase00_DC_OK"
        return
    }

    Invoke-ChildScript -Path (Join-Path $PSScriptRoot "00_Preparar-Servidor.ps1") -Parameters @{
        DomainName = $DomainName
        NetbiosName = $NetbiosName
        PromoteForest = $true
    }

    $roleAfter = (Get-CimInstance Win32_ComputerSystem).DomainRole
    if ($roleAfter -ge 4) {
        Pause-ForSnapshot -PhaseLabel "00 - Dominio promovido" -SnapshotName "P09_Fase00_DominioPromovido"
    } else {
        Write-Host ""
        Write-Host "[AVISO] Si el servidor pide reinicio o la promocion aun no se refleja, reinicia ahora." -ForegroundColor Yellow
        Write-Host "        Despues de volver a entrar, ejecuta otra vez el maestro y toma una instantanea." -ForegroundColor Yellow
    }
}

function Invoke-Phase01 {
    $params = @{}
    if (Test-Path $CsvPath) {
        $params.CsvPath = $CsvPath
    } else {
        Write-Host "[AVISO] No se encontro usuarios.csv. Se usaran usuarios de ejemplo." -ForegroundColor Yellow
    }
    Invoke-ChildScript -Path (Join-Path $PSScriptRoot "01_Crear-Estructura-AD.ps1") -Parameters $params
    Pause-ForSnapshot -PhaseLabel "01 - Estructura AD y usuarios" -SnapshotName "P09_Fase01_EstructuraAD"
}

function Invoke-Phase02 {
    Invoke-ChildScript -Path (Join-Path $PSScriptRoot "02_Configurar-RBAC.ps1")
    Pause-ForSnapshot -PhaseLabel "02 - RBAC y delegacion" -SnapshotName "P09_Fase02_RBAC"
}

function Invoke-Phase03 {
    Invoke-ChildScript -Path (Join-Path $PSScriptRoot "03_FGPP-Auditoria.ps1")
    Pause-ForSnapshot -PhaseLabel "03 - FGPP y auditoria" -SnapshotName "P09_Fase03_FGPP_Auditoria"
}

function Invoke-Phase04 {
    Invoke-ChildScript -Path (Join-Path $PSScriptRoot "04_Verificar-Practica09.ps1")
    Pause-ForSnapshot -PhaseLabel "04 - Verificacion general" -SnapshotName "P09_Fase04_Verificada"
}

function Invoke-Phase05 {
    if (-not (Test-Path $MsiPath)) {
        throw "No se encontro MFA_Install.msi en: $MsiPath"
    }
    Invoke-ChildScript -Path (Join-Path $PSScriptRoot "05_MFA-WindowsLogon-MultiOTP.ps1") -Parameters @{
        MsiPath = $MsiPath
    }
    Pause-ForSnapshot -PhaseLabel "05 - MFA instalado" -SnapshotName "P09_Fase05_MFA_Instalado"
}

function Show-Menu {
    while ($true) {
        Write-Banner
        Show-Config
        Write-Host ""
        Write-Host "1. Fase 00 - Preparar servidor / promover a DC"
        Write-Host "2. Fase 01 - Crear estructura AD y usuarios"
        Write-Host "3. Fase 02 - Configurar RBAC"
        Write-Host "4. Fase 03 - FGPP y auditoria"
        Write-Host "5. Fase 04 - Verificacion"
        Write-Host "6. Fase 05 - MFA multiOTP"
        Write-Host "7. Ejecutar fases 01 a 04"
        Write-Host "8. Mostrar configuracion actual"
        Write-Host "Q. Salir"

        $choice = Read-Host "Selecciona una opcion"
        switch ($choice.ToUpperInvariant()) {
            "1" { Invoke-Phase00 }
            "2" { Invoke-Phase01 }
            "3" { Invoke-Phase02 }
            "4" { Invoke-Phase03 }
            "5" { Invoke-Phase04 }
            "6" { Invoke-Phase05 }
            "7" {
                Invoke-Phase01
                Invoke-Phase02
                Invoke-Phase03
                Invoke-Phase04
            }
            "8" {
                Show-Config
                Read-Host "Presiona Enter para volver al menu"
            }
            "Q" { break }
            default {
                Write-Host "Opcion invalida." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    }
}

switch ($Phase) {
    "Menu"  { Show-Menu }
    "00"    { Show-Config; Invoke-Phase00 }
    "01"    { Show-Config; Invoke-Phase01 }
    "02"    { Show-Config; Invoke-Phase02 }
    "03"    { Show-Config; Invoke-Phase03 }
    "04"    { Show-Config; Invoke-Phase04 }
    "05"    { Show-Config; Invoke-Phase05 }
    "01-04" {
        Show-Config
        Invoke-Phase01
        Invoke-Phase02
        Invoke-Phase03
        Invoke-Phase04
    }
}
