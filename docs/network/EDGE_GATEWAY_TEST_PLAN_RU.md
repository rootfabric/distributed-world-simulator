# Edge Gateway Validation and Test Plan

**Дата:** 2026-08-18  
**Статус:** RESEARCH TEST PLAN / НЕ PRODUCTION ACCEPTANCE  
**Ветка:** `research/edge-gateway-architecture`  
**Связанный design:** `docs/network/EDGE_GATEWAY_ARCHITECTURE_RU.md`

Цель этого документа — заранее определить проверяемые свойства multi-region Edge Gateway, чтобы архитектура не стала набором красивых routing abstractions без доказательства correctness, latency behavior, failure isolation и scale properties.

---

## 1. Главные свойства, которые должны быть доказаны

```text
G1  client имеет один stable gateway session;
G2  authority handoff не меняет client transport endpoint;
G3  gateway не создаёт canonical state;
G4  PRIMARY route всегда соответствует committed owner/AuthorityEpoch;
G5  OBSERVER state всегда read-only;
G6  stale/rollback route не может перехватить command;
G7  gateway selection выбирает лучший healthy edge endpoint;
G8  gateway crash не меняет player/entity identity;
G9  duplicate/replayed operation не создаёт второй canonical commit;
G10 physical upstream connections масштабируются по gateway-authority pairs, а не client-authority pairs;
G11 slow client или slow authority не блокирует остальные sessions;
G12 loss/jitter/reorder не создают split-brain или duplicate presentation identity.
```

---

## 2. Типы тестов

Каждый runtime этап должен комбинировать несколько уровней.

### A. Pure contract tests

Без реальных sockets/processes:

- exact fields;
- schema/version;
- deterministic hash/checksum;
- invalid enum/identifier;
- epoch rollback;
- route revision rollback;
- replayed OperationId;
- malformed signed/catalog metadata;
- PRIMARY без ownership proof;
- OBSERVER mutation attempt.

### B. Deterministic model tests

Pure state machines:

- gateway selection;
- route lifecycle;
- role flip;
- hysteresis;
- draining;
- stale route resolution;
- connection pooling accounting;
- failover/rehome state machine.

### C. Real process tests

Отдельные процессы:

```text
client
edge gateway(s)
authority A/B/C
optional directory
```

Проверяют реальный transport lifecycle и отсутствие скрытой in-process coupling.

### D. Controlled network-condition tests

Переиспользовать существующий NX1-style deterministic condition simulator:

- latency;
- jitter;
- loss;
- duplicate;
- reorder;
- bandwidth limit;
- queue pressure;
- lag spike;
- disconnect;
- asymmetric network.

### E. Crash/restart tests

Kill/restart:

- gateway;
- primary authority;
- observer authority;
- directory/route source where applicable;
- client.

### F. Scale/soak tests

Проверять не только correctness, но и connection topology, queues, memory, route churn и operation throughput.

---

## 3. EG0 — Contract Freeze tests

### EG0-C1 Gateway identifiers

Проверить:

```text
GatewayId required
GatewayRegionId required
ClientSessionId required
GatewaySessionId != ClientSessionId
```

Negative:

- empty ids;
- invalid characters if canonical format introduced;
- duplicated gateway id with conflicting metadata.

### EG0-C2 GatewayCatalog

Catalog entry содержит endpoint/protocol/health/capacity metadata и проходит authenticity validation.

Negative:

- tampered endpoint;
- stale health epoch;
- unsupported protocol version;
- unsigned/invalid signature metadata.

### EG0-C3 Route update fencing

Вход:

```text
entity=player/42
owner=A
epoch=71
route_revision=12
```

Проверить:

- exact replay -> accepted as replay/no-op;
- revision 11 -> reject;
- epoch 70 -> reject;
- same epoch/revision different owner -> reject;
- epoch 72 owner B with valid ownership proof -> accept;
- PRIMARY assignment without required committed proof -> reject.

### EG0-C4 Operation envelope

Negative:

