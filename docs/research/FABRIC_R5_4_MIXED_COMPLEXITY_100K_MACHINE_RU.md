# FABRIC R5.4 — Mixed-Complexity 100k Machine

Статус: R3 repair candidate после merged R5.3 (`044eab40803acf51ffc8bc8ff59ae7e8727947de`). Независимая приёмка и merge не заявляются; результаты exact-прогонов публикуются в PR #743 с точным HEAD/TREE.

## Цель

R5.4 объединяет уже закрытые оси R5:

- R5.1: canonical structural `N=100000` и bounded local FULL=20;
- R5.2: qualitative complexity compression / NO_SAFE_BAKE discipline;
- R5.3: recursive `component → module → assembly → machine ROM` и causal rebuild.

Это не новый physics kernel. R5.4 — верхний mixed-machine orchestration/falsifier, который использует существующие R5.1/R5.3 пути без изменения их закрытых контрактов.

## Subject

```text
100,000 canonical structural parts (R5.1 source)
+
4-level recursive exact-linear subsystem (R5.3)
  8 leaves / 4 modules / 2 assemblies / 1 machine
  baseline hidden physical components = 1812
  root compile graph = 24 components
  root executable = 4 equations
```

Structural и recursive subjects принадлежат разным physical representations/domains, поэтому не дублируют ownership одних и тех же records.

## Local causal event

Локальное повреждение открывает ровно 20 structural parts и одновременно инвалидирует один recursive leaf dependency:

```text
structural: FULL peak = 20
structural residual metadata full scans = 0
recursive changed nodes = leaf + module + assembly + machine = 4
recursive reused nodes = 11
hidden recursive physical complexity = 1812 → 1852
root compile graph = 24
root executable = 4 equations
```

То есть expensive detail растёт только в causal workset; остальные 99k+ structural records и 11 recursive nodes остаются compact/reused.

## Recursive-global revision и отдельный контрольный обход

R2 ошибочно называл полное чтение неизменённой structural source глобальным физическим событием. Исполняемый reviewer falsifier в PR #743, comment 6016469344, опроверг это: structural revision, checksum, transitions и applied events не менялись. Старые Linux/Windows PASS не закрывают эту семантическую ошибку.

R3 использует явно разрешённый reviewer вариант разделения двух операций:

```text
global_reconfigure():
  реальная смена source revisions всей recursive hierarchy
  recursive changed/reused = 15/0
  structural parts scanned = 0
  structural source + capsule + runtime + ownership = UNCHANGED

explicit_global_control_scan():
  non-causal O(N) aggregate control
  structural parts scanned = 100000
  physical machine identity / source / runtime / events = UNCHANGED
  меняется только диагностический счётчик контрольного обхода
```

Это **не** доказательство физической причины, которая требует раскрытия всех 100k structural parts. Такой mixed-domain global causal event данным fixture не моделируется. Его нельзя объявлять пройденным по результату control scan или подменять изменением counters.

## Атомарное локальное событие

`local_damage_and_refine()` сначала восстанавливает capsule в отдельном R5.1 lifecycle, затем полностью выполняет на нём UNBAKE → canonical break observation → ReBAKE. Live structural source/runtime остаются прежними. После построения recursive candidate вызывается неизменённый транзакционный R5.3 `refresh`; только после его успеха устанавливаются готовые structural runtime/source и event/work counters. После успешного refresh нет отклоняемой операции над кандидатом.

Range index переиспользуется только для чтения; его полный снимок также проверяется отрицательными тестами. Перенос capsule сохраняет work counters и execution-slot history. Физические kernels и R5.1/R5.3 contracts не редактируются.

Fixture одноразовый: initialize → local event → recursive-global revision. Неинициализированные вызовы, преждевременный global, повтор local/global и local после global отклоняются без изменения состояния. Это ограничение конкретного research fixture, не новый production event owner.

### Исполняемые проверки отказов

Acceptance-only subclasses вводят отказы **после настоящих inherited операций**: restore, UNBAKE, canonical break observation, ReBAKE, а также при подготовке leaf после трёх prepared ancestors внутри настоящего R5.3 refresh. Дополнительно проверяется реальный отказ admission повреждённого range-index schema. В product runtime нет fault flags; два обычных instance factory метода позволяют подставить subclasses в тесте.

