# Checkpoint v17.7.0 — MW7 regional matter interest replication

```text
checkpoint: v17.7.0-simulation-mw7-matter-interest-replication
build_id: mw7-matter-interest-replication
base: v17.6.0-simulation-mw6-matter-network-replication / fix2
branch: feature/mw7-matter-interest-replication
status: CANDIDATE FOR INDEPENDENT REVIEW
```

## Реализовано

- per-client checksum-protected cell-cube subscription;
- независимый regional sequence поверх глобального MW6 stream;
- фильтрация только persistent snapshots revision `>= 1`;
- отсутствие frames для нерелевантных global mutations;
- reuse MW6 command authority и существующего `ReplicationEnvelope`;
- exact MW5 binary64 transport внутри regional frames;
- regional delta replay по sequence + projection hash;
- regional snapshot fallback без full-body sparse store;
- двухфазная interest replacement с сохранением старого view до snapshot;
- атомарное enter/leave и selective presenter invalidation;
- региональный acknowledgement с subscription fence;
- reconnect поверх сохранённого authoritative MW5 store;
- sequence-gap/base-hash resync без частичного применения.

## Не изменено

- production Moon runtime;
- `config/worlds/catalog.json`;
- MW0–MW6 checksum-domain;
- global authoritative mutation journal;
- ENet/LOOPBACK command path;
- MW5 durable checkpoint format;
- cross-server authority topology.

## Требуемая независимая проверка

```text
MW7 focused: PASS до watchdog
MW6: 130/130 PASS
MW5: 142/142 PASS
MW4: 187/187 PASS
MW3: 7519/7519 PASS
MW2: 7470/7470 PASS
MW1: 3685/3685 PASS
MW0: 2011/2011 PASS
M6 standalone: 10/10 PASS
A3 full profile: 3 consecutive PASS
git diff --check: PASS
```

Точное число MW7 assertions фиксируется по первому независимому successful run.
