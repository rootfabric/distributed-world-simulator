# FABRIC R5.6.1 R2 — COM recovery liveness repair: fresh Linux exact

Дата: 2026-10-21. Статус: **IMPLEMENTER_FRESH_LINUX_EXACT_PASS / NOT_MERGE_READY**.

## Идентичность

| Атрибут | Значение |
| --- | --- |
| Репозиторий | `rootfabric/distributed-world-simulator` |
| PR | [#784](https://github.com/rootfabric/distributed-world-simulator/pull/784) — draft |
| PRODUCT_HEAD | `60f193d6602d2d6ebb62393d3db6633b14623627` |
| PRODUCT_TREE | `1a92363e7cc159fef4c42e3443542ebb00a71464` |
| RED parent | `91223acb7bf79c37e12fc11d44054ad3e2732455` |
| Research base | `4f301fae461567362d408a51802cc3dde6730999` |
| Godot | `4.7.1.stable.double.custom_build.a13da4feb` |
| Linux binary SHA256 | `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7` |

Собственный fresh checkout восстановлен **из опубликованного GitHub Actions полного Git bundle** (run `39531287939`, source artifact `12315485919`), а не из implementer worktree. SHA256 обоих архивных объектов совпали с manifest; `git rev-parse HEAD`, TREE, parent и `git diff --check` PASS; tracked tree чист. Windows PowerShell syntax/gate smoke в том же Actions run PASS.

Первая попытка source-carrier для предшествовавшего HEAD `1ad08cae...` обнаружила trailing whitespace в документации (`git diff --check` FAIL). Дефект форматирования исправлен **отдельным docs-only коммитом** без переписывания физического кода, сформирован окончательный frozen HEAD выше, carrier на нём PASS.

## Причина узкого ремонта

Конкретная последовательность допустимых Construction-состояний:

1. Две массы по 1 кг: `x0=1e12`, `x1=x0+1` м. COM безопасен.
2. Владелец делает MOVE_PART → `x1=x0+0.0001220703125` м. Новый source принят, но абсолютный COM не представим в заданном Research Float64 envelope; `query_range()` корректно возвращает `R56_R2_RANGE_CENTER_PRECISION_UNSAFE`.
3. Владелец восстанавливает `x1=x0+1` м. Предыдущий index вызывал **полный query_range для проверки массы** и отказывал до восстановительного update, хотя значение COM требовалось только для публикации descriptor, но **не** для mass ledger.

Исходный самостоятельный численный тест: **RED, 6 проверок / 1 нарушение**, `recovery_error=R56_R2_RANGE_CENTER_PRECISION_UNSAFE`.

**Исправление:** в `apply_owner_verified()` проверяется только нулевой mass-момент дерева Fenwick за `O(log N)`. Сохраняются checksum/revision, проверка источника и частей, конечность массы, совпадение с Matter ledger, проверка узлов до мутации и exactly-once counters. `query_range()` по-прежнему отказывает при непредставимом COM; **COM-допуск 1 мкм не ослаблен**.

## Fresh exact на опубликованном HEAD

Штатный неизменённый `RUN_FABRIC_R5_6_1_R2_TESTS.sh`: **EXIT 0**.

| Gate | Факт |
| --- | --- |
| Cold import / 7 parse | PASS |
| R2 acceptance | **3 × 626/0**, byte-identical payload |
| Scale 5k/20k/100k | **255/0** |
| Numeric conditioning | **54/0** |
| COM representability | **52/0**, unsafe 6/6 rejected, valid 2/2 |
| COM Recovery liveness | **18/0**, unsafe → safe, wrong-matter/stale/replay fail-closed |
| R1 regression / narrow admission | **203/0** / **26/0** |
| BRIDGE-4 | **49/0** |
| Collector | `fabric.r56_r2.dynamic_aggregates.exact_evidence.v4` PASS |
| Collector tamper cases | **21/21 rejected** |
| SHA256SUMS (raw exact) | **21/21 MATCH** |
| HEAD/TREE/Godot SHA before-after | MATCH |

R2 deterministic hash unchanged:
`7fb3eb72caec05dd5341399c8f032f90165a4459610ab3058d798a97fa98dd43`.

## Независимый дополнительный интеграционный falsifier

На отдельном detached worktree с настоящими ConstructionConstructStore, Construction Mutation, Matter и R2 Session выполнен *другой* сценарий той же ошибки (8 деталей, connected bonds, два owner-committed MOVE_PART):

| Коммит | Результат |
| --- | --- |
| Original `91223acb...` | **RED 12 checks / 1 failure**, consumer refused recovery to safe COM |
| Repair `60f193d...` | **GREEN 18/18**, два внешних commit, stale guard, восстановленный COM, масса, replay |

Одинаковый исполняемый GDScript: SHA256 `2f7f4e0dc91fc9cb6dbdf5baeca6f7b337ce4fae308d919eebbc50f9da017ba8`. Тест и raw logs находятся в evidence ZIP, а также будут опубликованы в отдельной review-ветке; они не добавлены в продуктовый PR.

Это **дополнительный reviewer-style test в этой же сессии**, не выдаётся за отдельное независимое заключение другого агента.

## Физические границы и оставшиеся gates

- Стенд — точечные массы без собственного тензора инерции частей, orientation/collision и произвольных topology-split изменений.
- `O(k log N)` — только обновление индекса по k changed parts. Canonical snapshot, source hashing и BRIDGE-4 компиляция всё ещё могут требовать O(N).
- Отказ `R56_R2_RANGE_CENTER_PRECISION_UNSAFE` касается **публикации** Float64 COM, не блокирует легитимный source update/repair.
- Полная независимая научная приёмка, cross-platform Windows exact **на текущем HEAD/TREE**, fresh separate-actor Reviewer + Verifier и отдельное разрешение человека на merge остаются открытыми.

**MERGE_READY=false**, PR #784 DRAFT, `main` не изменена, merge не выполнялся.
