# ECO.EVO7 VIS4.2 R2 — Empty Descriptor Boundary Repair

Дата: 2026-08-31  
Статус: ACCEPTED REPAIR / WINDOWS VERIFIED / CLOSED

Predecessor RED:

~~~text
VIS4.2 R1 exact subject:
e74ffda554be177201542743f596b2c0bb272018
TREE a7090261af65b3f4a3313aa0c0275e18850f2435
~~~

R1 finding:

~~~text
VIS4.2-WIN-001
typed Array[Dictionary] API rejected literal empty []
on generation-zero/fail-closed viewer paths
~~~

## Exact R2 runnable boundary

~~~text
HEAD:
3ecee0f0fe491a6f76145eb8f2da133c820ae793

TREE:
762806c32b43a1cc0740e7b5ab78be8e1cb108bd
~~~

## Repair

File:

~~~text
scripts/labs/ecology/
eco_evo7_vis4_2_diagnostic_morphology_overlay.gd
~~~

Changed:

~~~gdscript
func set_descriptors(values: Array[Dictionary]) -> bool:
~~~

to:

~~~gdscript
func set_descriptors(values: Array) -> bool:
~~~

Internal storage remains strictly typed:

~~~gdscript
var descriptors: Array[Dictionary] = []
var ordered: Array[Dictionary] = []
~~~

Each non-empty item is still validated as:
- Dictionary;
- valid cell index;
- non-empty record_id;
- 64-byte silhouette hash.

Therefore the repair widens only the external empty/fail-closed input boundary. It does not weaken accepted descriptor storage.

## Acceptance hardening

Focused acceptance now explicitly proves:

~~~text
overlay.set_descriptors([])
-> PASS

overlay.set_descriptors([malformed descriptor])
-> REJECT
~~~

This prevents both regressions:

1. typed empty-array runtime abort;
2. accidental acceptance of arbitrary generic array contents.

## Scope

Unchanged:
- VIS4.1 Descriptor V2 schema;
- morphology evidence;
- LS3.4 / LS3.6;
- biology;
- ecology state_hash;
- GrowthGraph source identity;
- diagnostic morphology mappings;
- neutral-color semantics;
- deterministic replay semantics;
- PLAY0 boundary.

No new authority.

## R2 runner identity

Windows/Linux runner output and Windows workflow are retargeted to VIS4.2 R2.

Expected decisive final line:

~~~text
ECO.EVO7 VIS4.2 R2 Honest Diagnostic Morphology candidate: PASS
~~~

## Exit criteria

R2 can close only after fresh exact Windows run on:

~~~text
3ecee0f0fe491a6f76145eb8f2da133c820ae793
~~~

proves:

~~~text
exact HEAD/TREE
exact double Godot

VIS4.1 R2 predecessor chain GREEN
VIS3 GREEN
VIS4.2 focused GREEN
full runner RC=0

generation-zero initialization GREEN
deterministic replay initialization GREEN

61/61/61 source/diagnostic/overlay descriptors GREEN
controlled morphology gates GREEN
tamper rejection GREEN
non-empty deterministic replay GREEN

tracked tree clean
~~~

## Next

VIS4.3 runtime remains blocked until this R2 exact Windows gate is GREEN.


## Closure update

Exact Windows re-verification on R2 passed:

~~~text
HEAD: 3ecee0f0fe491a6f76145eb8f2da133c820ae793
TREE: 762806c32b43a1cc0740e7b5ab78be8e1cb108bd

VIS4.2 focused: PASS (1265)
full runner: PASS
RC=0
~~~

Formal status:

~~~text
VIS4.2 R2
ACCEPTED
WINDOWS VERIFIED
CLOSED
~~~

Final closure checkpoint:

~~~text
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_2_WINDOWS_VERIFIED_CLOSED_R2_RU.md
~~~
