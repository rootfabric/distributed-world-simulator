extends SceneTree
## Separate, independent A14.3 verifier fixture, not imported from R1 tests.
## Confirms global exactness, fail-closed budget accounting, fair preparation.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Budget = preload("res://scripts/research/ecology/v2/population_cpu_budget_wake_v1.gd")
const Priority = preload("res://scripts/research/ecology/v2/population_wake_priority_v1.gd")
const Fidelity = preload("res://scripts/research/ecology/v2/population_fidelity_schedule_plan_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")
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

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_verify")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_3_INDEPENDENT_FAIL " + label)

func options() -> Dictionary:
	return {"mutations_enabled": false, "seed": 20261014}

func fixture() -> Dictionary:
	var program := {
		"schema": Program.SCHEMA, "entry": "grow", "max_age": 64,
		"max_depth": 1, "rules": [Program.rule("grow", [
			Program.action("differentiate", "collector", [0, 2, 0], 1, 10000),
			Program.action("differentiate", "absorber", [0, -2, 0], 1, 0, 100),
			Program.action("differentiate", "reproductive", [2, 0, 0], 1),
			Program.action("retire"),
		])],
	}
	var genome := Genome.create(program, "a14-3-independent-fixture")
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
	var blueprint := Blueprint.create(genome, life)
	var stock := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(
		"a14-3-independent.field", 1, [0, 0, 0], 1000, 8, 8,
		stock, stock, FieldContract.signals(1000, 500, 0, 0))
	if blueprint.is_empty() or field.is_empty():
		return {}
	var population: Array = []
	var positions := [
		[500, 0, 500], [4500, 0, 500],
		[500, 0, 4500], [4500, 0, 4500],
	]
	for i in positions.size():
		population.append(Lifecycle.individual(blueprint,
			"a14-3-independent-%d" % i, positions[i],
			{"material_mg": 100000, "water_mg": 100000, "energy_mj": 100000}))
	var built := Runtime.create(
		"eco/a14-3/independent/v1", field, population,
		Feedback.default_policy(), false)
	return built.state if bool(built.get("success", false)) else {}

func _verify() -> void:
	var initial := fixture()
	check(not initial.is_empty(), "valid independent runtime")
	if initial.is_empty():
		_finish()
		return
	_verify_exact_and_falsifiers(initial)
	_verify_wake_priority(initial)
	_finish()

func _verify_exact_and_falsifiers(initial: Dictionary) -> void:
	var before := C.encode(initial)
	var cp_anchor := C.digest({"schema": "dws.ecology.a14-3-independent-checkpoint.v1"})
	var ref := initial.duplicate(true)
	var refs := {}
	for i in 5:
		var step := Runtime.step_spatial_parallel_advance(ref, options(), 4, 64, 4, 4)
		check(bool(step.get("success", false)), "independent continuous tick=%d" % (i + 1))
		if not bool(step.get("success", false)):
			return
		ref = step.state
		refs[int(ref.tick)] = C.encode(ref)
	var first := Fidelity.create(initial.field, initial.population, {}, 0, 5, 4, 16, 4, 64)
	check(not first.is_empty(), "FULL fidelity owed five")
	if first.is_empty():
		return
	var starved := Budget.create(initial, first, 3, 2, 2)
	check(not starved.is_empty(), "budget below one whole tick")
	if starved.is_empty():
		return
	check(int(starved.allowed_ticks) == 0 and int(starved.remaining_debt_ticks) == 5,
		"credit exhaustion defers all five")
	var defer := Budget.execute(initial, options(), starved, 4, 4)
	check(bool(defer.get("success", false)) and bool(defer.get("deferred", false))
		and int(defer.get("remaining_debt_ticks", -1)) == 5,
		"zero-credit scheduler success is deferred")
	if bool(defer.get("success", false)):
		check(C.encode(defer.state) == before, "defer does not mutate canonical state")

	# Independently falsify the zero-credit early-return worker bypass.
	var bad_prepare := Budget.execute(initial, options(), starved, 0, 4)
	var bad_advance := Budget.execute(initial, options(), starved, 4, 0)
	check(not bool(bad_prepare.get("success", false))
		and String(bad_prepare.get("error", "")) == "CPU_BUDGET_PARALLEL_PREPARE_WORKERS",
		"prepare workers=0 must fail even when no ticks granted")
	check(not bool(bad_advance.get("success", false))
		and String(bad_advance.get("error", "")) == "CPU_BUDGET_PARALLEL_ADVANCE_WORKERS",
		"advance workers=0 must fail even when no ticks granted")
	var forged := starved.duplicate(true)
	forged.estimated_spend_us = 3
	check(not Budget.validate(forged, initial).is_empty(), "forged spend credits rejected")
	forged = starved.duplicate(true)
	forged.source_state_hash = "wrong"
	check(not Budget.validate(forged, initial).is_empty(), "forged source hash rejected")
	check(C.encode(initial) == before, "adversarial tests leave original frontier untouched")

	var cursor := initial.duplicate(true)
	var quotas := [2, 2, 1]
	for i in quotas.size():
		var fidelity := Fidelity.create(cursor.field, cursor.population,
			{}, int(cursor.tick), 5, 4, 16, 4, 64)
		check(not fidelity.is_empty(), "slice=%d fresh plan" % i)
		if fidelity.is_empty():
			return
		var grant := Budget.create(cursor, fidelity, 3, 7, 2)
		check(not grant.is_empty() and int(grant.allowed_ticks) == int(quotas[i]),
			"slice=%d bounded expected ticks" % i)
		if grant.is_empty():
			return
		check(int(grant.estimated_spend_us) <= 7, "slice=%d no estimated overspend" % i)
		var local_before := C.encode(cursor)
		var stepped := Budget.execute(cursor, options(), grant, 4, 4)
		check(bool(stepped.get("success", false)), "slice=%d execution" % i)
		if not bool(stepped.get("success", false)):
			return
		check(C.encode(cursor) == local_before, "slice=%d input remains immutable" % i)
		cursor = stepped.state
		check(C.encode(cursor) == refs.get(int(cursor.tick), ""),
			"slice=%d exact to alternate continuous reference" % i)
		check(int(stepped.remaining_debt_ticks) == 5 - int(cursor.tick),
			"slice=%d remaining debt exact" % i)
		if i == 0:
			check(not Budget.validate(grant, cursor).is_empty(),
				"stale plan cannot be applied to new canonical frontier")
	check(int(cursor.tick) == 5, "last tick reached expected canonical target")
	check(C.encode(cursor) == C.encode(ref)
		and Runtime.state_hash(cursor) == Runtime.state_hash(ref),
		"byte-identical canonical result and hash")
	var cp := Checkpoint.create(cp_anchor, cursor)
	var reference_cp := Checkpoint.create(cp_anchor, ref)
	check(not cp.is_empty() and not reference_cp.is_empty(),
		"independent final checkpoints created")
	if not cp.is_empty() and not reference_cp.is_empty():
		check(Checkpoint.serialize(cp) == Checkpoint.serialize(reference_cp),
			"independent checkpoints serialize byte-identically")
	check(C.encode(initial) == before, "full independent replay did not mutate initial")

