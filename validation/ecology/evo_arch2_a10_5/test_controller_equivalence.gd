extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P2 ExperimentController equivalence tests
# (repair R1 edition). Runner: Godot headless --script; prints checks/failed
# counts and PASS/FAIL.
#
# ORACLE (repaired): the direct comparison drives the SHARED CANONICAL
# EcologyRuntimeV1 primitives EXPLICITLY — Runtime.step_lifecycle (A5, once)
# -> Runtime.admit_propagules (receipt-only mutation admission) ->
# Runtime.step_feedback (A6 post-lifecycle on the SAME field) — and requires
# the exact same final canonical_state_hash as the controller. The tick
# formulas are NEVER re-implemented in this file: composing canonical APIs is
# the comparison; duplicating controller orchestration would not be an oracle
# (the pre-repair direct loop copied the controller's dual-trajectory scheme
# and its silent mutation fallback, so it proved nothing).
#
# Scenario X (equivalence, 64 ticks): manifest X / seed X, founder program
#   without a reproductive module (bounded population; feedback enabled).
# Scenario R (reproduction + inheritance, 12 ticks): reproductive program;
#   the population grows through canonical receipt-backed propagule
#   admission and at least one child carries a REALLY INHERITED mutated
#   genome (mutation receipt bound to parent+child genome hashes).
# Scenario F (feedback disabled, 8 ticks): the feedback-off path is held to
#   the same single-trajectory oracle.

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const LifeState = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const OrganismState = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
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

func _manifest(with_reproductive: bool, horizon: int, seed: int, feedback_enabled: bool = true) -> Dictionary:
	# Scenario X (equivalence, 64 ticks): single founder, 1x1 field, one zone.
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
		"feedback": {"enabled": feedback_enabled, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
	}

# --- shared canonical runtime oracle (explicit primitive composition) --------

func _build_runtime_state(manifest: Dictionary) -> Dictionary:
	# Genesis through the controller's PUBLIC genesis read, then the shared
	# runtime create: the same canonical genesis, no second genesis formula.
	var genesis_controller := Controller.new()
	var init_result: Dictionary = genesis_controller.initialize(manifest)
	_check(bool(init_result.get("success", false)), "oracle genesis initialize succeeds: " + str(init_result))
	var debug: Dictionary = genesis_controller.debug_state()
	var policy := Feedback.default_policy()
	policy.decomposition_enabled = manifest.feedback.decomposition_enabled
	var created: Dictionary = Runtime.create(String(manifest.experiment_id), debug.field, debug.population, policy, bool(manifest.feedback.enabled))
	_check(bool(created.get("success", false)), "oracle runtime create succeeds: " + str(created))
	return created.get("state", {})

func _runtime_tick(state: Dictionary, manifest: Dictionary) -> Dictionary:
	# Independent canonical composition: each phase is a public runtime
	# primitive; the mutation stream uses the controller's declared key
	# prefix so both sides derive identical deterministic seeds.
	var lifecycle: Dictionary = Runtime.step_lifecycle(state)
	if not bool(lifecycle.get("success", false)):
		return {"success": false, "error": "A5:" + String(lifecycle.get("error", "?"))}
	var admitted: Dictionary = Runtime.admit_propagules(lifecycle.state, {
		"mutations_enabled": manifest.mutation.mutations_enabled,
		"operator": manifest.mutation.operator,
		"seed": manifest.seed,
		"mutation_key_prefix": Controller.MUTATION_KEY_PREFIX,
	})
	if not bool(admitted.get("success", false)):
		return {"success": false, "error": "ADMIT:" + String(admitted.get("error", "?"))}
	var feedback: Dictionary = Runtime.step_feedback(admitted.state)
	if not bool(feedback.get("success", false)):
		return {"success": false, "error": "A6:" + String(feedback.get("error", "?"))}
	return {"success": true, "state": feedback.state}

