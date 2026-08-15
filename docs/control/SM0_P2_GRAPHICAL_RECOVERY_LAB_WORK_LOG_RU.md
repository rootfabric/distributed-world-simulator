# SM0-P2 — Graphical Recovery Lab work log

Статус: **IMPLEMENTED / WINDOWS GRAPHICAL RUNTIME VERIFICATION PENDING**.

Scope: branch-local experimental presentation/test surface. Никакой production/global/V0-S1 acceptance этим документом не объявляется.

## База

H4.3 exact runtime-tested SHA:

`1126ec53ddf036389d2d11aa5211147b5cd7e320`

H4.3 runtime evidence commit:

`db87444a06c24541ba3a10b3825918e9bd7c6d67`

H4.3 work log closed commit:

`0a007d428614e1e8084ff5df1cdbb1e1ed6c7bb2`

## P2 implementation dynamics

### Design

Commit:

`2b5b02acc54fad68b9de846e1029ab36bdcd9d40`

File:

`docs/control/SM0_P2_GRAPHICAL_RECOVERY_LAB_DESIGN_RU.md`

Defined presentation-only projection of the already-tested H4.3 same-transfer recovery chain.

### Graphical recovery projection

Commit:

`f62bb441befb7d06700b3d33ff45785712eb98ea`

File:

`scripts/runtime/seamless/sm0/sm0_graphical_recovery_lab.gd`

The scene inherits the P1 graphical handoff lab, therefore manual movement still uses `sm0_manual_client_node.gd` and authoritative client view state. Added presentation-only recovery HUD with:

- server A/B process state;
- durable phase and generation;
- source/target;
- exact transfer id;
- chain/outage status;
- large total-outage banner;
- world beacons for A/B online/recovering/down state.

The presentation JSON is read only by the graphical scene. Authority processes never consume it.

### Scene

Commit:

`8bd01db98f7699622acd6008653ef8b9c256f296`

File:

`scenes/testing/sm0_graphical_recovery_lab.tscn`

### Graphical recovery supervisor

Commit:

`62f3a3c2cd9dcd74a680f700bc6d4358f21de4e7`

File:

`RUN_V0_SM0_GRAPHICAL_RECOVERY_LAB.ps1`

Supervisor responsibilities:

- exact custom-double Godot version check for console and graphical binaries;
- clean-worktree guard and generated `.uid` cleanup;
- compile checks for P1/P2 graphical client plus H4.3 recovery-chain fault/server process;
- headless smoke of P2 scene;
- two authority startup using existing `h4-recovery-of-recovery-same-transfer-v1` and one recovery root;
- graphical manual client startup;
- durable H4.3 marker observation;
- visible pause at PREPARED / COMMITTED / ACTIVE;
- simultaneous A+B process kill with maximum 500 ms kill-request gap;
- visible zero-authority hold;
- target/source restore from same durable recovery files;
- exact transfer-id continuity checks COMMITTED and ACTIVE;
- terminal crossing count wait;
- automatic opposite-direction next chain until user closes window;
- `-Stop` / `-Restart` session lifecycle;
- optional `-RequireRecoveries N` local verification gate.

No production recovery node or canonical protocol contract is changed by P2.

## Static workflow

Project Control run #611 for commit `62f3a3c2cd9dcd74a680f700bc6d4358f21de4e7`: **SUCCESS**.

This is static/control evidence only. It does not replace Windows graphical Godot verification.

## Next gate

Run P2 on exact branch candidate and require at least one completed graphical recovery chain. Visually confirm:

- initial A/WEST ownership;
- one exact T visible through PREPARED, COMMITTED, ACTIVE;
- both A/B beacons become DOWN on each of three outages;
- same graphical client survives;
- after terminal restore base HUD switches to B/EAST with one completed handoff and unchanged player identity;
- optional reverse B -> A chain behaves symmetrically.

After successful Windows run, record separate P2 graphical runtime evidence. Until then status remains implementation candidate.
