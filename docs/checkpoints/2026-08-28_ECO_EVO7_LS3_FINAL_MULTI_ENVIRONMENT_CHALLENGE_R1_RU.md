# ECO EVO7 / LS3.FINAL — Multi-environment Challenge R1

## Новый порядок дорожной карты

```text
LS3.0 Real Planet Patch        CLOSED
LS3.1 Environment Generator    CLOSED
LS3.2 Spatial Cohort Lattice   CLOSED
LS3.3 Dispersal / Recruitment  CLOSED
LS3.4 Local Competition        CLOSED (+ extinction evidence repair in LS3.FINAL)
LS3.5 Emergent Biomes          CLOSED
LS3.6 Rule Workbench           CLOSED

                ↓

LS3.FINAL
Multi-environment Challenge    IMPLEMENTATION CANDIDATE

                ↓ exact-head acceptance

ECO-VIS1 Spatial World Viewer
                ↓
ECO-VIS2 Procedural Plant Renderer
                ↓
ECO-VIS3 Planet Patch / Biome Viewer
                ↓
LS4 next ecology complexity stage
```

Визуальная ветка начинается **сразу после принятия LS3.FINAL**, а не после LS4.
Machine-readable route: `config/ecology/eco-evo7-live-simulation-roadmap.v1.json`.

## Цель LS3.FINAL

Одна и та же исходная наследственность запускается в нескольких физически различных средах. Менять genome, fitness, mutation, dispersal, recruitment или желаемый biome через challenge запрещено.

Causal path:

```text
same founder hereditary pool
          +
physical world seed / environment recipe
          ↓
LS3.6 Workbench public facade
          ↓
LS3.3 reproduction/dispersal/recruitment
          ↓
LS3.4 physical competition
          ↓
LS3.5 post-hoc classification
          +
LS2.1/LS3.6 spatial Observatory
          ↓
read-only LS3.FINAL evidence
```

## Frozen R1 challenge

Максимальный горизонт — 10 поколений. Extinction является терминальным допустимым исходом и завершает конкретный case раньше горизонта.

### WET_SURFACE

- `world_seed = 362365`;
- `environment_seed = 310031`;
- recipe `WATER_GRADIENT_STRONG`;
- physical envelope: почти полностью surface-water patch, высокая средняя soil moisture;
- ожидаемый класс результата: terminal extinction, без resurrection и без трактовки extinction как runtime failure.

### DRY_DRAINED

- `world_seed = 361406`;
- `environment_seed = 310031`;
- recipe `RELIEF_DRAINAGE_STRONG`;
- physical envelope: `soil_moisture <= 0.40`, `drainage_index >= 0.70`, без surface-water dominance;
- ожидаемый класс результата: population survives 10 generations, но меньше исходных 64 records.

### BRIGHT_DRY

- `world_seed = 358529`;
- `environment_seed = 310031`;
- recipe `WATER_GRADIENT_STRONG`;
- physical envelope: `incident_light >= 0.85`, без surface-water dominance;
- ожидаемый класс результата: population survives 10 generations и превышает исходные 64 records.

Дополнительный strong-response gate: final population `BRIGHT_DRY - DRY_DRAINED >= 40`.

## Найденная LS3.4 boundary bug и repair

LS3.FINAL обнаружил ранее не покрытую границу: если LS3.3 возвращал нулевую population, LS3.4 оставлял competition field пустым. Из-за этого валидное биологическое extinction-состояние не проходило `validate_snapshot()` и Workbench видел ошибку вместо терминального исхода.

Repair не меняет биологию и survival thresholds. LS3.4 теперь для zero-population generation публикует отдельное deterministic empty competition evidence:

- `record_count_before = 0`;
- `record_count_after = 0`;
- empty evaluations / water cells;
- canonical empty-light identity;
- deterministic competition hash;
- fail-closed validation против forged empty-light hash.

LS3.4 revision: `ECO.EVO7-LS3.4.2`.

## Acceptance gates

1. Exact same founder hereditary pool во всех challenge cases.
2. Три distinct physical patch/environment identities.
3. WET_SURFACE даёт валидный extinction evidence, а не pipeline failure.
4. Extinction replay через public Workbench даёт exact ecology/heredity hashes.
5. DRY_DRAINED survives, но population contracts.
6. BRIGHT_DRY survives и population expands.
7. Population response gap между BRIGHT_DRY и DRY_DRAINED >= 40.
8. Final ecology state hashes различаются во всех трёх средах.
9. Final hereditary pool hashes различаются во всех трёх средах.
10. Classification + spatial Observatory evidence присутствуют и при extinction.
11. Desired-outcome forgery fail-closes даже после полного rehash.
12. Authority escalation fail-closes даже после rehash.
13. Challenge source не вызывает LS3.3/LS3.4/LS3.5 напрямую и использует только LS3.6 Workbench facade.
14. LS3.4 focused regression green.
15. LS3.5, LS3.6 и полный inherited LS3 chain green на exact double Godot.

## Следующая стадия после acceptance

`ECO-VIS1 Spatial World Viewer`.

VIS1 должен использовать уже существующие read-only projections и Observatory: 32x32 spatial view, камера, переключение environment/population/biome overlays, выбор клетки/растения и live generation controls. Renderer остаётся presentation-only и не становится ecology truth.
