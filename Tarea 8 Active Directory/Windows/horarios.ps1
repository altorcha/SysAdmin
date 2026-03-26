
function Build-LogonHours {
    param([int[]]$HorasUTC)
    $bits = New-Object bool[] 168
    for ($dia = 0; $dia -lt 7; $dia++) {
        foreach ($hora in $HorasUTC) { $bits[$dia * 24 + $hora] = $true }
    }
    $bytes = New-Object byte[] 21
    for ($i = 0; $i -lt 168; $i++) {
        if ($bits[$i]) {
            $bytes[[math]::Floor($i / 8)] = $bytes[[math]::Floor($i / 8)] -bor (1 -shl ($i % 8))
        }
    }
    return $bytes
}

function Configurar-Horarios {

    Write-Header "CONFIGURAR HORARIOS DE ACCESO"

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Fila "ERR" "AD no disponible. Ejecuta primero las opciones 1 y 2."; Write-Host ""; return
    }

    Write-Host "  Zona horaria  :  UTC-7  (Los Mochis, Sinaloa)" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "Cuates    :  08:00 - 15:00  local  (15:00 - 22:00 UTC)"
    Write-Fila "INF" "NoCuates  :  15:00 - 02:00  local  (22:00 - 09:00 UTC)"
    Write-Host ""
    Write-Host "  Se aplicara GPO para forzar cierre de sesion al expirar el turno." -ForegroundColor Gray
    Write-Host ""

    if (-not (Confirm-Accion "Deseas continuar?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    $bytesCuates   = Build-LogonHours -HorasUTC @(15,16,17,18,19,20,21)
    $bytesNoCuates = Build-LogonHours -HorasUTC @(22,23,0,1,2,3,4,5,6,7,8)

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Fila "ERR" "No se encontro usuarios.csv en $PSScriptRoot"; Write-Host ""; return
    }

    $usuarios = Import-Csv -Path $csvPath

    Write-Host "  Aplicando horarios..." -ForegroundColor Gray
    Write-Host ""

    foreach ($u in $usuarios) {
        try {
            if ($u.Departamento -eq "Cuates") {
                Set-ADUser -Identity $u.Usuario -Clear logonHours
                Set-ADUser -Identity $u.Usuario -Replace @{logonHours = ([byte[]]$bytesCuates)}
                Write-Fila "OK" "$($u.Usuario)  ->  Cuates    08:00 - 15:00"
            } elseif ($u.Departamento -eq "NoCuates") {
                Set-ADUser -Identity $u.Usuario -Clear logonHours
                Set-ADUser -Identity $u.Usuario -Replace @{logonHours = ([byte[]]$bytesNoCuates)}
                Write-Fila "OK" "$($u.Usuario)  ->  NoCuates  15:00 - 02:00"
            } else {
                Write-Fila "AVS" "$($u.Usuario)  :  departamento desconocido  '$($u.Departamento)'"
            }
        } catch {
            Write-Fila "ERR" "$($u.Usuario)  :  $($_.Exception.Message)"
        }
    }

    # -- GPO cierre de sesion forzado --
    Write-Host ""
    Write-Host "  Configurando GPO de cierre de sesion forzado..." -ForegroundColor Gray
    Write-Host ""

    $gpoNombre = "Practica8-LogonHours"

    try {
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Fila "NEW" "GPO creada  ->  $gpoNombre"
        } else {
            Write-Fila "UPD" "GPO ya existe, se actualiza  ->  $gpoNombre"
        }

        Set-GPRegistryValue `
            -Name $gpoNombre `
            -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
            -ValueName "EnableForcedLogOff" `
            -Type DWord `
            -Value 1 | Out-Null

        Write-Fila "OK" "Politica de cierre forzado configurada."

        try {
            New-GPLink -Name $gpoNombre -Target $dominio.DistinguishedName -ErrorAction Stop | Out-Null
            Write-Fila "OK" "GPO vinculada al dominio."
        } catch {
            Write-Fila "UPD" "GPO ya estaba vinculada al dominio."
        }
    } catch {
        Write-Fila "ERR" "No se pudo configurar la GPO  :  $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Sep
    Write-Fila "INF" "Los usuarios seran desconectados al expirar su turno permitido."
    Write-Host ""
}
