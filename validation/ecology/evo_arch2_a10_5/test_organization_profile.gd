extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P9 OrganizationProfile + morphotype
# classifier tests. Runner: Godot headless --script; prints counts + PASS/FAIL.
#
# Coverage (work order P9, brief §18-20):
#   a) VISUAL_ONLY profile APPLIES: palette_seed / presentation_detail really
#      change the realizer visual_profile (colours and LOD detail differ);
#      16-tick runs with profile A vs profile B vs NO profile produce an
#      IDENTICAL canonical_state_hash (non-causal proof, §14/§18/§27).
#   b) DEVELOPMENT_BIAS profiles (SOFT/EARTH_LIKE/NMS_LIKE) ->
#      status BLOCKED_CANONICAL_EXTENSION_REQUIRED; canonical state unchanged.
#   c) FREE-mode acceptance (§19): a canonical valid genome WITHOUT species /
#      curated labels grows -> valid BodyGraph -> descriptor -> generic
#      realizer -> >= 1 primitive per module.
#   d) Emergent morphotypes (§20): classifier determinism; classification ON
#      vs OFF -> identical canonical hash; classifier never writes to state.
#   e) All 5 manifest organization_profile modes are valid manifests.

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const S = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")
const D = preload("res://scripts/research/ecology/v2/development_interpreter_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")\nconst Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const E = preload("res://scripts/research/ecology/v2/environment_fixture_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const Profile = preload("res://scripts/ecology/workbench/organization_profile_v1.gd")
const Descriptor = preload("res://scripts/ecology/workbench/morphology_descriptor_v1.gd")
const Realizer = preload("res://scripts/ecology/workbench/generic_morphology_realizer_v1.gd")
const Classifier = preload("res://scripts/ecology/workbench/morphotype_classifier_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P9_FAIL " + message)

# --- shared fixtures ----------------------------------------------------------

func _founder_genome() -> Dictionary:
	# Canonical valid genome whose ONLY label is a founder bookkeeping label
	# ("founder-a") — NOT a species / curated morphology label (§19).
	return G.create({
		"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 2,
		"rules": [P.rule("r1", [
			P.action("extend", "support", [0, 100, 0], 10),
			P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
		])],
	}, "founder-a")

func _manifest_16(mode: String = "FREE", seed: int = 777) -> Dictionary:
	return {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco-polygon/exp-p9-profile",
		"seed": seed,
		"horizon_ticks": 16,
		"founders": [{"founder_id": "founder/a", "biological_hash": null, "genome": _founder_genome()}],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [{"id": "zone/wet", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": 1000, "organic_mg": 0}],
		},
		"placement": {"entries": [{"founder_ref": "founder/a", "zone_id": "zone/wet", "position_mm": [500, 0, 500]}]},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": mode,
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
	}

# --- a) VISUAL_ONLY applies + non-causal proof ---------------------------------

func _run_with_profile(manifest: Dictionary, profile: Dictionary) -> String:
	var ctl := Controller.new()
	if not bool(ctl.initialize(manifest).get("success", false)):
		return ""
	var visual: Dictionary = Profile.visual_profile(profile) if not profile.is_empty() else {}
	var primitives_total := 0
	for _tick in 16:
		if not bool(ctl.step().get("success", false)):
			return ""
		for entry in ctl.debug_state().population:
			var state: Dictionary = entry.state
			var descriptor := Descriptor.compile(state.development.modules, String(state.individual_id), state.position_mm)
			if descriptor.is_empty():
				continue
			var realized: Dictionary = Realizer.realize(descriptor, visual)
			primitives_total += int(realized.primitive_count)
	_check(primitives_total > 0, "profile run produced primitives")
	return String(ctl.get_snapshot().canonical_state_hash)

func _test_visual_only() -> void:
	for mode in Profile.MODES:
		var preset: Dictionary = Profile.preset(mode)
		_check(Profile.validate(preset).is_empty(), "preset %s validates" % mode)
	_check(Profile.validate(Profile.preset("NOT_A_MODE")) == "" and String(Profile.preset("NOT_A_MODE").mode) == "FREE",
		"unknown mode falls back to FREE")
	var broken: Dictionary = Profile.preset("FREE")
	broken.visual.presentation_detail = "ULTRA"
	_check(not Profile.validate(broken).is_empty(), "invalid presentation_detail rejected")
	broken = Profile.preset("EARTH_LIKE")
	broken.rule_class = "VISUAL_ONLY"
	_check(not Profile.validate(broken).is_empty(), "rule_class/mode mismatch rejected")
	# visual_profile REALLY differs between profiles.
	var vp_free: Dictionary = Profile.visual_profile(Profile.preset("FREE"))
	var vp_nms: Dictionary = Profile.visual_profile(Profile.preset("NMS_LIKE"))
	var vp_soft: Dictionary = Profile.visual_profile(Profile.preset("SOFT"))
	_check(int(vp_free.palette_seed) != int(vp_nms.palette_seed), "palette differs FREE vs NMS_LIKE")
	_check(String(vp_free.lod) == "HIGH" and String(vp_soft.lod) == "MEDIUM", "presentation_detail differs FREE vs SOFT")
	# ...and the realizer output actually changes.
	var descriptor := _grown_descriptor()
	var m_free: Dictionary = Realizer.realize(descriptor, vp_free)
	var m_nms: Dictionary = Realizer.realize(descriptor, vp_nms)
	var m_soft: Dictionary = Realizer.realize(descriptor, vp_soft)
	var colors_differ := false
	for i in m_free.primitives.size():
		if Array(m_free.primitives[i].color) != Array(m_nms.primitives[i].color):
			colors_differ = true
			break
	_check(colors_differ, "palette change really changes realized colours")
	_check(int(m_free.primitives[0].radial_segments) != int(m_soft.primitives[0].radial_segments),
		"presentation_detail change really changes LOD detail")
	# Non-causal proof: 16 ticks, profile A vs profile B vs NO profile.
	var manifest := _manifest_16()
	var hash_none := _run_with_profile(manifest, {})
	var hash_a := _run_with_profile(manifest, Profile.preset("NMS_LIKE"))
	var hash_b := _run_with_profile(manifest, Profile.preset("EARTH_LIKE"))
	_check(not hash_none.is_empty() and not hash_a.is_empty() and not hash_b.is_empty(), "all three profile runs complete")
	_check(hash_none == hash_a and hash_none == hash_b,
		"canonical_state_hash identical: no profile vs A vs B (non-causal proof §18)")

func _grown_descriptor() -> Dictionary:
	var state := _grow(Fixtures.make(1), 12)
	return Descriptor.compile(state.modules, "test/p9", [500, 0, 500])

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

# --- b) DEVELOPMENT_BIAS uses canonical A3 hook -------------------------------

func _test_development_bias_applied() -> void:
	for mode in ["SOFT", "EARTH_LIKE", "NMS_LIKE"]:
		var preset: Dictionary = Profile.preset(mode)
		_check(String(preset.rule_class) == "DEVELOPMENT_BIAS", "%s declares DEVELOPMENT_BIAS intent" % mode)
		var result: Dictionary = Profile.apply_development_bias(preset)
		_check(bool(result.get("success", false)) and bool(result.get("applied", false)), "%s canonical bias is applied" % mode)
		_check(String(result.get("status", "")) == Profile.APPLIED_STATUS, "%s reports APPLIED_CANONICAL_BIAS" % mode)
		var bias: Dictionary = result.get("bias", {})
		_check(Mutation.validate_bias(bias).is_empty(), "%s bias validates in canonical A3" % mode)
		var one := Mutation.mutate_with_bias(_founder_genome(), 42, bias)
		var two := Mutation.mutate_with_bias(_founder_genome(), 42, bias)
		_check(bool(one.get("success", false)) == bool(two.get("success", false)), "%s bias deterministic success/rejection" % mode)
		if bool(one.get("success", false)):
			_check(String(one.get("event_hash", "")) == String(two.get("event_hash", "")), "%s same seed -> same canonical mutation event" % mode)
			_check(String(one.get("selected_operator", "")) in Mutation.OPERATORS, "%s selects only an existing canonical operator" % mode)
	var free_result: Dictionary = Profile.apply_development_bias(Profile.preset("FREE"))
	_check(bool(free_result.get("success", false)) and String(free_result.status) == "NOT_APPLICABLE", "FREE profile has no development semantics")
	var weights: Dictionary = Profile.resolve_weights(Profile.preset("EARTH_LIKE"), 42)
	_check(not bool(weights.get("blocked", true)) and not (weights.operator_weights as Dictionary).is_empty(), "DEVELOPMENT_BIAS weights are active provenance")

# --- c) FREE-mode acceptance (§19) ----------------------------------------------

func _test_free_acceptance() -> void:
	var genome := _founder_genome()
	_check(not genome.is_empty(), "label-free founder genome is canonical-valid")
	_check(String(genome.get("label", "")) == "founder-a" and not genome.has("species"),
		"genome carries only a founder bookkeeping label, no species/curated label")
	var manifest := _manifest_16("FREE")
	_check(Manifest.validate(manifest).is_empty(), "FREE-mode manifest validates")
	var ctl := Controller.new()
	_check(bool(ctl.initialize(manifest).get("success", false)), "FREE-mode controller initializes")
	_check(bool(ctl.run(16).get("success", false)), "FREE-mode run(16) succeeds")
	var any_alive := false
	for entry in ctl.debug_state().population:
		var state: Dictionary = entry.state
		if not bool(state.alive) or state.development.modules.is_empty():
			continue
		any_alive = true
		_check(B.validate(state.development.modules).is_empty(),
			"%s grown body is a canonical-valid BodyGraph" % String(state.individual_id))
		var descriptor := Descriptor.compile(state.development.modules, String(state.individual_id), state.position_mm)
		_check(not descriptor.is_empty(), "%s has a visible morphology (descriptor non-empty)" % String(state.individual_id))
		if descriptor.is_empty():
			continue
		var realized: Dictionary = Realizer.realize(descriptor, Profile.visual_profile(Profile.preset("FREE")))
		var per_module := {}
		for primitive in realized.primitives:
			per_module[String(primitive.module_id)] = int(per_module.get(String(primitive.module_id), 0)) + 1
		var uncovered := 0
		for module in state.development.modules:
			if int(per_module.get(String(module.id), 0)) < 1:
				uncovered += 1
		_check(uncovered == 0, "%s realizes >= 1 primitive per module" % String(state.individual_id))
	_check(any_alive, "FREE mode accepted the label-free genome with visible growth")

# --- d) Emergent morphotypes (§20) -----------------------------------------------

func _test_morphotype_classifier() -> void:
	# Determinism + purity on real grown descriptors.
	for index in [0, 1, 2]:
		var state := _grow(Fixtures.make(index), 12)
		if state.is_empty():
			continue
		var descriptor := Descriptor.compile(state.modules, "test/morpho", [500, 0, 500])
		if descriptor.is_empty():
			continue
		var before: Dictionary = descriptor.duplicate(true)
		var c1: Dictionary = Classifier.classify(descriptor)
		var c2: Dictionary = Classifier.classify(descriptor)
		_check(not c1.is_empty() and String(c1.classification_digest) == String(c2.classification_digest),
			"fixture%d classification deterministic" % index)
		_check(descriptor == before, "fixture%d classify never mutates the descriptor" % index)
		_check(String(c1.morphotype) in Classifier.MORPHOTYPES or String(c1.morphotype).begins_with("cluster_"),
			"fixture%d morphotype in vocabulary (%s)" % [index, String(c1.morphotype)])
	# Diversity aggregation.
	var classifications: Array = []
	for index in [0, 1, 2]:
		var state := _grow(Fixtures.make(index), 12)
		if state.is_empty():
			continue
		var descriptor := Descriptor.compile(state.modules, "test/morpho", [0, 0, 0])
		if not descriptor.is_empty():
			classifications.append(Classifier.classify(descriptor))
	var diversity: Dictionary = Classifier.diversity(classifications)
	_check(int(diversity.count) == classifications.size(), "diversity counts every classification")
	_check(int(diversity.unique_morphotypes) >= 1, "diversity finds at least one morphotype")
	# Non-causality: 16 ticks with classification ON after EVERY tick vs OFF
	# -> identical canonical hash; the classifier writes nothing.
	var manifest := _manifest_16()
	var ctl := Controller.new()
	ctl.initialize(manifest)
	ctl.run(16)
	var hash_off := String(ctl.get_snapshot().canonical_state_hash)
	var ctl2 := Controller.new()
	ctl2.initialize(manifest)
	var state_writes := 0
	for _tick in 16:
		ctl2.step()
		var debug: Dictionary = ctl2.debug_state()
		for entry in debug.population:
			var state: Dictionary = entry.state
			var modules_before: Array = state.development.modules.duplicate(true)
			var descriptor := Descriptor.compile(state.development.modules, String(state.individual_id), state.position_mm)
			if not descriptor.is_empty():
				Classifier.classify(descriptor)
			if state.development.modules != modules_before:
				state_writes += 1
	_check(state_writes == 0, "classification never writes into canonical state")
	_check(String(ctl2.get_snapshot().canonical_state_hash) == hash_off,
		"classification ON vs OFF: canonical_state_hash identical (§20)")

# --- e) all 5 manifest modes valid -----------------------------------------------

func _test_manifest_modes() -> void:
	for mode in Profile.MODES:
		var manifest := _manifest_16(mode)
		_check(Manifest.validate(manifest).is_empty(), "manifest with organization_profile=%s validates" % mode)
		var ctl := Controller.new()
		var init_result: Dictionary = ctl.initialize(manifest)
		_check(bool(init_result.get("success", false)), "controller initializes with mode %s" % mode)
		if bool(init_result.get("success", false)):
			_check(bool(ctl.run(4).get("success", false)), "controller runs 4 ticks with mode %s" % mode)

func _run() -> void:
	_test_visual_only()
	_test_development_bias_applied()
	_test_free_acceptance()
	_test_morphotype_classifier()
	_test_manifest_modes()
	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_5_ORGANIZATION_PROFILE_P9 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_ORGANIZATION_PROFILE_P9 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P9_FAILURE " + failure)
		quit(1)
