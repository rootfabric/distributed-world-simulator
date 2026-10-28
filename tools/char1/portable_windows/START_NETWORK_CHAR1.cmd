@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\START_NETWORK_CHAR1.ps1" %*
if errorlevel 1 (
  echo.
  echo CHAR2 Host/Join launcher could not start. Review error and evidence\.
  pause
  exit /b 1
)
exit /b 0
