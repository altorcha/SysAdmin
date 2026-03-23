# ============================================================
# ui.ps1
# Practica 7 - Interfaz de Usuario - Entrada y Salida
# Windows Server 2019/2022 - PowerShell
# ============================================================

function Escribir-Titulo {
    param([string]$Texto)
    $linea = "=" * 60
    Write-Host ""
    Write-Host $linea -ForegroundColor Cyan
    Write-Host "  $Texto" -ForegroundColor Cyan
    Write-Host $linea -ForegroundColor Cyan
    Write-Host ""
}

function Escribir-SubTitulo {
    param([string]$Texto)
    Write-Host ""
    Write-Host "--- $Texto ---" -ForegroundColor Yellow
}

function Leer-Texto {
    param([string]$Prompt, [string]$Default = "")
    while ($true) {
        if ($Default) {
            Write-Host "$Prompt (Enter = '$Default'): " -NoNewline
        } else {
            Write-Host "${Prompt}: " -NoNewline
        }
        $val = Read-Host
        if ([string]::IsNullOrWhiteSpace($val) -and $Default) { return $Default }
        if (-not [string]::IsNullOrWhiteSpace($val)) { return $val.Trim() }
        Write-Host "  No puede estar vacio." -ForegroundColor Red
    }
}

function Leer-Opcion {
    param([string]$Prompt, [string[]]$Validas)
    while ($true) {
        Write-Host "${Prompt}: " -NoNewline
        $val = (Read-Host).Trim()
        if ($Validas -contains $val) { return $val }
        Write-Host "  Opcion no valida. Validas: $($Validas -join ', ')" -ForegroundColor Red
    }
}

function Leer-Puerto {
    param([string]$Prompt = "Puerto de escucha", [int]$Default = 0)
    while ($true) {
        $raw = Leer-Texto -Prompt $Prompt -Default $(if ($Default) { "$Default" } else { "" })
        if ($raw -notmatch '^\d+$') { Write-Host "  Debe ser un numero entero." -ForegroundColor Red; continue }
        $p = [int]$raw
        if ($p -lt 1 -or $p -gt 65535) { Write-Host "  Rango valido: 1-65535." -ForegroundColor Red; continue }
        $enUso = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
        if ($enUso.TcpTestSucceeded) {
            Write-Host "  Puerto $p ya esta en uso por otro proceso." -ForegroundColor Yellow
            $cont = Leer-Opcion -Prompt "  ¿Usar de todas formas? [S/N]" -Validas @("S","N","s","n")
            if ($cont -match "^[Nn]$") { continue }
        }
        return $p
    }
}

function Registrar-Resumen {
    param([string]$Servicio, [string]$Accion, [string]$Estado, [string]$Detalle = "")
    $global:RESUMEN += [PSCustomObject]@{
        Servicio = $Servicio
        Accion   = $Accion
        Estado   = $Estado
        Detalle  = $Detalle
    }
}

