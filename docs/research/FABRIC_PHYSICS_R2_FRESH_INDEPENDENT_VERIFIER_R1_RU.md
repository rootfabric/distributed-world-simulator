# FABRIC PHYSICS-R2 — Fresh Independent Verifier R1

Статус: **IN_PROGRESS**.

```text
SUBJECT_BRANCH = research/fabric-physics-r2-material-geometry-laws-r1
SUBJECT_HEAD = 2c1802bf0b90c7ca11992cb1c166855f2d92c682
SUBJECT_TREE = 37494670a981cacb65761054e5d0953ffa0e719b
VERIFIER_BRANCH = verify/fabric-physics-r2-fresh-independent-verifier-r1
RISK = HIGH
```

## Роль

Этот ref является отдельным verifier-контекстом. Он создан непосредственно от exact `PHYSICS-R2` closure subject и не изменяет subject-ветку. Implementer acceptance tests не являются primary oracle этого verifier.

Primary verifier использует отдельный executable fixture/oracle:

```text
tests/research/fabric1/fabric_physics_r2_independent_verifier_r1.gd
```

Он заново строит Construction/Matter fixtures и независимо вычисляет ожидаемые физические значения из объявленных SI-законов.

## Binding gates

Verifier обязан fail-closed, если хотя бы одно неверно:

```text
origin/research/fabric-physics-r2-material-geometry-laws-r1 == SUBJECT_HEAD
SUBJECT_HEAD^{tree} == SUBJECT_TREE
merge-base(verifier HEAD, SUBJECT_HEAD) == SUBJECT_HEAD
subject runtime files are unchanged on verifier branch
verifier diff contains only verifier-owned evidence/test/workflow paths
```

## Independent oracle

Primary executable verifier проверяет независимо от implementation acceptance suite:

1. Все nominal material-law constants для steel/aluminum/copper/rubber в mechanical/electrical domains.
2. Неосевой 3D spring fixture с аналитическими `L`, `k=E*A/L`, `x=F/k`, `U=0.5*k*x^2`, `W=0.5*F*x`.
3. `strength_n` влияет на capacity, но не на stiffness.
4. Точные guard boundaries: `80 N` остаётся SAFE, `100 N` остаётся REFINE, превышение capacity создаёт только `FAILURE_PROPOSAL`, damage не commit-ится.
5. Proper rigid rotation + translation и реальное переименование canonical IDs не меняют физические observables.
6. Системы 2/6/20 деталей не получают hidden nodes и используют fail-safe `FULL`, пока typed BAKE reducer не сертифицирован.
7. Model contract содержит ожидаемые SI base-dimension signatures и запрещает legacy surrogate.
8. Неоднородные series/parallel electrical fixtures проверяются аналитически через `R=rho*L/A`.
9. `strength_n` не меняет electrical resistance.
10. Unknown material, mixed composition, unsupported temperature и missing area fail-closed.
11. Tampered model checksum блокирует physical response.

## Secondary exact-subject replay

После primary independent oracle workflow создаёт detached clean worktree **точно на `SUBJECT_HEAD`** и повторяет:

```text
fresh Godot import
RUN_FABRIC_PHYSICS_R2_TESTS.sh
RUN_FABRIC_REPAIR_R1_TESTS.sh
fatal runtime scan
tracked-clean check
```

Secondary replay не заменяет independent oracle; он подтверждает, что исходный exact subject остаётся executable и R1 regression не сломан.

## Exact runtime

```text
Godot = 4.7.1.stable.double.custom_build.a13da4feb
Linux x86_64 SHA256 = bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
Runner = self-hosted Linux X64
```

## Verdict policy

Допустимые durable verdict:

```text
VERIFIED
NOT_VERIFIED
INSUFFICIENT_EVIDENCE
```

`VERIFIED` разрешён только если primary independent oracle, exact subject replay, R1 regression, fresh imports, binding gates и evidence capture зелёные на одном verifier run.

Финальный run id и verifier HEAD/TREE будут записаны отдельным durable status commit после первого полного successful verifier run; затем status commit обязан пройти тот же workflow ещё раз. Subject HEAD/TREE при этом остаются неизменными.
