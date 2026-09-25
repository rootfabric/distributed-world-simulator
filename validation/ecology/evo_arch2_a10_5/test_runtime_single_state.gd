extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — SINGLE-STATE INVARIANT tests (repair R1).
# Runner: Godot headless --script; prints checks/failed counts and PASS/FAIL.
#
# Proves the ECO-POLYGON-1 core contract after the repair: there is EXACTLY
# ONE current ecology state trajectory (one field, one population).
#   S1  A5 executes exactly once per ecology tick (age and maintenance
#       ledgers grow by exactly one tick per tick — a second A5 per tick
#       would double them);
#   S2  structural single truth: the runtime state carries exactly one
#       field and one population; the A6 feedback bookkeeping carries NO
#       field/population copy; the historical A6 public API still works for
#       old callers unchanged;
#   S3  mineralization mutates THE SAME field the next A5 tick samples
#       (organic decreases, nutrient increases, canonical field shows
#       exactly this — also through the controller);
#   S4  corpse return lands in THE SAME canonical field (real death through
#       the runtime API; exact water/organic/energy equations per cell);
#   S5  presentation snapshot sees the same state (snapshot field hash ==
#       debug field hash == runtime integrity hash; views match population);
#   S6  checkpoint saves the same state (save -> load -> identical hashes;
#       identical continuation).

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeState = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_SINGLE_STATE_FAIL " + message)

# --- fixtures ------------------------------------------------------------------------

func _founder_blueprint() -> Dictionary:
	var program := {
		"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 2,
		"rules": [P.rule("r1", [
			P.action("extend", "support", [0, 100, 0], 10),
			P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
		])],
	}
	return Blueprint.create(Genome.create(program, "single-state-founder"))

func _runtime_state(zone: Dictionary, endowment: Dictionary, feedback_enabled: bool = true) -> Dictionary:
	var field := Field.create("eco.single.state", 0, [0, 0, 0], 1000, 1, 1,
		FieldContract.stock(0), FieldContract.stock(1000000), FieldContract.signals(0, 0))
	var deposits := []
	for resource in FieldContract.RESOURCES:
		if int(zone.get(resource, 0)) > 0:
			deposits.append(Ports.effect("setup/%s" % resource, "eco.single.state", "deposit", resource, int(zone[resource]), [500, 0, 500], 0, "SINGLE_STATE_GENESIS"))
	if not deposits.is_empty():
		var applied := Field.apply_effects(field, deposits, "eco.single.state", 0, field.revision)
		if bool(applied.get("success", false)):
			field = applied.state
	var founder := _founder_blueprint()
	var individual := Lifecycle.individual(founder, "founder/solo", [500, 0, 500], endowment)
	var policy := Feedback.default_policy()
	var created := Runtime.create("eco-single-state", field, [individual], policy, feedback_enabled)
	return created

func _step(state: Dictionary, mutations_enabled := false) -> Dictionary:
	return Runtime.step(state, {
		"mutations_enabled": mutations_enabled,
		"operator": "small",
		"seed": 7,
		"mutation_key_prefix": Controller.MUTATION_KEY_PREFIX,
	})

func _stock_sum(field: Dictionary, resource: String) -> int:
	var total := 0
	for cell in field.cells:
		total += int(cell.stocks[resource])
	return total

func _manifest(horizon: int, organic_mg: int, nutrient_mg: int) -> Dictionary:
	return {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco-polygon/exp-single-state",
		"seed": 20260921,
		"horizon_ticks": horizon,
		"founders": [{"founder_id": "founder/solo", "biological_hash": null, "genome": Genome.create({
			"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 2,
			"rules": [P.rule("r1", [
				P.action("extend", "support", [0, 100, 0], 10),
				P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
			])],
		}, "single-state-founder")}],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [{"id": "litter", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": nutrient_mg, "organic_mg": organic_mg}],
		},
		"placement": {"entries": [{"founder_ref": "founder/solo", "zone_id": "litter", "position_mm": [500, 0, 500]}]},
		"mutation": {"operator": "small", "mutations_enabled": false},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 4},
		"mode": "LAB",
	}

# --- driver --------------------------------------------------------------------------

