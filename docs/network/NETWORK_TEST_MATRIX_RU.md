# Матрица тестов сетевой бесшовности

## 1. Contract tests

| ID | Проверка | Этап |
|---|---|---|
| NC-001 | JSON round-trip всех DTO | N0 |
| NC-002 | неизвестная schema/version отклоняется | N0 |
| NC-003 | payload hash стабилен | N0 |
| NC-004 | DTO не содержит Godot runtime references | N0 |
| NC-005 | authority epoch монотонен | N0 |
| NC-006 | handoff state machine запрещает нелегальные переходы | N0 |
| NC-007 | exhaustive handoff state transition matrix | N0 |
| NC-008 | snapshot checksum и delta result checksum | N0 |
| NC-009 | nested delta path conflict/protected roots | N0 |
| NC-010 | snapshot/delta loopback replay и ID conflict | N0 |
| NC-011 | golden fixtures всех DTO сохраняют hash | N0 |
| NC-012 | missing/wrong-type/extra-field mutation matrix | N0 |
| NC-013 | EntityRegistry/Repository kernel ports strict and presentation-free | N0 |
| NC-014 | owner не меняется без повышения authority epoch | N0 fix1 |
| NC-015 | state revision и server tick не откатываются через новый epoch | N0 fix1 |
| NC-016 | delta paths с пустыми/пробельными сегментами отклоняются | N0 fix1 |
| NC-017 | forged и повреждённый kernel port отклоняются без замены live port | N0 fix1 |
| NC-018 | higher epoch с равным revision не скрывает domain-state mutation | N0 fix1 |

## 2. Single authority

| ID | Проверка | Этап |
|---|---|---|
| NS-001 | реальный bot-client подключается по ENet и получает initial snapshot | N1.1 |
| NS-001A | handshake согласует protocol, role, capabilities и contract versions | N1.1 |
| NS-001B | malformed/non-canonical wire packet отклоняется fail-closed | N1.1 |
| NS-001C | server/client подтверждают одинаковый snapshot checksum | N1.1 |
| NS-001D | ранний disconnect и timeout завершают сценарий FAIL без process leak | N1.1 |
| NS-002 | сервер применяет item command | N1.2 |
| NS-003 | duplicate operation возвращает прежний результат | N1.2 |
| NS-004 | stale revision отклоняется | N1.2 |
| NS-005 | stale epoch отклоняется | N1.2 |
| NS-005A | server/client final snapshot checksum совпадает после delta apply | N1.2 |
| NS-005B | operation ledger и mutation count остаются равны одному после exact replay | N1.2 |
| NS-005C | повторный delta ID/checksum не применяется клиентом второй раз | N1.2 |
| NS-005D | post-domain failure восстанавливает item/container/ledger/aggregate | N1.2 |
| NS-006 | disconnect/reconnect возвращает replay результата без второй mutation | N1.3 |
| NS-006A | logical session сохраняется, transport session ротируется | N1.3 |
| NS-006B | resume ticket связан с client identity, token и tick-window | N1.3 |
| NS-006C | command fingerprint/checksum conflict отклоняется | N1.3 |
| NS-006D | replay grant одноразовый и не протекает после serve | N1.3 |
| NS-006E | bounded ticket/record cache и expiry выполняются детерминированно | N1.3 |
| NS-006F | два reconnect оставляют handler/mutation/ledger равными одному | N1.3 |
| NS-006G | клиент применяет replay delta один раз и ограждает duplicate | N1.3 |
| NS-007 | два peer одновременно видят согласованную revision | T1 |

## 3. Directory и lease

| ID | Проверка | Этап |
|---|---|---|
| ND-001 | один active owner на entity/region | N3 |
| ND-002 | lease renew продлевает срок | N3 |
| ND-003 | expired lease теряет write authority | N3 |
| ND-004 | restart node получает новый epoch | N3 |
| ND-005 | concurrent acquire выбирает одного победителя | N3 |
| ND-006 | route lookup возвращает актуальный node | N3 |

## 4. Object handoff

| ID | Проверка | Этап |
|---|---|---|
| NH-001 | успешный Space → Moon handoff | N4 |
| NH-002 | duplicate prepare идемпотентен | N4 |
| NH-003 | duplicate commit идемпотентен | N4 |
| NH-004 | target crash до commit оставляет source owner | N4 |
| NH-005 | source crash до commit не активирует target | N4 |
| NH-006 | source crash после commit не откатывает target | N4 |
| NH-007 | checksum mismatch вызывает abort | N4 |
| NH-008 | position continuity | N4 |
| NH-009 | velocity continuity | N4 |
| NH-010 | mass/quantity/item graph conservation | N4 |
| NH-011 | ровно один authority и не более N ghosts | N4 |
| NH-012 | stale source update после commit отвергается | N4 |

