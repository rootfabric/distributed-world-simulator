# H1 — Playable listen-host

**Checkpoint:** `v16.9.1-runtime-h1-playable-listen-host`
**Build ID:** `h1-playable-listen-host`
**Статус:** candidate
**База:** `v16.9.0-simulation-s1-distributed-compute-fix1`

## 1. Назначение

H1 переводит обычный графический запуск PlanetSimulator на network-first композицию. Authority и graphical client остаются в одном процессе, но больше не разделяют один live domain object graph.

```text
input / UI
→ replica controller
→ PlayableItemCommandBridge или player command DTO
→ ClientRuntime
→ loopback command transport
→ PlayableListenHostAuthority
→ authoritative mutation
→ command result + EntityDelta
→ ClientReplicaStore
→ graphical replica / presentation
```

`offline` сохраняется как явно выбранный режим для инструментов, fixtures и диагностики. Запуск без `--role` использует `listen-host`.

## 2. Разделение ролей

### Embedded authority

`PlayableListenHostAuthority` создаётся под отдельным узлом `ListenHostAuthorityHost` и владеет:

- authoritative player state;
- authoritative Item Graph;
- persistence Item Graph;
- operation replay ledger;
- session, authority epoch, revision и tick fencing;
- проверкой дистанции до world item, container и mount socket.

Authority не создаёт UI, Presenter или world presentation nodes.

### Graphical client

Графический runtime получает только ограниченный `PlayableClientSession`. Session предоставляет snapshot/command/delta API и не предоставляет `ListenHostRuntime`, authoritative store, authority controller или метод повторной композиции authority. `ItemGameplayController` работает в режиме `replica`:

- локальный graph загружается из `ClientReplicaStore`;
- mutation methods формируют command DTO;
- authoritative result применяется до обновления UI;
- persistence отключена;
- прямой authority/domain reference отсутствует;
- invalidated session после detach больше не выдаёт snapshot, bridge или command result.

### SimulationKernel

Только доверенная композиция `SimulatorApp` может передать authoritative `WorldEntityStore` в `SimulationKernel`. Это kernel port, а не клиентский gameplay API.

## 3. Реплицируемое состояние игрока

`PlayableStateCodec` задаёт JSON-safe DTO:

```text
schema
spatial_ref
interaction_position_m
controller_id
camera_mode
flashlight_enabled
last_input_sequence
```

DTO проходит canonical JSON boundary. `Node`, `Object`, `Transform3D`, `Basis`, NaN, Infinity и дополнительные поля через boundary не проходят.

В H1 graphical player сначала формирует candidate state, после чего authority проверяет:

- session ID;
- authority epoch;
- expected revision;
- monotonic input sequence;
- конечность координат и скорости;
- максимальную скорость;
- максимальное перемещение за command interval.

Принятое состояние возвращается как `EntityDelta` и повторно применяется к graphical player. Полноценная input prediction/reconciliation model остаётся для H2/A2.

## 4. Item и container commands

Через authority проходят:

- выбор hotbar slot;
- transfer, stack и split;
- pickup;
- drop;
- mount и detach;
- placement;
- открытие и закрытие внешнего контейнера;
- debug grant;
- save и reload authoritative Item Graph.

Authority отклоняет:

- stale revision или epoch;
- неверную session;
- повтор operation ID с другим fingerprint;
- pickup предмета вне мира или вне дистанции;
- transfer из/в недоступный container;
- split с нулевым, отрицательным или чрезмерным quantity;
- drop/placement вне допустимой дистанции;
- mount/detach вне дистанции до socket parent.

Точный replay возвращает прежний result и не повторяет mutation.

## 5. Persistence и lifecycle

Authoritative Item Graph загружается и сохраняется только authority-контроллером. Replica-контроллер persistence не выполняет.

При остановке мира:

1. graphical replica отправляет `item.save` через command boundary;
2. runtime drain завершается;
3. playable authority сохраняет graph;
4. bridge инвалидируется;
5. authority node освобождается;
6. старый bridge после detach больше не принимает команды.

## 6. Compatibility

Принятый H0 fixture сохранён без замены. Его isolated command/snapshot scenario по-прежнему используется для regression и transport-equivalence tests.

H1 не меняет:

- N1 ENet contracts;
- T1 multi-peer transport;
- B0 message bus ports;
- M0 aggregate transactions;
- S1 distributed compute protocol.

## 7. Проверка

```text
H1 target:                 39 + 71 + 76 + 32 assertions PASS
Network profile:           39/39 suites, 3168/3168 assertions PASS
World regression:          82/82 tests, 85/85 steps PASS
Main scene:                6/6 PASS
Heavy runtime scenarios:   3/3 PASS
Runtime roles:             offline/listen-host/simulation-server PASS
Editor import:             PASS
```

Печатный runtime descriptor формируется после загрузки активного мира, поэтому отражает уже подключённый playable authority, а не промежуточную bootstrap-композицию. Отдельный H1 boot gate для `earth_moon` подтверждает `8/8` runtime-проверок, включая configured client session и отсутствие client authority/domain references.

## 8. Ограничения H1

H1 намеренно не включает:

- отдельный graphical client process;
- dedicated connection UI;
- второго игрока;
- remote player interpolation;
- NATS или JetStream;
- межсерверный routing и handoff;
- server-side character input integrator и prediction protocol.

Следующий этап H2 должен заменить loopback topology на отдельный headless authority, не меняя UI и gameplay command semantics.
