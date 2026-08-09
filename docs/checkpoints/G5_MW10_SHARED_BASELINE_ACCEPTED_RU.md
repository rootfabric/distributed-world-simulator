# G5 + MW10 shared baseline — ACCEPTED

**Дата:** 2026-08-09
**Ветка:** `feature/g5-world-feature-graph`
**Runtime head:** `36ec94fcc96e0f1a0837bbfecffd970ea614cbee`

PR #43 интегрировал независимо принятый MW10 atomic-lock lifecycle fix в shared G5 baseline.

Scope runtime/test fix:

```text
scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_repository.gd
tests/matter/transactions/test_mw10_lock_release_retry.gd
```

Accepted blobs:

```text
repository  a25b7d8c358410e60e1bb7db9d3f99333a305a63
retry test  afab0c98de45c34dcf6c923d622c84835d428fa5
```

## Проверка assistant-side Linux double Godot

Использован project-provided:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
linuxbsd-x86_64-double
```

Результат focused lock lifecycle:

```text
MW10 lock release retry: PASS (12 assertions)
MW10 Linux acquire/release stress: PASS (501 assertions)
cycles: 100
lock residue: 0
```

Focused fixture использует принятый atomic acquire/release implementation и изолирует unrelated persistence/checkpoint dependencies, потому что проверяемый путь касается только lock lifecycle.

## Уже имеющееся независимое Windows evidence

```text
MW10 lock release retry               PASS — 12 assertions
real multi-process contention         25/25 PASS
process assertions                    1275/1275 PASS
zero/multiple winners                 0
ordinary MW10 transaction contracts   PASS — 184 assertions
ordinary MW10 processes               PASS — 51 assertions
```

## Shared regression integration

После первого G6 full-gate закрыты два integration/hygiene хвоста в shared G5 baseline:

```text
RUN_WORLD_REGRESSION_TESTS.ps1
  + res://tests/matter/transactions/test_mw10_lock_release_retry.gd

tracked Godot UID
  tests/matter/transactions/test_mw10_lock_release_retry.gd.uid
  uid://yush8dg03nlf
```

UID сгенерирован project-provided Godot 4.7.1 double через `ResourceUID.create_id()` / `ResourceUID.id_to_text()`.

## Решение

```text
G5 shared MW10 baseline — ACCEPTED
```

G6 должен синхронизироваться с текущим G5 head через lineage-preserving merge перед следующим full acceptance run.
