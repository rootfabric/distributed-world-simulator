extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P6 Generic Morphology Realizer tests.
# Runner: Godot headless --script; prints checks/failed counts and PASS/FAIL.
#
# Coverage matrix (work order P6):
#   a) COVERAGE: every canonical program (body_program_fixtures_v1.make(0..5),
#      observatory_protocol_v1.ancestor(), plus an all-roles program) grown
#      through the canonical development interpreter produces a non-empty
#      descriptor and >= 1 primitive per module and per parent->child edge —
#      NO module renders as zero primitives.
#   b) UNKNOWN-FORM FALLBACK: the canonical body_graph validator forbids
#      non-standard roles (verified here: MODULE_ID_ROLE), so the unknown-role
#      fallback is covered at descriptor level via a mock descriptor with an
#      out-of-vocabulary role_class -> real primitives, no errors.
#   c) VISUAL INVARIANT (§14/§27): 16 controller ticks with presentation ON
#      (descriptor + realizer called after EVERY tick, via debug_state) vs OFF
#      produce an identical canonical_state_hash; LOD HIGH vs LOW identical;
#      different palette seeds identical.
#   d) Descriptor determinism: same state -> same descriptor digest; LOD and
#      palette never change the descriptor or primitive counts.
#   e) P3/P2-P5 regressions run as separate scripts (see report).

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const E = preload("res://scripts/research/ecology/v2/environment_fixture_v1.gd")
const S = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")
const D = preload("res://scripts/research/ecology/v2/development_interpreter_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Descriptor = preload("res://scripts/ecology/workbench/morphology_descriptor_v1.gd")
const Realizer = preload("res://scripts/ecology/workbench/generic_morphology_realizer_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P6_FAIL " + message)

# --- canonical growth helper (development interpreter, synthetic grants) ----

func _grow(genome: Dictionary, ticks: int) -> Dictionary:
	var state := S.create(genome, "test/growth", B.stock(100000000))
	if state.is_empty():
		return {}
	var environment := E.create()
	var grant := B.stock(10000000)
	for _tick in ticks:
		var begun: Dictionary = D.begin_tick(state, genome, environment, grant, state.grant_seq + 1)
		if not begun.success:
			return {}
		state = begun.state
		for _slice in 64:
			var advanced: Dictionary = D.advance(state, genome, 4096)
			if not advanced.success:
				return {}
			state = advanced.state
			if String(advanced.status) == "TICK_COMPLETE":
				break
	return state

func _all_roles_genome() -> Dictionary:
	var first := [
		P.action("extend", "support", [0, 60, 0], 3),
		P.action("extend", "transport", [0, 50, 0], 2),
		P.action("differentiate", "collector", [0, 40, 0], 1, 400),
		P.action("differentiate", "absorber", [0, -50, 0], 1, 0, 40),
		P.action("differentiate", "storage", [0, 20, 0], 2),
		P.action("retire"),
	]
	var second := [
		P.action("differentiate", "sensor", [0, 20, 0], 1),
		P.action("differentiate", "defense", [0, 20, 0], 1),
		P.action("differentiate", "reproductive", [0, 30, 0], 2),
		P.action("attach", "attachment", [0, 0, 0], 1, 0, 20, "ground"),
		P.action("retire"),
	]
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 32, "max_depth": 2,
		"rules": [P.rule("start", first, "second"), P.rule("second", second)]}, "all-roles")

func _coverage_case(label: String, genome: Dictionary, ticks: int) -> void:
	var state := _grow(genome, ticks)
	_check(not state.is_empty(), "%s: canonical growth produced a state" % label)
	if state.is_empty():
		return
	_check(B.validate(state.modules).is_empty(), "%s: grown body is canonical-valid" % label)
	_check(state.modules.size() > 1, "%s: growth created modules (n=%d)" % [label, state.modules.size()])
	var descriptor := Descriptor.compile(state.modules, "test/" + label, [500, 0, 500])
	_check(not descriptor.is_empty(), "%s: descriptor non-empty" % label)
	_check(descriptor.modules.size() == state.modules.size(), "%s: descriptor covers every module" % label)
	_check(not String(descriptor.topology_signature).is_empty(), "%s: canonical topology_signature present" % label)
	var manifest := Realizer.realize(descriptor, {"lod": "HIGH", "palette_seed": 7})
	_check(not manifest.is_empty() and int(manifest.primitive_count) >= 1, "%s: realizer produced primitives" % label)
	# >= 1 primitive per module.
	var per_module := {}
	# >= 1 primitive per parent->child edge.
	var per_edge := {}
	var edges := 0
	for primitive in manifest.primitives:
		per_module[String(primitive.module_id)] = int(per_module.get(String(primitive.module_id), 0)) + 1
		if String(primitive.edge) != "":
			per_edge[String(primitive.edge)] = int(per_edge.get(String(primitive.edge), 0)) + 1
	var uncovered := 0
	for module in state.modules:
		if int(per_module.get(String(module.id), 0)) < 1:
			uncovered += 1
		if String(module.parent) != "":
			edges += 1
			if int(per_edge.get("%s->%s" % [String(module.parent), String(module.id)], 0)) < 1:
				uncovered += 1
	_check(uncovered == 0, "%s: every module and every edge has >=1 primitive (modules=%d edges=%d)" % [label, state.modules.size(), edges])

