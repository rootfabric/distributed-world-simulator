# План: система тестирования бесшовных перемещений между двумя authority

Статус: DRAFT (r1). Ветка: `feature/seamless-transfer-testing-r1` от main `e3e9a3b98`.
Дата: 2026-11-13. Цель заказчика: игра должна устойчиво держать два сервера и
перемещения между ними предметов, гридов (construction grids) и игроков; замерить
время перемещения; проверить проекции; довести бесшовность до рабочего состояния.

## 1. Что уже есть (база)

- SM1.2 `sm1_authority_transfer_coordinator` — one-writer transfer state machine
  (ACTIVE → SOURCE_FROZEN → TARGET_WARM_VALIDATED → OWNERSHIP_COMMITTED →
  SOURCE_RETIRED → активация), fail-closed на всём gap.
- SM1.6 process harness: `sm1_6_authority_worker.gd` (A и B, ENet),
  `sm1_6_gateway_worker.gd` (stable client endpoint + route pivot),
  `sm1_6_graphical_client.gd`; SM1.7 клиенты (reconnect, concurrent, impaired,
  authority recovery, gateway restart) + fault driver.
- Существующие тесты (L0 contract и process): player carry + gateway pivot,
  world state continuity (Item Graph / Construction / Outpost), world mutations
  around handoff, graphical handoff processes, reconnect after handoff,
  concurrent crossings, impaired repeated crossings, authority recovery,
  gateway failure restart, fault matrix 1.6, MVP seam continuity.
- N3 R0a region lease directory (lab-only, in-memory) + EG2 gateway directory.
- EG4 projection suite (interest/aggregation/lifecycle) — single-server
  проекции, не на шве.

## 2. Целевая тестовая система (что создаём)

### T1. Перемещение предметов (items) через шов A→B→A — process-level
- Два authority-процесса + gateway + графический клиент.
- До шва: предметы в инвентаре игрока, в контейнере и в мире (ground items).
- Шов: инициировать handoff; во время gap попытать мутации (должны быть
  fail-closed); после активации B — предметные операции продолжаются с
  сохранением identity, количества, привязок, operation ledger continuity.
- Возврат A→B→A; повторные швы (stress: ≥20 последовательных переходов).

### T2. Перемещение гридов (construction aggregates/grids)
- Construction aggregate с частями и attachment-relations до шва; после
  перехода — продолжение сборки/разборки на B; структурные ревизии и
  реляции не теряются; collision-привязки сохранены.
- Тот же сценарий в process-топологии с двумя реальными authority.

### T3. Перемещение игроков — расширенные варианты
- Игрок с переносимыми предметами (carry) — уже покрыто частично; расширить:
  два игрока одновременно в противоположных направлениях; игрок в движении
  через границу во время шва (input sequence continuity); reconnect второго
  игрока, пока первый в соседнем регионе (критерий из Playtest R1).

### T4. Замеры времени перемещения (timing instrumentation)
- Единый metrics-JSON на каждый переход: `begin→warm_validated`,
  `warm→committed`, `commit→activated`, полный `begin→activated`,
  длительность write-freeze gap, client-observed pause (между последним
  delta от A и первым delta от B), количество потерянных/повторных команд.
- Пороговые значения (diagnostic, не блокирующие по DEV-FLOW): полный
  handoff < 1000 мс, client pause < 500 мс, 0 потерь команд.
- Сводка по ≥20 переходам: min/p50/p95/max.

### T5. Проекции на шве (ghost/projection continuity)
- Клиентская проекция сущности из региона A во время перехода владельца:
  нет despawn/respawn (identity проекции стабилен), нет телепорта позиции
  (непрерывная интерполяция), удалённые сущности видны как read-only реплики.
- Использовать/расширить модель EG4 projections в клиентском снапшоте шва;
  добавить утверждения в process-тест (T1–T3) — проекция непрерывна на всём
  окне перехода.

### T6. Runners и отчёт
- `RUN_SEAMLESS_TRANSFER_SUITE.ps1/.sh` — полный прогон, preflight версии
  Godot, запись exact HEAD, логов и metrics в `artifacts/runtime/seamless-*`.
- Итоговый отчёт `docs/network/SEAMLESS_TRANSFER_TESTING_REPORT_RU.md`
  с таблицами результатов и замеров.

## 3. Порядок исполнения

1. Baseline: все существующие SM1-тесты зелёные на HEAD (фоновая задача).
2. L0-contract тесты T1/T2 (in-process, быстрая обратная связь).
3. Timing-инструментация в координатор/harness (не меняя семантику) + metrics JSON.
4. Process-тесты T1–T3 на двух authority + gateway.
5. Projection-проверки T5.
6. Полный прогон, отчёт, коммит.

## 3.1 Ключевые факты разведки (уточняют объём)

- SM1.5 `sm1_world_state_continuity` переносит через шов ТОЛЬКО
  hash-fingerprint'ы (item_graph/construction/outpost); данные предметов и
  гридов между процессами не сериализуются — доказывается
  непротиворечивость на общем сторе, а не перенос. Реального переноса
  Item Graph / Construction между двумя процессами в проекте ещё нет.
- SM1.6 через реальные процессы переходит только плоский player-dict
  (position/action/world_revision/operation_ids). Handoff инициирует
  authority-воркер по порогу позиции (x>=10 → B, x<=0 → A).
- Замеров времени handoff в проекте нет вообще (только таймауты).
- Проекций на шве нет: EG4 — read-only fan-in за одним gateway;
  entity-level handoff-tickets (handoff_state_machine) существуют, но
  не подключены к SM1 runtime.
- Критерии бесшовности Playtest R1 (A→B→A без потери управления,
  reconnect в соседнем регионе и т.д.) — см. принятую базу.

Поэтому система тестов честно разделяет уровни:
- L0-контракты (in-process, реальные домены): что ГАРАНТИРОВАНО механизмом
  сегодня — continuity/fencing/идентичности + стресс 20 переходов + метрики.
- Процессный уровень (2 authority + gateway + клиент, реальные ENet):
  тайминги реального handoff player-state, пауза клиента, потери команд.
- Перенос данных предметов/гридов между процессами и проекции на шве —
  фиксируются как РЕАЛИЗОВАННЫЙ ГЭП с готовой тестовой базой для проверки,
  когда перенос появится (T7, backlog).

## 4. Границы

- Two-process/two-host N3 (реальный multi-host с durable leases) вне рамок:
  R0a-директория lab-only; это фиксируется в отчёте как отдельный
  N3 R0b work order.
- p99-микробенчмарки не создают новых блокеров (DEV-FLOW 2026-10-28).
- База тестов — main e3e9a3b98 (механизм SM1 идентичен); прогон на
  Playtest R1 базе 3b634cea — отдельная задача интеграции, отмечена в отчёте.
