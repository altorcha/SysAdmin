function Configurar-CuotasFSRM {

    Write-Header "CONFIGURAR CUOTAS FSRM"

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

    Write-Host "  Configuracion que se aplicara:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "Carpeta raiz  :  $carpetaRaiz\<usuario>"
    Write-Fila "INF" "Cuates        :  10 MB  (cuota estricta)"
    Write-Fila "INF" "NoCuates      :   5 MB  (cuota estricta)"
    Write-Host ""
    Write-Host "  El servidor bloqueara archivos que superen el limite asignado." -ForegroundColor DarkYellow
    Write-Host ""

    if (-not (Confirm-Accion "Deseas continuar?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    # -- Carpeta raiz --
    if (-not (Test-Path $carpetaRaiz)) {
        New-Item -Path $carpetaRaiz -ItemType Directory | Out-Null
        Write-Fila "NEW" "Carpeta raiz creada  ->  $carpetaRaiz"
    } else {
        Write-Fila "UPD" "Carpeta raiz ya existe  ->  $carpetaRaiz"
    }

    # -- Recurso compartido --
    Write-Host ""
    $shareExiste = Get-SmbShare -Name "Usuarios" -ErrorAction SilentlyContinue
    if (-not $shareExiste) {
        New-SmbShare -Name "Usuarios" -Path $carpetaRaiz `
            -FullAccess "PRACTICA8\Domain Admins" `
            -ChangeAccess "PRACTICA8\Domain Users" | Out-Null
        Write-Fila "NEW" "Recurso compartido  ->  \\192.168.10.11\Usuarios"
    } else {
        Write-Fila "UPD" "Recurso compartido ya existe."
    }

    # -- Permisos NTFS --
    $acl   = Get-Acl $carpetaRaiz
    $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "PRACTICA8\Domain Users","Modify","ContainerInherit,ObjectInherit","None","Allow")
    $acl.AddAccessRule($regla)
    Set-Acl $carpetaRaiz $acl
    Write-Fila "OK" "Permisos NTFS configurados para Domain Users."

    # -- Plantillas de cuota --
    Write-Host ""
    Write-Host "  Creando plantillas de cuota..." -ForegroundColor Gray
    Write-Host ""

    foreach ($p in @(
        @{ Nombre = "Practica8-Cuates-10MB";  Tamano = 10MB },
        @{ Nombre = "Practica8-NoCuates-5MB"; Tamano = 5MB  }
    )) {
        try {
            $existe = Get-FsrmQuotaTemplate -Name $p.Nombre -ErrorAction SilentlyContinue
            if ($existe) {
                Write-Fila "UPD" "Plantilla ya existe  ->  $($p.Nombre)"
            } else {
                New-FsrmQuotaTemplate -Name $p.Nombre -Size $p.Tamano -SoftLimit:$false | Out-Null
                Write-Fila "NEW" "Plantilla creada    ->  $($p.Nombre)  ($($p.Tamano / 1MB) MB)"
            }
        } catch {
            Write-Fila "ERR" "No se pudo crear $($p.Nombre)  :  $($_.Exception.Message)"
        }
    }

    # -- Cuotas por usuario --
    Write-Host ""
    Write-Host "  Aplicando cuotas a usuarios..." -ForegroundColor Gray
    Write-Host ""

    $creadas = 0; $actualizadas = 0; $errores = 0

    foreach ($u in $usuarios) {
        $carpetaUsuario = "$carpetaRaiz\$($u.Usuario)"

        if ($u.Departamento -eq "Cuates") {
            $plantillaNombre = "Practica8-Cuates-10MB";  $tamanoBytes = 10MB; $tamanoTexto = "10 MB"
        } elseif ($u.Departamento -eq "NoCuates") {
            $plantillaNombre = "Practica8-NoCuates-5MB"; $tamanoBytes = 5MB;  $tamanoTexto = " 5 MB"
        } else {
            Write-Fila "AVS" "$($u.Usuario)  :  departamento desconocido, omitido."; continue
        }

        if (-not (Test-Path $carpetaUsuario)) {
            try {
                New-Item -Path $carpetaUsuario -ItemType Directory | Out-Null
                Write-Fila "NEW" "Carpeta creada  ->  $carpetaUsuario"
            } catch {
                Write-Fila "ERR" "No se pudo crear carpeta  $carpetaUsuario"; $errores++; continue
            }
        }

        try {
            $cuotaExiste     = Get-FsrmQuota -Path $carpetaUsuario -ErrorAction SilentlyContinue
            $plantillaExiste = Get-FsrmQuotaTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue

            if ($cuotaExiste) {
                if ($plantillaExiste) { Set-FsrmQuota -Path $carpetaUsuario -Template $plantillaNombre | Out-Null }
                else                  { Set-FsrmQuota -Path $carpetaUsuario -Size $tamanoBytes -SoftLimit:$false | Out-Null }
                Write-Fila "UPD" "$($u.Usuario)  ($($u.Departamento))  ->  $tamanoTexto  actualizado"
                $actualizadas++
            } else {
                if ($plantillaExiste) { New-FsrmQuota -Path $carpetaUsuario -Template $plantillaNombre | Out-Null }
                else                  { New-FsrmQuota -Path $carpetaUsuario -Size $tamanoBytes -SoftLimit:$false | Out-Null }
                Write-Fila "OK"  "$($u.Usuario)  ($($u.Departamento))  ->  $tamanoTexto"
                $creadas++
            }
        } catch {
            Write-Fila "ERR" "$($u.Usuario)  :  $($_.Exception.Message)"; $errores++
        }
    }

    Write-Resumen @(
        @{ Label = "Cuotas creadas";      Valor = $creadas;      Color = "Green"      },
        @{ Label = "Cuotas actualizadas"; Valor = $actualizadas; Color = "DarkYellow" },
        @{ Label = "Errores";             Valor = $errores;      Color = "Red"        }
    )
}
