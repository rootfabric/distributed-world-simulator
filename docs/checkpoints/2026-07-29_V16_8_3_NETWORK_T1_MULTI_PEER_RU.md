# Checkpoint v16.8.3 — T1 Multi-peer Transport v2

**Статус:** candidate
**Ветка:** `feature/t1-multi-peer-transport-v2`
**База:** `v16.8.2-simulation-s0-spatial-substrate`
**Build ID:** `t1-multi-peer-transport-v2`

## Реализовано

- `ProtocolFrame v2` с channel и payload schema routing;
- строгий `NetworkTransportEvent v2`;
- отдельный `NetworkPeerSession` lifecycle;
- listener lifecycle, независимый от peer readiness;
- `send_to_peer(peer_id, frame)`;
- реальные per-peer FIFO с message/byte limits и backpressure;
- route generation независимо от authority epoch;
- loopback multi-peer port;
- ENet multi-peer port;
- single-peer v1 compatibility adapter;
- real-process сценарий: один server и два одновременных ENet clients.

## Acceptance gates

```text
T1 contracts
T1 multi-process ENet
full network regression
full world regression
main scene offline/listen-host
simulation-server lifecycle
```

## Результаты локальной проверки candidate

```text
Editor import/parse:              PASS
T1 contracts:                    121/121 PASS
T1 real-process ENet:             20/20 PASS
Multi-peer process repetitions:     5/5 PASS
Full network profile:             31/31 suites, 2535/2535 assertions
World standalone scripts:         74/74 PASS
Equivalent world runner steps:    77/77 PASS
Main scene offline:                 6 PASS, 0 FAIL
Main scene listen-host:             6 PASS, 0 FAIL
Simulation-server lifecycle:       PASS
```

Два ENet-клиента удерживаются подключёнными до серверного барьера. Ответы отправляются только после одновременного наблюдения обоих peer sessions, поэтому process gate не может ложно пройти за счёт двух последовательных одиночных соединений.

## Архитектурный результат

Server listener больше не меняет глобальное состояние при подключении одного peer. Reconnect одного peer создаёт новую transport session и route generation, не меняя authority owner/epoch и не затрагивая другие sessions.

`send_to_peer()` теперь помещает frame в реальную per-peer outbound FIFO. Queue metrics освобождаются только после успешного dispatch в adapter; переполнение peer A не блокирует enqueue и dispatch peer B.

Подробности: [`../architecture/T1_MULTI_PEER_TRANSPORT_V2_RU.md`](../architecture/T1_MULTI_PEER_TRANSPORT_V2_RU.md).
