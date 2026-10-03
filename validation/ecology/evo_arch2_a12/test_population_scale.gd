extends SceneTree

const Scale = preload("res://scripts/research/ecology/v2/ecology_scale_contract_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
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

func _rich_multigeneration_manifest() -> Dictionary:
	var manifest := Preset.create(104729, Scale.ACCEPTANCE_HORIZON_TICKS)
	manifest["experiment_id"] = "eco/a12/multigeneration-replay/v1"
	manifest["founders"] = [{"founder_id": "founder/a", "biological_hash": null, "genome": Protocol.ancestor()}]
	manifest["environment"] = {
		"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
		"zones": [{"id": "rich", "water_mg": 1000000, "light": 1000, "temperature": 500,
			"nutrient_mg": 1000000, "organic_mg": 1000000}],
	}
	manifest["placement"] = {"entries": [{"founder_ref": "founder/a", "zone_id": "rich", "position_mm": [500, 0, 500]}]}
	var endowment := Body.stock(0)
	endowment.material_mg = 200000
	endowment.water_mg = 200000
	endowment.energy_mj = 200000
	manifest["genesis"] = {"founder_endowment": endowment}
	return manifest

func _multigeneration_replay() -> void:
	var manifest := _rich_multigeneration_manifest()
	check(Manifest.validate(manifest).is_empty(), "multi-generation manifest is canonical")
	var original := Session.new()
	var started: Dictionary = original.start(manifest)
	check(started.success, "mutation-enabled multi-generation habitat starts")
	if not started.success:
		return
	var middle: Dictionary = original.controller.run_to_generation(2)
	check(middle.success and int(middle.generation) >= 2, "real lineage reaches generation 2")
	if not middle.success or int(middle.generation) < 2:
		return
	var checkpoint: Dictionary = original.export_bundle()
	check(checkpoint.success, "generation-2 checkpoint uses existing canonical transport")
	if not checkpoint.success:
		return
	var resumed := Session.new()
	var restored: Dictionary = resumed.restore_bundle(checkpoint.text, checkpoint.sha256)
	check(restored.success, "generation-2 checkpoint restores exactly")
	if not restored.success:
		return
	check(resumed.controller.get_snapshot().canonical_state_hash == original.controller.get_snapshot().canonical_state_hash,
		"mid-generation restore preserves exact canonical state")

	var a: Dictionary = original.controller.run_to_generation(Scale.ACCEPTANCE_TARGET_GENERATION)
	var b: Dictionary = resumed.controller.run_to_generation(Scale.ACCEPTANCE_TARGET_GENERATION)
	check(a.success and b.success and int(a.generation) >= Scale.ACCEPTANCE_TARGET_GENERATION 			and int(b.generation) >= Scale.ACCEPTANCE_TARGET_GENERATION,
		"both trajectories reach generation 3 inside declared horizon")
	if not a.success or not b.success:
		return
	check(original.controller.get_snapshot().canonical_state_hash == resumed.controller.get_snapshot().canonical_state_hash,
		"generation-3 uninterrupted/resumed state hashes match")
	check(original.controller.get_snapshot().field_hash == resumed.controller.get_snapshot().field_hash,
		"generation-3 field hashes match")
	check(original.controller.get_metrics().population_size == resumed.controller.get_metrics().population_size,
		"generation-3 population counts match")
	check(int(original.controller.get_metrics().population_size) > 1, "multi-generation result is not a single-organism long run")

	var state: Dictionary = original.controller.debug_state()
	var mutated_children := 0
	var hashes := {}
	for entry in state.population:
		hashes[String(entry.state.individual_id)] = Genome.biological_hash(entry.blueprint.genome)
	for entry in state.population:
		if String(entry.state.origin_kind) != "PARENT_TRANSFER":
			continue
		var receipt: Dictionary = entry.state.get("mutation_receipt", {})
		var parent_id := String(entry.state.origin_receipt.parent_id)
		if not receipt.is_empty() and hashes.has(parent_id) 				and String(receipt.receipt.child_genome_hash) == hashes[String(entry.state.individual_id)] 				and hashes[parent_id] != hashes[String(entry.state.individual_id)]:
			mutated_children += 1
	check(mutated_children > 0, "multi-generation chain contains receipt-backed inherited mutation")
	check(state.population.size() <= Scale.MAX_POPULATION, "multi-generation acceptance stays inside explicit scale contract")
