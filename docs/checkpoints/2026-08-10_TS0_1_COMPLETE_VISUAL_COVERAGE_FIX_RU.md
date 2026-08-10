# TS0.1 — Complete Visual Coverage Fix

**Дата:** 2026-08-10  
**Ветка:** `feature/ts0-large-structural-visual-lab`  
**Статус:** `IMPLEMENTED — WINDOWS REVALIDATION REQUIRED`

## Причина

Ручная графическая проверка показала две разные проблемы.

1. C24 ArrayMesh использовал обратный для Godot front-face winding. Это исправлено отдельным C24 fix: stored normals остаются наружу, triangle indices теперь `GODOT_CLOCKWISE`.
2. После winding fix `FAR` показывал полную конструкцию, но `MID` и `NEAR` показывали только ближайшие 12 секций. Для `PYRAMID_10K` это означало 12 из 40 секций и визуально обрезанную пирамиду.

Вторая проблема не является допустимой production-моделью HLOD. Interest/refinement может менять детализацию, но не имеет права оставлять части конструкции без representation.

## Новый invariant

```text
COMPLETE_VISUAL_COVERAGE_REQUIRED
```

На каждом активном HLOD уровне вся canonical форма конструкции должна иметь визуальное покрытие.

```text
FAR  -> полный root shell
MID  -> все section artifacts TS0.1
NEAR -> все section artifacts TS0.1; local refinement reserved
```

LOD может менять число meshes, triangles, collision detail и material detail, но не должен превращать полную пирамиду в локальный срез.

## TS0.1 реализация

Для 10k fixtures используется ограниченный flat complete-coverage режим:

- `CUBE_10K`: 27 section artifacts;
- `PYRAMID_10K`: 40 section artifacts;
- hard limit: 64 sections.

Adapter для `MID/NEAR` теперь:

1. собирает все `section_id` из C22 manifest;
2. передаёт их explicit `visible_section_ids`;
3. ставит `max_section_artifacts = total_section_count`;
4. fail-closed, если `total_section_count > 64`.

Это позволяет TS0.1 проверить правильный whole-object coverage, но не превращает flat-all-sections в стратегию масштабирования.

## TS0.2 архитектурное требование

100k gate не имеет права просто поднять flat limit.

TS0.2 должен ввести hierarchical coverage:

```text
root shell
  -> coarse clusters
      -> section clusters
          -> sections
              -> local exact detail
```

Для каждой области конструкции одновременно выбирается один подходящий representation level. Refinement заменяет coarse representation локально; непокрытых регионов быть не должно.

## Acceptance после fix

Focused gate должен доказать для обоих 10k profiles:

```text
FAR:
  proxy meshes == 1
  visible sections == 0
  whole shape complete

MID/NEAR:
  visible sections == total sections
  proxy meshes == total sections
  total sections <= 64
  whole shape complete

all modes:
  canonical checksum invariant
  C24 ArrayMesh backend
  runtime nodes << canonical part count
```

Ручная проверка должна визуально подтвердить, что `CUBE_10K` остаётся кубом, а `PYRAMID_10K` остаётся полной пирамидой на кнопках `3`, `4`, `5`.

## Коммиты

```text
89e3fa8 fix(c24): use Godot clockwise proxy winding
3ee0112 test(c24): assert Godot clockwise front-face winding
aef8ba9 fix(ts0): require complete visual coverage
ed1e70e fix(ts0): keep near and mid coverage complete
4ce372e test(ts0): require complete section coverage
fd1dde0 validation(ts0): require complete HLOD coverage
```

`SOURCE_ACCEPTED` остаётся `false` до нового Windows focused PASS, ручного graphical PASS и полного world regression.
