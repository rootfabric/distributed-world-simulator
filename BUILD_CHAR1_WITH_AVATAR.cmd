@echo off
setlocal
cd /d "%~dp0"
where pwsh.exe >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoProfile -File "%~dp0BUILD_CHAR1_WITH_AVATAR.ps1" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD_CHAR1_WITH_AVATAR.ps1" %*
)
if errorlevel 1 (
    echo.
    echo CHAR1 WITH AVATAR build FAILED. See the error above and artifacts\char1-with-avatar\ logs.
    pause
    exit /b 1
)
echo.
echo CHAR1 package created. Press any key to close.
pause >nul
exit /b 0
