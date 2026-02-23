# ==========================================================
# MENU PRINCIPAL SERVICIOS WINDOWS
# Integra los servicios DHCP, DNS y SSH
# ==========================================================

# Cargar módulos
. .\servicio_dhcp.ps1
. .\servicio_dns.ps1
. .\servicio_ssh.ps1
while ($true) {

    Clear-Host
    Write-Host "======================================="
    Write-Host "      MENU DE SERVICIOS DEL SERVIDOR"
    Write-Host "======================================="
    Write-Host "1. Servicio DHCP"
    Write-Host "2. Servicio DNS"
    Write-Host "3. Servicio SSH"
    Write-Host "4. Salir"
    Write-Host "======================================="

    $op = Read-Host "Seleccione una opcion"

    switch ($op) {
        "1" { Menu-DHCP }
        "2" { Menu-DNS }
        "3" { return }
        default { 
            Write-Host "Opcion invalida"
            Start-Sleep 1
        }
    }
}
