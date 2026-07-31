# Checkpoint v17.3.0 — MW3 local meshing fix1

## Статус

```text
checkpoint: v17.3.0-simulation-mw3-local-meshing
delivery: fix1
build_id: mw3-local-meshing-fix1
base: v17.2.0-simulation-mw2-sparse-bricks / fix1
branch: feature/mw3-local-meshing
status: CANDIDATE FOR INDEPENDENT REVIEW
```

`fix1` закрывает два блокирующих замечания independent review первоначального MW3. Граница этапа не расширена: canonical matter MW0–MW2, Луна, production world catalog, persistence, network authority и mutation semantics не изменяются.

## 1. Исправление streamer lifecycle

Первоначальный `MatterLocalMeshStreamer.configure()` сразу вызывал `refresh_now()`, а тот читал `observer.global_position` и использовал `to_local()`. После `add_child()`, но до гарантированной готовности `Node3D` в `SceneTree`, Godot 4.7.1 double мог вернуть некорректное состояние transform. После этого пустой `observer_cell` использовался как полноценный DTO.

`fix1` полностью убирает зависимость первого refresh от `global_position`:

```text
observer local transform
        ↓ parent-chain composition
observer transform in common root
        ↓
streamer transform in common root
        ↓ affine inverse
observer position in streamer/body-local space
```

Свойства исправления:

- работает до `_ready()`, если observer и streamer уже имеют общую parent-цепочку;
- не требует доступа к `global_transform`/`global_position`;
- отклоняет разные roots с `MW3_STREAMER_OBSERVER_SPACE_MISMATCH`;
- проверяет пустой `observer_cell` до чтения `address_id`;
- сохраняет исходную семантику: observer вне root отклоняет конфигурацию;
- добавляет явный `refresh_at_body_local_position()` для тестов и будущих body-frame adapters.

## 2. Исправление seam result envelope

Первоначальный validator возвращал counts через стандартный вызов:

```text
MatterContractUtils.success({ ... })
```

Следовательно, значения находились в `result.details`. Focused-тест ошибочно читал `boundary_*_count` как top-level поля и всегда получал `0`, хотя независимая численная модель и реальные mesh signatures содержали 17 boundary vertices и 16 segments.

`fix1` исправляет тест на чтение:

```text
seam.details.boundary_vertex_count
seam.details.boundary_normal_count
seam.details.boundary_segment_count
```

## 3. Запрет пустого seam

Дополнительно закрыта реальная слабость validator: два одинаковых пустых набора больше не считаются доказанным seam.

Если хотя бы один обязательный набор пуст:

- boundary vertices;
- boundary normals;
- boundary segments,

validator возвращает:

```text
MATTER_MESH_SEAM_INTERSECTION_MISSING
```

Focused-тест содержит отдельный отрицательный сценарий с плоскостью вне mesh surface.

## 4. Тестовая топология

Ожидаемый focused-профиль после добавления отрицательного seam-сценария:

```text
MW3: 7519 assertions
MW2: 7470 assertions
MW1: 3685 assertions
MW0: 2011 assertions
A3:  12/12
M6:  10/10
```

## 5. Критерии приёмки

`fix1` принимается только после выполнения всех условий:

1. `RUN_MW3_LOCAL_MESHING_TESTS` — `7519/7519 PASS`.
2. Streamer конфигурируется в focused-тесте до готовности добавленных `Node3D`.
3. Observer вне root корректно отклоняется без invalid dictionary access.
4. Synthetic seam возвращает ненулевые counts из `details`.
5. Real asteroid seam возвращает ненулевые counts из `details`.
6. Два пустых seam-набора отклоняются с failure.
7. MW0–MW2, A3 и M6 regression проходят.
8. `git diff --check` проходит.
9. В лабораторной сцене `failed_brick_count = 0`.
