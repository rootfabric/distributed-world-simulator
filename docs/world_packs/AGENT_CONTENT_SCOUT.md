# Agent Work Order — WORLD PACKS Content Scout

## Mission

Build a license-clean R1 content catalog and populate the WORLD PACKS gallery under canonical Godot 4.7.1.

Target:
`scenes/labs/world_packs/world_packs_gallery.tscn`

## Priority content sources

### Preferred — repository-safe CC0
1. **Poly Haven**
   - HDRIs;
   - PBR textures;
   - individual 3D props.
2. **ambientCG**
   - PBR surfaces;
   - HDRIs;
   - material source.
3. **Kenney**
   - CC0 modular/space/building props.

### Conditional
**Quaternius** has highly relevant sci-fi kits, including Godot-ready material, but licensing must be verified against the current asset/site terms before redistributing files in this public repository. If redistribution is not unambiguously allowed, keep it out of git and document only a local evaluation.

## First scouting target — Moon Industrial

Find a minimal coherent set:
- regolith/basalt PBR material;
- 3–5 rock variants;
- crate/debris set;
- antenna/beacon;
- small modular station/outpost elements;
- one suitable HDRI or manually configured black-sky environment;
- optional ambient audio from a separately license-clean source.

Prefer glTF/GLB for 3D imports.

## Second scouting target — Mars Dust

Find:
- red rock/soil PBR;
- layered/stony props;
- industrial debris reusable from Moon pack;
- haze/sky solution.

## Do not download blindly

For every candidate answer:
- What exact pack/asset?
- Why does it fit DWS?
- What is the license now?
- Can the raw asset be redistributed in this public repository?
- Is attribution required?
- Approximate disk cost after import?
- glTF/GLB available?
- Does it import cleanly in Godot 4.7.1 GL Compatibility?

## Asset layout

`assets/third_party/<source>/<asset_name>/`

Each asset directory requires `SOURCE.md` with provenance/license.

Pack manifests belong under:
`config/world_packs/packs/`

Do not put canonical gameplay data into pack manifests.

## Gallery composition

R1 gallery must contain equal-size pads for:
- Moon Industrial;
- Mars Dust;
- Frozen placeholder.

Keep geometry intentionally comparable. The pack identity should come from material/environment/props rather than from a different gameplay setup.

## Validation

Canonical double Godot 4.7.1:
- remove `.godot/`;
- fresh import;
- headless parse;
- headless gallery launch;
- no missing resource errors;
- capture screenshots in graphical environment;
- record rough object/draw-call budget.

## Deliverable

Commit:
- source/license ledger;
- selected assets only;
- pack manifests;
- populated gallery scene;
- screenshots/evidence metadata;
- a short accept/reject report for every source evaluated.

Do not modify P7/MW, Item Graph, authority, persistence, network protocol, ECO truth, WORLDGEN truth or FABRIC truth.
