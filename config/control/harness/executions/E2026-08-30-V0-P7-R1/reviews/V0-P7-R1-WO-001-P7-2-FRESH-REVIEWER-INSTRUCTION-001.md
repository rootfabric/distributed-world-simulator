# V0 P7.2 — Fresh Independent Reviewer Brief R1

Работать только как **fresh independent READ-ONLY Reviewer**. Не изменять runtime-код, не исправлять findings в этой роли и не выполнять merge.

Допустимые verdict: `PASS`, `FAIL`, `INSUFFICIENT_EVIDENCE`. Implementer-side выводы — только входные утверждения, которые Reviewer должен попытаться опровергнуть.

## Exact subject

```text
runtime PR: #350
branch: feature/v0-p7-bounded-terrain-mutation
base: 3a396232235d46cc2c6fb1a3960553c624f951bf
HEAD: cc98bee7109118e4aecab6df5a6f112edab4d35c
TREE: c58c9ec74f09ff83dfbbb149c8e9ab67746f8fcd
Godot: 4.7.1.stable.double.custom_build.a13da4feb
```

Immutable review source:

```text
validation carrier PR: #357
export run: 33348644031
artifact: 9742839583
artifact name: p7-2-final-review-source-cc98bee710
artifact ZIP digest: sha256:d3ec3c5e12af37c031d76b3e7db36bf13ffae841715dba43c8131d74ff569b7f
source tar SHA-256: b9257ae59fcffa8b0a3c971ec9ad3c909ebc246b888ddce1f95642ae5b802230
reconstructed tree: c58c9ec74f09ff83dfbbb149c8e9ab67746f8fcd
```

Сначала независимо подтвердить source tar SHA и reconstructed tree. Несовпадение identity блокирует review.

## Обязательные inputs

Прочитать `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, `docs/control/DEVELOPMENT_HARNESS_RU.md`, `docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md`, `config/control/harness/review-policy.v1.json`, P7 Work Order, P7 owner map и P7.2 sampler-seam amendment.

Затем проверить Evidence Map и Post-build Critique этой dispatch-ветки.

## Что нужно попытаться опровергнуть

1. **No second canonical truth** — bubble/runtime/presenter/adapter/clipper не должны владеть canonical store, journal, persistence, replication или authority.
2. **Sampler seam backward compatibility** — без injection три существующих Matter services должны сохранять `fixed_seed_asteroid_generator`.
3. **Moon identity/determinism** — `body/moon`, `body/moon/fixed`, seed `20260724`, никаких observer/camera-dependent canonical samples.
4. **Bounded mutation** — query/mutation/materialization не выходят за один body-fixed root; outside остаётся legacy.
5. **Physical seam** — проверить box root вместо circle, crossing-triangle case, fully-inside removal, preservation outside fragments, winding/degenerates/UV/normals, 0.02 m clearance, off-center/recenter, sync+worker parity, stale cache/worker, collision from exact clipped mesh.
6. **Rollback** — feature OFF восстанавливает legacy presentation/collision без удаления Matter snapshots.
7. **Scope/ownership** — нет новых Matter/Terrain mutation DTO, P7-private persistence/network/authority foundation, architecture ownership change.
8. **Evidence adequacy** — test design должен реально доказывать заявленные invariants; числа Implementer-а нельзя принимать без чтения tests/runner.

Declared exact evidence:

```text
P7.2 bubble       53/53
P7.2 seam         45/45
P7.1 authority    83/83
P7.1 Tool→MW4     30/30
MW4               187
MW5               142
MW6               130
canonical runner  exit 0
Project Control   33347609950 SUCCESS
```

## Durable output

Создать только:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/reviews/
  V0-P7-R1-WO-001-P7-2-FINAL-REVIEW-001.v1.json
```

Required identity:

```text
schema: distributed_world_simulator.harness_review_result.v1
review_id: V0-P7-R1-WO-001-P7-2-FINAL-REVIEW-001
review_type: POST_BUILD_EXACT_HEAD_SUBSTEP_REVIEW
work_order_id: V0-P7-R1-WO-001
risk_class: CRITICAL
reviewed_head_sha: cc98bee7109118e4aecab6df5a6f112edab4d35c
reviewed_tree_sha: c58c9ec74f09ff83dfbbb149c8e9ab67746f8fcd
reviewer: INDEPENDENT_REVIEWER_P7_2_FRESH_EXACT_SOURCE_R1
```

Output обязан содержать `verdict`, `required_fixes`, `rank_up_moves`, `evidence_gaps`, `risk_assessment`.

Даже при PASS запрещено объявлять: P7 checkpoint ACCEPTED, P7.3 implemented, P7.2 merged, RUNTIME_FEATURE_MERGE authorized, Verifier PASS или whole-P7 FULL_WORLD_CORE_REGRESSION_PASS.

Reviewer PASS открывает только fresh independent Verifier на том же runtime HEAD/TREE.
