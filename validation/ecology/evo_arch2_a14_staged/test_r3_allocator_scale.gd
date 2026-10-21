extends SceneTree
## ECO A14.6 R3 opt-in LAB-like staged A4 latency and exact scale evidence.
## Each sample is host wall time (NOT CPU-time/hard deadline), separate
## from the canonical field/population/checkpoint and all RNG seeds.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Session = preload("res://scripts/ecology/workbench/staged_frame_session_v1.gd")
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
		push_error("ECO_A14_6_R3_SCALE_FAIL " + label)

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
	_check(not blueprint.is_empty(), "real biological founder fixture valid")
	if blueprint.is_empty():
		_finish()
		return
	for n in [4, 32, 96, 256]:
		_profile(n, blueprint)
	_finish()

func _run_session(initial: Dictionary, options: Dictionary,
		r3: bool, allocator_quota: int = 64) -> Dictionary:
	var session = Session.new()
	var final: Dictionary = {}
	var wall_total := 0
	var max_frame_us := 0
	var resumes := 0
	var allocator_pending := 0
	var stages := {}
	for frame in 120:
		var started_us: int = Time.get_ticks_usec()
		var step: Dictionary = session.advance(initial, options,
			1000000000, 1, 1, 64, 8388608, r3, allocator_quota)
		var sampled_wall: int = maxi(0, Time.get_ticks_usec() - started_us)
		_check(bool(step.get("success", false)),
			"n=%d mode=%s frame=%d: %s" % [
				initial.population.size(), "R3" if r3 else "LEGACY",
				frame, String(step.get("error", ""))])
		if not bool(step.get("success", false)):
			return {}
		wall_total += sampled_wall
		max_frame_us = maxi(max_frame_us, sampled_wall)
		resumes += 1
		var t: Dictionary = session.status()
		stages[String(t.phase)] = true
		if r3 and String(t.phase) == "ALLOCATE":
			allocator_pending += 1
		if bool(step.get("complete", false)):
			final = step.state
			break
		_check(not step.has("state")
			and int(step.get("replayed_ticks", -1)) == 0,
			"n=%d mode=%s pending frame cannot publish canonical state" % [
				initial.population.size(), "R3" if r3 else "LEGACY"])
	_check(not final.is_empty(),
		"n=%d mode=%s full global tick eventually completed" %
		[initial.population.size(), "R3" if r3 else "LEGACY"])
	if final.is_empty():
		return {}
	var telemetry: Dictionary = session.status()
	_check(int(telemetry.completed_ticks) == 1
		and not bool(telemetry.pending)
		and int(telemetry.cancellations) == 0,
		"completion is one successful tick and not cancellation")
	_check(int(telemetry.peak_cursor_bytes) > 0
		and int(telemetry.peak_cursor_bytes) <= 8388608,
		"nested R2 + A5 cursor fits host byte cap")
	# The final ADVANCE may complete the tick and immediately reset
	# status.phase to NONE. Use measured execution counters, not an
	# already-closed cursor's presentation state, for the exact witness.
	_check(int(telemetry.phase_stats.PREPARE.samples) > 0
		and int(telemetry.phase_stats.ALLOCATE.samples) > 0
		and int(telemetry.phase_stats.ADVANCE.samples) > 0,
		"all global tick stages actually executed (including terminal ADVANCE)")
	if r3:
		_check(allocator_pending > 1 and int(telemetry.r3_allocator_calls) > 4,
			"R2 allocator materially resumes across host frame boundaries")
		for sub in ["BEGIN", "NORMALIZE", "BUILD_CLAIMS", "PRIMARY",
				"RESIDUAL", "FINALIZE"]:
			_check(int(telemetry.r3_allocator_phase_stats[sub].samples) > 0,
				"actual R2 global A4 subphase %s measured" % sub)
	return {"success": true, "state": final,
		"wall_total_us": wall_total, "peak_frame_us": max_frame_us,
		"resume_calls": resumes, "telemetry": telemetry,
		"allocator_pending": allocator_pending}