func _run() -> void:
	_s1_a5_exactly_once()
	_s2_structural_single_truth()
	_s3_mineralization_same_field()
	_s4_corpse_return_same_field()
	_s5_presentation_same_state()
	_s6_checkpoint_same_state()
	_finish()

# S1: A5 executes exactly once per ecology tick.

func _s1_a5_exactly_once() -> void:
	# Dark zone: no photosynthesis, no growth activation -> constant module
	# count; maintenance is paid from the endowment every single tick.
	var created := _runtime_state({"water_mg": 500000, "light": 0}, B.stock(200000))
	_check(bool(created.get("success", false)), "S1 runtime create succeeds: " + str(created))
	var state: Dictionary = created.state
	var founder := _founder_blueprint()
	var rate_water := int(founder.life_history.metabolism.maintenance_water_per_module_mg)
	var rate_energy := int(founder.life_history.metabolism.maintenance_energy_per_module_mj)
	var ticks := 6
	var module_count := -1
	for _i in ticks:
		var stepped: Dictionary = _step(state)
		_check(bool(stepped.get("success", false)), "S1 tick %d succeeds: %s" % [_i + 1, String(stepped.get("error", "?"))])
		if not bool(stepped.get("success", false)):
			return
		state = stepped.state
		var entry: Dictionary = state.population[0]
		if module_count < 0:
			module_count = int(entry.state.development.modules.size())
		_check(int(entry.state.development.modules.size()) == module_count, "S1 module count constant (no growth in the dark)")
		_check(int(entry.state.age_ticks) == _i + 1, "S1 age advanced by EXACTLY one tick (age=%d after %d ticks)" % [int(entry.state.age_ticks), _i + 1])
		_check(int(entry.state.starvation_ticks) == 0, "S1 maintenance fully funded")
		# One A5 per tick => maintenance ledger == ticks * rate * modules. A
		# second A5 execution per tick would double age AND this ledger.
		_check(int(entry.state.resource_ledger.maintenance.water_mg) == (_i + 1) * rate_water * module_count,
			"S1 maintenance water == exactly %d ticks * rate * modules (%d)" % [_i + 1, int(entry.state.resource_ledger.maintenance.water_mg)])
		_check(int(entry.state.resource_ledger.maintenance.energy_mj) == (_i + 1) * rate_energy * module_count,
			"S1 maintenance energy == exactly %d ticks * rate * modules (%d)" % [_i + 1, int(entry.state.resource_ledger.maintenance.energy_mj)])
		_check(int(state.feedback.step) == _i + 1, "S1 feedback advanced exactly once per tick (step=%d)" % int(state.feedback.step))

# S2: structural single truth.

func _s2_structural_single_truth() -> void:
	var created := _runtime_state({"water_mg": 500000, "light": 700, "nutrient_mg": 1000}, B.stock(200000))
	_check(bool(created.get("success", false)), "S2 runtime create succeeds")
	var state: Dictionary = created.state
	_check(Runtime.validate(state).is_empty(), "S2 runtime state validates")
	_check(C.keys(state, Runtime.STATE_KEYS), "S2 state carries exactly the canonical key set (one field, one population)")
	_check(C.keys(state.feedback, Runtime.FEEDBACK_KEYS), "S2 feedback bookkeeping carries exactly its own key set")
	_check(not state.feedback.has("field"), "S2 A6 bookkeeping has NO field truth")
	_check(not state.feedback.has("population"), "S2 A6 bookkeeping has NO population truth")
	var stepped: Dictionary = _step(state)
	_check(bool(stepped.get("success", false)), "S2 tick succeeds: " + String(stepped.get("error", "?")))
	if bool(stepped.get("success", false)):
		var next_state: Dictionary = stepped.state
		_check(C.keys(next_state, Runtime.STATE_KEYS), "S2 post-tick state keeps the single canonical key set")
		_check(not next_state.feedback.has("field") and not next_state.feedback.has("population"), "S2 post-tick A6 bookkeeping still truthless")
		_check(Runtime.validate(next_state).is_empty(), "S2 post-tick state validates")
	# Old-caller regression: the historical A6 public API is untouched.
	var field := Field.create("eco.single.a6", 0, [0, 0, 0], 1000, 1, 1, FieldContract.stock(0), FieldContract.stock(1000000), FieldContract.signals(700, 500, 0, 0))
	var applied := Field.apply_effects(field, [Ports.effect("a6-reg/water", "eco.single.a6", "deposit", "water_mg", 500000, [500, 0, 500], 0, "S2_GENESIS")], "eco.single.a6", 0, 0)
	if _check_bool(applied, "S2 A6 regression field deposit"):
		field = applied.state
	var founder := _founder_blueprint()
	var individual := Lifecycle.individual(founder, "founder/a6", [500, 0, 500], B.stock(200000))
	var legacy := Feedback.create("eco-single-a6", field, [individual], Feedback.default_policy())
	if _check_bool(legacy, "S2 historical Feedback.create works for old callers"):
		var legacy_field: Dictionary = legacy.state.frame.field
		var advanced := Feedback.advance(legacy.state, legacy_field.owner_token, legacy_field.owner_epoch, int(legacy.state.frame.step))
		_check(bool(advanced.get("success", false)), "S2 historical Feedback.advance works for old callers: " + String(advanced.get("error", "?")))
		if bool(advanced.get("success", false)):
			_check(Feedback.validate(advanced.state).is_empty(), "S2 historical A6 state still replay-validates")

