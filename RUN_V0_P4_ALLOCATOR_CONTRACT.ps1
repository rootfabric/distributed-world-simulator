[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p4-allocator"
$ImportLog = Join-Path $ArtifactRoot "import.log"
$TestLog = Join-Path $ArtifactRoot "allocator.log"
$ExpectedSummary = "V0-P4 deterministic allocator: PASS ("

if (-not (Test-Path -LiteralPath $GodotExe)) { throw "Godot executable not found: $GodotExe" }
if (-not (Test-Path -LiteralPath $ProjectFile)) { throw "Godot project file not found: $ProjectFile" }

$ActualHead = (& git -C $ProjectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $ActualHead -notmatch '^[0-9a-fA-F]{40}$') { throw "Unable to resolve exact V0-P4 HEAD." }
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $ActualHead.ToLowerInvariant() -ne $ExpectedHead.Trim().ToLowerInvariant()) {
    throw "V0-P4 allocator exact-head mismatch. Expected $ExpectedHead, got $ActualHead"
}
if (git -C $ProjectRoot status --porcelain) { throw "V0-P4 allocator gate requires a clean tracked checkout." }

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
$ProjectHashBefore = (Get-FileHash -Path $ProjectFile -Algorithm SHA256).Hash
$FatalPatterns = @("SCRIPT ERROR:", "Parse Error:", "Compile Error:", "Failed to load script", "Resource file not found: res://")

& $GodotExe --headless --editor --path $ProjectRoot --log-file $ImportLog --import
if ($LASTEXITCODE -ne 0) { Get-Content $ImportLog -Tail 180 -ErrorAction SilentlyContinue; throw "V0-P4 allocator import failed." }

& $GodotExe --headless --path $ProjectRoot --log-file $TestLog --script res://tests/construction/test_v0_p4_deterministic_server_allocator.gd
if ($LASTEXITCODE -ne 0) { Get-Content $TestLog -Tail 220 -ErrorAction SilentlyContinue; throw "V0-P4 deterministic allocator contract is RED." }

foreach ($LogPath in @($ImportLog, $TestLog)) {
    foreach ($Pattern in $FatalPatterns) {
        if (Select-String -Path $LogPath -SimpleMatch $Pattern -Quiet) {
            Get-Content $LogPath -Tail 220 -ErrorAction SilentlyContinue
            throw "V0-P4 allocator gate contains fatal marker: $Pattern"
        }
    }
}
if (-not (Select-String -Path $TestLog -SimpleMatch $ExpectedSummary -Quiet)) {
    Get-Content $TestLog -Tail 220 -ErrorAction SilentlyContinue
    throw "V0-P4 allocator contract did not emit required PASS summary."
}
$ProjectHashAfter = (Get-FileHash -Path $ProjectFile -Algorithm SHA256).Hash
if ($ProjectHashAfter -ne $ProjectHashBefore) { throw "V0-P4 allocator gate mutated project.godot." }
if (git -C $ProjectRoot status --porcelain) { git -C $ProjectRoot status --short; throw "V0-P4 allocator gate changed tracked checkout state." }

Write-Host "V0-P4 deterministic allocator GREEN on exact HEAD $ActualHead" -ForegroundColor Green
