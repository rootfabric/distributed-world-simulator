@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\START_TWO_CLIENTS_CHAR1.ps1" -GodotConsole "%~dp0runtime\godot.windows.editor.double.x86_64.console.exe" %*
if errorlevel 1 (
  echo Launch failed. See evidence logs.
  pause
  exit /b 1
)
