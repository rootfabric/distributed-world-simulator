# WORLD PACKS — Parallel Workstreams R1

База всех пяти worker-веток создаётся от одного exact controller HEAD. Workstreams не должны менять файлы друг друга и не должны брать canonical simulation ownership.

Актуальный точный work order всегда генерируется командой:

```bash
python tools/world_packs/parallel_controller.py instructions <TRACK>
```

Ниже — смысл потоков и первый bounded checkpoint.

## WP-ASSET1 — Safe Asset Fetch / Raw Cache

Branch:

```text
work/world-packs-asset1-safe-fetch-r1
```

Цель: реализовать подготовительный downloader/cache слой, который существует только до runtime и получает строго те bytes, которые зафиксированы immutable descriptor-ом.

Первый checkpoint `FETCH_CONTRACT`:

```text
request = exact asset id/version/hash/expected size + approved source location
result  = verified temporary payload OR explicit typed failure
```

Далее по порядку:

```text
FETCH_CONTRACT
BOUNDED_HTTPS
RAW_CONTENT_ADDRESSABLE_CACHE
SSRF_REDIRECT_AND_SIZE_GATES
ARCHIVE_SAFETY_FIXTURES
OFFLINE_REUSE_AND_CORRUPTION_RECOVERY
EVIDENCE_READY
```

Обязательные negative proofs: HTTP/non-public IP, redirect в private/local target, response-size overflow, hash mismatch, partial file, corrupt cache, `../` archive entry, absolute/drive/UNC path, symlink/hardlink/device, excessive file count/unpacked size.

Не делать: gameplay HTTP; тяжелые production downloads; executable post-download hooks; изменение WP1.0 identity semantics без отдельного controller decision.

## WP-CONTENT1 — Real CC0 Candidate Library

Branch:

```text
work/world-packs-content1-cc0-library-r1
```

Цель: создать проверяемый source/provenance catalog для реальных материалов, не превращая Git в asset storage.

Первый checkpoint `SOURCE_POLICY`: формат candidate descriptor и требования к фактам. Нельзя придумывать SHA-256, expected bytes, автора, каналы PBR или scientific provenance, пока они фактически не проверены.

Далее:

```text
SOURCE_POLICY
ROCK_AND_CLIFF_CANDIDATES
SAND_AND_SOIL_CANDIDATES
ICE_AND_SNOW_CANDIDATES
LICENSE_AND_PROVENANCE_AUDIT
NO_HEAVY_GIT_PAYLOAD_GATE
EVIDENCE_READY
```

Минимальный набор discovery:

```text
rock/cliff
sand/gravel
soil/ground
ice
snow
```

Предпочтительно CC0/public-domain/permissive redistributable. Fab/reference-only/download-by-user assets могут документироваться отдельно, но не смешиваются с baseline redistributable library.

Не делать: добавлять 4K/8K payloads; скачивать гигабайты; выдавать artistic rock за measured basalt или asteroid mineral sample.

## WP-SURFACE1 — Reusable Surface Families / Recipe Fragments

Branch:

```text
work/world-packs-surface1-families-r1
```

Цель: сформировать переиспользуемый semantic layer ниже старых WP0 exemplars.

Первый checkpoint `FAMILY_TAXONOMY`: определить стабильную taxonomy и правила explicit binding к существующим `matter/...` ID.

Далее:

```text
FAMILY_TAXONOMY
MATTER_BINDING_RULES
REGOLITH_BASALT_SAND_ICE_FAMILIES
FIDELITY_AND_EXPOSURE_STATES
RECIPE_FRAGMENT_COMPOSITION
CONFLICT_AND_ORDER_INDEPENDENCE_TESTS
EVIDENCE_READY
```

Минимальный набор families:

```text
surface/regolith
surface/basalt
surface/fractured-rock presentation relation
surface/sand
surface/ice
```

Важно: `surface/sand` нельзя привязать к `matter/basalt` и затем называть это физическим sandstone. Presentation recipe меняет внешний вид, не canonical material.

