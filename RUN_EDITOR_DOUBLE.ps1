$ErrorActionPreference = "Stop"

$ProjectPath = $PSScriptRoot
$Candidates = @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.exe",
    (Join-Path $ProjectPath "godot.windows.editor.double.x86_64.exe")
)

$GodotExe = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $GodotExe) {
    Write-Host "Double-precision Godot не найден в стандартных путях." -ForegroundColor Yellow
    $GodotExe = Read-Host "Введите полный путь к godot.windows.editor.double.x86_64.exe"
}

if (-not (Test-Path $GodotExe)) {
    throw "Файл Godot не найден: $GodotExe"
}

Write-Host "Запуск: $GodotExe" -ForegroundColor Green
Write-Host "Проект: $ProjectPath" -ForegroundColor Green

Start-Process -FilePath $GodotExe -ArgumentList @("--editor", "--path", $ProjectPath)
