# Agent Work Order — WORLD FILL Plugin / Content Scout

## Mission

Find, evaluate and integrate optional Godot 4.7-compatible tools/assets that accelerate WORLD FILL while preserving the train constitution.

Target scene:
`scenes/labs/world_fill/world_fill_demo.tscn`

## Required evaluation order

### A. Native baseline first
Prove what can be done with:
- `MultiMeshInstance3D`;
- `WorldEnvironment`;
- `DirectionalLight3D`;
- GPUParticles3D;
- AudioStreamPlayer/3D;
- Decal;
- standard glTF import.

External plugins are only accepted when they materially improve authoring or runtime cost.

### B. Scatter plugin candidates

Evaluate at least:
1. **Scatter** from the Godot Asset Store — editor-only graph authoring over native MultiMesh, MIT, minimum Godot 4.7 at the time this order was written.
2. **ProtonScatter** — Godot 4 procedural non-destructive scatter, MIT.

For each candidate record:
- exact source URL + commit/tag;
- license;
- Godot 4.7.1 compatibility;
- double-precision compatibility;
- GL Compatibility renderer behavior;
- editor-only vs runtime footprint;
- import time;
- startup warnings/errors;
- deterministic seed support;
- ability to bake/export to native scene/MultiMesh;
- maintenance/activity;
- reasons to accept or reject.

Do not make either plugin mandatory.

### C. Asset/content sources

Prioritize redistributable CC0 sources:
- Poly Haven for PBR textures, HDRIs and individual props;
- ambientCG for PBR surfaces/HDRIs;
- Kenney CC0 3D packs for simple modular/space props.

Quaternius is visually useful, but its current site-level license must be checked asset-by-asset before repository redistribution. Do not commit assets with ambiguous redistribution terms.

## R1 demo composition

Populate the WORLD FILL demo with a small but coherent "industrial moon dig site":
- ground material;
- 20–100 decorative stones using MultiMesh/scatter;
- 3–8 larger rocks;
- 1 antenna/beacon;
- 2–6 crates/debris pieces;
- dust/fog ambience;
- one looping ambient sound if license-clean;
- optional impact/dust event example;
- one camera composition suitable for screenshot evidence.

## Repository hygiene

Third-party content must live under:
`assets/third_party/<source>/<pack_or_asset>/`

Every imported source must include:
`assets/third_party/<source>/<pack_or_asset>/SOURCE.md`

SOURCE.md must record:
- source URL;
- author/source;
- downloaded date;
- original license name and URL;
- whether redistribution is allowed;
- modifications;
- imported files;
- original archive checksum when available.

Never commit a marketplace asset whose redistribution terms are unclear.

## Validation

Use canonical double Godot 4.7.1.

Required:
1. fresh import with `.godot/` removed;
2. headless project parse;
3. headless launch of `world_fill_demo.tscn`;
4. no parser errors;
5. no missing resource errors;
6. screenshot/manual visual evidence when graphical runner is available.

## Deliverable

Return:
- chosen/rejected plugin matrix;
- chosen asset list + license ledger;
- changed files;
- exact Godot output;
- screenshot(s);
- performance snapshot;
- follow-up risks.

Do not touch P7/MW authority, Item Graph truth, persistence, handoff, ECO truth, WORLDGEN truth or FABRIC truth.
