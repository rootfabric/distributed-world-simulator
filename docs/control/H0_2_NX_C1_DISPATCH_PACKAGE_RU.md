# H0.2 / NX.C1 — Dispatch Preparation Package

**Preparation status:** `H0_2_NX_C1_DISPATCH_PACKAGE_READY`  
**Lane type:** docs/control preparation only  
**Preparation base:** `main @ 4a42c2fb6befb386f5c3eb48d9ba070745e25bbb`, registry generation `77`, architecture `GLOBAL-P0-2026-08-10-R2`  
**Observed active runtime:** `H0.1 R7 / C22`, PR `#88`, state `VERIFYING`  
**Observed R3 candidate:** `control/global-p0-r3-refresh-r1 @ fbc563c80eb55e960356f23e91bfb8f436bbff9a`, PR `#85`, not canonical  
**Runtime authorization:** `false`

Этот документ готовит H0.2, но не создаёт Project Epoch, Work Order, runtime branch и не dispatch-ит worker. Все SHA/registry/revision для реального H0.2 должны быть заново взяты после `R3 canonical + post-R3 PC0`.

## 1. Dispatch gate

H0.2 runtime разрешён только после полной цепочки:

```text
H0_1_PASS
→ HUMAN C22_RUNTIME_MERGE
→ post-C22 standard + directional PC0
→ C22 MAIN_INTEGRATED
→ GLOBAL-P0 R3 final current-main refresh
→ HUMAN GLOBAL_ARCHITECTURE_PROMOTION
→ post-R3 standard + directional PC0
→ fresh exact main/registry/architecture snapshot
→ H0.2 Project Epoch + NX.C1 Work Order
→ HIGH pre-build review on exact pre-dispatch head
→ Director dispatch of exactly one runtime worker
```

До этого документа разрешено только быть preparation evidence.

## 2. Design Brief

### Problem statement

Проект имеет accepted NX0–NX6 evidence и legacy M7 two-client/owner-authority evidence, но production convergence нельзя строить из старой FIX-lineage. Нужен второй реальный HIGH-risk H-process pilot, который воспроизводимо собирает минимальную комфортную network capability из fresh post-R3 main, не создаёт второй gameplay truth и заканчивается bounded `NX SOURCE_ACCEPTED`.

### Current behavior

Canonical network architecture уже разделяет server gameplay truth, fixed-tick simulation, client prediction/reconciliation, remote interpolation и optimistic item presentation. NX.C0 preparation разрешает использовать legacy M7 только как evidence. Текущий R3 ownership candidate закрепляет `NETWORK_REPLICATION_POLICY → NX`, но отдельно сохраняет `AUTHORITY_FOUNDATION → AUTHORITY`, `ITEM_IDENTITY_AND_GRAPH → ITEM`, `IDENTITY_SESSION_FABRIC → IAM`, `PERSISTENCE_DURABILITY → R3_M0_MW` и `DERIVED_PRESENTATION → DOMAIN_ADAPTERS`.

### Desired behavior

Fresh NX.C1 должен доказать один компактный end-to-end runtime slice:

```text
local input
→ immediate owner prediction
→ server fixed-tick authoritative simulation
→ authoritative snapshot
→ reconciliation/replay
→ remote snapshot interpolation

pickup/drop intent
→ optimistic local presentation
→ authoritative Item outcome
→ confirm OR deterministic rollback

reconnect
→ transport/session may change
→ canonical gameplay identity preserved
→ stale authority epoch rejected
```

### Selected design

H0.2 использует **owner-predicted local player + server-authoritative canonical simulation**. Legacy M7 `OWNER_AUTHORITATIVE_VALIDATED` рассматривается только как evidence о responsiveness, validation pitfalls, reconnect и two-client composition; он **не является обязательной capability H0.2** и не даёт клиенту canonical transform ownership.