func _check_bool(result: Dictionary, message: String) -> bool:
	_check(bool(result.get("success", false)), message + ": " + String(result.get("error", "?")))
	return bool(result.get("success", false))

# S3: mineralization mutates THE SAME field the next A5 tick samples.

func _s3_mineralization_same_field() -> void:
	# Controller path (canonical field shows exactly the mineralization).
	var controller := Controller.new()
	var manifest := _manifest(16, 5000, 0)
	_check(bool(controller.initialize(manifest, {}).get("success", false)), "S3 controller initializes on a litter zone")
	var organic_before := _stock_sum(controller.debug_state().field, "organic_mg")
	var nutrient_before := _stock_sum(controller.debug_state().field, "nutrient_mg")
	_check(bool(controller.run(4).get("success", false)), "S3 controller run(4) succeeds")
	var debug: Dictionary = controller.debug_state()
	var mineralized := int(debug.feedback.frame.mineralized_mg)
	_check(mineralized > 0, "S3 mineralization happened (mineralized_mg=%d)" % mineralized)
	var intake_organic := 0
	var intake_nutrient := 0
	for entry in debug.population:
		intake_organic += int(entry.state.resource_ledger.field_intake.organic_mg)
		intake_nutrient += int(entry.state.resource_ledger.field_intake.nutrient_mg)
	var organic_after := _stock_sum(debug.field, "organic_mg")
	var nutrient_after := _stock_sum(debug.field, "nutrient_mg")
	# THE canonical single-field equation: organic dropped by mineralization
	# PLUS organism intake; nutrient rose by mineralization MINUS intake.
	_check(organic_before - organic_after == mineralized + intake_organic,
		"S3 canonical field organic drop == mineralized + intake (%d == %d + %d)" % [organic_before - organic_after, mineralized, intake_organic])
	_check(nutrient_after - nutrient_before == mineralized - intake_nutrient,
		"S3 canonical field nutrient gain == mineralized - intake (%d == %d - %d)" % [nutrient_after - nutrient_before, mineralized, intake_nutrient])
	# The next A5 tick sampled exactly this (mineralized) field: the sample
	# source hash equals the canonical field hash at the end of the previous
	# tick (which already contains that tick's mineralization).
	var hash_after_tick4 := Field.state_hash(debug.field)
	_check(bool(controller.run(1).get("success", false)), "S3 one more tick succeeds")
	var sampled_same := true
	for entry in controller.debug_state().population:
		if not bool(entry.state.alive):
			continue
		if String(entry.state.last_environment_source.get("field_hash", "")) != hash_after_tick4:
			sampled_same = false
	_check(sampled_same, "S3 A5 samples THE canonical mineralized field (source hash == previous tick's canonical field hash)")
	# Runtime path: the same equation on the shared runtime state.
	var created := _runtime_state({"water_mg": 500000, "light": 700, "organic_mg": 5000}, B.stock(200000))
	if _check_bool(created, "S3 runtime create on litter zone"):
		var state: Dictionary = created.state
		var rt_organic_before := _stock_sum(state.field, "organic_mg")
		var rt_mineralized := 0
		var ok := true
		for _i in 4:
			var stepped: Dictionary = _step(state)
			if not _check_bool(stepped, "S3 runtime tick %d" % (_i + 1)):
				ok = false
				break
			state = stepped.state
			rt_mineralized = int(state.feedback.mineralized_mg)
		if ok:
			_check(rt_mineralized > 0, "S3 runtime mineralization happened")
			_check(rt_organic_before - _stock_sum(state.field, "organic_mg") == rt_mineralized + _runtime_intake(state, "organic_mg"),
				"S3 runtime canonical field organic equation holds")
			_check(Runtime.validate(state).is_empty(), "S3 runtime state still validates (conservation over the ONE field)")

