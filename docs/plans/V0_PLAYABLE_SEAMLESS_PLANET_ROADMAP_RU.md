# V0 PLAYABLE SEAMLESS PLANET — глобальная продуктовая дорожная карта

**Revision:** R3 / 2026-08-29  
**Primary purpose:** сфокусировать product critical path на первом полноценном playable seamless world milestone.

> Эта roadmap — human product-routing document. Canonical checkpoint eligibility, ownership и acceptance по-прежнему определяются `config/control/harness/v0-product-train-policy.v1.json` и остальным main-owned control plane.

## North Star checkpoint

# V0 PLAYABLE SEAMLESS PLANET

Это первый рубеж, после которого проект должен ощущаться не как набор инфраструктурных доказательств, а как ранняя persistent multiplayer game.

Acceptance scenario:

```text
1. Запустить dedicated server / Gateway / Authority A / Authority B.
2. Подключить два graphical client.
3. Оба игрока видят общий canonical world.
4. Игрок экипирует tool.
5. Добывает canonical resource.
6. Копает/изменяет bounded terrain.
7. Получает материал в canonical Item Graph.
8. Строит из canonical resources.
9. Второй клиент видит тот же результат.
10. Игрок пересекает A/B authority boundary без respawn/reconnect/loading.
11. Продолжает копать и строить после handoff.
12. Disconnect/reconnect восстанавливает тот же player/world state.
13. Server restart восстанавливает terrain + inventory + equipment + Construction.
14. Duplicate/stale operations не создают вторую canonical truth.
```

## Фаза A — persistent multiplayer foundation

**Статус: DONE / ACCEPTED foundation**

- P4 real-resource Construction — ACCEPTED;
- P5 equipment/tools — ACCEPTED;
- P6 persistent shared outpost — ACCEPTED;
- Edge Gateway Foundation — ACCEPTED;
- two-client persistence/reconnect/restart foundation существует.

Не открывать альтернативные Item Graph, Construction, persistence или Gateway owners.

## Фаза B — SM1 production seamless

**Статус: ACTIVE / feature-complete; B2-B5 closed; B6 Verifier current**

Уже реализовано до SM1.7.12:

- one-writer transfer;
- stable logical player/entity identity;
- monotonic authority epoch;
- Gateway route preservation;
- graphical A<->B;
- fault/replay cases;
- concurrent crossings;
- reconnect;
- Gateway restart;
- Authority recovery;
- canonical gameplay mutation continuity;
- repeated A<->B crossings under BAD_MOBILE/LAG_SPIKE network impairment.

Текущий exact implementation candidate:

`b270fb806038333c97fa1ed49655961adddd6a21`

SM1.7.12 закрыт: **700/700 PASS**, regression belt PASS, Project Control #1439 SUCCESS.

B2 composite regression-repair candidate:

`6fdfc047f54e727e6b398370e576c746c7949441`

tree `b9b1202d959b3da4a0c73840091c7bf56070429e`, Draft PR #282 over exact `b270fb8...`.

Exact Windows double-Godot B2: **307/307 steps PASS**, `304/304` standalone tests, `main_scene_cli_all` PASS, `summary.passed=true`. Durable closure is linked from PR #242.

Осталось:

```text
B1. SM1.7.12 impaired-network repeated crossings    DONE
B2. full world/core regression                       CLOSED
B2.5 manual seamless smoke demo                      CLOSED / WINDOWS MANUAL PASS
B3. post-build critique                               CLOSED
B4. Evidence Map                                      CLOSED
B5. fresh exact-head Reviewer                          CLOSED / PASS
B6. fresh Verifier                                     FAILED / BLOCKED — M5 correctness R6 CURRENT
B7. checkpoint proposal
B8. human RUNTIME_FEATURE_MERGE
```

### Pre-P7 manual seamless smoke demo

B2 закрыт. Non-acceptance tester demo реализован в Draft PR #284 поверх B2 composite.

```text
Authority A + Authority B + Gateway
→ graphical client connects only to Gateway
→ manual movement across visible A/B boundary
→ A -> B without loading/reconnect/respawn
→ B -> A
→ repeated crossings
```

