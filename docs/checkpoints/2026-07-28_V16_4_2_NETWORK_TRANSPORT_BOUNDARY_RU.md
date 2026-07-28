# v16.4.2 Network Transport Boundary

Статус: candidate для независимой проверки.

База: `v16.4.1-foundation-inventory-merge`.

Build ID: `n1-transport-lifecycle-boundary`.

## Реализовано

- канонический `NetworkTransportPort`;
- строгая проверка наследования port script;
- exact descriptor schema;
- lifecycle `STOPPED/STARTING/LISTENING/CONNECTING/READY/DRAINING/FAILED`;
- allowlist сетевых message types;
- canonical JSON fence;
- запрет Godot runtime objects в payload;
- payload-size и outbound-queue limits;
- идемпотентные drain/stop;
- loopback port для проверки общего boundary;
- отдельный regression test.

## Не входит

- ENet socket;
- handshake DTO;
- отдельный bot-client process;
- remote item command;
- reconnect/replay storage.

Эти части относятся к N1.1–N1.3.

## Acceptance

```text
editor import/parse: PASS
N1 transport boundary test: PASS
N0 profile including N1.0 test: PASS
full regression including new test: PASS
git diff --check: PASS
```
