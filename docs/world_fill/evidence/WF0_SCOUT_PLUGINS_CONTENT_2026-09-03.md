# WF0 — Plugin / Content Scout Report (R1) — 2026-09-03

Scout: Plugin/Content Scout agent (WORLD FILL train, R1)
Work order: `docs/world_fill/AGENT_PLUGIN_CONTENT_SCOUT.md`
Mission type: **research + evaluation only — no integration, no commits.**

## Scope and method

- Target scene context: `scenes/labs/world_fill/world_fill_demo.tscn` +
  `scripts/world_fill/demo/world_fill_demo.gd`.
- Project constraints verified from `project.godot`:
  `config/features=PackedStringArray("4.7", "Double Precision", "GL Compatibility")`,
  `renderer/rendering_method="gl_compatibility"` — **every plugin/renderer claim
  below is evaluated against GL Compatibility + double-precision builds.**
- Verification marks used in this report:
  - **VERIFIED** — the fact was obtained first-hand in this session (clone
    inspected, API/page fetched, file read). Method noted inline.
  - **DESK-CHECKED** — from documentation/release notes/README claims only; must
    be re-proven by the integrating agent.
  - **NOT RUN** — requires running Godot (import/launch); explicitly out of the
    scout's scope because the concurrent agent owns canonical runtime
    validation in this worktree.