Это намеренно уже старого NX.C0 текста. Если реализация потребует реального `OWNER_AUTHORITATIVE_VALIDATED` canonical movement mode, это scope expansion: STOP, новая Design Brief/risk review и отдельное решение, а не скрытый перенос FIX ladder.

### Alternatives rejected

- merge/rebase старой M7 FIX-lineage;
- cherry-pick NX4/NX5/NX6 или M7 как authorization;
- client-owned canonical player transform;
- новый identity/session registry внутри NX;
- новый Item Graph/Inventory authority path;
- изменение protocol manifest ради удобства без доказанной необходимости;
- расширение в NX7/NX8/NX9.

### Non-goals

- physics authority profiles для произвольных world objects;
- interest management / replication budget;
- server zones, shard split/merge, server-to-server authority handoff;
- async persistence redesign;
- IAM/AUTHZ/RF/TF/WB implementation;
- NET-min implementation;
- V0 runtime implementation.

## 3. Risk classification

**Risk = HIGH.**

Причины: realtime network runtime, authoritative movement boundary, recovery/reconnect, optimistic item rollback, public behavior across client/server processes.

Обязательные роли:

```text
IMPLEMENTER
REVIEWER
VERIFIER
DIRECTOR
```

Risk автоматически повышается до `CRITICAL` и работа останавливается до новой авторизации, если появляется хотя бы одно из:

```text
architecture ownership change
new global identity/session foundation
AUTHORITY foundation semantics change
security/authentication/authorization change
cross-server authority
new global registry/manager
```

Изменение network public protocol/manifest остаётся минимум `HIGH`, но является critical watched dependency для существующих consumers и требует отдельного directional revalidation gate.

## 4. Minimal NX.C1 scope boundary

В scope входят только:

1. owner-predicted local player;
2. server-authoritative fixed-tick simulation;
3. client prediction/reconciliation;
4. remote interpolation;
5. pickup/drop optimistic presentation;
6. rollback on rejection;
7. authority epoch correctness;
8. reconnect identity preservation.

Не входят NX7/NX8/NX9 и любые новые world/network foundations.

## 5. Work Order materialization template

Реальный Work Order не создаётся сейчас. После post-R3 gate Director материализует один schema-valid `distributed_world_simulator.work_order.v1` по следующим правилам.

| Field | Exact materialization rule |
|---|---|
| `work_order_id` | Новый H0.2/NX.C1 id, уникальный внутри fresh Project Epoch. Не переиспользовать NX.C0/M7/FIX ids. |
| `project_epoch` | Новый epoch, созданный только после exact post-R3 `origin/main` reread. |
| `program` | `NX` |
| `goal_checkpoint` | `NX_SOURCE_ACCEPTED`; одновременно Director должен зафиксировать, как machine control представляет harness verdict `H0_2_PASS`. |
| `state` | `PLANNED` до exact-head pre-build review; затем только Director переводит в `DISPATCHED`. |
| `work_order_type` | `IMPLEMENTATION` |
| `base_sha` | Exact canonical `origin/main` SHA после R3 promotion и post-R3 PC0. |
| `branch` | Новая fresh NX.C1 runtime branch от `base_sha`; не `feature/nx-m7-owner-authority-convergence` и не legacy FIX branch. |
| `scope` | Minimal owner-predicted/server-authoritative realtime slice + item optimistic rollback + reconnect/epoch proof. |
| `risk_class` | `HIGH` unless a CRITICAL trigger appears. |
| `review_required` | `true` |
| `required_review_roles` | `IMPLEMENTER`, `REVIEWER`, `VERIFIER`, `DIRECTOR` |
| `evidence_map_required` | `true` |
| `repair_context_required` | `true` after any MEDIUM+ `FIX_REQUIRED`. |
| `human_approval_required_for` | `NX_RUNTIME_MERGE`; H0.2 itself stops before merge. |

### Intent

```text
Converge only the minimum realtime network capability needed for responsive two-client player/item gameplay from fresh R3-canonical main while preserving server/domain truth and proving the H-process on a second HIGH-risk subsystem.
```

