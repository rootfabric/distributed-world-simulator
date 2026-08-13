# ECO / P3.2 — Density & Carrying Capacity — CANDIDATE

Статус: `CANDIDATE / RESEARCH_ONLY / TARGETED LINUX PASS / P3.1 ACCEPTANCE + EXACT WINDOWS CANONICAL PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Parent control head: `f614d67f7db5be093e46a3d8b8ea4e3fd5d166be` (`P3.1 CANDIDATE`).

Parent P3.1 targeted aggregate:

```text
f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
```

Frozen EVO1/P2.8 ancestor:

```text
ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
```

## Цель

P3.2 вводит отдельный deterministic kernel локальной density feedback и carrying capacity поверх P3.1 resource competition.

Это **не** дубликат прежних механизмов:

- `plant_resource_model_v1.gd::density_cost` — локальная линейная стоимость biomass внутри resource-balance, без явного `K`, recovery trajectory или bounded over-capacity response;
- старые `_apply_capacity()` / `PATCH_SHARED_CAPACITY_KG_M2` — hard proportional clipping: если biomass выше лимита, она сразу масштабируется до лимита;
- P3.2 не клипует состояние мгновенно. Он задаёт мягкую направленную динамику ниже/выше `K` и связывает сам `K` с resource support из P3.1.

## Contract

Patch задаёт:

```text
area_m2 > 0
reference_capacity_kg_m2 > 0
0 < minimum_capacity_fraction <= 1
0 <= max_recovery_fraction <= 1
0 <= max_decline_fraction <= 1
```

P3.1 передаёт canonical competition result. Для каждого resource вычисляется patch-level support:

```text
support(resource) = total_uptake(resource) / total_demand(resource)
```

с bounded `[0,1]`; ресурс без demand имеет neutral support `1.0`.

Общий support использует limiting-resource minimum:

```text
resource_support = min(light_support, water_support, nutrient_support)
resource_pressure = 1 - resource_support
```

Carrying capacity:

```text
reference_K = area_m2 * reference_capacity_kg_m2
capacity_fraction = minimum_capacity_fraction
                  + (1 - minimum_capacity_fraction) * resource_support
effective_K = reference_K * capacity_fraction
```

Density feedback:

```text
D = total_biomass / effective_K

D <= 1: feedback = 1 - D
D >  1: feedback = 1 / D - 1
```

Таким образом feedback непрерывен в `D=1`, равен `0` ровно на `K` и bounded в `(-1, 1]`.

Ниже `K` recovery дополнительно умножается на P3.1 `growth_factor` конкретного растения. Выше `K` все растения получают один и тот же proportional decline fraction. P3.2 не содержит lookup по plant ID, species name или заранее выбранному winner.

Zero-biomass растение P3.2 не создаёт заново: recruitment/dispersal остаются за последующими checkpoint'ами.

## Ключевые доказанные свойства

```text
same input -> same result_hash
input permutation -> canonical plant order -> same result_hash
full resources -> reference K
resource limitation -> lower effective K
below K -> bounded positive recovery
at K -> zero density response
above K -> bounded decline toward K
above K -> no instant hard clipping
shared over-K decline -> composition preserved
repeated over-K steps -> monotonic convergence toward K without crossing
empty population -> valid neutral state, no biomass creation
malformed input -> fail closed
tampered derived state -> validation FAIL
```

## Targeted Linux evidence

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Exact P3.1 kernel blob used by the targeted test:

```text
c667569b40775a1a1898d7b911a610ca5795f380
```

Parser/preload:

```text
PASS
```

Three independent process runs A/B/C were identical:

```text
ECO.P3.2 Density & Carrying Capacity: PASS (79 assertions)
aggregate_hash=172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
under_capacity_hash=8f08ce09fe5d6db5e34d1109e0899b680fb5b877ec790d3c39cc376b5c0f56b8
over_capacity_hash=b93d073f06c878fb3ea52b98b898ff7fce8bf97e6f1cf4e28c6af7e0d4cb721f
resource_limited_hash=8711ee9d04f20489eff580ff798d3ee799c9c02a12d4dc0c8ac0fa9801fdaca4
parent_p3_1=f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
```

Это targeted Linux validation нового P3.2 kernel/test. Она не подменяет Windows canonical parent gate и не делает P3.1 или P3.2 `ACCEPTED`.

## Canonical acceptance gate

Runner: `RUN_ECO_P3_2_TESTS.ps1`.

Он fail-closed требует сначала, чтобы factual status P3.1 validation начинался с `ACCEPTED`. Затем runner:

1. выполняет parser/preload P3.2;
2. запускает полный `RUN_ECO_P3_1_TESTS.ps1` как accepted parent regression;
3. выполняет P3.2 process A;
4. выполняет P3.2 fresh process B;
5. требует одинаковый P3.2 aggregate hash;
6. требует exact P3.1 aggregate `f3e5ff9e...`.

До выполнения этих условий:

```text
P3.2 = CANDIDATE
P3.2 != ACCEPTED
```

## Next

Порядок закрытия остаётся строгим:

```text
P3.1 exact Windows canonical -> ACCEPTED
P3.2 exact Windows canonical -> ACCEPTED
P3.3 Spatial Dispersal
```

`OBS1` остаётся отдельной non-gating read-only веткой наблюдения и не может использоваться как evidence вместо P3.2 acceptance.
