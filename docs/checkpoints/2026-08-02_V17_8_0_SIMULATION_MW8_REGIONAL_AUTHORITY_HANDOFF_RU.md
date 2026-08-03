# Checkpoint v17.8.0 — MW8 regional authority handoff

```text
checkpoint: v17.8.0-simulation-mw8-regional-authority-handoff
build_id:   mw8-regional-authority-handoff
base:       v17.7.0-simulation-mw7-matter-interest-replication
branch:     feature/mw8-regional-authority-handoff
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Реализовано

- непересекающиеся checksum-protected authority regions;
- single-active-owner lease directory;
- `ACTIVE -> PREPARING -> ACTIVE` handoff state machine;
- source freeze до создания transfer package;
- target shadow import с backup и компенсационным rollback;
- persistent snapshot, regional journal и related batch transfer;
- exact MW5 binary64 transport;
- target MW6 stream rebase из imported journal;
- old-owner fencing и new-owner activation по authority epoch;
- exact replay операции после handoff;
- MW7 regional reconnect к новому серверу через filtered snapshot;
- client handoff ticket;
- body-definition/grid-profile/lease binding transfer package;
- transfer fingerprint conflict fence и запрет mixed-level directory regions;
- explicit MW7 interest observer shutdown в focused lifecycle;
- отказ overlapping regions, concurrent transfer и cross-region mutation.

## Focused runner

```text
RUN_MW8_MATTER_HANDOFF_TESTS.ps1
RUN_MW8_MATTER_HANDOFF_TESTS.sh
```

Точное число assertions фиксируется первым независимым successful run.

## Обязательная матрица

```text
MW8 focused:     PASS
MW7 regression:  114/114 PASS
MW6 regression:  130/130 PASS
MW5 regression:  142/142 PASS
MW4 regression:  187/187 PASS
MW3 regression:  7519/7519 PASS
MW2 regression:  7470/7470 PASS
MW1 regression:  3685/3685 PASS
MW0 regression:  2011/2011 PASS
M6 standalone:   10/10 PASS
A3 full profile: 3 consecutive PASS
git diff --check: PASS
```

## Focused-сценарии

1. Active source принимает mutation, target до handoff отклоняет.
2. `PREPARING` одновременно замораживает source и не активирует target.
3. Abort возвращает source lease в `ACTIVE`.
4. Ошибка target rebase полностью откатывает imported store/receiver/journal.
5. Успешный commit переносит snapshot, journal и batches.
6. Directory меняет owner и epoch ровно один раз.
7. Старый owner после commit не может писать.
8. Новый owner обслуживает exact replay без нового stream delta.
9. Новая mutation после handoff создаёт следующий target sequence.
10. MW7 client подключается к target и получает transferred regional snapshot.
11. Overlapping region и concurrent transfer отклоняются.
12. Mutation через две authority-regions отклоняется до domain execution.
13. Пакет другого body definition или lease revision отклоняется до import.
14. Повтор transfer ID с иным target fingerprint отклоняется.
15. Mixed-level authority region отклоняется до регистрации.
16. Source/target interest observers явно освобождаются перед завершением runner.

## Изоляция

Не изменяются production Moon, world catalog и существующие MW0–MW7 wire schemas. Новый gate в MW6 authority опционален и не влияет на прежние single-server тесты без конфигурации MW8.
