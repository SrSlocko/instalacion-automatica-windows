# 🛠️ Soporte Técnico Windows — Script Unificado

Herramienta **todo-en-uno** en PowerShell que automatiza el diagnóstico y la instalación completa de máquinas Windows. Diseñada para técnicos de soporte que quieren **ahorrar tiempo** en cada equipo.

> Compatible con **Windows 10 / 11** (32 y 64 bits) · PowerShell 5.1+ · UTF-8 con BOM

## 📦 Estructura del proyecto

| Archivo | Descripción |
|---------|-------------|
| `SoporteTecnicoWin.ps1` | **Script único** con todas las funciones (menú, diagnóstico, pre-test, instalación) |
| `SoporteTecnicoWin.bat` | Lanzador por lotes — doble clic y se eleva solo a Administrador |
| `README.md` | Este archivo |

Todo el proyecto es **un solo script**: sin redundancias ni código repetido.

## 🚀 Uso rápido

### Con doble clic
Ejecuta `SoporteTecnicoWin.bat` → pide UAC → abre el **menú interactivo**.

### Desde PowerShell (como Administrador)
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force

.\SoporteTecnicoWin.ps1                    # Menú interactivo (recomendado)
.\SoporteTecnicoWin.ps1 -Modo total        # Pre-test + diagnóstico + instalación completa
.\SoporteTecnicoWin.ps1 -Modo diag         # Solo diagnóstico y corrección
.\SoporteTecnicoWin.ps1 -Modo test         # Solo pruebas previas
.\SoporteTecnicoWin.ps1 -Modo install      # Solo instalación (6 pasos)
.\SoporteTecnicoWin.ps1 -Modo install -Gui # Instalación con interfaz gráfica
.\SoporteTecnicoWin.ps1 -Modo install -Pasos drivers,apps -Silencioso
```

## 🖥️ Menú interactivo

```
   1) Diagnostico y correccion  (bateria, temps, Defender)
   2) Pre-test del equipo       (reporte de compatibilidad)
   3) Instalacion completa      (6 pasos, GUI)
   4) Instalacion por consola   (6 pasos, sin GUI)
   5) Todo: pre-test + diag + instalacion
   6) Instalacion selectiva     (elegir pasos)
   0) Salir
```

## ⚙️ Los 6 pasos de instalación

| Paso | Descripción | Detalle |
|------|-------------|---------|
| 1️⃣ | **Verificar sistema** | Windows 10/11, RAM, CPU, disco, internet, winget |
| 2️⃣ | **Optimizar Windows** | Telemetría, OneDrive, Copilot, bloatware; retrasa actualizaciones |
| 3️⃣ | **Controladores** | SDIO con **fallback automático a Windows Update** |
| 4️⃣ | **Office** | ODT de Microsoft — versión óptima según RAM (LTSC 2021/2024, 32/64 bits) |
| 5️⃣ | **Activación** | Windows (HWID) y Office (Ohook) mediante MAS |
| 6️⃣ | **Aplicaciones** | 7-Zip, WinRAR, IrfanView, Chrome, Firefox, VLC, Notepad++, Adobe Reader, Zoom, TeamViewer, AnyDesk, Google Drive, Spotify |

## 🔍 Módulos de diagnóstico integrados

### Pre-test del equipo
Verifica PowerShell, versión de Windows, arquitectura, privilegios, internet, winget, GUI, disco y antivirus. Genera un **reporte** en el Escritorio con errores críticos y advertencias.

### Diagnóstico y corrección
- **Antivirus**: detecta los instalados
- **Windows Defender**: lo activa **solo si no hay otro antivirus**
- **Batería**: informe HTML con desgaste y ciclos (`powercfg /batteryreport`)
- **Temperatura**: lectura de zonas térmicas WMI
- **Pasta térmica**: criterios de evaluación
- **Navegador lento**: recomendaciones

## 🔧 Detalles técnicos

- **Auto-elevación**: si no eres Administrador, se relanza solo con UAC
- **Logs**: se guardan en el Escritorio (`SoporteTecnico_*.log`)
- **Descargas robustas**: 3 reintentos, TLS 1.2, verificación de tamaño
- **Sin internet**: los pasos que lo requieren se omiten y se avisa
- **Parámetros**: `-Modo`, `-Pasos`, `-Silencioso`, `-Gui`

## 🛡️ Notas

- Ejecutar **siempre como Administrador** (el script lo hace automáticamente)
- Los scripts de activación (MAS) descargan herramientas de terceros bajo tu responsabilidad
- Requiere ~20 GB libres para Office + controladores

## 📋 Requisitos

- Windows 10 (1809+) o Windows 11
- PowerShell 5.1 o superior
- Conexión a internet (drivers, Office, activación, apps)
