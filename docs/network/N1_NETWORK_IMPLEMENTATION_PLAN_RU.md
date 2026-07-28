# План реализации сетевой части N1–N5

## Текущая база

```text
v16.4.2-network-transport-boundary       принят
v16.5.0-network-n1-snapshot              принят
v16.5.1-network-n1-remote-item-command   принят
v16.5.2-foundation-network-n1            candidate N1.3
```

## Критический путь

```text
N1.0 transport boundary                   ACCEPTED
→ N1.1 ENet handshake + initial snapshot ACCEPTED
→ N1.2 remote item.move_to_container     ACCEPTED
→ N1.3 reconnect + bounded replay        CURRENT CANDIDATE
→ N2 multi-process harness               NEXT
→ R3.1 persistence/recovery
→ N3 World Directory
→ N4 cross-server handoff
→ N5 ghost replicas/interest management
```

## N1.3 — reconnect и replay

Checkpoint: `v16.5.2-foundation-network-n1`.
Ветка: `feature/n1-reconnect-replay`.

Сервер коммитит команду, но обрывает соединение до доставки результата. Клиент подключается с новой transport session, предъявляет ограниченный resume-ticket и повторяет прежний `operation_id`. Replay cache возвращает исходные result/delta без повторного вызова domain handler.

Обязательные свойства:

- logical session не меняется при reconnect;
- transport session меняется на каждом reconnect;
- resume ticket связан с client identity, logical session, token и tick-window;
- command fingerprint, operation ID и last snapshot checksum совпадают;
- replay grant одноразовый и связан с новой transport session;
- cache ограничен по tickets, records, TTL и resume count;
- повторная доставка delta не применяет mutation второй раз;
- handler, mutation и ledger record остаются равными одному;
- server/client checksum совпадает после reconnect.

N1.3 намеренно не сохраняет replay cache после рестарта server process. Это обязанность R3.1.

## N2 — общий multi-process harness

Следующая ветка: `feature/n2-process-harness`.
Target checkpoint: `v16.6.0-network-n2-process-harness`.

Один кроссплатформенный runner должен:

1. выбирать свободные порты;
2. создавать isolated `user://` для каждого процесса;
3. запускать server/client и ждать readiness;
4. выполнять handshake, command, disconnect/reconnect и fault scenarios;
5. контролировать per-state timeout;
6. собирать stdout/stderr и machine-readable события;
7. завершать или принудительно очищать дочерние процессы;
8. формировать JSON и JUnit отчёты.

Минимальные сценарии N2:

```text
handshake_and_snapshot
remote_item_command
lost_result_reconnect_replay
malformed_packet
stale_revision
stale_authority
disconnect_during_handshake
server_drain
process_timeout_cleanup
```

## R3.1 — persistence/recovery

После N2 replay/dedup records, ledger и authoritative snapshot должны переживать server restart. Повторный `operation_id` после crash возвращает прежний terminal result и не выполняет mutation заново.

## N3–N5

- N3: World Directory, node heartbeat, authority lease/route и epoch fencing.
- N4: make-before-break cross-server authority handoff.
- N5: bounded ghost replicas и interest management.

## Правила веток

- новый этап: отдельная короткая `feature/<stage>-<purpose>` ветка;
- review fixes непринятого checkpoint: в той же ветке отдельными `fix(...)` commits;
- новая fix-ветка: только для уже принятого и влитого checkpoint;
- каждый patch содержит только изменённые файлы и сопровождается branch/apply/commit/test инструкцией.
