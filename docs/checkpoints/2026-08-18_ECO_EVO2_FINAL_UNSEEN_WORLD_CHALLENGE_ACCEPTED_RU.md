# ECO.EVO2 / E2.FINAL — Unseen World Challenge — ACCEPTED

Дата: 2026-08-18  
Ветка: `feature/eco-evolutionary-ecology`  
Статус: `ACCEPTED / RESEARCH_ONLY / EVO2 RESEARCH ROUTE COMPLETE`

## 1. Exact boundary

```text
E2.8 accepted aggregate
4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061

E2.8 code-under-test
5790de059aaafbfc10434bb2d40124e3c1ceb361

FINAL protocol precommit
 d936efac36d2664ec2f24f26306fa3ba95409117

FINAL accepted code-under-test
376796ab8c8370b7370fcd220ed207d07955cb42

FINAL accepted aggregate
6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250

FINAL evidence
989e5ae02e66052ca7d2e46f5f452446300ba625dd4efd5cd6b5ffd9db2f2cd1

FINAL protocol
 d3dc2b0c2a251cf645d03430eb14ad2215166a5be03f5ec13b8eafb4d56678e1
```

Protocol/world definition was committed at `d936ef...` before the first behavioral result. Geometry, environments, transport and acceptance thresholds were not changed after observing the result.

## 2. What was tested

The challenge starts from the **actual durable E2.8 artifact**, not from an in-memory `SpeciesCatalog` reconstruction:

```text
fresh E2.8 writer process
        ↓
10,383-byte typed artifact
transport SHA-256 b31c863f...
        ↓
fresh-process Persistence.restore
        ↓
full accepted E2.2 SpeciesCatalog + EVO2 provenance
        ↓
precommitted hidden world
        ↓
source-port emission for EVERY restored catalog entry
        ↓
P2.1 dispersal
        ↓
establishment / seed bank / ResourceModel viability
        ↓
P2.4 patch migration
        ↓
colonization-derived founders only
        ↓
paired CONTROL / TREATMENT ecological sorting + adaptation
```

No rebake, biome→species table, target-aware species list or direct catalog builder is allowed.

## 3. Frozen hidden world

```text
reachable cells   dry-ridge / wet-basin
isolated control  isolated-control
transport         (1, 0), turbulence 0.25
emission          frozen genome seed_count × 32
population        8
adaptation run    10 generations × 4 offspring/parent
```

Precommitted minimum gates:

```text
reachable colonized patches >= 2
unique recruited species    >= 2
sorting observed cells      >= 1
adaptation-positive cells   >= 1
isolated control colonized  false
```

`ADAPTATION_NULL`, `ADAPTATION_REVERSAL` and `VALID_NO_COLONIZATION` are valid evidence classes and may not be censored.

## 4. Observed result

```text
reachable_colonized_patches  2
unique_recruited_species     2
isolated_no_colonization     true
sorting_observed_cells       2
adaptation_positive_cells    2

DRY  ADAPTATION_POSITIVE
gain 0.222347111576

WET  ADAPTATION_POSITIVE
gain 0.218384189961
```

These observed values did not replace the precommitted thresholds.

The first run after protocol precommit already produced the same evidence hash. No scientific repair was needed after seeing the hidden-world result.

## 5. Exact executable evidence

```text
protocol   372591ee3bee1c19538729259373e97fd9838461
challenge  4d353e774887c45f8a0487cb17b782e44d563951
test       82850fb850c35bcffb937707e4a8d29fb2827caa
runner     4385861b62ae10df07cb0f71295f50bf9a2097ee
```

The exact GDScript execution set contains 17/17 matched blobs. The acceptance test's transitive preload closure is 16 files; the accepted E2.8 fresh writer is the additional executed script.

## 6. Fresh verification

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Post-freeze evidence:

```text
parser/preload                    PASS
parser ERROR lines                0
parser log SHA-256                7e13b74061328cb38002de86c89b160a49fe4d3df65f763fc0d8c691893803c2

fresh E2.8 writer A/B             PASS / PASS
writer ERROR lines                0 / 0
writer logs                       byte-identical
writer log SHA-256                99de02e7f29f17eafa68b2fa73bb082d80baff356afc9b933ec60646cd11c275
artifacts                         byte-identical
artifact SHA-256                  b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1
artifact bytes                    10383

FINAL process A/B                 PASS / PASS
assertions                        68 / 68 PASS
FINAL ERROR lines                 0 / 0
FINAL logs                        byte-identical
FINAL log SHA-256                 4fdeaa581cd889c94f1bb5e1391466cad3deea308d631f4e3a3c056b532f69c2
```

## 7. Harness repair history

Initial runner freeze `65864ed...` passed the accepted E2.8 artifact path as a positional argument. The accepted E2.8 writer correctly rejected it because its contract is `--artifact-path=<path>`.

That failure occurred **before ecology execution** and was classified as Harness invocation only. No protocol, world, threshold, challenge implementation or acceptance test changed. Runner-only repair produced accepted freeze `376796ab...`.

## 8. Integrity and anti-shortcut gates

Acceptance proves/rejects:

- exact E2.8 transport/content/provenance/catalog identities;
- corrupted persisted input rejected before ecology;
- E2.8 semantic tamper suite remains fail-closed;
- no `Catalog.build` bypass;
- no direct accepted-catalog reconstruction preload;
- no bake-export preload;
- no direct `SpeciesCatalog` builder preload;
- every restored catalog entry receives a source-port migration event;
- colonization founders come only from actual recruited counts;
- restored catalog is not mutated;
- paired CONTROL/TREATMENT arms begin with identical colonization-derived founders;
- no global RNG consumption.

## 9. Claim boundary

Accepted claim:

> The persisted frozen research SpeciesCatalog and accepted EVO2 provenance can be restored in a fresh process and can causally colonize a precommitted unseen world, undergo ecological sorting and continued adaptation, with deterministic reproducible evidence and without rebake or biome species tables.

Not claimed:

```text
production ecology authority
production save authority
distributed durability
canonical biological taxonomy
world transaction semantics
P4 global/main acceptance
```

Canonical PowerShell runner exists but was not executed because `pwsh/powershell` is unavailable in the Linux verification carrier. Acceptance authority is `EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_EXECUTION`. Independent Reviewer/Verifier PASS is not claimed.

## 10. Decision

`ECO.EVO2` research route is complete.

Next architectural step is **bounded XFER0 contract design**, followed by EVO3 Planetary Ecology Compiler planning. This does not promote ECO into production runtime and does not alter the separate P4 governance line.
