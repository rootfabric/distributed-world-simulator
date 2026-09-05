# WORLD PACKS — corrected development roadmap

Дата: 2026-09-05. Область: parallel / noncritical / consumer-only content lane.
Новая mission: reusable world-generation content library, не бесконечная gallery.
Текущий WP1.0: IMPLEMENTED METADATA CANDIDATE, independent review pending.
**FOUNDATION DONE / GENERATION READY / PRODUCTION READY пока НЕ достигнуты.**

## 1. WP0 сохраняется как завершённое историческое поколение

Основание: `8da220d50ec0b987c16bd5b5aa4d6d34073a24de`. Исторические evidence
сохранены; данный аудит не выдаёт их за заново исполненные Godot tests.

| ID | Назначение / реализация | Проверки в историческом evidence | Долг / будущая роль | Решение |
|---|---|---|---|---|
| WP0.0 | constitution + asset-free gallery | isolated Godot boot | fixture, не planet generator | KEEP |
| WP0.1 | JSON V1 + custom validator | valid/invalid manifest tests | validator subset, обязательные props/POI; оставить V1 и отдельный WP1 | KEEP + MIGRATE future consumer |
| WP0.2 | SOURCE.md license ledger | nonempty provenance fields / empty baseline | не проверяет actual hash или юридическую допустимость | KEEP as inventory, REFRAME claims |
| WP0.3 | Moon Industrial GDScript profile | profile + gallery tests | useful regolith/industrial exemplar; не Matter binding | REFRAME |
| WP0.4 | Mars Dust profile | profile + gallery tests | cosmetic variation; не Mars geology | REFRAME |
| WP0.5 | Frozen profile | profile + gallery tests | ice/snow look; не physical thermal model | REFRAME |
| WP0.6 | Volcanic profile | profile + gallery tests | emissive/lava appearance; не thermal/volcanism owner | REFRAME |
| WP0.7 | Temperate profile | profile + gallery tests | scenery tree/grass не canonical ECO | REFRAME |
| WP0.8 | Alien Wetland profile | profile + gallery tests | shallow-water look не actual hydrology | REFRAME |
| WP0.9 | shared POI library | library selftest | переиспользуемые decorations, не Construction truth | KEEP |
| WP0.10 | registry gallery + comparison harness | 6 packs, 394 gallery nodes, chain PASS reported | MCP screenshots reported 2026-09-04; draw-call profiling pending | KEEP |

Фактические exemplars: Moon Industrial, Mars Dust, Frozen World, Volcanic World,
Temperate, Alien Wetland. Предложенные Alpine/Coastal/Autumn названия не подменяют
живой каталог. Они могут появиться как новые exemplars позже, но не задают core model.

KEEP: noncanonical constitution, procedural baseline, POI reuse, tests/evidence.
REFRAME: "world pack" WP0 = gallery/integration sample над будущей библиотекой.
MIGRATE: static registry/class profiles → explicit data adapter; V1 consumers не ломать.
DEPRECATE as architecture: URL-as-identity, global Y-up, texture-as-physics, ручная сцена
для каждого мира, silent last-wins. Это не приказ удалить работающий WP0 код.

## 2. Порядок поколений

```text
WP0 gallery foundation (retained)
  -> WP1 contracts + safe asset preparation + immutable offline locks
  -> WP2 canonical surface consumption + same-generator + digging proofs
  -> WP3 arbitrary-body/multiscale recipes + generation-ready closure
  -> WP4 capability fidelity + library scale + production closure
```

External asset preparation идёт ДО WORLDGEN consumption, а не в самом конце.
Собственный CDN не является обязательной стадией. Body/coordinate/fidelity identity
закладываются сейчас, их renderer proofs исполняются после готовности consumers.

Общий exit любого этапа: exact source/tree, repeatable commands, actual outputs,
negative tests, независимый review; локальный PASS не разрешает main promotion.
WP2+ требует live проверки main-owned P7/WORLDGEN activation и scheduler capacity.

## 3. Исполнимые этапы

### WP1.0 — Library contract and ownership correction

**Purpose:** Зафиксировать библиотечную модель ниже WP0.

**Why:** Не накапливать новые skins до определения asset/surface/recipe identity.

**Inputs:** Live WP0, main Matter/WORLDGEN, ECO/WF contracts и primary-source research.

**Implementation:** ADR, отдельная Draft 2020-12 schema, source sidecar, metadata resolver, tiny fixture, тесты; оставить legacy V1/runtime неизменными.

