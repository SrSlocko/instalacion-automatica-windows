# =============================================================================
# DIAGNOSTICO Y CORRECCION - Windows (Soporte Tecnico)
# Ejecutar este archivo como ADMINISTRADOR (clic derecho -> Ejecutar con PowerShell)
# =============================================================================

# Verificar privilegios de administrador al inicio
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) {
    Write-Host "ADVERTENCIA: Este script NO se está ejecutando como Administrador." -ForegroundColor Yellow
    Write-Host "Algunas funciones (registro, servicios, Desbloquear Defender) fallarán." -ForegroundColor Yellow
    Write-Host "Cierre y vuelva a ejecutar como Administrador para corrección completa.`n" -ForegroundColor Cyan
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTICO Y CORRECCION DE EQUIPO      " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. DETECTAR SI YA HAY UN ANTIVIRUS INSTALADO
# -----------------------------------------------------------------------------
Write-Host "`n[1] Buscando antivirus instalados..." -ForegroundColor Yellow
$Antivirus = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue

if ($Antivirus) {
    Write-Host "  Antivirus detectado:" -ForegroundColor Green
    $Antivirus | ForEach-Object { Write-Host "    - $($_.displayName)" }
    $TieneAV = $true
}
else {
    Write-Host "  No se detectó ningún antivirus." -ForegroundColor Green
    $TieneAV = $false
}

# -----------------------------------------------------------------------------
# 2. ACTIVAR WINDOWS DEFENDER (SOLO SI NO HAY OTRO ANTIVIRUS)
# -----------------------------------------------------------------------------
if (-not $TieneAV) {
    Write-Host "`n[2] Activando Windows Defender (no hay otro antivirus)..." -ForegroundColor Yellow

    if (-not $esAdmin) {
        Write-Host "  Se requiere Administrador para activar Defender. Omitiendo este paso." -ForegroundColor Yellow
    }
    else {
        # Intentar mediante cmdlets de Defender (si el módulo está disponible)
        $cmdletsOk = $false
        try {
            Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop | Out-Null
            Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction Stop | Out-Null
            Set-MpPreference -DisableScriptScanning $false -ErrorAction SilentlyContinue | Out-Null
            $cmdletsOk = $true
            Write-Host "  Protección en tiempo real y monitor de comportamiento: ACTIVADOS (cmdlets)." -ForegroundColor Green
        }
        catch {
            Write-Host "  Cmdlets de Defender no disponibles o sin acceso, aplicando registro directamente..." -ForegroundColor Yellow
        }

        # Quitar bloqueos por directiva de grupo / registro (lo que suele "esconder" Defender)
        $regPaths = @(
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender",
            "HKLM:\SOFTWARE\Microsoft\Windows Defender"
        )
        $registroOk = $false
        foreach ($rp in $regPaths) {
            if (Test-Path $rp) {
                try {
                    Set-ItemProperty -Path $rp -Name "DisableAntiSpyware" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
                    Set-ItemProperty -Path $rp -Name "DisableAntiVirus"   -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
                    Write-Host "  Desbloqueado Defender en $rp" -ForegroundColor Green
                    $registroOk = $true
                }
                catch {
                    Write-Host "  No se pudo escribir en $rp (falta de permisos o clave inexistente)." -ForegroundColor Yellow
                }
            }
        }

        # Protección en tiempo real vía clave específica (Windows 10/11)
        $rtp = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
        if (Test-Path $rtp) {
            try {
                Set-ItemProperty -Path $rtp -Name "DisableRealtimeMonitoring" -Value 0 -Type DWord -Force -ErrorAction Stop | Out-Null
                Write-Host "  Monitor en tiempo real: ACTIVADO (registro)." -ForegroundColor Green
                $registroOk = $true
            }
            catch {
                Write-Host "  No se pudo activar monitor en tiempo real en el registro." -ForegroundColor Yellow
            }
        }

        if (-not $cmdletsOk -and -not $registroOk) {
            Write-Host "  No se pudo activar Defender por falta de privilegios de Administrador." -ForegroundColor Red
        }

        Write-Host "  Recomendación: reinicie el equipo para que Defender tome el control completo." -ForegroundColor Cyan
    }
}
else {
    Write-Host "`n[2] Se omite la activación de Defender porque ya hay otro antivirus instalado." -ForegroundColor Gray
}

# -----------------------------------------------------------------------------
# 3. INFORME DE BATERÍA (capacidad real, desgaste, ciclos)
# -----------------------------------------------------------------------------
Write-Host "`n[3] Generando informe de batería..." -ForegroundColor Yellow
$BateríaHtml = "$env:USERPROFILE\Desktop\Reporte_Bateria.html"
powercfg /batteryreport /output $BateríaHtml | Out-Null
Write-Host "  Informe guardado en: $BateríaHtml" -ForegroundColor Green
Write-Host "  Ábralo en el navegador y revise la sección ""Baterías instaladas"":" -ForegroundColor Cyan
Write-Host "    • Capacidad de diseño  = capacidad original de fábrica"
Write-Host "    • Carga completa actual = capacidad real hoy"
Write-Host "    • Desgaste % = ((Diseño - Actual) / Diseño) * 100"
Write-Host "    • Si el desgaste supera el 20-30 %, considere cambiar la batería." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 4. TEMPERATURA (zonas térmicas WMI)
# -----------------------------------------------------------------------------
Write-Host "`n[4] Leyendo temperatura del sistema..." -ForegroundColor Yellow
$Zonas = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
if ($Zonas) {
    foreach ($z in $Zonas) {
        $Kelvin = $z.CurrentTemperature / 10
        $Celsius = $Kelvin - 273.15
        Write-Host ("  {0}: {1:N1} °C" -f $z.InstanceName, $Celsius)
    }
    Write-Host "  > Si la CPU supera 85-90 °C bajo carga, el equipo está sobrecalentado." -ForegroundColor Cyan
}
else {
    Write-Host "  No se expone temperatura vía WMI en este equipo." -ForegroundColor Gray
    Write-Host "  Use HWMonitor, Core Temp o HWiNFO para ver la temperatura en tiempo real." -ForegroundColor Cyan
}

# -----------------------------------------------------------------------------
# 5. RECOMENDACIÓN DE PASTA TÉRMICA
# -----------------------------------------------------------------------------
Write-Host "`n[5] Evaluación de pasta térmica:" -ForegroundColor Yellow
Write-Host "  Cambie la pasta térmica si:" -ForegroundColor Cyan
Write-Host "    • La laptop/PC tiene más de 3-4 años y nunca se le ha cambiado."
Write-Host "    • La CPU pasa de 85-90 °C bajo carga (juegos, renders, etc.)."
Write-Host "    • El ventilador siempre gira al máximo y el equipo se calienta mucho."
Write-Host "  Si las temperaturas son normales (<75 °C bajo carga), no es necesario." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 6. NAVEGADOR LENTO AL ESCRIBIR (recomendaciones generales)
# -----------------------------------------------------------------------------
Write-Host "`n[6] Si el navegador va lento al escribir:" -ForegroundColor Yellow
Write-Host "    • Cierre pestañas innecesarias y reinicie el navegador." -ForegroundColor Cyan
Write-Host "    • Deshabilite extensiones que no use (especialmente bloqueadores de anuncios, traductor, cupones)." -ForegroundColor Cyan
Write-Host "    • Limpie caché y cookies (Ctrl + Mayús + Supr)." -ForegroundColor Cyan
Write-Host "    • En Chrome/Edge: vaya a configuración → Restablecer valores → Restablecer a predeterminados." -ForegroundColor Cyan
Write-Host "    • Revise el Administrador de tareas (Ctrl + Mayús + Esc): si hay un proceso al 100 % de CPU, finalícelo." -ForegroundColor Cyan
Write-Host "    • Ejecute un escaneo con Windows Defender (una vez activado) para descartar malware." -ForegroundColor Cyan

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTICO FINALIZADO                  " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
