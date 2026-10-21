# =============================================================================
# TEST-PREINSTALACION.PS1
# Pruebas previas antes de ejecutar InstalacionAutomatica en un equipo.
# Ejecutar como ADMINISTRADOR.
# Genera reporte en el Escritorio: PreInstalacion_<Equipo>_<Fecha>.txt
# =============================================================================
[CmdletBinding()]
param(
    [string]$ScriptInstalador = ""
)

$Reporte = @()
$ErroresCriticos = @()
$Advertencias = @()

function Escribir-Reporte {
    param([string]$Mensaje, [string]$Tipo = "INFO") # INFO, OK, WARN, ERROR, CRITICO
    $ts = Get-Date -Format "HH:mm:ss"
    $linea = "[{0}] [{1}] {2}" -f $ts, $Tipo, $Mensaje
    $Reporte += $linea
    switch ($Tipo) {
        "OK"      { Write-Host $linea -ForegroundColor Green }
        "WARN"    { Write-Host $linea -ForegroundColor Yellow }
        "ERROR"   { Write-Host $linea -ForegroundColor Red }
        "CRITICO" { Write-Host $linea -ForegroundColor Red; $ErroresCriticos += $Mensaje }
        default   { Write-Host $linea -ForegroundColor Cyan }
    }
}

function Agregar-Advertencia {
    param([string]$Mensaje)
    $Advertencias += $Mensaje
    Escribir-Reporte $Mensaje "WARN"
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  TEST PRE-INSTALACION - SOPORTE TECNICO MULTIEQUIPO       " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ---------------------------------------------------------
# 1. POWERShell
# ---------------------------------------------------------
$ps = $PSVersionTable.PSVersion
Escribir-Reporte ("PowerShell {0}.{1}.{2} ({3})" -f $ps.Major, $ps.Minor, $ps.Build, $PSVersionTable.Edition) "INFO"
if ($ps.Major -lt 5) {
    Escribir-Reporte "PowerShell menor a 5.0. Algunos cmdlets (Expand-Archive, Get-CimInstance) pueden fallar." "CRITICO"
}

# ---------------------------------------------------------
# 2. VERSION DE WINDOWS
# ---------------------------------------------------------
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $build = [int]$os.BuildNumber
    $isWin11 = $build -ge 22000
    $isServer = $os.ProductType -ne 1
    $osName = $os.Caption
    Escribir-Reporte ("Sistema: {0} | Build {1} | Arquitectura: {2} | Es servidor: {3}" -f $osName, $build, $os.OSArchitecture, $isServer) "OK"

    if (-not $isWin11 -and $build -lt 10240) {
        Agregar-Advertencia "Windows anterior a 10. Se recomienda Windows 10/11."
    }
    if ($isServer) {
        Agregar-Advertencia "Sistema detectado como Servidor. Algunas funciones (winget, Microsoft Store apps) pueden no funcionar."
    }
}
catch {
    Escribir-Reporte "No se pudo detectar la versión de Windows." "CRITICO"
}

# ---------------------------------------------------------
# 3. ARQUITECTURA
# ---------------------------------------------------------
$is64 = [Environment]::Is64BitOperatingSystem
$bits = if ($is64) { "64" } else { "32" }
Escribir-Reporte ("Sistema operativo {0} bits" -f $bits) "OK"
if (-not $is64) {
    Agregar-Advertencia "Sistema 32 bits. Office se instalará en 32 bits y algunas apps de 64 bits no estarán disponibles."
}

# ---------------------------------------------------------
# 4. PRIVILEGIOS DE ADMINISTRADOR
# ---------------------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) {
    Escribir-Reporte "Ejecutando como ADMINISTRADOR." "OK"
}
else {
    Escribir-Reporte "NO se ejecuta como Administrador. El instalador fallará al modificar registro, servicios y desinstalar apps." "CRITICO"
}

# ---------------------------------------------------------
# 5. CONEXION A INTERNET
# ---------------------------------------------------------
function Test-PuertoInternet {
    param(
        [string]$TargetHost = "8.8.8.8",
        [int]$Port = 443,
        [int]$TimeoutMs = 3000
    )
    try {
        $socket = New-Object System.Net.Sockets.TcpClient
        $result = $socket.BeginConnect($TargetHost, $Port, $null, $null)
        $success = $result.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $success) { return $false }
        $socket.EndConnect($result)
        $socket.Close()
        return $true
    } catch { return $false }
}

$t0 = Get-Date
$tieneInternet = Test-PuertoInternet
$t1 = Get-Date
$ms = ($t1 - $t0).TotalMilliseconds
if ($tieneInternet) {
    Escribir-Reporte ("Internet OK (8.8.8.8:443) en {0:N0} ms" -f $ms) "OK"
}
else {
    Escribir-Reporte "Sin conexión a Internet. Pasos de descarga (drivers, Office, activación, apps) se saltarán o fallarán." "CRITICO"
}

# ---------------------------------------------------------
# 6. WINGET
# ---------------------------------------------------------
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    Escribir-Reporte ("winget disponible: {0}" -f $winget.Source) "OK"
}
else {
    Agregar-Advertencia "winget no encontrado. Paso de aplicaciones se saltará o intentará instalar App Installer."
}

