# INT0 — текущий статус интеграции

**Обновлено:** 2026-08-03 19:44 UTC+10  
**Основной план:** `docs/plans/THREE_DOMAIN_INTEGRATION_MERGE_PLAN_RU.md`  
**Machine-readable manifest:** `validation/int0-three-domain-frozen-heads.json`

## Где мы сейчас

```text
Stage: INT0-NX6 STAGING
Status: IN PROGRESS
Main changed: NO
Production merge completed: NO
Validation gate completed: NO
```

Подготовительный этап завершён:

```text
[done] frozen SHA verified
[done] backup/main-before-int0-20260803 created
[done] integration/c24-nx6-mw10-rl3 created
[done] merge plan committed
[done] frozen-head manifest committed
```

Активный первый доменный этап:

```text
source branch:
feature/nx6-predicted-item-interactions

source frozen head:
144adf35cd2151ce5f8572dbbb8ed1b58ccd9778

staging branch:
merge/int0-nx6

staging PR:
#4 — INT0-NX6: stage accepted NX6 network stack

PR state:
OPEN / DRAFT / MERGEABLE
```

## Что уже сделано в этапе NX6

- создана отдельная staging-ветка от документированной integration-базы;
- открыт draft PR frozen NX6 → staging;
- GitHub подтвердил отсутствие merge-конфликтов;
- head PR совпадает с accepted SHA;
- merge ещё не выполнен;
- `main` и integration production tree не изменены.

## Текущий блокирующий gate

До merge PR №4 необходимо выполнить и документировать:

```text
Editor import
NX0–NX6
M7 playable contracts
M7 graphical multiprocess
M7 recovery
Network full regression
World regression
Main-scene CLI
git diff --check
conflict markers = 0
remaining Godot/Xvfb = 0
```

После PASS последовательность такая:

```text
1. merge PR #4 методом merge commit в merge/int0-nx6
2. записать validation commit на staging-ветке
3. открыть PR merge/int0-nx6 → integration/c24-nx6-mw10-rl3
4. проверить diff и результаты gate
5. merge staging PR в integration
6. отметить INT0-NX6 DONE
7. создать merge/int0-rl3-mw10
```

## Что запрещено сейчас

- не merge-ить NX6 непосредственно в `main`;
- не начинать RL3/MW10 до прохождения NX6 gate;
- не менять frozen NX6 head;
- не выполнять squash/rebase/force-push;
- не утверждать PASS для тестов, которые не запускались.
