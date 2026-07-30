param([string]$GodotPath = "")

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw "GodotPath is required"
}

$Tests = @(
    @{
        Path = "res://tests/runtime/test_m4_networked_playground_extension.gd"
        World = ""
    },
    @{
        Path = "res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd"
        World = ""
    },
    @{
        Path = "res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd"
        World = ""
    },
    @{
        Path = "res://tests/runtime/test_m3_graphical_multiplayer_processes.gd"
        World = "playground"
    }
)

$ProfileRoot = Join-Path $Root "artifacts/test-results/m4-networked-playground-$PID"
New-Item -ItemType Directory -Force -Path $ProfileRoot | Out-Null
$OriginalAppData = $env:APPDATA
$OriginalLocalAppData = $env:LOCALAPPDATA
$OriginalProcessWorld = $env:PLANET_M3_PROCESS_WORLD

try {
    foreach ($Test in $Tests) {
        $Name = [IO.Path]::GetFileNameWithoutExtension($Test.Path)
        $TestProfile = Join-Path $ProfileRoot $Name
        $Data = Join-Path $TestProfile "appdata"
        $LocalData = Join-Path $TestProfile "localappdata"
        New-Item -ItemType Directory -Force -Path $Data, $LocalData | Out-Null
        $env:APPDATA = $Data
        $env:LOCALAPPDATA = $LocalData
        if ([string]::IsNullOrWhiteSpace($Test.World)) {
            Remove-Item Env:PLANET_M3_PROCESS_WORLD -ErrorAction SilentlyContinue
        }
        else {
            $env:PLANET_M3_PROCESS_WORLD = $Test.World
        }

        $OldPreference = $ErrorActionPreference
        $NativePreference = $null
        try {
            if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
                $NativePreference = $PSNativeCommandUseErrorActionPreference
                $PSNativeCommandUseErrorActionPreference = $false
            }
            $ErrorActionPreference = "Continue"
            $Output = & $GodotPath --headless --path $Root --script $Test.Path 2>&1
            $ExitCode = $LASTEXITCODE
            $Output | ForEach-Object { Write-Host $_ }
        }
        finally {
            $ErrorActionPreference = $OldPreference
            if ($null -ne $NativePreference) {
                $PSNativeCommandUseErrorActionPreference = $NativePreference
            }
        }
        if (
            $ExitCode -ne 0 -or
            (($Output -join "`n") -match "(: FAIL|SCRIPT ERROR:|Parse Error:|Compile Error:)")
        ) {
            throw "M4 networked playground test failed: $($Test.Path)"
        }
    }
}
finally {
    $env:APPDATA = $OriginalAppData
    $env:LOCALAPPDATA = $OriginalLocalAppData
    if ([string]::IsNullOrEmpty($OriginalProcessWorld)) {
        Remove-Item Env:PLANET_M3_PROCESS_WORLD -ErrorAction SilentlyContinue
    }
    else {
        $env:PLANET_M3_PROCESS_WORLD = $OriginalProcessWorld
    }
}

Write-Host "M4 networked playground extension: PASS ($($Tests.Count)/$($Tests.Count))"