- missing OperationId;
- malformed entity id;
- expected epoch zero;
- payload hash mismatch;
- duplicate OperationId with different payload;
- gateway attempts to rewrite OperationId.

---

## 4. EG1 — Single Gateway / Single Authority

Topology:

```text
Client -> Gateway G1 -> Authority A
```

### EG1-P1 Transparent gameplay equivalence

Запустить один и тот же deterministic command script:

```text
direct client -> A
client -> G1 -> A
```

Canonical result hash должен совпасть.

Gateway path не должен создавать второй gameplay code path.

### EG1-P2 Stable identity

После connect/play/disconnect/reconnect к тому же gateway:

```text
ClientSessionId expected according to reconnect contract
PlayerEntityId unchanged
Authority ownership unchanged unless authority protocol changed it
```

### EG1-P3 Gateway has no canonical writer

Static/runtime assertions:

- gateway не владеет Item Graph store;
- gateway не вызывает gameplay mutation APIs напрямую;
- gateway-generated presentation object имеет `canonical_write_allowed=false`;
- попытка local presentation mutation deterministic reject.

### EG1-P4 Authority unavailable

При падении A:

- gateway остаётся process-alive;
- route переходит DEGRADED;
- client получает deterministic unavailable/degraded state;
- никакой synthetic ownership не создаётся.

---

## 5. EG2 — Multi-Authority View Composition

Topology:

```text
             A PRIMARY
            /
Client -> G1
            \
             B OBSERVER
```

### EG2-P1 One entity identity

Один `player/42`, видимый из A и B, не должен стать двумя client entities.

Expected:

```text
canonical identity count = 1
presentation duplicates = 0
```

### EG2-P2 Foreign read-only

B projection содержит owner/epoch/revision/checksum.

Проверить:

- OBSERVER presentation видима;
- client interaction routed к current owner A;
- попытка записать в B foreign replica reject;
- gateway не меняет B projection locally.

### EG2-P3 Projection sequence fencing

Negative:

- epoch rollback;
- sequence rollback;
- same sequence different checksum;
- stale cached representation incorrectly marked fresh.

### EG2-P4 Source degradation

Отключить B:

- A PRIMARY продолжает работать;
- gateway не разрывает client session;
- cached coarse B representation может остаться только как explicitly stale presentation;
- command никогда не уходит в stale B route.

---

## 6. EG3 — Gateway-Mediated Handoff

Topology:

```text
Client -> G1 -> A + B
```

Initial:

```text
A PRIMARY epoch 71
B OBSERVER/WARM
```

### EG3-P1 Normal handoff

Authority protocol:

```text
A FREEZE
B PREPARE
Directory COMMIT B/72
A RETIRE
B ACTIVATE
```

Expected gateway behavior:

```text
before commit: A remains PRIMARY
at/after valid commit: B becomes PRIMARY
A becomes OBSERVER
```

Acceptance counters:

```text
client_disconnects_during_handoff = 0
client_session_changes = 0
player_identity_changes = 0
split_brain_observations = 0
commands_committed_by_old_epoch_after_flip = 0
```

### EG3-P2 Premature route flip

Inject fake B/72 PRIMARY update before canonical commit.

Expected: fail closed.

### EG3-P3 Delayed route update

Canonical handoff commits, но gateway получает update позже.

Expected:

- старый A route не должен получить mutation, которую authority epoch уже fence'ит;
- bounded resolve/retry policy deterministic;
- operation never commits twice.

### EG3-P4 Reordered ownership messages

Deliver:

```text
B/72
then stale A/71
```

Expected: B remains PRIMARY, stale rollback rejected.

### EG3-P5 Crash at each phase

Fault matrix:

```text
A crash before freeze
A crash after freeze
B crash before prepare
B crash after prepare
crash around directory commit
A crash before retire ack
B crash before activate ack
```

Gateway verdict должен всегда быть производным от recoverable canonical ownership state, а не от последнего увиденного process packet.

---

## 7. EG4 — Multi-Gateway Discovery and Selection

Topology:

```text
G1 RTT 20 ms
G2 RTT 45 ms
G3 RTT 90 ms
```

