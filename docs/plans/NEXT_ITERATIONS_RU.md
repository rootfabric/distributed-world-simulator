# Ближайшие итерации после v15

## v15.1 — анализ реальных performance logs

- пройти 2–5 км пешком и на джетпаке;
- выполнить несколько разворотов во время GENERATING;
- сопоставить `long_frame_detected` с `terrain_commit_stage`;
- определить долю CPU generation, ArrayMesh, collision и rocks;
- зафиксировать baseline для компьютера тестирования.

## v15.2 — устранение подтверждённого main-thread bottleneck

При доминировании `collision_shape`:

- разбить collision на небольшие tiles;
- подключать ближайшие tiles раньше дальних;
- заменять только вышедшие tiles;
- оставить визуальную и физическую поверхность основанными на одинаковых samples.

При доминировании `local_mesh_resource`:

- разделить LOCAL на concentric clipmap rings;
- создавать по одному ring resource за кадр;
- выполнять swap только после готовности критического внутреннего ring.

При доминировании `rock_descriptors` или `rock_layer_N`:

- отделить decoration queue от critical terrain;
- камни подключать после поверхности и collision;
- разбить крупные MultiMesh на пространственные batches.

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

---

## Параллельный долг по фундаменту

### Chunk Lifecycle

1. Явные состояния `Dormant`, `Warm`, `Active`, `Unloading`.
2. В Warm хранить только EntityRecord без физического узла.
3. В Active создавать визуальную сцену и коллизию.
4. Очередь создания сущностей по frame budget.
5. Метрики чтения JSON и создания runtime scenes.

### Controller Layer

1. equipment slots;
2. сохранение выбранного профиля;
3. отдельные wheel/track/flight contracts для Robot Actor.
