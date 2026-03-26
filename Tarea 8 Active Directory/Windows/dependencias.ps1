function Instalar-Dependencias {

    Write-Header "INSTALACION DE DEPENDENCIAS"

    $dependencias = @(
        @{ Nombre = "AD-Domain-Services";  Desc = "Active Directory Domain Services" },
        @{ Nombre = "DNS";                 Desc = "Servidor DNS"                     },
        @{ Nombre = "FS-Resource-Manager"; Desc = "FSRM  (Cuotas y Apantallamiento)" },
        @{ Nombre = "RSAT-AD-PowerShell";  Desc = "PowerShell para AD"               },
        @{ Nombre = "RSAT-ADDS";           Desc = "Herramientas de administracion AD" }
    )

    Write-Host "  Estado actual de dependencias:" -ForegroundColor Gray
    Write-Host ""

    $porInstalar = @()
    foreach ($dep in $dependencias) {
        $feat = Get-WindowsFeature -Name $dep.Nombre
        if ($feat.InstallState -eq "Installed") {
            Write-Fila "OK"  $dep.Desc
        } else {
            Write-Fila "INF" $dep.Desc
            $porInstalar += $dep
        }
    }

    Write-Host ""

    if ($porInstalar.Count -eq 0) {
        Write-Host "  Todas las dependencias estan instaladas." -ForegroundColor Gray
        Write-Host ""
        if (-not (Confirm-Accion "Reinstalar de todas formas?")) {
            Write-Sep; Write-Fila "INF" "Sin cambios."; Write-Host ""; return
        }
        $porInstalar = $dependencias
    }

    Write-Host "  Se instalaran los siguientes componentes:" -ForegroundColor Gray
    Write-Host ""
    foreach ($dep in $porInstalar) { Write-Fila "INF" $dep.Desc }
    Write-Host ""

    if (-not (Confirm-Accion "Confirmas la instalacion?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    Write-Host ""
    Write-Host "  Instalando componentes, esto puede tardar unos minutos..." -ForegroundColor Gray
    Write-Host ""

    foreach ($dep in $porInstalar) {
        Write-Host "  Instalando  $($dep.Desc)..." -ForegroundColor Gray
        $r = Install-WindowsFeature -Name $dep.Nombre -IncludeManagementTools
        if ($r.Success) { Write-Fila "OK"  $dep.Desc }
        else            { Write-Fila "ERR" "Fallo al instalar  $($dep.Desc)" }
    }

    Write-Host ""
    Write-Sep
    Write-Fila "INF" "Siguiente paso  ->  Opcion 2  :  Promover a Domain Controller"
    Write-Host ""
}