## 5. Player handoff

| ID | Проверка | Этап |
|---|---|---|
| NP-001 | warm connection установлена до commit | N5 |
| NP-002 | player UUID не меняется | N5 |
| NP-003 | input sequence не теряется | N5 |
| NP-004 | inventory checksum не меняется | N5 |
| NP-005 | UI/camera не пересоздаются | N5 |
| NP-006 | 100 циклов boundary без дублей | N5 |
| NP-007 | reconnect во время prepare | N5 |

## 6. Ghost и interest

| ID | Проверка | Этап |
|---|---|---|
| NG-001 | ghost read-only | N6 |
| NG-002 | ghost expiration | N6 |
| NG-003 | hysteresis предотвращает boundary thrashing | N6 |
| NG-004 | interest filter не пропускает далёкие entities | N6 |
| NG-005 | bandwidth budget | N6 |
| NG-006 | collision-critical island остаётся у одного authority | N6/N9 |

## 7. Child spaces

| ID | Проверка | Этап |
|---|---|---|
| NCV-001 | Moon surface → cave | N7 |
| NCV-002 | cave → Moon surface | N7 |
| NCV-003 | parent projection обновляется | N7 |
| NCV-004 | child crash закрывает portal fail-safe | N7 |
| NCV-005 | сохранение inventory/attachments | N7 |

## 8. Fault profiles

Каждый критический handoff-тест должен параметризоваться:

```text
LAN:            1 ms,   0% loss
Good WAN:      40 ms,   0.1% loss
Inter-region: 120 ms,   0.5% loss
Bad mobile:   180 ms,   3% loss, 20 ms jitter
Burst loss:    80 ms,  10% loss на коротком интервале
Reorder:       60 ms,   2% reorder
Partition:    disconnect 1–10 s
```

## 9. Conservation invariants

После каждого сценария автоматически проверяются:

```text
sum(item.quantity)
sum(item.mass)
set(entity_id)
container membership uniqueness
attachment uniqueness
state_revision monotonicity
authority_epoch monotonicity
operation ledger consistency
no duplicate authority
no orphan ghost after TTL
```

## 10. Обязательный regression gate

Новая игровая функция считается network-ready, если проходит:

```text
offline domain test
headless scene test
single-authority remote test
save/restart test
stale revision/epoch test
```

Handoff-specific тест требуется только для объектов, которые могут пересекать authority boundary.

## R3.1 persistence/recovery additions

| ID | Проверка | Этап |
|---|---|---|
| PR-001 | committed checkpoint восстанавливает snapshot/revision/epoch/tick | R3.1 |
| PR-002 | exact operation replay после restart не вызывает вторую mutation | R3.1 |
| PR-003 | orphan pending checkpoint не становится active | R3.1 |
| PR-004 | corrupted active checkpoint отклоняется fail-closed | R3.1 |
| PR-005 | generation/epoch/revision/tick rollback отклоняется | R3.1 |
| PR-006 | failed staged recovery не изменяет live state | R3.1 |
| PR-007 | legacy world.json требует явной migration | R3.1 |

## 11. H0 listen-host gates — accepted

| ID | Проверка | Этап |
|---|---|---|
| LH-001 | client replica не содержит ссылки на server Objects | H0 |
| LH-002 | loopback command проходит canonical serialization boundary | H0 |
| LH-003 | loopback и ENet дают одинаковый final checksum | H0 |
| LH-004 | UI не может вызвать authoritative service напрямую | H0 |
| LH-005 | duplicate delta применяется client replica один раз | H0 |
| LH-006 | listen-host process и ENet comparison children завершаются без leaks | H0 |
| LH-007 | stale client revision отклоняется без второй authoritative mutation | H0 |
| LH-008 | exact operation replay возвращает результат, duplicate delta fenced | H0 |

## 12. Generic aggregate и spatial gates — A1/S0 accepted

