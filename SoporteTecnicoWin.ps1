# =============================================================================
#  SOPORTE TECNICO WINDOWS - SCRIPT UNIFICADO
#  Todo-en-uno: Diagnostico + Pre-Test + Instalacion + Debloat + Drivers +
#               Office + Activacion + Apps + Correccion (Defender)
#
#  Compatible : Windows 10 / 11  (32 y 64 bits) · PowerShell 5.1+
#  Requiere   : Administrador
#
#  USO RAPIDO:
#    .\SoporteTecnicoWin.ps1                  -> Menu interactivo (recomendado)
#    .\SoporteTecnicoWin.ps1 -Modo total      -> Diagnostico + Instalacion completa
#    .\SoporteTecnicoWin.ps1 -Modo test       -> Solo pruebas previas
#    .\SoporteTecnicoWin.ps1 -Modo diag       -> Solo diagnostico y correccion
#    .\SoporteTecnicoWin.ps1 -Modo install    -> Solo instalacion (6 pasos)
#    .\SoporteTecnicoWin.ps1 -Modo install -Pasos drivers,apps -Silencioso
# =============================================================================
#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet("menu","total","test","diag","install")]
    [string]$Modo = "menu",

    [ValidateSet("preflight","debloat","drivers","office","activation","apps")]
    [string[]]$Pasos = @("preflight","debloat","drivers","office","activation","apps"),

    [switch]$Silencioso,
    [switch]$Gui
)

# =============================================================================
#  INICIALIZACION GLOBAL
# =============================================================================
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing       -ErrorAction SilentlyContinue

$Script:EsAdmin      = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------- Auto-elevacion a Administrador (conservando parametros) ----------
if (-not $Script:EsAdmin -and -not $env:SOPORTE_NOELEVATE) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Modo $Modo"
    if ($Pasos -and $Pasos.Count -gt 0) { $argList += " -Pasos " + ($Pasos -join ",") }
    if ($Silencioso) { $argList += " -Silencioso" }
    if ($Gui)        { $argList += " -Gui" }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        exit
    } catch {
        Write-Host "No se pudo elevar a Administrador. Continuando sin privilegios..." -ForegroundColor Yellow
    }
}
$Script:StepLabels   = @()
$Script:LogBox       = $null
$Script:ProgressBar  = $null
$Script:StatusLabel  = $null
$Script:TimeLabel    = $null
$Script:SmileyLabel  = $null
$Script:SysInfoLabel = $null
$Script:Form         = $null
$Script:Cancelled    = $false
$Script:StartTime    = $null
$Script:SystemInfo   = @{}
$Script:Resultados   = @{}
$Script:LogStream    = $null

$Cfg = @{
    ODT_URL    = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20326-20112.exe"
    MAS_ZIP    = "https://github.com/massgravel/Microsoft-Activation-Scripts/archive/refs/heads/master.zip"
    SDIO_PAGE  = "https://www.glenndelahoy.com/snappy-driver-installer-origin/"
    WINGET_URL = "https://aka.ms/getwinget"

    OfficeLang      = "es-es"
    UpdateDelayDays = 36500
    WorkDir         = "$env:TEMP\SoporteTecnico"
    LogFile         = "$env:USERPROFILE\Desktop\SoporteTecnico_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    ReporteFile     = "$env:USERPROFILE\Desktop\Reporte_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

    Apps = @(
        @{Id="7zip.7zip";                   Name="7-Zip"}
        @{Id="RARLab.WinRAR";               Name="WinRAR"}
        @{Id="IrfanView.IrfanView";         Name="IrfanView"}
        @{Id="Google.Chrome";               Name="Google Chrome"}
        @{Id="Mozilla.Firefox";             Name="Mozilla Firefox"}
        @{Id="VideoLAN.VLC";                Name="VLC Player"}
        @{Id="Notepad++.Notepad++";         Name="Notepad++"}
        @{Id="Adobe.Acrobat.Reader.64-bit"; Name="Adobe Acrobat Reader"}
        @{Id="Zoom.Zoom";                   Name="Zoom"}
        @{Id="TeamViewer.TeamViewer";       Name="TeamViewer"}
        @{Id="AnyDesk.AnyDesk";             Name="AnyDesk"}
        @{Id="Google.Drive";                Name="Google Drive"}
        @{Id="Spotify.Spotify";             Name="Spotify"}
    )

    Durations = @{ preflight=10; debloat=60; drivers=300; office=480; activation=60; apps=240 }
}

# =============================================================================
#  LOGGING
# =============================================================================
function Iniciar-Log {
    try {
        $Script:LogStream = [System.IO.StreamWriter]::new($Cfg.LogFile, $false, [System.Text.UTF8Encoding]::UTF8)
    } catch { $Script:LogStream = $null }
}
function Escribir-LogArchivo {
    param([string]$Msg)
    if ($Script:LogStream) {
        try { $Script:LogStream.WriteLine("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"); $Script:LogStream.Flush() } catch {}
    }
}
function Cerrar-Log {
    if ($Script:LogStream) { try { $Script:LogStream.Close() } catch {}; $Script:LogStream = $null }
}

function Write-Log {
    param([string]$Msg, [string]$Color = "White")
    $ts = Get-Date -Format "HH:mm:ss"
    $coloresGUI = @{
        "White"  = [System.Drawing.Color]::White
        "Green"  = [System.Drawing.Color]::FromArgb(0,230,118)
        "Red"    = [System.Drawing.Color]::FromArgb(255,82,82)
        "Yellow" = [System.Drawing.Color]::FromArgb(255,171,0)
        "Cyan"   = [System.Drawing.Color]::FromArgb(0,210,255)
        "Gray"   = [System.Drawing.Color]::FromArgb(150,150,150)
    }
    $guiColor = $coloresGUI[$Color]   # NO usar $color: PowerShell es case-insensitive
    if ($Script:LogBox) {
        $Script:LogBox.SelectionStart = $Script:LogBox.TextLength
        $Script:LogBox.SelectionColor = [System.Drawing.Color]::FromArgb(100,200,255)
        $Script:LogBox.AppendText("[$ts] ")
        $Script:LogBox.SelectionColor = $guiColor
        $Script:LogBox.AppendText("$Msg`r`n")
        $Script:LogBox.ScrollToCaret()
        $Script:LogBox.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    } else {
        Write-Host "[$ts] $Msg" -ForegroundColor $Color
    }
    Escribir-LogArchivo "[$ts] $Msg"
}