Каждый из 11 отклонённых initialized events сравнивает полный снимок обеих live representations: source, index, structural capsule, status/ownership, recursive root, sessions, bundles, hashes, ready-state, instance identities, work/event counters и machine identity. После отказов выполняется успешный retry. Ещё три cold entrypoints обязаны отклоняться без изменения состояния.

## Acceptance

- canonical machine parts = 100000;
- local FULL peak/reconstruction = 20;
- local residual full scans = 0;
- local recursive changed/reused = 4/11;
- recursive-global structural scan = 0; полный structural state неизменён;
- explicit non-causal control scan = 100000; physical state/identity неизменны;
- 11 rejected initialized events / 11 полных неизменённых снимков;
- 3 uninitialized rejections без изменения состояния;
- global recursive changed/reused = 15/0;
- baseline/final recursive hidden physical = 1812/1852;
- recursive root compile graph = 24;
- recursive executable = 4 equations;
- steady execute performs zero hidden recursive source traversal;
- exact deterministic payload repeats across 3 fresh runs;
- R5.3 and R5.1-100k regressions remain PASS.

## Non-claims

R5.4 не вводит production ownership, persistence/network handoff, universal nonlinear/hybrid recursive reduction или integration в current `main`. Не доказана structural-global physical causality. После независимого решения по R5.4 нужен `R5 CLOSE`, затем `INTEGRATION-R6`.

`local_metadata_parts_scanned = 0` относится к residual aggregate queries внутри lifecycle. Это **не** end-to-end O(1): неизменённый `Source.create_subject()` строит canonical fixture с expanded source digests за O(N). Создание source fixture, тестовые полные снимки и контрольный обход не выдаются за стоимость compact physical execution.


## R1 Windows exact falsifier → R2

Fresh Windows exact verification на frozen R1 подтвердил весь runtime/deterministic payload (3 × 1001/0, R5.3 1231/0, R5.1-100k 93/0, Linux/Windows result payload identical), но штатный collector завершился FAIL. Причина: `collect_r5_4_evidence.py` принимал только canonical Linux Godot SHA256 `bfa7ce63…517d7`, тогда как `RUN_FABRIC_R5_4_TESTS.ps1` правильно требует canonical Windows Godot SHA256 `3633c3e6…5a7a5`.

R2 исправляет только evidence identity contract: collector принимает ровно два разрешённых canonical engine SHA (Linux и Windows) при неизменной версии `4.7.1.stable.double.custom_build.a13da4feb`; любой неизвестный SHA остаётся fail-closed. Physics/runtime/acceptance/deterministic payload не меняются. Добавлены unit tests: Linux accepted, Windows accepted, unknown rejected.

После R2 требуются новый exact Linux evidence на R2 HEAD и повтор Windows exact на том же R2 HEAD; R1 runtime PASS не переносится формально на новый HEAD без fresh evidence.


## R3 evidence contract и граница приёмки

R3 вводит `fabric.r5_4.mixed_complexity_100k.result.v2` и `fabric.r5_4.exact_evidence.v2`. Старый R1/R2 result v1 не принимается новым collector. Точные predicates включают 1048 assertions, local 20 / 4 changed / 11 reused, recursive-global 15/0 с structural scan=0, отдельный control=100000, 11/11 rollback и три cold rejection.

Collector проверяет форму и типы полей, отсутствие failures, ровно один result/PASS/hash marker, совпадение указанного hash с полным result, одинаковые payload трёх samples, exact engine identity до/после, R5.3 1231/0 и R5.1-100k 93/0, import/parse и Python contract. Duplicate JSON keys, nonfinite числа, bool/float вместо integer counters, старый schema, неполный rollback, ложная structural causality и физическое изменение при control отвергаются. Unit tests вызывают настоящий collector на временных synthetic campaigns; они не являются runtime evidence.

Предварительный implementer Linux run: 1048/0; Python collector tests: 28/28. Предварительный deterministic hash:

```text
2e099bd76c89edf9abe75663e0eee6317170d1d9fd72ffc13cb5400306e822db
```

Этот результат не заменяет fresh 3× exact campaign на опубликованном R3 HEAD, Windows reproduction, fresh adversarial Reviewer и independent Verifier. Implementer не выпускает собственный independent verdict. Merge остаётся отдельным человеческим решением.
