# Checkpoint v16.5.2-foundation-network-n1

Дата: 2026-07-28
Статус: candidate N1.3
Build ID: `n1-reconnect-replay-bounded-cache`
База: `v16.5.1-network-n1-remote-item-command`
Ветка: `feature/n1-reconnect-replay`

## Цель

Закрыть N1 доказательством reconnect/replay после потери ответа: сервер коммитит `item.move_to_container`, соединение обрывается до доставки результата, клиент подключается с новой transport session и повторяет прежний `operation_id`. Сервер возвращает сохранённые result/delta без второй доменной мутации.

## Реализовано

- разделены logical session и сменяемая ENet transport session;
- добавлены строгие DTO `NetworkResumeTicket`, `NetworkSessionResumeEnvelope`, `NetworkSessionResumeResult`;
- resume-ticket содержит криптографически случайный token, ограниченный tick-window и identity клиента;
- bounded replay cache ограничивает количество tickets/records, TTL и число resume на ticket;
- replay record связывает command fingerprint, result, delta, base/final snapshot и checksum;
- resume разрешён только тому же client, logical session, `operation_id` и command fingerprint;
- replay grant одноразовый для конкретной новой transport session;
- exact replay не вызывает `ItemTransferService`, не повышает revision/tick и не создаёт вторую ledger-запись;
- клиент применяет delta один раз и ограждает повторную replay-доставку;
- server/client session имеют progress-based idle timeout 6000 мс;
- добавлен реальный двухпроцессный ENet-сценарий с двумя последовательными reconnect.

## Основной сценарий

```text
initial handshake + snapshot
→ item.move_to_container
→ server commits mutation
→ connection drops before result
→ reconnect with new transport session
→ SESSION_RESUME
→ same operation_id is resent
→ cached result + delta
→ client checksum == server checksum
→ second reconnect/replay
→ mutation_count remains 1
```

## Инварианты

```text
handler_invocation_count = 1
mutation_count = 1
operation_ledger_count = 1
aggregate revision: 12 → 13 once
server tick: 500 → 501 once
transport sessions = 3 unique
replay serves = 2
client delta applications = 1
```

## Ограничения N1

Replay cache пока process-local и не переживает рестарт authoritative-server. Персистентный dedup/replay и crash recovery входят в R3.1. Общий кроссплатформенный orchestration/fault harness входит в N2.

## Acceptance

- N1.3 contracts и mutation tests проходят;
- два отдельных Godot-процесса проходят reconnect/replay;
- первая mutation выполняется ровно один раз;
- новая transport session не меняет logical operation identity;
- cached result/delta совпадают с исходным commit;
- повторная delta не изменяет клиентский snapshot;
- bounded cache, expiry, conflict и resume-limit проверки проходят;
- полный network profile и world regression остаются зелёными.

## Следующий этап

`N2 — multi-process test harness`, ветка `feature/n2-process-harness`.