# =============================================================================
#  UTILIDADES GENERALES
# =============================================================================
function New-Dir {
    param([string]$Path)
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Test-Puerto {
    param([string]$TargetHost = "8.8.8.8", [int]$Port = 443, [int]$TimeoutMs = 4000)
    try {
        $socket = New-Object System.Net.Sockets.TcpClient
        $result = $socket.BeginConnect($TargetHost, $Port, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $socket.EndConnect($result); $socket.Close()
        return $true
    } catch { return $false }
}
function Test-Internet { try { return (Test-Puerto) } catch { return $false } }

# Descarga robusta: reintentos + User-Agent + verificacion de tamano
function Invoke-Descarga {
    param([string]$Uri, [string]$Destino, [int]$Intentos = 3, [int]$EsperaSeg = 5)
    for ($i = 1; $i -le $Intentos; $i++) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $wc.DownloadFile($Uri, $Destino)
            if ((Test-Path $Destino) -and ((Get-Item $Destino).Length -gt 0)) { return $true }
        } catch {
            Write-Log "  Descarga intento $i/$Intentos fallo: $($_.Exception.Message)" "Yellow"
            if ($i -lt $Intentos) { Start-Sleep -Seconds $EsperaSeg }
        }
    }
    return $false
}

# =============================================================================
#  ORQUESTADOR DE PASOS (usado por GUI y por consola)
# =============================================================================
function Invoke-AllSteps {
    Iniciar-Log
    Write-Log "==============================================" "Cyan"
    Write-Log "  SOPORTE TECNICO WINDOWS - INICIO           " "Cyan"
    Write-Log "==============================================" "Cyan"
    Write-Log "Equipo : $env:COMPUTERNAME"
    Write-Log "Fecha  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "Pasos  : $($Pasos -join ', ')" "Gray"
    Write-Log "Log    : $($Cfg.LogFile)" "Gray"
    Write-Log ""

    if ($Pasos -contains "preflight") { Invoke-PreFlight }
    if ($Pasos -contains "debloat"    -and -not $Script:Cancelled) { Invoke-Debloat }
    if ($Pasos -contains "drivers"    -and -not $Script:Cancelled) { Invoke-Drivers }
    if ($Pasos -contains "office"     -and -not $Script:Cancelled) { Invoke-Office }
    if ($Pasos -contains "activation" -and -not $Script:Cancelled) { Invoke-Activation }
    if ($Pasos -contains "apps"       -and -not $Script:Cancelled) { Invoke-Apps }

    $failCount = ($Script:Resultados.Values | Where-Object { $_ -eq $false }).Count

    if (-not $Script:Cancelled) {
        $elapsed = ((Get-Date) - $Script:StartTime)
        $elapsedStr = "{0:mm\:ss}" -f $elapsed
        $okCount = ($Script:Resultados.Values | Where-Object { $_ -eq $true }).Count
        Write-Log ""
        Write-Log "==============================================" "Cyan"
        Write-Log "  PROCESO COMPLETADO  ($elapsedStr)           " "Cyan"
        Write-Log "==============================================" "Cyan"
        Write-Log "  Pasos OK: $okCount/$($Pasos.Count) | Con error: $failCount" "White"
        Update-Progreso -Percent 100 -Text "Completado en $elapsedStr"
        Set-Carita "done"
    } else {
        Write-Log "  Proceso cancelado por el usuario" "Yellow"
        Set-Carita "error"
    }

    Cerrar-Log
    Write-Host ""
    Write-Host "Proceso finalizado. Log: $($Cfg.LogFile)" -ForegroundColor Green
    return $failCount
}

# =============================================================================
#  PASO 1: VERIFICACION DEL SISTEMA (preflight)
# =============================================================================
function Invoke-PreFlight {
    Actualizar-EstadoPaso -Index 0 -Status "working"
    Set-Carita "think"
    Write-Log ""
    Write-Log "=== PASO 1: Verificacion del sistema ===" "Cyan"
    Update-Progreso -Percent 2 -Text "Detectando sistema..."

    try {
        $os    = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $build = [int]$os.BuildNumber
        $cs    = Get-CimInstance Win32_ComputerSystem
        $cpu   = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
        $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        $disk  = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        $freeGB  = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 1) } else { 0 }
        $totalGB = if ($disk) { [math]::Round($disk.Size / 1GB, 1) } else { 0 }

        $Script:SystemInfo = @{
            OSName      = ($os.Caption -replace "Microsoft ", "")
            Build       = $build
            IsWin11     = ($build -ge 22000)
            RAM_GB      = $ramGB
            CPU         = $cpu
            Arch        = $os.OSArchitecture
            DiskFreeGB  = $freeGB
            DiskTotalGB = $totalGB
            PCName      = $env:COMPUTERNAME
            HasInternet = (Test-Internet)
            WingetOk    = ($null -ne (Get-Command winget -ErrorAction SilentlyContinue))
        }

        Write-Log "  Sistema : $($Script:SystemInfo.OSName) (Build $build)" "White"
        Write-Log "  RAM     : ${ramGB} GB | CPU: $cpu | $($os.OSArchitecture)" "White"
        Write-Log "  Disco C : ${freeGB} GB libres de ${totalGB} GB" "White"
        Write-Log "  Internet: $($Script:SystemInfo.HasInternet) | winget: $($Script:SystemInfo.WingetOk)" "Gray"

        if ($freeGB -lt 20) { Write-Log "  AVISO: poco espacio en C: ($freeGB GB). Office/drivers pueden fallar." "Yellow" }

        if ($Script:SysInfoLabel) {
            $Script:SysInfoLabel.Text = "$($Script:SystemInfo.OSName) | ${ramGB} GB RAM | $cpu | ${freeGB} GB libres"
            $Script:SysInfoLabel.Refresh()
        }

        New-Dir $Cfg.WorkDir
        Write-Log "  Verificacion completada." "Green"
        Actualizar-EstadoPaso -Index 0 -Status "done"
        Update-Progreso -Percent 5 -Text "Sistema verificado"
        $Script:Resultados["preflight"] = $true
        return $true
    }
    catch {
        Write-Log "  Error en verificacion: $_" "Red"
        Actualizar-EstadoPaso -Index 0 -Status "error"
        $Script:Resultados["preflight"] = $false
        return $false
    }
}

