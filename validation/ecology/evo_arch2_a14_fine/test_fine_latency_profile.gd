extends SceneTree
## ECO ARCH2 A14.6 R1 fine-grained read-only A5 phase profiling.
## Each sample is host wall time (NOT CPU-time/hard deadline), separate
## from the canonical field/population/checkpoint and all RNG seeds.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Fine = preload("res://scripts/research/ecology/v2/a5_fine_latency_profiler_v1.gd")
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
		push_error("ECO_A14_6_FINE_FAIL " + label)

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
	_check(not blueprint.is_empty(), "A14.6 stable canonical fixture blueprint")
	if blueprint.is_empty():
		_finish()
		return
	var profile_invalid: Dictionary = Fine.profile_tick({}, _options())
	_check(not bool(profile_invalid.get("success", false)),
		"invalid Runtime source refuses measurement before any execution")
	for n in SIZES:
		_measure(n, blueprint)
	_finish()

func _measure(n: int, blueprint: Dictionary) -> void:
	var original: Dictionary = _fixture(n, blueprint)
	_check(not original.is_empty() and original.population.size() == n,
		"n=%d accepted 256-cap fixture admitted" % n)
	if original.is_empty():
		return
	var original_bytes: String = C.encode(original)
	var options_before: String = C.encode(_options())
	var measurement: Dictionary = Fine.profile_tick(original, _options(), 64)
	_check(bool(measurement.get("success", false)),
		"n=%d diagnostic profile succeeds" % n)
	if not bool(measurement.get("success", false)):
		push_error("A14_6_PROFILE_ERROR n=%d error=%s" % [n, measurement.get("error", "?")])
		return
	var result: Dictionary = measurement.profile
	_check(String(result.schema) == Fine.SCHEMA,
		"n=%d versioned measurement evidence" % n)
	_check(int(result.population) == n and int(result.committed_tick) == 1
		and int(result.global_allocation_calls) == 1,
		"n=%d one full tick through exactly one global A5 barrier" % n)
	_check(bool(result.source_unchanged) and bool(result.checkpoint_equal),
		"n=%d source untouched and external A8 bytes equal" % n)
	_check(C.encode(original) == original_bytes and C.encode(_options()) == options_before,
		"n=%d wall measurements do not affect input or RNG" % n)
	_check(String(result.canonical_hash).length() == 64
		and String(result.source_hash).length() == 64,
		"n=%d canonical and input hash are present" % n)
	_check(String(result.frontier_hash).length() == 64
		and int(result.residual_buckets) >= 0,
		"n=%d allocator dependencies measured" % n)
	_check(int(result.max_cursor_bytes) > 0
		and int(result.max_cursor_bytes) <= Fine.MAX_CURSOR_BYTES,
		"n=%d cursor bounded measurement payload" % n)
	_check(int(result.demands) >= 0
		and int(result.source_validate_wall_us) >= 0
		and int(result.independent_a4_allocate_wall_us) >= 0
		and int(result.separate_admission_wall_us) >= 0
		and int(result.separate_feedback_wall_us) >= 0,
		"n=%d real subphase wall times valid" % n)
	var rows: Array = result.phase_samples
	_check(rows.size() == 2 * int(result.worksets) + 1,
		"n=%d each workset PREPARE and ADVANCE measured individually" % n)
	var saw := {"PREPARE": 0, "ALLOCATE": 0, "ADVANCE": 0}
	var max_member_count := 0
	for row in rows:
		var phase: String = String(row.phase)
		_check(saw.has(phase), "n=%d known stage" % n)
		if not saw.has(phase):
			continue
		saw[phase] += 1
		_check(int(row.wall_us) >= 0 and int(row.cursor_bytes_before) >= 0,
			"n=%d each stage has real monotonic wall and byte measurements" % n)
		if phase != "ALLOCATE":
			max_member_count = maxi(max_member_count, int(row.member_count))
			_check(int(row.workset_index) >= 0 and int(row.member_count) > 0,
				"n=%d workset index and cardinality" % n)
	_check(int(saw.PREPARE) == int(result.worksets)
		and int(saw.ADVANCE) == int(result.worksets)
		and int(saw.ALLOCATE) == 1
		and max_member_count <= 64,
		"n=%d exact stage count and workset membership bound" % n)
	for phase in ["PREPARE", "ALLOCATE", "ADVANCE"]:
		var stats: Dictionary = result.phase_stats[phase]
		_check(int(stats.calls) == int(saw[phase]) and int(stats.p50_us) >= 0
			and int(stats.p95_us) >= int(stats.p50_us)
			and int(stats.p99_us) >= int(stats.p95_us)
			and int(stats.peak_us) >= int(stats.p99_us),
			"n=%d stage %s p50/p95/p99/peak invariant" % [n, phase])
	# Unbounded, expensive diagnostic timings are observations, not speedup
	# or real-time acceptance gates. Output complete raw workset data.
	print("ECO_A14_6_FINE_PROFILE_JSON " + JSON.stringify(result))

func _finish() -> void:
	print("ECO_ARCH2_A14_6_FINE checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_6_FINE " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
