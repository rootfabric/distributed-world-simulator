# Checkpoint v17.4.0 — MW4 Matter Mutations

## Статус поставки

```text
checkpoint: v17.4.0-simulation-mw4-matter-mutations
build_id:   mw4-matter-mutations
base:       v17.3.0-simulation-mw3-local-meshing / fix2
branch:     feature/mw4-matter-mutations
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Реализовано

- canonical `MatterMaterialBatch`;
- swept capsule planning;
- deterministic one-sample narrow-band SDF excavation kernel;
- per-material removed-mass integration;
- mining-energy validation;
- mass/volume receiver reservation;
- exact replay journal;
- atomic multi-brick sparse-store commit and validated compensating rollback;
- continuous stored-snapshot sampling and raycast;
- selective MW3 presenter invalidation;
- standalone excavation laboratory;
- fault-injected post-commit rollback coverage;
- focused runner and regression handoff.

## Изоляция

Не изменены Moon runtime, production world catalog, network authority и disk persistence.

## Обязательная independent review

```text
RUN_MW4_MATTER_MUTATIONS_TESTS
RUN_MW3_LOCAL_MESHING_TESTS
RUN_MW2_SPARSE_BRICKS_TESTS
RUN_MW1_FIXED_SEED_ASTEROID_TESTS
RUN_MW0_MATTER_CONTRACTS_TESTS
RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS
RUN_M6_DEDICATED_RECOVERY_TESTS
git diff --check
```

Checkpoint нельзя принимать по статической проверке без запуска Godot 4.7.1 double.