| ID | Проверка | Этап |
|---|---|---|
| AG-001 | unknown aggregate kind/schema отклоняется | A1 |
| AG-002 | aggregate snapshot/delta canonical round-trip | A1 |
| AG-003 | item compatibility adapter сохраняет N1 semantics | A1 |
| AG-004 | aggregate adapter не экспортирует runtime Objects | A1 |
| SP-001 | cell address стабилен при render-origin shift | S0 |
| SP-002 | одна cell индексирует несколько aggregate kinds | S0 |
| SP-003 | aggregate spatial scope покрывает несколько cells | S0 |
| SP-004 | authority owner не выводится из cell ID | S0 |
| SP-005 | shard neighbour/boundary summary canonical | S0 |
| SP-006 | child cell требует зарегистрированный parent и находится в его bounds | S0 |
| SP-007 | одна cell хранит shards с разными authority addresses | S0 |
| SP-008 | owner change требует повышенного authority epoch | S0 |
| SP-009 | boundary summary revision/tick stream монотонен | S0 |
| SP-010 | reverse duplicate bidirectional topology link отклоняется | S0 |

## 13. Multi-peer и message-bus gates — T1/B0 accepted

| ID | Проверка | Этап |
|---|---|---|
| TP-001 | listener остаётся LISTENING при disconnect одного peer | T1 |
| TP-002 | peer sessions имеют независимые lifecycle/sequence | T1 |
| TP-003 | per-peer queues и metrics не смешиваются | T1 |
| TP-004 | frame v2 routes by channel/payload schema | T1 |
| TP-005 | N1 compatibility shim сохраняет accepted vertical slice | T1 |
| TP-006 | route change требует monotonic route generation | T1 |
| TP-007 | stale transport session fenced после reconnect | T1 |
| TP-008 | один ENet listener обслуживает два client process и сохраняет targeted isolation | T1 |
| TP-009 | outgoing sequence commit происходит только после successful enqueue | T1 |
| BUS-001 | semantic port round-trip не зависит от adapter | B0 |
| BUS-002 | job/event/request semantics нельзя взаимозаменить | B0 |
| BUS-003 | domain state не содержит subject/channel/broker ID | B0 |
| BUS-004 | timeout/backpressure result strict and versioned | B0 |
| BUS-005 | exact request replay не вызывает второй handler call; changed request ID conflict отклоняется | B0 |
| BUS-006 | event sequence монотонен, exact duplicate идемпотентен, buffered capacity даёт backpressure | B0 |
| BUS-007 | job claim/ack/retry сохраняет worker fence, attempt limit и delivery identity | B0 |
| BUS-008 | replication backpressure изолирован per peer и не блокирует соседний peer | B0 |
| BUS-009 | bulk object проверяет canonical base64, size, SHA-256, capacity и ID conflict | B0 |
| BUS-010 | direct/routed request-reply и direct/buffered event adapters дают одинаковую application semantics | B0 |

## 14. Transaction/outbox gates

| ID | Проверка | Этап |
|---|---|---|
| TX-001 | batch над двумя aggregates commit all-or-nothing | M0 |
| TX-002 | staged failure не меняет live aggregates | M0 |
| TX-003 | duplicate operation не создаёт второй aggregate | M0 |
| TX-004 | state/result/ledger/outbox восстанавливаются вместе | M0 |
| TX-005 | conservation invariant failure aborts batch | M0 |
| TX-006 | crash between commit and publish leaves durable outbox | M0/B2 |
| TX-007 | item/container cross-reference conservation проверяется до prepare | M0 |
| TX-008 | result effect sets и outbox/result cross-links каноничны | M0 |
| TX-009 | outbox publish transition не меняет aggregate snapshots | M0 |

## 15. Distributed compute gates

| ID | Проверка | Этап |
|---|---|---|
| DC-001 | worker input immutable и checksum-bound | S1 |
| DC-002 | worker не получает repository/registry write port | S1 |
| DC-003 | same input/package даёт same result hash | S1 |
| DC-004 | stale proposal rejected without mutation | S1 |
| DC-005 | undeclared write set rejected | S1 |
| DC-006 | budget overflow rejected | S1 |
| DC-007 | duplicate result processed once | S1/B2 |

## 16. Population/materialization gates

| ID | Проверка | Этап |
|---|---|---|
| PF-001 | field regenerates same visual instances from seed | P0 |
| PF-002 | procedural instance key stable within generation | P0 |
| PF-003 | materialization changes field and creates item atomically | P0 |
| PF-004 | replay/restart does not create duplicate item | P0 |
| PF-005 | mass disturbance compacts to patch state | P0 |
| PF-006 | aggregate delta updates client procedural representation | P0/D1 |
