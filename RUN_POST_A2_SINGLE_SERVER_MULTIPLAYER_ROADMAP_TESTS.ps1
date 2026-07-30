param([string]$GodotPath = "")
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportRoot = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportRoot "post-a2-single-server-multiplayer-roadmap-summary.json"
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
function Resolve-Godot([string]$Requested) {
    $Candidates=@(); if($Requested){$Candidates+=$Requested}; if($env:GODOT_BIN){$Candidates+=$env:GODOT_BIN}
    foreach($Name in @("godot.windows.editor.double.x86_64.console.exe","godot4","godot")){ $C=Get-Command $Name -ErrorAction SilentlyContinue; if($C){$Candidates+=$C.Source} }
    $Candidates += @("C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe","C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe")
    $Found=$Candidates|Where-Object{$_ -and (Test-Path $_)}|Select-Object -Unique|Select-Object -First 1
    if(-not $Found){throw "Double-precision Godot was not found."}; return (Resolve-Path $Found).Path
}
$Godot=Resolve-Godot $GodotPath
$Tests=@("res://tests/runtime/test_a2_networked_gameplay_architecture.gd","res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd")
$Summary=[ordered]@{schema="planet_simulator.post_a2_single_server_multiplayer_roadmap_summary.v1";checkpoint="v16.9.5-roadmap-single-server-multiplayer-first";build_id="post-a2-single-server-multiplayer-first";decision="FULL_SINGLE_SERVER_MULTIPLAYER_FIRST";started_at_utc=[DateTime]::UtcNow.ToString("o");finished_at_utc=$null;godot=$Godot;project_root=$ProjectRoot;declared_test_count=$Tests.Count;passed=$false;steps=@()}
function Save-Summary {$Summary.finished_at_utc=[DateTime]::UtcNow.ToString("o");[IO.File]::WriteAllText($ReportPath,($Summary|ConvertTo-Json -Depth 8)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))}
function Run-Step([string]$Name,[string]$Target,[string[]]$Arguments){
    $Started=[DateTime]::UtcNow
    $Captured=@()
    $PreviousErrorActionPreference=$ErrorActionPreference
    $NativePreference=Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference=if($null -ne $NativePreference){$NativePreference.Value}else{$null}
    try {
        $ErrorActionPreference="Continue"
        if($null -ne $NativePreference){Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false}
        & $Godot @Arguments 2>&1|Tee-Object -Variable Captured|ForEach-Object{Write-Host $_}
        $RawExitCode=$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference=$PreviousErrorActionPreference
        if($null -ne $NativePreference){Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference}
    }
    $OutputText=($Captured|Out-String)
    [IO.File]::WriteAllText((Join-Path $ReportRoot "post-a2-$Name.log"),$OutputText,(New-Object Text.UTF8Encoding($false)))
    $HasFailureMarker=$OutputText -match '(?m): FAIL(?:\s|\()'
    $Code=if($RawExitCode -ne 0){$RawExitCode}elseif($HasFailureMarker){1}else{0}
    $Summary.steps += [ordered]@{name=$Name;target=$Target;exit_code=$Code;duration_seconds=[Math]::Round(([DateTime]::UtcNow-$Started).TotalSeconds,3);passed=($Code-eq 0)}
    if($Code -ne 0){Save-Summary;throw "$Name failed"}
}
try {Run-Step "editor_import" "res://" @("--headless","--editor","--path",$ProjectRoot,"--quit");foreach($T in $Tests){Run-Step ([IO.Path]::GetFileNameWithoutExtension($T)) $T @("--headless","--path",$ProjectRoot,"--script",$T)};$Summary.passed=$true;Save-Summary;Write-Host "Post-A2 single-server multiplayer roadmap: PASS" -ForegroundColor Green;Write-Host "Report: $ReportPath"} catch {$Summary.passed=$false;Save-Summary;throw}
