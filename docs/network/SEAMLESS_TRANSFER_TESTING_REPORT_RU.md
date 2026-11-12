# Отчёт: тестирование бесшовных перемещений между двумя authority (r1)

Дата: 2026-11-13. Ветка: `feature/seamless-transfer-testing-r1`.
База: main `e3e9a3b98` (механизм SM1; перенос на Playtest R1 базу `3b634cea` —
отдельная задача интеграции, см. §6). Godot: 4.7.1.stable.double.custom_build.a13da4feb.

## 1. Созданная тестовая система

| Файл | Уровень | Что проверяет |
| --- | --- | --- |
| `RUN_SEAMLESS_TRANSFER_SUITE.ps1` | runner | полный прогон с preflight |
| `tests/runtime/test_seamless_transfer_items_grids_stress.gd` | L0 in-process | 20 переходов A↔B над реальными доменами: предметы (рюкзак/мир/аттачмент), 2 грида; fencing в каждом 5-м gap; тайминги по 6 стадиям; 1095 assertions |
| `tests/runtime/seamless_transfer_metrics_client.gd` + `test_seamless_transfer_process_metrics.gd` | процессный | 2 реальных authority-процесса + gateway + headless-клиент, 10 пересечений (20 handoff); замер пауз клиента и латентности команд; 56 assertions |

## 2. Результаты прогонов (все PASS, контрольные прогоны Lead'а)

### 2.1 Базовая линия (существующие тесты, main e3e9a3b98)
14/14 зелёные: L0 SM1 (owner map, world continuity, combined chain, activation
replay, player carry + gateway pivot) и процессные (graphical A-B-A, reconnect,
concurrent, impaired crossings, authority recovery, gateway restart, fault
matrix, MVP seam continuity).

### 2.2 L0-стресс: предметы + гриды, 20 переходов
- 1095 assertions / 0 failures. 100 авторизованных мутаций, 15 fenced-попыток
  в gap'ах (код `SM1_CANONICAL_MUTATION_FENCED`), 40 реконсиляций world entities.
- Инварианты после каждого перехода: ledger предметов (id+количество),
  идентичность конструкций, монотонный рост частей, валидность Item Graph,
  `validate_after_activation`, финал A/epoch 21.
- **Замер времени полного перехода (begin→activate, сумма 6 стадий):**
  min ≈ 23 мс, p50 ≈ 91–94 мс, p95 ≈ 184–186 мс, max ≈ 192 мс.
  Рост с эпохой (23→190 мс) — снапшоты растут с числом предметов/частей;
  доминирует стадия prepare/bind.

### 2.3 Процессный уровень: два сервера + gateway, 10 пересечений
- 56 assertions / 0 failures; 4 реальных OS-процесса (authority A, authority B,
  gateway, клиент), все завершились чисто; время прогона ~35 с.
- 20 реальных handoff'ов; финальный владелец A/epoch 21, revision 22; B retired.
- Непрерывность: 1 подключение, 0 дисконнектов, 22/22 команд (0 потерь),
  revisions строго непрерывны 1..22, эпохи +1 на каждый pivot, маршрут
  A/B×21 с возвратом на A, spawn_generation=1, endpoint стабилен.
- **Замеры:** пауза клиента на pivot p50/p95/max ≈ 48/49/49 мс
  (контрольный прогон под нагрузкой: латентность команд p50/p95 ≈ 75/76 мс).
  Пауза определяется кадровой каденцией опроса, а не работой переноса.

## 3. Вердикт по готовности бесшовности

**Работает и доказано:**
- Игра устойчиво держит два authority-процесса за одним gateway:
  20 последовательных handoff'ов без разрыва клиентской сессии, без потерь
  команд, с непрерывными ревизиями — бесшовность НА УРОВНЕ ПЕРЕНОСА ВЛАДЕНИЯ
  и player-state работает; тайминги ~48 мс на переход далеки от заметных.
- Контрактный уровень (L0) гарантирует fencing/идентичности/непрерывность
  для предметов и гридов на общем каноническом сторе.

**НЕ работает (реализационные гэпы, а не FAIL тестов):**
1. **Реального переноса ДАННЫХ предметов/гридов между процессами нет**:
   SM1.5 переносит только hash-fingerprint'ы; SM1.6 — плоский player-dict.
   «Предмет переехал на другой сервер» сегодня не существует как перенос данных.
2. **Проекций (ghost) на шве нет**: EG4 — read-only fan-in за одним gateway;
   entity-level handoff-tickets (`handoff_state_machine`) не подключены к SM1.
3. Gateway-воркер жёстко завязан: 2 клиента для START, shutdown по
   фиксированному operation_id, handoff по порогу позиции; один hardcoded player.
4. **Дефект продакшена (найден тестом):** M0 JSON round-trip не бит-точен для
   не-двоичных float — checksum'ы aggregate-снапшотов ломаются на 15+ частях
   (`AGGREGATE_SNAPSHOT_CHECKSUM_MISMATCH` → `INVALID_TRANSACTION_STATE_AGGREGATE`
   от `center_of_mass_m` 10.533333333333333 → …331). Нужен Work Order:
   полная точность кодирования в NetworkUtils или квантизация facets.

## 4. Рекомендуемые следующие шаги (приоритет)

1. WO на сериализацию переноса Item Graph / Construction между процессами
   (расширение SM1.5 до payload-переноса; база для готовых тестов уже есть).
2. WO на M0 float-дефект (блокирует большие гриды при переносе).
3. Подключение entity-level handoff-tickets к SM1 runtime (N4) и seam-проекции
   на базе EG4 (N6).
4. Перенос suite на Playtest R1 базу `3b634cea` и прогон там.

## 5. Артефакты

- `artifacts/test-results/seamless-transfer-stress/metrics-*.json`
- `artifacts/test-results/seamless-transfer-process/metrics-*.json`
- Базовые логи: `main/artifacts/runtime/seamless-baseline/*.log`