# =============================================================================
#  PASO 2: DEBLOAT / OPTIMIZACION
# =============================================================================
function Invoke-Debloat {
    Actualizar-EstadoPaso -Index 1 -Status "working"
    Set-Carita "working"
    Write-Log ""
    Write-Log "=== PASO 2: Optimizacion de Windows ===" "Cyan"
    Update-Progreso -Percent 8 -Text "Optimizando Windows..."

    try {
        # --- Telemetria ---
        $td = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $td)) { New-Item -Path $td -Force | Out-Null }
        Set-ItemProperty -Path $td -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        $wer = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
        if (-not (Test-Path $wer)) { New-Item -Path $wer -Force | Out-Null }
        Set-ItemProperty -Path $wer -Name "Disabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        foreach ($svc in @("DiagTrack","dmwappushservice")) {
            try { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue; Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
        }
        Write-Log "  [Telemetria] Desactivada" "Green"

        # --- OneDrive ---
        Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        foreach ($od in @("$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe","$env:SYSTEMROOT\System32\OneDriveSetup.exe")) {
            if (Test-Path $od) { Start-Process -FilePath $od -ArgumentList "/uninstall" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue; break }
        }
        foreach ($folder in @("$env:USERPROFILE\OneDrive","$env:LOCALAPPDATA\Microsoft\OneDrive")) {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Log "  [OneDrive] Eliminado" "Green"

        # --- Copilot (solo Windows 11) ---
        if ($Script:SystemInfo.IsWin11) {
            $cp = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
            if (-not (Test-Path $cp)) { New-Item -Path $cp -Force | Out-Null }
            Set-ItemProperty -Path $cp -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Get-AppxPackage "Microsoft.Copilot" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Write-Log "  [Copilot] Eliminado" "Green"
        }

        # --- Bloatware ---
        $bloat = @(
            "Microsoft.549981C3F5F10","Microsoft.BingNews","Microsoft.BingWeather","Microsoft.BingSearch",
            "Microsoft.GamingApp","Microsoft.GetHelp","Microsoft.Getstarted","Microsoft.MicrosoftOfficeHub",
            "Microsoft.MicrosoftSolitaireCollection","Microsoft.People","Microsoft.PowerAutomateDesktop",
            "Microsoft.Todos","Microsoft.WindowsAlarms","Microsoft.WindowsMaps","Microsoft.WindowsSoundRecorder",
            "Microsoft.Xbox.TCUI","Microsoft.XboxApp","Microsoft.XboxGameOverlay","Microsoft.XboxGamingOverlay",
            "Microsoft.XboxIdentityProvider","Microsoft.XboxSpeechToTextOverlay","Microsoft.YourPhone",
            "Microsoft.ZuneMusic","Microsoft.ZuneVideo","Clipchamp.Clipchamp","MicrosoftTeams","Microsoft.MicrosoftStickyNotes"
        )
        $removed = 0
        foreach ($app in $bloat) {
            try {
                Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $app } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                $removed++
            } catch {}
        }
        Write-Log "  [Bloatware] $removed apps procesadas" "Green"

        # --- Busqueda web / Bing / Cortana ---
        $search = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $search)) { New-Item -Path $search -Force | Out-Null }
        Set-ItemProperty -Path $search -Name "BingSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $search -Name "CortanaConsent"    -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        # --- Retrasar actualizaciones ---
        $wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        if (-not (Test-Path $wu)) { New-Item -Path $wu -Force | Out-Null }
        Set-ItemProperty -Path $wu -Name "DeferFeatureUpdates"                -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $wu -Name "DeferFeatureUpdatesPeriodInDays"    -Value $Cfg.UpdateDelayDays -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $wu -Name "DeferQualityUpdates"                -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $wu -Name "DeferQualityUpdatesPeriodInDays"    -Value 365 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "  [Updates] Actualizaciones retrasadas" "Green"

        Write-Log "  Optimizacion completada." "Green"
        Actualizar-EstadoPaso -Index 1 -Status "done"
        Update-Progreso -Percent 40 -Text "Optimizacion completada"
        $Script:Resultados["debloat"] = $true
        return $true
    }
    catch {
        Write-Log "  Error en optimizacion: $_" "Red"
        Actualizar-EstadoPaso -Index 1 -Status "error"
        $Script:Resultados["debloat"] = $false
        return $false
    }
}

# =============================================================================
#  PASO 3: CONTROLADORES (SDIO + fallback Windows Update)
# =============================================================================
function Invoke-WindowsUpdateDrivers {
    try {
        Write-Log "  [WU] Buscando drivers en Windows Update..." "Yellow"
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result   = $searcher.Search("IsInstalled=0 and Type='Driver'")
        $count    = $result.Updates.Count
        if ($count -eq 0) { Write-Log "  [WU] No hay drivers nuevos." "Gray"; return $false }

        Write-Log "  [WU] $count driver(s) encontrados. Descargando..." "Yellow"
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $result.Updates) { [void]$coll.Add($u) }

        $dl = $session.CreateUpdateDownloader(); $dl.Updates = $coll; [void]$dl.Download()
        $ins = $session.CreateUpdateInstaller(); $ins.Updates = $coll
        $res = $ins.Install().ResultCode   # 2 = exito
        if ($res -eq 2 -or $res -eq 3) {
            Write-Log "  [WU] $count driver(s) instalados via Windows Update." "Green"
            return $true
        }
        Write-Log "  [WU] Resultado: $res (parcial o fallido)" "Yellow"
        return ($res -ge 2)
    }
    catch {
        Write-Log "  [WU] Fallo: $($_.Exception.Message)" "Yellow"
        return $false
    }
}

