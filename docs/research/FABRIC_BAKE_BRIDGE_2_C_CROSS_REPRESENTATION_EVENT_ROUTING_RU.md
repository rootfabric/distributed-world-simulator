# FABRIC-BAKE BRIDGE-2-C — Cross-Representation Event Routing

**Статус:** IMPLEMENTED CANDIDATE / LOCAL EXACT DOUBLE PASS / BRIDGE-2 ещё не CLOSED.  
**Предшественники:** BRIDGE-2-A ownership + BRIDGE-2-B executable mixed subject.  
**Production:** не авторизован.

## Цель

BRIDGE-2-C доказывает, что physical event, рожденный активным executable representation,
проходит через существующий ownership boundary ровно один раз:

```text
active executable representation
        ↓
ownership resolution
        ↓
existing commit owner
        ↓
canonical commit OR derived FABRIC commit
        ↓
read-only observer deliveries
```

Router не хранит persistent event ledger. Caller передаёт внешний список уже committed
IDs; router возвращает только `ledger_append_event_id`.

## Canonical route

На реальном COMPLEX0-500 subject:

```text
FULL impact evaluator
        ↓
topology-event/complex0-0500-break
        ↓
commit owner = server/complex0
        ↓
real Construction source revision +1
        ↓
real RepresentationInvalidation
        ↓
new canonical frontier
        ↓
CONTACT_BAKE observer
STRUCTURAL_BAKE observer
```

Observers получают `CANONICAL_COMMIT_OBSERVATION` и всегда имеют
`canonical_write_authorized=false`.

BRIDGE-2-C намеренно **не** применяет BakeInvalidation/refinement к этим artifacts. Это
следующий checkpoint BRIDGE-2-D.

## Derived route

Для HYBRID_BAKE:

```text
HYBRID_BAKE emitter/evaluator
        ↓
FABRIC_PHYSICAL_EVENT owner
        ↓
NO_CANONICAL_REVISION
        ↓
DYNAMIC_ROM read-only observer
```

Derived event не может подложить новый frontier, RepresentationInvalidation или source
mutation kind.

## Ownership is revalidated inside route

Route хранит исходный `candidate_representation_ids`. При `validate_route()` ownership
resolution выполняется заново, после чего сверяются:

- evaluator;
- commit owner;
- canonical revision policy;
- exact observer set/order.

Поэтому tampered route не может поменять `server/complex0` на другой owner или
перенаправить observer delivery, даже если переписать hashes/checksum.

## Exactly-once

Persistent ledger в router отсутствует:

```text
input:
committed_event_ids

output:
ledger_append_event_id
```

Повторный route уже committed event блокируется существующим BRIDGE-2-A ownership
boundary; повторный commit блокируется BRIDGE-2-C.

## Fail-closed falsifiers

Проверяются:

- observer пытается emit event вместо active FULL evaluator;
- execution identity emitter не совпадает с B2-B witness;
- commit owner подменён после ownership resolution;
- observer route перенаправлен вне ownership result;
- canonical mutation заявляет unchanged frontier;
- derived event пытается протащить canonical mutation/invalidation;
- event route/receipt/commit replay детерминирован.

## Local exact evidence

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

SHA256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

BRIDGE-2-C acceptance:
64/64 PASS

Playground:
PASS
```

Local evidence hashes:

```text
acceptance log:
0d7aa48ad4deca4db5894d7bf0c0a28aa23dad597a0df8ae30e71d92e956603b

playground log:
9c70f203f52fa2fdcb05d7ac5dd57f824b70b327f61aebbab296253356bbb6c1
```

## Что B2-C НЕ доказывает

Не заявлять:

- invalidation/refinement ordering на реальных mixed artifacts;
- stale artifact rejection после routed mutation;
- rebake/reconstruction ordering;
- common mixed timestep;
- deterministic mixed state replay after mutation;
- COMPLEX1B;
- BRIDGE-2 CLOSED;
- production acceptance.

## Следующий checkpoint

```text
BRIDGE-2-A ✅ ownership
        ↓
BRIDGE-2-B ✅ executable mixed subject
        ↓
BRIDGE-2-C ✅ event routing candidate
        ↓
★ BRIDGE-2-D — Invalidation / Refinement Ordering ★
        ↓
BRIDGE-2-E — Deterministic Mixed Replay
        ↓
BRIDGE-2-F / COMPLEX1B
```
