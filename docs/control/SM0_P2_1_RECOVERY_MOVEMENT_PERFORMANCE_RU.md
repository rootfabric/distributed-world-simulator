# SM0-P2.1 — bounded movement recovery / graphical latency hardening

Статус: IMPLEMENTED / WINDOWS RUNTIME VERIFICATION PENDING / branch-local experimental.

Ветка: `feature/sm0-two-authority-seamless-handoff-lab`.

База: `aa577148be8773aa77681285cfd9c969580f95ed`.

Текущий implementation candidate: `50d92e0fdab71a74d73b124c210cc68250ea6fff`.

Никакой production/global/V0-S1 acceptance этим документом не объявляется. Cross-server authority остаётся CRITICAL, `SERVER_HANDOFF` остаётся за `stop_before` V0-S1.

## Runtime finding

Графический P2 на exact `62f3a3c2cd9dcd74a680f700bc6d4358f21de4e7` подтвердил две разные задержки.

Первая — намеренная: H4.3/P2 делает три total A+B outage на один crossing и держит видимые паузы вокруг PREPARED, COMMITTED и ACTIVE.

Вторая — нежелательная: при recovery mode каждый accepted MOVE проходит write-before-ACK `ACTIVE_OWNER` durability. Текущий canonical gameplay replay ledger содержит `operation/sm0/client/a/move/<sequence>` для каждого MOVEMENT_DELTA. Поэтому очередной recovery snapshot экспортирует и хэширует всё более крупный replay state. В длинной graphical session recovery generation и replay history растут вместе с количеством движений, а authoritative MOVE cadence начинает визуально дёргаться.

## Цель P2.1

Сохранить crash-safety H2.4/H4.3, но убрать неограниченный рост movement replay/history из recovery hot path.

Критический контракт не меняется:

> accepted MOVE_ACK в recovery mode не отправляется до durable ACTIVE_OWNER snapshot.

P2.1 не переводит ACK в nondurable режим и не вводит client-authoritative movement.

## Экспериментальная реализация

P2.1 использует отдельный SM0 recovery-performance node, включаемый только явным process option `--recovery-performance=p21` вместе с существующим H4.3 fault profile.

Перед ACTIVE_OWNER persistence для accepted MOVE он оставляет в canonical gameplay service replay ledger:

- все non-movement operations;
- только последний `operation/sm0/client/a/move/<last_input_sequence>`.

Именно последний movement replay record нужен H2.4 recovery для двух вещей:

- exact retry durable input возвращается как replay и не применяется второй раз;
- conflicting retry с тем же input_sequence, но другим delta получает replay conflict и не может rebind/mutate state.

Старые movement operations после более нового durable movement больше не нужны для active-owner recovery, потому что canonical player durable state уже содержит последний `last_input_sequence`, position, velocity и state_revision.

После успешной записи snapshot P2.1 также ограничивает количество recovery JSON файлов на authority, сохраняя последние 8 generations. Удаление выполняется только после успешного atomic write/rename нового generation. Это не меняет latest-generation truth и оставляет несколько fallback generations для restore.

## Telemetry

Каждый P2.1 persist пишет отдельный event с:

- phase/generation;
- persist duration usec;
- snapshot bytes;
- replay operation count до/после compaction;
- число удалённых старых recovery snapshots;
- last input sequence.

Это позволяет отличить artificial outage pause от реального MOVE durability cost.

## Реализованная динамика

Design commit:

`2999a8b2bd98d4d8b33815d1357e3702f277c61a`

Performance node:

`a5f5695cde799a7a4251cd0aa0b0a458f7b0fccd`

File:

`scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_performance.gd`

Node сохраняет последний movement replay record, удаляет более старые movement replay records до ACTIVE_OWNER persist, ограничивает recovery directory последними 8 JSON generations и публикует `SM0_P21_RECOVERY_PERSIST_PROFILE`.

Explicit process routing:

`9eb09d4039683fa617c3998d3b29f2b0d98f9e05`

File:

`scripts/runtime/seamless/sm0/sm0_authority_server_process.gd`

Существующий H4.3 path не меняется без явного `--recovery-performance=p21`. Только комбинация H4.3 fault profile + P2.1 option выбирает performance node.

Focused regression:

`4c159fe97e8af70f545d09b2ce46cd84793f385e`

File:

`tests/runtime/seamless/sm0/test_sm0_recovery_performance.gd`

Regression выполняет 40 consecutive durable movements, проверяет bounded replay ledger, bounded recovery files, exact latest restore, conflicting duplicate rejection и exact duplicate rebind без повторного применения movement.

Headless gate:

`c155319eb1a61245aa4d9544b596131feea05188`

File:

`RUN_V0_SM0_RECOVERY_PERFORMANCE_ACCEPTANCE.ps1`

Graphical comparison lab:

`50d92e0fdab71a74d73b124c210cc68250ea6fff`

File:

`RUN_V0_SM0_GRAPHICAL_RECOVERY_PERFORMANCE_LAB.ps1`

Wrapper использует существующий P2 supervisor, но во временной копии добавляет explicit P2.1 process mode и compile check performance node. Default visual holds уменьшены до 250 ms, чтобы artificial crash-lab pauses меньше маскировали реальную movement cadence.

Project Control run #620 на `50d92e0fdab71a74d73b124c210cc68250ea6fff`: SUCCESS. Это static/control evidence, не Windows Godot runtime evidence.

## Acceptance

Focused regression должен выполнить длинную серию movement + durable ACTIVE_OWNER persist и доказать:

- replay ledger не растёт линейно с movement count;
- текущая movement operation остаётся для exact/conflicting retry semantics;
- recovery directory bounded;
- restore последнего ACTIVE_OWNER generation сохраняет identity/position/sequence;
- conflicting duplicate не rebind'ит и не меняет position;
- exact duplicate rebind'ит и не применяет movement второй раз.

После focused gate запускается graphical P2.1 на Windows exact Godot `4.7.1.stable.double.custom_build.a13da4feb`. Сравнивается движение после нескольких round-trip crossings с исходным P2.

До Windows PASS нельзя утверждать, что рывки устранены; candidate только реализован и статически прошёл Project Control.

## Не входит

- отмена write-before-ACK;
- WAL/group commit production design;
- pipelined client movement;
- network prediction/interpolation optimization;
- consensus/lease/network partition;
- production handoff activation.
