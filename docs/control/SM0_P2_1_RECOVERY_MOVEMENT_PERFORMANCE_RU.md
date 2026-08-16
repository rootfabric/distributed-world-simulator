# SM0-P2.1 — bounded movement recovery / graphical latency hardening

Статус: IMPLEMENTATION IN PROGRESS / branch-local experimental.

Ветка: `feature/sm0-two-authority-seamless-handoff-lab`.

База: `aa577148be8773aa77681285cfd9c969580f95ed`.

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

## Acceptance

Focused regression должен выполнить длинную серию movement + durable ACTIVE_OWNER persist и доказать:

- replay ledger не растёт линейно с movement count;
- текущая movement operation остаётся для exact/conflicting retry semantics;
- recovery directory bounded;
- restore последнего ACTIVE_OWNER generation сохраняет identity/position/sequence;
- conflicting duplicate не rebind'ит и не меняет position;
- exact duplicate rebind'ит и не применяет movement второй раз.

После focused gate запускается graphical P2.1 на Windows exact Godot `4.7.1.stable.double.custom_build.a13da4feb`. Сравнивается движение после нескольких round-trip crossings с исходным P2.

## Не входит

- отмена write-before-ACK;
- WAL/group commit production design;
- pipelined client movement;
- network prediction/interpolation optimization;
- consensus/lease/network partition;
- production handoff activation.
