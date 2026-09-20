extends SceneTree
# Repair R1: controller equivalence must target the shared composed runtime,
# not a hand-copied controller loop. Also proves one A5+A6 trajectory and
# heritable canonical mutation transfer.

const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_composed_runtime_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("A10_5_REPAIR_EQ_FAIL " + message)

func _genome(reproductive: bool) -> Dictionary:
	var rules := [P.rule("r1", [
		P.action("extend", "support", [0, 100, 0], 10),
		P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
	])]
	if reproductive:
		rules[0].next = "r2"
		rules.append(P.rule("r2", [P.action("differentiate", "reproductive", [0, 50, 0], 5)]))
	return Genome.create({"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 3, "rules": rules}, "founder-a")

func _manifest(reproductive: bool, horizon: int) -> Dictionary:
	var g := _genome(reproductive)
	return {
		"schema": Manifest.SCHEMA, "experiment_id": "eco-polygon/repair-equivalence",
		"seed": 777, "horizon_ticks": horizon,
		"founders": [{"founder_id":"founder/a","biological_hash":null,"genome":g}],
		"environment": {"spatial":{"origin_mm":[0,0,0],"cell_size_mm":1000,"width":1,"depth":1},
			"zones":[{"id":"zone/wet","water_mg":500000,"light":700,"temperature":500,"nutrient_mg":1000,"organic_mg":0}]},
		"placement":{"entries":[{"founder_ref":"founder/a","zone_id":"zone/wet","position_mm":[500,0,500]}]},
		"mutation":{"operator":"small","mutations_enabled":true}, "organization_profile":"FREE",
		"feedback":{"enabled":true,"decomposition_enabled":true}, "metrics":{"requested":["population"]},
		"checkpoint":{"interval_ticks":16}, "mode":"LAB",
	}

func _direct_from_controller(controller: Object, manifest: Dictionary, ticks: int) -> Dictionary:
	var state: Dictionary = controller.current_runtime_state()
	var mutation := {"enabled": bool(manifest.mutation.mutations_enabled), "operator": String(manifest.mutation.operator), "bias": {}}
	for _i in ticks:
		var stepped := Runtime.step(state, mutation, int(manifest.seed))
		if not bool(stepped.get("success", false)):
			return {"success": false, "error": stepped.get("error", "?")}
		state = stepped.state
	return {"success": true, "state": state}

func _single_trajectory(controller: Object, label: String) -> void:
	var debug: Dictionary = controller.debug_state()
	_check(debug.field == debug.feedback.frame.field, label + " feedback field is the SAME canonical field")
	_check(debug.population == debug.feedback.frame.population, label + " feedback population is the SAME canonical population")
	_check(String(debug.runtime.integrity_hash) == String(controller.get_snapshot().canonical_state_hash), label + " snapshot hash is runtime integrity hash")

func _scenario_equivalence() -> void:
	var manifest := _manifest(false, 64)
	var direct_seed := Controller.new()
	_check(bool(direct_seed.initialize(manifest).get("success", false)), "X direct seed initialize")
	var direct := _direct_from_controller(direct_seed, manifest, 64)
	_check(bool(direct.get("success", false)), "X shared runtime direct run succeeds: " + str(direct.get("error", "")))

	var ctl := Controller.new()
	_check(bool(ctl.initialize(manifest).get("success", false)), "X controller initialize")
	_check(bool(ctl.run(64).get("success", false)), "X controller run(64)")
	if bool(direct.get("success", false)):
		_check(String(direct.state.integrity_hash) == String(ctl.get_snapshot().canonical_state_hash), "X controller == shared canonical runtime")
	_single_trajectory(ctl, "X")

	var step_ctl := Controller.new()
	step_ctl.initialize(manifest)
	var step_ok := true
	for _i in 64:
		if not bool(step_ctl.step().get("success", false)):
			step_ok = false
			break
	_check(step_ok and String(step_ctl.get_snapshot().canonical_state_hash) == String(ctl.get_snapshot().canonical_state_hash), "X STEP == RUN")

	var batch_ctl := Controller.new()
	batch_ctl.initialize(manifest)
	var batch_ok := true
	for _i in 4:
		if not bool(batch_ctl.run(16).get("success", false)):
			batch_ok = false
			break
	_check(batch_ok and String(batch_ctl.get_snapshot().canonical_state_hash) == String(ctl.get_snapshot().canonical_state_hash), "X 4x16 == RUN64")

func _scenario_mutation_inheritance() -> void:
	var manifest := _manifest(true, 24)
	var ctl := Controller.new()
	_check(bool(ctl.initialize(manifest).get("success", false)), "R initialize")
	var parent_hash := Genome.biological_hash(ctl.debug_state().population[0].blueprint.genome)
	var found_mutated := false
	for _i in 24:
		var step := ctl.step()
		_check(bool(step.get("success", false)), "R tick succeeds")
		if not bool(step.get("success", false)): break
		for entry in ctl.debug_state().population:
			if String(entry.state.origin_kind) == "PARENT_MUTATION_TRANSFER":
				found_mutated = true
				_check(Genome.biological_hash(entry.blueprint.genome) != parent_hash, "R mutated descendant genome differs from founder")
				_check(not entry.state.origin_receipt.mutation_receipt.is_empty(), "R mutation receipt persisted in lineage")
				break
		if found_mutated: break
	_check(found_mutated, "R at least one mutation is inherited, not fallback-only")
	_single_trajectory(ctl, "R")

	var seed_ctl := Controller.new()
	seed_ctl.initialize(manifest)
	var direct := _direct_from_controller(seed_ctl, manifest, int(ctl.get_snapshot().tick))
	_check(bool(direct.get("success", false)), "R direct shared runtime run")
	if bool(direct.get("success", false)):
		_check(String(direct.state.integrity_hash) == String(ctl.get_snapshot().canonical_state_hash), "R controller mutation lineage == shared runtime")

func _run() -> void:
	_scenario_equivalence()
	_scenario_mutation_inheritance()
	print("EVO_ARCH2_A10_5_CONTROLLER_REPAIR checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_CONTROLLER_REPAIR PASS")
		quit(0)
	else:
		for failure in failures: print("A10_5_CONTROLLER_REPAIR_FAILURE " + failure)
		quit(1)
