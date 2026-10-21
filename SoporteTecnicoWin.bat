@echo off
title Soporte Tecnico Windows - Todo en Uno
color 0B
echo.
echo  ================================================
echo    SOPORTE TECNICO WINDOWS - SCRIPT UNIFICADO
echo  ================================================
echo.
echo  Iniciando menu interactivo...
echo  (Se pedira permiso de Administrador - UAC)
echo.

:: Verificar que PowerShell existe
where powershell >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell no encontrado en este sistema.
    pause
    exit /b 1
)

:: Ejecutar el script unificado (menu interactivo)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SoporteTecnicoWin.ps1"

if errorlevel 1 (
    echo.
    echo [AVISO] El script termino con errores. Revisa la consola.
    pause
)
