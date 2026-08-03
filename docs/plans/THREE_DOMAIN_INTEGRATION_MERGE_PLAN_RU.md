# INT0 — план объединения Network, Matter/Representation и Construction/Items

**Дата начала:** 2026-08-03  
**Репозиторий:** `rootfabric/distributed-world-simulator`  
**Интеграционная ветка:** `integration/c24-nx6-mw10-rl3`  
**Целевой checkpoint:** `v18.0.0-integration-int0-three-domain-base`

## Текущая стадия

```text
PRE0 frozen heads verified:     DONE
PRE1 backup branch created:     DONE
PRE2 integration branch created: DONE
PRE3 plan and manifest:         IN PROGRESS
INT0-NX6 merge:                 NOT STARTED
INT0-RL3/MW10 merge:            NOT STARTED
INT0-C24 merge:                 NOT STARTED
INT0 combined validation:       NOT STARTED
INT0 independent acceptance:    NOT STARTED
merge to main:                  NOT STARTED
```

На текущей стадии production-код ещё не объединён. `main` не изменён.

## Замороженные входные головы

```text
main_base_sha:
69bd7fc7fde2bc0824b0d608451ecd310397b8d2

network_branch:
feature/nx6-predicted-item-interactions
network_head_sha:
144adf35cd2151ce5f8572dbbb8ed1b58ccd9778
checkpoint:
v16.16.0-network-nx6-predicted-item-interactions
status:
ACCEPTED

matter_surface_branch:
feature/rl3-representation-aware-network-streaming
matter_surface_head_sha:
89ff51b3ee5f66f6548f8b97e271062daf09b5cf
checkpoint:
v17.14.0-simulation-rl3-representation-aware-network-streaming
status:
ACCEPTED
includes:
MW10 + MW9 fix3 + RL2 + RL1 + RL0

construction_branch:
feature/c24-gpu-ready-proxy-mesh-backend
construction_head_sha:
c18b3afaf0f2f078899be20d0529fa94d53adf90
checkpoint:
C24_GPU_READY_PROXY_MESH_BACKEND
status:
ACCEPTED
```

RL3 уже содержит MW10. Ветку `feature/mw10-cross-region-matter-transactions` отдельно не вливать.

## Защитные точки

```text
backup/main-before-int0-20260803
→ 69bd7fc7fde2bc0824b0d608451ecd310397b8d2

integration/c24-nx6-mw10-rl3
→ создана от того же main base
```

Старые accepted-ветки считаются frozen. Новые функции в них не добавлять. Разрешены только блокирующие fixes отдельными коммитами с обязательным переносом в integration.

## Общая стратегия

```text
main
→ NX6
→ RL3 с MW10
→ C24
→ runtime composition
→ INT0 combined validation
→ independent acceptance
→ main
```

Каждый домен добавляется через отдельную staging-ветку и отдельный PR в integration. Следующий домен начинается только после полного PASS предыдущей композиции.

Merge method для доменных веток и финального PR: `merge commit`. Не использовать squash, rebase и force-push.

## Этап PRE — подготовка

### PRE0 — проверка SHA

Перед началом подтверждены точные головы `main`, NX6, RL3 и C24. При несовпадении любого SHA интеграцию остановить и обновить manifest отдельным решением.

### PRE1 — резервная ветка

Создана `backup/main-before-int0-20260803` от frozen `main_base_sha`.

### PRE2 — интеграционная ветка

Создана `integration/c24-nx6-mw10-rl3` от frozen `main_base_sha`.

### PRE3 — документация

В integration должны существовать:

```text
docs/plans/THREE_DOMAIN_INTEGRATION_MERGE_PLAN_RU.md
validation/int0-three-domain-frozen-heads.json
```

После этого статус PRE меняется на `DONE`, и начинается `INT0-NX6`.

## Этап 1 — INT0-NX6

Staging branch:

```text
merge/int0-nx6
```

Источник:

```text
144adf35cd2151ce5f8572dbbb8ed1b58ccd9778
```

NX6 определяет базовую runtime/transport модель, поэтому вливается первым.

Обязательно сохранить:

- fixed-tick authoritative simulation;
- client prediction и reconciliation;
- remote interpolation;
- channel separation;
- predicted item transaction journal;
- production `bridge.stop()` при unload;
- lifecycle реальной `playground.tscn`.

Gate перед PR в integration:

```text
Editor import PASS
NX0–NX6 PASS
M7 playable contracts PASS
M7 graphical multiprocess PASS
M7 recovery PASS
Network regression PASS
World regression PASS
Main-scene CLI PASS
git diff --check PASS
conflict markers 0
remaining Godot/Xvfb 0
```

После PASS открыть PR `merge/int0-nx6 → integration/c24-nx6-mw10-rl3`.

## Этап 2 — INT0-RL3/MW10

Staging branch:

```text
merge/int0-rl3-mw10
```

Источник:

```text
89ff51b3ee5f66f6548f8b97e271062daf09b5cf
```