# ---------------------------------------------------------
# 7. .NET / WINFORMS (para GUI)
# ---------------------------------------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Escribir-Reporte "Windows Forms y System.Drawing disponibles (GUI funcional)." "OK"
}
catch {
    Escribir-Reporte "No se pueden cargar System.Windows.Forms / System.Drawing. La GUI no funcionará." "CRITICO"
}

# ---------------------------------------------------------
# 8. ESPACIO EN DISCO C:
# ---------------------------------------------------------
try {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
    $libreGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $totalGB = [math]::Round($disk.Size / 1GB, 2)
    Escribir-Reporte ("Disco C: {0} GB libres de {1} GB ({2:P1} libre)" -f $libreGB, $totalGB, ($disk.FreeSpace / $disk.Size)) "OK"
    if ($libreGB -lt 20) {
        Agregar-Advertencia "Menos de 20 GB libres en C:. Office y controladores pueden fallar por falta de espacio."
    }
}
catch {
    Escribir-Reporte "No se pudo consultar el espacio del disco C:." "ERROR"
}

# ---------------------------------------------------------
# 9. ANTIVIRUS REGISTRADO
# ---------------------------------------------------------
$av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue
if ($av) {
    $nombres = ($av | ForEach-Object { $_.displayName }) -join ", "
    Escribir-Reporte ("Antivirus detectado: {0}" -f $nombres) "OK"
    Escribir-Reporte "Windows Defender NO se forzará (hay otro AV instalado)." "INFO"
}
else {
    Escribir-Reporte "No se detectó antivirus registrado. Windows Defender se activará en el paso de corrección." "INFO"
}

# ---------------------------------------------------------
# 10. PARSEO DEL SCRIPT INSTALADOR
# ---------------------------------------------------------
Write-Host "`n--- Validando script instalador ---" -ForegroundColor Cyan

# Determinar ruta del instalador
$rutasPosibles = @()
if ($ScriptInstalador -and (Test-Path $ScriptInstalador)) {
    $rutasPosibles += $ScriptInstalador
}
# Buscar en carpetas comunes del usuario
$rutasPosibles += "$PSScriptRoot\InstalacionAutomatica.ps1"
$rutasPosibles += "$PSScriptRoot\instalacion-automatica-windows-fix\InstalacionAutomatica.ps1"
$rutasPosibles += "$env:USERPROFILE\Desktop\InstalacionAutomatica.ps1"
$rutasPosibles += "$env:USERPROFILE\Desktop\instalacion-automatica-windows-fix\InstalacionAutomatica.ps1"

$scriptEncontrado = $null
foreach ($r in $rutasPosibles) {
    if (Test-Path $r) {
        $scriptEncontrado = $r
        break
    }
}

if (-not $scriptEncontrado) {
    Escribir-Reporte "No se encontró el script InstalacionAutomatica.ps1 en las rutas buscadas." "CRITICO"
}
else {
    Escribir-Reporte ("Script instalador encontrado: {0}" -f $scriptEncontrado) "INFO"
    $errors = $null; $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptEncontrado, [ref]$tokens, [ref]$errors)
    if ($errors.Count -eq 0) {
        Escribir-Reporte "El script instalador PARSEA CORRECTAMENTE. Sin errores de sintaxis." "OK"
    }
    else {
        Escribir-Reporte ("El script instalador tiene {0} error(es) de parseo:" -f $errors.Count) "CRITICO"
        $errors | ForEach-Object {
            Escribir-Reporte ("Línea {0}: {1}" -f $_.Extent.StartLine, $_.Message) "ERROR"
        }
    }

    # Verificar BOM UTF-8
    $bytes = [System.IO.File]::ReadAllBytes($scriptEncontrado)
    $hasBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hasBom) {
        Escribir-Reporte "Codificación: UTF-8 con BOM (correcto para PowerShell 5.1)." "OK"
    }
    else {
        Agregar-Advertencia "El script no tiene BOM UTF-8. En PowerShell 5.1 los caracteres especiales (✓, Ó, etc.) pueden romperse."
    }
}

# ---------------------------------------------------------
# 11. RESUMEN
# ---------------------------------------------------------
$reportePath = "$env:USERPROFILE\Desktop\PreInstalacion_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$separador = "============================================================"
$resumen = @"
$separador
TEST PRE-INSTALACION - $env:COMPUTERNAME
Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
$separador

$($Reporte -join "`n")

$separador
RESUMEN
$separador
Errores críticos : $($ErroresCriticos.Count)
Advertencias     : $($Advertencias.Count)

"@

if ($ErroresCriticos.Count -gt 0) {
    $resumen += "ERRORES CRITICOS:`n"
    $resumen += ($ErroresCriticos -join "`n") + "`n`n"
}

if ($Advertencias.Count -gt 0) {
    $resumen += "ADVERTENCIAS:`n"
    $resumen += ($Advertencias -join "`n") + "`n`n"
}

$resumen += "RECOMENDACION: " + $(if ($ErroresCriticos.Count -eq 0) { "PUEDEN PROCEDER CON LA INSTALACION." } else { "NO EJECUTAR EL INSTALADOR hasta corregir los errores críticos." }) + "`n"
$resumen += $separador + "`n"

$resumen | Out-File -FilePath $reportePath -Encoding UTF8
Write-Host "`nReporte guardado en: $reportePath" -ForegroundColor Cyan

if ($ErroresCriticos.Count -gt 0) {
    exit 1
}
exit 0