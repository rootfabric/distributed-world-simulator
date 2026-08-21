# V0 — Current Primary Work Map

Статус: **PRIMARY WORK MAP CANDIDATE R2 / STABLE GATEWAY DIRECTION**

После формального acceptance P5 текущая основная рабочая карта V0 состоит из двух обязательных human документов:

1. detailed base roadmap:
   `docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_RU.md`
2. normative R2 Gateway overlay:
   `docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_R2_GATEWAY_OVERLAY_RU.md`

При конфликте R2 overlay имеет приоритет.

Machine companion:

`config/control/harness/v0-p6-seamless-execution-roadmap.v1.json`

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
    | P6.6 stable-ingress-compatible gameplay surface
    |
    +---- parallel ----> Seamless Research
    |                    I2.6 -> I3 -> I4
    |                    I5A Stable Edge Gateway MVP
    |                    I5B ACTIVE/WARM backend pivot
    |                    I8 + NX/SM1 audit
    |                    bounded MRPF Gateway/projection alignment
    |                                      |
    +----------------------+---------------+
                           v
                      P6 ACCEPTED
                           |
                           v
                    ACTIVATE V0-SM1
                           |
                           v
           Stable Gateway + Directory + A/B
                           |
                           v
        production A <-> B behind one gameplay ingress
                           |
                           v
           Gateway rehome + projection/AOI hybrid
                           |
                           v
                          P7
                           |
                           v
                          P8
```

## Stable Gateway rule

Canonical gameplay direction:

```text
Client -> stable Gateway gameplay session -> current ACTIVE authority
```

Normal authority crossing A -> B must not require a new public gameplay endpoint, login, respawn or gameplay reconnect.

The Gateway is non-authoritative: it routes traffic but does not own world state, Item Graph, Construction, persistence, operation dedup or authority ownership truth.

Read-only projection traffic may still flow directly from authorized MRPF/Projection publishers to the client where this avoids unnecessary relay cost.

## Current control warning

Open P6 preactivation candidates PR #182 and PR #184 were authored against R1 semantics. If the R2 overlay becomes canonical, those candidates must be refreshed/rebased or replaced before runtime mutation is authorized so they cannot silently restore weaker Gateway assumptions.

## Operator rule

For planning, dispatch preparation, visual-test expectations and P6/Seamless convergence, agents must read the base roadmap plus the R2 Gateway overlay before relying on older P6/Post-P6 prose.

Older plans remain architectural/history context unless current main-owned control explicitly promotes them.

This pointer does not itself authorize runtime mutation, merge PR #182/#184, rotate the V0 mutation lease, or activate production SM1.
