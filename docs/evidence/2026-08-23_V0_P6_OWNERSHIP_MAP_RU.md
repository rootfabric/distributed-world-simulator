# V0-P6.1 — Карта владения каноническим состоянием (ownership map)

- Дата: 2026-08-23
- Стадия: P6.1 (контрольная, визуальные/ручные проверки не требуются)
- Чекпоинт: `V0_P6_PERSISTENT_SHARED_OUTPOST`
- Work order: `V0-P6-R1-WO-001` (state=DISPATCHED)
- Ветка: `feature/v0-p6-persistent-shared-outpost`
- Статус: IMPLEMENTED (declaration-only; реализация персистентности — стадия P6.7)

## Машиночитаемый источник

Единственный источник истины по владению состоянием аутпоста:

```text
scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd
```

Файл объявляет статический реестр (`RefCounted` со статическим API) всех
канонических доменов состояния, которые будет владеть/персистировать P6-аутпост.
Схема снимка: `distributed_world_simulator.p6_ownership_map.v1`.

## Объявленные домены

| domain_id | Владелец | persistence_replay | reconnect_restore | transport_path | write_authority |
| --- | --- | --- | --- | --- | --- |
| `p6-domain/outpost-world-state` | `p6-owner/directory-one-writer` | да | да | `GATEWAY_ONLY` | `SERVER_ONLY` |
| `p6-domain/item-inventory` | `p6-owner/directory-one-writer` | да | да | `GATEWAY_ONLY` | `SERVER_ONLY` |
| `p6-domain/equipment-tool-slots` | `p6-owner/directory-one-writer` | да | да | `GATEWAY_ONLY` | `SERVER_ONLY` |
| `p6-domain/construction-builds` | `p6-owner/directory-one-writer` | да | да | `GATEWAY_ONLY` | `SERVER_ONLY` |
| `p6-domain/player-identity-bindings` | `p6-owner/directory-one-writer` | да | да | `GATEWAY_ONLY` | `SERVER_ONLY` |
| `p6-domain/interaction-operation-ledger` | `p6-owner/directory-one-writer` | да | да | `GATEWAY_ONLY` | `SERVER_ONLY` |

Каждый домен не создаёт новой «правды»: инвентарь остаётся каноническим Item
Graph (M4), экипировка — принятой композицией P5 над Item Graph, строительство —
каноническим владельцем Construction (P4), identity-binding и operation ledger —
существующими каноническими агрегатами. Единственный владелец персистентности
для всех replay-доменов — один Directory-backed one-writer (`p6-owner/directory-one-writer`).

## Инварианты (статические функции реестра)

- `single_persistence_owner()` — у каждого replay-домена ровно один владелец
  персистентности; второй владелец запрещён.
- `gateway_only_transport()` — весь клиентский трафик идёт только через edge
  gateway (`GATEWAY_ONLY`); прямые транспорты запрещены.
- `no_private_truth()` — карта внутренне согласована; никакой домен вне карты не
  может персистироваться. Для последующих стадий (P6.7+) предусмотрен fail-closed
  гейт `assert_domains_declared(...)`: каждая точка записи обязана ссылаться на
  объявленный здесь `domain_id`, иначе ошибка `PRIVATE_TRUTH_UNDECLARED`.

Fail-closed валидаторы: `validate_domain`, `validate_map`,
`try_register_domain` (ничего не мутирует — стадия declaration-only).
Коды ошибок включают `MULTIPLE_PERSISTENCE_OWNERS`, `NON_GATEWAY_TRANSPORT`,
`NON_CANONICAL_DOMAIN_ID`, `DUPLICATE_DOMAIN_ID`, `EMPTY_DOMAIN_MAP`.

Запрещённые приватные хранилища (из дорожной карты P6.1): OutpostTruthStore,
OutpostInventory, OutpostPersistence, приватная правда экипировки/Item
Graph/Construction, приватный сетевой фундамент.

## Проверки

- L0-тест: `tests/runtime/test_v0_p6_ownership_map.gd`
  (`godot --headless --path <wt> --script res://tests/runtime/test_v0_p6_ownership_map.gd`)
  Результат: 71 assertion / 0 failures, exit code 0. Покрывает: обязательные поля
  и типы каждой записи; каноничность идентификаторов `p6-domain/*`; ровно одного
  владельца персистентности по всем replay-доменам; `GATEWAY_ONLY` для всех
  доменов; детерминизм снимка (canonical JSON стабилен между двумя
  конструкциями, обратимый парсинг); негативные сценарии — второй владелец
  персистентности и прямой транспорт отвергаются валидаторами без мутации
  реестра; fail-closed на пустой карте, дубликате id и необъявленном домене.

## Smoke-запуск

По плану P6.1 smoke опционален и выполнен в минимальном объёме:
headless-запуск главной сцены (`godot --headless --path <wt> --quit-after 30`)
корректно поднял проект, сохранил мир и завершился с кодом 0
(`SMOKE_EXIT=0`, логи `world_saved`, без ошибок). Полноценный графический
scene-smoke отложен до P6.2 («deferred to P6.2 smoke»).

## Границы стадии

Реализация персистентности, восстановление после рестарта и фактическая
маршрутизация через gateway НЕ входят в P6.1: это declaration-only стадия.
Изменения `gateway/**`, `transports/**`, `config/**` (кроме журнала исполнения)
не производились.