### Initial allowed_paths set

Actual Work Order should begin with this bounded set and may only shrink during pre-build review. Any expansion requires Director amendment and re-review before mutation.

```text
scripts/network/authority/movement_authority_profile.gd
scripts/runtime/networked_gameplay/networked_gameplay_service_owner_movement.gd
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_owner_movement.gd
scripts/network/prediction/client_prediction_reconciler.gd
scripts/network/interpolation/remote_snapshot_interpolator.gd
scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd
scripts/runtime/networked_gameplay/services/player_movement_service.gd

tests/network/test_nx_owner_movement_authority.gd
tests/network/test_nx_owner_item_projection_rollback.gd
tests/network/test_nx_render_physics_separation.gd
tests/network/test_nx_client_tick_robustness.gd
tests/network/test_nx_c1_reconnect_authority_epoch.gd
tests/runtime/test_nx_c1_two_graphical_clients.gd
validation/nx-m7-owner-authority-convergence-validation.json
RUN_NX_C1_OWNER_AUTHORITY_CONVERGENCE_TESTS.ps1
RUN_NX_C1_OWNER_AUTHORITY_CONVERGENCE_TESTS.sh
```

Rules for the reusable NX3/NX4/NX5 files above:

- first preference is reuse unchanged from canonical main;
- mutation is allowed only when an exact integration defect proves it necessary;
- generic base runtime files are not automatically writable merely because they are watched.

### Forbidden paths / surfaces

```text
config/control/project-program-registry.v1.json
config/control/architecture-ownership.v1.json
config/architecture/global-program-roadmap.v1.json
config/control/harness/** canonical policy/schema files
scripts/network/contracts/network_protocol_manifest.gd
scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd
scripts/runtime/networked_gameplay/ch9/ch9_5_persistent_dedicated_server_runtime.gd
scripts/items/** canonical Item truth
scripts/characters/** Character/equipment truth
Construction/Matter/G production truth
persistence/save-format truth
IAM/AUTHZ/RF/TF/SD/MAT/WT/WQ/LIFE/WB/COMPAT/SEC foundations
```

Если реальная post-R3 tree использует `scripts/network/observability/network_protocol_manifest.gd` как canonical manifest path, он также forbidden by default. Любая необходимость его менять требует Work Order amendment + dependency revalidation before mutation.

## 6. Canonical owners and dependency map

| Surface | Canonical owner | NX.C1 rule |
|---|---|---|
| Development authorization/checkpoints | `MAIN/HARNESS` | consume only |
| Network replication/realtime policy | `NX` | primary owner within bounded scope |
| Canonical player/gameplay authority | server/domain authority | NX transports/predicts; client does not become truth owner |
| Authority leases/epochs/routing | `AUTHORITY` | consume epoch contract; do not redefine |
| Account/principal/session identity | `IAM` after R3 | consume/observe only; no NX identity registry |
| Item identity/graph/mutation | `ITEM` | server-authoritative; NX only optimistic presentation/rollback |
| Persistence durability | `R3_M0_MW` | no persistence redesign |
| Derived remote/local presentation | `DOMAIN_ADAPTERS` | NX may feed presentation state; no second physics writer |
| Character/equipment composition | `CH` | watched dependency; no owner-side mutation |
| Construction consumers of network | `T/CONSTRUCTION` | directional revalidation if watched paths hit |
| World work budgeting | `WB` | no runtime/development scheduler ownership |

### Watched paths