**Acceptance criteria:** Exact refs; проверка SHA/bytes fixture; deterministic set composition; missing/cycle/conflict/path/license rejects; шесть legacy manifests валидны.

**Executable proof:** Metadata lock repeat/order/mirror tests и negative suite. Это НЕ E2E A–E.

**Dependencies:** Никакой runtime lease; branch-scoped docs/tooling review.

**Out of scope:** HTTP, archive extraction, Godot import, real PBR rendering, production registration.

**Final gate:** Independent review + published exact evidence; затем freeze draft только после WP1.2 compatibility review.

### WP1.1 — Locked external sources and safe fetch

**Purpose:** Получать ровно разрешённые bytes до запуска мира.

**Why:** URL и название asset не гарантируют версию, права или доступность.

**Inputs:** WP1.0 approved contract; 2–3 небольших реальных CC0 map sets с author/source/license и точными hashes.

**Implementation:** Bounded HTTPS fetch; retries/timeouts; DNS/redirect/SSRF checks; atomic raw cache; explicit license/entitlement gate; secure allowlisted archive extraction.

**Acceptance criteria:** Valid source fetched once; cache reuse verified; corruption/size mismatch/missing source/offline miss rejected; archive traversal/link/device/bomb/case-collision rejected.

**Executable proof:** Proof E, часть 1: clean raw cache -> fetch -> SHA verification -> repeat without network; malicious archive/HTTP fixtures.

**Dependencies:** WP1.0 review; rights review; native network-capable preparer, не gameplay runtime.

**Out of scope:** CDN/server, credential storage in Git, arbitrary post-download scripts.

**Final gate:** Exact positive/negative security evidence, no raw binary added to Git; all untrusted redirect/extraction paths exercised.

### WP1.2 — Prepared assets, offline lock and old-world compatibility

**Purpose:** Сделать raw content локально потребляемым и сохранить старые worlds.

**Why:** Одинаковый archive не гарантирует одинаковый импорт; library update не должен менять save.

**Inputs:** WP1.1; versioned import recipes; units/channels/colorspace/normal convention; exact Godot binary and target profile.

**Implementation:** Isolated allowlisted import; prepared cache key; local export bundle; no runtime HTTP; old/new lock migration; source relocation; dependency retention; CI job.

**Acceptance criteria:** Clean machine clone/prepare/sample затем offline repeat; missing/corrupt assets дают явные errors; same toolchain/target gives same prepared hash; old lock survives new library version.

**Executable proof:** Proof E полностью: one small real surface set, old-version replay, mirror replacement, offline reuse and eviction/pin test.

**Dependencies:** WP1.1; project Godot/importer pin; independent verifier.

**Out of scope:** WORLDGEN runtime mutation, automatic generator upgrade, universal cross-GPU pixel equality.

**Final gate:** WORLD PACKS FOUNDATION DONE: frozen compatible schema + exact identity/rights/locks + fetch/import/cache/offline CI verified.

### WP2.0 — Read-only semantic surface consumer contract

**Purpose:** Соединить WP recipes с настоящим Matter/WORLDGEN без нового terrain owner.

**Why:** Catalog fixture не доказывает, что renderer видит реальные вскрытые материалы.

**Inputs:** Foundation; actual Matter IDs/catalog hash/composition/revision; WORLDGEN body frames; RL invalidation contract.

**Implementation:** Bounded adapter DTO for surface point/frame/normal/gravity optional/composition/exposure/revision; resolve material bindings; server metadata-only path; documented missing material fallback.

**Acceptance criteria:** No new physics/wire/persistence owner; unknown material rejected or exact neutral fallback; headless server starts without texture cache; capability has no physical effect.

**Executable proof:** Owner-bound contract test on generated and mutated Matter sample; forged catalog binding rejected.

**Dependencies:** Main-owned P7.7 COMPLETE_MERGED + formal P7 acceptance + WORLDGEN executable activation + available scheduler slot, rechecked live.

**Out of scope:** Changing Moon physical sampler, procedural cave implementation, construction simulation.

**Final gate:** Independent owner review + adapter exact tests; absence of producer fields stays explicit, not fabricated.

### WP2.1 — Same generator, different appearance — Proof A

**Purpose:** Показать замену поверхностей без fork генератора и без ручных сцен на каждый мир.

**Why:** Это основная проверка назначения библиотеки.