NX6 остаётся владельцем player realtime transport. RL3 добавляет representation manifests, artifact chunks, cache ACK, cancellation, invalidation и budgets. Artifact bytes не становятся canonical world state.

Критические общие файлы:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd
scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd
tests/runtime/test_m3_graphical_multiplayer_contracts.gd
AGENTS.md
NETWORK_ROADMAP_RU.md
PROJECT_MANIFEST.txt
README_RU.md
```

Запрещено разрешать runtime-файлы целиком через `ours` или `theirs`.

Gate:

```text
весь INT0-NX6 gate PASS
MW0–MW10 PASS
MW9 fix3 race/recovery PASS
MW8 98/98 PASS
RL0–RL3 PASS
server + 2 clients PASS
reconnect/full-resync PASS
network conditions PASS
artifact cancellation PASS
stale artifact rejection PASS
cache reuse PASS
```

## Этап 3 — INT0-C24

Staging branch:

```text
merge/int0-c24
```

Источник:

```text
c18b3afaf0f2f078899be20d0529fa94d53adf90
```

C24 вливается последним, потому что имеет наиболее широкий overlap с Item Graph, graphical runtime, construction commands, manifests и regression runners.

Распределение ответственности:

```text
NX6 → predicted presentation and network interaction UX
C2B/C24 → authoritative Item Graph and Construction state
RL3 → derived representation artifact delivery
C24 proxy backend → construction artifact ArrayMesh materialization
```

На INT0 не унифицировать C24 proxy backend с RL3 через крупный redesign. Нужна совместимость существующих boundaries; глубокая унификация относится к последующим INT1/INT2.

Критические файлы:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd
scripts/items/presentation/item_gameplay_controller.gd
scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd
scripts/app/simulator_app.gd
scripts/world/testing/playground_runtime.gd
RUN_WORLD_REGRESSION_TESTS.ps1
PROJECT_MANIFEST.txt
README_RU.md
AGENTS.md
```

Gate:

```text
весь NX6 + MW/RL gate PASS
C1–C24 PASS
C2B Item Graph PASS
C9 damage/split/repair PASS
C17 authority migration PASS
C22 proxy/HLOD PASS
C23 production hardening PASS
C24 2522 assertions PASS
10k-part scale/soak PASS
World full regression PASS
Main scene PASS
```

## Этап 4 — runtime composition

Разрешать общие runtime-файлы через adapters, а не через выбор одной версии.

Рекомендуемый порядок startup:

```text
1. Network transport
2. NX6 fixed-tick runtime
3. Player prediction/interpolation
4. Authoritative Item Graph
5. Predicted item interaction bridge
6. Matter canonical replica
7. RL3 representation streaming
8. Construction authoritative runtime
9. C24 construction proxy presentation
10. UI/presentation
```

Shutdown выполняется в обратном порядке. Command pumps и stream callbacks должны останавливаться до освобождения stores, caches и runtimes.

## Этап 5 — INT0 combined validation

Создать runners:

```text
RUN_INT0_THREE_DOMAIN_INTEGRATION_TESTS.ps1
RUN_INT0_THREE_DOMAIN_INTEGRATION_TESTS.sh
```

Combined scenario:

```text
dedicated server
→ two clients
→ predicted local movement
→ remote interpolation
→ predicted pickup/drop/placement
→ replicated Matter state
→ RL3 coarse-to-fine surface stream
→ C24 10k-part proxy presentation
→ reconnect
→ exact canonical state
→ no unresolved predictions
→ no stale artifacts
→ no duplicate identities
→ clean shutdown
```

INT0 не добавляет новые cross-domain gameplay mechanics. Matter-to-item и construction-on-mutable-surface относятся к INT4/INT5.

## Этап 6 — checkpoint и независимая приёмка

Candidate commits:

```text
feat(integration): compose NX6 RL3 and C24 runtimes
docs(integration): record INT0 three-domain candidate
```

Документы:

```text
docs/checkpoints/2026-08-XX_INT0_THREE_DOMAIN_INTEGRATION_RU.md
validation/int0-three-domain-integration-validation.json
validation/int0-three-domain-integration-files.txt
```

Сначала статус `IMPLEMENTED_CANDIDATE`. После независимой полной проверки — отдельный acceptance-коммит со статусом `ACCEPTED`.

## Этап 7 — merge в main

Только после INT0 acceptance открыть финальный PR:

```text
integration/c24-nx6-mw10-rl3 → main
```

После merge поставить checkpoint/tag доступным инструментом, сохранить новый backup main и начинать дальнейшие этапы только от общей базы.

## Правила остановки

Интеграция блокируется при любом из условий:

- frozen SHA изменился без отдельного решения;
- не пройден gate предыдущей стадии;
- runtime conflict разрешён wholesale через `ours/theirs`;
- canonical state заменён presentation artifact;
- остались unresolved predictions, stale streams или duplicate identities;
- validation metadata утверждает тесты, которые фактически не запускались;
- `main` изменён до принятия INT0.
