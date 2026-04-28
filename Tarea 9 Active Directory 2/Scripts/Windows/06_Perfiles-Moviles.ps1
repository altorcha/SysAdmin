#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$ProfileRoot = "C:\PerfilesMoviles",
    [string]$ShareName = "Perfiles$",
    [string]$CsvPath = (Join-Path $PSScriptRoot "usuarios.csv"),
    [switch]$IncludeDelegatedAdmins,
    [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory
Import-Module GroupPolicy

$domain = Get-ADDomain
$domainDn = $domain.DistinguishedName
$dnsRoot = $domain.DNSRoot
$netbios = $domain.NetBIOSName
$server = $env:COMPUTERNAME
$shareUnc = "\\$server\$ShareName"
$domainAdmins = "$netbios\Domain Admins"
$domainUsers = "$netbios\Domain Users"

function Write-Step {
    param([string]$Text)
    Write-Host "`n> $Text" -ForegroundColor Cyan
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Host "[OK] Carpeta creada: $Path" -ForegroundColor Green
    } else {
        Write-Host "[OK] Carpeta existente: $Path" -ForegroundColor DarkGray
    }
}

function Set-ProfileFolderPermissions {
    param([string]$Path)

    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        $acl.RemoveAccessRule($rule) | Out-Null
    }

    $rules = @(
        (New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow")),
        (New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")),
        (New-Object System.Security.AccessControl.FileSystemAccessRule($domainAdmins,"FullControl","ContainerInherit,ObjectInherit","None","Allow")),
        (New-Object System.Security.AccessControl.FileSystemAccessRule("CREATOR OWNER","FullControl","ContainerInherit,ObjectInherit","InheritOnly","Allow")),
        (New-Object System.Security.AccessControl.FileSystemAccessRule($domainUsers,"ReadAndExecute, CreateDirectories","None","None","Allow"))
    )

    foreach ($rule in $rules) {
        $acl.AddAccessRule($rule) | Out-Null
    }

    Set-Acl -Path $Path -AclObject $acl
    Write-Host "[OK] Permisos NTFS aplicados." -ForegroundColor Green
}

function Ensure-ProfileShare {
    param([string]$Path, [string]$Name)

    $share = Get-SmbShare -Name $Name -ErrorAction SilentlyContinue
    if ($share) {
        Write-Host "[OK] Share existente: \\$server\$Name" -ForegroundColor DarkGray
        return
    }

    New-SmbShare -Name $Name -Path $Path -FullAccess $domainAdmins,"Administrators" -ChangeAccess $domainUsers | Out-Null
    Write-Host "[OK] Share creado: \\$server\$Name" -ForegroundColor Green
}

function Ensure-ProfileGpo {
    param([string]$Name = "Practica09-PerfilesMoviles")

    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $Name
        Write-Host "[OK] GPO creada: $Name" -ForegroundColor Green
    } else {
        Write-Host "[OK] GPO existente: $Name" -ForegroundColor DarkGray
    }

    Set-GPRegistryValue -Name $Name `
        -Key "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        -ValueName "CompatibleRUPSecurity" -Type DWord -Value 1 | Out-Null

    Set-GPRegistryValue -Name $Name `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
        -ValueName "DeleteRoamingCache" -Type DWord -Value 1 | Out-Null

    Set-GPRegistryValue -Name $Name `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
        -ValueName "SlowLinkDefaultProfile" -Type DWord -Value 1 | Out-Null

    Set-GPRegistryValue -Name $Name `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
        -ValueName "SlowLinkTimeOut" -Type DWord -Value 0 | Out-Null

    try {
        New-GPLink -Name $Name -Target $domainDn -ErrorAction Stop | Out-Null
        Write-Host "[OK] GPO vinculada al dominio." -ForegroundColor Green
    } catch {
        Write-Host "[OK] GPO ya vinculada." -ForegroundColor DarkGray
    }
}

function Get-TargetUsers {
    $users = @()

    if (Test-Path $CsvPath) {
        $csvUsers = Import-Csv -Path $CsvPath
        foreach ($row in $csvUsers) {
            $sam = $row.Usuario.Trim()
            $user = Get-ADUser -Identity $sam -ErrorAction SilentlyContinue
            if ($user) { $users += $user }
        }
    } else {
        Write-Host "[AVISO] No se encontro usuarios.csv; se usaran usuarios de Cuates y No Cuates." -ForegroundColor Yellow
        $users += Get-ADUser -Filter * -SearchBase "OU=Cuates,$domainDn" -ErrorAction SilentlyContinue
        $users += Get-ADUser -Filter * -SearchBase "OU=No Cuates,$domainDn" -ErrorAction SilentlyContinue
    }

    if ($IncludeDelegatedAdmins) {
        foreach ($sam in "admin_identidad","admin_storage","admin_politicas","admin_auditoria") {
            $user = Get-ADUser -Identity $sam -ErrorAction SilentlyContinue
            if ($user) { $users += $user }
        }
    }

    return $users | Sort-Object SamAccountName -Unique
}

