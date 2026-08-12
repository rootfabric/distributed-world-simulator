# FPE-R2 S8 accepted / S9 volumetric hand prototype

Date: 2026-08-12
Branch: `research/first-person-embodiment-prototype`
Frozen parent: `feature/ch9-6-playable-network-equipment-lab @ e547ba52a440e72cc02c6bbe449edaf160bae7ab`

## S8 acceptance

Operator rerun on `ec59d0d61062393f9d21bf254aa365cba96bb89d` completed cleanly:

- `FPE R2 S8 skinned hand retarget provider: PASS (46 assertions)`
- `FPE R2 S8 skinned configurable viewmodel: PASS (25 assertions)`
- sandbox owner collision isolation: PASS (30)
- performance gate: PASS (10)
- graphical scene load: PASS (27)
- final `FirstPersonEmbodiment focused tests: PASS`

Graphical run with:

`-SkinnedHandScene res://tests/fixtures/fpe_s8_skinned_hand_visual.tscn`

also reached the requested runtime path. HUD reported `RESOURCE_SKINNED_RETARGETED` for both first-person hands while one-hand/two-hand presentation remained functional.

The visible palm/finger parts in the S8 fixture are flat rectangular quads. This is expected contract geometry: S8 proves weighted `ArrayMesh`, bone/weight arrays, named `Skin` binds and source-to-canonical retargeting. It is not accepted as final hand art quality.

Therefore:

`FPE_R2_S8_RESEARCH_CONTRACT_ACCEPTED`

means the weighted skin/retarget architecture is accepted, not that the S8 fixture is production visual art.

## S9 opened

S9 introduces a volumetric low-poly full-hand asset over the exact same S8 provider contract:

- one weighted `ArrayMesh` per hand;
- volumetric palm;
- five fingers;
- three volumetric phalanges per finger;
- 16 named weighted binds: palm + 15 finger bones;
- explicit bind poses matching the canonical-compatible rest space;
- no Item Graph, network, gameplay-transform or collision ownership.

New fixture:

`res://tests/fixtures/fpe_s9_volumetric_skinned_hand_visual.tscn`

New focused gate:

`FPE R2 S9 volumetric skinned hand asset: PASS`

The S9 geometry is still a research low-poly visual candidate, not final production art, but it must no longer appear as zero-thickness rectangular palm/finger strips.
