# =============================================================================
# INSTALACION AUTOMATIZADA PARA SOPORTE TECNICO - VERSION PRODUCCION v2.2
# Compatible: Windows 10 / Windows 11 (32 y 64 bits) · PowerShell 5.1+
# Requiere: Ejecutar como ADMINISTRADOR
#
# USO:
#   .\InstalacionAutomatica_Produccion.ps1
#   .\InstalacionAutomatica_Produccion.ps1 -Silencioso
#   .\InstalacionAutomatica_Produccion.ps1 -Pasos preflight,debloat
#   .\InstalacionAutomatica_Produccion.ps1 -Pasos drivers,apps -Silencioso
# =============================================================================
[CmdletBinding()]
param(
    [switch]$Silencioso,
    [ValidateSet("preflight","debloat","drivers","office","activation","apps")]
    [string[]]$Pasos = @("preflight","debloat","drivers","office","activation","apps")
)

# ---------- TLS 1.2 obligatorio (Windows 10/11 antiguos, PowerShell 5.1) ----------
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

# ---------- Codificación de consola para Unicode ----------
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# ---------- Carga de ensamblados ----------
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# ---------- Auto-elevación a Administrador (conservando parámetros) ----------
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Silencioso) { $argList += " -Silencioso" }
    if ($Pasos -and $Pasos.Count -gt 0) { $argList += " -Pasos " + ($Pasos -join ",") }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit
}

# =============================================================================
# CONFIGURACION
# =============================================================================
$Cfg = @{
    ODT_URL   = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20326-20112.exe"
    MAS_ZIP   = "https://github.com/massgravel/Microsoft-Activation-Scripts/archive/refs/heads/master.zip"
    SDIO_PAGE = "https://www.glenn.delahoy.com/snappy-driver-installer-origin/"
    WINGET_URL= "https://aka.ms/getwinget"

    OfficeLang = "es-es"
    UpdateDelayDays = 36500
    WorkDir     = "$env:TEMP\SoporteTecnico"
    LogFile     = "$env:USERPROFILE\Desktop\Instalacion_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    Apps = @(
        @{Id="7zip.7zip";                        Name="7-Zip"}
        @{Id="RARLab.WinRAR";                    Name="WinRAR"}
        @{Id="IrfanView.IrfanView";              Name="IrfanView"}
        @{Id="Google.Chrome";                    Name="Google Chrome"}
        @{Id="Mozilla.Firefox";                  Name="Mozilla Firefox"}
        @{Id="VideoLAN.VLC";                     Name="VLC Player"}
        @{Id="Notepad++.Notepad++";              Name="Notepad++"}
        @{Id="Adobe.Acrobat.Reader.64-bit";      Name="Adobe Acrobat Reader"}
        @{Id="Zoom.Zoom";                        Name="Zoom"}
        @{Id="TeamViewer.TeamViewer";            Name="TeamViewer"}
        @{Id="AnyDesk.AnyDesk";                  Name="AnyDesk"}
        @{Id="Google.Drive";                     Name="Google Drive"}
        @{Id="Spotify.Spotify";                  Name="Spotify"}
    )

    RemoveOneDrive     = $true
    RemoveCopilot      = $true
    RemoveBloatware    = $true
    DisableTelemetry   = $true
    DelayUpdates       = $true
    DisableWidgets     = $true
    DisableSpotlight   = $true

    Durations = @{
        preflight  = 10
        debloat    = 60
        drivers    = 300
        office     = 480
        activation = 60
        apps       = 240
    }
}

# =============================================================================
# VARIABLES GLOBALES / ESTADO
# =============================================================================
$Script:StepLabels   = @()
$Script:LogBox       = $null
$Script:ProgressBar  = $null
$Script:StatusLabel  = $null
$Script:TimeLabel    = $null
$Script:SmileyLabel  = $null
$Script:SysInfoLabel = $null
$Script:BtnStart     = $null
$Script:BtnClose     = $null
$Script:Form         = $null
$Script:Cancelled    = $false
$Script:StartTime    = $null
$Script:TotalEstimate = 0
$Script:SystemInfo   = @{}
$Script:LogStream    = [System.IO.StreamWriter]::new($Cfg.LogFile, $false, [System.Text.UTF8Encoding]::UTF8)
$Script:Resultados   = @{}

function Escribir-LogArchivo {
    param([string]$Msg)
    try {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Script:LogStream.WriteLine("[$ts] $Msg")
        $Script:LogStream.Flush()
    } catch {}
}

function Cerrar-LogArchivo {
    try { $Script:LogStream.Close() } catch {}
}

# =============================================================================
# FUNCIONES AUXILIARES
# =============================================================================

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
    # IMPORTANTE: usar $guiColor (NO $color) porque PowerShell es case-insensitive
    # y $color = ... sobreescribiría el parámetro $Color (string) con un Drawing.Color,
    # rompiendo -ForegroundColor en modo consola.
    $guiColor = $coloresGUI[$Color]
    if ($Script:LogBox) {
        $Script:LogBox.SelectionStart = $Script:LogBox.TextLength
        $Script:LogBox.SelectionColor = [System.Drawing.Color]::FromArgb(100,200,255)
        $Script:LogBox.AppendText("[$ts] ")
        $Script:LogBox.SelectionColor = $guiColor
        $Script:LogBox.AppendText("$Msg`r`n")
        $Script:LogBox.ScrollToCaret()
        $Script:LogBox.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
    else {
        Write-Host "[$ts] $Msg" -ForegroundColor $Color
    }
    Escribir-LogArchivo "[$ts] $Msg"
}

