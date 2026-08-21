# V0 — Current Primary Work Map

Статус: **PRIMARY WORK MAP CANDIDATE R2 / EDGE GATEWAY FABRIC DIRECTION**

После formal P5 acceptance текущая основная рабочая карта V0 состоит из:

1. detailed base roadmap:
   `docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_RU.md`
2. normative R2 Gateway overlay:
   `docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_R2_GATEWAY_OVERLAY_RU.md`
3. normative Edge Gateway network spec:
   `docs/network/EDGE_GATEWAY_FABRIC_SPEC_RU.md`
4. executable Edge Gateway lab plan:
   `docs/network/EDGE_GATEWAY_TEST_IMPLEMENTATION_PLAN_RU.md`

При конфликте R2 overlay/Edge Gateway spec имеют приоритет над R1 network assumptions.

Machine companions:

- `config/control/harness/v0-p6-seamless-execution-roadmap.v1.json`
- `config/control/harness/v0-edge-gateway-fabric-test-plan.v1.json`

Canonical roadmap main anchor:

`1d9de3c479c60045d613660b2a5c5db0374963f8`

Declared P6 product base:

`491ca7d058690d3de5fcea5e41aaee230a31b3ab`

## Current route

```text
P5 ACCEPTED
    |
    v
P6 Persistent Shared Outpost + Seamless-Ready Foundation
    |
    | P6.6 Edge-Gateway-compatible gameplay ingress
    |
    +---- parallel ----> Seamless Research / Edge Gateway Lab
    |                    I2.6 -> I3 -> I4
    |                    EG0-EG5 / SR3 Edge Gateway Fabric MVP
    |                    EG6 / SR4 ACTIVE/WARM backend pivot
    |                    EG7-EG9 failure/WAN/scale hardening
    |                    I8 + NX/SM1 audit
    |                    bounded MRPF projection/AOI alignment
    |                                      |
    +----------------------+---------------+
                           v
                      P6 ACCEPTED
                           |
                           v
                    ACTIVATE V0-SM1
                           |
                           v
        Global Edge Gateway Fabric + Directory + A/B
                           |
                           v
   production A <-> B behind one client-facing world connection
                           |
                           v
      Gateway rehome + projection/AOI aggregation + static N-authority
                           |
                           v
                          P7
                           |
                           v
                          P8
```

## Edge Gateway rule

V0 baseline:

```text
Client -> nearest healthy Edge Gateway
Edge Gateway -> current ACTIVE authority
Edge Gateway -> projection sources
```

Normal gameplay hard invariant:

```text
client_active_world_transports == 1
```

Normal authority crossing A -> B must not require:

- new public client endpoint;
- new login;
- respawn;
- client gameplay reconnect;
- direct connection to simulation server B.

Gateway backend route changes behind the stable client-facing session.

## Multi-Gateway rule

There may be many Gateway POPs and many instances per POP.

Initial Gateway is selected by healthy network score (RTT/loss/jitter/capacity), not simple geographic distance.

Routine server/world handoff does not move the player to a new Gateway. Gateway rehome is a separate recovery/network event.

## Shared backend links

Gateway->Server connection model is:

```text
1..K physical links per GatewayInstance <-> ServerInstance
many logical player sessions multiplexed over those links
```

V0 MVP must explicitly prove two or more clients sharing one backend physical tunnel without cross-session leakage or starvation.

## Projection rule

V0 baseline no longer uses direct `ProjectionPublisher -> Client` transports.

Neighbor/macro projections are aggregated through Gateway and delivered on the same client transport.

Direct projection sockets are a later optional optimization and cannot weaken V0 acceptance.

## Gateway authority boundary

Gateway remains non-authoritative. It routes/multiplexes/aggregates network traffic but does not own:

- world state;
- Item Graph;
- Construction;
- persistence;
- OperationId dedup truth;
- authority ownership;
- AuthorityEpoch assignment;
- canonical mutation authorization.

## Current control warning

Open P6 preactivation candidates PR #182 and PR #184 were authored against R1 semantics. If this R2 Edge Gateway Fabric candidate becomes canonical, those candidates must be refreshed/rebased or replaced before runtime mutation is authorized.

## Operator rule

For planning and dispatch, agents must read:

```text
R1 P6 roadmap
+ R2 Edge Gateway overlay
+ Edge Gateway network spec
+ Edge Gateway test plan
+ machine companions
```

Older plans remain architecture/history context unless main-owned control explicitly promotes them.

This pointer does not itself authorize runtime mutation, merge PR #182/#184, rotate the V0 mutation lease, or activate production SM1.