Carry forward and refresh from the NX.C0 passport after R3:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd
scripts/runtime/networked_gameplay/networked_gameplay_service.gd
scripts/network/prediction/**
scripts/network/simulation/**
scripts/runtime/networked_gameplay/m4/**
scripts/runtime/networked_gameplay/ch9/ch9_5_persistent_dedicated_server_runtime.gd
canonical network protocol manifest
scripts/items/**
scripts/characters/**
```

Critical watched:

```text
canonical network protocol manifest
scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd
scripts/runtime/networked_gameplay/ch9/ch9_5_persistent_dedicated_server_runtime.gd
R3 AUTHORITY/IAM contract surfaces if they become runtime-materialized before H0.2
```

Current preparation evidence already shows a blocking directional `CH → NX` watched hit on Character equipment/lab files. Fresh H0.2 must recompute this from post-R3 refs; it cannot inherit a stale green assumption.

## 7. Entry gates

All must be true before branch creation/dispatch:

```text
H0_1_PASS recorded
C22 runtime merge explicitly human-authorized and complete
post-C22 standard PC0 acceptable
post-C22 directional PC0 acceptable
C22 MAIN_INTEGRATED recorded
GLOBAL-P0 R3 promoted by human gate
post-R3 standard PC0 acceptable
post-R3 directional PC0 acceptable
exact canonical main SHA known
exact registry generation known
exact canonical architecture revision is R3
fresh NX.C1 branch not yet created from any older base
old FIX/M7 lineage classified evidence-only
HIGH Design Brief reviewed
allowed_paths exact and bounded
forbidden ownership exact
current directional producer→NX hits enumerated
one runtime worker slot available
machine representation of H0_2_PASS resolved
```

## 8. Acceptance matrix

| Proof ID | Proof case | PASS condition |
|---|---|---|
| `NX_C1_OWNER_PREDICTED_LOCAL` | Immediate owner response | Real InputMap input affects local predicted state within one render frame; no wait for RTT; canonical server record remains unchanged until authoritative simulation. |
| `NX_C1_SERVER_AUTH_FIXED_TICK` | Server authority | Movement is committed only by server fixed-tick path; packet arrival/client frame delta cannot become simulation delta. |
| `NX_C1_RECONCILIATION` | Prediction/replay | Inject bounded client/server divergence; authoritative snapshot removes acknowledged history, resets baseline, replays unacknowledged input exactly once and converges without duplicate jump/input. |
| `NX_C1_HARD_CORRECTION` | Recovery from large divergence | >2 m or explicit invalid state produces hard correction/recovery marker, converges and leaves no stale prediction history. |
| `NX_C1_REMOTE_INTERPOLATION` | Remote player | Client B renders player A from snapshot buffer/interpolation timeline; bounded extrapolation; teleport/recovery does not smear across invalid state. |
| `NX_C1_SINGLE_WRITER` | Physics/presentation separation | `_process`/render path cannot mutate `CharacterBody3D` canonical transform/velocity; physics/server path is sole physics writer and presentation modifies only visual proxy/offset. |
| `NX_C1_PICKUP_ACCEPT` | Optimistic pickup | Local pending presentation appears immediately; server accept resolves to one canonical item state; pending count returns to zero. |
| `NX_C1_PICKUP_REJECT` | Pickup rollback | Rejection restores presentation deterministically at same canonical revision; no duplicate/lost item; no unresolved prediction. |
| `NX_C1_DROP_ACCEPT` | Predicted drop | Provisional local presentation is correlated with authoritative result and resolves to exactly one canonical item identity. |
| `NX_C1_DROP_REJECT` | Drop rollback | Rejection removes provisional presentation and restores inventory projection with no revision corruption. |
| `NX_C1_TWO_GRAPHICAL_CLIENTS_LOCAL` | Two real clients | Dedicated server + two graphical clients: both can move; each local owner is responsive; each remote is smooth; pickup/drop remains server-authoritative; no process error. |
| `NX_C1_IMPAIRED_AVERAGE` | Impaired network | Deterministic `AVERAGE_BROADBAND` profile: 80 ms RTT, 10 ms jitter, 0.5% loss; minimum 5-minute movement + pickup/drop stress; no canonical corruption, duplicate item, unresolved prediction or authority leak. |
| `NX_C1_RECONNECT_IDENTITY` | Reconnect | Disconnect/reconnect may change transport/session binding, but canonical gameplay player/entity identity remains the same according to existing canonical contract; no new NX identity registry. |
| `NX_C1_AUTHORITY_EPOCH` | Stale epoch rejection | Commands/state from prior authority epoch are rejected after epoch advance; current epoch succeeds; stale peer cannot regain write effect through replay/reorder. |
| `NX_C1_CLIENT_TICK_FUZZ` | Tick robustness | Required only if client tick/sequence scheduling is modified: huge forward gap, duplicate, backward, wrap and reorder are bounded/rejected/rebased without multi-second implicit scheduling. |
| `NX_C1_WORLD_CORE_REGRESSION` | Project regression | Exact Windows Godot 4.7.1 double `RUN_WORLD_REGRESSION_TESTS.ps1` PASS on exact runtime/evidence head. |
| `NX_C1_TESTED_HEAD_FRESH` | Freshness | runtime/focused/full tested heads resolve to the exact reviewed evidence head for every changed runtime surface. |
| `NX_C1_EVIDENCE_MAP` | Review package | Evidence Map complete under canonical schema, with entry points/callers/callees/siblings and remaining risks. |
| `NX_C1_REVIEWER` | Independent review | Reviewer verdict `PASS` on exact evidence/runtime head. |
| `NX_C1_VERIFIER` | Independent verification | Verifier independently re-runs required checks and confirms exact head/provenance. |
| `NX_C1_DIRECTIONAL` | Dependency validation | Standard PC0 has no blocking RED; directional PC0 has no unresolved critical hit; every watched hit has targeted revalidation evidence. |
| `NX_C1_RECOVERY` | Git-only resume | Status/Plan/Resume reconstruct the H0.2 state from Git without chat and recover the current checkpoint proposal state. |

### Acceptance result

Only when all applicable rows PASS:

```text
H0_2_PASS
NX SOURCE_ACCEPTED
```

Then STOP. `NX SOURCE_ACCEPTED != NX MAIN_INTEGRATED`.

## 9. Evidence Map skeleton

Materialize one `distributed_world_simulator.harness_evidence_map.v1` with these exact semantic obligations:

```text
work_order_id              = exact H0.2 NX.C1 Work Order
program                    = NX
checkpoint                 = NX_SOURCE_ACCEPTED
risk_class                 = HIGH unless reclassified CRITICAL
evidence_head_sha          = exact reviewed runtime/evidence head
intent                     = minimal owner-predicted/server-authoritative convergence
changed_surfaces           = exact production diff only
canonical_owner            = NX for replication policy; list consumed owners separately in narrative
entry_points               = graphical client, dedicated server, gameplay service, item optimistic projection
callers/callees            = exact reread from final code
sibling_surfaces_checked   = NX3 fixed tick, NX4 prediction, NX5 interpolation, NX6 item interaction, M3 process composition, CH/T consumers
canonical_truth_changed    = false for identity/item/construction/persistence; player canonical movement still server-owned
architecture_ownership_changed = false
focused_validation         = PASS
full_regression            = PASS
pc0                        = NON_RED
directional_pc0            = NON_RED
production_diff_summary    = bounded NX.C1 production surface only
remaining_risks            = explicit residual latency/visual limitations, not hidden ownership changes
required_fixes             = empty at acceptance
rank_up_moves               = empty unless reviewer identifies justified simplification
review_verdict             = PASS
```

## 10. Reviewer / Verifier focus

Reviewer должен отдельно проверить:

- нет ли фактического client-owned canonical movement под названием prediction;
- нет ли второго physics writer из render/process path;
- не импортирован ли legacy FIX inheritance ladder;
- Item rollback меняет только projection до server result;
- authority epoch не смешан с session/peer identity;
- reconnect не создаёт новый global identity concept;
- remote interpolation не пишет physics truth;
- allowed_paths не расширились молча;
- production diff не трогает R3 foundations/registry/persistence/Construction/Item truth;
- exact-head runtime evidence fresh.

Verifier должен независимо подтвердить process-level two-client, impaired-network, reconnect/epoch, exact-Windows regression, Evidence Map integrity и Git-only recovery.

## 11. V0-facing capability map

### Что H0.2/NX.C1 обязан дать будущему NET-min / V0-S3

```text
stable session/gameplay connection lifecycle already present in canonical runtime
local player predicted presentation with server authority
canonical authoritative player state observation
remote player interpolation/presentation
server-authoritative pickup/drop result
optimistic pending + rejection rollback observation
authority epoch/reconnect correctness
network telemetry needed to explain corrections/rejections
process-proven dedicated server + two graphical clients
```

NET-min после `NX MAIN_INTEGRATED` должен быть thin composition adapter поверх этих capabilities, а не private protocol/state owner.

### Что не нужно для NET-min / V0-S3 и остаётся NX7+

```text
arbitrary rigid-body physics authority profiles
owner-authoritative canonical object movement
predicted spawn for broad physics object classes
interest grid / relevance tiers
per-client replication budget
large-scale dormancy/dirty replication
server zone handoff / distributed authority routing
async persistence hardening
production 12h/24h soak policy
```

`OWNER_AUTHORITATIVE_VALIDATED` как общий physics authority profile относится к будущему расширению и не требуется для первого V0 two-client player/item scenario.

## 12. NX integration rule for V0

```text
H0_2_PASS
NX SOURCE_ACCEPTED
        ↓
H0.3 may become next harness checkpoint
```

Но network truth для V0 проходит отдельно:

```text
NX SOURCE_ACCEPTED
        ↓
HUMAN NX_RUNTIME_MERGE / integration gate
        ↓
post-NX standard + directional PC0
        ↓
NX MAIN_INTEGRATED
        ↓
NET-min
        ↓
V0-S3
```

Запрещено cherry-pick'ать NX truth напрямую в V0.

## 13. Stop conditions

Немедленный STOP без продолжения runtime implementation при любом событии:

```text
R3 not canonical
post-R3 PC0 has blocking RED
main moves and Project Epoch becomes invalid
actual branch is not fresh from exact post-R3 main
attempt to use old FIX/M7 branch as authorization/base
scope expands into NX7/NX8/NX9
client becomes canonical player transform owner
protocol manifest change becomes necessary without amended review
Item/CH/Construction/Persistence canonical truth change becomes necessary
new identity/session/authority/global registry is proposed
CRITICAL directional hit remains unresolved
review head != runtime evidence head
runtime changes occur after review without re-review
focused/process/impaired/reconnect/world regression fails
Evidence Map incomplete
Reviewer FAIL or INSUFFICIENT_EVIDENCE
Verifier cannot reproduce evidence
H0.2 checkpoint machine representation is unresolved
NX SOURCE_ACCEPTED reached
```

Последняя строка означает остановку **до NX runtime merge**.

## 14. Control gap to resolve before real dispatch

Canonical `checkpoint-catalog.v1.json` сейчас содержит project checkpoint `NX_SOURCE_ACCEPTED`, но не отдельный machine checkpoint `H0_2_PASS`. Primary execution roadmap уже использует `H0.2 / NX.C1 → H0_2_PASS + NX SOURCE_ACCEPTED`.

До реального Work Order Director должен main-owned control decision-ом выбрать один вариант:

1. добавить отдельный harness checkpoint H0.2, который композирует `NX_SOURCE_ACCEPTED` и closed-loop predicates; или
2. формально объявить `H0_2_PASS` Director/harness verdict над существующим `NX_SOURCE_ACCEPTED` без второго checkpoint object.

Нельзя оставлять это только текстовым соглашением чата.

## 15. Final preparation verdict

```text
H0_2_NX_C1_DISPATCH_PACKAGE_READY

runtime_authorized = false
runtime_branch_created = false
runtime_code_changed = false
main_changed = false
active_H0_1_changed = false
NX7_NX8_NX9_started = false
NET_min_started = false

STOP_UNTIL = R3 canonical + post-R3 PC0
```
