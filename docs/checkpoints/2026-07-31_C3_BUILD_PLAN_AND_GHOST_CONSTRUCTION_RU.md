# Checkpoint C3 — BuildPlan and Ghost Construction

**Дата:** 2026-07-31
**Статус:** IMPLEMENTED CANDIDATE
**База:** принятый C2B, ветка `feature/c2b-authoritative-item-graph-integration`
**Рекомендуемая ветка:** `feature/c3-build-plan-and-ghost`

## Цель

Сделать строительство resumable-процессом, не ослабляя принятые Item Graph и M0 authority invariants.

## Реализованная цепочка

```text
immutable BuildPlan
→ weightless GhostState
→ stage capability check
→ deterministic ConstructionItemTransactionPlan
→ C2B-compatible authoritative apply
→ partial ConstructSnapshot
→ reconcile/replay
→ operational ConstructSnapshot
```

## Контракты

- `planet_simulator.construction_build_stage.v1`;
- `planet_simulator.construction_build_plan.v1`;
- `planet_simulator.construction_ghost_state.v1`;
- `planet_simulator.construction_build_plan_store.v1`;
- `planet_simulator.construction_ghost_projection.v1`;
- `ADVANCE_CONSTRUCTION_STAGE` в `construction_item_transaction_plan.v1`.

## Инварианты

1. BuildPlan immutable и checksum-protected.
2. Source item projections точны и не меняют identity.
3. Stage parts/bonds монотонны.
4. Final stage содержит полный target и является `OPERATIONAL`.
5. Material allocations не могут полностью уничтожить stack в C3 v1.
6. Ghost до первой стадии не имеет Item identity, массы или capabilities.
7. Partial construct не публикует operational capabilities.
8. Реальный расход проходит только через C2B adapter.
9. Exact replay не повторяет material consumption.
10. Crash между C2B commit и ghost update восстанавливается reconciliation.
11. Ghost не может откатить authoritative construct.
12. Divergent construct отклоняется, а не маскируется progress projection.

## Vertical slice

Трёхстадийный item-backed стол:

```text
FOUNDATION:
  top + leg A + leg B + fasteners ×2

FRAME:
  leg C + leg D + fasteners ×2

COMMISSIONING:
  sealant ×1 + INSPECT
```

После первых двух стадий snapshot `PARTIAL`, capabilities отсутствуют. После commissioning snapshot `OPERATIONAL`, capability compiler выдаёт `PLACE_ITEMS`, `SUPPORT_SURFACE`, `WORK_SURFACE`.

## Локальная проверка

```text
C3 contracts:      PASS — 80 assertions
C3 integration:    PASS — 114 assertions
Focused C3 total:  PASS — 194 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
Editor parse:      PASS
```

Focused tests выполнялись на `Godot 4.7.1.stable.double.custom_build.a13da4feb` в изолированном construction workspace. Полный checkout required для C2B/network/world acceptance.

## Review fix1 — каноническое сравнение preconditions

Внешняя проверка первоначального кандидата обнаружила blocker: после FOUNDATION in-memory adapter сохранял `ConstructSnapshot` через JSON-canonicalization, а следующая стадия передавала семантически тот же snapshot с другими числовыми Variant-типами (`int`/`float`). Прямое сравнение `Dictionary` ошибочно возвращало различие и завершало FRAME с `CONSTRUCT_PRECONDITION_MISMATCH`.

Исправление:

- construct preconditions сравниваются через `NetworkContractUtils.canonical_json()`;
- item preconditions переведены на то же сравнение, чтобы аналогичный дефект не проявился после снятия первого blocker;
- добавлен отдельный регрессионный сценарий с канонически равными, но Variant-типоразличными `state_revision` и item `revision`;
- invalid/non-JSON-safe значения по-прежнему не совпадают, поскольку пустой canonical JSON считается отказом сравнения.

Локальный профиль fix1:

```text
C3 contracts:      PASS — 80 assertions
C3 integration:    PASS — 114 assertions
Focused C3 total:  PASS — 194 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
Editor parse:      PASS
```

Полный C2B/network/world/main-scene профиль должен быть повторён во внешнем полном checkout.

## Вне scope

- gameplay UI и placement controls;
- network command endpoint для BuildPlan;
- reusable CompositeDefinition;
- automatic inventory search and logistics;
- pathfinding builder robot;
- repair/deconstruction BuildPlan;
- полное уничтожение material stack;
- multiplayer contention между builders.

## Acceptance gate

```text
RUN_C1_CONSTRUCTION_KERNEL_TESTS.ps1
RUN_C2A_CONSTRUCTION_ITEM_GRAPH_TESTS.ps1
RUN_C2B_AUTHORITATIVE_ITEM_GRAPH_TESTS.ps1
RUN_C3_BUILD_PLAN_TESTS.ps1
RUN_NETWORK_CONTRACT_TESTS.ps1
RUN_WORLD_REGRESSION_TESTS.ps1
git diff --check
```

После внешнего PASS C3 становится базой C4 — `CompositeDefinition`.
