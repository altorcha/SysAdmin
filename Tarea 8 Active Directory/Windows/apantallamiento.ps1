function Configurar-Apantallamiento {

    Write-Header "CONFIGURAR APANTALLAMIENTO DE ARCHIVOS"

    $fsrm = Get-WindowsFeature -Name "FS-Resource-Manager"
    if ($fsrm.InstallState -ne "Installed") {
        Write-Fila "ERR" "FSRM no esta instalado. Ejecuta primero la opcion 1."; Write-Host ""; return
    }

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Fila "ERR" "No se encontro usuarios.csv en $PSScriptRoot"; Write-Host ""; return
    }

    $usuarios    = Import-Csv -Path $csvPath
    $carpetaRaiz = "C:\Usuarios"
    $grupoNombre = "Practica8-ArchivosProhibidos"

    Write-Host "  Tipos de archivo que seran bloqueados en todas las carpetas:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "Multimedia   :  *.mp3  *.mp4"
    Write-Fila "INF" "Ejecutables  :  *.exe  *.msi"
    Write-Host ""
    Write-Host "  Tipo  :  ACTIVO  (el servidor rechaza el archivo en tiempo real)" -ForegroundColor DarkYellow
    Write-Host ""

    if (-not (Confirm-Accion "Deseas continuar?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    # -- Grupo de archivos --
    Write-Host ""
    Write-Host "  Creando grupo de archivos prohibidos..." -ForegroundColor Gray
    Write-Host ""

    try {
        $grupoExiste = Get-FsrmFileGroup -Name $grupoNombre -ErrorAction SilentlyContinue
        if ($grupoExiste) {
            Set-FsrmFileGroup -Name $grupoNombre -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
            Write-Fila "UPD" "Grupo actualizado  ->  $grupoNombre"
        } else {
            New-FsrmFileGroup -Name $grupoNombre -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
            Write-Fila "NEW" "Grupo creado       ->  $grupoNombre"
        }
    } catch {
        Write-Fila "ERR" "No se pudo gestionar el grupo  :  $($_.Exception.Message)"; return
    }

    # -- Plantilla de apantallamiento --
    Write-Host ""
    Write-Host "  Creando plantilla de apantallamiento..." -ForegroundColor Gray
    Write-Host ""

    $plantillaNombre = "Practica8-Apantallamiento"

    try {
        $plantillaExiste = Get-FsrmFileScreenTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue
        if ($plantillaExiste) {
            Set-FsrmFileScreenTemplate -Name $plantillaNombre -Active:$true -IncludeGroup @($grupoNombre) | Out-Null
            Write-Fila "UPD" "Plantilla actualizada  ->  $plantillaNombre"
        } else {
            New-FsrmFileScreenTemplate -Name $plantillaNombre -Active:$true -IncludeGroup @($grupoNombre) | Out-Null
            Write-Fila "NEW" "Plantilla creada       ->  $plantillaNombre"
        }
    } catch {
        Write-Fila "ERR" "No se pudo gestionar la plantilla  :  $($_.Exception.Message)"; return
    }

    # -- Aplicar a carpetas --
    Write-Host ""
    Write-Host "  Aplicando apantallamiento a carpetas de usuarios..." -ForegroundColor Gray
    Write-Host ""

    $creados = 0; $actualizados = 0; $errores = 0

    foreach ($u in $usuarios) {
        $carpetaUsuario = "$carpetaRaiz\$($u.Usuario)"

        if (-not (Test-Path $carpetaUsuario)) {
            Write-Fila "AVS" "Carpeta no existe  ->  $carpetaUsuario  (ejecuta opcion 5 primero)"
            $errores++; continue
        }

        try {
            $screenExiste = Get-FsrmFileScreen -Path $carpetaUsuario -ErrorAction SilentlyContinue
            if ($screenExiste) {
                Set-FsrmFileScreen -Path $carpetaUsuario -Template $plantillaNombre | Out-Null
                Write-Fila "UPD" "$($u.Usuario)  ->  apantallamiento actualizado"
                $actualizados++
            } else {
                New-FsrmFileScreen -Path $carpetaUsuario -Template $plantillaNombre | Out-Null
                Write-Fila "OK"  "$($u.Usuario)  ->  .mp3 .mp4 .exe .msi  bloqueados"
                $creados++
            }
        } catch {
            Write-Fila "ERR" "$($u.Usuario)  :  $($_.Exception.Message)"; $errores++
        }
    }

    Write-Resumen @(
        @{ Label = "Screens creados";      Valor = $creados;      Color = "Green"      },
        @{ Label = "Screens actualizados"; Valor = $actualizados; Color = "DarkYellow" },
        @{ Label = "Errores";              Valor = $errores;      Color = "Red"        }
    )
}
