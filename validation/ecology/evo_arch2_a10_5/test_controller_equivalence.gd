extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P2 ExperimentController equivalence tests.
# Runner: Godot headless --script; prints checks/failed counts and PASS/FAIL.
# CRITICAL case: direct canonical loop (a-d steps implemented here) MUST
# produce the same final canonical_state_hash as the controller.
#
# Scenario X (equivalence, 64 ticks): manifest X / seed X, founder program
#   without a reproductive module (bounded population; A6 replay validation
#   is O(steps^2) in payload size, so a reproduction-heavy 64-tick history
#   costs minutes per run — see report known limitations).
# Scenario R (reproduction liveness, 12 ticks): reproductive program; the
#   population grows through canonical propagule materialization and the
#   direct loop still matches the controller hash.

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeState = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const OrganismState = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P2_FAIL " + message)

func _program(with_reproductive: bool) -> Dictionary:
	var actions := [
		P.action("extend", "support", [0, 100, 0], 10),
		P.action("differentiate", "collector", [0, 60, 0], 4, 200),
	]
	var rules := [P.rule("r1", actions)]
	if with_reproductive:
		rules[0].next = "r2"
		rules.append(P.rule("r2", [P.action("differentiate", "reproductive", [0, 50, 0], 5)]))
	return {"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 4, "rules": rules}

func _manifest(with_reproductive: bool, horizon: int, seed: int) -> Dictionary:
	# Scenario X (equivalence, 64 ticks): single founder, 1x1 field, one zone;
	# the A6 feedback replay validation is O(steps^2), so a reproduction-heavy
	# 64-tick history costs minutes per run (known limitation) — scenario R
	# exercises reproduction at a shorter horizon.
	var actions := [
		P.action("extend", "support", [0, 100, 0], 10),
		# Large collector keeps the founder energy-solvent while the growth
		# grant drains reserves each tick (canonical A5 semantics).
		P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
	]
	var rules := [P.rule("r1", actions)]
	if with_reproductive:
		rules[0].next = "r2"
		rules.append(P.rule("r2", [P.action("differentiate", "reproductive", [0, 50, 0], 5)]))
	var founder := Genome.create({
		"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 2, "rules": rules,
	}, "founder-a")
	return {
		"schema": "dws.ecology.workbench.experiment-manifest.v1",
		"experiment_id": "eco-polygon/exp-002" if with_reproductive else "eco-polygon/exp-001",
		"seed": seed,
		"horizon_ticks": horizon,
		"founders": [
			{"founder_id": "founder/a", "biological_hash": null, "genome": founder},
		] if not with_reproductive else [
			{"founder_id": "founder/a", "biological_hash": null, "genome": founder},
			{"founder_id": "founder/b", "biological_hash": null, "genome": founder.duplicate(true)},
		],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [
				{"id": "zone/wet", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": 1000, "organic_mg": 0},
			],
		} if not with_reproductive else {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 2, "depth": 2},
			"zones": [
				{"id": "zone/wet", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": 1000, "organic_mg": 0},
				{"id": "zone/dry", "water_mg": 50000, "light": 900, "temperature": 600, "nutrient_mg": 100, "organic_mg": 0},
			],
		},
		"placement": {
			"entries": [
				{"founder_ref": "founder/a", "zone_id": "zone/wet", "position_mm": [500, 0, 500]},
			] if not with_reproductive else [
				{"founder_ref": "founder/a", "zone_id": "zone/wet", "position_mm": [500, 0, 500]},
				{"founder_ref": "founder/b", "zone_id": "zone/wet", "position_mm": [500, 0, 500]},
			],
		},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
	}

# --- direct canonical loop (mini-runner): the same a-d steps ---------------

func _direct_tick(state: Dictionary, manifest: Dictionary) -> String:
	# (a) A5 lifecycle step.
	var result := Lifecycle.step_population(state.field, state.population, state.field.owner_token, state.field.owner_epoch, state.field.revision)
	if not result.success:
		return "A:" + String(result.error)
	state.field = result.field
	state.population = result.population
	# (b)+(c) mutation + materialization of propagules.
	var children: Array = []
	for propagule in result.propagules:
		var parent: Dictionary = {}
		for entry in state.population:
			if entry.state.individual_id == propagule.parent_id:
				parent = entry
				break
		if parent.is_empty():
			return "PARENT"
		var child_blueprint: Dictionary = parent.blueprint
		if manifest.mutation.mutations_enabled:
			var seed := Controller.mutation_seed(manifest.seed, state.tick + 1, String(propagule.parent_id))
			var mutated := Mutation.mutate(parent.blueprint.genome, seed, manifest.mutation.operator)
			if mutated.get("success", false):
				var candidate := Blueprint.create(mutated.genome, parent.blueprint.life_history)
				if not candidate.is_empty():
					child_blueprint = candidate
		var child := Lifecycle.materialize_propagule(propagule, child_blueprint, parent.state)
		if child.is_empty() and child_blueprint != parent.blueprint:
			child = Lifecycle.materialize_propagule(propagule, parent.blueprint, parent.state)
		if child.is_empty():
			return "MATERIALIZE"
		children.append(child)
	state.population.append_array(children)
	state.population.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.state.individual_id < b.state.individual_id)
	# (d) A6 feedback advance.
	if manifest.feedback.enabled:
		var advanced := Feedback.advance(state.feedback, state.feedback.frame.field.owner_token, state.feedback.frame.field.owner_epoch, state.feedback.frame.step)
		if not advanced.success:
			return "D:" + String(advanced.error)
		state.feedback = advanced.state
	state.tick += 1
	return ""

