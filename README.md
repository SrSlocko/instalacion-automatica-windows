# 🛠️ Instalación Automatizada para Soporte Técnico

Suite completa de **PowerShell** que automatiza el formateo y la configuración de máquinas Windows. Diseñada para técnicos de soporte que quieren **ahorrar tiempo** en cada equipo.

> Compatible con **Windows 10 / 11** (32 y 64 bits) · PowerShell 5.1+ · UTF-8 con BOM (sin errores de codificación)

## 📦 Archivos

| Archivo | Descripción |
|---------|-------------|
| `InstalacionAutomatica.ps1` | Script principal corregido (codificación UTF-8+BOM, sin errores de parseo) |
| `InstalacionAutomatica_Produccion.ps1` | **Versión de producción v2.2** — GUI con barra de progreso, descargas con reintentos, fallback de drivers por Windows Update, modo silencioso y pasos individuales |
| `Test-PreInstalacion.ps1` | Prueba previa de cada máquina: Windows, RAM, disco, internet, winget, antivirus, codificación |
| `DiagnosticoYCorreccion.ps1` | Diagnóstico: batería (informe HTML), temperaturas, pasta térmica, activación de Windows Defender, tips de navegador |
| `InstalacionAutomatica.bat` | Lanzador por lotes (clic derecho → Ejecutar como administrador) |

## 🚀 Instalación rápida

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\InstalacionAutomatica_Produccion.ps1              # Interfaz gráfica
.\InstalacionAutomatica_Produccion.ps1 -Silencioso  # Modo silencioso (logs)
.\InstalacionAutomatica_Produccion.ps1 -Pasos preflight,drivers  # Solo pasos específicos
```

## ⚙️ Qué hace la versión de producción (6 pasos)

| Paso | Descripción | Detalle |
|------|-------------|---------|
| 1️⃣ | **Verificar sistema** | Detecta Windows 10/11, RAM, CPU, disco, internet, winget |
| 2️⃣ | **Debloat** | Elimina telemetría, OneDrive, Copilot, bloatware; retrasa actualizaciones |
| 3️⃣ | **Controladores** | SDIO con **fallback automático a Windows Update** si la descarga falla |
| 4️⃣ | **Office** | ODT de Microsoft — versión óptima según RAM (LTSC 2021/2024, 32/64 bits) |
| 5️⃣ | **Activación** | Windows (HWID) y Office (Ohook) mediante MAS |
| 6️⃣ | **Aplicaciones** | 7-Zip, WinRAR, IrfanView, Chrome, Firefox, VLC, Notepad++, Adobe Reader, Zoom, TeamViewer, AnyDesk, Google Drive, Spotify (vía winget, se instala si falta) |

## 🔍 Flujo recomendado para soporte multi-equipo

1. **Pre-prueba**: `.\Test-PreInstalacion.ps1` → genera reporte en el Escritorio
2. **Diagnóstico**: `.\DiagnosticoYCorreccion.ps1` → batería, temperatura, Defender
3. **Instalación**: `.\InstalacionAutomatica_Produccion.ps1` → GUI completa

## 🛡️ Notas

- Ejecutar **siempre como Administrador**
- Los logs se guardan automáticamente en el **Escritorio**
- Los scripts de activación (MAS) descargan herramientas de terceros bajo tu responsabilidad
- Requiere internet para los pasos 3-6; si no lo hay, se omiten y se avisa

## 📋 Requisitos previos

- Windows 10 (1809+) o Windows 11
- PowerShell 5.1 o superior
- Conexión a internet (para drivers, Office, activación y apps)
- ~20 GB de espacio libre en disco
