# ECO.EVO7 VIS5.0 — Ubuntu Exact Verified Closed R1

Дата: 2026-09-03  
Статус: ACCEPTED / UBUNTU EXACT GREEN / CLOSED  
Branch: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1

## Exact executable subject

~~~text
HEAD:
d9491c847020e88f7ba26de3da9d5f8b7b8e42fd

TREE:
baadd745156d5f8d083976c9bc0db150b135f934
~~~

Fresh detached verification worktree:

~~~text
/home/yurig/dws-vis5-0-ubuntu-exact-r1
~~~

Host:

~~~text
Ubuntu 26.04 LTS (Resolute Raccoon)
kernel 7.0.0-30-generic
x86_64
Intel Core i5-10400 @ 2.90GHz
12 CPU
git 2.53.0
~~~

Canonical Godot:

~~~text
/home/yurig/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64

4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
~~~

## Exact result

~~~text
VIS4.8 Diversity:
PASS / 106 assertions

VIS4.9 predecessor:
PASS / 116 assertions

VIS5.0 focused:
PASS / 87 assertions

canonical runner:
RC=0

final marker:
ECO.EVO7 VIS5.0 Terrain / Ecosystem Composition Contract Audit candidate: PASS

HEAD unchanged:
YES

TREE unchanged:
YES

tracked worktree clean:
YES
~~~

Observed VIS4.9 diagnostics remained observational only:

~~~text
cache hit rate: 0.282
cost units: 12280
frame: 7.544 ms
~~~

No source contract mismatch was found and no test was modified during verification.

## Boundary claims proven

The focused gate proves:

~~~text
VIS4 PH5
= canonical evolved macro-plant presentation

ProceduralEarthWorld
= canonical terrain source

EarthPlacementSystem grass
= technical presentation donor only

procedural grass
!= ECO.EVO7 biological individual

procedural Earth trees
= forbidden in VIS5 mixed composition
  until explicit source binding exists

EVO4 B6
= legacy presentation donor only

PERF2.4 benchmark / thresholds
= unchanged

PERF2.CONV
= required final integrated performance gate
~~~

## GitHub Actions infrastructure note

Workflow run:

~~~text
33707460577
~~~

remains queued because the Ubuntu verification host has no registered GitHub Actions self-hosted runner.

~~~text
RUNNER_REGISTRATION_REQUIRED
labels required:
self-hosted
Linux
X64
~~~

This is an infrastructure scheduling condition, not a test failure.

The exact verification was instead executed manually in a fresh detached worktree against the same immutable HEAD/TREE with the canonical double-Godot. Therefore the missing GHA runner does not invalidate the independent exact evidence and is not a VIS5.0 required fix.

## Formal verdict

~~~text
VIS5.0
ACCEPTED
UBUNTU EXACT GREEN
CLOSED

required_fixes:
[]
~~~

Next checkpoint:

~~~text
VIS5.1 — Terrain Surface Frame Adapter
~~~