- Network: shallow git clones and metadata fetches were performed **only** into
  `%TEMP%\wf-scout\` (`protonscatter` @ tag `4.0`, `scatter-xwx` @ `main`).
  `git ls-remote` and `git clone --depth 1` both work through the session proxy;
  the earlier "cannot resolve github.com" failure did not reproduce. No clone,
  download, or git write touched the repository worktree.
- No Godot binary was run. No `.godot/` import was triggered. No files outside
  this report were created or modified. Nothing was committed.

---

## 1. Native baseline checklist (evaluation order A)

Current demo coverage (VERIFIED by reading `scripts/world_fill/demo/world_fill_demo.gd`, 91 lines):

| Native item | Covered today | Evidence / gap |
|---|---|---|
| `MultiMeshInstance3D` | **NO** | `_build_rocks()` (lines 39–56) spawns **36 individual `MeshInstance3D`** (SphereMesh scaled/rotated) — 36 draw calls where 1 MultiMesh would do. Seeded RNG `rng.seed = 0x57464C30` is already deterministic — good WF0.2 precedent. This is the single biggest native-baseline gap. |
| `WorldEnvironment` | YES (partial) | `BG_COLOR` dark space blue + `AMBIENT_SOURCE_COLOR` at 0.45 energy (lines 11–20). No sky/HDR background, no fog, no glow. |
| `DirectionalLight3D` | YES | rotation `(-42, -28)`, energy 1.7, `shadow_enabled = true` (lines 22–26). |
| `GPUParticles3D` | **NO** | Dust/fog ambience (WF0.4) not started. Compatibility-renderer support note below. |
| `AudioStreamPlayer` / `AudioStreamPlayer3D` | **NO** | No ambience or event audio (WF0.5). |
| `Decal` | **NO — and unavailable in this project's renderer** | Godot docs (master, `using_decals.rst`, fetched from godot-docs source this session): *"Decals are only supported in the Forward+ and Mobile renderers, not the Compatibility renderer."* and *"If using the Compatibility renderer, consider using Sprite3D as an alternative for projecting decals onto (mostly) flat surfaces."* → **WF0.3 must not plan on native `Decal` nodes** (VERIFIED, docs source). |
| glTF import | **NO** | No `.glb`/`.gltf` anywhere under `scripts/world_fill/` or `scenes/labs/world_fill/`; demo is deliberately asset-free at baseline. Standard glTF import is the intended path for Poly Haven models (see §3). |
| Camera composition | YES | Fixed `Camera3D` at `(17, 10, 22)` looking at `(0, 1.2, -3)` — usable for screenshot evidence. |

Renderer-feature notes for this project (GL Compatibility):

- `Decal` — **not supported** (VERIFIED quote above). WF0.3 alternatives:
  blit scars into the ground material's albedo/normal via a small canvas/SVG
  texture set, `Sprite3D`/`QuadMesh` overlays lying on the surface, or a custom
  ground shader with a scar-mask texture. All remain presentation-only.
- `GPUParticles3D` in GL Compatibility — supported since Godot 4.3
  (DESK-CHECKED: 4.3 release notes page fetched this session; the headline
  sentence was not captured through the slow proxy — re-verify on the double
  custom build at WF0.4). Fallback if it misbehaves on the double build:
  `CPUParticles3D` (CPU path, renderer-independent).
- `MultiMeshInstance3D` in GL Compatibility — standard supported feature
  (DESK-CHECKED, engine docs; MultiMesh predates 4.x renderers and is the
  canonical vegetation/rock path on Compatibility). Confirm in the WF0.2
  fresh-import validation run (NOT RUN here).

**Baseline verdict:** the R1 composition (ground, stones, boulders, crates,
beacon, ambience) is achievable with native nodes + CC0 assets alone.
Plugins are not needed for runtime. The one mandatory native change is
replacing the 36 per-rock `MeshInstance3D` with `MultiMeshInstance3D` (WF0.2).

---

## 2. Plugin matrix (evaluation order B)

Two candidates evaluated. They are **different projects**: the Asset Store
entry "Scatter" (xiaowangxu) is not ProtonScatter.

### 2.1 Scatter — Godot Asset Store (xiaowangxu/godot-scatter-plugin)

| Field | Finding | Mark |
|---|---|---|
| Exact source URL | Store: `https://store.godotengine.org/asset/xiaowangxu/scatter/` — Repo: `https://github.com/xiaowangxu/godot-scatter-plugin` | VERIFIED (store page fetched; repo cloned) |
| Latest tag/commit | No git tags. `main` @ `b42238f30f67a0553c96b92d4800a476a55b674d` ("save", 2026-07-16); other branches `dev`, `refactor`, `refactor-interface`; repo created 2026-07-13, last push 2026-07-23. Store release string: **v0.0.1-alpha**; repo `addons/scatter/plugin.cfg` says `version="3.0.0"` (versioning inconsistency — pin the commit, not the version string) | VERIFIED (clone + GitHub API + ls-remote) |
| License | **MIT** — `addons/scatter/LICENSE`: "MIT License. Copyright (c) 2026 WangxuXiaofeng, Scatter Plugin Contributors". Store page also states "License: MIT". Note: GitHub's license detector shows "None" because the LICENSE sits inside `addons/scatter/`, not at repo root — do not misread this as unlicensed. | VERIFIED (read the LICENSE file in the clone) |
| Godot 4.7.1 compatibility | README headline: **"Scatter for Godot 4.7+"**; its `project.godot` declares `config/features=PackedStringArray("4.7", "Forward Plus")`. This matches the work order's "minimum Godot 4.7". Behavior on the **double** 4.7.1 custom build: NOT RUN (see §2.3 note) | VERIFIED (README + project.godot) / NOT RUN |
| Double-precision compatibility | Pure GDScript: 164 `.gd` files; **zero** `.cs`/`.cpp`/`.h`/`.gdextension` binaries → no ABI/float build to rebuild; GDScript floats are doubles in double builds and `Vector3`/`Transform3D` follow build precision. No hardcoded single-precision math constants found in a structural review. | VERIFIED (file census) |
| GL Compatibility renderer status | Output is a plain `MultiMeshInstance3D` — README: "runtime rendering stays on Godot's standard MultiMesh path". Grep of all addon `.gd`/`.gdshader` for `volumetric/ssao/ssil/sdfgi/forward_plus/rendering_method`: **0 hits** → renderer-agnostic. Its own demo project targets Forward Plus, but nothing in the addon code requires it. | VERIFIED (grep over clone) |
| Editor-only vs runtime footprint | Editor-only by design: README — "does not add custom nodes to your scene tree and it does not evaluate the graph at runtime. A built scene contains an ordinary `MultiMeshInstance3D`". 157 of 164 `.gd` files are `@tool`; editor wiring uses `EditorInterface`/`EditorNode3DGizmoPlugin`. Runtime footprint after bake = **zero addon code**; only the saved MultiMesh buffer ships. Addon size ≈ 2.4 MB. | VERIFIED (clone inspection) |
| Import time / startup warnings | NOT RUN — scout does not run Godot in this worktree (concurrent agent owns canonical import). Integration must record: fresh-import time with the addon present, and headless launch sentinel/errors. | NOT RUN |
| Deterministic seed support | README: "Deterministic output — seeded random operations are reproducible and individual nodes can use independent seeds." Behavior not yet tested in this project. | DESK-CHECKED (README claim) |
| Bake/export to native MultiMesh | Native to its design: the graph **writes the instance transform/color/custom-data result directly into a `MultiMesh` buffer** on an ordinary `MultiMeshInstance3D`; recipes are external `.tres` graph resources referenced by scene metadata. No conversion step needed. | VERIFIED (README + plugin.cfg description + code structure) |
| Maintenance activity | Created 2026-07-13; last push 2026-07-23; 3 stars. README carries: "Scatter is under active development. APIs … may change without migration support." → very young, fast-moving, v0.0.1-alpha maturity. | VERIFIED (GitHub API) |
| Risks | Pre-alpha churn; no tags to pin releases against; single-author bus factor; store listing younger than 3 months at time of writing. | — |

