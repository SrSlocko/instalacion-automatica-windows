# ===================================================================
#  INSTALACIÓN AUTOMATIZADA PARA SOPORTE TÉCNICO
#  Versión 2.0
#  Compatible: Windows 10 / Windows 11 (64 y 32 bits)
#  Requiere: PowerShell 5.1+ · Se auto-eleva a Administrador
#
#  Pasos automatizados:
#    1. Detección del sistema
#    2. Debloat / Optimización (telemetría, OneDrive, Copilot, etc.)
#    3. Controladores (SDIO – Snappy Driver Installer Origin)
#    4. Office (ODT de Microsoft – versión adaptada al equipo)
#    5. Activación (MAS – HWID + Ohook)
#    6. Aplicaciones útiles (winget)
# ===================================================================

# ---------- Auto-elevación a Administrador ----------
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# ---------- Carga de ensamblados WinForms ----------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ===================================================================
#  CONFIGURACIÓN  (edita según necesidad)
# ===================================================================
$Cfg = @{
    # --- URLs de descarga (actualizar si dejan de funcionar) ---
    ODT_URL    = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20326-20112.exe"
    MAS_ZIP    = "https://github.com/massgravel/Microsoft-Activation-Scripts/archive/refs/heads/master.zip"
    SDIO_PAGE  = "https://www.glenn.delahoy.com/snappy-driver-installer-origin/"

    # --- Office ---
    OfficeLang = "es-es"

    # --- Retraso de actualizaciones (días) ---
    UpdateDelayDays = 36500   # ~100 años

    # --- Aplicaciones vía winget ---
    #  Quita el "#" de las que NO quieras instalar
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

    # --- Opciones de Debloat ---
    RemoveOneDrive     = $true
    RemoveCopilot      = $true
    RemoveBloatware    = $true
    DisableTelemetry   = $true
    DelayUpdates       = $true
    DisableWidgets     = $true
    DisableSpotlight   = $true

    # --- Directorio de trabajo ---
    WorkDir = "$env:TEMP\SoporteTecnico"

    # --- Duraciones estimadas por paso (segundos) ---
    Durations = @{
        PreFlight  = 10
        Debloat    = 60
        Drivers    = 300
        Office     = 480
        Activation = 60
        Apps       = 240
    }
}

# ===================================================================
#  VARIABLES GLOBALES
# ===================================================================
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

# ===================================================================
#  FUNCIONES AUXILIARES
# ===================================================================