function Apply-ProfilePath {
    param([Microsoft.ActiveDirectory.Management.ADUser[]]$Users)

    foreach ($user in $Users) {
        $profilePath = "$shareUnc\$($user.SamAccountName)"
        Set-ADUser -Identity $user.SamAccountName -ProfilePath $profilePath
        Write-Host "[OK] $($user.SamAccountName) -> $profilePath" -ForegroundColor Green
    }
}

function Verify-ProfileConfig {
    param([Microsoft.ActiveDirectory.Management.ADUser[]]$Users)

    Write-Step "Verificacion"
    Write-Host "Carpeta perfiles : $ProfileRoot" -ForegroundColor White
    Write-Host "Share UNC        : $shareUnc" -ForegroundColor White

    $share = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
    if ($share) {
        Write-Host "[OK] Share activo." -ForegroundColor Green
    } else {
        Write-Host "[FALLO] Share no encontrado." -ForegroundColor Red
    }

    foreach ($user in $Users) {
        $u = Get-ADUser -Identity $user.SamAccountName -Properties ProfilePath
        Write-Host ("{0,-20} {1}" -f $u.SamAccountName, $u.ProfilePath) -ForegroundColor DarkGray
    }
}

function Get-ProfileFolderCandidates {
    param([string]$SamAccountName)

    return @(
        (Join-Path $ProfileRoot "$SamAccountName.V6"),
        (Join-Path $ProfileRoot $SamAccountName)
    )
}

function Show-ExistingProfiles {
    param([Microsoft.ActiveDirectory.Management.ADUser[]]$Users)

    Write-Step "Perfiles almacenados en servidor"
    foreach ($user in $Users) {
        $candidates = Get-ProfileFolderCandidates -SamAccountName $user.SamAccountName
        $existing = $candidates | Where-Object { Test-Path $_ }

        if (-not $existing) {
            Write-Host ("[AVISO] {0} -> aun no existe carpeta de perfil. Inicia sesion en cliente Windows para crearla." -f $user.SamAccountName) -ForegroundColor Yellow
            continue
        }

        foreach ($folder in $existing) {
            $items = Get-ChildItem -Path $folder -Force -ErrorAction SilentlyContinue
            $count = @($items).Count
            Write-Host ("[OK] {0} -> {1} | Elementos: {2}" -f $user.SamAccountName, $folder, $count) -ForegroundColor Green
        }
    }
}

function Show-SyncGuide {
    Write-Step "Prueba de sincronizacion recomendada"
    Write-Host "1. En un cliente Windows 10 unido al dominio, inicia sesion con un usuario del dominio." -ForegroundColor White
    Write-Host "2. Verifica que en el servidor aparezca la carpeta del perfil, normalmente con extension .V6." -ForegroundColor White
    Write-Host "3. En el cliente crea un archivo en Desktop o Documents." -ForegroundColor White
    Write-Host "4. Cierra sesion en el cliente para forzar sincronizacion." -ForegroundColor White
    Write-Host "5. Revisa en el servidor que el archivo exista dentro de la carpeta del perfil del usuario." -ForegroundColor White
    Write-Host "6. Crea un archivo de prueba dentro del perfil almacenado en el servidor." -ForegroundColor White
    Write-Host "7. Vuelve a iniciar sesion con el mismo usuario en el cliente Windows." -ForegroundColor White
    Write-Host "8. Confirma que el archivo agregado en el servidor aparece en el cliente." -ForegroundColor White
    Write-Host ""
    Write-Host "Rutas tipicas a revisar:" -ForegroundColor Cyan
    Write-Host "  $ProfileRoot\usuario.V6\Desktop" -ForegroundColor DarkGray
    Write-Host "  $ProfileRoot\usuario.V6\Documents" -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host "Practica 09 - Perfiles moviles" -ForegroundColor Green
Write-Host "Dominio: $dnsRoot | Servidor: $server" -ForegroundColor DarkGray

$users = Get-TargetUsers
if (-not $users) {
    throw "No se encontraron usuarios para asignar perfiles moviles."
}

if (-not $VerifyOnly) {
    Write-Step "Preparando carpeta raiz"
    Ensure-Directory -Path $ProfileRoot
    Set-ProfileFolderPermissions -Path $ProfileRoot
    Ensure-ProfileShare -Path $ProfileRoot -Name $ShareName

    Write-Step "Configurando GPO de perfiles moviles"
    Ensure-ProfileGpo
    gpupdate /force 2>&1 | Out-Null

    Write-Step "Asignando ProfilePath a usuarios"
    Apply-ProfilePath -Users $users
}

Verify-ProfileConfig -Users $users
Show-ExistingProfiles -Users $users
Show-SyncGuide

Write-Host ""
Write-Host "[OK] Perfiles moviles configurados." -ForegroundColor Green
Write-Host "[RECUERDA] Toma una instantanea si esto sera parte de tu evidencia." -ForegroundColor Yellow
Write-Host "[NOTA] La carpeta real del perfil se creara en el primer inicio de sesion del usuario." -ForegroundColor White
