# V0 Product Frontier — единая отправная точка развития

**Статус:** USER-VALIDATED PLAYABLE / MERGE-PREPARED PRODUCT FRONTIER  
**Дата фиксации:** 2026-08-15  
**Runtime-tested SHA:** `7f4177b32ce76191aecea60f2f8963c1b0ffd02e`  
**Validated branch:** `fix/v0-playable-merge-prep`  
**Immutable checkpoint:** `checkpoint/v0-playable-merge-ready-2026-08-15`  
**Continuation branch after integration:** `feature/v0-playable-product-frontier`  
**Merge-prep PR:** `#100`

> Это единственный product-development указатель для V0. Он не заменяет `main` как владельца global Project Control и не объявляет глобальный V0 acceptance.

## 1. Что зафиксировано

`7f4177b32ce76191aecea60f2f8963c1b0ffd02e` — текущая подтверждённая человеком рабочая V0-композиция после materialization и merge-prep hardening.

Она запускается из clean checkout обычным V0 launcher без recovery/sync patches и включает:

- procedural Earth runtime;
- dedicated server;
- два graphical clients;
- two-player join/ready flow;
- SERVER_PREDICTED / NX4 client prediction + reconciliation movement;
- surface-relative camera/input;
- remote-player presentation;
- F1 debug HUD toggle;
- M5 network inventory + Tab/input ownership;
- Construction MVP controls and authoritative Construction replication;
- Earth-fixed Construction presentation anchor;
- spectator toggle;
- clean Godot UID/import preflight;
- stable tracked `project.godot` during editor import;
- same-revision cross-channel snapshot ordering protection;
- single-owner BreakpointRuntimeBridge process isolation for multi-process V0 launch.

Observed Windows runtime evidence on the merge-prep line includes successful dedicated-server + clients A/B startup, clean cold/imported UID contracts, H3 multiplayer gameplay contract PASS, healthy joined clients with zero async rejections/pending blocking operations, and no remaining startup ERROR after the runtime bridge isolation fix was validated by the operator.

## 2. Нельзя потерять эту точку

The immutable recovery lineage remains historical evidence:

- `checkpoint/v0-playable-recovered-2026-08-15` -> recovery recipe;
- `checkpoint/v0-playable-materialized-2026-08-15` -> materialized source baseline `31e846698d6b319e083dc0e86a76025e2d7ed64e`.

The new immutable product checkpoint is:

```text
checkpoint/v0-playable-merge-ready-2026-08-15
    -> 7f4177b32ce76191aecea60f2f8963c1b0ffd02e
```

Do not develop on checkpoint branches.

After PR #100 is integrated into `feature/v0-playable-product-frontier`, every new V0 product branch MUST start from the exact current head of:

```text
feature/v0-playable-product-frontier
```

Never restart V0 product work from:

- `feature/v0-s1-networked-planetary-outpost-mvp`;
- `agent/v0-mvp-next-integration`;
- `agent/v0-s1-inventory-convergence`;
- `feature/v0-playable-mvp-recovery`;
- arbitrary `agent/v0-*` or old subsystem feature branches.

Those branches are evidence/capability donors only.

## 3. Capability-transfer rule

Old accepted branches MUST NOT be merged wholesale into V0 merely because they contain useful features.

Correct continuation:

```text
current V0 product frontier
        ↓
new bounded V0 capability branch
        ↓
identify exact donor capability
        ↓
port/reimplement only that capability against CURRENT interfaces
        ↓
focused tests
        ↓
server + A + B runtime gate
        ↓
reconnect/state gate when stateful
        ↓
merge back into V0 product frontier
```

Rules:

1. Current V0 authority/network/item/construction foundations win over historical donor code.
2. Do not import an old transport, authority, replica store, movement loop, Item Graph owner, persistence owner, Construction owner or project settings layer as a side effect of a feature transfer.
3. Prefer additive/new files and narrow adapters over replacing current V0 runtime files.
4. If a donor branch changes a current foundation, extract semantics and reimplement them on the current frontier instead of merging the old foundation.
5. Each transfer must leave the existing V0 smoke playable before adding the next capability.

## 4. Development order from this frontier

### V0-P0 — Frontier lock / merge completion

- integrate PR #100 into `feature/v0-playable-product-frontier`;
- verify the product-frontier head launches from clean checkout;
- preserve `checkpoint/v0-playable-merge-ready-2026-08-15` immutable;
- keep recovery scripts out of normal product startup.

### V0-P1 — World items + pickup/drop + external containers

Primary donor candidate:

```text
feature/v0-i2s-world-items-containers
875822dac3de6500761581ef2ec09984abb11436
```

