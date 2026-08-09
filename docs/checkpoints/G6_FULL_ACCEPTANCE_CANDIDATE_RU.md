# G6 Full Acceptance — FIX3 IMPLEMENTED CANDIDATE

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

G6.0–G6.4 приняты. Shared G5 + MW10 baseline интегрирован. Полный Windows world/core regression уже завершился успешно; остался только post-run hygiene хвост `Microsoft/`, созданный Windows child-process profile handling.

## Full Windows runtime evidence

```text
G6.0-G6.4 focused chain                PASS
MW10 lock release retry                PASS (12 assertions)
world regression manifest coverage     PASS
RUN_WORLD_REGRESSION_TESTS.ps1         PASS
main_scene_cli_all                      PASS (6 tests, 0 fail)
world regression terminal marker       PASS
```

Финальный runtime marker:

```text
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

После этого только final hygiene обнаружил:

```text
?? Microsoft/
```

Функционального runtime regression нет.

## Fix3

`RUN_G6_FULL_ACCEPTANCE.ps1` теперь запоминает, существовал ли `Microsoft/` до запуска. После дочерних процессов каталог удаляется только если:

```text
он отсутствовал до запуска;
он расположен ровно как <repo>/Microsoft;
Git не знает ни одного tracked файла под Microsoft/.
```

Pre-existing и tracked content никогда не удаляется. Fix3 не меняет hydrology, Matter, world runtime или тестовую семантику.

```text
Fix3 commit: 865b907cfb886aec122ed611a82f7dc5cc6bb7b1
```

## Closeout

Полный world regression повторно не требуется, потому что он уже зелёный, а после tested runtime head изменены только acceptance-harness cleanup и validation/docs.

На обновлённом head требуется:

```text
PowerShell parser                PASS
stale Microsoft/ removed         PASS
git status --porcelain           empty
git diff --check G5...G6         empty
```

После этого:

```text
G6 Full Acceptance -> SOURCE_ACCEPTED
G7 Semantic Field Fabric -> START
```

`MAIN_INTEGRATED`, `COMPOSITION_VERIFIED` и `PRODUCTION_READY` остаются отдельными статусами согласно GLOBAL-P0.