# --- a) COVERAGE --------------------------------------------------------------

func _test_coverage() -> void:
	for index in Fixtures.NAMES.size():
		var genome: Dictionary = Fixtures.make(index)
		_check(not genome.is_empty(), "fixture %d genome non-empty" % index)
		if not genome.is_empty():
			_coverage_case("fixture%d" % index, genome, 12)
	_coverage_case("ancestor", Protocol.ancestor(), 12)
	_coverage_case("all_roles", _all_roles_genome(), 12)

# --- b) UNKNOWN-FORM FALLBACK ---------------------------------------------------

func _test_unknown_form() -> void:
	# The canonical validator forbids non-standard roles: verify and record it.
	var modules: Array = [B.root()]
	var mutant := B.root().duplicate(true)
	mutant.id = "m000001"
	mutant.parent = "m000000"
	mutant.role = "unknown_organ"
	mutant.radius_mm = 1
	mutant.start_mm = [0, 0, 0]
	mutant.end_mm = [0, 50, 0]
	mutant.cost = B.cost(mutant)
	modules.append(mutant)
	_check(String(B.validate(modules)) == "MODULE_ID_ROLE",
		"canonical validator rejects non-standard roles (MODULE_ID_ROLE) — unknown-role fallback covered at descriptor level")

	# Descriptor-level mock with an out-of-vocabulary role_class: the
	# universal realizer must still produce real primitives, no errors.
	var mock := {
		"schema": Descriptor.SCHEMA,
		"entity_id": "test/unknown",
		"origin_mm": [0, 0, 0],
		"modules": [
			{
				"id": "m000000", "parent": "", "role": "attachment", "role_class": "attachment",
				"position_mm": [0, 0, 0], "start_mm": [0, 0, 0], "end_mm": [0, 0, 0],
				"size_mm": [2, 2, 2], "radius_mm": 1, "area_mm2": 0, "reach_mm": 0,
			},
			{
				"id": "m000001", "parent": "m000000", "role": "unimaginable_fluid_limb", "role_class": "unknown",
				"position_mm": [0, 25, 0], "start_mm": [0, 0, 0], "end_mm": [0, 50, 0],
				"size_mm": [2, 52, 2], "radius_mm": 1, "area_mm2": 0, "reach_mm": 0,
			},
		],
		"topology_signature": "",
		"bounds_mm": {"min_mm": [-1, -1, -1], "max_mm": [1, 51, 1]},
	}
	var manifest := Realizer.realize(mock, {"lod": "HIGH", "palette_seed": 3})
	_check(not manifest.is_empty(), "unknown-role descriptor still realizes")
	var module_primitives := {}
	var unknown_primitive_count := 0
	for primitive in manifest.primitives:
		module_primitives[String(primitive.module_id)] = true
		if String(primitive.role_class) == "unknown":
			unknown_primitive_count += 1
			_check(primitive.color == Realizer.NEUTRAL_COLOR, "unknown role_class gets the neutral colour")
	_check(int(manifest.primitive_count) >= 2, "unknown-role descriptor yields >= 1 primitive per module")
	_check(module_primitives.has("m000001") and unknown_primitive_count >= 1,
		"unknown-form module renders real primitives (universal fallback)")

	# All canonical roles realize without errors (covered in (a) too).
	var all_roles := _grow(_all_roles_genome(), 12)
	if not all_roles.is_empty():
		var descriptor := Descriptor.compile(all_roles.modules, "test/allroles", [0, 0, 0])
		var realized := Realizer.realize(descriptor, {"lod": "MEDIUM"})
		_check(int(realized.primitive_count) >= all_roles.modules.size(), "all-canonical-roles body realizes fully")

# --- c) VISUAL INVARIANT + d) determinism ---------------------------------------

