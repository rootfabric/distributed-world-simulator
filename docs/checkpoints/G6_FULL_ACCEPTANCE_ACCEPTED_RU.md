# G6 Full Acceptance — SOURCE_ACCEPTED

**Дата:** 2026-08-09  
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

G6.0–G6.4 приняты. Shared G5 + MW10 baseline интегрирован и является реальным предком G6.

## Финальное решение

```text
G6 Full Acceptance  PASS
G6                  SOURCE_ACCEPTED
```

`MAIN_INTEGRATED`, `COMPOSITION_VERIFIED` и `PRODUCTION_READY` остаются отдельными статусами и этим checkpoint не объявляются.

## Runtime evidence

Полный Windows прогон на Godot `4.7.1.stable.double.custom_build.a13da4feb` прошёл:

```text
G6.0-G6.4 focused chain                PASS
MW10 lock release retry                PASS (12 assertions)
world regression manifest coverage     PASS
RUN_WORLD_REGRESSION_TESTS.ps1         PASS
main_scene_cli_all                      PASS (6 tests, 0 fail)
```

Финальный runtime marker:

```text
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

Runtime-tested head:

```text
c165f797304334d1fbde6e8178fbd143751c1e60
```

## Acceptance Fix3 closeout

После полного зелёного runtime regression final hygiene обнаружил только новый untracked каталог:

```text
?? Microsoft/
```

Это был Windows profile transient, а не runtime regression. Fix3 (`865b907cfb886aec122ed611a82f7dc5cc6bb7b1`) изменил только acceptance harness: каталог удаляется только если его не было до запуска и Git не содержит tracked-файлов под ним.

После Fix3 пользователь подтвердил на head:

```text
04987a5bc8ade0a4aff94671eefac3181156bc60
```

следующее:

```text
post-runtime changed files             4 acceptance/harness/docs files only
PowerShell parser                      PASS
git status --porcelain                 EMPTY
git diff --check G5...G6               PASS
working tree                           CLEAN
```

Поэтому повтор полного world regression не требовался: после уже зелёного runtime-кода production/hydrology/Matter/world runtime не менялись.

## G6.4 graphical/runtime evidence

```text
G6.4 contracts                         PASS — 158
Adaptive Macro Surface                 PASS
far_lod -> near_lod                    1 -> 9
far_triangles -> near_triangles        120 -> 4176
octaves                                8
min_signal_km                          4.688
manual graphical observation           PASS_BY_USER_OBSERVATION
```

## Shared G5 / MW10

```text
repository blob  a25b7d8c358410e60e1bb7db9d3f99333a305a63
retry test blob  afab0c98de45c34dcf6c923d622c84835d428fa5
retry test UID   uid://yush8dg03nlf
```

## Следующий checkpoint

```text
G7 Semantic Field Fabric
```

G7 должен использовать принятые G5 feature identity и G6 hydrology/fluid semantics как upstream truth, не превращая cell/LOD/rendering/network identity в semantic identity.
