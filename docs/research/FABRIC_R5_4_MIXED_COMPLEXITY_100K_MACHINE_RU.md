# FABRIC R5.4 — Mixed-Complexity 100k Machine

Статус: implementer candidate после merged R5.3 (`044eab40803acf51ffc8bc8ff59ae7e8727947de`).

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

## Global causal event

Отдельный machine-wide reconfiguration намеренно объявлен глобальной причинностью. Для него допустима O(N) structural re-derivation и полный recursive rebuild:

```text
structural parts scanned = 100000
recursive changed nodes = 15
recursive reused nodes = 0
```

Это не маскируется под local scaling. R5.4 таким образом проверяет обе стороны правила: locality когда causal scope локален и глобальное расширение только когда dependency scope действительно global.

## Acceptance

- canonical machine parts = 100000;
- local FULL peak/reconstruction = 20;
- local residual full scans = 0;
- local recursive changed/reused = 4/11;
- global structural scan = 100000;
- global recursive changed/reused = 15/0;
- baseline/final recursive hidden physical = 1812/1852;
- recursive root compile graph = 24;
- recursive executable = 4 equations;
- steady execute performs zero hidden recursive source traversal;
- exact deterministic payload repeats across 3 fresh runs;
- R5.3 and R5.1-100k regressions remain PASS.

## Non-claims

R5.4 не вводит production ownership, persistence/network handoff, universal nonlinear/hybrid recursive reduction или integration в current `main`. После R5.4 нужен `R5 CLOSE`, затем `INTEGRATION-R6`.


## R1 Windows exact falsifier → R2

Fresh Windows exact verification на frozen R1 подтвердил весь runtime/deterministic payload (3 × 1001/0, R5.3 1231/0, R5.1-100k 93/0, Linux/Windows result payload identical), но штатный collector завершился FAIL. Причина: `collect_r5_4_evidence.py` принимал только canonical Linux Godot SHA256 `bfa7ce63…517d7`, тогда как `RUN_FABRIC_R5_4_TESTS.ps1` правильно требует canonical Windows Godot SHA256 `3633c3e6…5a7a5`.

R2 исправляет только evidence identity contract: collector принимает ровно два разрешённых canonical engine SHA (Linux и Windows) при неизменной версии `4.7.1.stable.double.custom_build.a13da4feb`; любой неизвестный SHA остаётся fail-closed. Physics/runtime/acceptance/deterministic payload не меняются. Добавлены unit tests: Linux accepted, Windows accepted, unknown rejected.

После R2 требуются новый exact Linux evidence на R2 HEAD и повтор Windows exact на том же R2 HEAD; R1 runtime PASS не переносится формально на новый HEAD без fresh evidence.
