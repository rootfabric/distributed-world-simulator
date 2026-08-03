# INT0 — текущий статус интеграции

**Обновлено:** 2026-08-03 20:40 UTC+10  
**Основной план:** `docs/plans/THREE_DOMAIN_INTEGRATION_MERGE_PLAN_RU.md`  
**Machine-readable manifest:** `validation/int0-three-domain-frozen-heads.json`

## Где мы сейчас

```text
Completed domain: NX6
Active stage: INT0-RL3-MW10 VALIDATION
Status: COMPOSED STAGING CANDIDATE
Main changed: NO
NX6 merged into integration: YES
RL3/MW10 merged into staging: YES
RL3/MW10 merged into integration: NO
Full staged-tree validation gate: PENDING
```

## Завершённый этап NX6

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

## Активный этап RL3/MW10

```text
accepted frozen head:
89ff51b3ee5f66f6548f8b97e271062daf09b5cf

includes:
MW10 + MW9 fix3 + RL2 + RL1 + RL0

staging branch:
merge/int0-rl3-mw10

conflict-neutralization branch:
merge/int0-rl3-mw10-resolved

resolution commit:
c2e7c1e91993add2dd7aa9387519a391dfbb91ce

resolution PR:
#7 — MERGED

RL3/MW10 staging merge:
515b179d276c59df1624fe640eb04464410bf974

runtime composition:
ba1127ab24c4af0493d7445539387b9e9fee219a

validation update:
fcf1a1d121e90afc05f6fd810656a5f8d32868c4

integration PR:
#8 — OPEN / DRAFT / MERGEABLE
```

MW10 отдельно не merge-ится: frozen RL3 head уже содержит всю принятую matter/representation цепочку.

## Разрешение конфликтов

Трёхсторонний анализ от общего предка
`e12e8a1c8bc949180ab9041fa4db308baf3dd11e` выявил ровно шесть пересечений:

```text
AGENTS.md
NETWORK_ROADMAP_RU.md
PROJECT_MANIFEST.txt
README_RU.md
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
tests/runtime/test_m3_graphical_multiplayer_contracts.gd
```

Стратегия:

```text
1. сохранить все non-conflicting RL3/MW10 blobs byte-exact;
2. временно нейтрализовать только шесть пересечений до NX6-версии;
3. выполнить чистый merge;
4. вернуть нужную RL3 runtime-семантику отдельным композиционным commit;
5. не применять wholesale ours/theirs.
```

## Runtime-композиция

Exact NX6 M3 client runtime сохранён как:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd
```

Production `m3_graphical_client_runtime.gd` является узким adapter поверх NX6 и добавляет только bounded recovery:

```text
MULTIPLAYER_DELTA_BASE_MISMATCH
→ pending replica resync
→ authoritative full snapshot
→ pending cleared
```

Не изменены:

- authority;
- transport/channel ownership;
- fixed-tick simulation;
- prediction/reconciliation;
- Item Graph и predicted-item paths;
- replica revision/checksum fences.

Добавлена bounded telemetry:

```text
pending_replica_resync
delta_base_mismatches
snapshot_resyncs
```

Подробности: `docs/plans/INT0_RL3_MW10_COMPOSITION_RU.md` в staging-ветке.

## Текущая проверка

```text
GitHub conflict resolution: PASS
remaining GitHub merge conflicts: 0
PR #8 mergeable: YES
isolated Godot 4.7.1 double adapter syntax parse: PASS
full staging editor import: NOT RUN
focused staging contract: NOT RUN
combined Network/Matter/RL regression: NOT RUN
```

Изолированный syntax fixture не заменяет проверку полного дерева.

## Gate перед merge PR №8

```text
Godot editor import on full staging tree
INT0 focused composition contract — expected 12 assertions
NX0–NX6 regression
M7 playable contracts
M7 graphical multiprocess
M7 recovery
MW0–MW10 regression
MW9 fix3 race/recovery
MW8 98/98
RL0–RL3 regression
Dedicated server + two clients
Reconnect/full-resync
Network condition profiles
World regression
Main-scene CLI
git diff --check
conflict markers = 0
remaining Godot/Xvfb = 0
```

## Следующее действие

```text
1. Запустить полный staged-tree gate на merge/int0-rl3-mw10.
2. Записать фактические результаты в validation/int0-rl3-mw10-staging-validation.json.
3. Только после PASS перевести PR #8 из draft.
4. Merge PR #8 методом merge commit.
5. Отметить RL3/MW10 DONE.
6. Создать merge/int0-c24.
```

## Что запрещено сейчас

- не merge-ить PR №8 до полного staged-tree gate;
- не merge-ить RL3 или MW10 непосредственно в `main`;
- не вливать MW10 отдельно;
- не начинать C24 до стабилизации NX6 + RL3;
- не менять frozen RL3 head;
- не выполнять squash/rebase/force-push;
- не утверждать PASS для тестов, которые не запускались.
