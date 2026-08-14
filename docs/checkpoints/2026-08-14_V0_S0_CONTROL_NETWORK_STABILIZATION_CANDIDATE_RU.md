# V0-S0 — CONTROL / NETWORK STABILIZATION CANDIDATE

**Date:** 2026-08-14  
**Status:** IMPLEMENTED CANDIDATE / REAL WINDOWS 2-CLIENT VALIDATION REQUIRED  
**Delivery branch:** `agent/v0-s1-inventory-convergence`

## Scope implemented

1. Surface-locked camera: explicit surface-relative yaw/pitch, pitch clamp, no accumulated roll basis in network surface mode.
2. Explicit V0 input ownership states: `GAMEPLAY`, `INVENTORY`, `SPECTATOR`. The Earth MVP owns global mouse capture; inventory UI no longer does.
3. NX4 predicted movement restored. The temporary reliable per-step `MOVE` fallback is removed from the V0 path.
4. Camera-relative movement uses the existing shared movement kernel and correct Earth-to-server yaw sign.
5. Realtime logical `UNRELIABLE_SEQUENCED` traffic is physically mapped to Godot ENet `UNRELIABLE_ORDERED`, while application sequence suppression remains active.
6. Leaving gameplay input ownership submits an explicit zero movement intent, preventing stale held movement from continuing while inventory/spectator takes control.
7. Debug HUD starts collapsed, supports expand/collapse, and F1 hide/show.
8. A real server disconnect no longer falls through into a false `M3_CLIENT_CONNECT_TIMEOUT`.

## Authority / ownership invariants

No new movement authority is introduced. The client predicts presentation only; the dedicated server remains canonical through the existing fixed-tick `FixedTickInputBuffer -> NetworkedGameplayService.simulate_fixed_movement_tick` path.

No new Item Graph, Construction, terrain, or persistence truth is introduced.

## Delivery

Fail-closed installer:

`APPLY_V0_S0_STABILIZATION.ps1`

Compressed payload:

`patches/v0-s0-stabilize-controls-network.patch.gz.b64`

Canonical uncompressed patch SHA-256:

`aa7e6160e91982d6f85015037dd98dd5f1de7b18b1f59d6a517493f688087c7f`

The installer first verifies the payload checksum and `git apply --check`; on mismatch it changes nothing.

## Pre-publication checks

- patch hunk syntax / stats: PASS;
- synthetic current-tree `git apply --check`: PASS;
- `git diff --check` expectation: PASS;
- Godot 4.7.1 double camera math stress (10,000 yaw/pitch updates): PASS;
- surface-view basis remains orthonormal and roll-free in the test;
- camera heading to shared server movement-yaw sign mapping verified.

## Required real-runtime acceptance

Run `RUN_V0_MVP.ps1 -Clients 2 -Restart` on the existing Windows double build and verify:

- mouse circles cannot invert/roll the surface camera;
- F1 hides/restores HUD and the HUD starts collapsed;
- Tab switches cleanly between gameplay mouse capture and inventory cursor;
- W follows camera heading;
- local movement is continuous through NX4 prediction rather than 0.3-0.5 m reliable MOVE steps;
- releasing W produces a prompt stop;
- client `input_batches_sent` grows;
- server receives/applies fixed-tick movement inputs;
- movement no longer grows `pending_operation_timer_count` as reliable MOVE did;
- two clients remain convergent;
- no false connect-timeout is emitted after an actual server disconnect.

Only after this real-runtime acceptance should V0-S0 be promoted from CANDIDATE to PASS and the roadmap continue to V0-I1P/V0-I2.
