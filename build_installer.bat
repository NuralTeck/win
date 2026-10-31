@echo off
setlocal enabledelayedexpansion
title OpsCore Pro — Enterprise Installer Builder
cd /d "%~dp0"
cls

echo =========================================================================
echo   [OpsCore Pro] ENTERPRISE INSTALLER BUILDER (INNO SETUP 7)
echo   Maximum LZMA2 Ultra64 Solid Compression - Full Windows 7/10/11 Support
echo =========================================================================
echo.

:: 1. Add Flutter to PATH if not already present
where flutter >nul 2>&1
if errorlevel 1 (
    if exist "C:\flutter\bin\flutter.bat" (
        set "PATH=C:\flutter\bin;%PATH%"
    )
)

:: 2. Locate Inno Setup Compiler
set "ISCC_PATH="
if exist "C:\Program Files\Inno Setup 7\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files\Inno Setup 7\ISCC.exe"
) else if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files\Inno Setup 6\ISCC.exe"
)

if "%ISCC_PATH%"=="" (
    echo [ERROR] Inno Setup compiler (ISCC.exe) was not found on this system!
    echo Please install Inno Setup 7 from: https://jrsoftware.org/isdl.php
    echo.
    pause
    exit /b 1
)

echo [1/3] Found Inno Setup Compiler: "%ISCC_PATH%"
echo.

:: 3. Check / Build Flutter Release Binaries
echo [2/3] Compiling Flutter Windows Release build...
if "%1"=="--skip-flutter" (
    if exist "build\windows\x64\runner\Release\opscore_pro.exe" (
        echo [SKIP] Skipping Flutter build (--skip-flutter passed). Using existing binary.
    ) else (
        echo [ERROR] --skip-flutter passed but release binary does not exist!
        pause
        exit /b 1
    )
) else (
    echo Compiling Flutter Windows release binaries (this may take 1-2 minutes)...
    call flutter build windows --release
    if errorlevel 1 (
        echo [ERROR] Flutter Windows release build failed!
        pause
        exit /b 1
    )
)
echo.

:: 4. Compile Inno Setup Installer with Ultra LZMA2 Compression
echo [3/3] Compiling installer with maximum LZMA2 solid compression...
echo (Compressing Flutter binaries, WhatsApp Engine, and Master Admin Web Console...)
echo Please wait 30-60 seconds for ultra-compression to complete...
echo.

"%ISCC_PATH%" "installer_setup.iss"

if errorlevel 1 (
    echo.
    echo [ERROR] Inno Setup compilation failed!
    pause
    exit /b 1
)

echo.
echo =========================================================================
echo   [SUCCESS] INSTALLER COMPILED SUCCESSFULLY!
echo =========================================================================
echo   Output File: build\installer\OpsCore_Pro_Windows_Setup_v2.0.0.exe
echo.
if exist "build\installer\OpsCore_Pro_Windows_Setup_v2.0.0.exe" (
    copy /y "build\installer\OpsCore_Pro_Windows_Setup_v2.0.0.exe" "%~dp0OpsCore_Pro_Windows_Setup_v2.0.0.exe" >nul
    echo   Copied to Project Root: OpsCore_Pro_Windows_Setup_v2.0.0.exe
)
echo.
explorer "%~dp0build\installer"
echo Done! You can now distribute this single setup file to clients.
echo.
pause
