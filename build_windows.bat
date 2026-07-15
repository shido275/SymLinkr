@echo off
title SymLinkr Executable Builder
echo ==================================================
echo         SymLinkr Windows Compilation Script
echo ==================================================
echo.

:: 1. Check if Python is installed
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python is not installed or not in system PATH.
    echo Please install Python 3.x and ensure "Add Python to PATH" is checked.
    echo Download: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

echo [INFO] Python environment detected.
echo [INFO] Installing required dependencies...
python -m pip install --upgrade pip
python -m pip install pyinstaller websockets requests psutil

echo.
echo [INFO] Starting PyInstaller build process...
python build_exe.py

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Build failed! Check messages above.
    pause
    exit /b 1
)

echo.
echo ==================================================
echo [SUCCESS] Standalone EXE compiled successfully!
echo Location: dist\symlinkr.exe
echo ==================================================
echo.
pause
