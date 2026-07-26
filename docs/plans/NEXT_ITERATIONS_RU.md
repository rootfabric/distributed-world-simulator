# Ближайшие итерации после v15.2

## v15.2.1 — валидация terrain cache

- выполнить полёт на 2–5 км и возврат к маякам;
- подтвердить `project_version=15.2` в startup-log;
- подтвердить `terrain_surface_cached` при уходе;
- подтвердить `terrain_pinned_cache_return_triggered` и `terrain_surface_cache_hit` при возврате;
- измерить `total_cache_activation_ms`;
- проверить, что движение от маяка не вызывает обратное переключение pinned-cell;
- оценить размер RAM при 8 обычных и нескольких pinned cells.

Решения по результатам:

- уменьшить или увеличить `recent_surface_cache_capacity`;
- изменить `pinned_return_trigger_distance_m`;
- при длинном cache activation разбить создание CollisionShape3D-узлов на несколько кадров.

## v15.3 — First-person Interaction

- центральный raycast из активной камеры;
- контракт `Interactable`;
- действие `E`;
- информация о Survey Beacon;
- outline/подсветка объекта;
- начало placement preview.

## v16 — первая локальная база

- Foundation;
- Solar Panel;
- Battery;
- Charging Dock;
- preview и проверка уклона;
- sockets и простой power graph;
- сохранение через существующий persistent layer.

## Параллельный долг по фундаменту

### Chunk Lifecycle

1. Явные состояния `Dormant`, `Warm`, `Active`, `Unloading`.
2. В Warm хранить только EntityRecord без физического узла.
3. В Active создавать визуальную сцену и коллизию.
4. Очередь создания сущностей по frame budget.
5. Метрики чтения JSON и создания runtime scenes.

### Terrain Streaming

1. Clipmap rings вместо единого LOCAL ArrayMesh.
2. Низкоприоритетная очередь декоративных камней.
3. Удаляемый disk cache, отделённый от авторитетного мира.
4. Ограничение памяти по оценочному размеру, а не только числу cells.

### Controller Layer

1. equipment slots;
2. сохранение выбранного профиля;
3. отдельные wheel/track/flight contracts для Robot Actor.
