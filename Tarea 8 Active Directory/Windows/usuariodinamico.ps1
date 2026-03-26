function Crear-UsuarioDinamico {

    Write-Header "CREAR USUARIO DINAMICAMENTE"

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Fila "ERR" "AD no disponible. Ejecuta primero las opciones 1 y 2."; Write-Host ""; return
    }

    $dcBase      = $dominio.DistinguishedName
    $carpetaRaiz = "C:\Usuarios"

    Write-Host "  Ingresa los datos del nuevo usuario:" -ForegroundColor Gray
    Write-Host ""

    $nombre = Read-Host "  Nombre"
    if ([string]::IsNullOrWhiteSpace($nombre)) { Write-Fila "ERR" "El nombre no puede estar vacio."; return }

    $apellido = Read-Host "  Apellido"
    if ([string]::IsNullOrWhiteSpace($apellido)) { Write-Fila "ERR" "El apellido no puede estar vacio."; return }

    $usuario = Read-Host "  Usuario  (sin espacios ni caracteres especiales)"
    if ([string]::IsNullOrWhiteSpace($usuario)) { Write-Fila "ERR" "El usuario no puede estar vacio."; return }

    try {
        Get-ADUser -Identity $usuario -ErrorAction Stop | Out-Null
        Write-Fila "ERR" "El usuario '$usuario' ya existe en el dominio."; return
    } catch {}

    $password = Read-Host "  Password  (min 8 caracteres, mayuscula, numero y simbolo)"
    if ([string]::IsNullOrWhiteSpace($password)) { Write-Fila "ERR" "El password no puede estar vacio."; return }

    Write-Host ""
    Write-Host "  Departamento:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "1  ->  Cuates    (08:00 - 15:00  |  cuota 10 MB)"
    Write-Fila "INF" "2  ->  NoCuates  (15:00 - 02:00  |  cuota  5 MB)"
    Write-Host ""

    $deptoOpcion = Read-Host "  Selecciona el departamento (1 o 2)"

    if      ($deptoOpcion -eq "1") { $departamento = "Cuates"   }
    elseif  ($deptoOpcion -eq "2") { $departamento = "NoCuates" }
    else    { Write-Fila "ERR" "Opcion invalida. Elige 1 o 2."; return }

    # -- Confirmacion --
    Write-Host ""
    Write-Sep
    Write-Fila "INF" "Nombre       :  $nombre $apellido"
    Write-Fila "INF" "Usuario      :  $usuario@practica8.local"
    Write-Fila "INF" "Departamento :  $departamento"

    if ($departamento -eq "Cuates") {
        Write-Fila "INF" "Horario      :  08:00 - 15:00"
        Write-Fila "INF" "Cuota        :  10 MB"
    } else {
        Write-Fila "INF" "Horario      :  15:00 - 02:00"
        Write-Fila "INF" "Cuota        :   5 MB"
    }

    Write-Fila "INF" "Apantallam.  :  .mp3  .mp4  .exe  .msi  bloqueados"
    Write-Sep
    Write-Host ""

    if (-not (Confirm-Accion "Confirmas la creacion del usuario?")) {
        Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    # -- PASO 1  :  Crear en AD --
    Write-Host "  [ 1 / 5 ]  Creando usuario en Active Directory..." -ForegroundColor Gray
    try {
        $passwordSegura = ConvertTo-SecureString $password -AsPlainText -Force
        New-ADUser `
            -Name "$nombre $apellido" `
            -GivenName $nombre `
            -Surname $apellido `
            -SamAccountName $usuario `
            -UserPrincipalName "$usuario@practica8.local" `
            -Path "OU=$departamento,$dcBase" `
            -AccountPassword $passwordSegura `
            -Enabled $true `
            -PasswordNeverExpires $true `
            -ChangePasswordAtLogon $false

        Write-Fila "OK" "Usuario creado  ->  OU $departamento"
    } catch {
        Write-Fila "ERR" "No se pudo crear el usuario  :  $($_.Exception.Message)"; return
    }

    # -- PASO 2  :  Grupo --
    Write-Host "  [ 2 / 5 ]  Agregando al grupo $departamento..." -ForegroundColor Gray
    try {
        Add-ADGroupMember -Identity $departamento -Members $usuario -ErrorAction Stop
        Write-Fila "OK" "Agregado al grupo  ->  $departamento"
    } catch {
        Write-Fila "AVS" "No se pudo agregar al grupo  :  $($_.Exception.Message)"
    }

    # -- PASO 3  :  Horario --
    Write-Host "  [ 3 / 5 ]  Aplicando horario de acceso (UTC-7)..." -ForegroundColor Gray

    try {
        $horasUTC     = if ($departamento -eq "Cuates") { @(15,16,17,18,19,20,21) } else { @(22,23,0,1,2,3,4,5,6,7,8) }
        $bytesHorario = Build-LogonHours -HorasUTC $horasUTC
        Set-ADUser -Identity $usuario -Clear logonHours
        Set-ADUser -Identity $usuario -Replace @{logonHours = ([byte[]]$bytesHorario)}
        Write-Fila "OK" "Horario aplicado correctamente."
    } catch {
        Write-Fila "AVS" "No se pudo aplicar el horario  :  $($_.Exception.Message)"
    }

    # -- PASO 4  :  Cuota FSRM --
    Write-Host "  [ 4 / 5 ]  Creando carpeta y aplicando cuota FSRM..." -ForegroundColor Gray

    $carpetaUsuario = "$carpetaRaiz\$usuario"

    if (-not (Test-Path $carpetaUsuario)) {
        try {
            New-Item -Path $carpetaUsuario -ItemType Directory | Out-Null
            Write-Fila "NEW" "Carpeta creada  ->  $carpetaUsuario"
        } catch {
            Write-Fila "AVS" "No se pudo crear la carpeta  :  $($_.Exception.Message)"
        }
    } else {
        Write-Fila "UPD" "Carpeta ya existe  ->  $carpetaUsuario"
    }

    try {
        if ($departamento -eq "Cuates") {
            $plantillaNombre = "Practica8-Cuates-10MB";  $tamanoBytes = 10MB; $tamanoTexto = "10 MB"
        } else {
            $plantillaNombre = "Practica8-NoCuates-5MB"; $tamanoBytes = 5MB;  $tamanoTexto = " 5 MB"
        }

        $cuotaExiste     = Get-FsrmQuota -Path $carpetaUsuario -ErrorAction SilentlyContinue
        $plantillaExiste = Get-FsrmQuotaTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue

        if ($cuotaExiste) {
            if ($plantillaExiste) { Set-FsrmQuota -Path $carpetaUsuario -Template $plantillaNombre | Out-Null }
            else                  { Set-FsrmQuota -Path $carpetaUsuario -Size $tamanoBytes -SoftLimit:$false | Out-Null }
        } else {
            if ($plantillaExiste) { New-FsrmQuota -Path $carpetaUsuario -Template $plantillaNombre | Out-Null }
            else                  { New-FsrmQuota -Path $carpetaUsuario -Size $tamanoBytes -SoftLimit:$false | Out-Null }
        }
        Write-Fila "OK" "Cuota aplicada  ->  $tamanoTexto"
    } catch {
        Write-Fila "AVS" "No se pudo aplicar la cuota  :  $($_.Exception.Message)"
    }

    # -- PASO 5  :  Apantallamiento --
    Write-Host "  [ 5 / 5 ]  Aplicando apantallamiento de archivos..." -ForegroundColor Gray

    $plantillaScreen = "Practica8-Apantallamiento"

    try {
        $plantillaExiste = Get-FsrmFileScreenTemplate -Name $plantillaScreen -ErrorAction SilentlyContinue
        if (-not $plantillaExiste) {
            Write-Fila "AVS" "Plantilla de apantallamiento no existe. Ejecuta primero la opcion 6."
        } else {
            $screenExiste = Get-FsrmFileScreen -Path $carpetaUsuario -ErrorAction SilentlyContinue
            if ($screenExiste) {
                Set-FsrmFileScreen -Path $carpetaUsuario -Template $plantillaScreen | Out-Null
            } else {
                New-FsrmFileScreen -Path $carpetaUsuario -Template $plantillaScreen | Out-Null
            }
            Write-Fila "OK" ".mp3  .mp4  .exe  .msi  bloqueados."
        }
    } catch {
        Write-Fila "AVS" "No se pudo aplicar el apantallamiento  :  $($_.Exception.Message)"
    }

    # -- Resumen final --
    Write-Host ""
    Write-Sep
    Write-Fila "OK" "Usuario creado exitosamente  ->  $usuario@practica8.local"
    Write-Sep
    Write-Host ""
    Write-Fila "OK" "Usuario en Active Directory"
    Write-Fila "OK" "Grupo de seguridad"
    Write-Fila "OK" "Horario de acceso"
    Write-Fila "OK" "Cuota FSRM"
    Write-Fila "OK" "Apantallamiento de archivos"
    Write-Host ""
}
