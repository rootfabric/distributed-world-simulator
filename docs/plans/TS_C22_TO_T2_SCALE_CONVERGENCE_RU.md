# TS/C22 → T2 Scale Convergence Roadmap

**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Control plane:** `PC0-2026-08-10-R1`  
**Owner of program state:** `main` / PC0  
**Purpose:** зафиксировать порядок перехода от доказанного TS0/C22 scale evidence к T2 real heterogeneous station scale так, чтобы параллельные ветки не потеряли handoff при дальнейшем развитии.

## 1. Текущее исходное состояние

На момент фиксации этого roadmap:

```text
TS0.0 deterministic fixtures                    DONE
TS0.1 10k graphical proof                       DONE / evidence obtained
TS0.2 100k hierarchical visual scale gate       DONE / manual functional evidence
TS0.3 local mutation / dirty rebuild             DONE / focused evidence
C22 production incremental convergence           SOURCE_ACCEPTED / PR #59 merge pending

T1A.7.3 Dirty / Selective Runtime Replication    focused PASS / full regression pending
T1A.7.4 Scale / Soak Lab                         next T runtime-scale stage
```

C22 convergence proves that an eligible unit-axis-grid local mutation can rebuild only dirty/neighbor sections, reuse unchanged content-addressed section artifacts and preserve equality with an independent full C22 compile without requiring a full snapshot scan on the fast path.

This document does **not** change canonical Construction truth, authority, persistence, network, spatial-domain or global work-budget ownership.

## 2. Immediate required transition — integrate accepted C22

The accepted convergence branch must not continue accumulating unrelated features.

Required sequence:

```text
feature/c22-incremental-local-rebuild
        ↓
merge accepted PR #59 into main
        ↓
post-merge CONTROL_PROJECT audit
        ↓
mark MAIN_INTEGRATED = true
        ↓
retire C22 convergence frontier
```

Do not start the next scale experiment inside the convergence branch.

The convergence branch is a production handoff branch, not a permanent TS development branch.

## 3. Next independent TS stage — TS0.4 1M Research Ceiling Probe

After C22 is integrated into `main`, create a fresh branch from current `main`, recommended name:

```text
feature/ts0-4-1m-research-ceiling
```

TS0.4 is a **research ceiling probe**, not an acceptance blocker for the already proven 100k scale path.

Primary profile:

```text
CUBE_1M_RESEARCH
100 × 100 × 100
1 000 000 canonical parts
```

The goal is not merely to wait for a one-million-part scene to finish building. The goal is to identify the dominant cost centers and determine the practical ceiling of the current architecture.

Required measurements:

```text
canonical fixture/materialization time
canonical memory footprint
section count
C22 topology build time
C22 exposed-surface extraction time
section artifact compilation time
FAR shell compilation time
C24 mesh materialization/upload time
artifact-cache entries/bytes
mesh-cache entries/GPU bytes
peak process memory where available
MID/FAR node / triangle / surface counts
local mutation dirty-section count
local mutation rebuild time
unchanged section reuse count
```

The 1M result must be classified as one of:

```text
PASSABLE
DEGRADED
CURRENT_CEILING_EXCEEDED
```

`CURRENT_CEILING_EXCEEDED` is valid research evidence and does not invalidate TS0.2/TS0.3 acceptance.

Do not reduce the 1M fixture merely to hide startup cost. If the ceiling is exceeded, preserve the evidence and identify which stage becomes the next optimization target.

## 4. Parallel development with T1A.7.4

TS0.4 and T1A.7.4 intentionally solve different scale problems and should normally proceed in parallel.

```text
T1A.7.4 Scale / Soak
--------------------
100 / 1,000 constructs
10,000 runtime subjects
interest / reconnect / selective replication
network/runtime fan-out
recovery behavior
long-running soak / bounded queues

TS0.4 1M Research
-----------------
1,000,000 canonical structural parts
C22/C24 representation cost
section/HLOD scaling
memory/cache pressure
mesh generation/materialization
local dirty rebuild scaling
```

Neither branch should take ownership of the other's foundation.

T must not redefine C22/HLOD identity or renderer ownership.
TS must not introduce network authority, interest identity, persistence, runtime replication or a global scheduler.

## 5. Synchronization gate before T2.0

T2.0 should start only after the project has enough evidence from **both** composition/runtime scale and representation/structural scale.

Minimum convergence condition:

```text
C22 incremental convergence MAIN_INTEGRATED
        +
T1 runtime recovery / interest / selective replication accepted through the relevant scale gate
        +
TS0 100k + dirty rebuild evidence preserved
        +
TS0.4 1M result recorded (PASSABLE / DEGRADED / CURRENT_CEILING_EXCEEDED)
        ↓
T2.0 Large Static Construct Scale may start
```

TS0.4 does not need to be `PASSABLE`; T2.0 may start with a documented 1M ceiling as long as the 100k production path and local incremental rebuild are accepted and the ceiling is understood.

If T1A.7.4 finds a blocker in shared Construction canonical/runtime contracts, resolve that blocker before T2.0. If it only finds network/interest tuning debt, T2.0 may still start provided ownership boundaries remain intact and PC0 marks the dependency non-blocking.

## 6. T2.0 target — real heterogeneous station scale

T2.0 must not repeat the synthetic cube benchmark as its primary proof.

It must reuse:

```text
C21 large-scale acceptance
C22 compiled proxy / HLOD
C24 ArrayMesh backend
production incremental local rebuild
TS0 10k / 100k representation evidence
TS0.4 ceiling data
T1 runtime/recovery/interest/replication evidence
```

