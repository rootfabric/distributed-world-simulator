# V0-P3 — подготовка Resource / Mining

Дата: 2026-08-16

Статус: **PREPARATION ONLY / NO PRODUCTION RUNTIME MUTATION**

## 1. Точная линия

Текущий product frontier provenance:

`d66378b98b69756fab6c2a93b80b74db9ccd1980`

Repaired и independently reviewed P1:

`f7ab0a8b91394724b66e3f4ee387de3441a676ca`

Текущий P2 R8 repair candidate:

`92e3e197e11156d6c36a58a3b4a4f447397c99d7`

Эта preparation-ветка re-anchored поверх exact P2 R8 candidate без force-push и без production runtime mutation. P2 остаётся HIGH-risk candidate и ещё проходит independent Reviewer / Verifier / Director routing. Поэтому данный checkpoint **не имеет права менять production runtime** и не является началом mining implementation.

## 2. Цель P3

Первый P3 runtime slice после снятия P2 gate должен дать минимальный сервер-авторитетный цикл:

`canonical resource node -> resource.mine -> depletion -> existing M4 Item Graph output`

Следующий slice расширит его до:

`resource -> inventory/container -> Construction consumption -> multiplayer reconnect convergence`

P3 не создаёт второй Item Graph, второй Construction graph или клиентскую authority.

## 3. Найденные существующие authoritative seams

### Item Graph

Canonical M4 Item Graph остаётся владельцем добытых item identity / quantity / location.

Текущий sandbox уже содержит:

- canonical item `item/shared/ore/1`;
- `definition_id = item/ore`;
- quantity `8`.

P3 использует существующую `item/ore` семантику как первый fixture/output contract. Отдельный material inventory graph не вводится.

### Construction

Construction уже имеет собственный authoritative multiplayer bundle:

- `server_generation`;
- canonical items/constructs;
- bundle checksum.

Construction multiplayer commands содержат session/permission/generation preconditions и проходят через существующий Construction authority path.

Construction является downstream consumer добытого материала, но **не** владельцем resource depletion state и не владельцем M4 items.

### Spatial authority

Resource node должен хранить canonical Earth-fixed spatial state. Render origin, SceneTree transform, mesh/node target и клиентская камера остаются presentation/input surfaces и не становятся canonical resource position.

## 4. P3 authority contract

Будущий resource state owner: dedicated authoritative server.

Минимальная canonical resource record должна содержать:

- `resource_node_id`;
- `resource_definition_id`;
- `output_definition_id`;
- `remaining_units`;
- canonical Earth-fixed position;
- revision/generation, достаточную для stale-command fencing.

Первый контракт фиксирует:

- resource id: `resource/earth/ore-demo/1`;
- resource definition: `resource/ore`;
- output definition: существующий `item/ore`;
- стартовый остаток fixture: `8` units.

## 5. Command contract

Первый игровой command name:

`resource.mine`

Клиент может запрашивать только намерение, например:

- `resource_node_id`;
- `requested_units`.

Клиент не имеет права присылать authoritative result fields:

- новый `remaining_units`;
- canonical output item id;
- output quantity result;
- server revision/generation;
- checksum;
- canonical resource position.

Server preflight обязан проверить до мутации:

1. resource существует;
2. requested quantity допустима;
3. resource не depleted;
4. player/session имеет право на действие;
5. canonical spatial/range validation проходит;
6. есть допустимый способ опубликовать output в существующий M4 Item Graph.

Успех должен атомарно/транзакционно публиковать согласованный результат: resource уменьшается и добытый `item/ore` появляется в canonical Item Graph. Нельзя сначала уменьшить resource, а затем потерять output из-за отказа Item Graph.

## 6. Rejection purity

Минимальные rejection contracts:

- `RESOURCE_NOT_FOUND`;
- `RESOURCE_DEPLETED`;
- `RESOURCE_OUT_OF_RANGE`;
- `INVALID_MINING_QUANTITY`;
- `RESOURCE_OUTPUT_REJECTED`.

Для preflight/rejected command canonical resource state и Item Graph должны оставаться неизменными: generation/revision/checksum/remaining units/item membership не двигаются.

## 7. Non-goals этого preparation checkpoint

Не реализуются:

- production `resource.mine` handler;
- resource persistence owner;
- depletion runtime;
- mining animation/tool speed;
- respawn/regeneration;
- procedural ore generation;
- geology/biome/ecology coupling;
- economy/recipes;
- новый material graph;
- новый inventory/container authority;
- новый Construction authority;
- client prediction mining.

Этот checkpoint может менять только docs/tests/fixtures/runner.

## 8. Ручные visual gates проекта

Эти точки считаются частью durable project memory и не должны теряться при смене сессии.

### Visual Gate V-P2

После окончательного P2 promotion — короткий необязательный visual sanity check двух клиентов: B disconnect, A mutation, B reconnect/convergence.

### Visual Gate V-P3.1 — ОБЯЗАТЕЛЬНЫЙ

После первого P3 Resource/Mining runtime slice:

- открыть игровой полигон;
- подойти к resource node;
- выполнить mining;
- увидеть feedback действия;
- увидеть уменьшение/depletion ресурса;
- увидеть добытый canonical item в мире/инвентаре.

До этой ручной проверки не наращивать большой следующий mining UX slice.

### Visual Gate V-P3.2 — ОБЯЗАТЕЛЬНЫЙ

После интеграции `resource -> inventory/container -> Construction`:

- добыть материал;
- перенести его;
- использовать в Construction;
- визуально подтвердить расход и результат строительства;
- отдельно оценить UX: дистанция, input, feedback, скорость, перенос.

### Visual Gate V-P3.3 — ОБЯЗАТЕЛЬНЫЙ

После multiplayer/reconnect версии полного loop:

- A добывает/переносит/строит;
- B видит authoritative изменения;
- B отключается;
- A продолжает;
- B возвращается;
- resource/item/container/Construction state сходятся без локальной второй истины.

## 9. Обязательная короткая карта после каждого этапа

Каждый development report после завершения этапа должен заканчивать короткой картой вида:

```text
✅ завершено
🟡 текущий gate / работа
⏸ заблокированный следующий runtime этап
👁 следующий ручной visual gate
```

Это presentation правило для отчёта, а не замена main-owned Project Control.

## 10. Риск и activation gate

Preparation checkpoint: MEDIUM, потому что он фиксирует будущий cross-domain contract, но не меняет runtime.

Первый production P3 resource/mining slice: HIGH до отдельной классификации, потому что он будет связывать новый canonical depletion state с M4 Item Graph и multiplayer/reconnect semantics.

Production P3 activation разрешается только после того, как текущий P2 R8 candidate завершит требуемый acceptance routing и Director определит допустимую runtime base/frontier. До этого `scripts/runtime` и production Construction/Item Graph в P3 preparation не меняются.
