extends SceneTree
## ECO A14.6 R3.2 off-main full canonical A4/A5/A6 worker scale proof.
## Each sample is host wall time (NOT CPU-time/hard deadline), separate
## from the canonical field/population/checkpoint and all RNG seeds.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeHistory = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")

const SIZES := [4, 32, 96, 256]
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_6_R32_SCALE_FAIL " + label)

func _options() -> Dictionary:
	return {"mutations_enabled": false, "seed": 20261015}

func _stable_blueprint() -> Dictionary:
	var program := {
		"schema": Program.SCHEMA, "entry": "grow", "max_age": 64,
		"max_depth": 1,
		"rules": [Program.rule("grow", [
			Program.action("differentiate", "collector", [0, 2, 0], 1, 10000),
			Program.action("differentiate", "absorber", [0, -2, 0], 1, 0, 100),
			Program.action("differentiate", "reproductive", [2, 0, 0], 1),
			Program.action("retire"),
		])],
	}
	var genome := Genome.create(program, "a14-4 scale profile stable founder")
	var life := LifeHistory.create_default()
	life.regulation.growth_light_min = 0
	life.regulation.growth_water_min = 0
	life.regulation.growth_competition_max = 1000
	life.regulation.growth_temperature_min = 0
	life.regulation.growth_temperature_max = 1000
	life.metabolism.maintenance_energy_per_module_mj = 0
	life.metabolism.maintenance_water_per_module_mg = 0
	life.growth.transfer_permille = 500
	life.reproduction.maturity_ticks = 1000
	life.reproduction.interval_ticks = 2
	life.reproduction.required_reproductive_modules = 1
	life.reproduction.offspring_per_event = 1
	life.reproduction.endowment = {"material_mg": 100, "water_mg": 100, "energy_mj": 100}
	life.reproduction.fee_energy_mj = 0
	return Blueprint.create(genome, life)

func _fixture(n: int, blueprint: Dictionary) -> Dictionary:
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a14-4.profile", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	if field.is_empty():
		return {}
	var population: Array = []
	for i in n:
		var pos := [(i % 8) * 1000 + 500, 0, (int(i / 8) % 8) * 1000 + 500]
		var member := Lifecycle.individual(
			blueprint, "a14-4-founder-%03d" % i, pos,
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		if member.is_empty():
			return {}
		population.append(member)
	var created := Runtime.create("eco/a14-4/stress/v1", field, population,
		Feedback.default_policy(), false)
	return created.state if bool(created.get("success", false)) else {}

func _run() -> void:
	var blueprint: Dictionary = _stable_blueprint()
	_check(not blueprint.is_empty(), "legal canonical 4–256 organism fixture")
	if blueprint.is_empty():
		_finish()
		return
	for n in SIZES:
		await _profile(n, blueprint)
	_finish()

func _profile(n: int, blueprint: Dictionary) -> void:
	var source: Dictionary = _fixture(n, blueprint)
	_check(not source.is_empty() and source.population.size() == n,
		"n=%d canonical founder state" % n)
	if source.is_empty():
		return
	var original_bytes: String = C.encode(source)
	var options: Dictionary = _options()
	var baseline: Dictionary = Runtime.step_spatial_parallel_advance(
		source, options, 4, 64, 4, 4)
	_check(bool(baseline.get("success", false)),
		"n=%d accepted original global A5/A4/A6 baseline" % n)
	if not bool(baseline.get("success", false)):
		return
	var session = OffMain.new()
	var start: int = Time.get_ticks_usec()
	var dispatched: Dictionary = session.advance(source, options, 64, 4096, 8388608)
	var dispatch_us: int = maxi(0, Time.get_ticks_usec() - start)
	_check(bool(dispatched.get("success", false))
		and not bool(dispatched.get("complete", true))
		and not dispatched.has("state") and session.has_pending(),
		"n=%d pending worker cannot reveal or commit partial canonical state" % n)
	if not bool(dispatched.get("success", false)):
		return
	var max_poll := 0
	var polls := 0
	var result: Dictionary = {}
	for frame in 12000:
		var t: int = Time.get_ticks_usec()
		var next: Dictionary = session.advance(source, options, 64, 4096, 8388608)
		max_poll = maxi(max_poll, Time.get_ticks_usec() - t)
		polls += 1
		_check(bool(next.get("success", false)),
			"n=%d worker poll %d: %s" %
			[n, frame, String(next.get("error", ""))])
		if not bool(next.get("success", false)):
			break
		if bool(next.get("complete", false)):
			result = next
			break
		_check(not next.has("state") and not next.has("grants"),
			"n=%d pending frame never publishes partial global grants" % n)
		await create_timer(0.02).timeout
	_check(not result.is_empty(), "n=%d CPU worker completes global tick" % n)
	if result.is_empty():
		session.cancel()
		return
	_check(not session.has_pending() and not session.is_draining()
		and int(session.status().tasks_joined) == 1,
		"n=%d task joined once, no retained background worker" % n)
	_check(C.encode(result.state) == C.encode(baseline.state)
		and Runtime.state_hash(result.state) == Runtime.state_hash(baseline.state),
		"n=%d full global Runtime bytes/hash exactly match accepted baseline" % n)
	var anchor: String = C.digest({
		"schema": "dws.ecology.a14-6-r32-offmain-scale.v1",
		"population": n})
	var checkpoint_original: Dictionary = Checkpoint.create(anchor, baseline.state)
	var checkpoint_worker: Dictionary = Checkpoint.create(anchor, result.state)
	_check(not checkpoint_original.is_empty()
		and not checkpoint_worker.is_empty()
		and Checkpoint.serialize(checkpoint_original) ==
			Checkpoint.serialize(checkpoint_worker),
		"n=%d A8 serialized checkpoint exact with accepted synchronous A5" % n)
	_check(C.encode(source) == original_bytes and int(source.tick) == 0,
		"n=%d immutable source never mutates during background A4" % n)
	var status: Dictionary = session.status()
	_check(int(status.jobs_started) == 1
		and int(status.jobs_committed) == 1
		and int(status.jobs_failed) == 0,
		"n=%d one job, one complete publication, zero failure" % n)
	print("ECO_A14_6_R32_SCALE_PROFILE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a14-6-r32-offmain-scale-observation.v1",
		"population": n,
		"dispatch_wall_us": dispatch_us,
		"peak_main_poll_us": max_poll,
		"worker_wall_us": int(result.worker_wall_us),
		"poll_count": polls,
		"canonical_hash": Runtime.state_hash(result.state),
		"checkpoint_equal": not checkpoint_original.is_empty() and
			not checkpoint_worker.is_empty() and
			Checkpoint.serialize(checkpoint_original) ==
				Checkpoint.serialize(checkpoint_worker),
		"source_unchanged": C.encode(source) == original_bytes,
		"hard_frame_deadline_claim": false,
		"cpu_throughput_speedup_claim": false,
	}))

func _finish() -> void:
	print("ECO_ARCH2_A14_6_R32_SCALE checks=%d failed=%d" %
		[checks, failed])
	print("ECO_ARCH2_A14_6_R32_SCALE " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