func _canonical_hash(field: Dictionary, population: Array, feedback_view: Dictionary, tick_value: int) -> String:
	var population_hashes: Array = []
	for entry in population:
		population_hashes.append({
			"individual_id": entry.state.individual_id,
			"life_state_hash": LifeState.state_hash(entry.state, entry.blueprint),
			"development_biological_hash": OrganismState.biological_hash(entry.state.development),
		})
	return C.digest({
		"tick": tick_value,
		"field_hash": Field.state_hash(field),
		"population": population_hashes,
		"feedback_hash": C.digest(feedback_view),
	})

func _controller_hash(controller: Object) -> String:
	var snapshot: Dictionary = controller.get_snapshot()
	return String(snapshot.canonical_state_hash)

func _runtime_hash(state: Dictionary) -> String:
	return _canonical_hash(state.field, state.population, Runtime.feedback_view(state), int(state.tick))

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

func _run() -> void:
	_scenario_x()
	_scenario_r()
	_scenario_f()
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
		hash_run = _controller_hash(ctl_run)
		_check(not hash_run.is_empty(), "X controller run hash non-empty")
		var before: Dictionary = ctl_run.get_snapshot()
		var after: Dictionary = ctl_run.get_snapshot()
		_check(before == after, "X repeated snapshots are identical")
		var metrics: Dictionary = ctl_run.get_metrics()
		_check(bool(metrics.get("success", false)), "X get_metrics succeeds")
		_check(_controller_hash(ctl_run) == hash_run, "X snapshot/metrics calls do not mutate state")
		var reset_result: Dictionary = ctl_run.reset()
		_check(bool(reset_result.get("success", false)), "X reset succeeds")
		_check(int(ctl_run.get_snapshot().tick) == 0, "X reset returns to tick 0")
		var rerun: Dictionary = ctl_run.run(64)
		_check(bool(rerun.get("success", false)), "X post-reset run(64) succeeds: " + str(rerun))
		_check(_controller_hash(ctl_run) == hash_run, "X reset + rerun reproduces hash")
		# Liveliness at 64 ticks: alive organisms + development growth.
		var state: Dictionary = ctl_run.debug_state()
		_check(_alive(state) >= 1, "X alive organisms >= 1 after 64 ticks")
		_check(_max_modules(state) > 1, "X development growth observed (max modules=%d)" % _max_modules(state))

	# 2. Shared canonical runtime composition from the same genesis: the
	#    oracle. Explicit primitives, no controller orchestration.
	var oracle_state: Dictionary = _build_runtime_state(manifest)
	var oracle_error := ""
	for _i in 64:
		var ticked: Dictionary = _runtime_tick(oracle_state, manifest)
		if not bool(ticked.get("success", false)):
			oracle_error = String(ticked.get("error", "?"))
			break
		oracle_state = ticked.state
	_check(oracle_error.is_empty(), "X oracle canonical composition completes 64 ticks: " + oracle_error)
	if oracle_error.is_empty():
		_check(Runtime.validate(oracle_state).is_empty(), "X oracle state validates")
		_check(_runtime_hash(oracle_state) == hash_run, "X oracle (shared runtime) hash == controller hash")

	# 3. Time-mode equivalence: 64x step == 4x run(16) == run(64).
	var ctl_step := Controller.new()
	ctl_step.initialize(manifest)
	var step_ok := true
	for i in 64:
		var one: Dictionary = ctl_step.step()
		if not bool(one.get("success", false)):
			step_ok = false
			_check(false, "X step %d fails: %s" % [i, str(one)])
			break
	if step_ok:
		_check(_controller_hash(ctl_step) == hash_run, "X 64x step == run(64)")
	var ctl_batch := Controller.new()
	ctl_batch.initialize(manifest)
	var batch_ok := true
	for _b in 4:
		var batch: Dictionary = ctl_batch.run(16)
		if not bool(batch.get("success", false)):
			batch_ok = false
			_check(false, "X run(16) batch fails: " + str(batch))
			break
	if batch_ok:
		_check(_controller_hash(ctl_batch) == hash_run, "X 4x run(16) == run(64)")

# Scenario R: reproduction liveness + REAL inherited mutation + oracle.

