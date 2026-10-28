# ECO ARCH2 A14.7 R1 — real native Windows GUI/GPU soak.
# Run in signed-in interactive desktop, NOT a Session 0 service.
[CmdletBinding()]
param(
  [string]$Godot = "",
  [int]$Ticks = 2,
  [string]$EvidenceRoot = "a147-evidence",
  [switch]$AllowSoftware,
  [switch]$SkipImport
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($Godot)) { $Godot = $env:CONFIGURED_GODOT }
if ([string]::IsNullOrWhiteSpace($Godot)) { $Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe' }
if (-not (Test-Path -LiteralPath $Godot)) { throw "A147_GODOT_BINARY_MISSING $Godot" }
$sha = (Get-FileHash -LiteralPath $Godot -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') {
  throw "A147_GODOT_SHA256_MISMATCH $sha"
}
if ($Ticks -lt 1 -or $Ticks -gt 4) { throw "A147_TICKS_OUT_OF_RANGE $Ticks" }
$project = (Get-Location).Path
$evidence = Join-Path $project $EvidenceRoot
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$meta = @{
  godot_sha256 = $sha
  godot_path = $Godot
  product_head = (& git rev-parse HEAD).Trim()
  product_tree = (& git rev-parse "HEAD^{tree}").Trim()
  started_utc = (Get-Date).ToUniversalTime().ToString("o")
  os = [Environment]::OSVersion.VersionString
  user_interactive = [Environment]::UserInteractive
  sizes = @(4,32,96,256)
}
$meta | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $evidence "a147-win-identity.json") -Encoding utf8
if (-not [Environment]::UserInteractive) {
  throw "A147_GUI_BLOCKED_NO_INTERACTIVE_DESKTOP: use the signed-in Windows user session"
}
if (-not $SkipImport) {
  & $Godot --headless --editor --path . --import *> (Join-Path $evidence "cold-import.txt")
  if ($LASTEXITCODE -ne 0) { throw "A147_COLD_IMPORT_FAIL" }
}
$seconds = @{4=65;32=110;96=190;256=380}
$results = @()
foreach ($n in @(4,32,96,256)) {
  $stdout = Join-Path $evidence "gui-$n.stdout.log"
  $stderr = Join-Path $evidence "gui-$n.stderr.log"
  $relative = "res://$EvidenceRoot/a147-$n.json"
  $argv = @('--path', '.', '--script', 'res://validation/ecology/evo_arch2_a14_7/a147_gui_soak.gd',
    '--', '--a147-gui', '--a147-population', "$n",
    '--a147-ticks', "$Ticks", '--a147-seconds', "$($seconds[$n])",
    '--a147-output', $relative)
  if ($AllowSoftware) { $argv += '--a147-allow-software' }
  Write-Host "A147_R1_GUI_PROCESS_BEGIN population=$n native_window=true"
  $started = Get-Date
  $proc = Start-Process -FilePath $Godot -ArgumentList $argv -PassThru -WorkingDirectory $project -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  $peak = [int64]0
  $seenChildren = [System.Collections.Generic.HashSet[int]]::new()
  while (-not $proc.HasExited) {
    try {
      $proc.Refresh()
      if (-not $proc.HasExited) { $peak = [Math]::Max($peak, [int64]$proc.PeakWorkingSet64) }
      # Console wrappers may hide the real renderer in a subprocess.
      $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $($proc.Id)" -ErrorAction SilentlyContinue)
      foreach ($child in $children) {
        $seenChildren.Add([int]$child.ProcessId) | Out-Null
        try {
          $cp = Get-Process -Id ([int]$child.ProcessId) -ErrorAction Stop
          $peak = [Math]::Max($peak, [int64]$cp.PeakWorkingSet64)
        } catch {}
      }
    } catch { Write-Host "A147_RSS_PROBE_WARNING population=$n $($_.Exception.Message)" }
    Start-Sleep -Seconds 1
  }
  $proc.WaitForExit()
  $exit = [int64]$proc.ExitCode
  $hex = '0x{0:X8}' -f ([uint32]($exit -band [int64]0xffffffff))
  $duration = ((Get-Date) - $started).TotalSeconds
  $native = @{
    population = $n
    native_exit_signed = $exit
    native_exit_hex = $hex
    elapsed_s = $duration
    peak_observed_process_tree_working_set_bytes = $peak
    observed_child_process_ids = @($seenChildren)
    process_tree_sampling_note = 'one-second sampled, not guaranteed exhaustive'
  }
  $native | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $evidence "gui-$n.native.json") -Encoding utf8
  Write-Host "A147_R1_NATIVE_EXIT population=$n signed=$exit hex=$hex sampled_rss=$peak seconds=$duration"
  if (Test-Path $stdout) { Get-Content $stdout }
  if (Test-Path $stderr) { Get-Content $stderr }
  if ($exit -ne 0) { throw "A147_R1_GUI_NATIVE_FAIL population=$n signed=$exit hex=$hex" }
  if (-not (Select-String -Path $stdout -Pattern '^A147_R1_NATIVE_GUI PASS$' -Quiet)) {
    throw "A147_R1_GUI_MARKER_MISSING population=$n"
  }
  $path = Join-Path $evidence "a147-$n.json"
  if (-not (Test-Path $path)) { throw "A147_R1_GUI_JSON_MISSING population=$n" }
  $results += $path
}
$validator = Join-Path $project 'validation/ecology/evo_arch2_a14_7/validate_gui_evidence.py'
$python = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } elseif (Get-Command py -ErrorAction SilentlyContinue) { 'py' } else { throw 'A147_PYTHON_MISSING' }
if ($AllowSoftware) {
  & $python $validator @results --allow-software
} else {
  & $python $validator @results
}
if ($LASTEXITCODE -ne 0) { throw "A147_R1_STRICT_EVIDENCE_INVALID" }
Write-Host "A147_R1_WINDOWS_GUI_EVIDENCE_COMPLETE"
