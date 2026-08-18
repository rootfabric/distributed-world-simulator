# SM0 Seamless Research — Scoped Agent Instructions

Этот файл действует для `scripts/runtime/seamless/sm0/**` дополнительно к root `AGENTS.md`, canonical Project Control и active Work Order.

## Mandatory additional read

Перед изменением SM0/seamless-кода обязательно прочитать:

```text
docs/control/NETWORK_FRAMEWORK_READY_DEVELOPMENT_POLICY_RU.md
```

## SM0 role

SM0 остаётся research/reference/evidence environment и semantic donor будущего reusable network runtime.

SM0 не является отдельным gameplay/network truth и не должен превращаться в параллельную production network architecture.

Принятые fixture-specific identities и topology (`authority/sm0/...`, `zone/earth/...`, `player/a`, `ship/01`) допустимы внутри research harness и deterministic tests. Не выполнять массовую generic-переделку этих fixtures без отдельного Work Order.

## Frozen evidence protection

Если текущий SM0 carrier/checkpoint объявлен frozen или review-targeted:

- не менять runtime semantics ради framework-readiness;
- не переписывать accepted contracts ради более красивого API;
- не смешивать docs-only framework guidance с claims о новом runtime acceptance;
- сохранять exact runtime/evidence boundary и явно отделять последующие documentation-only commits.

## Donor direction

Новые общие semantics следует формулировать так, чтобы после acceptance их можно было перенести в актуальную `scripts/network/` architecture без изменения смысла protocol.

Предпочитать общие concepts:

```text
EntityId
AuthorityId
AuthorityEpoch
OperationId
TransferId
StateRevision
ReferenceFrameId
ProjectionRevision
RetirementProof
```

но не расширять текущий scope только ради abstraction.

## Ownership boundary

SM0 может доказывать cross-authority semantics для player/item/island/projection, но canonical domain state остаётся у существующего владельца simulator domain.

Не создавать:

- второй Item Graph;
- второй player/gameplay store;
- новую несовместимую authority model;
- transport-specific canonical truth.

## Research to production rule

После acceptance SM0 используется как:

```text
evidence donor
contract donor
semantic donor
```

Доказанные semantics должны адаптироваться к актуальной product/network line, а не переноситься blind merge из устаревшего research carrier.

Framework extraction не является scope SM0 без отдельного formal Work Order.
