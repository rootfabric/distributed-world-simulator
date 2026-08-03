# INT0 — композиция C24 поверх NX6 + RL3/MW10

```text
stage: INT0-C24
source checkpoint: C24_GPU_READY_PROXY_MESH_BACKEND
source branch: feature/c24-gpu-ready-proxy-mesh-backend
source frozen head: c18b3afaf0f2f078899be20d0529fa94d53adf90
staging branch: merge/int0-c24
staging base: 64770c62574de58fa522dbdf2b4be891fe00442c
staging merge commit: 00ae523ac85c575424d84a49b48fa4be37bcbf3a
classification: COMPOSED CANDIDATE, NOT ACCEPTED
```

## Результат merge-аудита

GitHub выполнил чистый merge без текстовых конфликтов. C24 добавляет 863 пути относительно текущей integration-базы:

```text
new paths:      862
modified paths: 1
removed paths:  0
```

Единственный изменённый существующий путь:

```text
RUN_WORLD_REGRESSION_TESTS.ps1
```

Изменение runner является аддитивным: в `$Tests` добавлены 57 construction scripts C1–C24. Существующие Network, Matter, Representation, Item, World и runtime entries не удалены и не заменены.

Следующие ожидавшиеся общие runtime-файлы C24 не изменяет:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd
scripts/items/presentation/item_gameplay_controller.gd
scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd
scripts/app/simulator_app.gd
scripts/world/testing/playground_runtime.gd
AGENTS.md
PROJECT_MANIFEST.txt
README_RU.md
```

Поэтому C24 не перезаписывает уже выполненную NX6/RL3 runtime-композицию и не требует conflict-resolution adapter на этом этапе.

## Границы ответственности

```text
NX6:
transport, fixed tick, prediction/reconciliation,
remote interpolation, predicted item interaction presentation.

RL3/MW10:
Matter canonical state, representation manifests/artifacts,
invalidation, cache lifecycle and bounded representation delivery.

C24:
authoritative Construction/Item Graph domain,
compiled construction proxies and ArrayMesh materialization.
```

Construction proxy meshes остаются производными presentation artifacts. C24 не подключён напрямую к generic RL3 artifact transport в рамках механического INT0 merge. Такая унификация требует отдельного adapter checkpoint после успешного общего gate.

## Что доказано

```text
frozen C24 head unchanged: PASS
GitHub mergeability: PASS
text merge conflicts: 0
C24 history preserved: PASS
squash/rebase/force-push: not used
existing runtime files replaced: 0
world runner additions: 57
```

## Что ещё не доказано

```text
full integration editor import
C24 focused 2522 assertions on composed tree
C23/C22/C2B/C9 regression on composed tree
NX0–NX6 regression after C24 addition
MW0–MW10 and RL0–RL3 regression after C24 addition
World regression with all 57 construction scripts
main-scene CLI
combined server + two clients + Matter + construction proxy scenario
```

## Gate перед INT0 acceptance

1. Godot 4.7.1 double editor import.
2. C24 focused runner.
3. C23, C22, C2B и C9 focused profiles.
4. NX0–NX6 и M7 graphical/recovery.
5. MW0–MW10, MW9 race/recovery, RL0–RL3.
6. Полный `RUN_WORLD_REGRESSION_TESTS.ps1` с construction entries.
7. Main-scene CLI 6/6.
8. Static repository checks и отсутствие оставшихся Godot/Xvfb процессов.

Только после полного PASS общая ветка может получить checkpoint `v18.0.0-integration-int0-three-domain-base` и перейти к независимой приёмке.
