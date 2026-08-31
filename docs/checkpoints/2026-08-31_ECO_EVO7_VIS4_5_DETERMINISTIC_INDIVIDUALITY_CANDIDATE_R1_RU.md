# ECO.EVO7 VIS4.5 — Deterministic Individuality R1 Candidate

Дата: 2026-08-31

Статус:

~~~text
VIS4.5 IMPLEMENTED CANDIDATE
EXACT UBUNTU DOUBLE-GODOT VERIFICATION REQUIRED
NOT CLOSED
~~~

## Frozen executable subject

~~~text
HEAD:
1389c897d5a17ab0986e0c1d65602d705479e859

TREE:
27f61dc56f87b893f8370b7523841e2ee806f6b1
~~~

Predecessor:

~~~text
VIS4.4 R2 CLOSED
canonical executable:
6ec628ad125114c1588f543d877ec83b1dfc81ed
~~~

## Implementation

VIS4.5 does not introduce a second stochastic tree generator.

The accepted PH5 GrowthGraph already consumes `development_individual_seed`
for branch selection, branch azimuth, bounded angle jitter and bounded branch
length jitter. RenderDescription deterministically derives foliage placement
from the resulting GrowthGraph identity.

VIS4.5 adds the missing explicit PLAY0 presentation contract:

~~~text
VIS4.1 Descriptor V2
  development_individual_seed
  descriptor_hash
  growth_graph_hash
        |
        v
VIS4.5 DeterministicIndividuality
        |
        +-> orientation_yaw_deg
        +-> individuality_hash
        |
        v
VIS4.4/5 PH5 live renderer
        |
        v
surface-up basis x deterministic local-yaw
~~~

The local yaw is presentation-only. It rotates the already-accepted PH5 object
as a whole and cannot alter GrowthGraph, RenderDescription, PH5 materialization,
ecology fitness or any source hash.

## New durable surfaces

~~~text
scripts/labs/ecology/eco_evo7_vis4_5_deterministic_individuality.gd
tests/ecology/eco_evo7_vis4_5_deterministic_individuality_acceptance.gd
RUN_ECO_EVO7_VIS4_5_TESTS.sh
RUN_ECO_EVO7_VIS4_5_TESTS.ps1
~~~

Existing presentation surfaces extended:

~~~text
scripts/labs/ecology/eco_evo7_vis4_4_play0_ph5_renderer.gd
scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd
~~~

## Invariants

~~~text
same development_individual_seed
+ same source descriptor / GrowthGraph
=> same individuality hash and local yaw

different seed
=> accepted GrowthGraph/foliage stochastic realization may differ
=> stable presentation orientation differs

individuality
!= ecology trait
!= fitness advantage
!= mutation axis
!= canonical physical position
~~~

No TREE/BUSH/GRASS taxonomy is introduced.

## Focused acceptance

The VIS4.5 acceptance proves:

~~~text
controlled same-seed GrowthGraph exact replay
controlled different-seed branch geometry divergence
accepted branch azimuth seed binding
accepted angle jitter remains within 0.92..1.08
different-seed foliage placement divergence

all live PH5 records bind exact development_individual_seed
all live records have sealed individuality_hash
live population has multiple deterministic orientations

PLAY0 applies:
surface-up basis x deterministic local-yaw

lineage/neutral color switch:
individuality identity unchanged
geometry identity unchanged

render-origin shift:
individuality identity unchanged
visual orientation unchanged

LOD switch:
individuality identity unchanged
seed-derived yaw unchanged

ecology state hash:
unchanged by VIS4.5 presentation operations
~~~

Runtime source guards require no process RNG, no direct GrowthGraph rebuild in
VIS4.5, no reproduction/mutation/dispersal authority and no persistence/network
authority.

## Canonical runner

~~~text
RUN_ECO_EVO7_VIS4_5_TESTS.sh
~~~

Execution chain:

~~~text
VIS4.4 canonical predecessor runner
  -> VIS4.3 / PH5 / PLAY0 / VIS4.4 regressions
  -> VIS4.5 focused deterministic individuality acceptance
~~~

Required final marker:

~~~text
ECO.EVO7 VIS4.5 Deterministic Individuality candidate: PASS
~~~

One exact Ubuntu double-Godot GREEN on the frozen subject is sufficient for
closure; a separate Windows gate is not required.
