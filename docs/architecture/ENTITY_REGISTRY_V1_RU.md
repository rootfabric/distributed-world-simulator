# Entity Registry v1

> **Legacy:** актуальное состояние описано контрактом `planet_simulator.entity.v2` в `docs/contracts/ENTITY_STATE_V2_RU.md`.


## Назначение

Entity Registry связывает игровые сущности с логической сеткой зон и чанков.
Он пока работает в одном локальном процессе, но контракты уже не зависят от
Godot NodePath и локального render origin.

## Сущность

```text
entity_id          постоянный идентификатор
entity_type        тип сущности
world_position     абсолютная double-координата Луны
zone_id            логическая зона
chunk_id           логический чанк
components         расширяемые компоненты
revision           версия состояния
```

## Интеграция в v12

Игрок зарегистрирован как:

```text
player/local-astronaut
```

Его абсолютная позиция обновляется каждый кадр. Реестр публикует события
только при фактическом переходе границы чанка или зоны.

## События

```text
entity_registered
entity_unregistered
entity_moved
entity_left_chunk
entity_entered_chunk
entity_left_zone
entity_entered_zone
```

Событие содержит старый и новый адрес, позицию и revision сущности.

## Почему это фундамент серверного разделения

В будущем один сервер будет владеть набором чанков. При переходе сущности
между чанками события реестра станут входом для протокола передачи владения.
Сейчас owner остаётся `local-process`, сетевой слой отсутствует.
