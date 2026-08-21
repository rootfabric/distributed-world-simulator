# V0 EG0 — Edge Gateway Contracts Candidate

Статус: **IMPLEMENTATION CANDIDATE / NOT ACCEPTED / STACKED ON PR #185**

Goal:

`TOPOLOGY_NEUTRAL_DTOS_PASS`

Stacked base:

`c5d7d0d682181f0a796d0e059508a1fdfe91b6e1`

Branch:

`feature/eg0-edge-gateway-contracts-r1`

## Реализовано

- `ClientWorldFrame`;
- ingress/egress Gateway envelopes;
- Gateway session binding;
- Gateway route binding;
- read-only projection subscription;
- Gateway locator descriptor;
- protocol/channel/role validation helpers;
- canonical fixture set;
- focused contract tests;
- fixture round-trip tests;
- Windows/Linux focused runners;
- HIGH-risk design brief + glossary.

## Инварианты

```text
client/gameplay identity is topology-neutral
Gateway route metadata is not authority
OperationId survives Gateway wrapping unchanged
mutating ingress requires ACTIVE route
WORLD_PROJECTION requires PROJECTION source
projection subscriptions are read-only
GatewayDescriptor does not expose simulation server endpoint
```

## Explicit non-authority

Этот candidate:

- не запускает Gateway process;
- не реализует EG1;
- не активирует P6;
- не меняет NX/AUTHORITY ownership;
- не становится product ancestry;
- не создаёт `EDGE_GATEWAY_FOUNDATION_ACCEPTED`;
- не является self-review/self-verification.

Следующий допустимый gate после implementer validation: fresh independent Reviewer + Verifier, но только после разрешения зависимости PR #185.
