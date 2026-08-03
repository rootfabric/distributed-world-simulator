# NX6 — Predicted Item Interactions

## Цель

NX6 убирает RTT из визуального отклика предметных действий, не передавая клиенту authority над Item Graph. Клиент немедленно строит presentation-only проекцию, а сервер остаётся единственным источником canonical revision, checksum, durable state и созданных authority identity.

## Предсказуемые действия

- `item.pickup` — предмет немедленно скрывается в мире и показывается в локальном инвентаре;
- `item.drop` — немедленно создаётся temporary world spawn, включая partial stack;
- `item.place` — немедленно показывается placement ghost и temporary mount socket;
- `item.transfer` — оптимистический перенос между inventory, hotbar и контейнером.

Temporary item и mount IDs принадлежат только presentation projection. Они запрещены как identity для последующих authority-команд.

## Authoritative completion

`prediction_id` совпадает с уже существующим `operation_id`. Bridge ведёт ограниченный mailbox завершений и предоставляет три API:

```gdscript
poll_authoritative_completion(operation_id)
await wait_for_authoritative_completion(operation_id, timeout_ms)
take_authoritative_completion(operation_id)
```

`wait_for_authoritative_completion()` отдаёт итоговый server result только после того, как M3 runtime принял связанный Item Graph delta/result. Поэтому зависимая цепочка выглядит так:

```text
place submission
→ immediate placement ghost
→ await operation_id completion
→ read canonical server fixture mount_id
→ mount authoritative item
→ detach authoritative item
```

`mount/predicted/...` никогда не заменяет `fixture/...` в canonical state.

## Runtime compatibility

Prediction pump включается только для совместимого `Node` runtime с M3 mailbox boundary. Принятый `ServiceBackedClient extends RefCounted` остаётся на blocking server-authority пути и не получает дочерний Node.

## Projection relay

Runtime владеет canonical сигналом `item_graph_updated`. Bridge переводит существующих consumers на собственный `projected_item_graph_updated`, чтобы pending overlay не эмитировал runtime-сигнал рекурсивно. При stop исходные connections и flags восстанавливаются.

## Lifecycle cleanup

`M7NetworkItemCommandBridge.stop()`:

1. останавливает `PredictedItemCommandPump`;
2. удаляет pending operation IDs и buffered results из runtime mailbox;
3. откатывает все оставшиеся predictions к canonical snapshot;
4. сохраняет cancellation completion по каждому operation ID;
5. публикует финальную rollback projection;
6. отключает bridge callback и восстанавливает canonical consumers;
7. безопасно допускает повторный вызов.

M7 process client вызывает stop до `client.stop()`. Production `playground_runtime.gd` также вызывает `_m7_item_bridge.stop("NX6_PLAYGROUND_UNLOAD")` непосредственно в `prepare_for_unload()` — до отключения runtime-сигналов и освобождения bridge. M7 multiprocess client инстанцирует реальную `playground.tscn`; test-only lifecycle wrapper больше не участвует в flow.

## Транспорт и authority

Используется существующий `ITEM_GRAPH / RELIABLE_ORDERED`. Второй transport не создаётся. Protocol hash, серверные handlers и persistence не меняются.

## Обязательные gates fix3

Focused runner всегда выполняет:

1. editor import;
2. NX6 journal contracts;
3. NX6 bridge integration;
4. M7 playable contracts;
5. M7 graphical multiprocess regression.

```powershell
.\RUN_NX6_PREDICTED_ITEM_INTERACTIONS_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

После 5/5 следует запустить NX5 accepted regression, recovery, Network, World и conditioned ENet rejection/timeout scenarios.


## Fix3 production unload

Фактическая playground-сцена остаётся на `res://scripts/world/testing/playground_runtime.gd`. Её unload path сначала останавливает NX6 bridge с причиной `NX6_PLAYGROUND_UNLOAD`, затем отключает runtime signals и только после этого обнуляет bridge. Скрипты `APPLY_NX6_PREDICTED_ITEM_INTERACTIONS_FIX3.ps1/.sh` удаляют устаревший fix2 wrapper.