func _manifest_16() -> Dictionary:
	var founder := G.create({
		"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 2,
		"rules": [P.rule("r1", [
			P.action("extend", "support", [0, 100, 0], 10),
			P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
		])],
	}, "founder-a")
	return {
		"schema": "dws.ecology.workbench.experiment-manifest.v1",
		"experiment_id": "eco-polygon/exp-p6-visual-invariant",
		"seed": 777,
		"horizon_ticks": 16,
		"founders": [{"founder_id": "founder/a", "biological_hash": null, "genome": founder}],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [{"id": "zone/wet", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": 1000, "organic_mg": 0}],
		},
		"placement": {"entries": [{"founder_ref": "founder/a", "zone_id": "zone/wet", "position_mm": [500, 0, 500]}]},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
	}

## Presentation ON: descriptor + realizer run after EVERY tick, reading only
## debug_state (a deep copy) — presentation must never touch canonical state.
func _run_with_presentation(manifest: Dictionary, lod: String, palette_seed: int) -> String:
	var ctl := Controller.new()
	var init_result: Dictionary = ctl.initialize(manifest)
	if not bool(init_result.get("success", false)):
		return ""
	var primitives_total := 0
	for _tick in 16:
		var step: Dictionary = ctl.step()
		if not bool(step.get("success", false)):
			return ""
		for entry in ctl.debug_state().population:
			var state: Dictionary = entry.state
			var descriptor := Descriptor.compile(state.development.modules, String(state.individual_id), state.position_mm)
			if descriptor.is_empty():
				continue
			var realized: Dictionary = Realizer.realize(descriptor, {"lod": lod, "palette_seed": palette_seed})
			primitives_total += int(realized.primitive_count)
	_check(primitives_total > 0, "presentation path produced primitives over 16 ticks (lod=%s)" % lod)
	return String(ctl.get_snapshot().canonical_state_hash)

func _test_visual_invariant() -> void:
	var manifest := _manifest_16()
	# Baseline: presentation OFF (no descriptor/realizer calls at all).
	var ctl := Controller.new()
	var init_result: Dictionary = ctl.initialize(manifest)
	_check(bool(init_result.get("success", false)), "VI controller initialize succeeds")
	var run_result: Dictionary = ctl.run(16)
	_check(bool(run_result.get("success", false)), "VI baseline run(16) succeeds")
	var hash_off := String(ctl.get_snapshot().canonical_state_hash)
	_check(not hash_off.is_empty(), "VI baseline hash non-empty")
	var hash_on := _run_with_presentation(manifest, "HIGH", 7)
	_check(not hash_on.is_empty(), "VI presentation-ON run completes")
	_check(hash_on == hash_off, "VI presentation ON vs OFF: canonical_state_hash identical (§14/§27)")
	var hash_low := _run_with_presentation(manifest, "LOW", 7)
	_check(hash_low == hash_off, "VI LOD LOW: canonical_state_hash identical")
	var hash_palette := _run_with_presentation(manifest, "HIGH", 424242)
	_check(hash_palette == hash_off, "VI different palette seed: canonical_state_hash identical")

func _test_descriptor_determinism() -> void:
	var state := _grow(Fixtures.make(0), 12)
	_check(not state.is_empty(), "determinism growth produced a state")
	if state.is_empty():
		return
	var d1 := Descriptor.compile(state.modules, "test/det", [500, 0, 500])
	var d2 := Descriptor.compile(state.modules, "test/det", [500, 0, 500])
	_check(String(d1.descriptor_digest) == String(d2.descriptor_digest), "same state -> same descriptor digest")
	# LOD / palette live ONLY in the visual profile: the descriptor is
	# unaffected, and primitive counts are identical across LODs.
	var high: Dictionary = Realizer.realize(d1, {"lod": "HIGH", "palette_seed": 1})
	var low: Dictionary = Realizer.realize(d1, {"lod": "LOW", "palette_seed": 1})
	var other_palette: Dictionary = Realizer.realize(d1, {"lod": "HIGH", "palette_seed": 999999})
	_check(int(high.primitive_count) == int(low.primitive_count), "primitive count identical at LOD HIGH and LOW")
	_check(int(high.primitive_count) == int(other_palette.primitive_count), "primitive count independent of palette seed")
	var same_coverage := true
	var low_by_module := {}
	for primitive in low.primitives:
		low_by_module[String(primitive.module_id)] = int(low_by_module.get(String(primitive.module_id), 0)) + 1
	for module in state.modules:
		if int(low_by_module.get(String(module.id), 0)) < 1:
			same_coverage = false
	_check(same_coverage, "LOD never drops module coverage")
	# Palette changes colours only.
	var colors_differ := false
	for i in high.primitives.size():
		if Array(high.primitives[i].color) != Array(other_palette.primitives[i].color):
			colors_differ = true
			break
	_check(colors_differ, "palette seed changes colours (presentation-only differentiation)")
	# Descriptor purity: compile never mutates the input modules.
	var modules_before: Array = state.modules.duplicate(true)
	Descriptor.compile(state.modules, "test/det", [0, 0, 0])
	_check(state.modules == modules_before, "descriptor compile does not mutate canonical modules")

func _run() -> void:
	_test_coverage()
	_test_unknown_form()
	_test_visual_invariant()
	_test_descriptor_determinism()
	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_5_GENERIC_REALIZER_P6 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_GENERIC_REALIZER_P6 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P6_FAILURE " + failure)
		quit(1)
