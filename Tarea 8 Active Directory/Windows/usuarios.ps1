function Crear-OUsYUsuarios {

    Write-Header "CREAR OUs Y USUARIOS DESDE CSV"

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Fila "ERR" "AD no disponible. Ejecuta primero las opciones 1 y 2."; Write-Host ""; return
    }

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Fila "ERR" "No se encontro  usuarios.csv  en:"
        Write-Host "       $csvPath" -ForegroundColor Gray
        Write-Host ""; return
    }

    $usuarios = Import-Csv -Path $csvPath
    Write-Fila "INF" "Usuarios encontrados en CSV  :  $($usuarios.Count)"
    Write-Host ""

    if (-not (Confirm-Accion "Crear OUs y usuarios?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    $dcBase = $dominio.DistinguishedName

    # -- Crear OUs --
    Write-Host "  Creando unidades organizativas..." -ForegroundColor Gray
    Write-Host ""

    foreach ($ou in @("Cuates", "NoCuates")) {
        $ouPath = "OU=$ou,$dcBase"
        try {
            Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
            Write-Fila "UPD" "OU ya existe  ->  $ou"
        } catch {
            try {
                New-ADOrganizationalUnit -Name $ou -Path $dcBase -ProtectedFromAccidentalDeletion $false
                Write-Fila "NEW" "OU creada     ->  $ou"
            } catch {
                Write-Fila "ERR" "No se pudo crear OU $ou  :  $($_.Exception.Message)"
            }
        }
    }

    # -- Crear usuarios --
    Write-Host ""
    Write-Host "  Creando usuarios..." -ForegroundColor Gray
    Write-Host ""

    $creados = 0; $omitidos = 0; $errores = 0

    foreach ($u in $usuarios) {
        $ouDestino = "OU=$($u.Departamento),$dcBase"
        try {
            Get-ADUser -Identity $u.Usuario -ErrorAction Stop | Out-Null
            Write-Fila "UPD" "$($u.Usuario)  ya existe  ->  omitido"
            $omitidos++; continue
        } catch {}

        try {
            $passwordSegura = ConvertTo-SecureString $u.Password -AsPlainText -Force
            New-ADUser `
                -Name "$($u.Nombre) $($u.Apellido)" `
                -GivenName $u.Nombre `
                -Surname $u.Apellido `
                -SamAccountName $u.Usuario `
                -UserPrincipalName "$($u.Usuario)@practica8.local" `
                -Path $ouDestino `
                -AccountPassword $passwordSegura `
                -Enabled $true `
                -PasswordNeverExpires $true `
                -ChangePasswordAtLogon $false

            Write-Fila "NEW" "$($u.Nombre) $($u.Apellido)  ->  $($u.Departamento)"
            $creados++
        } catch {
            Write-Fila "ERR" "$($u.Usuario)  :  $($_.Exception.Message)"; $errores++
        }
    }

    # -- Crear grupos --
    Write-Host ""
    Write-Host "  Creando grupos de seguridad..." -ForegroundColor Gray
    Write-Host ""

    foreach ($g in @(
        @{ Nombre = "Cuates";   OU = "OU=Cuates,$dcBase"   },
        @{ Nombre = "NoCuates"; OU = "OU=NoCuates,$dcBase" }
    )) {
        try {
            Get-ADGroup -Identity $g.Nombre -ErrorAction Stop | Out-Null
            Write-Fila "UPD" "Grupo ya existe  ->  $($g.Nombre)"
        } catch {
            try {
                New-ADGroup -Name $g.Nombre -GroupScope Global -GroupCategory Security -Path $g.OU
                Write-Fila "NEW" "Grupo creado     ->  $($g.Nombre)"
            } catch {
                Write-Fila "ERR" "No se pudo crear $($g.Nombre)  :  $($_.Exception.Message)"
            }
        }
    }

    # -- Asignar usuarios a grupos --
    Write-Host ""
    Write-Host "  Asignando usuarios a grupos..." -ForegroundColor Gray
    Write-Host ""

    foreach ($u in $usuarios) {
        try {
            Add-ADGroupMember -Identity $u.Departamento -Members $u.Usuario -ErrorAction Stop
            Write-Fila "OK" "$($u.Usuario)  ->  $($u.Departamento)"
        } catch {
            Write-Fila "AVS" "$($u.Usuario)  ->  $($u.Departamento)  :  $($_.Exception.Message)"
        }
    }

    Write-Resumen @(
        @{ Label = "Usuarios creados";   Valor = $creados;  Color = "Green"      },
        @{ Label = "Usuarios omitidos";  Valor = $omitidos; Color = "DarkYellow" },
        @{ Label = "Errores";            Valor = $errores;  Color = "Red"        }
    )
}
