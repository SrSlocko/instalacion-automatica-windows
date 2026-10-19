@echo off
title Instalacion Automatica - Soporte Tecnico
color 0B
echo.
echo  ╔═══════════════════════════════════════════╗
echo  ║   INSTALACION AUTOMATIZADA - SOPORTE      ║
echo  ║          TECNICO v2.0                     ║
echo  ╚═══════════════════════════════════════════╝
echo.
echo  Iniciando script...
echo  (Se abrirá una ventana de PowerShell)
echo.

:: Verificar que PowerShell existe
where powershell >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell no encontrado en este sistema.
    pause
    exit /b 1
)

:: Ejecutar el script con bypass de política de ejecución
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstalacionAutomatica.ps1"

if errorlevel 1 (
    echo.
    echo [AVISO] El script terminó con errores. Revisa la consola.
    pause
)