func _scenario_r() -> void:
	var manifest := _manifest(true, 12, 777)
	var ctl := Controller.new()
	var init_result: Dictionary = ctl.initialize(manifest)
	_check(bool(init_result.get("success", false)), "R controller initialize succeeds: " + str(init_result))
	var founder_genomes := {}
	for entry in ctl.debug_state().population:
		founder_genomes[String(entry.state.individual_id)] = Genome.biological_hash(entry.blueprint.genome)
	var run_result: Dictionary = ctl.run(12)
	_check(bool(run_result.get("success", false)), "R run(12) succeeds: " + str(run_result))
	var inherited := 0
	if bool(run_result.get("success", false)):
		var state: Dictionary = ctl.debug_state()
		_check(_alive(state) >= 1, "R alive organisms >= 1")
		_check(state.population.size() > 2, "R propagules materialized (population=%d > founders=2)" % state.population.size())
		# BLOCKER R2 proof: mutated genomes really enter the lineage through
		# sealed receipts — no silent parent-blueprint fallback exists.
		for entry in state.population:
			if String(entry.state.origin_kind) != "PARENT_TRANSFER":
				continue
			var parent_id := String(entry.state.origin_receipt.parent_id)
			if not founder_genomes.has(parent_id):
				continue
			var child_hash := Genome.biological_hash(entry.blueprint.genome)
			if child_hash == String(founder_genomes[parent_id]):
				continue
			inherited += 1
			var record: Dictionary = entry.state.get("mutation_receipt", {})
			_check(not record.is_empty(), "R inherited child carries durable mutation provenance")
			if record.is_empty():
				continue
			_check(String(record.get("schema", "")) == "dws.ecology.parent-transfer-mutation.v1", "R provenance record schema")
			var receipt: Dictionary = record.get("receipt", {})
			_check(String(receipt.get("child_genome_hash", "")) == child_hash, "R receipt binds the child genome")
			_check(String(receipt.get("parent_genome_hash", "")) == String(founder_genomes[parent_id]), "R receipt binds the parent genome")
			_check(LifeState.validate(entry.state, entry.blueprint).is_empty(), "R inherited child state validates canonically")
		_check(inherited >= 1, "R at least one REALLY INHERITED mutated genome in the lineage (inherited=%d)" % inherited)
		var hash_run := _controller_hash(ctl)
		var oracle_state: Dictionary = _build_runtime_state(manifest)
		var oracle_error := ""
		for _i in 12:
			var ticked: Dictionary = _runtime_tick(oracle_state, manifest)
			if not bool(ticked.get("success", false)):
				oracle_error = String(ticked.get("error", "?"))
				break
			oracle_state = ticked.state
		_check(oracle_error.is_empty(), "R oracle canonical composition completes 12 ticks: " + oracle_error)
		if oracle_error.is_empty():
			_check(_runtime_hash(oracle_state) == hash_run, "R oracle (shared runtime) hash == controller hash")

# Scenario F: feedback disabled — same single-trajectory oracle.

func _scenario_f() -> void:
	var manifest := _manifest(false, 8, 424242, false)
	var ctl := Controller.new()
	ctl.initialize(manifest)
	var run_result: Dictionary = ctl.run(8)
	_check(bool(run_result.get("success", false)), "F controller run(8) succeeds: " + str(run_result))
	var hash_run := _controller_hash(ctl)
	var oracle_state: Dictionary = _build_runtime_state(manifest)
	var oracle_error := ""
	for _i in 8:
		var ticked: Dictionary = _runtime_tick(oracle_state, manifest)
		if not bool(ticked.get("success", false)):
			oracle_error = String(ticked.get("error", "?"))
			break
		oracle_state = ticked.state
	_check(oracle_error.is_empty(), "F oracle canonical composition completes 8 ticks: " + oracle_error)
	if oracle_error.is_empty():
		_check(_runtime_hash(oracle_state) == hash_run, "F oracle (shared runtime, feedback off) hash == controller hash")

func _finish() -> void:
	print("EVO_ARCH2_A10_5_CONTROLLER_P2 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_CONTROLLER_P2 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P2_FAILURE " + failure)
		quit(1)
