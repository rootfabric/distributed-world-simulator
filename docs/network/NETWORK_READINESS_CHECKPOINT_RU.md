# Checkpoint готовности PlanetSimulator к сетевому слою

**Дата исследования:** 27 июля 2026 года
**Текущий подтверждённый checkpoint:** `v16.1.0-r2-stack-controls`
**Назначение:** определить, что уже можно использовать для сети, а что должно быть закрыто до настоящего authority handoff.

## 1. Фактическая стадия проекта

Последняя сохранённая в проекте валидация подтверждает:

- Godot `4.7.1 stable double custom build`;
- `32/32` обнаруженных и выполненных regression-теста;
- `6/6` main-scene smoke-тестов;
- стабильные предметы, контейнеры, слоты и stack transfers;
- `Item Graph` save/load;
- operation ledger и optimistic revisions;
- гравитационное поле и физическую массу;
- несколько миров и единый runtime lifecycle;
- `SimulationClock`, `FrameGraph`, `SpatialRef` и `PartitionAddress v2`;
- `authority_owner_id` и `authority_epoch` в локальном entity registry.

Это означает, что проект уже прошёл стадию, на которой сеть пришлось бы «прикручивать» к случайным `Node3D.global_position` и локальным ID.

## 2. Что уже является сетевым фундаментом

### 2.1 Постоянная идентичность

Для сетевого объекта уже можно использовать:

```text
entity_id / item_id
universe_id
instance_id
space_id
frame_id
state_revision
authority_owner_id
authority_epoch
```

UUID не должен меняться при:

- переходе между серверами;
- смене `Space`;
- входе в контейнер;
- монтаже;
- выгрузке физического представления;
- восстановлении после рестарта.

### 2.2 Координатный контракт

`SpatialRef` уже отделяет каноническое состояние от render-local координат Godot. Это обязательное условие для передачи объекта между процессами.

Сетевой слой не должен передавать `global_transform` как единственную истину. Он передаёт `SpatialRef` с явными universe, instance, space, frame и временем.

### 2.3 Защита команд

R1.2 уже дал:

```text
operation_id
payload_hash
expected_revision
result_revision
operation ledger
```

Эти поля почти напрямую переходят в сетевой command envelope и защищают от:

- повторной доставки;
- задержанного пакета;
- повторного выполнения после reconnect;
- конфликта двух клиентов;
- повторного сообщения после authority handoff.

### 2.4 Единственный владелец

В проекте уже принят инвариант `ADR-003`: изменяемый chunk имеет одного владельца. Для сетевой версии он расширяется с chunk до entity и interaction island.

## 3. Что можно начинать прямо сейчас

Можно немедленно запускать параллельный сетевой трек:

1. сетевые DTO и JSON fixtures;
2. `SimulationNodeRole` и headless startup arguments;
3. одиночный authoritative server и один клиент;
4. локальный Python launcher нескольких Godot-процессов;
5. World Directory в памяти;
6. authority lease без настоящего handoff;
7. тесты подключения, команд и snapshot replication.

Эти работы не требуют остановки развития предметов, строительства, энергетики и новых миров.

## 4. Что нельзя начинать сразу

Пока рано реализовывать:

- динамическое дробление Земли по нагрузке;
- WAN-handoff игрока между континентами;
- физическое столкновение, одновременно рассчитанное двумя серверами;
- rollback всех `RigidBody3D`;
- Kubernetes и Agones как первый шаг;
- глобальную N-body симуляцию, распределённую по узлам;
- произвольную миграцию огромной базы во время активной физики.

## 5. Обязательные предварительные барьеры

Перед первым объектным handoff должны быть выполнены:

### Барьер A — server-safe runtime

- мир запускается с `--headless --role=simulation`;
- сервер не создаёт обязательные UI, камеру и визуальные материалы;
- presentation можно полностью отключить;
- `user://` каждого процесса изолирован;
- процесс выдаёт JSONL-событие `node_ready`.

### Барьер B — authoritative input

- клиент отправляет команды, а не изменяет домен напрямую;
- сервер проверяет `authority_epoch` и `expected_revision`;
- клиентская сцена является представлением серверного snapshot;
- offline mode использует тот же command path через loopback adapter.

### Барьер C — переносимый aggregate snapshot

- entity/item graph сериализуется без `NodePath` и instance ID Godot;
- snapshot содержит все физические скорости и relation;
- snapshot можно загрузить в чистый процесс;
- checksum до и после загрузки совпадает.

### Барьер D — наблюдаемость

Каждый процесс пишет:

```text
node_id
role
space_id
region_id
server_tick
authority_epoch
connected_peers
entity_count
ghost_count
handoff_state
```

## 6. Главные текущие риски

1. **Смешение simulation и presentation.** Любая новая система должна иметь headless-safe доменную часть.
2. **Скрытые прямые изменения.** UI и сцены не должны обходить command services.
3. **Physics nondeterminism.** Для server authority допустима коррекция клиента; lockstep между серверами не принимается как базовая модель.
4. **Legacy persistence.** Ошибка старого `moon-experiment-001/world.json` должна быть изолирована от сетевых тестов отдельным `user://` на каждый процесс.
5. **Слишком ранняя инфраструктура.** Kubernetes не решает authority, handoff и interest management.

## 7. Решение checkpoint

> Сетевой слой можно начинать сейчас и вести параллельно. Первый настоящий seamless handoff начинается только после N0–N3 дорожной карты. До этого сеть является отдельным adapter/test layer и не меняет каноническую offline-симуляцию.
