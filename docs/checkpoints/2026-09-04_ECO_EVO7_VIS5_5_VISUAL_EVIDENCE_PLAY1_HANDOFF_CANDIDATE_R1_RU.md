# ECO.EVO7 VIS5.5 — Visual Evidence / Integrated PLAY1 Handoff Candidate R1

Дата: 2026-09-04  
Статус: IMPLEMENTED / FOCUSED GREEN / GRAPHICAL CAPTURE GREEN / EXACT FRESH-SOURCE PENDING  
Branch: `feature/eco-evo7-vis5-terrain-ecosystem-composition-r1`

## Реализованная граница

VIS5.5 является presentation-only надстройкой над уже закрытыми VIS5.3 и VIS5.4:

~~~text
VIS5.3 real mixed composition
+
VIS5.4 LOD / streaming lifecycle
        |
        v
VIS5.5 operator evidence lab
        |
        +-- six deterministic evidence views
        +-- truth / authority HUD
        +-- real GL Compatibility PNG capture
        +-- SHA-256 evidence manifest
        +-- machine-readable PLAY1 handoff package
~~~

VIS5.5 не создаёт новую ecology, terrain, network, persistence или PERF2 authority.

## Truth labels

Operator HUD и handoff contract фиксируют:

~~~text
terrain       = ProceduralEarthWorld
macro plants  = CANONICAL_ECO_VIS4_PH5
ground cover  = NONCANONICAL_SCENERY
rocks         = TERRAIN_SCENERY
~~~

Legacy ProceduralEarth placement / trees остаются suppressed.

## Evidence views

Фиксирован capture plan:

~~~text
01 NEAR_OVERVIEW          -> NEAR
02 NEAR_DETAIL            -> NEAR
03 MID_CONTEXT            -> MID
04 FAR_CONTEXT            -> FAR
05 CULLED_CONTEXT         -> CULLED
06 RETURN_AFTER_STREAMING -> NEAR
~~~

Каждый capture требует operator truth overlay.

## Lifecycle handoff evidence

Перед lifecycle rebuild VIS5.5 явно нормализует presentation в NEAR, чтобы не переносить stale CULLED visibility diagnostic в VIS5.3 summary.

Далее выполняется:

~~~text
NEAR
 -> render origin +1500 m
 -> exact source identity check
 -> restore original render origin
 -> exact composition hash restoration
 -> real ProceduralEarth remote-region rebuild beyond local recenter threshold
 -> real return-region rebuild
 -> same-seed scenery rebuild
 -> RETURN_AFTER_STREAMING / NEAR
~~~

Обязательные invariants:

~~~text
source_ecology_hash unchanged
Descriptor V2 adapter hash unchanged
PH5 bridge hash unchanged
composition hash restored for same seed/region
remote legacy placement suppressed
return legacy placement suppressed
no ecology identity drift
~~~

## Operator HUD

HUD показывает:

~~~text
current evidence view
current VIS5.4 mode
PH5 visible / total
 grass visible / total
rocks visible / total
truth labels
terrain relief / slope
procedural-tree suppression
composition cost / draw proxies
recenter / earth rebuild / roundtrip counters
VIS5 visual handoff state
PLAY1 PERFORMANCE NOT ACCEPTED
PERF2.CONV REQUIRED
~~~

Workload counters явно маркируются как `PROXIES ONLY`; frame diagnostics остаются observational-only.

## PLAY1 handoff boundary

Machine-readable contract:

~~~text
config/ecology/eco-evo7-vis5-5-play1-handoff.v1.json
~~~

VIS5.5 GREEN означает только:

~~~text
VIS5 visual composition line READY_FOR_PLAY1_HANDOFF
~~~

И не означает:

~~~text
PLAY1 performance accepted
~~~

Финальный join остаётся:

~~~text
VIS5.5 GREEN
+
PERF2.CONV GREEN
        |
        v
PLAY1 integrated acceptance
~~~

## Focused evidence

Canonical attached Godot:

~~~text
4.7.1.stable.double.custom_build.a13da4feb
~~~

Focused acceptance:

~~~text
ECO.EVO7 VIS5.5 Visual Evidence / Integrated PLAY1 Handoff:
PASS (114 assertions)
~~~

Acceptance использует реальный VIS5.3 / VIS5.4 / ProceduralEarthWorld, а не fake terrain/streaming world.

## Graphical development evidence

Headless capture намеренно отвергнут: Godot headless использует dummy renderer и не даёт валидный viewport screenshot.

Принят настоящий graphical path:

~~~text
X11 / Xvfb
+
OpenGL Compatibility
+
1280x720 viewport
+
real viewport texture capture
~~~

Development capture:

~~~text
capture_count = 6
capture_bundle_hash = cff5f4fadd14f056075f39697458ffcd4e427a7473db7f27c922db411218cd98
manifest_sha256 = 5ab781aff2c1ca1ebecc5d5762e8d9c8f98aab9c441bcced6872732299f5278b
~~~

Это development evidence; exact closure требует повторный capture из fresh immutable source export.

## Durable surfaces

~~~text
scripts/labs/ecology/
  eco_evo7_vis5_5_visual_evidence_play1_handoff.gd

scenes/labs/ecology/
  eco_evo7_vis5_5_visual_evidence_play1_handoff.tscn

tests/ecology/
  eco_evo7_vis5_5_visual_evidence_play1_handoff_acceptance.gd
  eco_evo7_vis5_5_capture_evidence.gd

config/ecology/
  eco-evo7-vis5-5-play1-handoff.v1.json

RUN_ECO_EVO7_VIS5_5_TESTS.sh
RUN_ECO_EVO7_VIS5_5_TESTS.ps1
CAPTURE_ECO_EVO7_VIS5_5_EVIDENCE.sh
CAPTURE_ECO_EVO7_VIS5_5_EVIDENCE.ps1
OPEN_ECO_EVO7_VIS5_5_EVIDENCE_LAB.sh
OPEN_ECO_EVO7_VIS5_5_EVIDENCE_LAB.ps1

.github/workflows/
  evo7-vis5-5-visual-evidence-play1-handoff.yml
~~~

## Exact closure requirement

Перед CLOSED:

~~~text
fresh immutable source export
+
RUN_ECO_EVO7_VIS5_5_TESTS.sh RC=0
+
canonical Linux double-Godot
+
VIS5.0 .. VIS5.5 all GREEN
+
real GL Compatibility capture
+
6 PNG + manifest
+
source/runtime hashes recorded
~~~

После этого VIS5.5 можно закрыть как visual line ready for PLAY1 handoff, сохраняя PERF2.CONV как обязательный внешний final join gate.
