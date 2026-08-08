# G0 — Geo Contracts Freeze v0 — implementation candidate

**Дата:** 2026-08-08
**Program branch:** `feature/g0-procedural-planetary-generation-lab`
**Implementation branch:** `feature/g0-geo-contracts`
**Decision:** `IMPLEMENTED CANDIDATE`
**Production worlds changed:** NO
**Production terrain changed:** NO

---

## 1. Назначение checkpoint

G0 создаёт минимальное сменное ядро procedural planetary generation до появления геодезии, LOD и реального рельефа.

На G0 намеренно отсутствуют:

```text
sphere/geodesy implementation
planetary cells
terrain mesh
noise mountains
rivers
geology simulation
caves
Matter integration
network replication
```

Цель — доказать, что будущие generators подключаются через versioned semantic contracts, а GeoKernel не становится planet-specific terrain monolith.

---

## 2. Реализованные contracts

```text
PlanetDefinition
PlanetEnvironment
PlanetRecipe
GeoProviderDescriptor
GeoGenerationContext
GeoSurfaceQuery
GeoVolumeQuery
GeoFieldBundle
GeoSample
```

Все DTO:

- exact-field validated;
- JSON-safe;
- checksum protected;
- stable-ID/version validated;
- не содержат Node/Mesh/SceneTree state.

---

## 3. Provider contract

Executable provider boundary:

```text
GeoProvider
├── get_descriptor()
├── supports_query_kind()
├── sample_surface()
└── sample_volume()
```

`GeoProviderDescriptor` включает:

```text
provider_id
contract_version
generator_version
requires[]
provides[]
deterministic
parameters
checksum
```

`parameters` являются частью descriptor hash. Это обязательное уточнение G0: параметры, влияющие на deterministic procedural baseline, не могут жить только во внутреннем runtime state provider.

Пример:

```text
FlatSurfaceProvider(height_m=0)
!=
FlatSurfaceProvider(height_m=12.5)
```

Их descriptor/provider-manifest hashes различаются.

---

## 4. GeoKernel v0

`GeoKernel.configure()`:

1. валидирует PlanetDefinition;
2. валидирует PlanetRecipe;
3. проверяет recipe identity;
4. проверяет runtime provider methods;
5. требует exact descriptor match между recipe и implementation;
6. обнаруживает missing/undeclared/duplicate implementations;
7. строит semantic output ownership;
8. отклоняет duplicate output fields;
9. проверяет required fields;
10. обнаруживает dependency cycles;
11. запрещает nondeterministic provider graph;
12. строит stable lexical topological order;
13. вычисляет provider manifest hash.

`sample_surface()` / `sample_volume()`:

```text
requested fields
      ↓
find owning providers
      ↓
mark transitive declared dependencies
      ↓
execute only required provider subset
      ↓
provider receives only declared requires[]
      ↓
validate exact provides[] output
      ↓
GeoFieldBundle(values + provenance)
      ↓
GeoSample(provider_manifest_hash)
```

Таким образом hidden field dependency не становится случайной частью generator API.

---

## 5. Reference provider

G0 содержит только:

```text
FlatSurfaceProvider
```

Он предоставляет:

```text
geo/surface-height-m
```

и не поддерживает volume query.

Это намеренно примитивная реализация. Её задача — доказать provider substitution, а не генерировать красивую поверхность.

---

## 6. Validation

Engine:

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
```

Проверки в изолированном G0 harness:

```text
headless editor import              PASS
focused G0 contracts               PASS — 209 assertions
source hygiene                     PASS — 15 GDScript files
```

Acceptance покрывает:

```text
manifest/schema
contract validation
checksum mutation detection
NaN/INF rejection
JSON runtime-object rejection
provider parameter provenance
requested field canonicalization
field provenance
recipe provider canonicalization
same query → same sample
query A→B == B→A
missing dependency rejection
duplicate output rejection
dependency cycle rejection
nondeterministic provider rejection
missing provider rejection
undeclared provider rejection
duplicate implementation rejection
descriptor/parameter mismatch rejection
canonical provider ordering
provider replacement without caller change
surface/volume query boundary
absence of renderer/Node/global-RNG dependencies in Geo core
```

Focused runners:

```text
RUN_G0_GEO_CONTRACTS_TESTS.ps1
RUN_G0_GEO_CONTRACTS_TESTS.sh
```

---

## 7. Почему candidate, а не accepted

Текущая среда позволила проверить exact G0 source set на exact Godot double build, но не имела полного локального checkout репозитория для запуска всей существующей regression композиции.

Перед `G0 ACCEPTED` на полном checkout требуется:

```text
editor import
RUN_G0_GEO_CONTRACTS_TESTS.ps1
git diff --check
существующие world/core regressions
подтверждение отсутствия production-world changes
```

Acceptance script пока намеренно называется:

```text
tests/procedural/contracts/g0_geo_contracts_acceptance.gd
```

без `test_` prefix. Поэтому strict discovery существующего `RUN_WORLD_REGRESSION_TESTS.ps1` не получает новый незарегистрированный test и не ломается на implementation candidate. После полной независимой приёмки G0 можно зарегистрировать focused coverage в общей regression policy отдельным коротким patch.

---

## 8. Gate результата

G0 architectural gate считается реализованным, если одновременно верно:

```text
[PASS] Geo core data-only
[PASS] deterministic provider graph
[PASS] provider order canonical
[PASS] invalid dependency graph rejected before generation
[PASS] runtime provider must match recipe descriptor
[PASS] generator parameters participate in provenance
[PASS] same inputs produce same sample
[PASS] query order does not change sample
[PASS] FlatSurfaceProvider replaceable without caller API change
[PASS] Surface/Volume contracts already separated
[PASS] renderer/mesh/network semantics absent from GeoKernel
```

Эти свойства подтверждены focused validation.

---

## 9. Следующий этап

После независимой приёмки G0:

```text
G1 — Geodesy + Body Shape
branch: feature/g1-geodesy-body-shape
```

G1 должен добавить:

```text
IBodyShapeProvider
SphereBodyShapeProvider
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
GeodesyService
```

Не добавлять в G1 hills, rivers, caves или planetary LOD.
