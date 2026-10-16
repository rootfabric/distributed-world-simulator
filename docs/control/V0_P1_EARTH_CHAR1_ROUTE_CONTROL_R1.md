# V0-P1 route baseline repair — control only

**Subject:** exact stacked NET-SMOOTH1 R3C3 R1 implementation PR #772, parent `bb39396fe838a297a60555cdbcafb3aa3af42578`.

**Observed independent Windows result:** R3C3 real Godot geometry parity **PASS 68/68**, Earth M3 spectator **PASS 24/24**, pinned Godot double + cold import PASS. The third inherited test `test_v0_p1_earth_wiring.gd` fails one unrelated catalog routing assertion: it compares to an old P3 script path while this **stacked** product Earth catalog points to CHAR1.

**Source provenance:** `config/worlds/catalog.json` Earth runtime = `res://scripts/app/earth_char1_avatar_app.gd`; its exact `extends` = P3 ResourceMining; P3 exactly extends P1 Modern Inventory; P1 Modern Inventory exactly extends P1. The accepted **main** still routes Earth directly through P3, so this change is **not** a general rewrite of the main control baseline.

**Repair:** one exact expected stacked CHAR1 route instead of expected P3, plus seven new stricter Godot assertions for route instantiation, exact inheritance and inherited canonical P1/M3 interfaces. Added a Python source contract and a separate exact Windows control job. No product code, schema, authority, generator, RNG, M6, terrain or network modified.

**Hard gates:** fresh source PASS; pinned exact Windows Godot double `test_v0_p1_earth_wiring.gd` now PASS including stronger assertions; R3C3 staged geometry parity and Earth M3 regression must remain PASS. A missing/altered route is FAIL, not a waived test.

**Separation:** This is control-plane branch stacked **on** PR #772. Merge is human-only and blocked on control + product acceptance. Historical main P3 route is untouched.

**Status:** CONTROL_REPAIR_CANDIDATE / EXACT_WINDOWS_PENDING / NO_MERGE.
