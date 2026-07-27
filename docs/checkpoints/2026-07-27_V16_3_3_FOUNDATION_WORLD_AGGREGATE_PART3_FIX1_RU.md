# Checkpoint v16.3.3 Part 3 fix1 — Transactional aggregate boundary

**Версия:** `v16.3.3-foundation-world-aggregate-part3-fix1`
**Build ID:** `foundation-world-aggregate-transactional-boundary-fix1`

## Причина fix1

Ревью выявило три непокрытых границы: частичную live-миграцию WORLD relations, возможность создать aggregate с несохраняемым `SpatialRef` и неполную рекурсивную проверку presentation-free kernel.

## Исправления

1. `WorldEntityStore.migrate_legacy_item_relations()` сначала строит staged store и список relation updates. Live store и ItemInstance изменяются только после полной проверки всех WORLD items.
2. `ItemGraphPersistence.create_snapshot_result()` останавливает создание snapshot при ошибке миграции; `save()` возвращает точную ошибку и не продолжает запись.
3. `WorldEntityAggregate.setup()`, `validate()` и `apply_spatial_state()` используют строгую сохраняемую схему `SpatialRef`: точные поля, полные массивы, конечные безопасные числа и канонический quaternion.
4. `SimulationKernel` отклоняет `Camera2D`, все варианты `AudioStreamPlayer`, listeners/lights/environment и рекурсивно инспектирует script-поля service objects и дочерние Node.
5. Удалена лишняя пустая строка в `item_state_store.gd`; `git diff --check` входит в проверку пакета.

## Приёмочные сценарии

- валидный legacy item перед ошибочным item не оставляет aggregate или переписанную relation;
- snapshot creation fail-closed не изменяет live domain;
- aggregate с неизвестным полем или неполным `SpatialRef` не создаётся;
- отклонённый spatial update не меняет state/revision;
- presentation object внутри произвольного RefCounted service обнаруживается;
- полный regression и process-level simulation-server остаются зелёными.