func _profile(n: int, blueprint: Dictionary) -> void:
	var initial: Dictionary = _fixture(n, blueprint)
	_check(not initial.is_empty() and initial.population.size() == n,
		"population %d authentic canonical fixture" % n)
	if initial.is_empty():
		return
	var immutable: String = C.encode(initial)
	var options: Dictionary = _options()
	var t0: int = Time.get_ticks_usec()
	var baseline: Dictionary = Runtime.step_spatial_parallel_advance(
		initial, options, 4, 64, 4, 4)
	var baseline_us: int = maxi(0, Time.get_ticks_usec() - t0)
	_check(bool(baseline.get("success", false)),
		"n=%d accepted global A5/A6 serial barrier reference" % n)
	if not bool(baseline.get("success", false)):
		return
	var legacy: Dictionary = _run_session(initial, options, false)
	var staged: Dictionary = _run_session(initial, options, true, 64)
	if not bool(legacy.get("success", false)) \
			or not bool(staged.get("success", false)):
		return
	_check(C.encode(staged.state) == C.encode(legacy.state)
		and C.encode(staged.state) == C.encode(baseline.state),
		"n=%d R3 LAB A4 exact canonical bytes to legacy and A14.5" % n)
	var h: String = Runtime.state_hash(staged.state)
	_check(h == Runtime.state_hash(legacy.state)
		and h == Runtime.state_hash(baseline.state),
		"n=%d all canonical hash types match" % n)
	var anchor := C.digest({"schema": "dws.ecology.a14-6-r3-lab-profile.v1", "n": n})
	var a: Dictionary = Checkpoint.create(anchor, baseline.state)
	var b: Dictionary = Checkpoint.create(anchor, staged.state)
	var c: Dictionary = Checkpoint.create(anchor, legacy.state)
	_check(not a.is_empty() and not b.is_empty() and not c.is_empty()
		and Checkpoint.serialize(a) == Checkpoint.serialize(b)
		and Checkpoint.serialize(a) == Checkpoint.serialize(c),
		"n=%d A8 checkpoint byte parity R3/legacy/original" % n)
	_check(C.encode(initial) == immutable and int(initial.tick) == 0,
		"n=%d full source unchanged by any speculative stage" % n)
	var t: Dictionary = staged.telemetry
	_check(int(t.r3_allocator_calls) >= 6
		and int(t.phase_stats.ALLOCATE.samples) >= 6,
		"n=%d repeated global A4 resume calls observed" % n)
	# Observations only; time measurements never alter the canonical RNG,
	# source state, checkpoint, or biological scheduling decisions.
	print("ECO_A14_6_R3_PROFILE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a14-6-r3-live-stage-benchmark.v1",
		"population": n,
		"baseline_parallel_wall_us": baseline_us,
		"accepted_legacy_staged_total_us": int(legacy.wall_total_us),
		"r3_staged_allocator_total_us": int(staged.wall_total_us),
		"accepted_legacy_peak_frame_us": int(legacy.peak_frame_us),
		"r3_peak_frame_us": int(staged.peak_frame_us),
		"legacy_resume_calls": int(legacy.resume_calls),
		"r3_resume_calls": int(staged.resume_calls),
		"r3_alloc_substep_calls": int(t.r3_allocator_calls),
		"r3_alloc_pending_frames": int(staged.allocator_pending),
		"r3_allocator_phase_stats": t.r3_allocator_phase_stats,
		"r3_global_stage_stats": t.phase_stats,
		"r3_peak_cursor_bytes": int(t.peak_cursor_bytes),
		"canonical_hash": h,
		"checkpoint_equal": not a.is_empty() and not b.is_empty() and
			Checkpoint.serialize(a) == Checkpoint.serialize(b),
		"source_unchanged": C.encode(initial) == immutable,
		"hard_deadline_claim": false,
		"world_compat_activated": false,
	}))

func _finish() -> void:
	print("ECO_ARCH2_A14_6_R3_SCALE checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_6_R3_SCALE " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
