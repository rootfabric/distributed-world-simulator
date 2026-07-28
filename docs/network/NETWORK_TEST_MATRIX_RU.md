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
| NS-007 | два клиента видят одинаковую revision | N2 |

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