function Invoke-Drivers {
    Actualizar-EstadoPaso -Index 2 -Status "working"
    Set-Carita "download"
    Write-Log ""
    Write-Log "=== PASO 3: Controladores ===" "Cyan"
    Update-Progreso -Percent 42 -Text "Buscando controladores..."

    try {
        if (-not $Script:SystemInfo.HasInternet) {
            Write-Log "  Sin internet. Omitiendo descarga de drivers." "Yellow"
            Actualizar-EstadoPaso -Index 2 -Status "error"
            $Script:Resultados["drivers"] = $false
            return $false
        }

        $ok = $false

        # --- Intento 1: SDIO ---
        try {
            Write-Log "  Buscando SDIO..." "Gray"
            $page = Invoke-WebRequest -Uri $Cfg.SDIO_PAGE -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $zipLink = ($page.Links | Where-Object { $_.href -match '\.zip$' } | Select-Object -First 1).href
            if ($zipLink) {
                if ($zipLink -notmatch '^https?://') {
                    $zipLink = [System.Uri]::new([System.Uri]$Cfg.SDIO_PAGE, $zipLink).AbsoluteUri
                }
                $sdioZip = "$($Cfg.WorkDir)\SDIO.zip"
                if (Invoke-Descarga -Uri $zipLink -Destino $sdioZip -Intentos 2 -EsperaSeg 5) {
                    $sdioDir = "$($Cfg.WorkDir)\SDIO"
                    Expand-Archive -Path $sdioZip -DestinationPath $sdioDir -Force -ErrorAction SilentlyContinue
                    $exe = Get-ChildItem -Path $sdioDir -Recurse -Filter "SDI*_R*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if (-not $exe) { $exe = Get-ChildItem -Path $sdioDir -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 }
                    if ($exe) {
                        $sPath = "$sdioDir\auto_install.txt"
                        Set-Content -Path $sPath -Value "install all`r`nexit`r`n" -Encoding ASCII
                        Write-Log "  Ejecutando SDIO ($($exe.Name))..." "Yellow"
                        Update-Progreso -Percent 50 -Text "Instalando controladores (SDIO)..."
                        Start-Process -FilePath $exe.FullName -ArgumentList "--script:`"$sPath`"" -Wait -ErrorAction SilentlyContinue
                        Write-Log "  SDIO completado." "Green"
                        $ok = $true
                    } else { Write-Log "  No se hallo ejecutable en el ZIP de SDIO." "Yellow" }
                } else { Write-Log "  Fallo la descarga de SDIO." "Yellow" }
            } else { Write-Log "  SDIO no ofrecio enlace .zip." "Yellow" }
        }
        catch {
            Write-Log "  SDIO no disponible (sitio caido/bloqueado): $($_.Exception.Message)" "Yellow"
        }

        # --- Intento 2: Windows Update ---
        if (-not $ok) {
            Update-Progreso -Percent 52 -Text "Buscando drivers en Windows Update..."
            if (Invoke-WindowsUpdateDrivers) { $ok = $true }
        }

        # --- Intento 3: manual ---
        if (-not $ok) {
            Write-Log "  No se pudieron instalar drivers automaticamente. Abriendo SDIO manual..." "Yellow"
            Start-Process $Cfg.SDIO_PAGE -ErrorAction SilentlyContinue
            Actualizar-EstadoPaso -Index 2 -Status "error"
            $Script:Resultados["drivers"] = $false
            return $false
        }

        Actualizar-EstadoPaso -Index 2 -Status "done"
        Update-Progreso -Percent 62 -Text "Controladores instalados"
        $Script:Resultados["drivers"] = $true
        return $true
    }
    catch {
        Write-Log "  Error general en controladores: $_" "Yellow"
        Actualizar-EstadoPaso -Index 2 -Status "error"
        $Script:Resultados["drivers"] = $false
        return $false
    }
}

# =============================================================================
#  PASO 4: OFFICE (ODT)
# =============================================================================
function Invoke-Office {
    Actualizar-EstadoPaso -Index 3 -Status "working"
    Set-Carita "download"
    Write-Log ""
    Write-Log "=== PASO 4: Office ===" "Cyan"
    Update-Progreso -Percent 64 -Text "Descargando Office Deployment Tool..."

    try {
        if (-not $Script:SystemInfo.HasInternet) {
            Write-Log "  Sin internet. Omitiendo Office." "Yellow"
            Actualizar-EstadoPaso -Index 3 -Status "error"
            $Script:Resultados["office"] = $false
            return $false
        }

        $ramGB = $Script:SystemInfo.RAM_GB
        $is64  = ($Script:SystemInfo.Arch -match "64")

        if ($ramGB -le 4) {
            $product="ProPlus2021Volume"; $channel="PerpetualVL2021"; $edition="32"
            $exclude=@("Access","Groove","Lync","Publisher","Bing","OneNote","Outlook","Teams")
            Write-Log "  RAM <= 4GB -> Office LTSC 2021 (32 bits, apps basicas)" "Yellow"
        } elseif ($ramGB -le 8) {
            $product="ProPlus2021Volume"; $channel="PerpetualVL2021"; $edition="64"
            $exclude=@("Groove","Lync","Bing")
            Write-Log "  RAM 4-8GB -> Office LTSC 2021 (64 bits)" "Yellow"
        } else {
            $product="ProPlus2024Volume"; $channel="PerpetualVL2024"; $edition="64"
            $exclude=@("Groove","Lync")
            Write-Log "  RAM > 8GB -> Office LTSC 2024 (64 bits)" "Yellow"
        }
        if (-not $is64) { $edition="32"; $exclude=@("Access","Groove","Lync","Publisher","Bing","OneNote","Outlook","Teams") }

        $odtExe = "$($Cfg.WorkDir)\odt.exe"
        if (-not (Invoke-Descarga -Uri $Cfg.ODT_URL -Destino $odtExe -Intentos 3)) {
            Write-Log "  Fallo la descarga del ODT." "Red"
            Actualizar-EstadoPaso -Index 3 -Status "error"
            $Script:Resultados["office"] = $false
            return $false
        }
        Write-Log "  ODT descargado." "Green"

        $odtDir = "$($Cfg.WorkDir)\ODT"
        New-Dir $odtDir
        Start-Process -FilePath $odtExe -ArgumentList "/quiet /extract:`"$odtDir`"" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue

        $excludeXml = ($exclude | ForEach-Object { "      <ExcludeApp ID=`"$_`" />" }) -join "`n"
        $configXml = @"
<Configuration>
  <Add OfficeClientEdition="$edition" Channel="$channel" MigrateArch="TRUE">
    <Product ID="$product">
      <Language ID="$($Cfg.OfficeLang)" />
$excludeXml
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="SharedComputerLicensing" Value="0" />
  <Property Name="FORCEAPPSHUTDOWN" Value="FALSE" />
  <Property Name="DeviceBasedLicensing" Value="FALSE" />
  <RemoveMSI />
</Configuration>
"@
        $configPath = "$odtDir\config.xml"
        Set-Content -Path $configPath -Value $configXml -Encoding UTF8

        $setupExe = "$odtDir\setup.exe"
        if (-not (Test-Path $setupExe)) {
            Write-Log "  No se hallo setup.exe (extraccion del ODT fallo)." "Red"
            Actualizar-EstadoPaso -Index 3 -Status "error"
            $Script:Resultados["office"] = $false
            return $false
        }

        Write-Log "  Descargando archivos de Office (varios minutos)..." "Yellow"
        Update-Progreso -Percent 70 -Text "Descargando Office..."
        Start-Process -FilePath $setupExe -ArgumentList "/download `"$configPath`"" -Wait -WindowStyle Hidden -ErrorAction Stop
        Write-Log "  Archivos de Office descargados." "Green"

        Write-Log "  Instalando Office (silencioso)..." "Yellow"
        Update-Progreso -Percent 80 -Text "Instalando Office..."
        Start-Process -FilePath $setupExe -ArgumentList "/configure `"$configPath`"" -Wait -WindowStyle Hidden -ErrorAction Stop
        Write-Log "  Office instalado." "Green"
        Actualizar-EstadoPaso -Index 3 -Status "done"
        Update-Progreso -Percent 88 -Text "Office instalado"
        $Script:Resultados["office"] = $true
        return $true
    }
    catch {
        Write-Log "  Error instalando Office: $_" "Red"
        Actualizar-EstadoPaso -Index 3 -Status "error"
        $Script:Resultados["office"] = $false
        return $false
    }
}

# =============================================================================
#  PASO 5: ACTIVACION (MAS)
# =============================================================================
function Invoke-Activation {
    Actualizar-EstadoPaso -Index 4 -Status "working"
    Set-Carita "working"
    Write-Log ""
    Write-Log "=== PASO 5: Activacion (MAS) ===" "Cyan"
    Update-Progreso -Percent 90 -Text "Activando Windows y Office..."

    try {
        if (-not $Script:SystemInfo.HasInternet) {
            Write-Log "  Sin internet. Omitiendo activacion." "Yellow"
            Actualizar-EstadoPaso -Index 4 -Status "error"
            $Script:Resultados["activation"] = $false
            return $false
        }

        $masZip = "$($Cfg.WorkDir)\MAS.zip"
        if (-not (Invoke-Descarga -Uri $Cfg.MAS_ZIP -Destino $masZip -Intentos 4 -EsperaSeg 10)) {
            Write-Log "  Fallo la descarga de MAS (GitHub). Reintente o use massgrave.dev" "Red"
            Actualizar-EstadoPaso -Index 4 -Status "error"
            $Script:Resultados["activation"] = $false
            return $false
        }
        Write-Log "  MAS descargado." "Green"

        $masDir = "$($Cfg.WorkDir)\MAS"
        Expand-Archive -Path $masZip -DestinationPath $masDir -Force -ErrorAction SilentlyContinue

        Write-Log "  Activando Windows (HWID)..." "Yellow"
        $hwid = Get-ChildItem -Path $masDir -Recurse -Filter "hwid.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hwid) {
            Start-Process cmd.exe -ArgumentList "/c `"$($hwid.FullName)`"" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
            Write-Log "  Activacion HWID ejecutada." "Green"
        } else {
            $aio = Get-ChildItem -Path $masDir -Recurse -Filter "MAS_AIO.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($aio) { Start-Process cmd.exe -ArgumentList "/c `"$($aio.FullName)`"" -Wait -ErrorAction SilentlyContinue }
        }

        Write-Log "  Activando Office (Ohook)..." "Yellow"
        $ohook = Get-ChildItem -Path $masDir -Recurse -Filter "Ohook_Auto.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ohook) {
            Start-Process cmd.exe -ArgumentList "/c `"$($ohook.FullName)`"" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
            Write-Log "  Ohook ejecutado." "Green"
        }

        $lic = (Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*Windows*" } | Select-Object -First 1).LicenseStatus
        switch ($lic) {
            0 { Write-Log "  Windows NO activado. Ejecute MAS manualmente." "Yellow" }
            1 { Write-Log "  Windows ACTIVADO." "Green" }
            5 { Write-Log "  Windows ACTIVADO (notification mode)." "Green" }
            default { Write-Log "  Estado de licencia: $lic" "Gray" }
        }

        Actualizar-EstadoPaso -Index 4 -Status "done"
        Update-Progreso -Percent 96 -Text "Activacion completada"
        $Script:Resultados["activation"] = $true
        return $true
    }
    catch {
        Write-Log "  Error en activacion: $_" "Red"
        Actualizar-EstadoPaso -Index 4 -Status "error"
        $Script:Resultados["activation"] = $false
        return $false
    }
}

# =============================================================================
#  PASO 6: APLICACIONES (WINGET)
# =============================================================================
function Invoke-Apps {
    Actualizar-EstadoPaso -Index 5 -Status "working"
    Set-Carita "working"
    Write-Log ""
    Write-Log "=== PASO 6: Aplicaciones utiles ===" "Cyan"
    Update-Progreso -Percent 96 -Text "Instalando aplicaciones..."

    try {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Write-Log "  winget no disponible. Instalando App Installer..." "Yellow"
            try {
                $msix = "$($Cfg.WorkDir)\Microsoft.DesktopAppInstaller.msixbundle"
                if ((Invoke-Descarga -Uri $Cfg.WINGET_URL -Destino $msix -Intentos 3)) {
                    Add-AppxPackage -Path $msix -ErrorAction Stop
                    $winget = Get-Command winget -ErrorAction SilentlyContinue
                }
                if (-not $winget) { throw "winget no se pudo instalar." }
            } catch {
                Write-Log "  No se pudo instalar winget: $_" "Red"
                Write-Log "  Instale las apps manualmente desde ninite.com" "Yellow"
                Actualizar-EstadoPaso -Index 5 -Status "error"
                $Script:Resultados["apps"] = $false
                return $false
            }
        }

        $apps = $Cfg.Apps; $total = $apps.Count; $done = 0; $failed = 0
        foreach ($app in $apps) {
            if ($Script:Cancelled) { return $false }
            $done++
            $pct = 96 + [math]::Floor(($done / $total) * 3)
            Update-Progreso -Percent $pct -Text "Instalando $($app.Name) ($done/$total)..."
            Write-Log "  [$done/$total] $($app.Name)..." "Gray"
            try {
                $r = & winget install --id $($app.Id) --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
                if ($LASTEXITCODE -eq 0 -or $r -match "already installed") {
                    Write-Log "    $($app.Name) instalado" "Green"
                } else {
                    Write-Log "    $($app.Name): posible error (exit $LASTEXITCODE)" "Yellow"; $failed++
                }
            } catch {
                Write-Log "    Error con $($app.Name): $_" "Red"; $failed++
            }
        }

        if ($failed -eq 0) { Write-Log "  Todas las aplicaciones instaladas ($total/$total)" "Green" }
        else { Write-Log "  $([int]($total-$failed))/$total instaladas, $failed con avisos" "Yellow" }

        Actualizar-EstadoPaso -Index 5 -Status "done"
        Update-Progreso -Percent 99 -Text "Aplicaciones instaladas"
        $Script:Resultados["apps"] = $true
        return $true
    }
    catch {
        Write-Log "  Error instalando aplicaciones: $_" "Red"
        Actualizar-EstadoPaso -Index 5 -Status "error"
        $Script:Resultados["apps"] = $false
        return $false
    }
}

# =============================================================================
#  DIAGNOSTICO Y CORRECCION (integrado del antiguo DiagnosticoYCorreccion.ps1)
# =============================================================================
function Invoke-Diagnostico {
    Write-Log ""
    Write-Log "=== DIAGNOSTICO Y CORRECCION ===" "Cyan"
    Write-Log ""

    # --- 1. Antivirus instalado ---
    Write-Log "[1] Antivirus instalados..." "Yellow"
    $av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue
    if ($av) {
        $av | ForEach-Object { Write-Log "    - $($_.displayName)" }
        $tieneAV = $true
    } else {
        Write-Log "    No se detecto ningun antivirus." "Green"
        $tieneAV = $false
    }

    # --- 2. Windows Defender (solo si no hay otro AV) ---
    if (-not $tieneAV) {
        Write-Log "[2] Activando Windows Defender..." "Yellow"
        if (-not $Script:EsAdmin) {
            Write-Log "    Se requiere Administrador. Omitido." "Yellow"
        } else {
            $regOk = $false
            try {
                Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop | Out-Null
                Set-MpPreference -DisableBehaviorMonitoring  $false -ErrorAction Stop | Out-Null
                Set-MpPreference -DisableScriptScanning       $false -ErrorAction SilentlyContinue | Out-Null
                Write-Log "    Proteccion en tiempo real ACTIVADA (cmdlets)." "Green"
                $regOk = $true
            } catch {
                Write-Log "    Cmdlets de Defender no disponibles, usando registro..." "Yellow"
            }
            foreach ($rp in @("HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender","HKLM:\SOFTWARE\Microsoft\Windows Defender")) {
                if (Test-Path $rp) {
                    try {
                        Set-ItemProperty -Path $rp -Name "DisableAntiSpyware" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
                        Set-ItemProperty -Path $rp -Name "DisableAntiVirus"   -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
                        Write-Log "    Desbloqueado en $rp" "Green"
                        $regOk = $true
                    } catch { Write-Log "    No se pudo escribir en $rp" "Yellow" }
                }
            }
            $rtp = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
            if (Test-Path $rtp) {
                try {
                    Set-ItemProperty -Path $rtp -Name "DisableRealtimeMonitoring" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
                    Write-Log "    Monitor en tiempo real ACTIVADO (registro)." "Green"
                    $regOk = $true
                } catch { Write-Log "    No se pudo activar el monitor en tiempo real." "Yellow" }
            }
            if (-not $regOk) { Write-Log "    No se pudo activar Defender (privilegios)." "Red" }
            Write-Log "    Recomendacion: reinicie para que Defender tome control completo." "Cyan"
        }
    } else {
        Write-Log "[2] Defender no se fuerza (hay otro antivirus)." "Gray"
    }

    # --- 3. Bateria ---
    Write-Log "[3] Informe de bateria..." "Yellow"
    $batHtml = "$env:USERPROFILE\Desktop\Reporte_Bateria.html"
    powercfg /batteryreport /output $batHtml 2>$null | Out-Null
    if (Test-Path $batHtml) {
        Write-Log "    Informe: $batHtml" "Green"
        Write-Log "      Desgaste % = ((Diseno - Actual) / Diseno) * 100  (>20-30% = cambiar)" "Gray"
    } else {
        Write-Log "    No se pudo generar (equipo de escritorio o sin bateria)." "Gray"
    }

    # --- 4. Temperatura ---
    Write-Log "[4] Temperatura (zonas termicas WMI)..." "Yellow"
    $zonas = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
    if ($zonas) {
        foreach ($z in $zonas) {
            $c = ($z.CurrentTemperature / 10) - 273.15
            Write-Log ("    {0}: {1:N1} C" -f $z.InstanceName, $c)
        }
        Write-Log "    > Si la CPU pasa 85-90 C bajo carga: sobrecalentamiento." "Gray"
    } else {
        Write-Log "    No expuesto via WMI. Use HWMonitor / Core Temp / HWiNFO." "Gray"
    }

    # --- 5. Pasta termica ---
    Write-Log "[5] Pasta termica: cambiar si..." "Yellow"
    Write-Log "    - Equipo con 3-4+ anos sin cambio." "Gray"
    Write-Log "    - CPU > 85-90 C bajo carga." "Gray"
    Write-Log "    - Ventilador siempre al maximo con calor excesivo." "Gray"

    # --- 6. Navegador lento ---
    Write-Log "[6] Navegador lento al escribir..." "Yellow"
    Write-Log "    - Cerrar pestanas / reiniciar el navegador." "Gray"
    Write-Log "    - Deshabilitar extensiones que no use." "Gray"
    Write-Log "    - Limpiar cache y cookies (Ctrl+Mayus+Supr)." "Gray"
    Write-Log "    - Chrome/Edge: Restablecer valores predeterminados." "Gray"
    Write-Log "    - Revisar proceso al 100% de CPU en el Administrador de tareas." "Gray"

    Write-Log ""
    Write-Log "Diagnostico finalizado." "Green"
}

# =============================================================================
#  PRE-TEST (integrado del antiguo Test-PreInstalacion.ps1)
# =============================================================================
function Invoke-PreTest {
    $lineas = @(); $criticos = @(); $avisos = @()
    $sep = "============================================================"
    Write-Log ""
    Write-Log "=== PRE-TEST DEL EQUIPO ===" "Cyan"

    function Rep { param($m, $t="INFO")
        $l = "[$(Get-Date -Format 'HH:mm:ss')] [$t] $m"
        $script:lineas += $l
        switch ($t) {
            "OK"      { Write-Log $l "Green" }
            "WARN"    { Write-Log $l "Yellow"; $script:avisos += $m }
            "ERROR"   { Write-Log $l "Red" }
            "CRITICO" { Write-Log $l "Red"; $script:criticos += $m }
            default   { Write-Log $l "Cyan" }
        }
    }

    $ps = $PSVersionTable.PSVersion
    Rep ("PowerShell {0}.{1}.{2}" -f $ps.Major,$ps.Minor,$ps.Build) "INFO"
    if ($ps.Major -lt 5) { Rep "PowerShell < 5.0: algunos cmdlets pueden fallar." "CRITICO" }

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $build = [int]$os.BuildNumber
        Rep ("Sistema: {0} | Build {1} | {2}" -f $os.Caption, $build, $os.OSArchitecture) "OK"
        if ($build -lt 10240) { Rep "Windows anterior a 10." "WARN" }
        if ($os.ProductType -ne 1) { Rep "Detectado como Servidor." "WARN" }
    } catch { Rep "No se pudo detectar Windows." "CRITICO" }

    Rep ("SO {0} bits" -f $(if ([Environment]::Is64BitOperatingSystem) { "64" } else { "32" })) "OK"

    if ($Script:EsAdmin) { Rep "Ejecutando como ADMINISTRADOR." "OK" }
    else { Rep "NO es Administrador. Registro/servicios/apps fallaran." "CRITICO" }

    $t0 = Get-Date; $net = Test-Internet; $ms = ((Get-Date) - $t0).TotalMilliseconds
    if ($net) { Rep ("Internet OK en {0:N0} ms" -f $ms) "OK" }
    else { Rep "Sin conexion. Drivers/Office/activacion/apps se omitiran." "CRITICO" }

    if (Get-Command winget -ErrorAction SilentlyContinue) { Rep "winget disponible." "OK" }
    else { Rep "winget ausente. Se intentara instalar App Installer." "WARN" }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        Rep "Windows Forms disponible (GUI funcional)." "OK"
    } catch { Rep "GUI no disponible (System.Windows.Forms)." "CRITICO" }

    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        $libre = [math]::Round($disk.FreeSpace/1GB,1); $tot = [math]::Round($disk.Size/1GB,1)
        Rep ("Disco C: {0} GB libres de {1} GB" -f $libre,$tot) "OK"
        if ($libre -lt 20) { Rep "Menos de 20 GB libres: Office/drivers pueden fallar." "WARN" }
    } catch { Rep "No se pudo leer el disco C:." "ERROR" }

    $av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue
    if ($av) { Rep ("Antivirus: {0}" -f (($av | ForEach-Object { $_.displayName }) -join ", ")) "OK" }
    else { Rep "Sin antivirus. Defender se activara en el diagnostico." "INFO" }

    # Reporte a disco
    $res = @"
$sep
PRE-TEST - $env:COMPUTERNAME
Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
$sep

$($lineas -join "`n")

$sep
RESUMEN
$sep
Errores criticos : $($criticos.Count)
Advertencias     : $($avisos.Count)

"@
    if ($criticos.Count) { $res += "CRITICOS:`n" + ($criticos -join "`n") + "`n`n" }
    if ($avisos.Count)   { $res += "AVISOS:`n"   + ($avisos -join "`n")   + "`n`n" }
    $res += "RECOMENDACION: " + $(if ($criticos.Count -eq 0) { "PROCEDER CON LA INSTALACION." } else { "NO EJECUTAR hasta corregir los criticos." }) + "`n"
    $res | Out-File -FilePath $Cfg.ReporteFile -Encoding UTF8
    Write-Host "Reporte: $($Cfg.ReporteFile)" -ForegroundColor Cyan

    return ($criticos.Count -eq 0)
}

# =============================================================================
#  GUI (controles)
# =============================================================================
function Actualizar-EstadoPaso {
    param([int]$Index, [string]$Status)
    $icons  = @{ pending="o"; working=">"; done="+"; error="x" }
    $colors = @{
        pending=[System.Drawing.Color]::FromArgb(120,120,130)
        working=[System.Drawing.Color]::FromArgb(0,210,255)
        done=[System.Drawing.Color]::FromArgb(0,230,118)
        error=[System.Drawing.Color]::FromArgb(255,82,82)
    }
    if ($Script:StepLabels[$Index]) {
        $lbl = $Script:StepLabels[$Index]
        $lbl.ForeColor = $colors[$Status]
        $partes = $lbl.Text -split " ", 2
        $partes[0] = $icons[$Status]
        $lbl.Text = $partes -join " "
        $lbl.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Update-Progreso {
    param([int]$Percent, [string]$Text = "")
    if ($Percent -gt 100) { $Percent = 100 }
    if ($Percent -lt 0)   { $Percent = 0 }
    if ($Script:ProgressBar) {
        $Script:ProgressBar.Value = $Percent
        $Script:StatusLabel.Text  = $Text
        if ($Script:StartTime) {
            $elapsed = ((Get-Date) - $Script:StartTime).TotalSeconds
            $total = ($Cfg.Durations.Values | Measure-Object -Sum).Sum
            $rest = [math]::Max(0, $total - $elapsed)
            $min = [math]::Floor($rest/60); $sec = [math]::Floor($rest%60)
            $Script:TimeLabel.Text = if ($min -ge 1) { "~$min min restantes" } else { "~$sec seg restantes" }
        }
        $Script:ProgressBar.Refresh(); $Script:StatusLabel.Refresh(); $Script:TimeLabel.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    } else {
        Write-Host "Progreso: $Percent% - $Text"
    }
}

function Set-Carita {
    param([string]$Mood)
    $faces = @{
        "happy"=[char]::ConvertFromUtf32(0x1F60A); "working"=[char]::ConvertFromUtf32(0x1F604)
        "done"=[char]::ConvertFromUtf32(0x1F973);  "error"=[char]::ConvertFromUtf32(0x1F615)
        "think"=[char]::ConvertFromUtf32(0x1F914); "download"=[char]::ConvertFromUtf32(0x1F4E5)
    }
    if ($Script:SmileyLabel) {
        $Script:SmileyLabel.Text = $faces[$Mood]
        $Script:SmileyLabel.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Build-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Soporte Tecnico Windows"
    $form.Size = New-Object System.Drawing.Size(620, 760)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(18,18,30)
    $form.FormBorderStyle = "FixedSingle"; $form.MaximizeBox = $false
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $t = New-Object System.Windows.Forms.Label
    $t.Text = "SOPORTE TECNICO WINDOWS"; $t.Font = New-Object System.Drawing.Font("Segoe UI",15,[System.Drawing.FontStyle]::Bold)
    $t.ForeColor = [System.Drawing.Color]::FromArgb(0,210,255); $t.AutoSize = $true; $t.Location = New-Object System.Drawing.Point(22,14)
    $form.Controls.Add($t)

    $s = New-Object System.Windows.Forms.Label
    $s.Text = "Todo-en-uno · Windows 10 / 11"; $s.ForeColor = [System.Drawing.Color]::FromArgb(140,140,160)
    $s.AutoSize = $true; $s.Location = New-Object System.Drawing.Point(24,42); $form.Controls.Add($s)

    $sm = New-Object System.Windows.Forms.Label
    $sm.Text = [char]::ConvertFromUtf32(0x1F60A); $sm.Font = New-Object System.Drawing.Font("Segoe UI Emoji",42)
    $sm.AutoSize = $true; $sm.Location = New-Object System.Drawing.Point(490,8); $form.Controls.Add($sm)

    $si = New-Object System.Windows.Forms.Label
    $si.Text = "Detectando sistema..."; $si.ForeColor = [System.Drawing.Color]::FromArgb(140,140,160)
    $si.AutoSize = $true; $si.Location = New-Object System.Drawing.Point(24,66); $form.Controls.Add($si)

    $pb = New-Object System.Windows.Forms.ProgressBar
    $pb.Size = New-Object System.Drawing.Size(560,22); $pb.Location = New-Object System.Drawing.Point(22,96)
    $pb.Style = "Continuous"; $pb.BackColor = [System.Drawing.Color]::FromArgb(30,30,48)
    $form.Controls.Add($pb)

    $st = New-Object System.Windows.Forms.Label
    $st.Text = "Listo para iniciar"; $st.ForeColor = [System.Drawing.Color]::FromArgb(220,220,230)
    $st.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
    $st.AutoSize = $true; $st.Location = New-Object System.Drawing.Point(22,124); $form.Controls.Add($st)

    $tm = New-Object System.Windows.Forms.Label
    $tm.Text = ""; $tm.ForeColor = [System.Drawing.Color]::FromArgb(140,140,160)
    $tm.AutoSize = $true; $tm.Location = New-Object System.Drawing.Point(440,124); $form.Controls.Add($tm)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size(560,178); $panel.Location = New-Object System.Drawing.Point(22,150)
    $panel.BackColor = [System.Drawing.Color]::FromArgb(25,25,42); $panel.BorderStyle = "FixedSingle"
    $form.Controls.Add($panel)

    $nombres = @(
        "  Verificar sistema y conexion",
        "  Optimizar Windows (debloat)",
        "  Instalar controladores",
        "  Descargar e instalar Office",
        "  Activar Windows y Office",
        "  Instalar aplicaciones utiles"
    )
    $Script:StepLabels = @()
    for ($i=0; $i -lt 6; $i++) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = "o $($nombres[$i])"; $l.ForeColor = [System.Drawing.Color]::FromArgb(120,120,130)
        $l.Font = New-Object System.Drawing.Font("Segoe UI",10); $l.AutoSize = $true
        $l.Location = New-Object System.Drawing.Point(14, 10 + ($i*27))
        $panel.Controls.Add($l); $Script:StepLabels += $l
    }

    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Size = New-Object System.Drawing.Size(560,190); $log.Location = New-Object System.Drawing.Point(22,338)
    $log.BackColor = [System.Drawing.Color]::FromArgb(12,12,22); $log.ForeColor = [System.Drawing.Color]::FromArgb(200,200,210)
    $log.Font = New-Object System.Drawing.Font("Consolas",8.5); $log.ReadOnly = $true
    $log.BorderStyle = "FixedSingle"; $log.WordWrap = $true; $form.Controls.Add($log)

    $btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text = "INICIAR"; $btnStart.Size = New-Object System.Drawing.Size(280,44)
    $btnStart.Location = New-Object System.Drawing.Point(22,540); $btnStart.FlatStyle = "Flat"
    $btnStart.BackColor = [System.Drawing.Color]::FromArgb(0,140,200); $btnStart.ForeColor = [System.Drawing.Color]::White
    $btnStart.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($btnStart)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Cerrar"; $btnClose.Size = New-Object System.Drawing.Size(268,44)
    $btnClose.Location = New-Object System.Drawing.Point(314,540); $btnClose.FlatStyle = "Flat"
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(30,30,48); $btnClose.ForeColor = [System.Drawing.Color]::FromArgb(140,140,160)
    $btnClose.Font = New-Object System.Drawing.Font("Segoe UI",11); $form.Controls.Add($btnClose)

    $Script:Form = $form; $Script:ProgressBar = $pb; $Script:StatusLabel = $st
    $Script:TimeLabel = $tm; $Script:SmileyLabel = $sm; $Script:SysInfoLabel = $si; $Script:LogBox = $log

    $btnClose.Add_Click({ $Script:Cancelled = $true; $Script:Form.Close() })
    $btnStart.Add_Click({
        $btnStart.Enabled = $false; $btnClose.Enabled = $false
        $Script:Cancelled = $false; $Script:StartTime = Get-Date
        Invoke-AllSteps | Out-Null
        $btnClose.Enabled = $true
    })

    # Rellenar info del sistema antes de mostrar
    Invoke-PreFlight | Out-Null

    return $form
}

# =============================================================================
#  MENU INTERACTIVO (consola)
# =============================================================================
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  ==============================================" -ForegroundColor Cyan
    Write-Host "     SOPORTE TECNICO WINDOWS - TODO EN UNO" -ForegroundColor Cyan
    Write-Host "  ==============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Equipo: $env:COMPUTERNAME   Admin: $Script:EsAdmin" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   1) Diagnostico y correccion  (bateria, temps, Defender)" -ForegroundColor White
    Write-Host "   2) Pre-test del equipo        (reporte de compatibilidad)" -ForegroundColor White
    Write-Host "   3) Instalacion completa       (6 pasos, GUI)" -ForegroundColor Green
    Write-Host "   4) Instalacion por consola    (6 pasos, sin GUI)" -ForegroundColor White
    Write-Host "   5) Todo: pre-test + diag + instalacion" -ForegroundColor Green
    Write-Host "   6) Instalacion selectiva      (elegir pasos)" -ForegroundColor White
    Write-Host "   0) Salir" -ForegroundColor Red
    Write-Host ""
    $op = Read-Host "   Selecciona una opcion"
    return $op
}

function Invoke-InstalacionSelectiva {
    Write-Host ""
    Write-Host "  Pasos disponibles (separados por coma):" -ForegroundColor Cyan
    Write-Host "   preflight, debloat, drivers, office, activation, apps" -ForegroundColor Gray
    $sel = Read-Host "  Pasos"
    $lista = $sel -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $validos = @("preflight","debloat","drivers","office","activation","apps")
    $lista = $lista | Where-Object { $validos -contains $_ }
    if (-not $lista) { Write-Host "  Seleccion vacia." -ForegroundColor Yellow; return }
    $script:Pasos = $lista
    $Script:StartTime = Get-Date
    Invoke-AllSteps | Out-Null
}

# =============================================================================
#  PUNTO DE ENTRADA
# =============================================================================
function Start-Programa {
    New-Dir $Cfg.WorkDir

    switch ($Modo) {
        "test" {
            Invoke-PreTest | Out-Null
        }
        "diag" {
            Invoke-Diagnostico
        }
        "install" {
            $Script:StartTime = Get-Date
            if ($Gui -and -not $Silencioso) {
                try { [System.Windows.Forms.Application]::Run((Build-GUI)) }
                catch { Invoke-AllSteps | Out-Null }
            } else {
                Invoke-AllSteps | Out-Null
            }
        }
        "total" {
            Write-Host "== PRE-TEST ==" -ForegroundColor Cyan
            Invoke-PreTest | Out-Null
            Invoke-Diagnostico
            Write-Host "== INSTALACION ==" -ForegroundColor Cyan
            $Script:StartTime = Get-Date
            Invoke-AllSteps | Out-Null
        }
        default {
            # menu
            do {
                $op = Show-Menu
                switch ($op) {
                    "1" { Invoke-Diagnostico; Read-Host "`n  ENTER para continuar" | Out-Null }
                    "2" { Invoke-PreTest | Out-Null; Read-Host "`n  ENTER para continuar" | Out-Null }
                    "3" {
                        $Script:StartTime = Get-Date
                        try { [System.Windows.Forms.Application]::Run((Build-GUI)) }
                        catch { Invoke-AllSteps | Out-Null }
                    }
                    "4" { $Script:StartTime = Get-Date; Invoke-AllSteps | Out-Null; Read-Host "`n  ENTER para continuar" | Out-Null }
                    "5" {
                        Invoke-PreTest | Out-Null
                        Invoke-Diagnostico
                        $Script:StartTime = Get-Date
                        Invoke-AllSteps | Out-Null
                        Read-Host "`n  ENTER para continuar" | Out-Null
                    }
                    "6" { Invoke-InstalacionSelectiva; Read-Host "`n  ENTER para continuar" | Out-Null }
                    "0" { return }
                    default { Write-Host "  Opcion no valida." -ForegroundColor Yellow; Start-Sleep -Milliseconds 800 }
                }
            } while ($true)
        }
    }
}

Start-Programa
