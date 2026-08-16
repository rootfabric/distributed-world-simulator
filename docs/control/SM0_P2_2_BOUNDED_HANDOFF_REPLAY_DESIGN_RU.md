# SM0 P2.2 — bounded handoff replay / movement throughput

Статус: branch-local experimental design. Это не production/global acceptance и не изменение V0-S1 stop-before policy.

## Наблюдение

В P2.1 после устранения рывков графический H4.3 lab сохраняет корректный canonical movement delta/velocity через handoff, но эффективная частота движения постепенно падает после повторных recovery chains. В пользовательском прогоне на `d61d8b74a78e4266574c1758aa2cba5767f33069` все `SM0_CROSSING_COMPLETED` сохранили `velocity.x = +/-0.25`, однако время `SM0_CLIENT_ROUTE_SWITCHING -> SM0_CROSSING_COMPLETED` выросло примерно с 3.66 s до 3.88 s за шесть crossing.

P2.1 уже ограничивает историю MOVEMENT_DELTA replay и число recovery snapshot files. Но каждый durable ACTIVE_OWNER snapshot всё ещё сериализует полный `gameplay_replay_state`, а service operation ledger сохраняет старые SM0 join/leave/import/rebind records. Recovery snapshot также сохраняет все исторические `prepared_transfers` и `committed_transfers`. Поэтому стоимость checksum/validation/JSON/write остаётся зависящей от числа handoff/recovery операций.

## Цель P2.2

Ограничить именно исторический replay metadata, не ослабляя текущий handoff/recovery chain:

- сохранить latest durable movement replay для crash-before-ACK duplicate semantics;
- сохранить по одному наиболее свежему replay record на каждый SM0 internal operation class, чтобы непосредственный retry текущей join/import/rebind операции оставался replay-safe;
- удалить более старые SM0 internal service-operation records перед записью нового recovery snapshot;
- в transfer maps сохранять только transfer, относящийся к текущей durable phase/current directory; при SOURCE_RETIRED старый target-side history не является canonical recovery source и может быть отброшен в P2.2 experiment;
- продолжить сохранять recovery files с существующим retention=8;
- добавить telemetry before/after counts, чтобы графический прогон показывал, что state size действительно bounded.

## Неизменяемые свойства

- write-before-ACK ACTIVE_OWNER durability остаётся обязательной;
- latest exact movement replay не удаляется;
- текущий TARGET_PREPARED/TARGET_COMMITTED transfer не удаляется;
- текущий committed transfer владельца сохраняется через ACTIVE_OWNER;
- H4.3 PREPARED -> COMMITTED -> ACTIVE recovery-of-recovery fault chain остаётся тем же;
- P2.1 profile `p21` не меняется; P2.2 включается отдельным `--recovery-performance=p22`.

## Проверка

1. Compile new P2.2 node/process/test.
2. Established P2.1 gate должен продолжить PASS без изменения p21 semantics.
3. P2.2 focused test создаёт искусственно разросшийся valid service replay ledger и stale transfer history, пишет ACTIVE_OWNER snapshot и проверяет bounded retained records + latest movement replay.
4. Графический P2.2 lab: не менее 6 crossing на одном client PID. Проверить отсутствие рывков, отсутствие субъективного замедления и собрать per-chain timing. H4.3 visual transition по-прежнему искусственно включает три total outages; его абсолютные ~seconds не являются normal handoff latency.