### EG4-P1 Basic RTT choice

Все gateways healthy/equal load.

Expected: client выбирает G1.

### EG4-P2 Load-aware choice

```text
G1 RTT 20 ms, overloaded
G2 RTT 28 ms, healthy
```

Expected определяется формально заданным score. Test проверяет deterministic score, а не hardcoded region name.

### EG4-P3 Packet loss penalty

```text
G1 18 ms, 8% loss
G2 25 ms, 0% loss
```

Ожидаемый выбор должен следовать score policy.

### EG4-P4 Hysteresis

После connect к G1:

```text
G2 становится быстрее на 2-3 ms
```

Expected: no switch.

Затем G2 становится существенно лучше на duration, превышающий threshold.

Expected: switch только если migration/rehome checkpoint активирован; до EG5 выбор сохраняется sticky и только фиксирует better-candidate metric.

### EG4-P5 Gateway health override

G1 health становится unhealthy/draining.

Expected: G1 не выбирается новым client независимо от ping.

### EG4-P6 Geographic names are not logic

Переименовать regions/candidate ordering.

Expected selection не меняется при тех же metrics.

---

## 8. EG5 — Gateway Failure and Session Rehome

Topology:

```text
Client -> G1
          |
        A/B

alternate G2 available
```

### EG5-P1 Hard gateway crash

Kill G1 без graceful shutdown.

Client подключается к G2.

Expected:

```text
PlayerEntityId unchanged
canonical ownership unchanged
AuthorityEpoch not invented by G2
operation ledger dedup preserved
```

Допускается transport reconnect между client и gateway; не допускается gameplay identity reset.

### EG5-P2 In-flight operation during crash

Отправить `OperationId=op-100`, kill G1 после forward, до client result.

После rehome client retry того же OperationId через G2.

Expected:

```text
canonical commits = 1
client eventually receives one canonical result
```

### EG5-P3 Gateway crash during authority handoff

Kill G1 в разных фазах A->B transfer.

G2 после rehome обязан reconstruct PRIMARY route из Directory/ownership proof, а не из ephemeral G1 state.

### EG5-P4 Graceful draining

G1 -> DRAINING.

Expected:

- new clients выбирают G2;
- existing client migration follows explicit policy;
- no canonical world ownership change;
- no operation loss/duplication.

---

## 9. EG6 — Upstream Pooling and Multiplexing

### EG6-S1 Connection-count invariant

Запустить:

```text
100 clients
1 gateway
2 authorities
```

Expected physical upstream connections не должны стать 200.

Проверить bounded count согласно выбранному transport pool design.

### EG6-S2 Logical route isolation

Один client отправляет malformed/flood traffic.

Другие clients:

- продолжают movement;
- получают snapshots;
- не теряют authority route.

### EG6-S3 Slow client

Создать client с сильным downstream backpressure.

Expected:

- его queue bounded/drop/coalesce policy срабатывает;
- другие clients не блокируются;
- upstream authority process не останавливается.

### EG6-S4 Slow authority

Authority B latency + queue pressure.

Expected:

- routes B degrade independently;
- routes A продолжают работать;
- gateway main event loop/process остаётся responsive.

### EG6-S5 Subscription aggregation

100 nearby clients интересуются одной coarse representation.

Expected upstream subscription count/bytes меньше naive per-client duplication и проверяется metric-based assertion.

---

## 10. EG7 — Geo/WAN matrix

Минимальные profiles:

```text
LOCAL
GOOD
AVERAGE
MOBILE
BAD
EXTREME
LAG_SPIKE
ASYMMETRIC
```

Для каждой комбинации измерять отдельно:

```text
client -> gateway RTT
 gateway -> primary authority RTT
 gateway -> observer authority RTT
```

Важно не сводить latency к одной цифре.

### Matrix examples

#### Case A — близкий gateway, далёкий authority

```text
Client-G1 15 ms
G1-A      120 ms
```

Проверяет benefit edge termination/client stability, но не притворяется, что authoritative gameplay RTT исчез.

