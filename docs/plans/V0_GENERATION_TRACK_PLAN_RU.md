# V0 Generation Track (GEN-A/B/C) — план трека генерации миров

**Дата:** 2026-08-22
**Статус:** CONTROL CANDIDATE / OWNER-DIRECTED REVISION (amendment к pre-P6 sequencing)
**Canonical base:** этот документ вводится веткой `control/pre-p6-roadmap-amendments`
**Связанные документы:** `V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_ROADMAP_RU.md` (§14 CONV-0, §15 Two-line rule), `config/control/harness/v0-edge-gateway-fabric-test-plan.v1.json`

## 1. Назначение

Продуктовая цель требует «генерированных планет с генерированными пространствами»
(разные формы скал, реки, вода, уникальные локации) в сетевом мульти-мире.
Сегодня генерация детерминирована, но **однопланетна**: сид захардкожен и продублирован,
в `config/worlds/catalog.json` сида нет, сверка мира сервер↔клиент отсутствует.

Трек GEN закрывает это малыми шагами, не пересекающимися с сетевым критическим путём
(EG4→EG5→P6) по watched-путям: правки ограничены `scripts/world/**`,
`scripts/app/*earth*`, `config/generation/**`, `config/worlds/**`, `tests/**`.

## 2. Правило параллелизма

```text
GEN работает на PRODUCT BASE (accepted P5 lineage), а не на main.
GEN не меняет network contracts; единственная точка касания сети — GEN-A handshake field.
```

## 3. GEN-A — PlanetDefinition + world hash handshake (S–M, обязателен ДО P6.7)

Обоснование срока: P6.7 (`PERSISTENT_SHARED_OUTPOST`) фиксирует игровой мир;
без per-world определения «другая планета» остаётся копипастом класса.

Состав:

1. `config/worlds/catalog.json`: каждому миру — `seed`, `rules_config`,
   `generator_version`. Убрать дубль сида (`earth.json` vs `earth_rules.json`;
   pipeline читает rules, `find_biome_direction` — body_config).
2. `procedural_earth_world.gd`: конфиг из параметра (сейчас `BODY_CONFIG_PATH` const);
   `get_world_definition_hash()` = sha256 канонического JSON определения мира.
3. Handshake: сервер публикует `world_id + generator_hash`; клиент сверяет;
   mismatch → disconnect с кодом `WORLD_DEFINITION_MISMATCH` (fail-closed).
4. Контрольные точки: 5 направлений `sample(direction) -> elevation_m`
   (округление до см) сверяются сервер/клиент при подключении.
5. EG4-связка: amendment к EG0-контрактам — `WorldDescriptor` получает optional
   `generator_hash` (по прецеденту R4/R5 amendments); gateway остаётся read-only.

Exit-предикаты:

```text
PLANET_DEFINITION_PER_WORLD_PASS
WORLD_HASH_HANDSHAKE_MISMATCH_FAIL_CLOSED_PASS
CONTROL_POINT_ELEVATION_MATCH_PASS
WORLD_DESCRIPTOR_GENERATOR_HASH_CONTRACT_PASS
```

## 4. GEN-B — ходибельная Земля (M, HIGH risk, визуальный гейт)

1. Включить коллизию локального патча (`collision.enabled=true`; крючок
   `_include_collision` уже существует) через trimesh по образцу Луны.
2. Вынести тайловый стриминг из `procedural_moon_terrain.gd` в миро-агностичный
   менеджер (API `get_cell_descriptor(direction)` уже не зависит от тела),
   подключить к Earth вместо полного синхронного ребилда патча.

Exit: `EARTH_WALKABLE_COLLISION_PASS`, `EARTH_TILE_STREAMING_PASS`.

## 5. GEN-C — вода как субстанция + когерентность рек (S, presentation-only)

1. Полупрозрачный меш поверхности воды по `sea_mask`/`water_kind` на уровне моря;
   физика воды — отдельным решением позже.
2. Реки: domain-warp вдоль градиента continentalness, привязка basin-озёр к стоку
   (маски уже есть в `hydrology_rule.gd`).

Exit: `WATER_SURFACE_PRESENTATION_PASS` (не меняет высоты/коллизии/сеть).

## 6. Окна исполнения

```text
GEN-A : параллельно EG4/EG5, завершить до refresh P6 preactivation.
GEN-B : после P6 activation (нужен визуальный гейт и спокойный продуктовый контур).
GEN-C : после GEN-B или параллельно, presentation-only.
```

Правило приоритета: при конфликте ресурсов критический путь EG→P6 всегда важнее GEN;
GEN-инженер не имеет права держать незакоммиченное состояние дольше одного раунда.
