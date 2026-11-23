@echo off
rem SPDX-License-Identifier: MIT
rem Copyright (c) 2026 Manufacturing Automation, LLC
rem Double-click launcher for Install-CX9240.ps1
set /p ADDR=Controller address (for example 192.168.1.247):
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CX9240.ps1" -Address %ADDR%
echo.
pause