Port its capability onto the current V0 frontier; do NOT merge its historical base.

Acceptance slice:

- server spawns canonical world item;
- A and B see the same item;
- A picks it up, B sees disappearance from world and canonical inventory change;
- item can be dropped back to Earth-fixed world space;
- external container can be opened/closed;
- transfer between inventory and external container works;
- stale/duplicate interaction is safe;
- disconnect/reconnect reconstructs the same canonical item/container state.

### V0-P2 — Reconnectable shared state as a hard gate

State that must reconstruct:

- player identity/session ownership;
- current authoritative transforms;
- Item Graph/inventory;
- world items;
- external containers;
- Construction state;
- Earth-fixed presentation projections.

Gate:

```text
A + B join
→ mutate inventory/world item/construction
→ disconnect A
→ B remains healthy
→ reconnect A
→ canonical fingerprints converge
```

### V0-P3 — Minimal resource/mining gameplay loop

Do NOT pull the full Matter World / terrain-deformation stack yet.

First implement object-level resource extraction using current server authority + Item Graph:

- one resource node/rock with canonical resource quantity;
- server-authoritative `resource.harvest` / `resource.mine` command;
- bounded depletion/rejection rules;
- mined output materializes as canonical item stack;
- result is visible to both clients;
- reconnect preserves depletion + produced items.

Historical MW/Matter branches are design/implementation donors, not merge bases.

### V0-P4 — Construction consumes real resources

Required flow:

```text
mine/pick up resource
→ inventory owns stack
→ build request validates recipe/cost
→ atomic resource consumption
→ Construction commit
→ both clients receive same result
```

Use existing Construction and Item Graph owners. Do not introduce a second inventory/economy truth.

### V0-P5 — Equipment/tool presentation

Primary donor evidence:

```text
feature/ch9-6-playable-network-equipment-lab
```

Transfer only the capability needed by the V0 loop:

- equipped mining/build tool;
- flashlight/equipment presentation where useful;
- remote client sees equipped state;
- authority remains server-owned through existing canonical Item Graph/equipment state.

### V0-P6 — Persistent shared outpost loop

```text
join
→ gather resources
→ move items through containers
→ build outpost
→ disconnect/reconnect
→ continue from same live state
```

Run at least five clean E2E repeats and then a 30-minute two-client soak.

### V0-P7 — Terrain/matter mutation

Only after V0-P6 is stable, start a bounded terrain interaction track. MW4/MW5/MW6 and later Matter branches are capability donors only.

First terrain slice:

- one bounded dig/deform operation;
- authoritative mutation;
- persistence;
- second-client replication;
- reconnect reconstruction;
- no unbounded global terrain streaming requirement.

### V0-P8 — Mobile construct / first ship

Only after persistent item/resource/construction state is routine.

Start with a tiny mobile construct:

- enter/exit;
- authority/ownership explicit;
- move/fly locally under server authority;
- inventory/container aboard;
- persist/reconnect;
- dock/land.

Use C6/mobile-construct and later Construction branches as semantic donors, not wholesale merge sources.

## 5. Immediate priority order

```text
0. integrate/lock current merge-ready frontier
1. world items + pickup/drop + containers
2. reconnect state regression
3. minimal resources/mining
4. construction resource costs
5. equipment/tool presentation
6. 5x E2E + 30 min soak
7. bounded terrain deformation
8. first mobile construct/ship
```

## 6. Regression contract for every subsequent V0 transfer

Every new V0 capability must preserve the previous baseline:

- clean checkout/preflight;
- no tracked project mutation from import;
- dedicated server starts;
- A + B join;
- camera-relative smooth local movement;
- remote movement remains visible;
- `async_rejections == 0` during healthy operation;
- `pending_blocking == 0` after operations settle;
- no persistent `last_error_code`;
- inventory opens/closes and retains input ownership rules;
- Construction remains authoritative and Earth-fixed;
- no `MULTIPLAYER_SAME_REVISION_MUTATION` on normal disconnect ordering;
- multi-process startup is log-clean for expected paths;
- `git status --short` remains clean after preflight/runtime.

When a new stateful capability is added, reconnect reconstruction for that capability becomes part of this permanent regression set.

## 7. Control boundary

This document defines the V0 PRODUCT continuation point only.

It does NOT:

- make `7f4177b3...` canonical `main`;
- merge PR #98/#99/#100;
- change registry generation 79;
- declare `PLAYABLE_MVP_BASELINE` globally accepted;
- bypass independent Reviewer/Verifier or main-owned Project Control.

`main` remains the global project-state owner. Until control integration catches up, this document is the durable product-development anchor and prevents future V0 work from restarting from stale historical branches.
