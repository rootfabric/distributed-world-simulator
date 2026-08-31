# ECO.EVO7 VIS4.2 — Windows Verification RED R1

Дата: 2026-08-31  
Статус: VERIFIED RED / REPAIR REQUIRED

## Exact subject

~~~text
HEAD:
e74ffda554be177201542743f596b2c0bb272018

TREE:
a7090261af65b3f4a3313aa0c0275e18850f2435

Godot:
4.7.1.stable.double.custom_build.a13da4feb

worktree:
C:\distributed-world-simulator\eco-vis4-2-verify
~~~

Tracked tree после decisive run: clean.

113 untracked `.gd.uid` files были fresh Godot import artifacts и не добавлялись в Git.

## Verification result

Parent/regression chain GREEN:

~~~text
FFF2 56
FFF1 110
FFF0 112
P1B-S1 5834
PH2 107
P1A-S1 109
P1A-S2 235
P1C-S4 15
PH0 63

VIS4.0 176
LS3.4 45
LS3.6 114
VIS4.1 R2 598
VIS1 41
VIS2 69
VIS3 107
~~~

VIS4.2 focused:

~~~text
FAIL
1263 assertions
2 failures
~~~

Full runner:

~~~text
FAIL
RC=1
~~~

## VIS4.2-WIN-001

Both failures share one deterministic root cause:

~~~text
VIS4.2 initializes over public Workbench + Descriptor V2
VIS4.2 deterministic replay initializes
~~~

Runtime error:

~~~text
Invalid type in function 'set_descriptors'
in eco_evo7_vis4_2_diagnostic_morphology_overlay.gd.

Array argument type does not match expected Array[Dictionary].
~~~

R1 overlay boundary:

~~~gdscript
var descriptors: Array[Dictionary] = []

func set_descriptors(values: Array[Dictionary]) -> bool:
~~~

R1 viewer generation-zero/fail-closed paths call:

~~~gdscript
overlay.set_descriptors([])
~~~

A literal empty `[]` is an untyped Array in this call path.

Godot therefore aborts before the renderer can accept the semantically valid empty diagnostic set.

## Scope of failure

This is NOT:
- a Descriptor V2 source-binding failure;
- a morphology evidence failure;
- a biology regression;
- a deterministic morphology failure;
- a Windows wrapper artifact.

It is a typed API boundary failure on the empty generation-zero/fail-closed path.

Evidence from the same run proved 1261/1263 checks GREEN, including:

~~~text
61 source Descriptor V2 records
61 diagnostic descriptors
61 overlay-facing descriptors

exact descriptor/evidence/GrowthGraph seals
hereditary/development seeds
all controlled morphology visual mappings
neutral-color invariance
tampered Descriptor V2 rejection
non-empty deterministic ecology/evidence/Descriptor/render replay
~~~

## Repair decision

The renderer input boundary should accept generic `Array` and validate every element internally.

Reason:

~~~text
set_descriptors()
is a presentation input boundary

empty Array
is a valid diagnostic/fail-closed set

typed internal storage
remains Array[Dictionary]

malformed non-empty arrays
must still fail validation
~~~

Therefore R2 changes only the public input type:

~~~gdscript
func set_descriptors(values: Array) -> bool:
~~~

while keeping:

~~~gdscript
var descriptors: Array[Dictionary] = []
var ordered: Array[Dictionary] = []
~~~

and existing per-element validation.

No biology or morphology contract changes are required.

## Verdict

~~~text
VIS4.2 R1
WINDOWS VERIFICATION: FAIL

NOT ACCEPTED
~~~
