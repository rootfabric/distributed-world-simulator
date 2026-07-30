# Checkpoint v16.10.3 — M4 Canonical Shared Gameplay

- Base: `v16.10.2-runtime-m3-dedicated-graphical-multiplayer`.
- Decision: `CANONICAL_SHARED_GAMEPLAY_OVER_ENET`.
- Status: `candidate`.

## Evidence

- contracts: `26/26 PASS`;
- graphical ENet process: one dedicated server plus two simultaneous X11 clients, `22 assertions PASS`;
- focused M4 profile: `9/9 scripts`, `745 assertions PASS`;
- full network/runtime regression: `53/53 PASS`;
- full world regression: `96/96 PASS`;
- server/client A/client B item checksum convergence;
- no ObjectDB/resource leak markers in graphical client logs.

## Delivery fix1

- PowerShell focused runner uses `$TestHome` instead of the read-only automatic `$HOME` variable;
- network and world summary checkpoints identify M4 rather than M3;
- evidence counts are synchronized with the independently verified run.

## Remaining

M5 retains full UI-driven graphical acceptance. M6 retains persistence/crash recovery.