**Recommendation (Scatter):**
- As **runtime dependency**: **REJECT** (moot by design — it adds no runtime code — but also not needed: WF0.2 baseline is native `MultiMeshInstance3D` per the roadmap).
- As **editor-only authoring aid**: **ACCEPT as a WF0.2 pilot candidate, conditional on**: (1) vendoring/pinning exact commit `b42238f` in a scratch/authoring context, never as an enabled plugin of the canonical demo project; (2) recording import time + startup warnings on the double 4.7.1 build; (3) proving seeded determinism by rebuilding a test scatter twice and diffing baked transforms; (4) re-evaluation before WF0.7 because of alpha churn. If any condition fails, fall back to hand-authored MultiMesh placement — nothing else in the train depends on it.

### 2.2 ProtonScatter (HungryProton) — Codeberg primary, GitHub mirror

| Field | Finding | Mark |
|---|---|---|
| Exact source URL | **Primary:** `https://codeberg.org/hungryproton/proton_scatter` (created 2026-07-26; GitHub repo description itself says: "Mirror of https://codeberg.org/hungryproton/proton_scatter"). Mirror: `https://github.com/HungryProton/scatter`. Asset Library listing exists per the 4.0 release notes ("Also available in the Asset Library"); the Asset Library API refused the id I probed ("Couldn't find asset with id 7802") — treat the exact listing id as unconfirmed. | VERIFIED (APIs) / listing id DESK-CHECKED |
| Latest tag/commit | Latest tagged release on GitHub: **`4.0` @ `ca624412c657d469147b4ce464cee290df738a40`**, published 2023-10-23 ("fix 4.2 compatibility"; release body: "works with Godot 4.x (4.0 to 4.2 at the time of writing)"). Development continued on **Codeberg main @ `3a9c5c1640…` (2026-08-05)** — including commit `2ced25f1eb` 2026-07-26 **"adds uid files to the repo, fix compatibility issue with 4.7"**. So: tagged releases are stale; 4.7 fixes live untagged on Codeberg main. | VERIFIED (clone @ tag + Codeberg commits API) |
| License | **MIT** — `LICENSE.md`: "Copyright (c) 2020-present HungryProton." | VERIFIED (read in clone) |
| Godot 4.7.1 compatibility | Tag `4.0` targets 4.0–4.2. A dedicated "fix compatibility issue with 4.7" commit exists on Codeberg main (2026-07-26), so current main is 4.7-aware, but **no release/tag carries it** — consumption would mean pinning an untagged moving `main`. | VERIFIED (commit message) / runtime NOT RUN |
| Double-precision compatibility | Pure GDScript: 81 `.gd` files; zero `.cs`/`.cpp`/`.h`/GDExtension; only 5 `.gdshader` (demo/example particle shaders). Script-level floats follow build precision → double-safe structurally. MultiMesh instance transforms are set through the standard API. | VERIFIED (file census + source read) |
| GL Compatibility renderer status | Output = **one `MultiMeshInstance3D` per ScatterItem** (`src/scatter.gd:379–402` `_update_multimeshes`, plus `_update_split_multimeshes` chunking) — a core Compatibility feature. Grep of `src/` for `volumetric/ssao/ssil/sdfgi/forward_plus/rendering_method`: **0 hits** → renderer-agnostic. | VERIFIED (source read + grep) |
| Editor-only vs runtime footprint | Editor-heavy: 77 `@tool` files in `src/`. Caveat: `ProtonScatter` is a `@tool` **scene node** — left in a scene, it rebuilds in the running game (threads/rebuild logic live in `scatter.gd`). Runtime-safe path = `ScatterCache` (`src/cache/scatter_cache.gd`): stores transforms to `.res/.tres` and restores at scene load, "much more VCS friendly". Vendor footprint: core `addons/proton_scatter` ≈ **623 KB / 249 files**, plus **11.2 MB of demos** that must be stripped. | VERIFIED (clone measurements) |
| Import time / startup warnings | NOT RUN (same reason as §2.1). | NOT RUN |
| Deterministic seed support | Yes: `@export var global_seed := 0` (`src/scatter.gd:28`); every modifier receives and applies the seed (`_process_transforms(..., random_seed)` → `_rng.set_seed(random_seed)` in `create_inside_random.gd`; seeded shuffle in `transform_list.gd`). This is architecturally compatible with the WF0.1 dressing contract's stable-seed model. | VERIFIED (code) |
| Bake/export to native MultiMesh | Output is already native `MultiMeshInstance3D` assembly; `ScatterCache` is the bake/persist mechanism (external transform-list resource, restorable without scatter nodes at runtime if the cache is loaded and the scatter node removed). | VERIFIED (code read) |
| Maintenance activity | Active: Codeberg repo created 2026-07-26, last commit 2026-08-05; GitHub mirror last push 2026-07-26; 2,979 stars, 69 open issues (GitHub, pre-move); project is alive but its release/tag pipeline lags development. | VERIFIED (APIs) |
| Risks for this train | (1) tag `4.0` predates 4.7 — must pin Codeberg `main` SHA, which can move; (2) `@tool` node runtime-rebuild hazard if a scattered scene is copied into DWS without cache/bake + node strip; (3) heavier addon + demo payload to exclude; (4) no canonical Godot 4.7.1-double validation evidence anywhere yet. | — |