**Inputs:** WP2.0; два различимых real prepared appearance sets; same generation seed/profile/material catalog.

**Implementation:** One generic sample launcher; recipe-selected material presentation, regional/local scale transitions; macro/micro masks derived from same data.

**Acceptance criteria:** At least 3 fixed seeds, same geometry/Matter/collision hash and different declared presentation output; zero world-specific renderer code.

**Executable proof:** A: basalt-style vs desert-style presentation on SAME canonical material bindings, labelled artistic where necessary; screenshot/evidence hashes and unchanged canonical oracle.

**Dependencies:** WP2.0; compatible renderer consumer and prepared resources.

**Out of scope:** Calling the same physical basalt "actual sandstone". Real sandstone geology requires a separately versioned Matter/generation change.

**Final gate:** A green across 3 seeds and repeat launches; independent visual + canonical verification.

### WP2.2 — Digging/exposure/restart/seam — Proof C

**Purpose:** Отображать реальный subsurface после mutation.

**Why:** Static top texture не подходит mutable world.

**Inputs:** WP2.1; canonical MW4/MW10 bricks with at least 3 distinguishable physical material states/layers.

**Implementation:** RL revision invalidation + material/exposure presentation; new wall/floor/cave surface; same pipeline after persistence/restart.

**Acceptance criteria:** Dig top -> compacted -> fractured/bedrock follows actual Matter; no duplicate yield; two clients agree on physical hashes; region A/B crossing and restart retain result.

**Executable proof:** C: bounded dig stand with before/after material IDs, revision/cache invalidation, mass oracle, two-client and restart traces.

**Dependencies:** Existing accepted P7/MW4–MW10/RL2/RL3 paths; no replacement protocols.

**Out of scope:** Pack-owned depth thresholds, physics from texture, fake cosmetic hole.

**Final gate:** C green with no second terrain store and no stale material after mutation/restart.

### WP3.0 — Arbitrary-body multiscale surface — Proof B

**Purpose:** Использовать ту же библиотеку на non-planar asteroid и cave/overhang.

**Why:** Neither Y-up nor single radial height may constrain the content model.

**Inputs:** WP2; owner-generated irregular Matter fixture; stable body-fixed coordinates and renderer near/far contracts.

**Implementation:** Triplanar/procedural-3D/local tangent consumer; normal separate from gravity; orbital/regional/local/micro bands; origin-recenter and LOD paths.

**Acceptance criteria:** At least one irregular body, inward cave surface and overhang; 3 orientations; stable feature placement; no visible seam/crawl across recenter; bounded measured memory.

**Executable proof:** B: same recipe over asteroid surfaces including negative radial-normal dot; LOD and render-origin roundtrip with canonical hash invariant.

**Dependencies:** WORLDGEN irregular volume and RL LOD readiness; WP2 consumer; renderer capability baseline.

**Out of scope:** New gravity solver, full-planet voxel allocation, claiming flat pad proves asteroid support.

**Final gate:** B green plus declared hardware/scene-specific frame-time and memory budget, measured rather than object-count proxy.

### WP3.1 — Reusable world recipes and generation-ready closure

**Purpose:** Собрать несколько миров без дублирования content или кода.

**Why:** Композиция должна подтверждаться реально используемыми building blocks.

**Inputs:** A/B/C/E proofs; ≥4 surface families and ≥3 environment profiles; WORLDGEN archetype inputs.

**Implementation:** Generic generator entry consumes generation identity + WP recipe; create moon-like, desert-like and icy/irregular cases using shared assets; optional ECO/FILL adapters.

**Acceptance criteria:** At least 3 generated worlds including planet/moon + asteroid; no per-world scene/script; one family reused across ≥2 worlds; digging and save pins retained.

**Executable proof:** Composition replay across 3 seeds/world; explicit canonical-vs-scenery labels; server without high-resolution assets.

**Dependencies:** WP3.0 + actual WORLDGEN producers; optional ECO only after its own integration gates.

**Out of scope:** Pack enabling life/atmosphere/gameplay, unreviewed merging of whole research branches.

**Final gate:** WORLD PACKS GENERATION READY: A/B/C/E green, generic consumer and body/material compatibility independently verified.

### WP4.0 — Client capability and fidelity — Proof D

**Purpose:** Один мир для low/mid/high клиентов.

**Why:** Graphics quality не должна создавать разные simulation identities.

**Inputs:** Generation-ready; ≥2 real fidelity variants of same family; declared capability and fallback policy.

