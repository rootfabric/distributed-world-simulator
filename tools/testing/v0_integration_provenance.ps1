function Resolve-V0IntegrationProvenance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$CandidateHead,

        [Parameter(Mandatory = $true)]
        [string]$IntegrationRef,

        [string]$DeclaredIntegrationBase = ""
    )

    if ($CandidateHead -notmatch "^[0-9a-f]{40}$") {
        throw "Candidate HEAD must be an exact lowercase 40-character commit SHA."
    }

    $IntegrationRefHead = (& git -C $Root rev-parse --verify "$IntegrationRef^{commit}" 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $IntegrationRefHead -notmatch "^[0-9a-f]{40}$") {
        throw "Could not resolve integration ref to an exact commit: $IntegrationRef"
    }
    $IntegrationRefHead = $IntegrationRefHead.ToLowerInvariant()

    $ComputedMergeBase = (& git -C $Root merge-base $CandidateHead $IntegrationRefHead 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $ComputedMergeBase -notmatch "^[0-9a-f]{40}$") {
        throw "Could not compute merge-base for candidate $CandidateHead and integration $IntegrationRefHead."
    }
    $ComputedMergeBase = $ComputedMergeBase.ToLowerInvariant()

    $Declared = $DeclaredIntegrationBase.Trim().ToLowerInvariant()
    if ($Declared) {
        if ($Declared -notmatch "^[0-9a-f]{40}$") {
            throw "IntegrationBase must be an exact lowercase 40-character commit SHA."
        }
        & git -C $Root cat-file -e "$Declared^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "IntegrationBase commit does not exist in the checkout: $Declared"
        }
        if ($Declared -ne $ComputedMergeBase) {
            throw "IntegrationBase assertion mismatch: declared $Declared, computed merge-base $ComputedMergeBase."
        }
    }

    return [pscustomobject][ordered]@{
        integration_ref = $IntegrationRef
        integration_ref_head = $IntegrationRefHead
        candidate_head = $CandidateHead
        computed_merge_base = $ComputedMergeBase
        declared_integration_base = $Declared
        provenance_result = "PASS"
    }
}
