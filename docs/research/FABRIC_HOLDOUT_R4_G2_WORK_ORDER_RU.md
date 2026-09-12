# FABRIC HOLDOUT-R4 — G2 GENERALIZED CAPABILITY REPAIR WORK ORDER

Статус: **AUTHORIZED / IMPLEMENTATION_PENDING**. Risk: HIGH.

```text
WORK_ORDER = FABRIC-HOLDOUT-R4-G2-WO-001
BRANCH = repair/fabric-holdout-r4-g2-generalized-capabilities-r1
BASE_HEAD = b88004e77a9a424f1b23ba979f5ce8883a98f1a8
FROZEN_G1_RUNTIME_HEAD = fd6e83b35301d7a15e92c55939654f1f95729730
FROZEN_G1_RUNTIME_TREE = 314330d717db059cd9b9db32c5d6150097e1f2c3
G1_MEASUREMENT_HEAD = 9bb354c31d65600eccd6df713118e11a1f26f548
G1_AUTHOR_CASES_SHA256 = 7e2dd992e372129a7d006ca26fc2666473ca15f5aeeb45d769818cc0216a793f
G1_VERDICT = EXPERIMENT_COMPLETED_FAIL / FALSIFIED
```

## Цель

Исправить три обобщённых capability surface, выявленных G1, без case-specific логики и без переписывания исторического результата G1:

1. connected resistive graphs с ветвлениями, циклами и произвольным числом независимых Dirichlet boundary ports;
2. одномерная axial mechanics с произвольным bounded числом mobile masses и spring/damper bonds;
3. transport-stable canonical checksum для finite JSON numeric values, включая дробные Matter values после `JSON.stringify/parse`.

G2 не меняет физические законы R2, canonical ownership Construction/Matter, authority fencing или failure commit lifecycle.

## Неизменяемые исторические поверхности

G1 остаётся отрицательным экспериментом. Запрещено изменять ради G2:

```text
config/research/fabric-holdout-r4-cases.json
scripts/research/fabric_holdout_r4/holdout.py
tests/research/fabric1/fabric_holdout_r4_probe.gd
frozen expected/reference observations and thresholds
G1 author/provenance/raw evidence
```

Особенно запрещено удалять или обходить историческое G1-условие `INDEPENDENT_BOUNDARY_PORTS_NOT_REPRESENTED`. Поэтому G1 runner не может и не должен превращаться в PASS после раскрытия. Его cases используются только как открытый regression corpus G2.

## Разрешённые production surfaces

Разрешены только обобщённые изменения shared/runtime physics и canonical serialization, плюс новые G2 tests/evidence/workflow:

```text
scripts/network/contracts/network_contract_utils.gd
scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd
scripts/research/fabric_bake0/fabric_composition_r3_compiler_v1.gd
scripts/research/fabric_bake0/fabric_composition_r3_runtime_v1.gd
scripts/research/fabric_bake0/fabric_composition_r3_*general*.gd
scripts/research/fabric_bake0/fabric_*graph*.gd
tests/research/fabric1/fabric_holdout_r4_g2_*.gd
scripts/research/fabric_holdout_r4_g2/*
RUN_FABRIC_HOLDOUT_R4_G2_TESTS.sh
.github/workflows/fabric-holdout-r4-g2-*.yml
docs/research/FABRIC_HOLDOUT_R4_G2_*.md
validation/fabric-holdout-r4-g2-*
```

Расширение списка production surfaces требует отдельного Repair Map с объяснением caller/owner relationship.

## G2-A — General resistive graph

Использовать R2 `resistance_ohm` каждого active edge как единственный constitutive coefficient. Собирать nodal conductance matrix для всех free nodes. Boundary potentials берутся из canonical electrical snapshot facet; их число — данные, не константа. Требуется deterministic node/edge ordering и deterministic partial-pivot Gaussian elimination.

Обязательный readback:

```text
potentials_v       node_id -> voltage
edge_currents_a    element_id -> signed current node_a -> node_b
port_currents_a    boundary node_id -> current injected into graph
kcl_residual_a
power_residual_w
condition_estimate
```

Floating/underdetermined components должны fail-closed с отдельным error code. Нельзя сворачивать bridge/branch topology в один equivalent R как доказательство distributed solution.

Для двухпортового electromechanical R3 scalar path разрешён оптимизированный equivalent conductance, но он должен быть получен из того же graph solution/operator и сохранять прежние FULL/BAKE observables.

## G2-B — General axial multi-coordinate mechanics

Из R2 nodes/elements собрать bounded mobile coordinate set в stable sorted node-id order. Для каждого active spring/damper edge использовать incidence contribution к `K`/`C`; anchored endpoint имеет нулевые displacement/velocity. Coupler force и external force прикладываются только к заявленному mobile coupler node.

Dynamics:

```text
M q'' + C q' + K q = f_external + f_coupler
```

Требуются finite/conditioning checks, deterministic integration, bounded work, per-element effort `k*(q_a-q_b)+c*(v_a-v_b)`, total kinetic/elastic/damper accounting и truthful residuals. Нельзя иметь hidden `ONE_SLIDER` ceiling.

Старый affine one-slider path должен остаться regression-equivalent в пределах зафиксированных R3 tolerances; generalized path не может ослабить guard/failure lifecycle.

## G2-C — Transport-stable canonical numeric representation

`payload_hash`/checksum должны вычисляться над единственным JSON-transport-stable representation. Нельзя пересчитывать checksum повреждённого документа после чтения, ослаблять проверку или округлять конкретные G1 input values.

Нормализация finite float должна быть idempotent относительно canonical encode/decode:

```text
normalize(x) == normalize(JSON.parse_string(canonical_json(x)))
hash(x) == hash(JSON.parse_string(canonical_json(x)))
```

Existing safe-integer semantics и forbidden non-JSON Godot Variant types сохраняются.

## Controls

До production patch должны быть воспроизводимы red controls:

```text
branched graph -> R3_SERIES_PATH_REQUIRED
multi-mobile mechanics -> R3_ONE_SLIDER_REQUIRED
fractional Matter replay after Godot JSON roundtrip -> checksum/replay failure
```

После patch новые non-frozen targeted tests обязаны доказать:

- branch + loop + 3-port KCL/Ohm/power/readback;
- floating component rejection;
- 2+ mobile mass static/dynamic response, weak-but-well-posed mode, permutation/renaming invariance;
- fractional Matter checksum roundtrip and cold replay;
- negative tamper checksum rejection;
- unchanged R1/R2/R3 regression and old one-slider event/failure behavior.

## Acceptance semantics

G2 implementation acceptance НЕ переименовывает G1 в PASS. Ladder:

```text
G1 historical FAIL preserved
  -> G2 targeted RED->GREEN
  -> R1/R2/R3 regression PASS
  -> revealed G1 families replayed as OPEN REGRESSION (new G2 evaluator, frozen input bytes)
  -> immutable G1 source/evidence hash audit PASS
  -> fresh independent reviewer/verifier on exact G2 HEAD/TREE
  -> new independent post-G2 holdout with previously unseen families
  -> HOLDOUT-R4 CLOSED only if that new holdout PASSes
```

`SCALE-R5` и `INTEGRATION-R6` остаются заблокированы до последнего шага.
