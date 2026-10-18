extends SceneTree
## ECO A14.5 R2 — standalone portable/exact latency and cursor integrity proof.
## Timings are host-only observations, not simulation/RNG inputs.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeHistory = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")

const POPULATIONS := [4, 32, 96, 192, 256]
const R2_SCHEMA := "dws.ecology.staged-global-tick.v2"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ECO_A14_5_R2_FAIL " + label)

func _options() -> Dictionary:
	return {"mutations_enabled": false, "seed": 20261015}

func _stable_blueprint() -> Dictionary:
	var program := {
		"schema": Program.SCHEMA, "entry": "grow", "max_age": 64,
		"max_depth": 1, "rules": [Program.rule("grow", [
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
	life.reproduction.endowment = {
		"material_mg": 100, "water_mg": 100, "energy_mj": 100}
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
		var x: int = (i % 8) * 1000 + 500
		var z: int = (int(i / 8) % 8) * 1000 + 500
		var entry := Lifecycle.individual(
			blueprint, "a14-4-founder-%03d" % i, [x, 0, z],
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000})
		if entry.is_empty():
			return {}
		population.append(entry)
	var created := Runtime.create("eco/a14-4/stress/v1", field, population,
		Feedback.default_policy(), false)
	return created.state if bool(created.get("success", false)) else {}



func _run() -> void:
	var blueprint := _stable_blueprint()
	_check(not blueprint.is_empty(), "canonical fixture")
	if blueprint.is_empty():
		_finish()
		return
	for population in POPULATIONS:
		_evaluate(population, blueprint)
	_finish()

func _evaluate(n: int, blueprint: Dictionary) -> void:
	var state: Dictionary = _fixture(n, blueprint)
	_check(not state.is_empty(), "population %d initialized" % n)
	if state.is_empty():
		return
	var options: Dictionary = _options()
	var original := C.encode(state)
	var members: int = 64 if n >= 192 else 16
	var quota: int = 2 if n >= 192 else 1

	var reference_start := Time.get_ticks_usec()
	var ref := Runtime.step_spatial_parallel_advance(state, options, 4, members, 4, 4)
	var reference_wall_us := maxi(0, Time.get_ticks_usec() - reference_start)
	_check(bool(ref.get("success", false)), "n=%d canonical parallel reference" % n)
	if not bool(ref.get("success", false)):
		return

	var begin_started := Time.get_ticks_usec()
	var started := Runtime.begin_staged_global_tick(state, options, 4, members)
	var begin_wall_us := maxi(0, Time.get_ticks_usec() - begin_started)
	_check(bool(started.get("success", false)), "n=%d staged begin" % n)
	if not bool(started.get("success", false)):
		return
	var initial_cursor: Dictionary = started.cursor
	var initial_cursor_bytes := C.encode(initial_cursor)
	_check(not initial_cursor_bytes.is_empty()
		and String(initial_cursor.schema) == R2_SCHEMA,
		"n=%d versioned transient cursor" % n)

	# Independently construct the compact outer digest, without reading the
	# Runtime helper. All deep lifecycle bytes remain protected by its own
	# canonical checksum, verified in the lifecycle phase.
	var expected_outer := C.digest({
		"schema": R2_SCHEMA,
		"source_hash": String(initial_cursor.source_hash),
		"options_hash": String(initial_cursor.options_hash),
		"lifecycle_checksum": String(initial_cursor.lifecycle.checksum),
	})
	_check(String(initial_cursor.checksum) == expected_outer,
		"n=%d compact envelope includes lifecycle integrity checksum" % n)

	# A historically valid R1 envelope is explicitly rejected on upgrade;
	# in-flight cursor data is noncanonical and never checkpointed.
	var legacy_version: Dictionary = initial_cursor.duplicate(true)
	legacy_version.schema = "dws.ecology.staged-global-tick.v1"
	var denied_legacy := Runtime.resume_staged_global_tick(
		state, options, legacy_version, quota)
	_check(not bool(denied_legacy.get("success", false))
		and String(denied_legacy.get("error", "")) == "RUNTIME_STAGED_CURSOR_SCHEMA",
		"n=%d pre-R2 cursor fails closed" % n)

	var inner_tamper: Dictionary = initial_cursor.duplicate(true)
	inner_tamper.lifecycle.index = 99
	# Envelope checksum still matches (inner checksum unchanged).
	var bad_inner := Runtime.resume_staged_global_tick(
		state, options, inner_tamper, quota)
	_check(not bool(bad_inner.get("success", false))
		and "A5_STAGED_CURSOR_CHECKSUM" in String(bad_inner.get("error", "")),
		"n=%d nested mutation detected by inner checksum" % n)

	var inner_digest_tamper: Dictionary = initial_cursor.duplicate(true)
	inner_digest_tamper.lifecycle.checksum = "0".repeat(64)
	var bad_inner_digest := Runtime.resume_staged_global_tick(
		state, options, inner_digest_tamper, quota)
	_check(not bool(bad_inner_digest.get("success", false))
		and String(bad_inner_digest.get("error", "")) == "RUNTIME_STAGED_CURSOR_CHECKSUM",
		"n=%d outer checksum binds exact inner digest" % n)

	var invalid_opts: Dictionary = options.duplicate(true)
	invalid_opts.seed = int(options.seed) + 1
	_check(not bool(Runtime.resume_staged_global_tick(
		state, invalid_opts, initial_cursor, quota).get("success", false)),
		"n=%d changed options rejected" % n)
	_check(not bool(Runtime.resume_staged_global_tick(
		ref.state, options, initial_cursor, quota).get("success", false)),
		"n=%d changed canonical frontier rejected" % n)

	# Demonstrate that no call mutates either its caller's cursor or the
	# authoritative state, including twice replaying the SAME resume step.
	var replay_a := Runtime.resume_staged_global_tick(
		state, options, initial_cursor, quota)
	var replay_b := Runtime.resume_staged_global_tick(
		state, options, initial_cursor, quota)
	_check(bool(replay_a.get("success", false))
		and bool(replay_b.get("success", false))
		and C.encode(replay_a) == C.encode(replay_b),
		"n=%d repeat resume deterministic and detached" % n)
	_check(C.encode(initial_cursor) == initial_cursor_bytes,
		"n=%d original cursor immutable on resume" % n)

	# Focused microbenchmark of R1's repeated full nested checksum+copy,
	# measured alongside R2's compact envelope on the exact same cursor.
	var r1_start := Time.get_ticks_usec()
	var old_owned: Dictionary = initial_cursor.duplicate(true)
	old_owned.checksum = ""
	var full_payload_hash := C.digest(old_owned)
	var r1_outer_us := maxi(0, Time.get_ticks_usec() - r1_start)
	var r2_start := Time.get_ticks_usec()
	var compact_hash := C.digest({
		"schema": R2_SCHEMA, "source_hash": String(initial_cursor.source_hash),
		"options_hash": String(initial_cursor.options_hash),
		"lifecycle_checksum": String(initial_cursor.lifecycle.checksum)})
	var r2_outer_us := maxi(0, Time.get_ticks_usec() - r2_start)
	_check(not full_payload_hash.is_empty() and compact_hash == expected_outer,
		"n=%d measured full and compact hashes valid" % n)

	var phases := {"PREPARE": [], "ALLOCATE": [], "ADVANCE": []}
	var cursor: Dictionary = initial_cursor
	var final: Dictionary = {}
	var calls := 0
	var max_cursor_bytes := initial_cursor_bytes.to_utf8_buffer().size()
	for attempt in 96:
		var phase := String(cursor.lifecycle.phase)
		if not phases.has(phase):
			_check(false, "n=%d unexpected stage %s" % [n, phase])
			return
		var call_started := Time.get_ticks_usec()
		var progressed := Runtime.resume_staged_global_tick(
			state, options, cursor, quota)
		var wall_us := maxi(0, Time.get_ticks_usec() - call_started)
		phases[phase].append(wall_us)
		calls += 1
		_check(bool(progressed.get("success", false)),
			"n=%d stage %s call %d" % [n, phase, attempt])
		if not bool(progressed.get("success", false)):
			return
		_check(C.encode(state) == original,
			"n=%d authoritative truth unchanged until publication" % n)
		if bool(progressed.get("complete", false)):
			final = progressed
			break
		_check(not progressed.has("state"),
			"n=%d partial cursor cannot publish state" % n)
		cursor = progressed.cursor
		var encoded := C.encode(cursor)
		_check(not encoded.is_empty(), "n=%d canonical cursor encoding" % n)
		max_cursor_bytes = maxi(max_cursor_bytes, encoded.to_utf8_buffer().size())
	_check(bool(final.get("complete", false)),
		"n=%d stage sequence completed" % n)
	if not bool(final.get("complete", false)):
		return
	_check(phases.PREPARE.size() > 0 and phases.ALLOCATE.size() == 1
		and phases.ADVANCE.size() > 0,
		"n=%d global allocator executed exactly once" % n)
	_check(C.encode(final.state) == C.encode(ref.state),
		"n=%d staged state exact to reference" % n)
	_check(Runtime.state_hash(final.state) == Runtime.state_hash(ref.state),
		"n=%d exact state hash" % n)
	var anchor := C.digest({"schema": "dws.ecology.a14-5-r2-profile.v1", "n": n})
	var a := Checkpoint.create(anchor, ref.state)
	var b := Checkpoint.create(anchor, final.state)
	_check(not a.is_empty() and not b.is_empty()
		and Checkpoint.serialize(a) == Checkpoint.serialize(b),
		"n=%d A8 checkpoint bytes remain exact" % n)

	var stats := {}
	for phase in phases:
		stats[phase] = _stats(phases[phase])
	print("ECO_A14_5_R2_PROFILE_JSON " + JSON.stringify({
		"population": n,
		"reference_wall_us": reference_wall_us,
		"begin_wall_us": begin_wall_us,
		"resume_calls": calls,
		"max_cursor_bytes": max_cursor_bytes,
		"legacy_outer_deepcopy_hash_us": r1_outer_us,
		"r2_compact_envelope_hash_us": r2_outer_us,
		"phase_wall_us": stats,
		"checkpoint_equal": not a.is_empty() and not b.is_empty()
			and Checkpoint.serialize(a) == Checkpoint.serialize(b),
		"source_unchanged": C.encode(state) == original,
	}))

func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"calls": 0, "p50": 0, "p95": 0, "p99": 0, "peak": 0, "total": 0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var total := 0
	for value in sorted:
		total += int(value)
	return {
		"calls": sorted.size(), "p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95),
		"p99": _percentile(sorted, 0.99),
		"peak": int(sorted[sorted.size() - 1]), "total": total,
	}

func _percentile(sorted: Array, p: float) -> int:
	return int(sorted[maxi(0, int(ceil(float(sorted.size()) * p)) - 1)])

func _finish() -> void:
	print("ECO_ARCH2_A14_5_R2 checks=%d failed=%d" % [checks, failures])
	print("ECO_ARCH2_A14_5_R2 " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
