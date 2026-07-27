# Checkpoint v16.3.3 Part 3 fix2 — Presentation and raw SpatialRef boundary

**Версия:** `v16.3.3-foundation-world-aggregate-part3-fix2`
**Build ID:** `foundation-world-aggregate-presentation-spatial-boundary-fix2`
**Основа:** `v16.3.3-foundation-world-aggregate-part3-fix1`

## Причина fix2

Повторное ревью выявило два обхода presentation-free boundary и расхождение между raw-входом aggregate и строгой snapshot-схемой. `Dictionary` проверял только значения, metadata service objects не инспектировалась, а quaternion нормализовался до строгой проверки.

## Исправления

1. `SimulationKernel` рекурсивно проверяет и ключи, и значения каждого `Dictionary`. Presentation node не может быть спрятан в ключе.
2. Для каждого `Object` проверяются `get_meta_list()` и `get_meta()`; presentation node внутри metadata отклоняется так же, как script field или child node.
3. `WorldEntityAggregate.setup()` выполняет `raw validate → canonicalize → validate candidate`. Quaternion вне допустимой единичной нормы отклоняется до нормализации.
4. `apply_spatial_state()` использует тот же порядок и при отказе не меняет spatial state или revision.
5. Канонизация знака `q/-q` и устранение малых численных отклонений сохраняются только для уже валидного near-unit quaternion.

## Инварианты

- `presentation_free=true` означает отсутствие presentation objects в service graph, включая Dictionary keys и metadata.
- Aggregate не принимает raw SpatialRef, который строгая snapshot boundary отклоняет.
- Отказ raw spatial validation не оставляет частично инициализированное или частично обновлённое состояние.

## Приёмочные сценарии

- `Camera2D` как ключ словаря возвращает `PRESENTATION_OBJECT_REJECTED`;
- `Camera2D` в metadata `RefCounted` возвращает `PRESENTATION_OBJECT_REJECTED`;
- `[0,0,0,2]` отклоняется в `setup()` до инициализации aggregate;
- `[0,0,0,2]` отклоняется в `apply_spatial_state()` без изменения state/revision;
- unit `q` и `-q` по-прежнему канонизируются детерминированно;
- профиль Part 3, полный regression, main scene и process-level simulation-server остаются зелёными.
