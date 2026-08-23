@echo off
title OpsCore Pro - WhatsApp Engine Server
color 0A
echo ===================================================
echo     OpsCore Pro - WhatsApp Engine Background Server
echo ===================================================
echo.

cd /d "%~dp0"

if exist "whatsapp_engine\node.exe" (
    set "NODE_BIN=%~dp0whatsapp_engine\node.exe"
) else if exist "node.exe" (
    set "NODE_BIN=%~dp0node.exe"
) else (
    set "NODE_BIN=node"
)

if exist "whatsapp_engine\bot_engine.js" (
    set "ENGINE_SCRIPT=%~dp0whatsapp_engine\bot_engine.js"
    set "ENGINE_DIR=%~dp0whatsapp_engine"
) else if exist "bot_engine.js" (
    set "ENGINE_SCRIPT=%~dp0bot_engine.js"
    set "ENGINE_DIR=%~dp0"
) else (
    echo [ERROR] bot_engine.js not found!
    pause
    exit /b 1
)

echo [OK] Using Node Runtime: %NODE_BIN%
echo [OK] Using Engine Script: %ENGINE_SCRIPT%
echo.
echo Starting WhatsApp Bot Engine on http://127.0.0.1:4000 ...
echo (Do not close this window if you want WhatsApp Engine to keep running)
echo.

cd /d "%ENGINE_DIR%"
"%NODE_BIN%" "%ENGINE_SCRIPT%"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Engine stopped with error code %ERRORLEVEL%
    pause
)
