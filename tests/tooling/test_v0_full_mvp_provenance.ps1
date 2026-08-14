$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $Root "tools/testing/v0_integration_provenance.ps1")

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-v0-provenance-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

try {
    & git -C $TempRoot init -q
    if ($LASTEXITCODE -ne 0) { throw "git init failed" }
    & git -C $TempRoot config user.email "v0-review@example.invalid"
    & git -C $TempRoot config user.name "V0 Review Fixture"

    "base" | Set-Content -Encoding ASCII (Join-Path $TempRoot "state.txt")
    & git -C $TempRoot add state.txt
    & git -C $TempRoot commit -q -m "fixture base"
    $Base = (& git -C $TempRoot rev-parse HEAD | Out-String).Trim()

    & git -C $TempRoot switch -q -c integration
    "integration" | Add-Content -Encoding ASCII (Join-Path $TempRoot "state.txt")
    & git -C $TempRoot commit -q -am "integration advance"
    $IntegrationHead = (& git -C $TempRoot rev-parse HEAD | Out-String).Trim()

    & git -C $TempRoot switch -q -c candidate $Base
    "candidate" | Set-Content -Encoding ASCII (Join-Path $TempRoot "candidate.txt")
    & git -C $TempRoot add candidate.txt
    & git -C $TempRoot commit -q -m "candidate advance"
    $CandidateHead = (& git -C $TempRoot rev-parse HEAD | Out-String).Trim()

    $Correct = Resolve-V0IntegrationProvenance `
        -Root $TempRoot `
        -CandidateHead $CandidateHead `
        -IntegrationRef "refs/heads/integration" `
        -DeclaredIntegrationBase $Base
    if ($Correct.provenance_result -ne "PASS" -or $Correct.computed_merge_base -ne $Base) {
        throw "Correct merge-base assertion was not accepted."
    }

    $Rejected = $false
    try {
        Resolve-V0IntegrationProvenance `
            -Root $TempRoot `
            -CandidateHead $CandidateHead `
            -IntegrationRef "refs/heads/integration" `
            -DeclaredIntegrationBase $IntegrationHead | Out-Null
    }
    catch {
        $Rejected = $_.Exception.Message -like "IntegrationBase assertion mismatch:*"
    }
    if (-not $Rejected) {
        throw "E: existing but incorrect IntegrationBase was not rejected."
    }

    Write-Host "PASS: E: existing but incorrect IntegrationBase is rejected"
    Write-Host "V0 full MVP provenance contracts: 2 assertions, 0 failures"
    exit 0
}
finally {
    Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue
}
