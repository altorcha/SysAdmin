# ============================================================
# globals.ps1
# Practica 7 - Variables Globales Compartidas
# Windows Server 2019/2022 - PowerShell
# ============================================================

# ================================================================
# funciones_p7.ps1
# Practica 7 - Infraestructura de Despliegue Seguro e Instalacion
# Hibrida (FTP/Web) - Windows Server 2019/2022 - PowerShell
# ================================================================

# ----------------------------------------------------------------
# VARIABLES GLOBALES
# ----------------------------------------------------------------
$global:FTP_IP      = ""
$global:FTP_USER    = ""
$global:FTP_PASS    = ""
$global:FTP_RUTA    = "http/Windows"
$global:DOMINIO_SSL = ""
$global:RESUMEN     = @()

# Variables del servidor FTP local (logica P5 integrada)
$global:FTP_ROOT    = "C:\Users"
$global:FTP_DATA    = "C:\FTP_Data"
$global:FTP_SITE    = "FTP_SERVER"
$global:FTP_LOG     = "C:\FTP_Data\ftp_log.txt"
$global:SERVER_NAME = $env:COMPUTERNAME

# ================================================================
# SECCION 1 - UTILIDADES GENERALES
# ================================================================

