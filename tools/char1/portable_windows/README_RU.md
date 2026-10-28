# CHAR1 — Windows portable GUI test (tracked launcher source)

This directory is the source of the portable launcher. Do not manually edit a
generated ZIP and expect those fixes to survive the next build.

Build the test ZIP from the tracked Git HEAD:

    python tools/char1/build_windows_test.py --output CHAR1_Realistic_Avatar_Windows_Test.zip

The packer archives the *exact committed Git tree* to project/ and copies this
portable_windows/ directory as the package launcher. It writes BUILD_INFO.json
with exact HEAD/TREE and SHA256 of all critical source and the launcher.

On Windows:
1. Extract to a new directory; do not overwrite existing custom files.
2. Run START_CHAR1.cmd for the interactive Quaternius preview.
3. Run VERIFY_CHAR1.cmd for canonical Godot, source integrity, tests and screenshots.

Godot 4.7.1 double and official Quaternius CC0 assets are not bundled. The
launcher reuses a previously installed source directory or original ZIP files.
Real Quaternius animation is required in graphical verification; silent
FALLBACK success is forbidden.

C/V toggles camera. First-person intentionally hides only the local preview
world model; third-person shows it. This package does NOT change M3/SM1 state.

PowerShell 5.1 fast exit fix (PS51_EXITCODE_HANDLE_R2):
Invoke-CHAR1Command touches $process.Handle directly after Start-Process
-PassThru and before WaitForExit. This avoids the null ExitCode failure observed
when a cold import exits quickly. The actual process exit code and parse-error
markers remain hard gates.

Always verify this change on PowerShell 5.1 with the fast-exit regression and
the actual Godot cold import. Windows GUI acceptance is separate.