func _canonical_hash(state: Dictionary) -> String:
	var population_hashes: Array = []
	for entry in state.population:
		population_hashes.append({
			"individual_id": entry.state.individual_id,
			"life_state_hash": LifeState.state_hash(entry.state, entry.blueprint),
			"development_biological_hash": OrganismState.biological_hash(entry.state.development),
		})
	return C.digest({
		"tick": state.tick,
		"field_hash": Field.state_hash(state.field),
		"population": population_hashes,
		"feedback_hash": C.digest(state.feedback),
	})

func _alive(state: Dictionary) -> int:
	var count := 0
	for entry in state.population:
		if entry.state.alive:
			count += 1
	return count

func _max_modules(state: Dictionary) -> int:
	var count := 0
	for entry in state.population:
		count = maxi(count, entry.state.development.modules.size())
	return count

func _new_controller(manifest: Dictionary) -> Object:
	var controller := Controller.new()
	var started: Dictionary = controller.initialize(manifest)
	_check(bool(started.get("success", false)), "initialize succeeds: " + str(started))
	return controller

func _run() -> void:
	_scenario_x()
	_scenario_r()
	_finish()

# Scenario X: equivalence matrix at 64 ticks.

func _scenario_x() -> void:
	var manifest := _manifest(false, 64, 777)

	# 1. Controller run(64) + snapshot/metrics purity + reset determinism.
	var ctl_run := Controller.new()
	var init_result: Dictionary = ctl_run.initialize(manifest)
	_check(bool(init_result.get("success", false)), "X controller initialize succeeds: " + str(init_result))
	var run_result: Dictionary = ctl_run.run(64)
	_check(bool(run_result.get("success", false)), "X controller run(64) succeeds: " + str(run_result))
	var hash_run := ""
	if bool(run_result.get("success", false)):
		hash_run = String(ctl_run.get_snapshot().canonical_state_hash)
		_check(not hash_run.is_empty(), "X controller run hash non-empty")
		var before: Dictionary = ctl_run.get_snapshot()
		var after: Dictionary = ctl_run.get_snapshot()
		_check(before == after, "X repeated snapshots are identical")
		var metrics: Dictionary = ctl_run.get_metrics()
		_check(bool(metrics.get("success", false)), "X get_metrics succeeds")
		_check(String(ctl_run.get_snapshot().canonical_state_hash) == hash_run, "X snapshot/metrics calls do not mutate state")
		var reset_result: Dictionary = ctl_run.reset()
		_check(bool(reset_result.get("success", false)), "X reset succeeds")
		_check(int(ctl_run.get_snapshot().tick) == 0, "X reset returns to tick 0")
		var rerun: Dictionary = ctl_run.run(64)
		_check(bool(rerun.get("success", false)), "X post-reset run(64) succeeds: " + str(rerun))
		_check(String(ctl_run.get_snapshot().canonical_state_hash) == hash_run, "X reset + rerun reproduces hash")
		# Liveliness at 64 ticks: alive organisms + development growth.
		var state: Dictionary = ctl_run.debug_state()
		_check(_alive(state) >= 1, "X alive organisms >= 1 after 64 ticks")
		_check(_max_modules(state) > 1, "X development growth observed (max modules=%d)" % _max_modules(state))

	# 2. Direct canonical loop from an identical genesis state.
	var ctl_direct := _new_controller(manifest)
	var state: Dictionary = ctl_direct.debug_state()
	var direct_error := ""
	for _i in 64:
		direct_error = _direct_tick(state, manifest)
		if not direct_error.is_empty():
			break
	_check(direct_error.is_empty(), "X direct canonical loop completes 64 ticks: " + direct_error)
	if direct_error.is_empty():
		_check(_canonical_hash(state) == hash_run, "X direct loop hash == controller hash")

	# 3. Time-mode equivalence: 64x step == 4x run(16) == run(64).
	var ctl_step := _new_controller(manifest)
	var step_ok := true
	for i in 64:
		var one: Dictionary = ctl_step.step()
		if not bool(one.get("success", false)):
			step_ok = false
			_check(false, "X step %d fails: %s" % [i, str(one)])
			break
	if step_ok:
		_check(String(ctl_step.get_snapshot().canonical_state_hash) == hash_run, "X 64x step == run(64)")
	var ctl_batch := _new_controller(manifest)
	var batch_ok := true
	for _b in 4:
		var batch: Dictionary = ctl_batch.run(16)
		if not bool(batch.get("success", false)):
			batch_ok = false
			_check(false, "X run(16) batch fails: " + str(batch))
			break
	if batch_ok:
		_check(String(ctl_batch.get_snapshot().canonical_state_hash) == hash_run, "X 4x run(16) == run(64)")

