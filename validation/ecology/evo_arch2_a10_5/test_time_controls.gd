extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P5 Time controls mandatory test.
# Runner: Godot headless --script; prints checks/failed counts and PASS/FAIL.
# Deterministic equivalence contract (controller command API only, no
# _process / wall-clock dependency):
#   N x step == run(N) == k x run(N/k) == run_to_tick(N) == FAST cadence
#   (20-tick batches) -> identical canonical_state_hash;
#   reset -> run_to_tick(N/2) == hash of the first N/2 ticks of another
#   branch; pause freezes advancement; run(n) advances EXACTLY n ticks;
#   batch pattern (cadence) never affects the hash.
#
# ACTUAL N: 64. The brief's default N=100 is impossible with feedback enabled
# because canonical A6 caps feedback advance at MAX_STEPS=64 (documented
# known limitation). All equivalence modes below are covered at the SAME
# N=64 with assertions NOT weakened.

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")

const N := 64

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P5_FAIL " + message)

func _program(with_reproductive: bool) -> Dictionary:
	var actions := [
		P.action("extend", "support", [0, 100, 0], 10),
		P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
	]
	var rules := [P.rule("r1", actions)]
	if with_reproductive:
		rules[0].next = "r2"
		rules.append(P.rule("r2", [P.action("differentiate", "reproductive", [0, 50, 0], 5)]))
	return {"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 4, "rules": rules}

func _manifest(with_reproductive: bool, horizon: int, seed: int) -> Dictionary:
	var founder := Genome.create(_program(with_reproductive), "founder-a")
	return {
		"schema": "dws.ecology.workbench.experiment-manifest.v1",
		"experiment_id": "eco-polygon/exp-time-x" if not with_reproductive else "eco-polygon/exp-time-r",
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

func _new_controller(manifest: Dictionary, label: String) -> Object:
	var ctl := Controller.new()
	var init_result: Dictionary = ctl.initialize(manifest)
	_check(bool(init_result.get("success", false)), "%s initialize succeeds: %s" % [label, str(init_result)])
	return ctl

func _hash(ctl: Object) -> String:
	return String(ctl.get_snapshot().canonical_state_hash)

func _run() -> void:
	_scenario_equivalence()
	_scenario_generation_condition()
	_finish()

# Scenario X: full time-mode equivalence at N=64 (feedback enabled, A6-capped).

func _scenario_equivalence() -> void:
	var manifest := _manifest(false, N, 777)

	# 1. N x step (one tick per command).
	var ctl_step := _new_controller(manifest, "X step")
	var step_ok := true
	for i in N:
		var one: Dictionary = ctl_step.step()
		if not bool(one.get("success", false)):
			step_ok = false
			_check(false, "X step %d fails: %s" % [i, str(one)])
			break
	if step_ok:
		_check(int(ctl_step.get_snapshot().tick) == N, "X N x step reaches tick N")
	var hash_step := _hash(ctl_step)

	# 2. run(N) in one batch.
	var ctl_run := _new_controller(manifest, "X run")
	var run_result: Dictionary = ctl_run.run(N)
	_check(bool(run_result.get("success", false)), "X run(%d) succeeds" % N)
	_check(_hash(ctl_run) == hash_step, "X run(N) == N x step (same hash)")

	# 3. k x run(N/k) batches.
	var ctl_batch := _new_controller(manifest, "X batch")
	var batch_ok := true
	for _b in 4:
		var batch: Dictionary = ctl_batch.run(N / 4)
		if not bool(batch.get("success", false)):
			batch_ok = false
			_check(false, "X run(%d) batch fails: %s" % [N / 4, str(batch)])
			break
	if batch_ok:
		_check(_hash(ctl_batch) == hash_step, "X 4x run(N/4) == N x step")

	# 4. run_to_tick(N).
	var ctl_target := _new_controller(manifest, "X run_to_tick")
	var target_result: Dictionary = ctl_target.run_to_tick(N)
	_check(bool(target_result.get("success", false)), "X run_to_tick(%d) succeeds" % N)
	_check(int(ctl_target.get_snapshot().tick) == N, "X run_to_tick reaches exactly tick N")
	_check(_hash(ctl_target) == hash_step, "X run_to_tick(N) == N x step")

	# 5. FAST cadence simulated directly: 20-tick batches per wall interval
	#    (20 t/s = 20 ticks per interval; dt never changes).
	var ctl_fast := _new_controller(manifest, "X fast")
	var fast_ok := true
	for batch_size in [20, 20, 20, 4]:
		var batch: Dictionary = ctl_fast.run(batch_size)
		if not bool(batch.get("success", false)):
			fast_ok = false
			_check(false, "X fast cadence batch %d fails: %s" % [batch_size, str(batch)])
			break
	if fast_ok:
		_check(_hash(ctl_fast) == hash_step, "X FAST cadence (20-tick batches) == N x step")
		_check(fast_ok and int(ctl_fast.get_snapshot().tick) == N, "X fast cadence reaches tick N")

	# 6. Two sessions with different cadence patterns agree at every shared
	#    checkpoint tick (wall clock never enters the hash).
	var cadence_a := _new_controller(manifest, "X cadence A (1/interval)")
	var cadence_b := _new_controller(manifest, "X cadence B (20/interval)")
	var cadence_ok := true
	for _i in N:
		if not bool(cadence_a.step().get("success", false)):
			cadence_ok = false
			break
	for batch_size in [20, 20, 20, 4]:
		if not bool(cadence_b.run(batch_size).get("success", false)):
			cadence_ok = false
			break
	if cadence_ok:
		_check(_hash(cadence_a) == _hash(cadence_b), "X different cadences -> identical hash at tick N")

	# 7. Pause freezes advancement.
	var ctl_pause := _new_controller(manifest, "X pause")
	_check(bool(ctl_pause.run(10).get("success", false)), "X pause branch run(10) succeeds")
	var paused: Dictionary = ctl_pause.pause()
	_check(bool(paused.get("success", false)), "pause succeeds")
	_check(String(paused.status) == "PAUSED", "pause transitions RUNNING -> PAUSED")
	var tick_paused := int(ctl_pause.get_snapshot().tick)
	_check(tick_paused == 10, "tick frozen at 10 after pause")
	var snap_a: Dictionary = ctl_pause.get_snapshot()
	var snap_b: Dictionary = ctl_pause.get_snapshot()
	_check(snap_a == snap_b and int(snap_a.tick) == tick_paused, "ticks do not grow while paused")
	_check(bool(ctl_pause.step().get("success", false)), "step resumes from PAUSED")
	_check(int(ctl_pause.get_snapshot().tick) == tick_paused + 1, "resumed step advances by exactly 1")

	# 8. STEP N advances EXACTLY N ticks.
	var ctl_stepn := _new_controller(manifest, "X step n")
	var stepn: Dictionary = ctl_stepn.run(7)
	_check(bool(stepn.get("success", false)), "run(7) succeeds")
	_check(int(ctl_stepn.get_snapshot().tick) == 7, "STEP N advances exactly N ticks (7)")
	var hash_stepn := _hash(ctl_stepn)
	var ctl_stepn_ref := _new_controller(manifest, "X step n ref")
	for _i in 7:
		ctl_stepn_ref.step()
	_check(_hash(ctl_stepn_ref) == hash_stepn, "STEP N == N x step")

	# 9. reset -> run_to_tick(N/2) == first N/2 ticks of another branch.
	var hash_half_ref := ""
	var ctl_half := _new_controller(manifest, "X half ref")
	if bool(ctl_half.run(N / 2).get("success", false)):
		hash_half_ref = _hash(ctl_half)
	_check(not hash_half_ref.is_empty(), "reference branch run(N/2) succeeds")
	var reset_result: Dictionary = ctl_run.reset()
	_check(bool(reset_result.get("success", false)), "reset succeeds after run(N)")
	_check(int(ctl_run.get_snapshot().tick) == 0, "reset returns to tick 0")
	var half_result: Dictionary = ctl_run.run_to_tick(N / 2)
	_check(bool(half_result.get("success", false)), "run_to_tick(N/2) succeeds after reset")
	_check(_hash(ctl_run) == hash_half_ref, "reset -> run_to_tick(N/2) == first N/2 ticks of another branch")

	# 10. Guards: invalid time commands fail closed.
	_check(not bool(ctl_run.run(0).get("success", false)), "run(0) rejected")
	_check(not bool(ctl_run.run_to_tick(ctl_run.get_snapshot().tick - 1).get("success", false)), "run_to_tick backwards rejected")
	_check(not bool(ctl_run.run_to_tick(N + 1).get("success", false)), "run_to_tick beyond horizon rejected")

# Scenario R: run_to_generation / run_to_condition semantics (reproductive).

func _scenario_generation_condition() -> void:
	var manifest := _manifest(true, 12, 777)

	# 1. run_to_generation(1): stops as soon as lineage depth 1 exists.
	var ctl_gen := _new_controller(manifest, "R gen")
	var gen_result: Dictionary = ctl_gen.run_to_generation(1)
	_check(bool(gen_result.get("success", false)), "R run_to_generation(1) succeeds: " + str(gen_result))
	if bool(gen_result.get("success", false)):
		_check(int(gen_result.generation) >= 1, "R generation target reached (depth %d)" % int(gen_result.generation))
		_check(int(ctl_gen.get_snapshot().tick) <= 12, "R generation run stays within the horizon")
		var presentation: Array = ctl_gen.get_snapshot().presentation
		var depth_ok := false
		for view in presentation:
			if int(view.lineage_depth) >= 1 and String(view.parent_id) != "":
				depth_ok = true
		_check(depth_ok, "R presentation carries lineage_depth + parent_id for children")

	# 2. run_to_condition(population_at_least): met exactly.
	var ctl_pop := _new_controller(manifest, "R pop")
	var pop_result: Dictionary = ctl_pop.run_to_condition({"population_at_least": 3})
	_check(bool(pop_result.get("success", false)), "R run_to_condition(population>=3) succeeds: " + str(pop_result))
	_check(bool(pop_result.get("met", false)), "R population condition met")
	_check(int(ctl_pop.get_snapshot().presentation.size()) >= 3, "R population >= 3 when condition stops the run")

	# 3. Already-satisfied condition advances zero ticks.
	var ctl_now := _new_controller(manifest, "R now")
	var now_result: Dictionary = ctl_now.run_to_condition({"population_at_least": 1})
	_check(bool(now_result.get("success", false)) and bool(now_result.get("met", false)), "R trivially-met condition succeeds")
	_check(int(ctl_now.get_snapshot().tick) == 0, "R met condition advances zero ticks")

	# 4. tick condition == run_to_tick equivalence.
	var ctl_tick := _new_controller(manifest, "R tick cond")
	var tick_result: Dictionary = ctl_tick.run_to_condition({"tick": 8})
	_check(bool(tick_result.get("success", false)) and bool(tick_result.get("met", false)), "R tick condition met")
	_check(int(ctl_tick.get_snapshot().tick) == 8, "R tick condition stops at tick 8")

	# 5. Invalid conditions fail closed.
	var ctl_bad := _new_controller(manifest, "R bad cond")
	_check(not bool(ctl_bad.run_to_condition({"bogus": 1}).get("success", false)), "R unknown condition rejected")
	_check(not bool(ctl_bad.run_to_condition({"population_at_least": -1}).get("success", false)), "R negative condition value rejected")

func _finish() -> void:
	print("EVO_ARCH2_A10_5_TIME_P5 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_TIME_P5 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P5_FAILURE " + failure)
		quit(1)
