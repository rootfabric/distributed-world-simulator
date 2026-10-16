extends SceneTree
## A14.4 bounded real-world load profile at the accepted scale limit (256).
## Wall times are observations, NEVER canonical seeds or tick scheduling inputs.
## Benchmarked results are descriptive and must not be asserted as speedups.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Live = preload("res://scripts/research/ecology/v2/population_budget_live_driver_v1.gd")
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

# Frozen A14.4 R1 3-tick state hashes from independent Linux/Windows exact
# at e826a3f9bea3f2a96a8a98979a65671e25fdd616 (not computed from
# current implementation under test). Fail closed on biological drift.
const GOLDEN_TICK3_SHA256 := {
	4: "52f5b3db3502313ad64d26b5b9ff0aebfe72ca8765ff9d9b2bf93c937c98a92c",
	32: "e49d17c9761025db56218c7ceb2c3da569d8d951cc649dc352adeb888b55e399",
	96: "bb02e20bdc3ddf8c714885673995a11cd573a70adfcca04b23b6d3a069a444d0",
	192: "43c30e4202634ee27f8514028469b09b505cca470e39b9b7801b1d9c939e5f71",
	256: "05c2c2c626f2e37c715581dd80a047aa635b747e4aa33a983c68cdc6798fbc9d",
}
const SIZES := [4, 32, 96, 192, 256]
const TICKS := 3
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_4_PROFILE_FAIL " + label)

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
	_check(not blueprint.is_empty(), "validated stable founder blueprint")
	if blueprint.is_empty():
		_finish()
		return
	for n in SIZES:
		_profile(n, blueprint)
	_finish()

func _profile(n: int, blueprint: Dictionary) -> void:
	var initial: Dictionary = _fixture(n, blueprint)
	_check(not initial.is_empty(), "population=%d constructed at legal scale" % n)
	if initial.is_empty():
		return
	_check(initial.population.size() == n and Runtime.validate(initial).is_empty(),
		"population=%d canonical baseline valid" % n)
	var original: String = C.encode(initial)
	var reference: Dictionary = initial.duplicate(true)
	var reference_us: Array = []
	for i in TICKS:
		var start: int = Time.get_ticks_usec()
		var stepped := Runtime.step_spatial_parallel_advance(reference, _options(), 4, 64, 4, 4)
		reference_us.append(maxi(0, Time.get_ticks_usec() - start))
		_check(bool(stepped.get("success", false)),
			"population=%d reference tick=%d" % [n, i + 1])
		if not bool(stepped.get("success", false)):
			return
		reference = stepped.state

	var cursor: Dictionary = initial.duplicate(true)
	var sliced_us: Array = []
	var peak_us := 0
	var total_exec_us := 0
	var overrun_count := 0
	for i in TICKS:
		var result: Dictionary = Live.advance(cursor, _options(), TICKS,
			1000000000, 1000, 1)
		_check(bool(result.get("success", false)),
			"population=%d live slice=%d" % [n, i + 1])
		if not bool(result.get("success", false)):
			return
		_check(int(result.replayed_ticks) == 1 and int(result.canonical_tick) == i + 1,
			"population=%d one whole canonical tick per call" % n)
		_check(int(result.remaining_debt_ticks) == TICKS - int(result.canonical_tick),
			"population=%d debt accounting exact" % n)
		sliced_us.append(int(result.total_wall_us))
		peak_us = maxi(peak_us, int(result.total_wall_us))
		total_exec_us += int(result.execution_wall_us)
		if int(result.overrun_us) > 0:
			overrun_count += 1
		cursor = result.state

	_check(C.encode(reference) == C.encode(cursor),
		"population=%d global replay equals continuous bytes" % n)
	_check(Runtime.state_hash(reference) == Runtime.state_hash(cursor),
		"population=%d canonical state integrity equal" % n)
	_check(Runtime.state_hash(cursor) == String(GOLDEN_TICK3_SHA256.get(n, "")),
		"population=%d frozen A14.4 three-tick golden state hash" % n)
	var manifest_hash := C.digest({
		"schema": "dws.ecology.a14-4-scale-profile.v1", "population": n})
	var a := Checkpoint.create(manifest_hash, reference)
	var b := Checkpoint.create(manifest_hash, cursor)
	_check(not a.is_empty() and not b.is_empty(),
		"population=%d A8 checkpoints valid" % n)
	if not a.is_empty() and not b.is_empty():
		_check(Checkpoint.serialize(a) == Checkpoint.serialize(b),
			"population=%d serialized checkpoint exact" % n)
	_check(C.encode(initial) == original,
		"population=%d source is immutable" % n)

	var sorted_us: Array = sliced_us.duplicate()
	sorted_us.sort()
	var p95: int = int(sorted_us[maxi(0, int(ceil(0.95 * sorted_us.size())) - 1)])
	var baseline_total := 0
	for ms in reference_us:
		baseline_total += int(ms)
	var report := {
		"population": n, "ticks": TICKS,
		"baseline_parallel_total_wall_us": baseline_total,
		"budgeted_total_wall_us": _sum_us(sliced_us),
		"budgeted_execution_total_wall_us": total_exec_us,
		"budgeted_peak_slice_wall_us": peak_us,
		"budgeted_p95_slice_wall_us": p95,
		"overrun_calls": overrun_count,
		"final_state_hash": Runtime.state_hash(cursor),
		"checkpoint_equal": not a.is_empty() and not b.is_empty() \
			and Checkpoint.serialize(a) == Checkpoint.serialize(b),
	}
	print("ECO_A14_4_PROFILE_JSON " + JSON.stringify(report))

func _sum_us(values: Array) -> int:
	var amount := 0
	for x in values:
		amount += int(x)
	return amount

func _finish() -> void:
	print("ECO_ARCH2_A14_4_PROFILE checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_4_PROFILE " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
