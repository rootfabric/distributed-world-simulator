# INT0 — текущий статус интеграции

**Обновлено:** 2026-08-03 20:14 UTC+10  
**Основной план:** `docs/plans/THREE_DOMAIN_INTEGRATION_MERGE_PLAN_RU.md`  
**Machine-readable manifest:** `validation/int0-three-domain-frozen-heads.json`

## Где мы сейчас

```text
Completed domain: NX6
Active stage: INT0-RL3-MW10 STAGING
Status: IN PROGRESS
Main changed: NO
NX6 merged into integration: YES
RL3/MW10 merged into staging: NO
Validation gate completed: NO
```

## Подготовка

```text
[done] frozen SHA verified
[done] backup/main-before-int0-20260803 created
[done] integration/c24-nx6-mw10-rl3 created
[done] merge plan committed
[done] frozen-head manifest committed
```

## Завершённый этап NX6

```text
source branch:
feature/nx6-predicted-item-interactions

frozen head:
144adf35cd2151ce5f8572dbbb8ed1b58ccd9778

source PR:
#4 — frozen NX6 → merge/int0-nx6

staging merge commit:
ba485ffafda35579f43ed1bd3e980d7765a784d9

staging validation commit:
02c893d4bb79a2083c83107612083441fde07021

integration PR:
#5 — merge/int0-nx6 → integration/c24-nx6-mw10-rl3

integration merge commit:
312a0b12e5ddb78a2e67ada0b36385c84ed10854

status:
DONE
```

NX6 был объединён двумя merge-коммитами с сохранением полной истории. GitHub подтвердил отсутствие merge-конфликтов. Источник имел независимый статус `ACCEPTED`. В connector-окружении повторный Godot runtime regression не запускался; это явно зафиксировано в `validation/int0-nx6-staging-validation.json`. Полный повторный прогон остаётся обязательным до финальной приёмки INT0.

## Активный этап RL3/MW10

```text
source branch:
feature/rl3-representation-aware-network-streaming

source frozen head:
89ff51b3ee5f66f6548f8b97e271062daf09b5cf

includes:
MW10 + MW9 fix3 + RL2 + RL1 + RL0

staging branch:
merge/int0-rl3-mw10

staging base:
796f0b3708ce6f36ca3692145d4fe718a02d01ff

staging PR:
#6 — INT0-RL3: stage accepted Matter and representation stack

PR state:
OPEN / DRAFT / CONFLICTED

changed files reported by GitHub:
361
```

MW10 отдельно не вливается: frozen RL3 head уже содержит всю принятую matter/representation цепочку.

## Почему PR №6 нельзя сливать автоматически

GitHub показывает `mergeable: false`. Это ожидаемый первый семантический конфликт между сетевой линией NX6 и matter/representation линией RL3.

Особое внимание требуется к:

```text
AGENTS.md
NETWORK_ROADMAP_RU.md
PROJECT_MANIFEST.txt
README_RU.md
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd
tests/runtime/test_m3_graphical_multiplayer_contracts.gd
```

Разрешение целиком через `ours` или `theirs` запрещено.

## Целевая композиция

```text
NX6 сохраняет:
- transport boundary
- fixed-tick player simulation
- prediction and reconciliation
- remote interpolation
- predicted item interactions

RL3 добавляет:
- matter canonical replica integration
- representation manifests
- content-addressed artifact chunks
- cancellation and invalidation
- cache ACK and reconnect reuse
- bandwidth and memory budgets
```

Artifact presentation не становится canonical world state и не должна блокировать movement traffic.

## Следующие действия

```text
1. Получить точный список конфликтующих файлов PR #6.
2. Разобрать каждый общий runtime-файл по ответственности.
3. Создать композиционные исправления только в merge/int0-rl3-mw10.
4. Добиться mergeable state без wholesale ours/theirs.
5. Зафиксировать conflict-resolution commit.
6. Выполнить NX0-NX6 + MW0-MW10 + RL0-RL3 gate.
7. Записать staging validation commit.
8. Merge staging → integration отдельным PR.
```

## Что запрещено сейчас

- не merge-ить RL3 или MW10 непосредственно в `main`;
- не вливать MW10 отдельно;
- не начинать C24 до стабилизации NX6 + RL3;
- не менять frozen RL3 head;
- не выполнять squash/rebase/force-push;
- не утверждать PASS для тестов, которые не запускались;
- не разрешать общие runtime-файлы целиком одной стороной.
