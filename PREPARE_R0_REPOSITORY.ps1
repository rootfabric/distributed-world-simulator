$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $ProjectRoot
try {
    if (-not (Test-Path ".git")) {
        throw "The .git directory was not found. Run this script from a working project copy."
    }

    $Git = Get-Command "git" -ErrorAction SilentlyContinue
    if ($null -eq $Git) {
        throw "Git was not found in PATH."
    }

    Write-Host "Removing generated Godot directories from the Git index..."
    & $Git.Source rm -r -f --cached --ignore-unmatch -- .godot .import
    if ($LASTEXITCODE -ne 0) {
        throw "Could not remove .godot/.import from the Git index."
    }

    Write-Host "Renormalizing tracked text files using .gitattributes..."
    & $Git.Source add --renormalize -- .
    if ($LASTEXITCODE -ne 0) {
        throw "git add --renormalize failed."
    }

    $R0Paths = @(
        ".gitattributes",
        ".gitignore",
        "PREPARE_R0_REPOSITORY.ps1",
        "PROJECT_MANIFEST.txt",
        "README_RU.md",
        "RUN_WORLD_REGRESSION_TESTS.ps1",
        "docs/README_RU.md",
        "docs/checkpoints/2026-07-26_R0_STABILIZATION_CHECKPOINT_RU.md",
        "docs/architecture/MULTI_WORLD_SIMULATOR_CORE_RU.md",
        "docs/plans/NEXT_ITERATIONS_RU.md",
        "docs/plans/ROADMAP_RU.md",
        "scripts/app/lunar_app.gd",
        "scripts/app/simulator_app.gd",
        "scripts/ui/planetary_overlay.gd",
        "tests/core/test_double_precision_contract.gd",
        "tests/core/test_double_precision_contract.gd.uid",
        "tests/runtime/test_world_switch_during_generation.gd",
        "tests/runtime/test_world_switch_during_generation.gd.uid",
        "tests/unit/test_jetpack_controller.gd.uid"
    )
    $ExistingR0Paths = @($R0Paths | Where-Object { Test-Path $_ })
    if ($ExistingR0Paths.Count -gt 0) {
        & $Git.Source add -- $ExistingR0Paths
        if ($LASTEXITCODE -ne 0) {
            throw "Could not add R0 files to the Git index."
        }
    }

    Write-Host "R0 repository preparation completed. Review the staged changes:"
    & $Git.Source status --short
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed."
    }

    Write-Host "Generated .godot files are now ignored. Commit the staged deletion and normalization together with the R0 patch."
}
finally {
    Pop-Location
}