**Recommendation (ProtonScatter):**
- As **runtime dependency**: **REJECT.**
- As **editor-only authoring aid for R1**: **REJECT for now.** Scatter (§2.1) covers the same authoring niche with a smaller, purpose-built, zero-runtime-footprint tool and an explicit Godot 4.7 target. Reconsider ProtonScatter at WF0.2+ only if Scatter's graph proves too limited: then pin Codeberg `main` SHA + verify on the double build in a separate authoring project, and ship only `ScatterCache`-baked native scenes.

### 2.3 Shared integration note (both plugins)

- Neither plugin may become an enabled plugin of the canonical project
  (`project.godot` `[editor_plugins]` currently enables only
  `breakpoint_mcp`). Keep any authoring aid in a separate authoring lab/project
  and copy **baked native output** into the worktree.
- Both are GDScript-only, so double-precision risk is low at the scripting
  layer; the remaining double-build risks are editor-plugin quirks that only an
  import/launch run on `4.7.1.stable.double.custom_build.a13da4feb` can expose
  (NOT RUN here — required of the WF0.2 integration agent before any ACCEPT is
  finalized).
- Determinism chain for WF0.2 must remain: dressing contract
  (`world_fill.dressing_decision.v1`, `determinism_key`, density bands) →
  scatter pass seeded from that decision. Plugin-authored scatters are
  one-off authoring artifacts; procedural runtime scatter stays native code
  (roadmap: "editor scatter plugins are optional authoring accelerators, not
  runtime dependencies").

---

## 3. Content shortlist (evaluation order C) — "industrial moon dig site"

License posture of the three prioritized sources:

- **Poly Haven — CC0, site-wide, VERIFIED** (polyhaven.org/faq, fetched this
  session: "All our assets are released under the CC0 license, meaning you can
  use them for absolutely any purpose, including commercial work."). Per-asset
  author/tag metadata and `files_hash` checksums VERIFIED via
  `api.polyhaven.com/info/<slug>`. glTF availability VERIFIED on asset pages
  (moon_rock_01 page metadata lists `gltf,fbx,usd`).
- **ambientCG — CC0, site-wide, VERIFIED** (asset page text, fetched: "Yes. All
  assets are released under the Creative Commons CC0 license, making them free
  to use without attribution - even in commercial circumstances."). Direct
  download pattern `https://ambientcg.com/get?file=<ID>_<res>-<fmt>.zip` VERIFIED
  with a 302 redirect to their CDN for `Gravel023_2K-JPG.zip`.
- **Kenney — CC0, per-pack VERIFIED** (all four pack pages below state "for
  free, CC0 licensed!" in their og:description; exact zip URLs extracted).
- **Quaternius — EXCLUDED from R1.** Caveat confirmed: the site advertises
  "using the CC0 License" in metadata, but `quaternius.com/license.html`
  (VERIFIED fetch; "Last updated: 8/28/2026") is a **bespoke bilateral License
  agreement** ("This License is between you (the Licensee)… and Quaternius (the
  Licensor)…") rather than plain CC0 text. Per the work order
  ("Do not commit assets with ambiguous redistribution terms"), no Quaternius
  asset is shortlisted; revisit only after a per-asset legal read of that
  license text.

### 3.1 Candidate assets (10 primary)

| # | Asset | Source + exact URL | Role in R1 demo | License | Redistribution | Mark |
|---|---|---|---|---|---|---|
| 1 | **Moon Dusted 01** (PBR texture) | Poly Haven — `https://polyhaven.com/a/moon_dusted_01` | Ground material (regolith albedo/normal/rough) — matches dressing surface `regolith` | CC0 | Allowed | VERIFIED (info API: authors Greg Zaal, Rico Cilliers, Jenelle van Heerden, Dario Barresi; tags "regolith, dusted"; `files_hash` captured) |
| 2 | **Moon Footprints 01** (PBR texture) | Poly Haven — `https://polyhaven.com/a/moon_footprints_01` | Ground variant with track impressions — dig-site narrative; mood reference for WF0.3 scar texturing | CC0 | Allowed | VERIFIED (info API + `files_hash`) |
| 3 | **Gravel Ground 01** (PBR texture) | Poly Haven — `https://polyhaven.com/a/gravel_ground_01` | Industrial apron / work-path material, blendable with #1 (author Rob Tuytel) | CC0 | Allowed | VERIFIED (info API + `files_hash`) |
| 4 | **Moon Rock 01** (model, LODs) | Poly Haven — `https://polyhaven.com/a/moon_rock_01` | `stones` family — MultiMesh-instanced decorative stones (tags: "lunar, regolith, space"; glTF download) | CC0 | Allowed | VERIFIED (info API + `files_hash` + glTF listing) |
| 5 | **Moon Rock 04** (model, LODs) | Poly Haven — `https://polyhaven.com/a/moon_rock_04` | `boulders` family — the 3–8 large rocks | CC0 | Allowed | VERIFIED (info API + `files_hash`) |
| 6 | **Old Military Crate** (model) | Poly Haven — `https://polyhaven.com/a/old_military_crate` | Crates (author Jack Mava; hand-painted military supply crate) | CC0 | Allowed | VERIFIED (info API + `files_hash`) |
| 7 | **Plastic Crate 01** (model) | Poly Haven — `https://polyhaven.com/a/plastic_crate_01` | Secondary crates / industrial scrap dressing | CC0 | Allowed | VERIFIED (info API + `files_hash`) |
| 8 | **Industrial Plastic Container** (model) | Poly Haven — `https://polyhaven.com/a/industrial_pastic_container` | Debris / `industrial_scrap` family (note: the slug's "pastic" typo is Poly Haven's own — keep exact slug) | CC0 | Allowed | VERIFIED (info API + `files_hash`) |
| 9 | **Vintage Radio Transceiver** (model) | Poly Haven — `https://polyhaven.com/a/vintage_radio_transceiver` | Antenna/beacon POI stand-in (tags: "military, communications, field radio") until a dedicated antenna mesh is authored for WF0.6 | CC0 | Allowed | VERIFIED (info API + `files_hash`) |
| 10 | **Gravel023** (PBR material) | ambientCG — `https://ambientcg.com/view?id=Gravel023`, direct: `https://ambientcg.com/get?file=Gravel023_2K-JPG.zip` (302 → CDN, VERIFIED) | Secondary industrial gravel / landing-pad edge | CC0 | Allowed | VERIFIED (API listing + page + download redirect) |

Pack-level additions (one URL covers many usable props — preferable for R1 volume):

| Pack | Exact URL | Useful contents for R1 | License | Mark |
|---|---|---|---|---|
| Kenney **Space Kit** (150 assets) | Page `https://kenney.nl/assets/space-kit` — zip `https://kenney.nl/media/pages/assets/space-kit/20874c75ac-1677698978/kenney_space-kit.zip` | Crates/containers, antenna, satellite dish, radar dishes — crates + beacon hardware | CC0 | VERIFIED (page + CC0 statement + zip URL) |
| Kenney **Space Station Kit** (90 assets) | Page `https://kenney.nl/assets/space-station-kit` — zip `https://kenney.nl/media/pages/assets/space-station-kit/6475288f2e-1712749919/kenney_space-station-kit.zip` | Modular industrial/sci-fi structures for the dig-site outpost | CC0 | VERIFIED |
| Kenney **Impact Sounds** (130 assets) | Page `https://kenney.nl/assets/impact-sounds` — zip `https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip` | DIG_IMPACT / DIG_SUCCESS / debris-event sounds (WF0.5 event set) | CC0 | VERIFIED |
| Kenney **Sci-Fi Sounds** (70 assets) | Page `https://kenney.nl/assets/sci-fi-sounds` — zip `https://kenney.nl/media/pages/assets/sci-fi-sounds/6b296f9ecf-1677589334/kenney_sci-fi-sounds.zip` | Ambient loop candidates (`thin_air_loop`, `open_wind` moods) | CC0 | VERIFIED |

Catalog alternates found but not primary (DESK-CHECKED — catalog listing only,
no per-asset info pulled): Poly Haven textures `moon_01`, `moon_02`, `moon_03`,
`moon_04`, `moon_track_01..04`, `rocky_terrain_02/03` (grass-tinted — not
moon-appropriate without grading); ambientCG `Ground110`, `Ground108`,
`Gravel043`, `Ground081`; Poly Haven model series `moon_rock_02..07`,
`namaqualand_boulders_01..06`.

### 3.2 Ready SOURCE.md blocks (per repository hygiene rules)

Target layout: `assets/third_party/<source>/<pack_or_asset>/SOURCE.md`.
All blocks below are ready to commit **with** the asset files; `<SHA256>` and
"imported files" must be filled by the integrating agent at download time.
Poly Haven `files_hash` values below are the source-provided content hashes
(sha1, VERIFIED via `api.polyhaven.com/info/<slug>` this session).

```markdown
# SOURCE.md — assets/third_party/polyhaven/moon_dusted_01/
source_url: https://polyhaven.com/a/moon_dusted_01
author/source: Greg Zaal, Rico Cilliers, Jenelle van Heerden, Dario Barresi (Poly Haven)
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/)
redistribution_allowed: yes (CC0, site-wide Poly Haven policy)
modifications: <none|describe>
imported_files: <list of committed files>
original_archive_checksum: files_hash=sha1:f76d2e354f8acffaa604609e7817f40522798c6f (source-provided); downloaded zip sha256=<fill>
```

```markdown
# SOURCE.md — assets/third_party/polyhaven/moon_footprints_01/
source_url: https://polyhaven.com/a/moon_footprints_01
author/source: Greg Zaal, Rico Cilliers, Jenelle van Heerden, Dario Barresi (Poly Haven)
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/)
redistribution_allowed: yes
modifications: <none|describe>
imported_files: <list>
original_archive_checksum: files_hash=sha1:9e3cb3433e24c097bd9d67e3f97975ba19bbd9bf; downloaded zip sha256=<fill>
```

```markdown
# SOURCE.md — assets/third_party/polyhaven/gravel_ground_01/
source_url: https://polyhaven.com/a/gravel_ground_01
author/source: Rob Tuytel (Poly Haven)
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/)
redistribution_allowed: yes
modifications: <none|describe>
imported_files: <list>
original_archive_checksum: files_hash=sha1:1172e523db8f69e48d18c399dd8d9eac9be73c17; downloaded zip sha256=<fill>
```

```markdown
# SOURCE.md — assets/third_party/polyhaven/moon_rock_01/
source_url: https://polyhaven.com/a/moon_rock_01
author/source: Greg Zaal, Rico Cilliers, Jenelle van Heerden, Dario Barresi (Poly Haven)
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/)
redistribution_allowed: yes
modifications: <none|describe>  ; note if a specific glTF LOD was chosen for the WF0.2 budget
imported_files: <list>
original_archive_checksum: files_hash=sha1:8aac337ef1b7cd03ee522258ce658dbc1bffe554; downloaded zip sha256=<fill>
```

```markdown
# SOURCE.md — assets/third_party/polyhaven/moon_rock_04/
source_url: https://polyhaven.com/a/moon_rock_04
author/source: Greg Zaal, Rico Cilliers, Jenelle van Heerden (Poly Haven)
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/)
redistribution_allowed: yes
modifications: <none|describe>
imported_files: <list>
original_archive_checksum: files_hash=sha1:80374d9ae3cf6a80f1983768987db33576a6e277; downloaded zip sha256=<fill>
```

```markdown
# SOURCE.md — assets/third_party/polyhaven/old_military_crate/
source_url: https://polyhaven.com/a/old_military_crate
author/source: Jack Mava (Poly Haven)
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/)
redistribution_allowed: yes
modifications: <none|describe>
imported_files: <list>
original_archive_checksum: files_hash=sha1:03f2c68403869a77c2b3b4a7b2e2e2266ba616fa; downloaded zip sha256=<fill>
```

```markdown
# SOURCE.md — assets/third_party/polyhaven/plastic_crate_01/
source_url: https://polyhaven.com/a/plastic_crate_01
author/source: PierreB3D (Poly Haven)
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/)
redistribution_allowed: yes
modifications: <none|describe>
imported_files: <list>
original_archive_checksum: files_hash=sha1:74d27ffa75c1d477708f4dd344d500b65d376a84; downloaded zip sha256=<fill>
```

```markdown
# SOURCE.md — assets/third_party/polyhaven/industrial_plastic_container/
source_url: https://polyhaven.com/a/industrial_pastic_container  (slug contains Poly Haven's own 'pastic' typo)
author/source: Galo Benivegna (Poly Haven)
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/)
redistribution_allowed: yes
modifications: <none|describe>
imported_files: <list>
original_archive_checksum: files_hash=sha1:77cda45559262d55ab7c128db322f028d56de412; downloaded zip sha256=<fill>
```

```markdown
# SOURCE.md — assets/third_party/polyhaven/vintage_radio_transceiver/
source_url: https://polyhaven.com/a/vintage_radio_transceiver
author/source: Mateusz Sadek (Poly Haven)
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/)
redistribution_allowed: yes
modifications: <none|describe>
imported_files: <list>
original_archive_checksum: files_hash=sha1:f343f538ee1b638da93aeaf450e50e428a57a2f4; downloaded zip sha256=<fill>
```

```markdown
# SOURCE.md — assets/third_party/ambientcg/gravel023/
source_url: https://ambientcg.com/view?id=Gravel023
download_url: https://ambientcg.com/get?file=Gravel023_2K-JPG.zip (302 -> acg-download.struffelproductions.com CDN)
author/source: ambientCG (Rob?)  ; site does not name per-asset authors in the API
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/) — site-wide ambientCG policy
redistribution_allowed: yes
modifications: <none|describe>
imported_files: <list>
original_archive_checksum: sha256=<fill at download time>
```

```markdown
# SOURCE.md — assets/third_party/kenney/space-kit/
source_url: https://kenney.nl/assets/space-kit
download_url: https://kenney.nl/media/pages/assets/space-kit/20874c75ac-1677698978/kenney_space-kit.zip (hash segment may rotate — re-check page at download)
author/source: Kenney (kenney.nl)
downloaded_date: <fill at integration>
license: CC0 (https://creativecommons.org/publicdomain/zero/1.0/) — pack page states "CC0 licensed"
redistribution_allowed: yes
modifications: <none|describe>
imported_files: <list>
original_archive_checksum: sha256=<fill at download time>
```

(Repeat the Kenney block, mutatis mutandis, for `space-station-kit`,
`impact-sounds`, `sci-fi-sounds` with the URLs in §3.1.)

> Note on Poly Haven download endpoints: `api.polyhaven.com/download/<slug>`
> did not return parseable JSON through this session's proxy (response was not
> JSON — recorded, not retried endlessly). The download step at integration
> should go through the asset page's download button and must capture the
> archive checksum at that time.

---

## 4. Risks and follow-ups (WF0.2 / WF0.7)

1. **Decal is a dead end on GL Compatibility (VERIFIED).** WF0.3 (Surface
   Scars) must be designed around texture blits into the surface material,
   `Sprite3D`/`QuadMesh` overlays, or a scar-mask shader — never `Decal`
   nodes. This should be written into the WF0.3 item description before anyone
   prototypes against the wrong node.
2. **GPUParticles3D on Compatibility + double build (DESK-CHECKED).** Validate
   on `4.7.1.stable.double.custom_build.a13da4feb` early in WF0.4; keep
   `CPUParticles3D` as the documented fallback. Dust gusts are also achievable
   with MultiMesh-billboards if particles misbehave.
3. **WF0.2 determinism architecture.** Scatter placement must derive from the
   WF0.1 dressing decision (`determinism_key`, per-band density budgets) and
   feed one `MultiMeshInstance3D` per family (stones/boulders/debris/
   industrial_scrap). First native step: replace the demo's 36 individual rock
   nodes with a single MultiMesh (immediate draw-call win, no assets needed).
4. **Plugin acceptance protocol (if the Scatter pilot proceeds).** Pin commit
   `b42238f` (Scatter) or a Codeberg `main` SHA (ProtonScatter) in the
   authoring lab only; record fresh-import time, startup warnings, and a
   double-rebuild determinism diff on the double build; never enable the
   plugin in the canonical project; never ship `addons/` content in DWS.
5. **Precision note for real-scale coordinates.** Both plugins compute in
   script space (double-safe), but any authoring scene must not bake transforms
   conditioned on huge world-space magnitudes; author near origin and translate
   at runtime if the playground needs kilometer-scale offsets. Add a
   far-from-origin spot check to the WF0.2 validation list.
6. **Asset volume discipline.** Poly Haven moon_rock models ship LODs (info
   API exposes `lods`); pick a single LOD per family and enforce the per-band
   budgets from the dressing contract. Poly Haven 4K textures should be
   down-imported (2K or 1K) for the demo budget.
7. **Kenney zip URLs rotate** (hash segment in the media path). Re-extract the
   URL from the pack page at download time and record the sha256 in SOURCE.md;
   do not hardcode the current URL as a long-term provenance reference.
8. **Quaternius stays out** until its bespoke license text (updated
   2026-08-28) is reviewed per-asset; current CC0 branding does not match a
   plain CC0 deed.
9. **WF0.7 composition order.** Ground materials (§3.1 #1/#2/#3) + MultiMesh
   stones/boulders (#4/#5) + Kenney crate/beacon hardware + one ambience loop
   is sufficient for the Digging Playground screenshot evidence; the antenna
   POI (#9) is a stand-in until a purpose-built antenna model is authored or
   sourced.

---

## 5. Verification ledger (summary)

**VERIFIED this session** (clone inspected / API or page fetched / file read):

- Demo script + scene contents; project renderer = GL Compatibility, double
  precision (`project.godot`); dressing contract module and density bands.
- Scatter (xiaowangxu): repo cloned @ `b42238f` — MIT license text, plugin.cfg,
  README claims, 4.7 features, 157/164 `@tool` ratio, ~2.4 MB size, zero
  renderer-specific strings, no git tags, store page fields
  (title/description/MIT/v0.0.1-alpha).
- ProtonScatter: tag `4.0` @ `ca624412` cloned — MIT LICENSE.md, plugin.cfg 4.0,
  `global_seed`, seeded modifier RNG, MultiMesh assembly code, 0
  renderer-specific strings, 623 KB core / 11.2 MB demos, 77 `@tool` files;
  GitHub repo API (MIT, GDScript, pushed 2026-07-26, 2,979 stars); Codeberg
  repo API + commits (created 2026-07-26; "fix compatibility issue with 4.7"
  2026-07-26; last commit 2026-08-05); GitHub release 4.0 (2023-10-23) body.
- Godot docs source `using_decals.rst` (master): Decal not supported in
  Compatibility renderer + Sprite3D alternative quote.
- Poly Haven: site-wide CC0 FAQ quote; per-asset authors/tags/`files_hash` for
  the 9 shortlisted slugs; moon_rock_01 page lists glTF downloads; model and
  texture catalog name lists.
- ambientCG: API listing (Ground110/Ground108/Gravel043/Ground079S/Gravel023/
  Ground081); site-wide CC0 text; Gravel023 download 302 to CDN.
- Kenney: CC0 statements + exact zip URLs for all four packs.
- Quaternius: homepage CC0 meta + bespoke `license.html` text ("Last updated:
  8/28/2026").
- Proxy behavior: `git ls-remote`/`git clone --depth 1` work; all clones
  confined to `%TEMP%\wf-scout\`.

**DESK-CHECKED** (documentation/claims only — must be re-proven):

- GPUParticles3D support in GL Compatibility since Godot 4.3 (release-notes
  page reachable; exact sentence not captured through the slow proxy).
- MultiMeshInstance3D behavior on GL Compatibility (standard feature; confirm
  in WF0.2 validation).
- Scatter (xiaowangxu) deterministic-output behavior (README claim) and
  ProtonScatter behavior on Godot 4.7.1 double (commit-message evidence only).
- Asset Library listing coordinates for ProtonScatter (release note text only;
  probed id was rejected by the API).
- Catalog alternates listed in §3.1 tail (names only, no per-asset info pull).

**NOT RUN** (out of scout scope; integration agent must produce):

- Fresh `.godot/`-removed import, headless project parse, headless demo launch,
  import-time and startup-warning measurements with any addon present,
  screenshots, performance snapshot — canonical validation remains with the
  concurrently-running agent; this report deliberately contains none.

## 6. Deliverable record

- Changed files: **this report only**
  (`docs/world_fill/evidence/WF0_SCOUT_PLUGINS_CONTENT_2026-09-03.md`).
- Repository modifications: none. Git operations: none. Godot runs: none.
- Scratch artifacts (outside repo, disposable): `%TEMP%\wf-scout\protonscatter`
  (tag `4.0` @ `ca624412c657d469147b4ce464cee290df738a40`),
  `%TEMP%\wf-scout\scatter-xwx` (`main` @ `b42238f30f67a0553c96b92d4800a476a55b674d`),
  cached API/doc payloads (`ph_models.json`, `ph_textures.json`, `decals.rst`,
  `assetlib.json`, `rel43.rst`).