function Write-Log {
    param([string]$Msg, [string]$Color = "White")
    $ts = Get-Date -Format "HH:mm:ss"
    $colors = @{
        "White"  = [System.Drawing.Color]::White
        "Green"  = [System.Drawing.Color]::FromArgb(0,230,118)
        "Red"    = [System.Drawing.Color]::FromArgb(255,82,82)
        "Yellow" = [System.Drawing.Color]::FromArgb(255,171,0)
        "Cyan"   = [System.Drawing.Color]::FromArgb(0,210,255)
        "Gray"   = [System.Drawing.Color]::FromArgb(150,150,150)
    }
    $Script:LogBox.SelectionStart = $Script:LogBox.TextLength
    $Script:LogBox.SelectionColor = [System.Drawing.Color]::FromArgb(100,200,255)
    $Script:LogBox.AppendText("[$ts] ")
    $Script:LogBox.SelectionColor = $colors[$Color]
    $Script:LogBox.AppendText("$Msg`r`n")
    $Script:LogBox.ScrollToCaret()
    $Script:LogBox.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-StepStatus {
    param([int]$Index, [string]$Status)
    # Status: "pending", "working", "done", "error"
    $icons = @{ pending="○"; working="◉"; done="✓"; error="✗" }
    $colors = @{
        pending=[System.Drawing.Color]::FromArgb(120,120,130)
        working=[System.Drawing.Color]::FromArgb(0,210,255)
        done=[System.Drawing.Color]::FromArgb(0,230,118)
        error=[System.Drawing.Color]::FromArgb(255,82,82)
    }
    $lbl = $Script:StepLabels[$Index]
    $lbl.ForeColor = $colors[$Status]
    $parts = $lbl.Text -split " ", 2
    $parts[0] = $icons[$Status]
    $lbl.Text = $parts -join " "
    $lbl.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-ProgressBar {
    param([int]$Percent, [string]$Text = "")
    if ($Percent -gt 100) { $Percent = 100 }
    if ($Percent -lt 0)   { $Percent = 0 }
    $Script:ProgressBar.Value = $Percent
    $Script:StatusLabel.Text  = $Text

    # Calcular tiempo restante
    if ($Script:StartTime -and $Script:TotalEstimate -gt 0) {
        $elapsed  = ((Get-Date) - $Script:StartTime).TotalSeconds
        $remaining = [math]::Max(0, $Script:TotalEstimate - $elapsed)
        $mins = [math]::Floor($remaining / 60)
        $secs = [math]::Floor($remaining % 60)
        if ($mins -ge 1) {
            $Script:TimeLabel.Text = "⏱️  Tiempo restante: ~$mins min"
        } else {
            $Script:TimeLabel.Text = "⏱️  Tiempo restante: ~$secs seg"
        }
    }
    $Script:ProgressBar.Refresh()
    $Script:StatusLabel.Refresh()
    $Script:TimeLabel.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Smiley {
    param([string]$Mood)
    $faces = @{
        "happy"    = [char]::ConvertFromUtf32(0x1F60A)   # 😊
        "working"  = [char]::ConvertFromUtf32(0x1F604)   # 😄
        "done"     = [char]::ConvertFromUtf32(0x1F973)   # 🥳
        "error"    = [char]::ConvertFromUtf32(0x1F615)   # 😕
        "think"    = [char]::ConvertFromUtf32(0x1F914)   # 🤔
        "download" = [char]::ConvertFromUtf32(0x1F4E5)   # 📥
    }
    $Script:SmileyLabel.Text = $faces[$Mood]
    $Script:SmileyLabel.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Test-Internet {
    try {
        $r = Test-NetConnection -ComputerName "8.8.8.8" -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet
        return $r
    } catch { return $false }
}

function Invoke-WithDelay {
    param([int]$Seconds, [string]$Msg = "Esperando...")
    for ($i = $Seconds; $i -gt 0; $i--) {
        if ($Script:Cancelled) { return }
        Update-ProgressBar -Percent ($Script:ProgressBar.Value) -Text "$Msg ($i seg)"
        Start-Sleep -Seconds 1
    }
}

function New-DirmIfMissing {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# ===================================================================
#  CREACIÓN DE LA INTERFAZ GRÁFICA
# ===================================================================

function Build-GUI {
    # --- Colores oscuros ---
    $bgDark     = [System.Drawing.Color]::FromArgb(18, 18, 30)
    $bgMedium   = [System.Drawing.Color]::FromArgb(30, 30, 48)
    $bgCard     = [System.Drawing.Color]::FromArgb(25, 25, 42)
    $textMain   = [System.Drawing.Color]::FromArgb(220, 220, 230)
    $textDim    = [System.Drawing.Color]::FromArgb(140, 140, 160)
    $accent     = [System.Drawing.Color]::FromArgb(0, 210, 255)
    $accentDark = [System.Drawing.Color]::FromArgb(0, 140, 200)
    $success    = [System.Drawing.Color]::FromArgb(0, 230, 118)
    $border     = [System.Drawing.Color]::FromArgb(50, 50, 75)

    # --- Ventana principal ---
    $form = New-Object System.Windows.Forms.Form
    $form.Text          = "Instalacion Automatica - Soporte Tecnico"
    $form.Size          = New-Object System.Drawing.Size(620, 760)
    $form.StartPosition = "CenterScreen"
    $form.BackColor     = $bgDark
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox   = $false
    $form.Font          = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon          = [System.Drawing.SystemIcons]::Application

    # --- Título ---
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text     = "INSTALACIÓN AUTOMATIZADA"
    $lblTitle.Font     = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = $accent
    $lblTitle.AutoSize = $true
    $lblTitle.Location = New-Object System.Drawing.Point(22, 14)
    $form.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text     = "Soporte Técnico · Windows 10 / 11"
    $lblSub.ForeColor = $textDim
    $lblSub.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSub.AutoSize = $true
    $lblSub.Location = New-Object System.Drawing.Point(24, 42)
    $form.Controls.Add($lblSub)

    # --- Smiley ---
    $smiley = New-Object System.Windows.Forms.Label
    $smiley.Text     = [char]::ConvertFromUtf32(0x1F60A)
    $smiley.Font     = New-Object System.Drawing.Font("Segoe UI Emoji", 42)
    $smiley.AutoSize = $true
    $smiley.Location = New-Object System.Drawing.Point(490, 8)
    $form.Controls.Add($smiley)

    # --- Info del sistema ---
    $sysInfo = New-Object System.Windows.Forms.Label
    $sysInfo.Text     = "Detectando sistema..."
    $sysInfo.ForeColor = $textDim
    $sysInfo.Font     = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $sysInfo.AutoSize = $true
    $sysInfo.Location = New-Object System.Drawing.Point(24, 66)
    $form.Controls.Add($sysInfo)

    # --- Separador ---
    $sep1 = New-Object System.Windows.Forms.Label
    $sep1.BorderStyle = "Fixed3D"
    $sep1.Size        = New-Object System.Drawing.Size(560, 2)
    $sep1.Location    = New-Object System.Drawing.Point(22, 92)
    $form.Controls.Add($sep1)

    # --- Barra de progreso ---
    $pbar = New-Object System.Windows.Forms.ProgressBar
    $pbar.Size     = New-Object System.Drawing.Size(560, 22)
    $pbar.Location = New-Object System.Drawing.Point(22, 102)
    $pbar.Style    = "Continuous"
    $pbar.BackColor = $bgMedium
    $pbar.ForeColor = $accent
    $form.Controls.Add($pbar)

    # --- Etiqueta de estado ---
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text     = "Listo para iniciar"
    $lblStatus.ForeColor = $textMain
    $lblStatus.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblStatus.AutoSize = $true
    $lblStatus.Location = New-Object System.Drawing.Point(22, 130)
    $form.Controls.Add($lblStatus)

    # --- Tiempo restante ---
    $lblTime = New-Object System.Windows.Forms.Label
    $lblTime.Text     = "⏱️  --"
    $lblTime.ForeColor = $textDim
    $lblTime.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblTime.AutoSize = $true
    $lblTime.Location = New-Object System.Drawing.Point(440, 130)
    $form.Controls.Add($lblTime)

    # --- Panel de pasos ---
    $stepPanel = New-Object System.Windows.Forms.Panel
    $stepPanel.Size     = New-Object System.Drawing.Size(560, 178)
    $stepPanel.Location = New-Object System.Drawing.Point(22, 156)
    $stepPanel.BackColor = $bgCard
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
        $lbl.Text     = "○ $($stepNames[$i])"
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb(120,120,130)
        $lbl.Font     = New-Object System.Drawing.Font("Segoe UI", 10)
        $lbl.AutoSize = $true
        $lbl.Location = New-Object System.Drawing.Point(14, 10 + ($i * 27))
        $stepPanel.Controls.Add($lbl)
        $Script:StepLabels += $lbl
    }

    # --- Caja de log ---
    $logBox = New-Object System.Windows.Forms.RichTextBox
    $logBox.Size     = New-Object System.Drawing.Size(560, 190)
    $logBox.Location = New-Object System.Drawing.Point(22, 344)
    $logBox.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 22)
    $logBox.ForeColor = [System.Drawing.Color]::FromArgb(200,200,210)
    $logBox.Font      = New-Object System.Drawing.Font("Consolas", 8.5)
    $logBox.ReadOnly  = $true
    $logBox.BorderStyle = "FixedSingle"
    $logBox.WordWrap  = $true
    $form.Controls.Add($logBox)

    # --- Botones ---
    $btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text     = "▶  INICIAR INSTALACIÓN"
    $btnStart.Size     = New-Object System.Drawing.Size(280, 44)
    $btnStart.Location = New-Object System.Drawing.Point(22, 546)
    $btnStart.FlatStyle = "Flat"
    $btnStart.BackColor = $accentDark
    $btnStart.ForeColor = [System.Drawing.Color]::White
    $btnStart.Font      = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnStart.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($btnStart)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text     = "✕  Cerrar"
    $btnClose.Size     = New-Object System.Drawing.Size(268, 44)
    $btnClose.Location = New-Object System.Drawing.Point(314, 546)
    $btnClose.FlatStyle = "Flat"
    $btnClose.BackColor = $bgMedium
    $btnClose.ForeColor = $textDim
    $btnClose.Font      = New-Object System.Drawing.Font("Segoe UI", 11)
    $btnClose.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $form.Controls.Add($btnClose)

    # --- Pie de página ---
    $lblFooter = New-Object System.Windows.Forms.Label
    $lblFooter.Text     = "Compatible con Windows 10 / 11 · Se ejecuta como Administrador · Los logs se guardan en el Escritorio"
    $lblFooter.ForeColor = [System.Drawing.Color]::FromArgb(80,80,100)
    $lblFooter.Font     = New-Object System.Drawing.Font("Segoe UI", 7.5)
    $lblFooter.AutoSize = $true
    $lblFooter.Location = New-Object System.Drawing.Point(22, 600)
    $form.Controls.Add($lblFooter)

    # --- Asignar variables globales ---
    $Script:Form         = $form
    $Script:ProgressBar  = $pbar
    $Script:StatusLabel  = $lblStatus
    $Script:TimeLabel    = $lblTime
    $Script:SmileyLabel  = $smiley
    $Script:SysInfoLabel = $sysInfo
    $Script:LogBox       = $logBox
    $Script:BtnStart     = $btnStart
    $Script:BtnClose     = $btnClose

    # --- Eventos ---
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

        # Ejecutar todos los pasos
        Invoke-AllSteps

        $btnClose.Enabled = $true
    })
}

# ===================================================================
#  PASO 1: VERIFICACIÓN DEL SISTEMA
# ===================================================================
function Invoke-PreFlight {
    Update-StepStatus -Index 0 -Status "working"
    Set-Smiley "think"
    Write-Log "=== PASO 1: Verificación del sistema ===" "Cyan"
    Update-ProgressBar -Percent 2 -Text "Detectando sistema..."

    try {
        # Sistema operativo
        $os = Get-CimInstance Win32_OperatingSystem
        $build = [int]$os.BuildNumber
        $isWin11 = $build -ge 22000
        $osName = if ($isWin11) { "Windows 11" } else { "Windows 10" }
        $osCaption = $os.Caption -replace "Microsoft ", ""
        Write-Log "  Sistema: $osCaption (Build $build)" "White"

        # RAM
        $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        Write-Log "  RAM: ${ramGB} GB" "White"

        # CPU
        $cpu = (Get-CimInstance Win32_Processor).Name.Trim()
        Write-Log "  CPU: $cpu" "White"

        # Arquitectura
        $arch = $os.OSArchitecture
        Write-Log "  Arquitectura: $arch" "White"

        # Espacio en disco C:
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        $diskTotalGB = [math]::Round($disk.Size / 1GB, 1)
        Write-Log "  Disco C: ${diskFreeGB} GB libres de ${diskTotalGB} GB" "White"

        # Nombre del equipo
        $pcName = $env:COMPUTERNAME
        Write-Log "  Equipo: $pcName" "White"

        # Internet
        Write-Log "  Verificando conexión a internet..." "Gray"
        $hasInternet = Test-Internet
        if ($hasInternet) {
            Write-Log "  ✓ Conexión a internet: OK" "Green"
        } else {
            Write-Log "  ✗ Sin conexión a internet. Algunos pasos fallarán." "Red"
        }

        # Almacenar info del sistema
        $Script:SystemInfo = @{
            OSName     = $osCaption
            IsWin11    = $isWin11
            Build      = $build
            RAM_GB     = $ramGB
            CPU        = $cpu
            Arch       = $arch
            DiskFreeGB = $diskFreeGB
            PCName     = $pcName
            HasInternet= $hasInternet
        }

        # Actualizar etiqueta del sistema en la GUI
        $Script:SysInfoLabel.Text = "$osCaption  |  ${ramGB} GB RAM  |  $cpu  |  ${diskFreeGB} GB libres"
        $Script:SysInfoLabel.Refresh()

        # winget disponible?
        $wingetOk = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        if (-not $wingetOk) {
            Write-Log "  ⚠ winget no encontrado. Se intentará instalarlo." "Yellow"
        }

        # Directorio de trabajo
        New-DirmIfMissing $Cfg.WorkDir
        Write-Log "  Directorio de trabajo: $($Cfg.WorkDir)" "Gray"

        Write-Log "  ✓ Verificación completada" "Green"
        Update-StepStatus -Index 0 -Status "done"
        Update-ProgressBar -Percent 5 -Text "Sistema verificado"
        return $true
    }
    catch {
        Write-Log "  ✗ Error en verificación: $_" "Red"
        Update-StepStatus -Index 0 -Status "error"
        return $false
    }
}

# ===================================================================
#  PASO 2: DEBLOAT / OPTIMIZACIÓN
# ===================================================================
function Invoke-Debloat {
    Update-StepStatus -Index 1 -Status "working"
    Set-Smiley "working"
    Write-Log ""
    Write-Log "=== PASO 2: Optimización de Windows ===" "Cyan"
    Update-ProgressBar -Percent 8 -Text "Optimizando Windows..."

    $isWin11 = $Script:SystemInfo.IsWin11

    try {
        # ---- 2a. Telemetría ----
        if ($Cfg.DisableTelemetry) {
            Write-Log "  [Telemetría] Desactivando..." "Gray"

            # Política de telemetría
            $tdPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            if (-not (Test-Path $tdPath)) { New-Item -Path $tdPath -Force | Out-Null }
            Set-ItemProperty -Path $tdPath -Name "AllowTelemetry" -Value 0 -Type DWord -Force

            $tdPath2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
            if (-not (Test-Path $tdPath2)) { New-Item -Path $tdPath2 -Force | Out-Null }
            Set-ItemProperty -Path $tdPath2 -Name "AllowTelemetry" -Value 0 -Type DWord -Force

            # Desactivar servicios de telemetría
            foreach ($svc in @("DiagTrack", "dmwappushservice", "diagnosticshub.standardcollector.service")) {
                try {
                    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                } catch {}
            }

            # Desactivar tareas programadas de telemetría
            $taskPaths = @(
                "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
                "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
                "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
                "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
                "\Microsoft\Windows\Autochk\Proxy"
                "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
            )
            foreach ($tp in $taskPaths) {
                try { Disable-ScheduledTask -TaskName (Split-Path $tp -Leaf) -TaskPath (Split-Path $tp -Parent) -ErrorAction SilentlyContinue } catch {}
            }

            # Desactivar Windows Error Reporting
            $werPath = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
            if (-not (Test-Path $werPath)) { New-Item -Path $werPath -Force | Out-Null }
            Set-ItemProperty -Path $werPath -Name "Disabled" -Value 1 -Type DWord -Force

            # Desactivar Feedback
            $feedbackPath = "HKCU:\Software\Microsoft\Siuf\Rules"
            if (-not (Test-Path $feedbackPath)) { New-Item -Path $feedbackPath -Force | Out-Null }
            Set-ItemProperty -Path $feedbackPath -Name "NumberOfSIUFInPeriod" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $feedbackPath -Name "PeriodInNanoSeconds" -Value 0 -Type DWord -Force

            Write-Log "  [Telemetría] ✓ Desactivada" "Green"
        }

        Update-ProgressBar -Percent 12 -Text "Eliminando OneDrive..."

        # ---- 2b. OneDrive ----
        if ($Cfg.RemoveOneDrive) {
            Write-Log "  [OneDrive] Eliminando..." "Gray"

            # Matar proceso
            Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1

            # Desinstalar
            $odPaths = @(
                "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe"
                "$env:SYSTEMROOT\System32\OneDriveSetup.exe"
            )
            foreach ($od in $odPaths) {
                if (Test-Path $od) {
                    Start-Process -FilePath $od -ArgumentList "/uninstall" -Wait -WindowStyle Hidden
                    break
                }
            }

            # Eliminar carpetas residuales
            foreach ($folder in @(
                "$env:USERPROFILE\OneDrive"
                "$env:LOCALAPPDATA\Microsoft\OneDrive"
                "$env:PROGRAMDATA\Microsoft OneDrive"
            )) {
                Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Quitar de Explorador
            foreach ($clsid in @(
                "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
                "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
            )) {
                try {
                    if (Test-Path $clsid) {
                        Set-ItemProperty -Path $clsid -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord -Force
                    }
                } catch {}
            }

            Write-Log "  [OneDrive] ✓ Eliminado" "Green"
        }

        Update-ProgressBar -Percent 18 -Text "Eliminando Copilot y Widgets..."

        # ---- 2c. Copilot (solo Win11) ----
        if ($Cfg.RemoveCopilot -and $isWin11) {
            Write-Log "  [Copilot] Eliminando..." "Gray"

            # Desactivar Copilot
            $cpPath = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
            if (-not (Test-Path $cpPath)) { New-Item -Path $cpPath -Force | Out-Null }
            Set-ItemProperty -Path $cpPath -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force

            # Quitar del taskbar
            $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Set-ItemProperty -Path $advPath -Name "ShowCopilotButton" -Value 0 -Type DWord -Force

            # Desinstalar app
            Get-AppxPackage "Microsoft.Copilot" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

            Write-Log "  [Copilot] ✓ Eliminado" "Green"
        }

        # ---- 2d. Widgets (solo Win11) ----
        if ($Cfg.DisableWidgets -and $isWin11) {
            Write-Log "  [Widgets] Eliminando..." "Gray"
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord -Force
            Get-AppxPackage "Microsoft.WindowsWidgets" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Write-Log "  [Widgets] ✓ Eliminados" "Green"
        }

        Update-ProgressBar -Percent 24 -Text "Desactivando bloatware..."

        # ---- 2e. Bloatware ----
        if ($Cfg.RemoveBloatware) {
            Write-Log "  [Bloatware] Eliminando apps preinstaladas..." "Gray"

            $bloatware = @(
                "Microsoft.549981C3F5F10"          # Cortana
                "Microsoft.BingNews"
                "Microsoft.BingWeather"
                "Microsoft.BingSearch"
                "Microsoft.GamingApp"
                "Microsoft.GetHelp"
                "Microsoft.Getstarted"
                "Microsoft.MicrosoftOfficeHub"
                "Microsoft.MicrosoftSolitaireCollection"
                "Microsoft.People"
                "Microsoft.PowerAutomateDesktop"
                "Microsoft.Todos"
                "Microsoft.WindowsAlarms"
                "Microsoft.WindowsMaps"
                "Microsoft.WindowsSoundRecorder"
                "Microsoft.Xbox.TCUI"
                "Microsoft.XboxApp"
                "Microsoft.XboxGameOverlay"
                "Microsoft.XboxGamingOverlay"
                "Microsoft.XboxIdentityProvider"
                "Microsoft.XboxSpeechToTextOverlay"
                "Microsoft.YourPhone"
                "Microsoft.ZuneMusic"
                "Microsoft.ZuneVideo"
                "Clipchamp.Clipchamp"
                "MicrosoftTeams"
                "Microsoft.MicrosoftStickyNotes"
                "Microsoft.PowerShell"
            )

            $removed = 0
            foreach ($app in $bloatware) {
                try {
                    Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue |
                        Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -eq $app } |
                        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                    $removed++
                } catch {}
            }
            Write-Log "  [Bloatware] ✓ $removed apps procesadas" "Green"
        }

        Update-ProgressBar -Percent 30 -Text "Configurando privacidad..."

        # ---- 2f. Búsqueda web en el menú Inicio ----
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0 -Type DWord -Force

        # ---- 2g. Cortana ----
        $ctPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        if (-not (Test-Path $ctPath)) { New-Item -Path $ctPath -Force | Out-Null }
        Set-ItemProperty -Path $ctPath -Name "AllowCortana" -Value 0 -Type DWord -Force

        # ---- 2h. Historial de actividad ----
        $sysPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $sysPath)) { New-Item -Path $sysPath -Force | Out-Null }
        Set-ItemProperty -Path $sysPath -Name "EnableActivityFeed" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $sysPath -Name "PublishUserActivities" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $sysPath -Name "UploadUserActivities" -Value 0 -Type DWord -Force

        # ---- 2i. Windows Spotlight ----
        if ($Cfg.DisableSpotlight) {
            $cdPath = "HKCU:\Software\Policies\Microsoft\Windows\CloudContent"
            if (-not (Test-Path $cdPath)) { New-Item -Path $cdPath -Force | Out-Null }
            Set-ItemProperty -Path $cdPath -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $cdPath -Name "DisableWindowsSpotlightOnSettings" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $cdPath -Name "DisableConsumerFeatures" -Value 1 -Type DWord -Force

            # Ads en el menú Inicio
            $cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            foreach ($val in @(
                "RotatingLockScreenEnabled"
                "RotatingLockScreenOverlayEnabled"
                "SubscribedContent-338387Enabled"
                "SubscribedContent-338388Enabled"
                "SubscribedContent-338389Enabled"
                "SubscribedContent-310093Enabled"
                "SystemPaneSuggestionsEnabled"
                "SilentInstalledAppsEnabled"
            )) {
                try { Set-ItemProperty -Path $cdmPath -Name $val -Value 0 -Type DWord -Force } catch {}
            }
            Write-Log "  [Spotlight/Ads] ✓ Desactivados" "Green"
        }

        Update-ProgressBar -Percent 36 -Text "Retrasando actualizaciones..."

        # ---- 2j. Retrasar actualizaciones ----
        if ($Cfg.DelayUpdates) {
            Write-Log "  [Updates] Retrasando actualizaciones $($Cfg.UpdateDelayDays) días..." "Gray"

            $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
            Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdates" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdatesPeriodInDays" -Value $Cfg.UpdateDelayDays -Type DWord -Force
            Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdates" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdatesPeriodInDays" -Value 365 -Type DWord -Force
            Set-ItemProperty -Path $wuPath -Name "PauseFeatureUpdatesStartTime" -Value "2025-01-01T00:00:00Z" -Force
            Set-ItemProperty -Path $wuPath -Name "PauseQualityUpdatesStartTime" -Value "2025-01-01T00:00:00Z" -Force

            Write-Log "  [Updates] ✓ Actualizaciones retrasadas" "Green"
        }

        Write-Log ""
        Write-Log "  ✓ Optimización completada" "Green"
        Update-StepStatus -Index 1 -Status "done"
        Update-ProgressBar -Percent 40 -Text "Optimización completada"
        return $true
    }
    catch {
        Write-Log "  ✗ Error en optimización: $_" "Red"
        Update-StepStatus -Index 1 -Status "error"
        return $false
    }
}