#### Case B — более дальний gateway, значительно лучший backbone route

```text
Client-G1 20 ms, G1-A 120 ms
Client-G2 35 ms, G2-A 30 ms
```

На раннем EG4 client selection остаётся primarily edge-RTT based. Более поздний optional policy может учитывать estimated end-to-end route quality, но это отдельный checkpoint и не должно появляться скрыто.

#### Case C — observer WAN degradation

PRIMARY healthy, OBSERVER high loss.

Expected gameplay commands healthy; presentation B деградирует отдельно.

---

## 11. Security negative tests

Минимальный набор:

- forged GatewayCatalog entry;
- expired/stale catalog metadata;
- client token reuse from another session;
- gateway identity spoof;
- malformed route ownership proof;
- replayed route update;
- replayed operation with same payload;
- duplicate OperationId with changed payload;
- unauthorized entity id;
- gateway attempts epoch increment;
- observer attempts canonical mutation;
- rate-limit isolation test.

Security rejection не должна падать process или блокировать unrelated sessions.

---

## 12. Observability assertions

Каждый process acceptance должен генерировать machine-readable result.

Минимальный пример полей:

```text
result
scenario_id
seed
client_session_id
selected_gateway_id
selected_gateway_region
client_gateway_rtt_ms
primary_authority_id
primary_authority_epoch
route_revision_start
route_revision_end
handoffs_completed
client_transport_reconnects
player_identity_changes
duplicate_operation_commits
split_brain_observations
stale_route_rejections
projection_epoch_rollbacks
physical_upstream_connection_count
logical_route_count
unexpected_errors
```

Для successful normal handoff:

```text
result = PASS
handoffs_completed >= 1
client_transport_reconnects = 0
player_identity_changes = 0
duplicate_operation_commits = 0
split_brain_observations = 0
unexpected_errors = 0
```

Для EG5 gateway crash допускается client-to-gateway transport reconnect, поэтому assertion меняется:

```text
client_transport_reconnects >= 1
player_identity_changes = 0
duplicate_operation_commits = 0
split_brain_observations = 0
```

---

## 13. Regression gates

Новый gateway runtime не должен ухудшать существующие invariants.

На каждом code checkpoint запускать применимые существующие suites:

- network contracts;
- NX traffic/condition suites;
- player/session/reconnect;
- Item Graph regression;
- world regression;
- authority/handoff donor tests where ported;
- graphical smoke where client-facing path изменён.

Gateway-specific PASS не может замаскировать RED canonical authority regression.

---

## 14. Recommended implementation order

```text
EG0 contracts + deterministic tests
  ↓
EG1 one gateway / one authority process path
  ↓
EG2 primary + observer projections
  ↓
EG3 authority handoff without client reconnect
  ↓
EG4 multiple gateways + selection
  ↓
EG5 gateway failover/rehome
  ↓
EG6 pooling/multiplexing/scale
  ↓
EG7 WAN/load/fault matrix
  ↓
EG8 production convergence
```

Критически важно не начинать с geo-deployment orchestration. Сначала нужно доказать correctness локально в multi-process harness, затем те же topology contracts прогнать под deterministic WAN shaping, и только после этого переносить gateways в реальные географические regions.

---

## 15. Exit criteria research program

Архитектурное исследование можно считать достаточным для production integration planning, когда независимо доказано:

```text
1. Client -> Gateway -> Authority path функционально эквивалентен direct canonical path.
2. Один gateway корректно агрегирует минимум две authorities.
3. Authority A -> B handoff проходит без client reconnect и identity change.
4. Из нескольких gateways клиент deterministic выбирает лучший healthy candidate.
5. Crash выбранного gateway не создаёт duplicate gameplay commit и не меняет player identity.
6. Physical upstream connection count не растёт как clients * authorities.
7. Slow/faulty route изолирован от unrelated clients/routes.
8. WAN matrix не нарушает ownership/epoch/replay invariants.
9. Gateway остаётся полностью non-authoritative по canonical gameplay state.
```
