param([string]$GodotPath = "")
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportRoot = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportRoot "m3-dedicated-graphical-multiplayer-summary.json"
$ProfileRoot = Join-Path $ReportRoot ("m3-runner-profile-{0}" -f $PID)
New-Item -ItemType Directory -Force -Path $ReportRoot,$ProfileRoot | Out-Null
function Resolve-Godot([string]$Requested) {
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Requested)) { $Candidates += $Requested }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
    $Candidates += @("C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe","C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe")
    foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe","godot4","godot")) { $Command=Get-Command $Name -ErrorAction SilentlyContinue; if ($null -ne $Command) {$Candidates += $Command.Source} }
    foreach ($Candidate in ($Candidates|Select-Object -Unique)) { if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) { return (Resolve-Path $Candidate).Path } }
    throw "Double-precision Godot was not found. Set GODOT_BIN or pass -GodotPath."
}
$Godot=Resolve-Godot $GodotPath
$Tests=@(
"res://tests/runtime/test_launch_options.gd","res://tests/runtime/test_h0_listen_host_contracts.gd","res://tests/runtime/test_h1_playable_listen_host_contracts.gd","res://tests/runtime/test_h1_playable_listen_host_integration.gd","res://tests/runtime/test_h2_player_ownership_contracts.gd","res://tests/runtime/test_h2_host_client_processes.gd","res://tests/runtime/test_h3_multiplayer_gameplay_contracts.gd","res://tests/runtime/test_h3_dedicated_multiplayer_processes.gd","res://tests/runtime/test_m1_networked_gameplay_contracts.gd","res://tests/runtime/test_m1_unified_networked_gameplay_service.gd","res://tests/runtime/test_m2_graphical_client_contracts.gd","res://tests/runtime/test_m2_dedicated_graphical_processes.gd","res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd","res://tests/runtime/test_m3_graphical_multiplayer_processes.gd","res://tests/network/test_t1_multi_peer_transport_contracts.gd","res://tests/network/test_t1_multi_peer_transport_processes.gd","res://tests/runtime/test_a2_networked_gameplay_architecture.gd","res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd")
$Summary=[ordered]@{schema="planet_simulator.m3_dedicated_graphical_multiplayer_summary.v1";checkpoint="v16.10.2-runtime-m3-dedicated-graphical-multiplayer";build_id="m3-dedicated-two-graphical-clients";decision="DEDICATED_PLUS_TWO_GRAPHICAL_CLIENTS";started_at_utc=[DateTime]::UtcNow.ToString("o");finished_at_utc=$null;godot=$Godot;project_root=$ProjectRoot;isolated_user_profile=$ProfileRoot;declared_test_count=$Tests.Count;passed=$false;steps=@()}
function Save-Summary {$Summary.finished_at_utc=[DateTime]::UtcNow.ToString("o");[IO.File]::WriteAllText($ReportPath,(($Summary|ConvertTo-Json -Depth 8)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))}
function Run-Step([string]$Name,[string]$Target,[string[]]$Arguments) {
    Write-Host "`n[$Name]" -ForegroundColor Cyan
    $StepRoot=Join-Path $ProfileRoot $Name; $Data=Join-Path $StepRoot "data"; $Config=Join-Path $StepRoot "config"; $Cache=Join-Path $StepRoot "cache"
    New-Item -ItemType Directory -Force -Path $StepRoot,$Data,$Config,$Cache|Out-Null
    $Names=@("APPDATA","LOCALAPPDATA","USERPROFILE","HOME","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME")
    $Old=@{}; foreach($N in $Names){$Old[$N]=[Environment]::GetEnvironmentVariable($N,"Process")}
    $env:APPDATA=$Data;$env:LOCALAPPDATA=$Data;$env:USERPROFILE=$StepRoot;$env:HOME=$StepRoot;$env:XDG_DATA_HOME=$Data;$env:XDG_CONFIG_HOME=$Config;$env:XDG_CACHE_HOME=$Cache
    $Started=[DateTime]::UtcNow;$Captured=@();$LogPath=Join-Path $ReportRoot "m3-$Name.log";$RawExitCode=1
    $PreviousErrorActionPreference=$ErrorActionPreference;$NativePreference=Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue;$PreviousNativePreference=if($null-ne$NativePreference){$NativePreference.Value}else{$null}
    try {$ErrorActionPreference="Continue";if($null-ne$NativePreference){Set-Variable PSNativeCommandUseErrorActionPreference $false};& $Godot @Arguments 2>&1|Tee-Object -Variable Captured|Tee-Object -FilePath $LogPath|ForEach-Object{Write-Host $_};$RawExitCode=$LASTEXITCODE}
    finally {$ErrorActionPreference=$PreviousErrorActionPreference;if($null-ne$NativePreference){Set-Variable PSNativeCommandUseErrorActionPreference $PreviousNativePreference};foreach($N in $Names){[Environment]::SetEnvironmentVariable($N,$Old[$N],"Process")}}
    $OutputText=($Captured|Out-String);$HasFailureMarker=$OutputText-match'(?m)(: FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)';$ExitCode=if($RawExitCode-ne0){$RawExitCode}elseif($HasFailureMarker){1}else{0}
    $Summary.steps += [ordered]@{name=$Name;target=$Target;exit_code=$ExitCode;duration_seconds=[Math]::Round(([DateTime]::UtcNow-$Started).TotalSeconds,3);passed=($ExitCode-eq0);log_path=$LogPath};Save-Summary
    if($ExitCode-ne0){throw "$Name failed with exit code $ExitCode"}
}
try {Run-Step "editor_import" "res://" @("--headless","--editor","--path",$ProjectRoot,"--quit");foreach($Test in $Tests){Run-Step ([IO.Path]::GetFileNameWithoutExtension($Test)) $Test @("--headless","--path",$ProjectRoot,"--script",$Test)};$Summary.passed=$true;Save-Summary;Write-Host "`nM3 dedicated graphical multiplayer: PASS" -ForegroundColor Green;Write-Host "Report: $ReportPath"}
catch {$Summary.passed=$false;Save-Summary;Write-Host $_ -ForegroundColor Red;exit 1}