# ===================================================================
#  PASO 3: CONTROLADORES (SDIO)
# ===================================================================
function Invoke-Drivers {
    Update-StepStatus -Index 2 -Status "working"
    Set-Smiley "download"
    Write-Log ""
    Write-Log "=== PASO 3: Controladores (SDIO) ===" "Cyan"
    Update-ProgressBar -Percent 42 -Text "Descargando SDIO..."

    try {
        if (-not $Script:SystemInfo.HasInternet) {
            Write-Log "  ⚠ Sin internet. Omitiendo descarga de SDIO." "Yellow"
            Write-Log "  Descarga SDIO manualmente desde: $($Cfg.SDIO_PAGE)" "Yellow"
            Update-StepStatus -Index 2 -Status "error"
            return $false
        }

        # Buscar enlace de descarga en la página de Glenn Delahoy
        Write-Log "  Buscando última versión de SDIO..." "Gray"
        $page = Invoke-WebRequest -Uri $Cfg.SDIO_PAGE -UseBasicParsing -TimeoutSec 30
        $zipLink = ($page.Links | Where-Object { $_.href -match '\.zip$' } | Select-Object -First 1).href

        if (-not $zipLink) {
            Write-Log "  ⚠ No se encontró enlace de SDIO. Abriendo navegador..." "Yellow"
            Start-Process $Cfg.SDIO_PAGE
            Update-StepStatus -Index 2 -Status "error"
            return $false
        }

        # Corregir URL relativa
        if ($zipLink -notmatch '^https?://') {
            $zipLink = [System.Uri]::new([System.Uri]$Cfg.SDIO_PAGE, $zipLink).AbsoluteUri
        }

        Write-Log "  Descargando: $zipLink" "Gray"
        $sdioZip = "$($Cfg.WorkDir)\SDIO.zip"
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($zipLink, $sdioZip)
        Write-Log "  ✓ SDIO descargado ($([math]::Round((Get-Item $sdioZip).Length/1MB,1)) MB)" "Green"

        # Extraer
        Write-Log "  Extrayendo SDIO..." "Gray"
        Update-ProgressBar -Percent 46 -Text "Extrayendo SDIO..."
        $sdioDir = "$($Cfg.WorkDir)\SDIO"
        Expand-Archive -Path $sdioZip -DestinationPath $sdioDir -Force

        # Buscar el ejecutable SDIO
        $sdioExe = Get-ChildItem -Path $sdioDir -Recurse -Filter "SDI*_R*.exe" | Select-Object -First 1
        if (-not $sdioExe) {
            $sdioExe = Get-ChildItem -Path $sdioDir -Recurse -Filter "*.exe" | Select-Object -First 1
        }

        if ($sdioExe) {
            Write-Log "  Ejecutable: $($sdioExe.Name)" "Gray"

            # Crear script de instalación automática
            $scriptContent = "install all`r`nexit`r`n"
            $scriptPath = "$sdioDir\auto_install.txt"
            Set-Content -Path $scriptPath -Value $scriptContent -Encoding ASCII

            Write-Log "  Iniciando SDIO en modo automático..." "Yellow"
            Write-Log "  (Los drivers se instalarán automáticamente)" "Gray"
            Update-ProgressBar -Percent 50 -Text "Instalando controladores (puede tardar)..."

            # Ejecutar SDIO con el script
            Start-Process -FilePath $sdioExe.FullName -ArgumentList "--script:`"$scriptPath`"" -Wait

            Write-Log "  ✓ SDIO completado" "Green"
        }
        else {
            Write-Log "  ⚠ No se encontró ejecutable de SDIO" "Yellow"
            Start-Process $sdioDir
            Update-StepStatus -Index 2 -Status "error"
            return $false
        }

        Update-StepStatus -Index 2 -Status "done"
        Update-ProgressBar -Percent 62 -Text "Controladores instalados"
        return $true
    }
    catch {
        Write-Log "  ✗ Error con SDIO: $_" "Yellow"
        Write-Log "  Puedes descargarlo manualmente desde: $($Cfg.SDIO_PAGE)" "Yellow"
        Start-Process $Cfg.SDIO_PAGE
        Update-StepStatus -Index 2 -Status "error"
        return $false
    }
}

# ===================================================================
#  PASO 4: OFFICE (ODT)
# ===================================================================
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
            return $false
        }

        $ramGB = $Script:SystemInfo.RAM_GB
        $is64  = $Script:SystemInfo.Arch -match "64"

        # Seleccionar versión de Office según RAM
        if ($ramGB -le 4) {
            $product     = "ProPlus2021Volume"
            $channel     = "PerpetualVL2021"
            $edition     = "32"
            $excludeApps = @("Access","Groove","Lync","Publisher","Bing","OneNote","Outlook","Teams")
            Write-Log "  RAM ≤ 4GB → Office LTSC 2021 (32 bits, apps básicas)" "Yellow"
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

        # Si es 32-bit hardware, forzar 32
        if (-not $is64) { $edition = "32"; $excludeApps = @("Access","Groove","Lync","Publisher","Bing","OneNote","Outlook","Teams") }

        # ---- Descargar ODT ----
        Write-Log "  Descargando Office Deployment Tool..." "Gray"
        $odtExe = "$($Cfg.WorkDir)\odt.exe"
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Cfg.ODT_URL, $odtExe)
        Write-Log "  ✓ ODT descargado" "Green"

        # ---- Extraer ODT ----
        Write-Log "  Extrayendo ODT..." "Gray"
        Update-ProgressBar -Percent 68 -Text "Extrayendo ODT..."
        $odtDir = "$($Cfg.WorkDir)\ODT"
        New-DirmIfMissing $odtDir
        Start-Process -FilePath $odtExe -ArgumentList "/quiet /extract:`"$odtDir`"" -Wait -WindowStyle Hidden

        # ---- Crear configuración XML ----
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
        Write-Log "  Configuración: $product ($edition-bit, $($Cfg.OfficeLang))" "Gray"

        # ---- Descargar archivos de Office ----
        Write-Log "  Descargando archivos de Office (esto puede tardar)..." "Yellow"
        Update-ProgressBar -Percent 72 -Text "Descargando Office (puede tardar varios minutos)..."
        $setupExe = "$odtDir\setup.exe"

        if (-not (Test-Path $setupExe)) {
            Write-Log "  ✗ No se encontró setup.exe en la extracción del ODT" "Red"
            Update-StepStatus -Index 3 -Status "error"
            return $false
        }

        Start-Process -FilePath $setupExe -ArgumentList "/download `"$configPath`"" -Wait -WindowStyle Hidden
        Write-Log "  ✓ Archivos de Office descargados" "Green"

        # ---- Instalar Office ----
        Write-Log "  Instalando Office (silencioso)..." "Yellow"
        Update-ProgressBar -Percent 80 -Text "Instalando Office..."
        Start-Process -FilePath $setupExe -ArgumentList "/configure `"$configPath`"" -Wait -WindowStyle Hidden

        Write-Log "  ✓ Office instalado correctamente" "Green"
        Update-StepStatus -Index 3 -Status "done"
        Update-ProgressBar -Percent 88 -Text "Office instalado"
        return $true
    }
    catch {
        Write-Log "  ✗ Error instalando Office: $_" "Red"
        Write-Log "  Instálalo manualmente desde massgrave.dev" "Yellow"
        Update-StepStatus -Index 3 -Status "error"
        return $false
    }
}

# ===================================================================
#  PASO 5: ACTIVACIÓN (MAS)
# ===================================================================
function Invoke-Activation {
    Update-StepStatus -Index 4 -Status "working"
    Set-Smiley "working"
    Write-Log ""
    Write-Log "=== PASO 5: Activación (MAS) ===" "Cyan"
    Update-ProgressBar -Percent 90 -Text "Activando Windows y Office..."

    try {
        if (-not $Script:SystemInfo.HasInternet) {
            Write-Log "  ⚠ Sin internet. Omitiendo activación." "Yellow"
            Update-StepStatus -Index 4 -Status "error"
            return $false
        }

        # ---- Descargar MAS ----
        Write-Log "  Descargando MAS (Microsoft Activation Scripts)..." "Gray"
        $masZip = "$($Cfg.WorkDir)\MAS.zip"
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Cfg.MAS_ZIP, $masZip)
        Write-Log "  ✓ MAS descargado" "Green"

        # ---- Extraer MAS ----
        Write-Log "  Extrayendo MAS..." "Gray"
        $masDir = "$($Cfg.WorkDir)\MAS"
        Expand-Archive -Path $masZip -DestinationPath $masDir -Force

        # ---- Activar Windows (HWID) ----
        Write-Log "  Activando Windows (HWID)..." "Yellow"
        Update-ProgressBar -Percent 92 -Text "Activando Windows..."

        $hwidScript = Get-ChildItem -Path $masDir -Recurse -Filter "hwid.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hwidScript) {
            # Ejecutar HWID en consola separada
            Start-Process cmd.exe -ArgumentList "/c `"$($hwidScript.FullName)`"" -Wait -WindowStyle Hidden
            Write-Log "  ✓ Activación HWID ejecutada" "Green"
        }
        else {
            # Fallback: intentar con MAS AIO
            $aioScript = Get-ChildItem -Path $masDir -Recurse -Filter "MAS_AIO.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($aioScript) {
                Write-Log "  Ejecutando MAS All-In-One (selecciona HWID en la consola)..." "Yellow"
                Start-Process cmd.exe -ArgumentList "/c `"$($aioScript.FullName)`"" -Wait
            }
            else {
                Write-Log "  ⚠ Scripts MAS no encontrados en el ZIP" "Yellow"
            }
        }

        # ---- Activar Office (Ohook) ----
        Write-Log "  Activando Office (Ohook)..." "Yellow"
        Update-ProgressBar -Percent 95 -Text "Activando Office..."

        $ohookScript = Get-ChildItem -Path $masDir -Recurse -Filter "Ohook_Auto.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ohookScript) {
            Start-Process cmd.exe -ArgumentList "/c `"$($ohookScript.FullName)`"" -Wait -WindowStyle Hidden
            Write-Log "  ✓ Ohook ejecutado" "Green"
        }
        else {
            # Alternativa: buscar cualquier script de Ohook
            $ohookAlt = Get-ChildItem -Path $masDir -Recurse -Filter "*hook*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ohookAlt) {
                Start-Process cmd.exe -ArgumentList "/c `"$($ohookAlt.FullName)`"" -Wait
            }
        }

        # Verificar activación de Windows
        Write-Log "  Verificando activación..." "Gray"
        $licStatus = (Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*Windows*" } |
            Select-Object -First 1).LicenseStatus
        switch ($licStatus) {
            0    { Write-Log "  ⚠ Windows NO activado. Ejecuta MAS manualmente." "Yellow" }
            1    { Write-Log "  ✓ Windows ACTIVADO correctamente" "Green" }
            5    { Write-Log "  ✓ Windows ACTIVado (Notification Mode)" "Green" }
            default { Write-Log "  Estado de licencia: $licStatus" "Gray" }
        }

        Write-Log ""
        Write-Log "  Si la activación no fue automática, ejecuta MAS manualmente:" "Yellow"
        Write-Log "  $masDir\MAS\All-In-One-Version\MAS_AIO.cmd" "Yellow"

        Update-StepStatus -Index 4 -Status "done"
        Update-ProgressBar -Percent 96 -Text "Activación completada"
        return $true
    }
    catch {
        Write-Log "  ✗ Error en activación: $_" "Red"
        Update-StepStatus -Index 4 -Status "error"
        return $false
    }
}

