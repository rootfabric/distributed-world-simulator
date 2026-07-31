# M6 — Dedicated Persistence and Recovery

## Статус

```text
checkpoint: v16.10.5-persistence-m6-dedicated-recovery
build_id: m6-dedicated-persistence-recovery
runtime base: v16.10.4-testing-m5-graphical-multiplayer-acceptance
branch: feature/m6-dedicated-recovery
status: candidate_linux_double_verified_pending_independent_acceptance
```

M6 интегрирует принятый R3.1 authoritative recovery с реальным M3–M5 dedicated gameplay runtime. Новый parallel gameplay path не создаётся: ENet-команды по-прежнему обрабатывает единый `NetworkedGameplayService`, а persistence оборачивает его authoritative mutation boundary.

## Граница durable commit

Для каждой JOIN, MOVE, PRESENTATION, ITEM_COMMAND, LEAVE или transport-disconnect операции, дошедшей до replay-durable execution boundary, сервер выполняет последовательность:

```text
validate/replay lookup
    → authoritative mutation или replay-durable deterministic result
    → stage committed command result in durable outbox
    → create generation-fenced authoritative checkpoint
    → atomic replace ACTIVE checkpoint
    → ACK/COMMAND_RESULT and replication broadcast
```

Предварительные отказы — пустой/неканонический `operation_id`, неверный payload и transport/ownership fence до выполнения доменной команды — не меняют authoritative state, не входят в replay ledger и возвращаются без checkpoint. Любой результат, который уже стал replay-durable, подтверждается клиенту только после успешного atomic checkpoint. Если запись не завершилась, dedicated runtime переходит в fail-stop, прекращает обработку ENet и не выполняет final checkpoint при shutdown. Поэтому неподтверждённая мутация не может позднее стать committed после перезапуска.

Точный replay уже committed операции:

- возвращает сохранённый результат;
- содержит `replay=true`;
- не выполняет вторую мутацию;
- не увеличивает revision/tick;
- не создаёт новый checkpoint;
- не добавляет вторую outbox-запись.

Replay conflict остаётся отказом `OPERATION_REPLAY_CONFLICT`; защита не ослаблена.

## Что сохраняется

Checkpoint содержит:

- authority owner и authority epoch;
- gameplay revision и server tick;
- стабильные logical player ID и player entity ID;
- ownership epoch каждого игрока;
- authoritative position, velocity и presentation state;
- player inventory state;
- canonical M4 Item Graph: items, inventories, hotbar, containers и mounts;
- service, ownership и Item Graph operation ledgers;
- committed outbox с delivery state;
- SHA-256 checksums всех вложенных секций;
- checkpoint generation и previous generation.

## Что намеренно не сохраняется

Transport и UI-состояние не является частью canonical durable state:

- ENet peer ID и transport session ID;
- connected-флаг после recovery;
- открытый внешний контейнер как access session;
- cursor/drag/pending UI overlay;
- process ID, renderer и window state;
- локальные client command queues.

После recovery все player records существуют, но disconnected. Новый JOIN привязывает новую transport session к прежней player entity и увеличивает ownership epoch, например `1 → 2`.

## Компоненты

### `M6DedicatedGameplayAuthorityAdapter`

Преобразует `NetworkedGameplayService.export_durable_state()` в R3.1 `EntitySnapshotEnvelope`, проверяет owner/epoch/revision/tick и выполняет transactional restore через staged domain services.

### `M6DurableReplayOutbox`

Хранит replay state трёх уровней:

- service operation ledger;
- ownership JOIN/LEAVE ledger;
- canonical Item Graph command ledger.

Дополнительно хранит committed result outbox. Capacity ограничена 2048 записями; при заполнении удаляются только старые delivered records. Pending records не вытесняются.

### `M3DedicatedServerRuntime`

При наличии `persistence_root` runtime:

1. конфигурирует R3.1 repository/coordinator;
2. pre-validates authority и replay sections;
3. восстанавливает последний ACTIVE/PREVIOUS checkpoint либо создаёт generation 1;
4. только после этого открывает ENet listener;
5. сохраняет каждую новую committed операцию до ответа клиенту.

Без `persistence_root` историческое M3–M5 поведение остаётся неизменным.

## Отказоустойчивость

- ACTIVE checkpoint заменяется через verified pending file и generation fence.
- Повреждённый ACTIVE не принимается молча.
- Replay section проверяется до изменения live service.
- Durable state собирается во временных сервисах и применяется только после полной cross-section validation.
- Same-revision mutation, generation rollback/gap, owner/epoch rollback и checksum mismatch отклоняются.
- Graceful shutdown создаёт финальный checkpoint только если runtime не находится в fail-stop.

## Acceptance evidence

Focused contracts:

- `tests/runtime/test_m6_dedicated_recovery_contracts.gd`;
- `tests/runtime/test_m6_dedicated_recovery_processes.gd`.

Process test запускает dedicated server и два ENet-клиента, создаёт player/item state, жёстко завершает server process без graceful shutdown, запускает replacement server на том же persistence root, проверяет byte-stable recovery, reconnect с epoch 2, точный replay старой операции с epoch 1, продолжение gameplay и чистое завершение.

Focused runners:

- `RUN_M6_DEDICATED_RECOVERY_TESTS.ps1`;
- `RUN_M6_DEDICATED_RECOVERY_TESTS.sh`.

На Linux-сборке Godot 4.7.1 stable.double (`a13da4feb`) подтверждены focused 10/10, M6 contracts 118/118, M6 processes 124/124, network/runtime 59/59, world regression 104/104, editor import и main scene. Checkpoint остаётся `candidate` до независимой локальной приёмки; после неё M6 закрывает `A2-D04`, а следующий этап — A3 single-server multiplayer audit/freeze.