**Implementation:** Deterministic client variant selection; prepared per-platform resources; explicit diagnostic vs reference-based fidelity claims; measured texture/detail budgets.

**Acceptance criteria:** Casual/high clients share identical canonical world/material/mutation hash; selected variants reproducible; absent capability has declared local fallback; no online fetch.

**Executable proof:** D: two simultaneous clients, quality switch + restart, same dig outcome; display differs without canonical state change.

**Dependencies:** WP3.1; client capability contract; calibrated reference data for any measured-appearance claim.

**Out of scope:** Two separate worlds, physics LOD change, claiming 8K means scientific fidelity.

**Final gate:** D green, measured client budgets and fallback oracle; same semantic family in all modes.

### WP4.1 — Catalog scale, lifecycle and storage portability

**Purpose:** Подтвердить рост без asset database/server как обязательной зависимости.

**Why:** 10000 assets и несколько mirrors не должны создавать N копий pack assets.

**Inputs:** WP4.0; generated manifest corpus; content-addressed cache; immutable locks.

**Implementation:** Sharded Git indexes, taxonomy/search tooling, duplicate/deprecation/compatibility gates, cache concurrency/quota/pinning; replaceable location provider.

**Acceptance criteria:** 10000 descriptors + 250 recipes validate deterministically under recorded time/RSS limits; no payload duplication by pack; deprecated old versions still resolve; mirror swap preserves locks.

**Executable proof:** Synthetic scale benchmark + real small-blob backend switch filesystem/mock object-store adapter; concurrent corrupt/partial cache recovery.

**Dependencies:** Frozen foundation contracts; measured capacity target fixed before benchmark.

**Out of scope:** Building production CDN, changing stable asset IDs to storage URLs, silent latest aliases.

**Final gate:** Scale/recovery/storage-portability evidence green; newly measured limits published, not assumed from fixture tests.

### WP4.2 — Integrated production qualification

**Purpose:** Закрыть библиотеку как production-ready subsystem, а не бесконечную ветку.

**Why:** Каждый отдельный proof должен оставаться истинным в одном assembled product.

**Inputs:** A–E, scale/lifecycle evidence, production DWS integration slot and main-owned promotion policy.

**Implementation:** One released library snapshot; 3 complete generated worlds; distribution/license audit; documented authoring/prepare/recovery/migration; CI regression and independent review.

**Acceptance criteria:** All A–E on exact release, 2-client/seam/restart no physics divergence, offline startup, no heavy Git payloads, actual hardware budgets, external raw storage replaceable.

**Executable proof:** Clean clone -> prepare -> 3 worlds -> dig/seam -> fidelity switch -> restart -> offline replay, exact lock and canonical evidence bundle.

**Dependencies:** WP4.1; V0 PLAYABLE acceptance and required WORLDGEN product-promotion gates; human main merge gate.

**Out of scope:** Guaranteeing all future planets/features without new generic WORLDGEN operators; mandatory cloud service.

**Final gate:** WORLD PACKS PRODUCTION READY only after independent release verification + authorized product promotion; implementer cannot self-accept.

## 4. Конечные состояния и stop conditions

| Состояние | Closure criteria |
|---|---|
| FOUNDATION DONE | WP1.0–1.2 independently verified; frozen schema/exact refs/provenance; real secure fetch/import; offline cache; old-lock compatibility; CI; full Proof E |
| GENERATION READY | Foundation + A/B/C; ≥3 worlds, ≥4 families, ≥3 profiles; one generic consumer; planet/moon + asteroid + exposed surfaces; no per-world hand scene; server texture-independent |
| PRODUCTION READY | Generation + D + all A–E on one release; 10000 assets/250 recipes benchmark; restore/migration/rights/concurrency; measured client budgets; independent release + canonical promotion |

Stop immediately for: second Matter/terrain owner; pack-owned physical strata; unknown
asset provenance; required bytes without real hash; runtime network dependency; asset
location changing world identity; upstream branch drift; illegal runtime lease; false
closure from a mock. Keep diagnostics and propose bounded repair, never quietly widen scope.

## 5. Ближайший конкретный следующий шаг

Independent review WP1.0 candidate, затем **WP1.1 Locked External Sources and Safe Fetch**.
Не WP0.11 ещё один biome и не немедленная замена terrain renderer. Новый importer,
WORLDGEN adapter и E2E worlds — последующие отдельные executable checkpoints.
