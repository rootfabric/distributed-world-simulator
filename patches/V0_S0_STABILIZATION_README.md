# V0-S0 Stabilization

Incremental stabilization delivery for the current local V0-S1 working tree after Inventory Convergence, reliable movement recovery, and M5 mouse-capture fix.

Scope:
- surface-locked camera yaw/pitch without accumulated roll;
- explicit GAMEPLAY / INVENTORY / SPECTATOR input ownership;
- restore NX4 predicted movement and remove reliable MOVE fallback;
- map realtime ENet transport to UNRELIABLE_ORDERED while retaining application sequencing;
- submit explicit zero movement intent when gameplay loses input ownership;
- debug HUD starts collapsed and F1 hides/shows it;
- suppress false M3 connect-timeout after an actual disconnect.

Canonical patch SHA-256: `aa7e6160e91982d6f85015037dd98dd5f1de7b18b1f59d6a517493f688087c7f`.

The delivery is intentionally incremental because the user's current tested V0 tree contains uncommitted convergence patches that are not represented as source commits on this branch.
