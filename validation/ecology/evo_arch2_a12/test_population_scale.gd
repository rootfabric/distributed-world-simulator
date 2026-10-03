extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Scale = preload("res://scripts/research/ecology/v2/ecology_scale_contract_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeHistory = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const Session = preload("res://scripts/ecology/habitat/persistent_habitat_session_v1.gd")
const Preset = preload("res://scripts/ecology/habitat/habitat_preset_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("A12_SCALE_FAIL " + message)

func _run() -> void:
	_contract_alignment()
	_population_boundary()
	_corpse_boundary()
	_multigeneration_replay()
	print("EVO_ARCH2_A12_SCALE checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A12_SCALE " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _contract_alignment() -> void:
	check(Scale.validate_descriptor(Scale.descriptor()).is_empty(), "scale descriptor self-validates")
	check(Scale.MAX_POPULATION == 256 and Scale.MAX_CORPSES == 256, "A12 R1 bound is explicit 256/256")
	check(Lifecycle.MAX_POPULATION == Scale.MAX_POPULATION, "A5 consumes canonical population bound")
	check(Lifecycle.MAX_PROPAGULES_PER_STEP == Scale.MAX_PROPAGULES_PER_STEP, "A5 consumes canonical propagule bound")
	check(Runtime.MAX_POPULATION == Scale.MAX_POPULATION, "shared runtime consumes canonical population bound")
	check(Runtime.MAX_CORPSES == Scale.MAX_CORPSES, "shared runtime consumes canonical corpse bound")
	check(Runtime.MAX_OUTBOX == Scale.MAX_OUTBOX, "shared runtime consumes canonical outbox bound")

func _population_manifest(count: int, starvation: bool) -> Dictionary:
	var manifest := Preset.create(20261003, 8)
	manifest["experiment_id"] = "eco/a12/population-boundary/%s/v1" % ("starve" if starvation else "admit")
	manifest["founders"] = [{"founder_id": "founder/a", "biological_hash": null, "genome": Protocol.ancestor()}]
	manifest["environment"] = {
		"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 16, "depth": 16},
		"zones": [{
			"id": "zone",
			"water_mg": 0 if starvation else 1000000,
			"light": 0 if starvation else 1000,
			"temperature": 500,
			"nutrient_mg": 0 if starvation else 1000000,
			"organic_mg": 0 if starvation else 1000000,
		}],
	}
	var entries: Array = []
	for index in count:
		var cell := index % 256
		var x := cell % 16
		var z := int(cell / 16)
		entries.append({"founder_ref": "founder/a", "zone_id": "zone",
			"position_mm": [x * 1000 + 500, 0, z * 1000 + 500]})
	manifest["placement"] = {"entries": entries}
	if starvation:
		var endowment := Body.stock(0)
		endowment.material_mg = 1000
		manifest["genesis"] = {"founder_endowment": endowment}
	return manifest

func _population_boundary() -> void:
	var exact := _population_manifest(Scale.MAX_POPULATION, false)
	check(Manifest.validate(exact).is_empty(), "256-founder manifest is canonical")
	var accepted := Session.new()
	var start: Dictionary = accepted.start(exact)
	check(start.success, "exact population ceiling admitted")
	if start.success:
		check(int(accepted.controller.get_metrics().population_size) == Scale.MAX_POPULATION,
			"all 256 founders retained without culling")
		check(Runtime.validate(accepted.controller.debug_state().runtime).is_empty(),
			"256-founder runtime remains canonically valid")

	var over := _population_manifest(Scale.MAX_POPULATION + 1, false)
	check(Manifest.validate(over).is_empty(), "257-founder input is syntactically valid experiment input")
	var rejected := Session.new()
	var failure: Dictionary = rejected.start(over)
	check(not failure.success and String(failure.error) == "CONTROLLER_RUNTIME_CREATE:RUNTIME_POPULATION_SIZE",
		"257th founder fails closed at canonical runtime boundary")
	check(rejected.controller == null, "population overflow creates no partial live session")

func _corpse_boundary() -> void:
	var manifest := _population_manifest(Scale.MAX_POPULATION, true)
	var session := Session.new()
	var started: Dictionary = session.start(manifest)
	check(started.success, "256-founder starvation fixture starts")
	if not started.success:
		return
	var starvation_limit := int(session.controller.debug_state().population[0].blueprint.life_history.survival.starvation_limit_ticks)
	var advanced: Dictionary = session.controller.run(starvation_limit)
	check(advanced.success, "256 organisms execute canonical starvation transition")
	if not advanced.success:
		return
	var state: Dictionary = session.controller.debug_state()
	check(int(session.controller.get_metrics().alive) == 0, "all 256 organisms died through A5")
	check(state.feedback.frame.corpses.size() == Scale.MAX_CORPSES, "all 256 corpses retained through A6")
	check(Runtime.validate(state.runtime).is_empty(), "256-corpse runtime remains canonically valid")

func _reproductive_scale_genome() -> Dictionary:
	var program := {
		"schema": Program.SCHEMA,
		"entry": "grow",
		"max_age": 64,
		"max_depth": 1,
		"rules": [Program.rule("grow", [
			Program.action("differentiate", "collector", [0, 2, 0], 1, 10000),
			Program.action("differentiate", "absorber", [0, -2, 0], 1, 0, 100),
			Program.action("differentiate", "reproductive", [2, 0, 0], 1),
			Program.action("retire"),
		])],
	}
	return Genome.create(program, "A12 explicit reproductive scale fixture")

func _reproductive_scale_policy() -> Dictionary:
	var policy := LifeHistory.create_default()
	policy["regulation"]["growth_light_min"] = 0
	policy["regulation"]["growth_water_min"] = 0
	policy["regulation"]["growth_competition_max"] = 1000
	policy["regulation"]["growth_temperature_min"] = 0
	policy["regulation"]["growth_temperature_max"] = 1000
	policy["metabolism"]["maintenance_energy_per_module_mj"] = 0
	policy["metabolism"]["maintenance_water_per_module_mg"] = 0
	policy["growth"]["transfer_permille"] = 1000
	policy["reproduction"]["maturity_ticks"] = 2
	policy["reproduction"]["interval_ticks"] = 2
	policy["reproduction"]["required_reproductive_modules"] = 1
	policy["reproduction"]["offspring_per_event"] = 1
	policy["reproduction"]["endowment"] = {"material_mg": 100, "water_mg": 100, "energy_mj": 100}
	policy["reproduction"]["fee_energy_mj"] = 0
	return policy

func _initial_multigeneration_runtime() -> Dictionary:
	var genome := _reproductive_scale_genome()
	var policy := _reproductive_scale_policy()
	check(not genome.is_empty(), "explicit reproductive genome validates")
	check(LifeHistory.validate(policy).is_empty(), "explicit reproductive life-history validates")
	var blueprint := Blueprint.create(genome, policy)
	check(not blueprint.is_empty(), "explicit reproductive blueprint validates")
	var rich_stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create("a12.scale", 1, [0, 0, 0], 1000, 1, 1,
		rich_stock, rich_stock, FieldContract.signals(1000, 500, 0, 0))
	check(not field.is_empty(), "rich canonical A4 field validates")
	var founder := Lifecycle.individual(
		blueprint, "a12-founder", [500, 0, 500],
		{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
	check(not founder.is_empty(), "explicit reproductive founder validates")
	var created := Runtime.create(
		"eco/a12/multigeneration-runtime/v1", field, [founder],
		Feedback.default_policy(), false)
	check(created.success, "shared EcologyRuntime accepts explicit reproductive fixture")
	return created.state if created.success else {}

func _lineage_depth(individual_id: String, by_id: Dictionary, memo: Dictionary) -> int:
	if memo.has(individual_id):
		return int(memo[individual_id])
	var depth := 0
	var entry: Dictionary = by_id.get(individual_id, {})
	if not entry.is_empty() and String(entry.state.origin_kind) == "PARENT_TRANSFER" 			and not entry.state.origin_receipt.is_empty():
		var parent_id := String(entry.state.origin_receipt.parent_id)
		depth = 1 + (_lineage_depth(parent_id, by_id, memo) if by_id.has(parent_id) else 0)
	memo[individual_id] = depth
	return depth

func _max_generation(population: Array) -> int:
	var by_id := {}
	for entry in population:
		by_id[String(entry.state.individual_id)] = entry
	var memo := {}
	var depth := 0
	for entry in population:
		depth = maxi(depth, _lineage_depth(String(entry.state.individual_id), by_id, memo))
	return depth

func _run_runtime_to_generation(source: Dictionary, target: int) -> Dictionary:
	var state: Dictionary = source.duplicate(true)
	var options := {
		"mutations_enabled": true,
		"operator": "module_parameter",
		"seed": 20261003,
		"mutation_key_prefix": "eco-a12-scale-r3",
	}
	for _tick in Scale.ACCEPTANCE_HORIZON_TICKS:
		var generation := _max_generation(state.population)
		if generation >= target:
			return {"success": true, "state": state, "generation": generation, "tick": int(state.tick)}
		var stepped := Runtime.step(state, options)
		if not stepped.success:
			return {"success": false, "error": stepped.error, "state": state,
				"generation": generation, "tick": int(state.tick)}
		state = stepped.state
	return {"success": false, "error": "A12_GENERATION_HORIZON", "state": state,
		"generation": _max_generation(state.population), "tick": int(state.tick)}

func _multigeneration_replay() -> void:
	var initial := _initial_multigeneration_runtime()
	if initial.is_empty():
		return
	var middle := _run_runtime_to_generation(initial, 2)
	print("A12_SCALE_GENERATION2 tick=%d generation=%d population=%d" % [
		int(middle.get("tick", -1)), int(middle.get("generation", -1)),
		int(middle.get("state", {}).get("population", []).size())])
	check(middle.success and int(middle.generation) >= 2, "shared runtime reaches generation 2")
	if not middle.success:
		return
	check(Runtime.validate(middle.state).is_empty(), "generation-2 runtime is canonically valid")

	var manifest_hash := C.digest({
		"schema": "dws.ecology.a12-scale-fixture.v1",
		"seed": 20261003,
		"scale": Scale.descriptor(),
		"genome_hash": Genome.biological_hash(_reproductive_scale_genome()),
		"life_history_hash": LifeHistory.biological_hash(_reproductive_scale_policy()),
	})
	var checkpoint := Checkpoint.create(manifest_hash, middle.state)
	check(not checkpoint.is_empty(), "generation-2 canonical checkpoint created")
	if checkpoint.is_empty():
		return
	var checkpoint_text := Checkpoint.serialize(checkpoint)
	check(not checkpoint_text.is_empty(), "generation-2 checkpoint serializes canonically")
	var restored := Checkpoint.deserialize(checkpoint_text, checkpoint_text.sha256_text(), manifest_hash)
	check(not restored.is_empty(), "generation-2 checkpoint admitted by external text anchor")
	if restored.is_empty():
		return
	check(Runtime.state_hash(restored.runtime_state) == Runtime.state_hash(middle.state),
		"checkpoint restores exact generation-2 runtime hash")

	var a := _run_runtime_to_generation(middle.state, Scale.ACCEPTANCE_TARGET_GENERATION)
	var b := _run_runtime_to_generation(restored.runtime_state, Scale.ACCEPTANCE_TARGET_GENERATION)
	print("A12_SCALE_GENERATION3_A tick=%d generation=%d population=%d" % [
		int(a.get("tick", -1)), int(a.get("generation", -1)),
		int(a.get("state", {}).get("population", []).size())])
	print("A12_SCALE_GENERATION3_B tick=%d generation=%d population=%d" % [
		int(b.get("tick", -1)), int(b.get("generation", -1)),
		int(b.get("state", {}).get("population", []).size())])
	check(a.success and b.success and int(a.generation) >= Scale.ACCEPTANCE_TARGET_GENERATION 			and int(b.generation) >= Scale.ACCEPTANCE_TARGET_GENERATION,
		"uninterrupted and restored runtime reach generation 3")
	if not a.success or not b.success:
		return
	check(Runtime.state_hash(a.state) == Runtime.state_hash(b.state),
		"generation-3 uninterrupted/restored runtime hashes match")
	check(Field.state_hash(a.state.field) == Field.state_hash(b.state.field),
		"generation-3 uninterrupted/restored field hashes match")
	check(a.state.population.size() == b.state.population.size(),
		"generation-3 uninterrupted/restored population counts match")
	check(a.state.population.size() > 1, "multi-generation result is not a single-organism long run")

	var hashes := {}
	var mutated_children := 0
	for entry in a.state.population:
		hashes[String(entry.state.individual_id)] = Genome.biological_hash(entry.blueprint.genome)
	for entry in a.state.population:
		if String(entry.state.origin_kind) != "PARENT_TRANSFER":
			continue
		var parent_id := String(entry.state.origin_receipt.parent_id)
		var receipt: Dictionary = entry.state.get("mutation_receipt", {})
		if not receipt.is_empty() and hashes.has(parent_id) 				and String(receipt.receipt.child_genome_hash) == hashes[String(entry.state.individual_id)] 				and hashes[parent_id] != hashes[String(entry.state.individual_id)]:
			mutated_children += 1
	check(mutated_children >= Scale.ACCEPTANCE_TARGET_GENERATION,
		"generation-3 chain contains multiple receipt-backed inherited mutations")
	check(a.state.population.size() <= Scale.MAX_POPULATION,
		"multi-generation acceptance stays inside explicit scale contract")