func _runtime_intake(state: Dictionary, resource: String) -> int:
	var total := 0
	for entry in state.population:
		total += int(entry.state.resource_ledger.field_intake[resource])
	return total

# S4: corpse return lands in THE SAME canonical field (real death).

func _s4_corpse_return_same_field() -> void:
	# Zero endowment in a dark world: starvation death at
	# starvation_limit_ticks, then corpse return + mineralization on the ONE
	# canonical field. Every equation below is an exact delta balance over
	# that single field.
	var created := _runtime_state({"water_mg": 500000, "light": 0}, B.stock(0))
	_check(bool(created.get("success", false)), "S4 runtime create with a zero-endowment founder succeeds")
	var state: Dictionary = created.state
	var founder := _founder_blueprint()
	var starvation_limit := int(founder.life_history.survival.starvation_limit_ticks)
	var death_tick := -1
	for _i in starvation_limit + 1:
		var stepped: Dictionary = _step(state)
		if not _check_bool(stepped, "S4 tick %d succeeds" % (_i + 1)):
			return
		state = stepped.state
		if not bool(state.population[0].state.alive):
			death_tick = _i + 1
			break
	_check(death_tick == starvation_limit, "S4 founder died of starvation exactly at the policy limit (tick %d)" % death_tick)
	_check(int(state.feedback.corpses.size()) == 1, "S4 exactly one corpse registered in the canonical bookkeeping")
	_check(not bool(state.population[0].state.alive), "S4 dead entry stays in the single population (inert)")
	# Anchors at death time.
	var corpse: Dictionary = state.feedback.corpses[0]
	var water_anchor := _stock_sum(state.field, "water_mg")
	var organic_anchor := _stock_sum(state.field, "organic_mg")
	var returned_water_anchor := int(corpse.returned.water_mg)
	var returned_organic_anchor := int(corpse.returned.organic_mg)
	var mineralized_anchor := int(state.feedback.mineralized_mg)
	var intake_water_anchor := _runtime_intake(state, "water_mg")
	var intake_organic_anchor := _runtime_intake(state, "organic_mg")
	_check(returned_water_anchor + returned_organic_anchor + int(corpse.dissipated_energy_mj) > 0,
		"S4 corpse return/dissipation began in the death tick (A6 registers and returns in the same transition)")
	# Continue: the corpse drains into the field by the exact returned deltas;
	# dead organisms stop intaking; mineralization keeps converting organic.
	for _i in 4:
		var stepped: Dictionary = _step(state)
		if not _check_bool(stepped, "S4 post-death tick %d succeeds" % (_i + 1)):
			return
		state = stepped.state
		corpse = state.feedback.corpses[0]
		var water_now := _stock_sum(state.field, "water_mg")
		var organic_now := _stock_sum(state.field, "organic_mg")
		var nutrient_now := _stock_sum(state.field, "nutrient_mg")
		var d_water := int(corpse.returned.water_mg) - returned_water_anchor
		var d_organic := int(corpse.returned.organic_mg) - returned_organic_anchor
		var d_mineral := int(state.feedback.mineralized_mg) - mineralized_anchor
		_check(water_now == water_anchor + d_water - (_runtime_intake(state, "water_mg") - intake_water_anchor),
			"S4 field water == death anchor + corpse return delta - inert-intake delta")
		_check(organic_now == organic_anchor + d_organic - d_mineral - (_runtime_intake(state, "organic_mg") - intake_organic_anchor),
			"S4 field organic == death anchor + corpse return delta - mineralization delta (single field)")
		_check(nutrient_now >= 0, "S4 field nutrient stays canonical")
		returned_water_anchor = int(corpse.returned.water_mg)
		returned_organic_anchor = int(corpse.returned.organic_mg)
		mineralized_anchor = int(state.feedback.mineralized_mg)
		intake_water_anchor = _runtime_intake(state, "water_mg")
		intake_organic_anchor = _runtime_intake(state, "organic_mg")
	_check(Runtime.validate(state).is_empty(), "S4 runtime state validates across death + return (conservation over the ONE field)")