function Update-StepStatus {
    param([int]$Index, [string]$Status)
    $icons = @{ pending="○"; working="◉"; done="✓"; error="✗" }
    $colors = @{
        pending=[System.Drawing.Color]::FromArgb(120,120,130)
        working=[System.Drawing.Color]::FromArgb(0,210,255)
        done=[System.Drawing.Color]::FromArgb(0,230,118)
        error=[System.Drawing.Color]::FromArgb(255,82,82)
    }
    if ($Script:StepLabels[$Index]) {
        $lbl = $Script:StepLabels[$Index]
        $lbl.ForeColor = $colors[$Status]
        $parts = $lbl.Text -split " ", 2
        $parts[0] = $icons[$Status]
        $lbl.Text = $parts -join " "
        $lbl.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Update-ProgressBar {
    param([int]$Percent, [string]$Text = "")
    if ($Percent -gt 100) { $Percent = 100 }
    if ($Percent -lt 0)   { $Percent = 0 }
    if ($Script:ProgressBar) {
        $Script:ProgressBar.Value = $Percent
        $Script:StatusLabel.Text  = $Text
        if ($Script:StartTime -and $Script:TotalEstimate -gt 0) {
            $elapsed  = ((Get-Date) - $Script:StartTime).TotalSeconds
            $remaining = [math]::Max(0, $Script:TotalEstimate - $elapsed)
            $mins = [math]::Floor($remaining / 60)
            $secs = [math]::Floor($remaining % 60)
            $Script:TimeLabel.Text = if ($mins -ge 1) { "⏱️  ~$mins min restantes" } else { "⏱️  ~$secs seg restantes" }
        }
        $Script:ProgressBar.Refresh()
        $Script:StatusLabel.Refresh()
        $Script:TimeLabel.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
    else {
        Write-Host "Progreso: $Percent% - $Text"
    }
}

function Set-Smiley {
    param([string]$Mood)
    $faces = @{
        "happy"    = [char]::ConvertFromUtf32(0x1F60A)
        "working"  = [char]::ConvertFromUtf32(0x1F604)
        "done"     = [char]::ConvertFromUtf32(0x1F973)
        "error"    = [char]::ConvertFromUtf32(0x1F615)
        "think"    = [char]::ConvertFromUtf32(0x1F914)
        "download" = [char]::ConvertFromUtf32(0x1F4E5)
    }
    if ($Script:SmileyLabel) {
        $Script:SmileyLabel.Text = $faces[$Mood]
        $Script:SmileyLabel.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Test-PuertoInternet {
    param([string]$TargetHost = "8.8.8.8", [int]$Port = 443, [int]$TimeoutMs = 4000)
    try {
        $socket = New-Object System.Net.Sockets.TcpClient
        $result = $socket.BeginConnect($TargetHost, $Port, $null, $null)
        $ok = $result.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) { return $false }
        $socket.EndConnect($result)
        $socket.Close()
        return $true
    } catch { return $false }
}

function Test-Internet {
    try { return Test-PuertoInternet } catch { return $false }
}

function New-DirmIfMissing {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Descarga robusta con reintentos, User-Agent y verificación de tamaño
function Invoke-Descarga {
    param(
        [string]$Uri,
        [string]$Destino,
        [int]$Intentos = 3,
        [int]$EsperaSeg = 5
    )
    for ($i = 1; $i -le $Intentos; $i++) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $wc.DownloadFile($Uri, $Destino)
            if ((Test-Path $Destino) -and ((Get-Item $Destino).Length -gt 0)) {
                return $true
            }
        } catch {
            Write-Log "  Descarga intento $i/`$Intentos falló: $($_.Exception.Message)" "Yellow"
            if ($i -lt $Intentos) { Start-Sleep -Seconds $EsperaSeg }
        }
    }
    return $false
}

# =============================================================================
# CONSTRUCCION DE LA GUI
# =============================================================================
function Build-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text          = "Instalacion Automatica - Soporte Tecnico"
    $form.Size          = New-Object System.Drawing.Size(620, 760)
    $form.StartPosition = "CenterScreen"
    $form.BackColor     = [System.Drawing.Color]::FromArgb(18,18,30)
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox   = $false
    $form.Font          = New-Object System.Drawing.Font("Segoe UI", 9)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text     = "INSTALACIÓN AUTOMATIZADA"
    $lblTitle.Font     = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(0,210,255)
    $lblTitle.AutoSize = $true
    $lblTitle.Location = New-Object System.Drawing.Point(22, 14)
    $form.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text      = "Soporte Técnico · Windows 10 / 11"
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(140,140,160)
    $lblSub.AutoSize  = $true
    $lblSub.Location  = New-Object System.Drawing.Point(24, 42)
    $form.Controls.Add($lblSub)

    $smiley = New-Object System.Windows.Forms.Label
    $smiley.Text     = [char]::ConvertFromUtf32(0x1F60A)
    $smiley.Font     = New-Object System.Drawing.Font("Segoe UI Emoji", 42)
    $smiley.AutoSize = $true
    $smiley.Location = New-Object System.Drawing.Point(490, 8)
    $form.Controls.Add($smiley)

    $sysInfo = New-Object System.Windows.Forms.Label
    $sysInfo.Text      = "Detectando sistema..."
    $sysInfo.ForeColor = [System.Drawing.Color]::FromArgb(140,140,160)
    $sysInfo.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $sysInfo.AutoSize  = $true
    $sysInfo.Location  = New-Object System.Drawing.Point(24, 66)
    $form.Controls.Add($sysInfo)

    $sep1 = New-Object System.Windows.Forms.Label
    $sep1.BorderStyle = "Fixed3D"
    $sep1.Size        = New-Object System.Drawing.Size(560, 2)
    $sep1.Location    = New-Object System.Drawing.Point(22, 92)
    $form.Controls.Add($sep1)

    $pbar = New-Object System.Windows.Forms.ProgressBar
    $pbar.Size      = New-Object System.Drawing.Size(560, 22)
    $pbar.Location  = New-Object System.Drawing.Point(22, 102)
    $pbar.Style     = "Continuous"
    $pbar.BackColor = [System.Drawing.Color]::FromArgb(30,30,48)
    $pbar.ForeColor = [System.Drawing.Color]::FromArgb(0,210,255)
    $form.Controls.Add($pbar)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text      = "Listo para iniciar"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(220,220,230)
    $lblStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblStatus.AutoSize  = $true
    $lblStatus.Location  = New-Object System.Drawing.Point(22, 130)
    $form.Controls.Add($lblStatus)

    $lblTime = New-Object System.Windows.Forms.Label
    $lblTime.Text      = "⏱️  --"
    $lblTime.ForeColor = [System.Drawing.Color]::FromArgb(140,140,160)
    $lblTime.AutoSize  = $true
    $lblTime.Location  = New-Object System.Drawing.Point(440, 130)
    $form.Controls.Add($lblTime)

    $stepPanel = New-Object System.Windows.Forms.Panel
    $stepPanel.Size      = New-Object System.Drawing.Size(560, 178)
    $stepPanel.Location  = New-Object System.Drawing.Point(22, 156)
    $stepPanel.BackColor  = [System.Drawing.Color]::FromArgb(25,25,42)
    $stepPanel.BorderStyle = "FixedSingle"
    $form.Controls.Add($stepPanel)

    $stepNames = @(
        "  Verificar sistema y conexión"
        "  Optimizar Windows (debloat / telemetría)"
        "  Instalar controladores (SDIO)"
        "  Descargar e instalar Office"
        "  Activar Windows y Office (MAS)"
        "  Instalar aplicaciones útiles"
    )

    $Script:StepLabels = @()
    for ($i = 0; $i -lt 6; $i++) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text      = "○ $($stepNames[$i])"
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb(120,120,130)
        $lbl.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
        $lbl.AutoSize  = $true
        $lbl.Location  = New-Object System.Drawing.Point(14, 10 + ($i * 27))
        $stepPanel.Controls.Add($lbl)
        $Script:StepLabels += $lbl
    }

    $logBox = New-Object System.Windows.Forms.RichTextBox
    $logBox.Size      = New-Object System.Drawing.Size(560, 190)
    $logBox.Location  = New-Object System.Drawing.Point(22, 344)
    $logBox.BackColor  = [System.Drawing.Color]::FromArgb(12,12,22)
    $logBox.ForeColor = [System.Drawing.Color]::FromArgb(200,200,210)
    $logBox.Font      = New-Object System.Drawing.Font("Consolas", 8.5)
    $logBox.ReadOnly  = $true
    $logBox.BorderStyle = "FixedSingle"
    $logBox.WordWrap  = $true
    $form.Controls.Add($logBox)

    $btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text      = "▶  INICIAR INSTALACIÓN"
    $btnStart.Size      = New-Object System.Drawing.Size(280, 44)
    $btnStart.Location  = New-Object System.Drawing.Point(22, 546)
    $btnStart.FlatStyle = "Flat"
    $btnStart.BackColor  = [System.Drawing.Color]::FromArgb(0,140,200)
    $btnStart.ForeColor = [System.Drawing.Color]::White
    $btnStart.Font      = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnStart.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($btnStart)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text      = "✕  Cerrar"
    $btnClose.Size      = New-Object System.Drawing.Size(268, 44)
    $btnClose.Location  = New-Object System.Drawing.Point(314, 546)
    $btnClose.FlatStyle = "Flat"
    $btnClose.BackColor  = [System.Drawing.Color]::FromArgb(30,30,48)
    $btnClose.ForeColor = [System.Drawing.Color]::FromArgb(140,140,160)
    $btnClose.Font      = New-Object System.Drawing.Font("Segoe UI", 11)
    $btnClose.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($btnClose)

    $lblFooter = New-Object System.Windows.Forms.Label
    $lblFooter.Text      = "Windows 10 / 11 · Administrador · Los logs se guardan en el Escritorio"
    $lblFooter.ForeColor = [System.Drawing.Color]::FromArgb(80,80,100)
    $lblFooter.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
    $lblFooter.AutoSize  = $true
    $lblFooter.Location  = New-Object System.Drawing.Point(22, 600)
    $form.Controls.Add($lblFooter)

    $Script:Form         = $form
    $Script:ProgressBar  = $pbar
    $Script:StatusLabel  = $lblStatus
    $Script:TimeLabel    = $lblTime
    $Script:SmileyLabel  = $smiley
    $Script:SysInfoLabel = $sysInfo
    $Script:LogBox       = $logBox
    $Script:BtnStart     = $btnStart
    $Script:BtnClose     = $btnClose

    $btnClose.Add_Click({
        $Script:Cancelled = $true
        $Script:Form.Close()
    })

    $btnStart.Add_Click({
        $btnStart.Enabled = $false
        $btnClose.Enabled = $false
        $Script:Cancelled = $false
        $Script:StartTime = Get-Date
        $Script:TotalEstimate = ($Cfg.Durations.Values | Measure-Object -Sum).Sum
        Invoke-AllSteps
        $btnClose.Enabled = $true
    })

    return $form
}

# =============================================================================
# PASO 1: VERIFICACION DEL SISTEMA
# =============================================================================
function Invoke-PreFlight {
    Update-StepStatus -Index 0 -Status "working"
    Set-Smiley "think"
    Write-Log "=== PASO 1: Verificacion del sistema ===" "Cyan"
    Update-ProgressBar -Percent 2 -Text "Detectando sistema..."

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $build = [int]$os.BuildNumber
        $isWin11 = $build -ge 22000
        $osCaption = $os.Caption -replace "Microsoft ", ""
        $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        $cpu = (Get-CimInstance Win32_Processor).Name.Trim()
        $arch = $os.OSArchitecture

        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        $diskFreeGB = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 1) } else { 0 }
        $diskTotalGB = if ($disk) { [math]::Round($disk.Size / 1GB, 1) } else { 0 }

        $hasInternet = Test-Internet
        $wingetOk = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

        Write-Log "  Sistema: $osCaption (Build $build)" "White"
        Write-Log "  RAM: ${ramGB} GB | CPU: $cpu | Arch: $arch" "White"
        Write-Log "  Disco C: ${diskFreeGB} GB libres de ${diskTotalGB} GB" "White"
        Write-Log "  Equipo: $env:COMPUTERNAME | Internet: $hasInternet | winget: $wingetOk" "Gray"

        if ($diskFreeGB -lt 20) {
            Write-Log "  ⚠ Poco espacio en C: ($diskFreeGB GB). Office/controladores pueden fallar." "Yellow"
        }

        $Script:SystemInfo = @{
            OSName     = $osCaption
            IsWin11    = $isWin11
            Build      = $build
            RAM_GB     = $ramGB
            CPU        = $cpu
            Arch       = $arch
            DiskFreeGB = $diskFreeGB
            PCName     = $env:COMPUTERNAME
            HasInternet= $hasInternet
            WingetOk   = $wingetOk
        }

        if ($Script:SysInfoLabel) {
            $Script:SysInfoLabel.Text = "$osCaption | ${ramGB} GB RAM | $cpu | ${diskFreeGB} GB libres"
            $Script:SysInfoLabel.Refresh()
        }

        New-DirmIfMissing $Cfg.WorkDir
        Write-Log "  Directorio de trabajo: $($Cfg.WorkDir)" "Gray"
        Write-Log "  ✓ Verificacion completada" "Green"
        Update-StepStatus -Index 0 -Status "done"
        Update-ProgressBar -Percent 5 -Text "Sistema verificado"
        $Script:Resultados["preflight"] = $true
        return $true
    }
    catch {
        Write-Log "  ✗ Error en verificacion: $_" "Red"
        Update-StepStatus -Index 0 -Status "error"
        $Script:Resultados["preflight"] = $false
        return $false
    }
}

