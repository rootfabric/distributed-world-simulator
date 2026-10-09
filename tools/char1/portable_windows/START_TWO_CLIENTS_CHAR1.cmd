@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\START_TWO_CLIENTS_CHAR1.ps1" %*
if errorlevel 1 (
  echo.
  echo CHAR2 server/two-client launch FAILED. See errors and evidence logs.
  pause
  exit /b 1
)
exit /b 0
