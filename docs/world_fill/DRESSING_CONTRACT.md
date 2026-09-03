# WF0.1 — Environmental Dressing Contract

Status: **implemented on branch**  
Module: `scripts/world_fill/dressing/world_fill_dressing.gd`  
Tests: `tests/world_fill/test_wf0_1_dressing_contract.gd`  
Runner: `RUN_WORLD_FILL_WF0_1_TESTS.ps1`

## What this contract is

One deterministic, read-only derivation from canonical read-only surface
descriptors to presentation-only dressing decisions. It is the single input
surface consumed by WF0.2 (prop scatter), WF0.3 (decals), WF0.4 (ambience)
and WF0.6 (POI eligibility hints).

## Input descriptor (all fields optional)

| Field | Type | Meaning | Default when missing |
|---|---|---|---|
| `surface_type` | `String` | canonical read-only surface class (`regolith`, `dust`, `sand`, `rock`, `bedrock`, `ice`, `frost`, `metal`, `industrial`, `scrap`, `soil`, `dirt`) | `"unknown"` → generic sparse stones |
| `position` | `Vector3` | world position | `Vector3.ZERO` |
| `normal` | `Vector3` | surface normal | `Vector3.UP` (slope 0) |
| `slope_deg` | `float` | explicit slope override (wins over `normal`) | derived from `normal` |
| `altitude` | `float` | altitude | `position.y` |
| `moisture` | `float` | 0..1 canonical moisture when available | treated as absent |
| `temperature_c` | `float` | canonical temperature when available | treated as absent |
| `ground_cover` | `String` | read-only ECO ground-cover descriptor | `""` (no effect) |
| `biome_tags` | `Array[String]` | region presentation tags | `[]` |
| `seed` | `int` | deterministic seed already available to the client | `0` |

Every missing field is listed in `degraded_inputs` of the output. Degradation
never errors.

## Output decision (`world_fill.dressing_decision.v1`)

- `determinism_key` — stable key over quantized inputs + seed;
- `degraded_inputs` — names of absent optional inputs;
- `prop_families` — array of `{family, density_band, scale_range, tilt_deg_range}`;
  families: `stones`, `boulders`, `debris`, `dry_branches`, `crystals`,
  `industrial_scrap`; density bands: `none` (omitted), `sparse`, `moderate`,
  `dense`;
- `decal_families` — presentation-only eligibility list for WF0.3
  (`surface_wear`, `impact_dust`, `material_exposure`, `scorch_mark`);
- `ambience_selector` — one of `quiet_rubble`, `open_wind`, `wind_gusts`,
  `underground_echo`, `thin_air_loop`;
- `poi_eligibility` — boolean hints per POI kind for WF0.6.

## Deterministic rules (R1)

1. Surface → family/density map (`SURFACE_FAMILY_BANDS`).
2. Slope ≥ 40° demotes every family except `boulders`.
3. Moisture > 0.55 removes `dry_branches`; moisture < 0.2 on `soil`/`dirt`
   raises them to `moderate`.
4. Non-empty ECO `ground_cover` promotes `stones` by one band (capped).
5. Ambience: `cave` tag wins, then altitude > 800, then `canyon`,
   then `open_plain`, else `quiet_rubble`.
6. Decals: base `surface_wear` + surface-specific entry + `impact_dust` for
   `wreckage`/`battlefield` tags, deduplicated.

## Guarantees enforced by tests

1. **DETERMINISTIC** — identical inputs + seed produce byte-identical outputs;
   different seeds change `determinism_key`.
2. **READ-ONLY** — derive never mutates the descriptor and never aliases
   mutable output state to it.
3. **FAIL-SOFT** — an empty descriptor still yields a valid generic decision
   plus a populated `degraded_inputs` report.

## Explicit non-goals (STOP CONDITIONS apply)

No authority writer, no persistence owner, no wire fields, no gameplay
collision, no canonical weather, no server-side memory. If a consumer needs
any of those, open a canonical proposal instead of extending this contract.