Manual-input/presentation wrapper реализован: один graphical client подключается только к стабильному Gateway endpoint, показывает active Authority/epoch/world revision/reconnect/respawn и вручную управляется WASD/стрелками. Exact demo candidate `b0445e08c56e090279ab21a210169df01ff3bd73`, tree `98ab141e03707ca17a5ba913b9d0d9a7e775d7d5`. Автоматический graphical smoke тем же client path: 10/10 A→B→A циклов, 320/320 assertions PASS; старый two-client SM1.6 остаётся 58/58 PASS. Windows manual tester execution также PASS: `SM1_MANUAL_SEAMLESS_CLIENT_COMPLETE passed=true`, `SM1_MANUAL_SEAMLESS_DEMO_PASS`, route `A→B→A`, epochs `1→2→3`, `connect_count=1`, `reconnect_count=0`, `respawn_count=0`, 119/119 commands confirmed, last error none. Tester reports no noticeable movement delay. Repeated Camera3D physics-interpolation warnings were non-fatal and move to B3 critique cleanup. P7/terraforming для demo не требуется.

Exit condition: **SM1 ACCEPTED**.

## Фаза C — P7 bounded terrain mutation

**Статус: NEXT PRODUCT RUNTIME BLOCK**

Цель P7 — не "сделать новый terrain engine", а добавить authoritative mutable surface к уже существующему persistent/seam-aware product.

Минимальные slices:

### P7.1 Canonical bounded mutation

- определить/переиспользовать canonical Matter/terrain owner;
- bounded dig/remove operation;
- deterministic OperationId;
- server-only authoritative mutation;
- no client-private terrain truth;
- stable material/voxel/patch identity.

### P7.2 Dig -> resource

```text
equipped tool
→ authoritative dig command
→ terrain/material debit
→ canonical resource yield
→ Item Graph
→ replicated inventory/world result
```

Добыча ресурса не должна дублировать существующий P4/P5 resource path.

### P7.3 Replication + durability

- two-client convergence;
- deterministic terrain delta/fingerprint;
- disconnect/reconnect reconstruction;
- server restart reconstruction;
- stale/duplicate command fencing;
- bounded compaction/snapshot strategy.

### P7.4 Seam-aware terrain mutation

Проверить:

```text
A active: dig/build
→ A->B transfer gap: writes fenced
→ B active: dig/build
→ B->A
→ canonical terrain + Item Graph + Construction converge
```

Gateway не решает terrain ownership.

### P7.5 Graphical product acceptance

Два реальных клиента на bounded planetary patch:

- walk;
- mine;
- dig;
- build;
- cross seam;
- dig/build again;
- reconnect;
- restart;
- same world.

Exit condition: **P7 ACCEPTED + V0 PLAYABLE SEAMLESS PLANET graphical acceptance**.

## Фаза D — big checkpoint closure

После P7 выполнить отдельный product-level acceptance, а не считать P7 unit acceptance автоматически равным North Star.

Обязательные доказательства:

- 2 graphical clients;
- real dedicated processes;
- stable Gateway endpoint;
- A<->B crossing;
- terrain mutation;
- mining/material yield;
- resource-backed Construction;
- reconnect;
- server restart;
- repeated clean runs;
- bounded soak;
- zero duplicate canonical truth.

После этого фиксируется:

**V0 PLAYABLE SEAMLESS PLANET — ACHIEVED**

## Фаза E — P8 first mobile construct

Только после North Star:

```text
Construction
+ Item Graph/resources
+ persistence
+ reference frames
+ terrain/world relation
+ seam-aware authority
→ bounded mobile construct / rover / ship
```

P8 не блокирует первый seamless planet checkpoint.

## Фаза F — seamless scale-out

После доказанного static A<->B product:

- arbitrary N authorities;
- load-aware placement;
- dynamic ownership assignment;
- shard/region split;
- merge;
- failure redistribution;
- moving Interaction Islands;
- stronger WAN/fault models.

Не расширять SM1 до этих задач до его acceptance.

## Фаза G — planetary presentation scale

После working gameplay:

- hierarchical projection / MRPF;
- planet -> region -> local patch representation;
- surface HLOD;
- distant constructs/outposts;
- large-scale visibility;
- projection continuity independent of simulation ownership.

Это presentation scale, не prerequisite для bounded playable surface.

## Фаза H — living planet / ECO integration

ECO продолжает research line параллельно.

Текущая live-spatial последовательность:

```text
LS3.0 Real Planet Patch
→ LS3.1 Environment Generator
→ LS3.2 Spatial Cohort Lattice
→ LS3.3 Dispersal / Recruitment
→ LS3.4 Competition
→ LS3.5 Emergent Biomes
→ LS3.6 Rule Workbench
→ LS3.FINAL
```

ECO подключается к продукту только через явный integration/ownership contract. До этого research status alone не является V0 blocker.

## Critical-path rule

До достижения V0 PLAYABLE SEAMLESS PLANET приоритет:

```text
SM1 closure
    ↓
P7 terrain mutation
    ↓
North Star graphical acceptance
```

Не начинать на critical path:

- P8;
- новый Gateway;
- новый network transport;
- second Item Graph/Construction/persistence owner;
- global dynamic shards;
- full planet HLOD;
- ECO product promotion.

Исключение — доказанный blocker текущего SM1/P7 Work Order.

## Progress metric

Baseline 2026-08-28:

**~80% до V0 PLAYABLE SEAMLESS PLANET по функциональной готовности.**

Current navigation after B2 + B2.5 closure (2026-08-29): **~83%**, не Harness acceptance.

Historical comparison snapshot:

`docs/checkpoints/2026-08-28_V0_PLAYABLE_SEAMLESS_PLANET_PROGRESS_R2_RU.md`

### B3 post-build critique closure

B3 закрыт отдельным control/evidence carrier PR #285.

Exact closure candidate для дальнейшего Reviewer/Verifier: `6fdfc047f54e727e6b398370e576c746c7949441`, tree `b9b1202d959b3da4a0c73840091c7bf56070429e`.

Verdict: `IMPLEMENTATION_COMPLETE_READY_FOR_EVIDENCE_MAP_WITH_NONBLOCKING_FOLLOWUPS`.

Новых correctness-блокеров не найдено. Важно: Reviewer должен проверять composite closure candidate `6fdfc047...`, а не source-only `b270fb8...`; demo #284 остаётся non-acceptance UX evidence.

Non-blocking followups: один наблюдавшийся M5 convergence timing flake; isolated-profile cleanup и Camera3D warning cleanup для demo вынесены в Draft PR #286.

### B4 Evidence Map closure

B4 закрыт отдельным control/evidence carrier PR #287.

Evidence Map bind: exact production closure candidate `6fdfc047f54e727e6b398370e576c746c7949441`, tree `b9b1202d959b3da4a0c73840091c7bf56070429e`.

Map: focused PASS, full regression PASS, canonical truth changed=false, architecture ownership changed=false, required_fixes=[], review_verdict=PASS.

STANDARD/DIRECTIONAL PC0 на composite closure head честно остаются NOT_RUN и должны быть закрыты на fresh review-head; Project Control #1439 не переинтерпретируется как composite-head PASS.

Demo/tooling cleanup PR #286 подтверждён на Windows: ghosting исчез, isolated profile PASS, repeated manual route A→B→A→B→A→B / epochs 1..6 PASS при одном Gateway connection и zero reconnect/respawn.

Текущий следующий этап: **B5 fresh exact-head Reviewer**.

### B5 Reviewer closure

Fresh independent Reviewer PASS опубликован отдельным control-only record на `control/v0-sm1-b5-final-review-r1`.

Review record commit `8b4793d868eb81ff4786d51a4ba5ec90deb08a4e`, tree `4df95dcd3c32e49539b074990095726ca5aa0b4f`.

Reviewed subject остаётся exact `6fdfc047f54e727e6b398370e576c746c7949441`, tree `b9b1202d959b3da4a0c73840091c7bf56070429e`; verdict PASS; required_fixes=[].

Reviewer не объявлял Verifier PASS, checkpoint/merge acceptance или PC0 NON_RED. B6 fresh exact-head machine verification dispatched в Draft PR #290.

### B6 Verifier failure / M5 repair

Fresh B6 Verifier на exact subject `6fdfc047...` выдал FAILED: canonical full world/core regression упал на первом прогоне в `test_m5_graphical_multiplayer_acceptance`; M5 instability независимо воспроизведена 3/4 attempts. Focused SM1 13/13 и impaired-network 5/5 остались PASS.

B7 заблокирован. Director Repair Map: Draft PR #291. Bounded M5 harness repair: Draft PR #292, HEAD `8c44ea1aac6846502ce55e7ba9a61e2cfe154360`, tree `eff7a35411edca2ea71daf93fab90b706c4258e0`.