And add the properties absent from TS0:

```text
heterogeneous semantic sections
rooms and openings
structural and non-structural parts
interactive fixtures
containers / equipment where useful
utilities where useful
real visual classes/material presentation
non-uniform local mutation patterns
large real base/station topology
```

Recommended T2.0 scale profiles:

```text
S0  10,000+ semantic parts
S1  100,000-class semantic parts   PRIMARY PRODUCTION GATE
S2  1,000,000-class semantic parts RESEARCH / CEILING ONLY
```

## 7. Critical T2.0 proof using the new C22 path

A key T2.0 scenario must directly exercise the production result of TS0.3/C22 convergence on a real heterogeneous construct.

Example:

```text
100k-class station
        ↓
local structural modification
remove/replace a room wall, corner module or damaged section
        ↓
canonical revision changes
        ↓
only affected C22 sections + bounded neighbor context rebuild
        ↓
unchanged station sections reuse existing artifacts
        ↓
FAR/MID representation remains complete
        ↓
near state matches canonical Construction truth
```

Acceptance must prove that local modification does **not** cause a full station representation rebuild when the fast-path eligibility conditions are satisfied.

The synthetic TS0 mutation is evidence; T2.0 is the real-production composition proof.

## 8. Required telemetry for T2.0

At minimum preserve before/after values for:

```text
canonical part count
canonical revision/checksum
runtime subject count
section count
rebuild section count
reused section count
dirty HLOD/cluster count
active presentation nodes
triangles / surfaces / draw-call proxy
C22 rebuild time
C24 materialization time
artifact cache pressure
mesh/GPU cache pressure
observer representation mode
network-relevant construct/runtime subject counts where composed
```

Do not turn hardware-specific FPS into the first universal acceptance contract. Structural invariants and bounded growth come first; frame timings remain recorded evidence until enough hardware data exists.

## 9. 1M findings and possible follow-up branches

TS0.4 should produce a decision, not just metrics.

If the primary bottleneck is canonical fixture/materialization:

```text
candidate follow-up: canonical snapshot/build streaming or compact structural source representation
```

If it is C22 topology/surface extraction:

```text
candidate follow-up: hierarchical/spatial incremental topology construction
```

If it is section/HLOD compile:

```text
candidate follow-up: async/batched hierarchical artifact build
```

If it is C24 upload/cache pressure:

```text
candidate follow-up: bounded streaming mesh residency / upload budgeting
```

These are candidate implementation directions only. They must not silently create a private global World Work/Budget scheduler. Any global scheduling/budget foundation remains a separately owned P0/P1 concern.

## 10. PC0 activation rules

When the following transitions happen, the active maintainer should explicitly update the main-owned PC0 registry rather than relying on this document alone.

```text
PR #59 merged
    -> TS C22 convergence MAIN_INTEGRATED
    -> convergence frontier retired

TS0.4 branch created
    -> register TS0.4 as research/evidence frontier
    -> declare C22/C24 watched dependencies

T1A.7.4 accepted
    -> record runtime-scale evidence available for T2 convergence

TS0.4 result recorded
    -> record PASSABLE / DEGRADED / CURRENT_CEILING_EXCEEDED

both evidence lines ready
    -> register T2.0 Large Static Construct Scale as next Construction scale frontier
```

A branch may continue independent work while another branch is YELLOW if PC0 reports no runtime/contract ownership overlap and its required dependency is already accepted.

A branch must stop before crossing into a shared production foundation if PC0 reports watched-dependency drift, ownership conflict or runtime/contract overlap.

## 11. Compact execution roadmap

```text
NOW
│
├─ merge C22 PR #59
│   └─ post-merge PC0 → MAIN_INTEGRATED
│
├─ T branch
│   T1A.7.3 full regression
│       ↓
│   T1A.7.4 Scale / Soak
│
└─ TS branch
    TS0.4 1M Research Ceiling
        ↓
        record bottleneck + ceiling classification

T1 runtime-scale evidence
            +
TS structural/representation-scale evidence
            ↓
PC0 convergence review
            ↓
T2.0 Large Static Construct Scale
            ↓
real heterogeneous 100k-class station
            ↓
local mutation uses production incremental C22
            ↓
T2.1 Hierarchical Construct Frames
            ↓
T2.2 Moving / Orbital Construct
            ↓
T2.3 Docking / Undocking
            ↓
T2.4 Distributed Station Authority
            ↓
T2.5 Dormancy / Promotion / Budgets
            ↓
T2.6 Station Scale Acceptance
```

## 12. Non-negotiable architecture invariants

```text
canonical construct != HLOD artifact
part identity != mesh identity
section id != WorldAddress
section id != AuthorityRegionId
section id != InterestRegionId
observer LOD != canonical state
runtime replication target != construct identity
TS local build budget != global World Work/Budget Fabric
network interest != renderer visibility identity
```

The purpose of the convergence is to compose accepted foundations, not to merge their ownership models.

## 13. Definition of successful handoff

This roadmap is considered successfully consumed when:

1. accepted C22 incremental rebuild is integrated in `main`;
2. TS0.4 has a recorded 1M ceiling classification and bottleneck report;
3. T runtime-scale/soak evidence is accepted or explicitly classified as non-blocking debt;
4. PC0 registers T2.0 as the active scale frontier;
5. T2.0 proves the same incremental representation path on a real heterogeneous 100k-class construct.

After that, this document remains historical program guidance and T2's own roadmap becomes the active execution authority.