# =============================================================================
# PASO 2: DEBLOAT / OPTIMIZACION
# =============================================================================
function Invoke-Debloat {
    Update-StepStatus -Index 1 -Status "working"
    Set-Smiley "working"
    Write-Log ""
    Write-Log "=== PASO 2: Optimizacion de Windows ===" "Cyan"
    Update-ProgressBar -Percent 8 -Text "Optimizando Windows..."

    $isWin11 = $Script:SystemInfo.IsWin11

    try {
        if ($Cfg.DisableTelemetry) {
            Write-Log "  [Telemetria] Desactivando..." "Gray"
            $tdPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            if (-not (Test-Path $tdPath)) { New-Item -Path $tdPath -Force | Out-Null }
            Set-ItemProperty -Path $tdPath -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            $werPath = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
            if (-not (Test-Path $werPath)) { New-Item -Path $werPath -Force | Out-Null }
            Set-ItemProperty -Path $werPath -Name "Disabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

            foreach ($svc in @("DiagTrack", "dmwappushservice")) {
                try { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue; Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
            }
            Write-Log "  [Telemetria] ✓ Desactivada" "Green"
        }

        if ($Cfg.RemoveOneDrive) {
            Write-Log "  [OneDrive] Eliminando..." "Gray"
            Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            foreach ($od in @("$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe", "$env:SYSTEMROOT\System32\OneDriveSetup.exe")) {
                if (Test-Path $od) {
                    Start-Process -FilePath $od -ArgumentList "/uninstall" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    break
                }
            }
            foreach ($folder in @("$env:USERPROFILE\OneDrive", "$env:LOCALAPPDATA\Microsoft\OneDrive")) {
                Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Log "  [OneDrive] ✓ Eliminado" "Green"
        }

        if ($Cfg.RemoveCopilot -and $isWin11) {
            $cpPath = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
            if (-not (Test-Path $cpPath)) { New-Item -Path $cpPath -Force | Out-Null }
            Set-ItemProperty -Path $cpPath -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Get-AppxPackage "Microsoft.Copilot" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Write-Log "  [Copilot] ✓ Eliminado" "Green"
        }

        if ($Cfg.RemoveBloatware) {
            Write-Log "  [Bloatware] Eliminando apps preinstaladas..." "Gray"
            $bloatware = @(
                "Microsoft.549981C3F5F10", "Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.BingSearch",
                "Microsoft.GamingApp", "Microsoft.GetHelp", "Microsoft.Getstarted", "Microsoft.MicrosoftOfficeHub",
                "Microsoft.MicrosoftSolitaireCollection", "Microsoft.People", "Microsoft.PowerAutomateDesktop",
                "Microsoft.Todos", "Microsoft.WindowsAlarms", "Microsoft.WindowsMaps", "Microsoft.WindowsSoundRecorder",
                "Microsoft.Xbox.TCUI", "Microsoft.XboxApp", "Microsoft.XboxGameOverlay", "Microsoft.XboxGamingOverlay",
                "Microsoft.XboxIdentityProvider", "Microsoft.XboxSpeechToTextOverlay", "Microsoft.YourPhone",
                "Microsoft.ZuneMusic", "Microsoft.ZuneVideo", "Clipchamp.Clipchamp", "MicrosoftTeams",
                "Microsoft.MicrosoftStickyNotes"
            )
            $removed = 0
            foreach ($app in $bloatware) {
                try {
                    Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $app } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                    $removed++
                } catch {}
            }
            Write-Log "  [Bloatware] ✓ $removed apps procesadas" "Green"
        }

        $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
        Set-ItemProperty -Path $searchPath -Name "BingSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $searchPath -Name "CortanaConsent" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        if ($Cfg.DelayUpdates) {
            $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
            Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdates" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdatesPeriodInDays" -Value $Cfg.UpdateDelayDays -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdates" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdatesPeriodInDays" -Value 365 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Log "  [Updates] ✓ Actualizaciones retrasadas" "Green"
        }

        Write-Log "  ✓ Optimizacion completada" "Green"
        Update-StepStatus -Index 1 -Status "done"
        Update-ProgressBar -Percent 40 -Text "Optimizacion completada"
        $Script:Resultados["debloat"] = $true
        return $true
    }
    catch {
        Write-Log "  ✗ Error en optimizacion: $_" "Red"
        Update-StepStatus -Index 1 -Status "error"
        $Script:Resultados["debloat"] = $false
        return $false
    }
}

