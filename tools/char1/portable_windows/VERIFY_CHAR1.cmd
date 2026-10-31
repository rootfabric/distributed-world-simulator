@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\VERIFY_CHAR1.ps1" %*
if errorlevel 1 (
  echo.
  echo CHAR1 test FAILED. Logs are in evidence\.
  pause
  exit /b 1
)
echo.
echo Test completed. Press any key to close this console.
pause > nul
exit /b 0