# S5: presentation snapshot sees the same state.

func _s5_presentation_same_state() -> void:
	var controller := Controller.new()
	var manifest := _manifest(16, 0, 1000)
	_check(bool(controller.initialize(manifest, {}).get("success", false)), "S5 controller initializes")
	_check(bool(controller.run(5).get("success", false)), "S5 controller run(5) succeeds")
	var snapshot: Dictionary = controller.get_snapshot()
	var debug: Dictionary = controller.debug_state()
	_check(String(snapshot.field_hash) == Field.state_hash(debug.field), "S5 snapshot field hash == the ONE debug field hash")
	_check(String(snapshot.field_hash) == Field.state_hash(debug.runtime.field), "S5 snapshot field hash == runtime truth field hash")
	_check(int(snapshot.tick) == int(debug.runtime.tick), "S5 snapshot tick == runtime truth tick")
	_check(snapshot.presentation.size() == debug.population.size(), "S5 presentation covers exactly the one population")
	var views_by_id := {}
	for view in snapshot.presentation:
		views_by_id[String(view.individual_id)] = view
	var same_organisms := true
	for entry in debug.population:
		var view: Dictionary = views_by_id.get(String(entry.state.individual_id), {})
		if view.is_empty() or bool(view.alive) != bool(entry.state.alive) \
				or int(view.development_summary.module_count) != int(entry.state.development.modules.size()):
			same_organisms = false
	_check(same_organisms, "S5 presentation views project the same organisms (id/alive/modules)")
	_check(String(snapshot.canonical_state_hash) == String(debug.runtime.integrity_hash), "S5 canonical_state_hash is the integrity seal of the SAME shared runtime state")

# S6: checkpoint saves the same state.

func _s6_checkpoint_same_state() -> void:
	var controller := Controller.new()
	var manifest := _manifest(32, 2000, 0)
	_check(bool(controller.initialize(manifest, {}).get("success", false)), "S6 controller initializes")
	_check(bool(controller.run(6).get("success", false)), "S6 run(6) succeeds")
	var saved: Dictionary = controller.serialize_state()
	_check(bool(saved.get("success", false)), "S6 serialize_state succeeds: " + String(saved.get("error", "?")))
	var hash_at_6 := String(controller.get_snapshot().canonical_state_hash)
	var restored := Controller.new()
	_check(bool(restored.initialize(manifest, {}).get("success", false)), "S6 twin controller initializes")
	var loaded: Dictionary = restored.load_state(String(saved.state_text), String(saved.manifest_hash), String(saved.state_checksum))
	_check(bool(loaded.get("success", false)), "S6 load_state succeeds: " + String(loaded.get("error", "?")))
	_check(String(restored.get_snapshot().canonical_state_hash) == hash_at_6, "S6 restored snapshot hash == saved snapshot hash")
	_check(bool(controller.run(4).get("success", false)), "S6 original advances 4 more")
	_check(bool(restored.run(4).get("success", false)), "S6 restored advances 4 more")
	_check(String(controller.get_snapshot().canonical_state_hash) == String(restored.get_snapshot().canonical_state_hash),
		"S6 checkpoint continuation is THE same trajectory (identical hash at tick 10)")

func _finish() -> void:
	print("EVO_ARCH2_A10_5_RUNTIME_SINGLE_STATE checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_RUNTIME_SINGLE_STATE PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_SINGLE_STATE_FAILURE " + failure)
		quit(1)
