# T1A.7 — Runtime Recovery / Interest / Scale — ACCEPTED

Дата: 2026-08-11  
Ветка: `feature/t1a7-runtime-recovery-interest-scale`  
Parent: `T1A.6 ACCEPTED @ 06f332dc99287e94ba4515ce51346c4f639d240f`

## Итог

Полная линия T1A.7 принята:

```text
T1A.7.1 Recovery                         ACCEPTED
T1A.7.2 Late-Interest + Reconnect       ACCEPTED
T1A.7.3 Dirty / Selective Replication   ACCEPTED
T1A.7.4 Scale / Soak Lab                ACCEPTED
T1A.7.5 Composition Acceptance          ACCEPTED
```

Статус:

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

Production runtime/test boundary:

```text
cab2e1cdcafd831ab9c0cb09123383bf96f5dfe0
```

Final exact Windows acceptance checkout:

```text
1430284c3e523d9292804be2fc347ac1f70d39a6
```

## Что доказано

### Recovery

Construction runtime durable state восстанавливается через существующий M0 aggregate repository/coordinator. Persisted runtime не содержит peer/session/presentation/LOD/interest routing truth. Replay не повторяет уже committed effect.

### Late interest / reconnect

Logical client interest хранится отдельно от transport session. Поздно заинтересовавшийся или reconnect client получает текущий authoritative full baseline. Stale/conflicting interest revisions отклоняются. Interest projection не является global spatial identity.

### Dirty/selective replication

Runtime mutation diff изолирует dirty runtime IDs и fan-out идёт только выбранным active clients. Correctness path сохраняет существующий `ConstructionRuntimeSnapshot` и `RESYNC / RELIABLE_ORDERED`; новый network contract/channel не создан.

### Scale/soak

Headless synthetic lab доказал bounded work без `Node3D` на каждый runtime subject:

```text
1,000 canonical subjects   PASS
10,000 canonical subjects  PASS
2 cases / 2394 assertions  PASS
```

10k case:

```text
broadcast baseline messages  32,000
projected baseline messages      800
broadcast baseline bytes     147,228,480
projected baseline bytes       3,680,627
targeted deliveries               1,024
avoided peer deliveries            7,168
planner failures                       0
```

Reconnect остаётся full authoritative baseline; mutation replay-history bound = 0. T1A.7 не заявляет compact delta/replay subsystem.

### Final composition

Final focused gate повторно прогнал recovery, real M3 interest/reconnect, selective routing, 10k scale и отдельную recovered-truth composition. Затем тот же checkout прошёл full world/core regression до NX4 с `6 PASS / 0 FAIL`, lifecycle `STOPPED`, `exit_code 0` и финальным sentinel.

## Архитектурные invariants

```text
canonical Construction truth != presentation
canonical Construction truth != transport
construct/runtime identity != interest identity
construct/runtime identity != LOD/HLOD identity
transport session != logical client interest
```

T1A.7 не создал private:

- Item/Construct registry;
- persistence repository/coordinator;
- authority registry;
- transport/channel namespace;
- global interest/world-query identity;
- cross-domain transaction coordinator;
- WORLD_WORK_BUDGET scheduler;
- material ontology.

## Известный debt

`tests/construction/t1a7_2_late_interest_reconnect_acceptance.gd` ещё может выдавать transient JSON parse log во время rewrite result file. Финальный suite при этом PASS 35; аналогичный race в T1A.7.3 был устранён test-only FIX1 `a76afddd1d82e7d11bf1e72819580cd90db60448`.

## Handoff к следующему этапу

Canonical GLOBAL-P0 roadmap ведёт T composition и TS scale/visual к T2.0. T1A.7 закрыл runtime recovery/interest/scale сторону T. Но T2.0 остаётся control-gated до:

```text
C22 MAIN_INTEGRATED
+
T runtime-scale evidence (DONE by T1A.7)
+
TS0.4 1M Research Ceiling classification
+
PC0 convergence
```

До снятия этих блокеров разрешён T2 readiness/convergence preflight: фиксировать входные контракты, compose accepted evidence и готовить heterogeneous-station acceptance profile, не объявляя T2.0 активным и не создавая новую foundation ownership.
