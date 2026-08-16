# SM0-P2.1 — Windows headless runtime evidence

Статус: BRANCH-LOCAL EXPERIMENTAL HEADLESS PASS / GRAPHICAL VERIFICATION PENDING.

Ветка: `feature/sm0-two-authority-seamless-handoff-lab`.

Точный проверенный HEAD:

`2cb24d5d762847cd6c2670664266c6d370cac0c2`

Точный Godot runtime:

`4.7.1.stable.double.custom_build.a13da4feb`

Команда Windows runtime gate:

`RUN_V0_SM0_RECOVERY_PERFORMANCE_ACCEPTANCE.ps1`

Никакой production/global/V0-S1 acceptance этим документом не объявляется. Cross-server authority остаётся CRITICAL; `SERVER_HANDOFF` остаётся за `stop_before` V0-S1.

## Результат

Пользовательский Windows runtime на exact candidate завершился без ошибок.

Compile checks PASS для:

- `sm0_authority_server_node_recovery_performance.gd`;
- `sm0_authority_server_process.gd`;
- `test_sm0_recovery_performance.gd`;
- `test_sm0_active_owner_recovery.gd`.

Established active-owner recovery regression:

`SM0 active owner recovery: PASS (41 assertions)`.

Focused P2.1 regression:

`SM0 P2.1 recovery performance: PASS (188 assertions, 40 durable moves)`.

Gate result:

`SM0-P2.1 bounded recovery performance: PASS`.

## Что доказал focused runtime

40 последовательных accepted movement операций прошли canonical write-before-ACK durability. Для обычного movement после compaction:

- `service_operation_count` оставался равен `2`;
- с generation 2 каждый новый movement удалял один предыдущий movement replay record;
- `replay_operations_after_compaction` оставался равен `2`;
- recovery snapshot size после начального поколения стабилизировался примерно около `9.4 KiB`, а не рос вместе с movement history;
- начиная с generation 9 на каждый новый persist удалялся один старый recovery JSON и `recovery_files_retained` оставался равен `8`;
- `cleanup_failures` оставался пустым;
- generation 40 был восстановлен точно;
- last input sequence 40 и position x≈-1.0 были восстановлены точно;
- exact durable retry rebind не применил движение второй раз;
- identity `player/a` сохранилась.

Наблюдаемый regular movement persist cost в этом focused run был в основном примерно `14–16 ms` на snapshot. После restore/rebind generation 41 занял `20570 us`; snapshot стал `12884` bytes и service operation count `3`, что соответствует дополнительной recovery/rebind операции, а не накоплению старых movement operations.

## Интерпретация

Главный обнаруженный в P2 graphical session дефект — линейный рост movement replay/history — устранён в focused runtime: размер movement replay и recovery-file history теперь bounded.

При этом P2.1 всё ещё сохраняет строгий crash-safety контракт: accepted `MOVE_ACK` ждёт durable `ACTIVE_OWNER` snapshot. Поэтому около 14–16 ms синхронной durability стоимости на movement всё ещё существует. Следующая обязательная проверка — graphical P2.1 после нескольких round-trip crossings: она должна подтвердить, что движение больше не становится всё медленнее/рывками по мере роста history. Она не обязана доказать отсутствие базового write-before-ACK latency.

## Следующий gate

Запустить:

`RUN_V0_SM0_GRAPHICAL_RECOVERY_PERFORMANCE_LAB.ps1 -Restart -RequireRecoveries 1`

В graphical session выполнить несколько переходов WEST↔EAST и после каждого перехода длительно двигаться W/S/A/D, сравнивая cadence до первого handoff и после нескольких recovery chains.

PASS для P2.1 graphical означает:

- один и тот же player identity;
- handoff/recovery остаётся корректным;
- после нескольких crossings не появляется прежняя прогрессирующая деградация движения;
- recovery generation может расти, но movement replay и file history остаются bounded;
- допускается фиксированная базовая задержка write-before-ACK, которая является отдельным следующим performance frontier.