States `fresh`, `weathered`, `fracture` — presentation vocabulary. Если canonical producer не даёт фактический exposure age/weathering, family обязана использовать честный fallback, а не создавать новую truth.

Не делать: менять Matter catalog, strata depth, physical properties, WORLDGEN operator semantics.

## WP-VIS1 — Generic Surface Material Lab

Branch:

```text
work/world-packs-vis1-material-lab-r1
```

Цель: до готовности WORLDGEN runtime доказать, что presentation machinery не зашита в flat Y-up biome gallery.

Первый checkpoint `GENERIC_LAB_SCAFFOLD`: asset-free лаборатория, не production terrain.

Далее:

```text
GENERIC_LAB_SCAFFOLD
HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES
OVERHANG_AND_INVERTED_SURFACES
SPHERE_OR_IRREGULAR_FIXTURE
TRIPLANAR_OR_LOCAL_FRAME_MAPPING
FIDELITY_SWITCH_FIXTURE
HEADLESS_AND_GRAPHICAL_EVIDENCE_READY
```

В одной сцене должны присутствовать как минимум:

```text
horizontal plane
45-degree slope
vertical wall
overhang
inverted/ceiling surface
sphere or simple irregular rock fixture
```

Mapping не должен зависеть от global `Vector3.UP` как от physical truth. Lab может использовать локальный frame/triplanar и diagnostic materials.

Не делать: трогать production Moon terrain, canonical collision, Matter, ECO placement truth. Asset-free fixture не закрывает будущий real asteroid Proof B.

## WP-TOOLS1 — Authoring CLI / Doctor / Scale Fixtures

Branch:

```text
work/world-packs-tools1-authoring-cli-r1
```

Цель: сделать библиотеку удобной для разработчика и дешёвой в проверке CI.

Первый checkpoint `CLI_SCAFFOLD`: один clear entry point без дублирования resolver logic.

План:

```text
CLI_SCAFFOLD
VALIDATE_AND_RESOLVE
DOCTOR_DIAGNOSTICS
INSPECT_AND_INDEX
SYNTHETIC_1K_SCALE
SYNTHETIC_10K_SCALE
EVIDENCE_READY
```

Желаемый UX:

```bash
python -m tools.world_packs.wp_cli validate
python -m tools.world_packs.wp_cli resolve recipe/lunar-swatch@1.0.0
python -m tools.world_packs.wp_cli inspect surface/basalt@1.0.0
python -m tools.world_packs.wp_cli doctor
python -m tools.world_packs.wp_cli benchmark --assets 1000
python -m tools.world_packs.wp_cli benchmark --assets 10000
```

CLI должен переиспользовать текущий metadata contract, а не создавать второй parser/resolver с другими правилами.

Scale tests сначала synthetic descriptors без payloads. Зафиксировать wall time/RSS и environment; не превращать произвольный локальный результат в production SLA.

## Integration train — не запускается как шестой agent сейчас

```text
WP-ASSET1 ───┐
WP-CONTENT1 ─┤
WP-SURFACE1 ─┤
WP-VIS1 ─────┤──> WP1_2_FOUNDATION_INTEGRATION
WP-TOOLS1 ───┘
        +
WP1.0 independent review
```

Integration начинается только после пяти `READY_FOR_INTEGRATION` handoffs и закрытия review gate. Создаётся свежая integration branch от reviewed WORLD PACKS base. Child histories не force-rebase.

Именно там можно согласовать изменения sharded schemas/catalogs, real fetch + real candidate onboarding, prepared cache/import и FOUNDATION DONE gate.

## Что делать, если два агента хотят один файл

Worker не договаривается в чате о concurrent edit. Он:

1. фиксирует `BLOCKED` или scope request;
2. controller показывает collision/overlap;
3. integrator назначает единственного владельца или создаёт отдельный composition patch.

Это предотвращает ситуацию, когда два агента независимо меняют core catalog/schema и последний merge случайно выигрывает.