Repair не меняет SM1 runtime и не ослабляет M5 gameplay/convergence assertions. Exact Linux double-Godot/Xvfb supporting evidence после repair: 5/5 consecutive PASS, 99 assertions / 0 failures each. Decisive next gate: Windows 10x M5 stability, then one canonical full regression and fresh B6 re-verification.

### M5 R3 timeout-clock root cause

Windows R2 passed 2 runs and failed run 3 at ~164.4s with historical `M5_ACCEPTANCE_TIMEOUT` in `WAIT_CONVERGENCE_PEER` on long-lived client B. Root cause: driver compared `TIMEOUT_MS=150000` against process `_started_ms`, not per-stage `_stage_started_ms`, despite `_set_stage()` already resetting the stage clock.

R3 Repair Map: PR #295. R3 implementation: PR #296 @ `17801cecab4861683bd0d0ee4eabbd1186ba7164`, tree `944543e15718d1d427edb35be78446bee7659e43`.

Timeout value is unchanged; only clock scope is corrected. B6/B7 remain blocked until Windows 10/10 M5 stability and then one canonical full regression first-attempt PASS.

### M5 R4 child-exit observability

R3 exact candidate `17801cecab4861683bd0d0ee4eabbd1186ba7164` remains the preserved failed subject. Windows R3 first run failed in ~20.3s because A2 disappeared before first result JSON; no rerun and no canonical full regression were performed.

Earlier AppHang attribution is withdrawn: WER events do not overlap the gate window. R4 is therefore diagnostic-only and targets termination origin.

R4 Repair Map: PR #299. Diagnostic implementation: PR #300 @ `ba5e1509f078b4b7599f9390da7df819b7340c4d`, tree `471f86dc3d69fcef5bf50e89cdc80ff909798b24`.

R4 captures direct stdout/stderr, actual child exit code, parent-kill attribution, first-death wait label and last result/control snapshots. It does not claim to fix correctness. B6/B7 stay blocked until diagnostic evidence identifies the next legal repair.

### M5 R5 pipe observability repair

R4 diagnostic run был invalid: instrumentation вызывал отсутствующий `FileAccess.get_available_bytes()`. При этом A2 и B в этом прогоне дошли до `CONVERGENCE_LOCKED`, поэтому preserved R3 silent-A2 class остаётся OPEN, но не был воспроизведён в R4.

R5 Repair Map: PR #301. Diagnostic implementation: PR #302 @ `b9bc54086e959e7d26f79336c264a96f29f31a17`, tree `6c631f1517ce1f335fe2765fcdafcf5b1b39ef20`.

R5 использует FileAccess pipe `get_length() -> get_buffer() -> get_error()` и обязует stability runner выполнить настоящий stdout+stderr pipe smoke до run 1. Exact double-Godot algorithm smoke локально PASS (stdout/stderr по 13 bytes, child exit 0).

R5 остаётся diagnostic-only; canonical full regression из этой ветки не запускается автоматически. B6/B7 остаются BLOCKED.

### M5 R6 centralized convergence repair

R5 diagnostic gate на Windows полностью локализовал активный дефект: run 1 PASS, run 2 PASS, run 3 FAIL; A2 и B оба провели ~150s в `WAIT_CONVERGENCE_PEER`, затем сами завершились с exit=1 / `NOT_PARENT_INITIATED`. Parent-side prepare/release asserts при этом уже были зелёными.

Root cause: convergence-клиенты формировали второй peer-to-peer barrier через result-файлы, а `CONVERGENCE_RELEASED` оставался revocable. Из-за последовательного чтения `a.json`/`b.json` parent мог собрать временно несовместимые RELEASED snapshots и ложно решить, что оба release consumed.

R6 Repair Map: PR #303. Implementation: PR #304 @ `796a84f097f54b009e9745353a28a294f2937a70`, tree `5c064747589f298cc35b8f33a66a4ba55ac833c5`.

R6 делает parent единственным pair matcher, убирает peer-result gating из convergence, делает consumed release monotonic для generation и превращает post-release drift/control regression в явный fail-closed. Exact COMPLETE запечатывает convergence до штатного serialized teardown.

Pure convergence monotonicity regression включён в `RUN_NETWORK_CONTRACT_TESTS.ps1`. B6/B7 остаются BLOCKED до Windows contracts + pure regression + pipe smoke + 10/10 stability; только затем допустим один canonical full regression first attempt.
