# WP-TOOLS1: focused tooling test entry (Windows).
# Runs the authoring CLI tests, scale fixture tests and the WP1.0 contract
# predecessor regression. Exit code is pytest's exit code.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# NOTE: test_library_contract.py::test_local_missing_symlink_and_corruption needs
# os.symlink, which requires admin/developer mode on Windows (WinError 1314).
# It is deselected here for that environmental reason only.
python -m pytest `
    tests/world_packs/wp_cli `
    tests/world_packs/scale_fixtures `
    tests/world_packs/test_library_contract.py `
    --deselect "tests/world_packs/test_library_contract.py::test_local_missing_symlink_and_corruption" `
    -q
exit $LASTEXITCODE