# =============================================================================
# PASO 3: CONTROLADORES (SDIO + fallback Windows Update)
# =============================================================================

# Fallback: buscar e instalar drivers vía Windows Update (COM Microsoft.Update)
function Invoke-WindowsUpdateDrivers {
    try {
        Write-Log "  [WU Drivers] Buscando drivers en Windows Update..." "Yellow"
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        # Buscar SOLO controladores no instalados
        $result = $searcher.Search("IsInstalled=0 and Type='Driver'")
        $count = $result.Updates.Count
        if ($count -eq 0) {
            Write-Log "  [WU Drivers] Windows Update no encontró drivers nuevos." "Gray"
            return $false
        }
        Write-Log "  [WU Drivers] $count driver(s) encontrados. Descargando..." "Yellow"
        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $result.Updates) { [void]$updatesToInstall.Add($u) }

        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        [void]$downloader.Download()

        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installResult = $installer.Install()
        $res = $installResult.ResultCode  # 2 = éxito
        if ($res -eq 2 -or $res -eq 3) {
            Write-Log "  [WU Drivers] ✓ $count driver(s) instalados vía Windows Update." "Green"
            return $true
        }
        else {
            Write-Log "  [WU Drivers] Resultado de instalación: $res (parcial o fallido)" "Yellow"
            return ($res -ge 2)
        }
    }
    catch {
        Write-Log "  [WU Drivers] Falló: $($_.Exception.Message)" "Yellow"
        return $false
    }
}