func _verify_wake_priority(initial: Dictionary) -> void:
	var original := C.encode(initial)
	var spatial := Spatial.create(initial.field, initial.population, 4, 64)
	check(not spatial.is_empty(), "priority worksets valid")
	if spatial.is_empty():
		return
	var names: Array = []
	for workset in spatial.worksets:
		if not names.has(String(workset.address)):
			names.append(String(workset.address))
	names.sort()
	check(names.size() == 4, "four spatial priority addresses")
	if names.size() != 4:
		return
	var pending := {}
	var costs := {}
	var last := {}
	var hit := {}
	for name in names:
		pending[name] = 1
		costs[name] = 2
		last[name] = 0
		hit[name] = 0

	for epoch in range(1, 17):
		var advice := Priority.create(initial.field, initial.population,
			[names[0]], pending, costs, last, 4, epoch, 3, 4, 64)
		check(not advice.is_empty(), "priority epoch=%d plan" % epoch)
		if advice.is_empty():
			return
		check(Priority.validate(advice, initial.field, initial.population).is_empty(),
			"priority epoch=%d recomputable" % epoch)
		check(advice.selected_addresses.size() == 2 and int(advice.spent_us) == 4,
			"priority epoch=%d exactly two preparation credits" % epoch)
		for raw in advice.selected_addresses:
			var key := String(raw)
			hit[key] = int(hit[key]) + 1
		last = advice.next_last_served_epoch_by_address
		if epoch >= 6:
			for name in names:
				check(epoch - int(last[name]) <= 5,
					"priority aging prevents starvation epoch=%d" % epoch)
	for name in names:
		check(int(hit[name]) >= 3, "each eligible address eventually serviced")

	var direct := Priority.create(initial.field, initial.population,
		[names[2], names[0]], pending, costs, last, 4, 17, 3, 4, 64)
	var permuted := Priority.create(initial.field, initial.population,
		[names[0], names[2]], pending, costs, last, 4, 17, 3, 4, 64)
	check(not direct.is_empty() and C.encode(direct) == C.encode(permuted),
		"activity permutation yields same priority plan bytes")
	if direct.is_empty():
		return
	var bad := direct.duplicate(true)
	bad.selected_addresses = []
	check(not Priority.validate(bad, initial.field, initial.population).is_empty(),
		"forged priority grants rejected")
	var expensive := costs.duplicate(true)
	expensive[names[0]] = 100
	var qualified := Priority.create(initial.field, initial.population,
		[names[0]], pending, expensive, last, 2, 20, 3, 4, 64)
	check(not qualified.is_empty(), "oversize preparation job input")
	if not qualified.is_empty():
		check(not qualified.selected_addresses.has(names[0]),
			"nonfitting job cannot consume budget or promise guaranteed service")
		check(qualified.selected_addresses.size() == 1 and int(qualified.spent_us) == 2,
			"independent eligible preparation still served")
	check(C.encode(initial) == original, "priority planning never evolves biology")

func _finish() -> void:
	print("ECO_ARCH2_A14_3_INDEPENDENT checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_3_INDEPENDENT " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
