@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\START_CHAR1.ps1" %*
if errorlevel 1 (
  echo.
  echo CHAR1 preview could not start. Review the error above.
  pause
  exit /b 1
)
exit /b 0
