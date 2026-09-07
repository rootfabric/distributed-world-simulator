# FABRIC PHYSICS-R2 — Fresh Independent Verifier R1

Статус: **VERIFIED**.

```text
SUBJECT_BRANCH = research/fabric-physics-r2-material-geometry-laws-r1
SUBJECT_HEAD = 2c1802bf0b90c7ca11992cb1c166855f2d92c682
SUBJECT_TREE = 37494670a981cacb65761054e5d0953ffa0e719b
VERIFIER_BRANCH = verify/fabric-physics-r2-fresh-independent-verifier-r1
RISK = HIGH
VERDICT = VERIFIED

PRE_VERDICT_RUN = 34111032970
PRE_VERDICT_RESULT = SUCCESS
PRE_VERDICT_VERIFIER_HEAD = 1d2872dd11c7c031b7721e7fda086b488d970ebd
PRE_VERDICT_VERIFIER_TREE = 2f68ebf3946dd614eb669ef4eb34a796fd0b1915
PRE_VERDICT_ARTIFACT_ID = 10014390418
PRE_VERDICT_ARTIFACT_DIGEST = sha256:3c118bfc76b9c9dbd10f3ebfbca183d1eff2f804c9a69b0598583f2ae7cd0a28
```

## Роль и изоляция

Этот ref является отдельным verifier-контекстом. Он создан непосредственно от exact `PHYSICS-R2` closure subject и не изменяет subject-ветку. Implementer acceptance tests не являются primary oracle этого verifier.

Primary verifier использует отдельный executable fixture/oracle:

```text
tests/research/fabric1/fabric_physics_r2_independent_verifier_r1.gd
```

Он заново строит Construction/Matter fixtures и независимо вычисляет ожидаемые физические значения из объявленных SI-законов.

Первый полный verifier run `34111032970` прошёл на отдельной verifier-ветке. До вынесения verdict subject runtime не изменялся, а verifier diff содержал только verifier-owned test/runner/report/workflow paths.

## Binding gates

Проверено fail-closed:

```text
origin/research/fabric-physics-r2-material-geometry-laws-r1 == SUBJECT_HEAD   PASS
SUBJECT_HEAD^{tree} == SUBJECT_TREE                                           PASS
merge-base(verifier HEAD, SUBJECT_HEAD) == SUBJECT_HEAD                       PASS
subject runtime files unchanged on verifier branch                            PASS
verifier diff contains only verifier-owned paths                              PASS
```

Subject после проверки остаётся:

```text
HEAD = 2c1802bf0b90c7ca11992cb1c166855f2d92c682
TREE = 37494670a981cacb65761054e5d0953ffa0e719b
```

## Independent physical oracle

Primary executable verifier, не используя implementation acceptance suite как oracle, подтвердил:

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

Результат:

```text
FABRIC-PHYSICS-R2-INDEPENDENT-VERIFIER-R1: PASS
```

## Secondary exact-subject replay

После primary independent oracle workflow создал detached clean worktree **точно на `SUBJECT_HEAD`** и повторил:

```text
fresh Godot import                         PASS
FABRIC-PHYSICS-R2                          PASS
FABRIC-PHYSICS-R2-CONTRACT                 PASS
FABRIC-PHYSICS-R2-METAMORPHIC              PASS
FABRIC-REPAIR-R1 INTEGRITY regression      PASS
fatal runtime scan                         PASS
tracked-clean check                        PASS
```

Secondary replay не использовался вместо independent oracle; он подтвердил, что исходный exact subject остаётся executable и R1 regression не сломан.

## Exact runtime

```text
Godot = 4.7.1.stable.double.custom_build.a13da4feb
Linux x86_64 SHA256 = bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
Runner = self-hosted Linux X64
```

Результат exact runtime binding: **PASS**.

## Evidence

Pre-verdict evidence bundle:

```text
RUN = 34111032970
VERIFIER_HEAD = 1d2872dd11c7c031b7721e7fda086b488d970ebd
VERIFIER_TREE = 2f68ebf3946dd614eb669ef4eb34a796fd0b1915
ARTIFACT_ID = 10014390418
ARTIFACT_NAME = fabric-physics-r2-independent-verifier-r1-1d2872dd11c7c031b7721e7fda086b488d970ebd
ARTIFACT_DIGEST = sha256:3c118bfc76b9c9dbd10f3ebfbca183d1eff2f804c9a69b0598583f2ae7cd0a28
```

Artifact содержит exact subject/verifier identity, Godot identity, subject/verifier source archives, fresh-import logs, independent-verifier log, exact-subject replay log и SHA256 evidence manifest.

## Acceptance matrix

```text
exact SUBJECT_HEAD/TREE binding            PASS
verifier-role isolation                    PASS
fresh verifier import                      PASS
independent material-law oracle            PASS
independent mechanical analytic oracle     PASS
independent guard/failure oracle           PASS
rigid transform + ID permutation           PASS
2/6/20 small-system FULL fallback          PASS
SI dimension contract                      PASS
independent electrical series oracle       PASS
independent electrical parallel oracle     PASS
strength/capacity separation               PASS
fail-closed invalid-input cases            PASS
model checksum fencing                     PASS
fresh exact-subject import                 PASS
original R2 executable suite               PASS
R1 focused regression                      PASS
evidence capture/upload                    PASS
```

## Verdict

```text
PHYSICS-R2 FRESH INDEPENDENT VERIFIER R1 = VERIFIED
SUBJECT_HEAD = 2c1802bf0b90c7ca11992cb1c166855f2d92c682
SUBJECT_TREE = 37494670a981cacb65761054e5d0953ffa0e719b
```

`PHYSICS-R2` exact subject принят fresh independent verifier-контекстом. Старый R1 surrogate не получает новой физической сертификации: для typed R2 models остаются обязательны `legacy_surrogate_compatible=false`, `bake_certified=false` и безопасный `FULL` fallback до отдельной reducer certification.

Этот durable status commit обязан пройти тот же verifier workflow повторно. Финальный status-head run хранится в GitHub Actions evidence, а не самоссылкой внутри этого коммита. Если status-head run не зелёный или subject ref изменится, verdict перестаёт считаться durable.

После зелёного status-head rerun дорожка `COMPOSITION-R3` официально разблокирована и должна начинаться отдельным bounded Work Order и отдельной веткой от принятого `SUBJECT_HEAD`, а не от verifier-ветки.
