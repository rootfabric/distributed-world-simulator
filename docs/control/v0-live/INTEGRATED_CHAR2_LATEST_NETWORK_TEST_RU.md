# Latest-network + CHAR2 — real two-client Windows test candidate

Branch: `integration/char2-current-main-playtest-r1` (intentionally NOT main).
Source parent: main `8b504a2d854e891baa4688c6a8f25e9dc8c956d7`, which includes N3 R0a PR #871.
Imported: visual-only CHAR1/CHAR2 sources from `feature/char2-network-avatar-product-r1` @ `0558ff19eee17d99023ef89508050c51c9e1e7bf`.

## Scope / safety
This is a **test candidate**, not a production build, verified multi-host N3, or permission to merge main. The tree keeps all network/wire, prediction, M3/SM1, V0 USER1, persistence, construction, and gameplay authority from current main; it changes the Earth world catalog to provider-backed `earth_char1_avatar_app.gd` and adds CHAR1/CHAR2 code/assets integration. Quaternius CC0 source files are **not stored in git**; the packager pulls them from the local Windows host and fails closed if the model or animation library are unavailable.

## Build complete portable Windows ZIP
Open PowerShell 7 on canonical Windows machine, create a **fresh detached worktree** on exact HEAD of this integration branch. Godot console must be the original 4.7.1 Double custom build at:
`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe` (SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`).

Set `DWS_QUATERNIUS_ASSET_ROOT` to a folder with real `base_characters/` and `animation_library/` containing `Superhero_Male_FullBody.gltf` and `UAL1_Standard.glb`; then, from integration worktree:

```powershell
$env:DWS_QUATERNIUS_ASSET_ROOT='C:\replace-with-real-assets\quaternius'
.\BUILD_CHAR1_WITH_AVATAR.ps1 -GodotConsole 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe' -AssetSource $env:DWS_QUATERNIUS_ASSET_ROOT
```

The output is `artifacts/char1-with-avatar/CHAR1_REALISTIC_WITH_AVATAR_<HEAD>_Windows.zip`. This package bundles exact tracked project source, Windows Godot GUI+console binaries and real CC0 Base Characters/UAL1 assets. It checks the Quaternius file URIs, cold imports, and runs strict CHAR1/CHAR2 tests. No missing-asset procedural fallback counts as a successful release.

## Test the real game
Extract ZIP to a **new writable folder**. Within `CHAR1_REALISTIC_WITH_AVATAR/` execute `START_TWO_CLIENTS_CHAR1.cmd`. That script starts **one** dedicated ENet server and two real GUI clients `a`/`b` on UDP 24580; it refuses to reuse a bound port and never kills unrelated processes. Alternatively `START_NETWORK_CHAR1.cmd` launches the product shell: Host player `a` (slot `char2-smoke`) and Join player `b` via 127.0.0.1:24580. Make sure the old server on 24580 is stopped **through its original launcher** before this test. Do **not** erase persistence slots or bulk-kill Godot.

Both windows should say CONNECTED and show the **other** player's full human-shaped Quaternius. Press V or F7 to switch first-/third-person; in first person hide *only your own body*. Use F1 console `character.remote.status`, `character.avatar.status`, `character.camera.status`; remote should have provider `avatar/quaternius`, mode `QUATERNIUS_RETARGET` or `QUATERNIUS_EMBEDDED`, and `legacy_capsule_visible=false`. Walk/run/idle animations should follow the other player. USER1 mining, inventory, seam and reconnect remain on canonical main gameplay source.

If a capsule appears, check embedded BUILD_INFO.json product_head, Quaternius resource file existence and logs; do not claim the latest test is successful. If a GUI client has missing remote player despite network presence, capture `character.remote.status` from both clients and `network.jitter.snapshot`.

## CI and acceptance
`.github/workflows/char2-latest-network-playtest-windows.yml` builds exact source and, if the self-hosted Windows runner has real CC0 assets, creates the complete portable ZIP artifact. A source-only archive is **not** the finished game. Real 2-window graphics require **manual acceptance**; native headless CI cannot substitute. Preserve historical red Project Control MVP6 findings as a separate task.
