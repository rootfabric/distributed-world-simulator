# NX / M7 Owner Authority Convergence

## Решение

Старая ветка `feature/m7-sequence-aware-reconciliation-fix10-fix6-semantic-baseline` больше не является production frontier. Она сохраняется как исследовательская линия и источник доказательств, но не rebased/merged целиком в `main`.

Новая canonical NX frontier:

`feature/nx-m7-owner-authority-convergence`

База:

`main @ 9391ccfce40a14a0f568f81c4c68ddfc76f79c76`

Причина: старая N разошлась с main на сотни коммитов и накопила FIX6/FIX7/FIX8/FIX9/FIX10, presentation, scheduler, inventory/UI и diagnostics в одной lineage. Перенос всей истории создаст альтернативную integration architecture вместо convergence.

## Что доказано в старой N и разрешено использовать как evidence

- Owner-authoritative locomotion устраняет локальные сетевые рывки.
- Сервер валидирует `PLAYER_STATE` и relays accepted state другим клиентам.
- Remote presentation остаётся snapshot/interpolation driven.
- Inventory / Item Graph / containers остаются server-authoritative.
- Optimistic item pickup/drop требует same-authority-revision presentation rollback.
- `Basis -> yaw` должен сохранять Godot forward `-Z` convention.
- Windows focused suite на runtime `464e1b8dd27fad8b4d477f6e76ca52a449893353` прошёл owner movement, item rollback/drop, FIX10/FIX9/FIX8/NX4 regressions.
- Manual two-client LOCAL diagnostic подтвердил плавный owner, плавный remote и работающий pickup/drop.
- Acceptance record сохранён на legacy lineage в `docs/validation/M7_OWNER_AUTHORITY_ACCEPTANCE_2026-08-11.md` (`538674d1f3f991c9e04d77b0ce0a4dfea24d9ce6`).

Evidence не означает разрешение cherry-pick всей ветки.

## Что переносим в NX.C1

Минимальные capability units:

1. `MovementAuthorityProfile`
   - `SERVER_PREDICTED`
   - `OWNER_AUTHORITATIVE_VALIDATED`
   - профиль относится только к realtime locomotion authorship, не к permanent entity/gameplay authority.

2. Owner movement server service
   - owner/session/epoch validation;
   - playable-state validation;
   - bounded movement plausibility;
   - accepted state -> canonical player record;
   - correct `Basis(-Z) <-> yaw` round-trip.

3. Owner movement client composition
   - local deterministic controller is the sole local locomotion author;
   - send post-factum realtime owner state;
   - ordinary accepted snapshots do not rewind local owner;
   - explicit rejection/recovery path remains possible.

4. Remote snapshot relay/interpolation
   - reuse current main NX baseline where possible;
   - do not import duplicate FIX layers when main already supplies equivalent behavior.

5. Optimistic Item Graph rollback
   - canonical server revision and client presentation generation are separate identities;
   - same-revision reject/rollback must reach replica/UI;
   - Item ownership and mutation remain server-authoritative.

## Что запрещено переносить напрямую

### FIX7 render writer — BLOCKED

Legacy `playground_view_relative_runtime_fix7.gd` mutates the physics player from `_process()`:

- `player.set_world_position(...)`
- `player.velocity = ...`

This violates the single-writer physics boundary and is not eligible for convergence.

Correct target:

- physics tick owns `CharacterBody3D` transform/velocity;
- render tick may update only `VisualRoot` / camera presentation proxy / presentation offset;
- runtime test must prove render frames cannot mutate physics-body truth between physics ticks.

### Legacy FIX ladder — BLOCKED

Do not reproduce:

`NX4 -> FIX8 -> FIX10 -> FIX10_FIX5 -> FIX10_FIX6_CORE -> SEMANTIC_CADENCE -> LOCAL_PRESENTATION -> FIX7/FIX8 playground`

Production target is one canonical implementation per responsibility with compatibility tests, not an inheritance archaeology stack.

### Historical inventory/UI overlays — BLOCKED by default

Only migrate an item/UI change when it is necessary for the owner-authority capability and still missing from current main/CH9.6. Current Character/Inventory work owns its UI composition.

## Input metadata robustness

Legacy relative `client_tick` scheduling must not be copied without a bounded-gap policy.

Required contract before any such scheduler is promoted:

- monotonic sequence/tick handling;
- bounded reasonable forward delta;
- explicit duplicate/backward/huge-jump behavior;
- reject or rebase, never multi-second implicit future scheduling;
- telemetry for rebase/reject;
- fuzz/property tests for huge, repeated, backward and wrap-around values.

Owner-authority locomotion should not depend on legacy relative-tick scheduler behavior unless a concrete need is demonstrated.

## PC0 lifecycle

### NX.C0 — GREEN preparation

Only control/passport/plan changes.

- branch based on current main;
- no runtime paths changed;
- no stale tested head can exist;
- no cross-branch runtime overlap;
- old N is evidence only.

### NX.C1 — YELLOW implementation candidate

When first runtime file is changed:

- set `runtime_paths` to actual changed production runtime paths;
- set `health_declared=YELLOW`;
- stage status `IMPLEMENTED_CANDIDATE_VALIDATION_PENDING`;
- record exact candidate runtime head.

### NX.C2 — GREEN source accepted

Required on exact Windows Godot 4.7.1 double checkout:

1. editor import;
2. focused owner authority tests;
3. render/physics single-writer runtime test;
4. same-revision item rollback + pickup/drop test;
5. client tick robustness/fuzz tests if scheduler metadata is touched;
6. full `RUN_WORLD_REGRESSION_TESTS.ps1`;
7. two-client process test;
8. minimum 5 minute movement + item stress under LOCAL and at least one impaired profile;
9. reconnect/ownership-epoch test;
10. update `tested_heads.runtime/focused/full_regression` to the exact runtime head.

Only after all required evidence is green may passport and registry return to `health_declared=GREEN` with `SOURCE_ACCEPTED=true`.

## Cross-program dependencies

### CH9.6

Current CH9.6 no longer declares the generic M3 graphical/dedicated runtime as critical watched paths. It watches the Character equipment controller/UI, CH9.5 persistent server wrapper and presenter. NX must not modify those Character-owned files during convergence unless CH explicitly enters a convergence/revalidation step.

If NX changes behavior observable through CH9.5 persistent server composition, run CH9.6 targeted validation before NX source acceptance.

### T1B

T1B watches `scripts/network/**` broadly and treats `scripts/network/contracts/network_protocol_manifest.gd` as critical.

- scheduler/prediction/network implementation drift -> T YELLOW targeted revalidation;
- protocol manifest/channel contract change -> T RED until explicit revalidation/convergence.

NX.C1 should avoid protocol-manifest changes unless absolutely required.

## Acceptance dimensions

Keep separate:

- `SOURCE_ACCEPTED`
- `MAIN_INTEGRATED`
- `COMPOSITION_VERIFIED`
- `PRODUCTION_READY`

The legacy owner-authority visual PASS is evidence for implementation choice, not proof that the new main-based convergence branch is integrated or production-ready.

## Final target architecture

```text
Owned player
  local controller / physics truth
          |
          +--> OWNER_AUTHORITATIVE_VALIDATED realtime state
                      |
                      v
              server validation
                      |
              canonical player record
                      |
             snapshot / remote relay

Remote player
  snapshots -> interpolation -> presentation proxy

Items / Inventory / Containers / Economy
  server authoritative canonical graph
          |
  optimistic client projection
          |
  confirm or same-revision rollback

Render
  presentation proxy only
  never a second CharacterBody writer
```
