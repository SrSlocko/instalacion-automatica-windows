# 🛠️ Instalación Automatizada para Soporte Técnico

Script de **PowerShell** que automatiza el proceso completo de formateo y configuración de máquinas Windows. Diseñado para técnicos de soporte que quieren **ahorrar tiempo** en cada equipo.

## 🚀 Qué hace

Ejecuta **6 pasos automáticamente** con una interfaz gráfica limpia, barra de progreso y contador de tiempo estimado:

| Paso | Descripción | Detalle |
|------|-------------|---------|
| 1️⃣ | **Verificar sistema** | Detecta Windows 10/11, RAM, CPU, disco, conexión a internet |
| 2️⃣ | **Debloat completo** | Elimina telemetría, OneDrive, Copilot, Widgets, bloatware, Cortana, ads de Windows Spotlight, retrasa actualizaciones ~100 años |
| 3️⃣ | **Controladores** | Descarga e instala **SDIO** (Snappy Driver Installer Origin) automáticamente |
| 4️⃣ | **Office** | Descarga el **ODT de Microsoft** e instala la versión óptima según RAM del equipo |
| 5️⃣ | **Activación** | Activa Windows (**HWID**) y Office (**Ohook**) mediante **MAS** (Microsoft Activation Scripts) |
| 6️⃣ | **Aplicaciones** | Instala apps útiles vía **winget**: 7-Zip, WinRAR, IrfanView, Chrome, VLC, Notepad++, Adobe Reader, Zoom, TeamViewer, AnyDesk, Google Drive, Spotify |

## 🧠 Adaptativo por máquina

El script **detecta automáticamente** las especificaciones y elige la mejor opción:

| RAM detectada | Office instalado |
|---|---|
| ≤ 4 GB | LTSC 2021 · 32 bits · Solo Word, Excel, PowerPoint |
| 4–8 GB | LTSC 2021 · 64 bits · Apps estándar |
| > 8 GB | LTSC 2024 · 64 bits · Todos los apps |

- Detecta **Windows 10 vs 11** y aplica tweaks específicos de cada versión
- Si no hay internet, omite los pasos que lo requieren y avisa

## 📦 Archivos

| Archivo | Uso |
|---------|-----|
| `InstalacionAutomatica.ps1` | Script principal de PowerShell (ejecutar como Administrador) |
| `InstalacionAutomatica.bat` | Lanzador — doble clic en Windows para ejecutar el script |

## 🚀 Uso rápido

1. Copia los dos archivos a un **USB** o comparte por red
2. En la máquina del cliente, **doble clic** en `InstalacionAutomatica.bat`
3. Se auto-eleva a **Administrador** automáticamente
4. Haz clic en **▶ INICIAR INSTALACIÓN**
5. ¡Listo! Mira la barra de progreso y atiende otra máquina

## ⚙️ Personalización

Edita la sección `$Cfg` al inicio del `InstalacionAutomatica.ps1`:

```powershell
$Cfg = @{
    # Cambiar idioma de Office
    OfficeLang = "es-mx"    # o "es-es", "en-us", etc.

    # Quitar apps de la lista de instalación (borra la línea)
    Apps = @(
        @{Id="7zip.7zip"; Name="7-Zip"}
        @{Id="RARLab.WinRAR"; Name="WinRAR"}
        # ... borra las que no quieras
    )

    # Activar/desactivar opciones de debloat
    RemoveOneDrive   = $true
    RemoveCopilot    = $true
    RemoveBloatware  = $true
    DisableTelemetry = $true
    DelayUpdates     = $true
}
```

## 📝 Log automático

Al terminar, se guarda un archivo `.log` en el **Escritorio del cliente** con el detalle de todo lo que se hizo. Útil para revisar después.

## 📋 Requisitos

- **Windows 10** o **Windows 11** (64 o 32 bits)
- **PowerShell 5.1+** (viene preinstalado)
- Conexión a internet (para los pasos de descarga)
- Permisos de **Administrador** (el script se auto-eleva)

## ⚠️ Notas

- **Activación**: El paso 5 usa MAS (Microsoft Activation Scripts). Si la activación automática falla, el script abre MAS_AIO.cmd para que completes manualmente
- **URLs actualizables**: Si una URL deja de funcionar (ODT, SDIO), actualiza la variable correspondiente en `$Cfg`
- **Office**: El script usa el Office Deployment Tool (ODT) oficial de Microsoft. No necesita licencia de pago para instalar

## 📄 Licencia

Uso personal y para soporte técnico. Respeta los términos de servicio de las herramientas mencionadas.

---

**Hecho con ❤️ para técnicos de soporte que valoran su tiempo**