# Scenario R: reproduction liveness + direct-loop equivalence at 12 ticks.

func _scenario_r() -> void:
	var manifest := _manifest(true, 12, 777)
	var ctl := Controller.new()
	var init_result: Dictionary = ctl.initialize(manifest)
	_check(bool(init_result.get("success", false)), "R controller initialize succeeds: " + str(init_result))
	var run_result: Dictionary = ctl.run(12)
	_check(bool(run_result.get("success", false)), "R run(12) succeeds: " + str(run_result))
	if bool(run_result.get("success", false)):
		var state: Dictionary = ctl.debug_state()
		_check(_alive(state) >= 1, "R alive organisms >= 1")
		_check(state.population.size() > 2, "R propagules materialized (population=%d > founders=2)" % state.population.size())
		var hash_run := String(ctl.get_snapshot().canonical_state_hash)
		var ctl_direct := _new_controller(manifest)
		var dstate: Dictionary = ctl_direct.debug_state()
		var direct_error := ""
		for _i in 12:
			direct_error = _direct_tick(dstate, manifest)
			if not direct_error.is_empty():
				break
		_check(direct_error.is_empty(), "R direct loop completes 12 ticks: " + direct_error)
		if direct_error.is_empty():
			_check(_canonical_hash(dstate) == hash_run, "R direct loop hash == controller hash")

func _finish() -> void:
	print("EVO_ARCH2_A10_5_CONTROLLER_P2 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_CONTROLLER_P2 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P2_FAILURE " + failure)
		quit(1)
