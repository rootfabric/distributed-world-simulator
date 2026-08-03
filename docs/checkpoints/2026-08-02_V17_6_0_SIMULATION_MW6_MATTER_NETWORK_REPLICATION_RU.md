# Checkpoint v17.6.0 — MW6 matter network authority and replication

```text
checkpoint: v17.6.0-simulation-mw6-matter-network-replication
build_id: mw6-matter-network-replication
base: v17.5.0-simulation-mw5-matter-persistence / fix7
branch: feature/mw6-matter-network-replication
status: CANDIDATE FOR INDEPENDENT REVIEW
```

## Реализовано

- authoritative server wrapper над принятым MW4 excavation service;
- stream bootstrap из восстановленного MW5 mutation journal;
- peer/client/session/actor binding;
- reuse `NetworkCommandGateway` для mutation commands;
- reuse `ReplicationEnvelope` для snapshots и deltas;
- exact MW5 binary64 transport внутри wire payload;
- replication stream для committed и rejected journal outcomes;
- broadcast persistent brick revisions нескольким replicas;
- atomic client apply с rollback store/journal;
- reconnect delta replay по sequence + base hash;
- full snapshot fallback при gap/eviction/hash mismatch;
- ack sequence/hash fence;
- selective MW3 presenter invalidation;
- запрет передачи procedural revision-0 bricks.

## Не изменено

- production Moon runtime;
- world catalog;
- MW0–MW5 checksum contracts;
- ENet gameplay path;
- Item Graph production adapter;
- cross-server authority handoff.

## Требуемая проверка

```text
MW6 focused: PASS до watchdog
MW5: 142/142 PASS
MW4: 187/187 PASS
MW3: 7519/7519 PASS
MW2: 7470/7470 PASS
MW1: 3685/3685 PASS
MW0: 2011/2011 PASS
A3: PASS
M6: 10/10 PASS
git diff --check: PASS
```

Точное число MW6 assertions фиксируется по первому независимому successful run.


## Результат первой независимой проверки

```text
MW6 focused: 130 assertions PASS, 34.415 s
MW5: 142/142 PASS
MW4: 187/187 PASS
MW3: 7519/7519 PASS
MW2: 7470/7470 PASS
MW1: 3685/3685 PASS
MW0: 2011/2011 PASS
M6 standalone: 10/10 PASS
A3: FAIL дважды в test_m6_dedicated_recovery_processes
error: MULTIPLAYER_DELTA_BASE_MISMATCH
```

Исходная delivery не принимается. Исправление вынесено в `fix1`; matter authority/replication код не меняется.
