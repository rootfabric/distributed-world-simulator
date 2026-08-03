# INT0 — текущий статус интеграции

**Обновлено:** 2026-08-03 20:50 UTC+10  
**Основной план:** `docs/plans/THREE_DOMAIN_INTEGRATION_MERGE_PLAN_RU.md`  
**Machine-readable manifest:** `validation/int0-three-domain-frozen-heads.json`

## Где мы сейчас

```text
Completed domain candidate: NX6
Completed composed candidate: RL3/MW10
Active stage: INT0-C24 STAGING
Status: IN PROGRESS
Main changed: NO
NX6 merged into integration: YES
RL3/MW10 merged into integration: YES — COMPOSED CANDIDATE, NOT ACCEPTED
C24 merged into staging: NO
Combined INT0 runtime gate: PENDING
```

## Защитные точки

```text
main backup:
backup/main-before-int0-20260803

integration before RL3:
backup/int0-before-rl3-integration-20260803
→ 218e44fcdb5b0574a7931003dbc1952bed7aadff

RL3/MW10 staged candidate:
checkpoint/int0-rl3-mw10-composed-candidate
→ fcf1a1d121e90afc05f6fd810656a5f8d32868c4
```

## NX6

```text
frozen head:              144adf35cd2151ce5f8572dbbb8ed1b58ccd9778
source → staging PR:      #4
staging merge:            ba485ffafda35579f43ed1bd3e980d7765a784d9
staging validation:       02c893d4bb79a2083c83107612083441fde07021
staging → integration PR: #5
integration merge:        312a0b12e5ddb78a2e67ada0b36385c84ed10854
stage close:              796f0b3708ce6f36ca3692145d4fe718a02d01ff
status:                   DONE
```

## RL3/MW10

```text
accepted frozen head:     89ff51b3ee5f66f6548f8b97e271062daf09b5cf
includes:                 MW10 + MW9 fix3 + RL2 + RL1 + RL0
superseded conflicted PR: #6
resolution commit:        c2e7c1e91993add2dd7aa9387519a391dfbb91ce
resolution PR:            #7
staging merge:            515b179d276c59df1624fe640eb04464410bf974
runtime composition:      ba1127ab24c4af0493d7445539387b9e9fee219a
staging validation head:  fcf1a1d121e90afc05f6fd810656a5f8d32868c4
staging → integration PR: #8
integration merge:        60feb1cbc07a6617e498d65efcc9f747f68eaff7
classification:           COMPOSED CANDIDATE, NOT ACCEPTED
```

Трёхсторонний анализ выявил шесть пересечений. Все остальные Matter/Representation blobs сохранены byte-exact. Wholesale `ours`/`theirs`, squash, rebase и force-push не применялись.

Production `m3_graphical_client_runtime.gd` остаётся узким adapter поверх точной NX6-реализации `m3_graphical_client_runtime_nx6.gd`. Добавлен только bounded resync после `MULTIPLAYER_DELTA_BASE_MISMATCH`; authority, fixed tick, prediction, Item Graph и checksum/revision fences не изменены.

Доступная проверка:

```text
GitHub conflict resolution: PASS
remaining merge conflicts: 0
isolated Godot 4.7.1 double syntax fixture: PASS
full integration runtime gate: NOT RUN / PENDING
```

Перенос в integration не является решением ACCEPTED. Полный совместный gate обязателен до INT0 checkpoint и до любого merge в `main`.

## Активный этап C24

```text
source branch:
feature/c24-gpu-ready-proxy-mesh-backend

frozen accepted head:
c18b3afaf0f2f078899be20d0529fa94d53adf90

staging branch:
merge/int0-c24

base:
текущая integration/c24-nx6-mw10-rl3 после merge commit 60feb1cbc07a6617e498d65efcc9f747f68eaff7 и status commits
```

C24 должен добавляться поверх уже скомпонованных NX6 + RL3/MW10. Особое внимание:

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

## Правила C24-композиции

```text
NX6 owns:
transport, fixed tick, prediction/reconciliation, remote interpolation,
predicted item interaction presentation.

RL3/MW10 owns:
Matter canonical domain, representation manifests/artifacts,
cache/invalidation and bounded representation delivery.

C24 owns:
authoritative Item Graph/Construction state,
construction operations and GPU-ready proxy mesh materialization.
```

C24 не должен обходить NX6 command bridge и не должен превращать proxy mesh в canonical state. Унификация C24 proxy backend с RL3 generic artifact transport выполняется только через явные adapters.

## Следующие действия

```text
1. Создать merge/int0-c24 от текущей integration-головы.
2. Открыть frozen C24 → staging draft PR.
3. Получить точный список конфликтов.
4. Перенести все неконфликтующие C24 blobs без изменения.
5. Скомпоновать общие runtime/Item Graph/manifest файлы отдельными commits.
6. Добавить C24 staging validation record.
7. Перенести C24 candidate в integration отдельным merge commit.
8. Запустить единый INT0 gate: NX0–NX6 + MW0–MW10 + RL0–RL3 + C1–C24 + World + main scene.
9. Только после полного PASS оформлять INT0 acceptance и PR в main.
```

## Что запрещено

- не менять `main` до независимого INT0 acceptance;
- не утверждать, что RL3/MW10 или C24 integration accepted без полного общего gate;
- не вливать MW10 отдельно;
- не менять frozen C24 head;
- не выполнять squash/rebase/force-push;
- не разрешать общие runtime-файлы wholesale одной стороной;
- не скрывать отсутствующие runtime-прогоны.
