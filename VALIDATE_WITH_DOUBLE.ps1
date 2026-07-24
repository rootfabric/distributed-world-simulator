$ErrorActionPreference = "Stop"

$ProjectPath = $PSScriptRoot
$Candidates = @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.exe",
    (Join-Path $ProjectPath "godot.windows.editor.double.x86_64.exe")
)

$GodotExe = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $GodotExe) {
    $GodotExe = Read-Host "Введите полный путь к godot.windows.editor.double.x86_64.exe"
}

if (-not (Test-Path $GodotExe)) {
    throw "Файл Godot не найден: $GodotExe"
}

& $GodotExe --headless --editor --path $ProjectPath --quit

if ($LASTEXITCODE -ne 0) {
    throw "Godot завершил проверку с кодом $LASTEXITCODE"
}

Write-Host "Проект загружен headless-редактором без фатальной ошибки." -ForegroundColor Green
