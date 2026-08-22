# MULTI_LINK_DESIGN_NOTE — link-per-authority поверх EG3 backend multiplexer

Стадия: EG4 WORLD_GRAPH_DRIVEN_PROJECTION_AGGREGATION · Статус: DESIGN ONLY (без имплементации)
База: `e3828809` + дельта R2 · Владелец решения: оркестратор (этот документ — вход для ревью)

## 1. Контекст и проблема

Сегодня узел шлюза (`scripts/network/gateway/runtime/eg1_gateway_node.gd`) держит
РОВНО ОДИН физический backend-линк:

```text
_backend_peer_id / _backend_session_id / _backend_route_id / _backend_link_id   — синглтоны
```

Следствия:

1. `route_table.rows[*]["backend_link_id"]` заполняется при ATTACH
   (`bind_backend_link(gsid, _backend_link_id)`), но НИГДЕ не читается для выбора
   линка — поле-заготовка без потребителя (это и заметил ревью EG4).
2. Потеря единственного линка обрабатывается глобально
   (`_handle_backend_event / PEER_DISCONNECTED`): очистка `_pending_backend_specs`
   и `mux.purge_all()` — планирующие кадры ВСЕХ сессий уничтожаются одним
   взмахом, хотя пострадать должны только сессии погибшего линка.
3. Sim B (projection source) в EG4 живёт ВНЕ этой модели: проекционный фан-ин
   агрегатора уже использует СОБСТВЕННЫЙ внутренний экземпляр
   `eg3_backend_multiplexer`. То есть «мультиплексор на логический источник» —
   уже свершившийся факт внутри стадии, но узел его не обобщает.

Требование machine test plan (`v0-edge-gateway-fabric-test-plan.v1.json`):
`gateway_server_links_are_shared = true`,
`ONE_TO_K_PHYSICAL_TUNNELS_MULTIPLEX_MANY_LOGICAL_SESSIONS` — K > 1 заложен в
модель, но не реализован в узле.

## 2. Целевая модель: link-per-authority

Каждому upstream-авторитету (ACTIVE-мир, projection-источник, будущие домены) —
свой физический линк; многие логические сессии мультиплексируются в свой линк.

```text
LinkRegistry (в eg1_gateway_node):
  backend_link_id -> BackendLink {
      peer_id, wire_session, route_id,
      boundary: NetworkTransportBoundaryV2,   # свой порт ENET/loopback
      mux: Eg3BackendMultiplexer,             # свой планировщик P0..P5
      state: CONNECTING|READY|LOST,
      counters {...}
  }
```

* Инвариант EG0 сохраняется: клиент всегда имеет ровно ОДИН клиентский
  транспорт; рост числа авторитетов добавляет BACKEND-линки, не клиентские.
* EG4-агрегатор продолжает работать через `send_client_frame_spec_for_session`;
  его внутренний mux превращается в обычный член реестра (link B) без изменения
  read-only fence.

## 3. Изменения в eg1_gateway_node (аддитивные)

| Точка сегодня | Стало |
|---|---|
| `start(...)` принимает один backend-endpoint | `options.links[]` (id, endpoint, peer/session/route); одиночный линк — вырожденный случай, все существующие вызовы совместимы |
| `_send_to_backend(spec)` шлёт в единственный линк | резолвит `route_table.lookup(gsid).row.backend_link_id` -> `LinkRegistry[link_id].mux.enqueue(...)`; неизвестный/LOST линк — явная ошибка `BACKEND_LINK_UNAVAILABLE` (fail-closed, без «подходящего соседа») |
| `_handle_backend_event(PEER_DISCONNECTED)` → `purge_all()` | scoped: `mux.purge_link(link_id)` + очистка parked-specs ТОЛЬКО этого линка; сессии других линков не затронуты |
| счётчик `backend_link_drops` один | пер-линк счётчики + `link_state` в `get_report()` |

Семантика fail-predictable EG3 сохраняется ДОКУМЕНТАЛЬНО: кадры погибшего линка
не переигрываются в новую инкарнацию (никакого stale resurrection), просто зона
поражения сужается с «все» до «этот линк».

## 4. route_table.backend_link_id и route_revision

* `backend_link_id` становится ЕДИНСТВЕННЫМ источником правды о привязке
  «логическая сессия -> физический линк». Запись возможна только владельцу
  маршрута (узлу) в момент ATTACH/PIVOT — gateway canonical writes остаются 0
  относительно игрового домена.
* Смена линка сессии (например, EG6 ACTIVE→WARM pivot или восстановление линка
  на другом соединении) = `bind_backend_link(gsid, new_link_id)` +
  `route_binding.route_revision += 1`. Пара `(backend_link_id, route_revision)`
  образует монотонную историю маршрута: повтор маршрутизации старым значением
  revision отклоняется (fail-closed против resurrection), что напрямую
  переиспользуется EG6 «STABLE_CLIENT_CONNECTION_MULTI_WORLD_BACKEND_PIVOT».
* Клиентский транспорт при смене линка НЕ меняется — это главный acceptance
  инвариант (`normal_authority_pivot_changes_client_transport = false`,
  `normal_projection_source_adds_client_transport = false`).

## 5. Fair-share между линками

Два варианта, выбран вариант (a):

* **(a) mux-per-link** (выбрано): у каждого линка свой `eg3_backend_multiplexer`
  с текущей семантикой P0..P5, latest-wins, bounded queues. Дрейн узла идёт
  round-robin по READY-линкам с пер-линковым бюджетом `drain_budget/K`.
  Плюсы: нулевые изменения в мультиплексоре (его already-proofed семантики
  EG3 не трогаются), изоляция задержек доменов друг от друга бесплатно.
* (b) один mux c полем link_id в slot — отклонено: смешивает домены в общих
  очередях, усложняет scoped purge, ломает «чистый» reuse EG3.

## 6. Влияние на смежные стадии

* **EG5 (nearest edge selection):** LinkRegistry даёт естественный surface
  здоровья (`state`, RTT/loss из peer_statistics) — выбор ближайшего шлюза и
  выбор здорового линка становятся одной политикой над одними данными.
* **P6.6 / EG6 (pivot без разрыва клиента):** связка
  `bind_backend_link + route_revision` из §4 — готовый механизм переноса
  логической сессии между линками/авторитетами при неизменном клиентском
  транспорте; EG4-агрегатор переживает pivot источника как `mark_source_lost`
  + повторную подписку (уже доказано в L1/L2).
* **CWIP (EG4.5):** маршрутизация interaction-intent адресуется по
  `backend_link_id` автора действия — collision-proof трафик не проходит через
  чужой домен даже физически (усиление NO_CROSS_DOMAIN_LEAKAGE).

## 7. План имплементации (1–2 коммита, БЕЗ реализации в рамках EG4 R2)

1. **Коммит 1 — LinkRegistry + scoped failure:** аддитивный
   `options.links[]`, резолв линка из route table, `purge_link(link_id)`,
   per-link telemetry; регресс L1 «три линка, два авторитета: падение линка B
   не трогает очереди A и C» (предикат
   `MULTI_LINK_ISOLATED_FAILURE_PASS`).
2. **Коммит 2 — route_revision↔link binding:** pivoting API
   `rebind_session_link(gsid, link_id)` с bump route_revision + L1-регресс
   «смена линка видима в route history, клиентский транспорт неизменен»
   (`ROUTE_REVISION_LINK_BINDING_PASS`).

Не входит: реализация в EG4 R2, изменения EG0-контрактов, активация P6,
какие-либо canonical writes со стороны шлюза.
