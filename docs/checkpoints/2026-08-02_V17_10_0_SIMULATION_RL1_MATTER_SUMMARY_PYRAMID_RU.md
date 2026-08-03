# v17.10.0 — RL1 Matter Summary Pyramid and Dirty Propagation

```text
checkpoint: v17.10.0-simulation-rl1-matter-summary-pyramid
build_id:   rl1-matter-summary-pyramid-dirty-propagation
base:       v17.9.0-simulation-rl0-representation-contracts-fix1
branch:     feature/rl1-matter-summary-pyramid
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Реализовано

- region-scoped Matter summary pyramid поверх MW8 authority-region;
- deterministic leaf summary из `MatterBrickSnapshot`;
- direct-octree parent aggregation;
- min/max SDF и occupancy;
- matter/vacuum/surface presence;
- material occupancy weights;
- immediate dependency hash и transitive descendant revision hash;
- exact regional source frontier, same-revision mutation и revision rollback fences;
- mutation dirty chain только до region root;
- handoff dirty subtree с восстановлением отсутствующих ancestors;
- bounded atomic fine-to-coarse rebuild queue;
- same-cell coalescing и dirty-bounds union;
- content-addressed persistence manifest с общим source frontier;
- RL0 `RepresentationInvalidation` для mutation/handoff;
- запрет Mesh, Node, RID и других runtime objects в DTO.

## Focused runner

```text
RUN_RL1_MATTER_SUMMARY_PYRAMID_TESTS.ps1
RUN_RL1_MATTER_SUMMARY_PYRAMID_TESTS.sh
```

Ожидаемый маркер:

```text
RL1 matter summary pyramid: PASS (245 assertions)
```

Покрываются:

- config identity и boundaries;
- exact leaf metrics на 125-sample fixtures;
- deterministic material aggregation;
- parent independence from child arrival order;
- direct-child, duplicate, mixed-epoch и stale-revision fences;
- descendant hash propagation;
- canonical summary/source projection;
- mutation selective invalidation;
- stale-while-rebuild behavior;
- rebuild convergence leaf → parent → root;
- queue capacity atomicity, exact previous frontier и frontier rollback;
- persistence manifest sorting, region/source binding, mixed unchanged revisions и content keys;
- handoff epoch transition и old-epoch rejection;
- capacity failure without partial epoch/dirty mutation;
- runtime Godot object rejection.

## Выполненная authoring-проверка

```text
RL1 focused:       245/245 PASS × 3
RL0 regression:     92/92 PASS
MW6 regression:    130/130 PASS
MW5 regression:    142/142 PASS
MW4 regression:    187/187 PASS
MW3 regression:   7519/7519 PASS
MW2 regression:   7470/7470 PASS
MW1 regression:   3685/3685 PASS
MW0 regression:   2011/2011 PASS
M6 full profile:     10/10 PASS
A3 full profile:     12/12 PASS × 3
```

MW7/MW8 необходимо повторить на фактической accepted composition `MW7 + MW8 + RL0 fix1`: authoring full archive не содержит MW8 runtime-файлов и не воспроизводит принятую MW8 базу.

## Обязательный независимый gate

```text
RL1 focused:       245/245 PASS
RL0 regression:     92/92 PASS
MW8 regression:     98/98 PASS
MW7 regression:    114/114 PASS
MW6 regression:    130/130 PASS
MW5 regression:    142/142 PASS
MW4 regression:    187/187 PASS
MW3 regression:   7519/7519 PASS
MW2 regression:   7470/7470 PASS
MW1 regression:   3685/3685 PASS
MW0 regression:   2011/2011 PASS
M6 standalone/process: PASS
A3 full profile: 3 consecutive PASS
git diff --check: PASS
```

## Граница

Канонические snapshots, mutation journal, authority protocol, MW7 wire, production Moon и world catalog не изменены. Summary cache остаётся полностью перестраиваемым.

Следующий этап: MW9 — Durable Distributed Handoff and Crash Recovery.