# ===================================================================
#  PASO 6: APLICACIONES (WINGET)
# ===================================================================
function Invoke-Apps {
    Update-StepStatus -Index 5 -Status "working"
    Set-Smiley "working"
    Write-Log ""
    Write-Log "=== PASO 6: Aplicaciones útiles ===" "Cyan"
    Update-ProgressBar -Percent 96 -Text "Instalando aplicaciones..."

    try {
        # Verificar winget
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Write-Log "  ⚠ winget no disponible. Instalando App Installer..." "Yellow"
            try {
                $wingetMsix = "$($Cfg.WorkDir)\Microsoft.DesktopAppInstaller.msixbundle"
                $wc = New-Object System.Net.WebClient
                $wc.DownloadFile("https://aka.ms/getwinget", $wingetMsix)
                Add-AppxPackage -Path $wingetMsix -ErrorAction Stop
                $winget = Get-Command winget -ErrorAction SilentlyContinue
            } catch {
                Write-Log "  ✗ No se pudo instalar winget" "Red"
                Write-Log "  Instala las apps manualmente desde ninite.com" "Yellow"
                Update-StepStatus -Index 5 -Status "error"
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
            }
            catch {
                Write-Log "    ✗ Error con $($app.Name): $_" "Red"
                $failed++
            }
        }

        Write-Log ""
        if ($failed -eq 0) {
            Write-Log "  ✓ Todas las aplicaciones instaladas ($total/$total)" "Green"
        }
        else {
            Write-Log "  ✓ $([int]($total - $failed))/$total aplicaciones instaladas, $failed con advertencias" "Yellow"
        }

        Update-StepStatus -Index 5 -Status "done"
        Update-ProgressBar -Percent 99 -Text "Aplicaciones instaladas"
        return $true
    }
    catch {
        Write-Log "  ✗ Error instalando aplicaciones: $_" "Red"
        Update-StepStatus -Index 5 -Status "error"
        return $false
    }
}