function Invoke-Drivers {
    Update-StepStatus -Index 2 -Status "working"
    Set-Smiley "download"
    Write-Log ""
    Write-Log "=== PASO 3: Controladores ===" "Cyan"
    Update-ProgressBar -Percent 42 -Text "Buscando controladores..."

    try {
        if (-not $Script:SystemInfo.HasInternet) {
            Write-Log "  ⚠ Sin internet. Omitiendo descarga de drivers." "Yellow"
            Update-StepStatus -Index 2 -Status "error"
            $Script:Resultados["drivers"] = $false
            return $false
        }

        $driversOk = $false

        # ---------- INTENTO 1: SDIO ----------
        try {
            Write-Log "  Buscando ultima version de SDIO..." "Gray"
            $page = Invoke-WebRequest -Uri $Cfg.SDIO_PAGE -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $zipLink = ($page.Links | Where-Object { $_.href -match '\.zip$' } | Select-Object -First 1).href

            if ($zipLink) {
                if ($zipLink -notmatch '^https?://') {
                    $zipLink = [System.Uri]::new([System.Uri]$Cfg.SDIO_PAGE, $zipLink).AbsoluteUri
                }

                $sdioZip = "$($Cfg.WorkDir)\SDIO.zip"
                $ok = Invoke-Descarga -Uri $zipLink -Destino $sdioZip -Intentos 2 -EsperaSeg 5

                if ($ok) {
                    $mb = [math]::Round((Get-Item $sdioZip).Length / 1MB, 1)
                    Write-Log "  ✓ SDIO descargado ($mb MB)" "Green"

                    Write-Log "  Extrayendo SDIO..." "Gray"
                    $sdioDir = "$($Cfg.WorkDir)\SDIO"
                    Expand-Archive -Path $sdioZip -DestinationPath $sdioDir -Force -ErrorAction SilentlyContinue

                    $sdioExe = Get-ChildItem -Path $sdioDir -Recurse -Filter "SDI*_R*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if (-not $sdioExe) { $sdioExe = Get-ChildItem -Path $sdioDir -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 }

                    if ($sdioExe) {
                        Write-Log "  Ejecutable: $($sdioExe.Name)" "Gray"
                        $scriptContent = "install all`r`nexit`r`n"
                        $scriptPath = "$sdioDir\auto_install.txt"
                        Set-Content -Path $scriptPath -Value $scriptContent -Encoding ASCII
                        Write-Log "  Iniciando SDIO en modo automatico..." "Yellow"
                        Update-ProgressBar -Percent 50 -Text "Instalando controladores (SDIO, puede tardar)..."
                        Start-Process -FilePath $sdioExe.FullName -ArgumentList "--script:`"$scriptPath`"" -Wait -ErrorAction SilentlyContinue
                        Write-Log "  ✓ SDIO completado" "Green"
                        $driversOk = $true
                    }
                    else {
                        Write-Log "  ⚠ No se encontro ejecutable de SDIO en el ZIP" "Yellow"
                    }
                }
                else {
                    Write-Log "  ⚠ Fallo la descarga de SDIO" "Yellow"
                }
            }
            else {
                Write-Log "  ⚠ La pagina de SDIO no ofrecio enlace .zip" "Yellow"
            }
        }
        catch {
            Write-Log "  ⚠ SDIO no disponible (pagina caida o bloqueada): $($_.Exception.Message)" "Yellow"
        }

        # ---------- INTENTO 2: WINDOWS UPDATE (fallback automático) ----------
        if (-not $driversOk) {
            Write-Log "  SDIO no disponible. Probando Windows Update como alternativa..." "Yellow"
            Update-ProgressBar -Percent 52 -Text "Buscando drivers en Windows Update..."
            $wuOk = Invoke-WindowsUpdateDrivers
            if ($wuOk) {
                $driversOk = $true
                Write-Log "  ✓ Drivers instalados via Windows Update" "Green"
            }
        }

        # ---------- INTENTO 3: NAVEGADOR MANUAL ----------
        if (-not $driversOk) {
            Write-Log "  ⚠ No se pudieron instalar drivers automaticamente." "Yellow"
            Write-Log "  Abriendo pagina de SDIO para descarga manual..." "Yellow"
            Start-Process $Cfg.SDIO_PAGE -ErrorAction SilentlyContinue
            Update-StepStatus -Index 2 -Status "error"
            $Script:Resultados["drivers"] = $false
            return $false
        }

        Update-StepStatus -Index 2 -Status "done"
        Update-ProgressBar -Percent 62 -Text "Controladores instalados"
        $Script:Resultados["drivers"] = $true
        return $true
    }
    catch {
        Write-Log "  ✗ Error general en controladores: $_" "Yellow"
        Update-StepStatus -Index 2 -Status "error"
        $Script:Resultados["drivers"] = $false
        return $false
    }
}

# =============================================================================
# PASO 4: OFFICE (ODT)
# =============================================================================
function Invoke-Office {
    Update-StepStatus -Index 3 -Status "working"
    Set-Smiley "download"
    Write-Log ""
    Write-Log "=== PASO 4: Office ===" "Cyan"
    Update-ProgressBar -Percent 64 -Text "Descargando Office Deployment Tool..."

    try {
        if (-not $Script:SystemInfo.HasInternet) {
            Write-Log "  ⚠ Sin internet. Omitiendo Office." "Yellow"
            Update-StepStatus -Index 3 -Status "error"
            $Script:Resultados["office"] = $false
            return $false
        }

        $ramGB = $Script:SystemInfo.RAM_GB
        $is64  = $Script:SystemInfo.Arch -match "64"

        if ($ramGB -le 4) {
            $product     = "ProPlus2021Volume"
            $channel     = "PerpetualVL2021"
            $edition     = "32"
            $excludeApps = @("Access","Groove","Lync","Publisher","Bing","OneNote","Outlook","Teams")
            Write-Log "  RAM ≤ 4GB → Office LTSC 2021 (32 bits, apps basicas)" "Yellow"
        }
        elseif ($ramGB -le 8) {
            $product     = "ProPlus2021Volume"
            $channel     = "PerpetualVL2021"
            $edition     = "64"
            $excludeApps = @("Groove","Lync","Bing")
            Write-Log "  RAM 4-8GB → Office LTSC 2021 (64 bits)" "Yellow"
        }
        else {
            $product     = "ProPlus2024Volume"
            $channel     = "PerpetualVL2024"
            $edition     = "64"
            $excludeApps = @("Groove","Lync")
            Write-Log "  RAM > 8GB → Office LTSC 2024 (64 bits)" "Yellow"
        }
        if (-not $is64) { $edition = "32"; $excludeApps = @("Access","Groove","Lync","Publisher","Bing","OneNote","Outlook","Teams") }

        $odtExe = "$($Cfg.WorkDir)\odt.exe"
        $ok = Invoke-Descarga -Uri $Cfg.ODT_URL -Destino $odtExe -Intentos 3
        if (-not $ok) {
            Write-Log "  ✗ Fallo la descarga del Office Deployment Tool" "Red"
            Update-StepStatus -Index 3 -Status "error"
            $Script:Resultados["office"] = $false
            return $false
        }
        Write-Log "  ✓ ODT descargado" "Green"

        $odtDir = "$($Cfg.WorkDir)\ODT"
        New-DirmIfMissing $odtDir
        Start-Process -FilePath $odtExe -ArgumentList "/quiet /extract:`"$odtDir`"" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue

        $excludeXml = ($excludeApps | ForEach-Object { "      <ExcludeApp ID=`"$_`" />" }) -join "`n"
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
        Write-Log "  Configuracion: $product ($edition-bit, $($Cfg.OfficeLang))" "Gray"

        $setupExe = "$odtDir\setup.exe"
        if (-not (Test-Path $setupExe)) {
            Write-Log "  ✗ No se encontro setup.exe (extracción del ODT falló)" "Red"
            Update-StepStatus -Index 3 -Status "error"
            $Script:Resultados["office"] = $false
            return $false
        }

        Write-Log "  Descargando archivos de Office (puede tardar varios minutos)..." "Yellow"
        Start-Process -FilePath $setupExe -ArgumentList "/download `"$configPath`"" -Wait -WindowStyle Hidden -ErrorAction Stop
        Write-Log "  ✓ Archivos de Office descargados" "Green"

        Write-Log "  Instalando Office (silencioso)..." "Yellow"
        Start-Process -FilePath $setupExe -ArgumentList "/configure `"$configPath`"" -Wait -WindowStyle Hidden -ErrorAction Stop
        Write-Log "  ✓ Office instalado correctamente" "Green"
        Update-StepStatus -Index 3 -Status "done"
        Update-ProgressBar -Percent 88 -Text "Office instalado"
        $Script:Resultados["office"] = $true
        return $true
    }
    catch {
        Write-Log "  ✗ Error instalando Office: $_" "Red"
        Update-StepStatus -Index 3 -Status "error"
        $Script:Resultados["office"] = $false
        return $false
    }
}

# =============================================================================
# PASO 5: ACTIVACION (MAS)
# =============================================================================
function Invoke-Activation {
    Update-StepStatus -Index 4 -Status "working"
    Set-Smiley "working"
    Write-Log ""
    Write-Log "=== PASO 5: Activacion (MAS) ===" "Cyan"
    Update-ProgressBar -Percent 90 -Text "Activando Windows y Office..."

    try {
        if (-not $Script:SystemInfo.HasInternet) {
            Write-Log "  ⚠ Sin internet. Omitiendo activacion." "Yellow"
            Update-StepStatus -Index 4 -Status "error"
            $Script:Resultados["activation"] = $false
            return $false
        }

        $masZip = "$($Cfg.WorkDir)\MAS.zip"
        $ok = Invoke-Descarga -Uri $Cfg.MAS_ZIP -Destino $masZip -Intentos 4 -EsperaSeg 10
        if (-not $ok) {
            Write-Log "  ✗ Fallo la descarga de MAS (GitHub). Reintente o descargue manualmente desde massgrave.dev" "Red"
            Update-StepStatus -Index 4 -Status "error"
            $Script:Resultados["activation"] = $false
            return $false
        }
        Write-Log "  ✓ MAS descargado" "Green"

        $masDir = "$($Cfg.WorkDir)\MAS"
        Expand-Archive -Path $masZip -DestinationPath $masDir -Force -ErrorAction SilentlyContinue

        Write-Log "  Activando Windows (HWID)..." "Yellow"
        $hwidScript = Get-ChildItem -Path $masDir -Recurse -Filter "hwid.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hwidScript) {
            Start-Process cmd.exe -ArgumentList "/c `"$($hwidScript.FullName)`"" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
            Write-Log "  ✓ Activacion HWID ejecutada" "Green"
        }
        else {
            $aioScript = Get-ChildItem -Path $masDir -Recurse -Filter "MAS_AIO.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($aioScript) {
                Start-Process cmd.exe -ArgumentList "/c `"$($aioScript.FullName)`"" -Wait -ErrorAction SilentlyContinue
            }
        }

        Write-Log "  Activando Office (Ohook)..." "Yellow"
        $ohookScript = Get-ChildItem -Path $masDir -Recurse -Filter "Ohook_Auto.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ohookScript) {
            Start-Process cmd.exe -ArgumentList "/c `"$($ohookScript.FullName)`"" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
            Write-Log "  ✓ Ohook ejecutado" "Green"
        }

        $licStatus = (Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*Windows*" } | Select-Object -First 1).LicenseStatus
        switch ($licStatus) {
            0    { Write-Log "  ⚠ Windows NO activado. Ejecute MAS manualmente." "Yellow" }
            1    { Write-Log "  ✓ Windows ACTIVADO correctamente" "Green" }
            5    { Write-Log "  ✓ Windows ACTIVADO (Notification Mode)" "Green" }
            default { Write-Log "  Estado de licencia: $licStatus" "Gray" }
        }

        Update-StepStatus -Index 4 -Status "done"
        Update-ProgressBar -Percent 96 -Text "Activacion completada"
        $Script:Resultados["activation"] = $true
        return $true
    }
    catch {
        Write-Log "  ✗ Error en activacion: $_" "Red"
        Update-StepStatus -Index 4 -Status "error"
        $Script:Resultados["activation"] = $false
        return $false
    }
}

# =============================================================================
# PASO 6: APLICACIONES (WINGET)
# =============================================================================
function Invoke-Apps {
    Update-StepStatus -Index 5 -Status "working"
    Set-Smiley "working"
    Write-Log ""
    Write-Log "=== PASO 6: Aplicaciones utiles ===" "Cyan"
    Update-ProgressBar -Percent 96 -Text "Instalando aplicaciones..."

    try {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Write-Log "  ⚠ winget no disponible. Instalando App Installer..." "Yellow"
            try {
                $wingetMsix = "$($Cfg.WorkDir)\Microsoft.DesktopAppInstaller.msixbundle"
                $ok = Invoke-Descarga -Uri $Cfg.WINGET_URL -Destino $wingetMsix -Intentos 3
                if ($ok) {
                    Add-AppxPackage -Path $wingetMsix -ErrorAction Stop
                    $winget = Get-Command winget -ErrorAction SilentlyContinue
                }
                if (-not $winget) {
                    throw "winget no se pudo instalar (descarga o Add-AppxPackage falló)."
                }
            } catch {
                Write-Log "  ✗ No se pudo instalar winget: $_" "Red"
                Write-Log "  Instale las apps manualmente desde ninite.com" "Yellow"
                Update-StepStatus -Index 5 -Status "error"
                $Script:Resultados["apps"] = $false
                return $false
            }
        }

        $apps = $Cfg.Apps
        $total = $apps.Count
        $done = 0
        $failed = 0

        foreach ($app in $apps) {
            if ($Script:Cancelled) { return $false }
            $done++
            $pct = 96 + [math]::Floor(($done / $total) * 3)
            Update-ProgressBar -Percent $pct -Text "Instalando $($app.Name) ($done/$total)..."
            Write-Log "  [$done/$total] Instalando $($app.Name)..." "Gray"
            try {
                $result = & winget install --id $($app.Id) --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
                if ($LASTEXITCODE -eq 0 -or $result -match "already installed") {
                    Write-Log "    ✓ $($app.Name) instalado" "Green"
                }
                else {
                    Write-Log "    ⚠ $($app.Name): posible error (exit code: $LASTEXITCODE)" "Yellow"
                    $failed++
                }
            } catch {
                Write-Log "    ✗ Error con $($app.Name): $_" "Red"
                $failed++
            }
        }

        if ($failed -eq 0) {
            Write-Log "  ✓ Todas las aplicaciones instaladas ($total/$total)" "Green"
        }
        else {
            Write-Log "  ✓ $([int]($total - $failed))/$total instaladas, $failed con advertencias" "Yellow"
        }

        Update-StepStatus -Index 5 -Status "done"
        Update-ProgressBar -Percent 99 -Text "Aplicaciones instaladas"
        $Script:Resultados["apps"] = $true
        return $true
    }
    catch {
        Write-Log "  ✗ Error instalando aplicaciones: $_" "Red"
        Update-StepStatus -Index 5 -Status "error"
        $Script:Resultados["apps"] = $false
        return $false
    }
}

# =============================================================================
# EJECUCION PRINCIPAL
# =============================================================================
function Invoke-AllSteps {
    $logFile = $Cfg.LogFile
    Write-Log "╔══════════════════════════════════════════╗" "Cyan"
    Write-Log "║  INSTALACION AUTOMATIZADA INICIADA       ║" "Cyan"
    Write-Log "╚══════════════════════════════════════════╝" "Cyan"
    Write-Log "Equipo: $env:COMPUTERNAME" "White"
    Write-Log "Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "White"
    Write-Log "Pasos seleccionados: $($Pasos -join ', ')" "Gray"
    Write-Log "Log: $logFile" "Gray"
    Write-Log ""

    # Ejecutar SOLO los pasos solicitados
    if ($Pasos -contains "preflight") {
        $Script:TotalEstimate = ($Cfg.Durations.Values | Measure-Object -Sum).Sum
        Invoke-PreFlight
    }

    if ($Pasos -contains "debloat" -and -not $Script:Cancelled) {
        if (-not $Script:SystemInfo.ContainsKey("IsWin11")) { Invoke-PreFlight } # asegurar info del sistema
        Invoke-Debloat
    }

    if ($Pasos -contains "drivers" -and -not $Script:Cancelled) {
        if (-not $Script:SystemInfo.ContainsKey("HasInternet")) { Invoke-PreFlight }
        Invoke-Drivers
    }

    if ($Pasos -contains "office" -and -not $Script:Cancelled) {
        if (-not $Script:SystemInfo.ContainsKey("HasInternet")) { Invoke-PreFlight }
        Invoke-Office
    }

    if ($Pasos -contains "activation" -and -not $Script:Cancelled) {
        if (-not $Script:SystemInfo.ContainsKey("HasInternet")) { Invoke-PreFlight }
        Invoke-Activation
    }

    if ($Pasos -contains "apps" -and -not $Script:Cancelled) {
        Invoke-Apps
    }

    # Resumen final
    if (-not $Script:Cancelled) {
        $elapsed = ((Get-Date) - $Script:StartTime)
        $elapsedStr = "{0:mm\:ss}" -f $elapsed
        Write-Log ""
        Write-Log "╔══════════════════════════════════════════╗" "Cyan"
        Write-Log "║         INSTALACION COMPLETADA           ║" "Cyan"
        Write-Log "╚══════════════════════════════════════════╝" "Cyan"
        Write-Log "  Tiempo total: $elapsedStr" "Cyan"

        $okCount   = ($Script:Resultados.Values | Where-Object { $_ -eq $true }).Count
        $failCount = ($Script:Resultados.Values | Where-Object { $_ -eq $false }).Count
        Write-Log "  Pasos completados: $okCount/$($Pasos.Count)" "White"
        if ($failCount -gt 0) {
            Write-Log "  Pasos con errores: $failCount (revisar log)" "Yellow"
        }
        Update-ProgressBar -Percent 100 -Text "✓ Instalacion completada en $elapsedStr"
        Set-Smiley "done"
    }
    else {
        Write-Log "  ⚠ Instalacion cancelada por el usuario" "Yellow"
        Set-Smiley "error"
    }

    Cerrar-LogArchivo
    Write-Host ""
    Write-Host "Instalacion completada. Log: $logFile" -ForegroundColor Green

    if ($Silencioso) {
        exit $failCount
    }
}

# =============================================================================
# INICIO
# =============================================================================
$Script:StartTime = Get-Date
$Script:TotalEstimate = ($Cfg.Durations.Values | Measure-Object -Sum).Sum

if (-not $Silencioso) {
    try {
        $form = Build-GUI
        [System.Windows.Forms.Application]::Run($form)
    }
    catch {
        Write-Host "GUI no disponible, ejecutando en modo consola..." -ForegroundColor Yellow
        Invoke-AllSteps
    }
}
else {
    Invoke-AllSteps
}