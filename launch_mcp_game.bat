@echo off
setlocal
for %%I in ("%~dp0.") do set "PROJECT_ROOT=%%~fI"
start "" "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe" --path "%PROJECT_ROOT%"
endlocal