# ===================================================================
#  EJECUCIÓN PRINCIPAL
# ===================================================================
function Invoke-AllSteps {
    $logFile = "$env:USERPROFILE\Desktop\Instalacion_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    Write-Log "╔══════════════════════════════════════════╗" "Cyan"
    Write-Log "║  INSTALACIÓN AUTOMATIZADA INICIADA       ║" "Cyan"
    Write-Log "╚══════════════════════════════════════════╝" "Cyan"
    Write-Log ""
    Write-Log "Equipo: $env:COMPUTERNAME" "White"
    Write-Log "Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "White"
    Write-Log "Log: $logFile" "Gray"
    Write-Log ""

    # Paso 1
    $r1 = Invoke-PreFlight

    # Paso 2
    if (-not $Script:Cancelled) { $r2 = Invoke-Debloat }

    # Paso 3
    if (-not $Script:Cancelled) { $r3 = Invoke-Drivers }

    # Paso 4
    if (-not $Script:Cancelled) { $r4 = Invoke-Office }

    # Paso 5
    if (-not $Script:Cancelled) { $r5 = Invoke-Activation }

    # Paso 6
    if (-not $Script:Cancelled) { $r6 = Invoke-Apps }

    # ---- Resumen final ----
    if (-not $Script:Cancelled) {
        $elapsed = ((Get-Date) - $Script:StartTime)
        $elapsedStr = "{0:mm\:ss}" -f $elapsed

        Write-Log ""
        Write-Log "╔══════════════════════════════════════════╗" "Cyan"
        Write-Log "║         INSTALACIÓN COMPLETADA           ║" "Cyan"
        Write-Log "╚══════════════════════════════════════════╝" "Cyan"
        Write-Log "  Tiempo total: $elapsedStr" "Cyan"

        $results = @($r1, $r2, $r3, $r4, $r5, $r6)
        $okCount = ($results | Where-Object { $_ -eq $true }).Count
        $failCount = ($results | Where-Object { $_ -eq $false }).Count
        Write-Log "  Pasos completados: $okCount/6" "White"
        if ($failCount -gt 0) {
            Write-Log "  Pasos con errores: $failCount (revisar log)" "Yellow"
        }

        Update-ProgressBar -Percent 100 -Text "✓ Instalación completada en $elapsedStr"
        Set-Smiley "done"
    }
    else {
        Write-Log ""
        Write-Log "  ⚠ Instalación cancelada por el usuario" "Yellow"
        Set-Smiley "error"
        Update-ProgressBar -Percent $Script:ProgressBar.Value -Text "Cancelado"
    }

    # Guardar log
    try {
        $Script:LogBox.Text | Out-File -FilePath $logFile -Encoding UTF8
        Write-Log ""
        Write-Log "  Log guardado en: $logFile" "Gray"
    } catch {}

    # Guardar en consola también (por si se ejecuta sin GUI)
    Write-Host ""
    Write-Host "Instalación completada. Log: $logFile" -ForegroundColor Green
}

# ===================================================================
#  INICIO
# ===================================================================
Build-GUI
[System.Windows.Forms.Application]::Run($Script:Form)
