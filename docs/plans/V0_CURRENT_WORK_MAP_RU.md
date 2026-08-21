# V0 — Current Primary Work Map

Статус: **CANONICAL PRIMARY WORK MAP / P6 PREACTIVATION**

Карта P6 + Seamless была независимо reviewed `PASS` на exact candidate `5a5f2e766f87c8f0f099bb499ae5e8691d8ed6a8` и канонизирована в `main` merge-коммитом:

`1d9de3c479c60045d613660b2a5c5db0374963f8`

Текущая основная рабочая карта V0:

`docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_RU.md`

Machine companion:

`config/control/harness/v0-p6-seamless-execution-roadmap.v1.json`

Formal P5 acceptance record:

`config/control/harness/acceptance/V0-P5-R2-CHECKPOINT-ACCEPTED-001.v1.json`

Declared exact P6 product base:

`491ca7d058690d3de5fcea5e41aaee230a31b3ab`

Fresh P6 preactivation control:

- checkpoint: `V0_P6_PERSISTENT_SHARED_OUTPOST`;
- epoch: `E2026-08-21-V0-P6-R1`;
- Work Order: `V0-P6-R1-WO-001`;
- planned runtime branch: `feature/v0-p6-persistent-shared-outpost`;
- risk: `HIGH`;
- mutation lease rotation: still pending separate main-owned control;
- runtime mutation: **FORBIDDEN** until lease rotation + exact runtime branch creation + Director dispatch;
- production SM1: **INACTIVE**.

## Current route

```text
P5 ACCEPTED
    |
    v
P6 PREACTIVATION
    |
    v
P6 Persistent Shared Outpost + Seamless-Ready Foundation
    |
    +---- parallel ----> Seamless Research
    |                    I2.6 -> I3 -> I4 -> I5A/I5B -> I8
    |                    + NX/SM1 ownership audit
    |                    + bounded MRPF donor alignment
    |                                      |
    +----------------------+---------------+
                           v
                      P6 ACCEPTED
                           |
                           v
                 POST-P6 SEAMLESS GATE
                           |
                           v
                    ACTIVATE V0-SM1
                           |
                           v
                 production A <-> B
                           |
                           v
                          P7
                           |
                           v
                          P8
```

## Operator rule

For planning, dispatch preparation, visual-test expectations and P6/Seamless convergence, agents MUST read this pointer and the primary roadmap before relying on older P6/Post-P6 prose.

P6 is seam-ready but remains single-canonical-authority until a later explicit production SM1 activation. WARM/SHADOW work in P6 is read-only compatibility evidence, not an ownership handoff.

Seamless Research remains a parallel donor train and MUST NOT become P6/SM1 product Git ancestry by wholesale merge.

Older plans remain architectural/history context unless current main-owned control explicitly promotes them.
