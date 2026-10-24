extends RefCounted
## A5 deterministic lifecycle runtime. Selection is emergent from resource grants and balances;
## there is no top-k/fitness gate in this path.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")
const K = preload("res://scripts/research/ecology/v2/development_interpreter_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const StagedA4R2 = preload("res://scripts/research/ecology/v2/a4_staged_global_allocator_probe_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const Scale = preload("res://scripts/research/ecology/v2/ecology_scale_contract_v1.gd")
const Worksets = preload("res://scripts/research/ecology/v2/population_workset_plan_v1.gd")
const SpatialWorksets = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")
const MAX_POPULATION := Scale.MAX_POPULATION
const MAX_PROPAGULES_PER_STEP := Scale.MAX_PROPAGULES_PER_STEP
const PROPAGULE_SCHEMA := "dws.ecology.propagule.v1"
const DEFAULT_PARALLEL_PREPARE_WORKERS := 4
const MAX_PARALLEL_PREPARE_WORKERS := 8
const DEFAULT_PARALLEL_ADVANCE_WORKERS := 4
const MAX_PARALLEL_ADVANCE_WORKERS := 8

static func individual(blueprint: Dictionary, individual_id: String, position_mm: Array, endowment: Dictionary = {}, origin_kind: String = "FOUNDER_ENDOWMENT") -> Dictionary:
	if origin_kind != "FOUNDER_ENDOWMENT": return {}
	var state := LS.create(blueprint, individual_id, position_mm, endowment, "FOUNDER_ENDOWMENT")
	return {"blueprint": blueprint.duplicate(true), "state": state} if not state.is_empty() else {}

static func step_population(field: Dictionary, population: Array, owner_token: String, owner_epoch: int, revision: int) -> Dictionary:
	# A13 default execution is partitioned for computation but NOT for resource
	# ownership/allocation. The exact same global allocation remains authoritative.
	return step_population_scheduled(field, population, owner_token, owner_epoch, revision, Worksets.DEFAULT_WORKSET_SIZE)

static func step_population_scheduled(field: Dictionary, population: Array, owner_token: String, owner_epoch: int, revision: int, workset_size: int) -> Dictionary:
	var precondition := _precondition_error(field, population, owner_token, owner_epoch, revision)
	if not precondition.is_empty():
		return _fail(precondition)
	var normalized := _canonical_entries(population)
	if not bool(normalized.get("success", false)):
		return normalized
	var entries: Array = normalized.entries
	var plan := Worksets.create(entries, workset_size)
	if plan.is_empty():
		return _fail("A5_WORKSET_PLAN")
	return _step_population_with_entries(field, entries, owner_token, owner_epoch, revision, plan)

static func step_population_with_plan(field: Dictionary, population: Array, owner_token: String, owner_epoch: int, revision: int, plan: Dictionary) -> Dictionary:
	var precondition := _precondition_error(field, population, owner_token, owner_epoch, revision)
	if not precondition.is_empty():
		return _fail(precondition)
	var normalized := _canonical_entries(population)
	if not bool(normalized.get("success", false)):
		return normalized
	var entries: Array = normalized.entries
	var plan_error := Worksets.validate(plan, entries)
	if not plan_error.is_empty():
		return _fail("A5_WORKSET_PLAN:" + plan_error)
	return _step_population_with_entries(field, entries, owner_token, owner_epoch, revision, plan)

static func step_population_spatial_scheduled(field: Dictionary, population: Array,
		owner_token: String, owner_epoch: int, revision: int,
		tile_span_cells: int = SpatialWorksets.DEFAULT_TILE_SPAN_CELLS,
		max_members: int = SpatialWorksets.DEFAULT_MAX_MEMBERS) -> Dictionary:
	var precondition := _precondition_error(field, population, owner_token, owner_epoch, revision)
	if not precondition.is_empty():
		return _fail(precondition)
	var normalized := _canonical_entries(population)
	if not bool(normalized.get("success", false)):
		return normalized
	var entries: Array = normalized.entries
	var plan := SpatialWorksets.create(field, entries, tile_span_cells, max_members)
	if plan.is_empty():
		return _fail("A5_SPATIAL_WORKSET_PLAN")
	return _step_population_with_validated_units(
		field, entries, owner_token, owner_epoch, revision, plan.worksets)

static func step_population_spatial_parallel_prepare(field: Dictionary, population: Array,
		owner_token: String, owner_epoch: int, revision: int,
		tile_span_cells: int = SpatialWorksets.DEFAULT_TILE_SPAN_CELLS,
		max_members: int = SpatialWorksets.DEFAULT_MAX_MEMBERS,
		max_prepare_workers: int = DEFAULT_PARALLEL_PREPARE_WORKERS) -> Dictionary:
	var precondition := _precondition_error(field, population, owner_token, owner_epoch, revision)
	if not precondition.is_empty():
		return _fail(precondition)
	if not valid_parallel_prepare_workers(max_prepare_workers):
		return _fail("A5_PARALLEL_PREPARE_WORKERS")
	var normalized := _canonical_entries(population)
	if not bool(normalized.get("success", false)):
		return normalized
	var entries: Array = normalized.entries
	var plan := SpatialWorksets.create(field, entries, tile_span_cells, max_members)
	if plan.is_empty():
		return _fail("A5_SPATIAL_WORKSET_PLAN")
	return _step_population_with_validated_units_parallel_prepare(
		field, entries, owner_token, owner_epoch, revision, plan.worksets,
		max_prepare_workers)

static func step_population_with_spatial_plan_parallel_prepare(field: Dictionary, population: Array,
		owner_token: String, owner_epoch: int, revision: int, plan: Dictionary,
		max_prepare_workers: int = DEFAULT_PARALLEL_PREPARE_WORKERS) -> Dictionary:
	var precondition := _precondition_error(field, population, owner_token, owner_epoch, revision)
	if not precondition.is_empty():
		return _fail(precondition)
	if not valid_parallel_prepare_workers(max_prepare_workers):
		return _fail("A5_PARALLEL_PREPARE_WORKERS")
	var normalized := _canonical_entries(population)
	if not bool(normalized.get("success", false)):
		return normalized
	var entries: Array = normalized.entries
	var plan_error := SpatialWorksets.validate(plan, field, entries)
	if not plan_error.is_empty():
		return _fail("A5_SPATIAL_WORKSET_PLAN:" + plan_error)
	return _step_population_with_validated_units_parallel_prepare(
		field, entries, owner_token, owner_epoch, revision, plan.worksets,
		max_prepare_workers)

static func valid_parallel_prepare_workers(max_prepare_workers: int) -> bool:
	return max_prepare_workers >= 1 and max_prepare_workers <= MAX_PARALLEL_PREPARE_WORKERS

static func step_population_spatial_parallel_advance(field: Dictionary, population: Array,
		owner_token: String, owner_epoch: int, revision: int,
		tile_span_cells: int = SpatialWorksets.DEFAULT_TILE_SPAN_CELLS,
		max_members: int = SpatialWorksets.DEFAULT_MAX_MEMBERS,
		max_prepare_workers: int = DEFAULT_PARALLEL_PREPARE_WORKERS,
		max_advance_workers: int = DEFAULT_PARALLEL_ADVANCE_WORKERS) -> Dictionary:
	var precondition := _precondition_error(field, population, owner_token, owner_epoch, revision)
	if not precondition.is_empty():
		return _fail(precondition)
	if not valid_parallel_prepare_workers(max_prepare_workers):
		return _fail("A5_PARALLEL_PREPARE_WORKERS")
	if not valid_parallel_advance_workers(max_advance_workers):
		return _fail("A5_PARALLEL_ADVANCE_WORKERS")
	var normalized := _canonical_entries(population)
	if not bool(normalized.get("success", false)):
		return normalized
	var entries: Array = normalized.entries
	var plan := SpatialWorksets.create(field, entries, tile_span_cells, max_members)
	if plan.is_empty():
		return _fail("A5_SPATIAL_WORKSET_PLAN")
	return _step_population_with_validated_units_parallel_advance(
		field, entries, owner_token, owner_epoch, revision, plan.worksets,
		max_prepare_workers, max_advance_workers)

static func step_population_with_spatial_plan_parallel_advance(field: Dictionary, population: Array,
		owner_token: String, owner_epoch: int, revision: int, plan: Dictionary,
		max_prepare_workers: int = DEFAULT_PARALLEL_PREPARE_WORKERS,
		max_advance_workers: int = DEFAULT_PARALLEL_ADVANCE_WORKERS) -> Dictionary:
	var precondition := _precondition_error(field, population, owner_token, owner_epoch, revision)
	if not precondition.is_empty():
		return _fail(precondition)
	if not valid_parallel_prepare_workers(max_prepare_workers):
		return _fail("A5_PARALLEL_PREPARE_WORKERS")
	if not valid_parallel_advance_workers(max_advance_workers):
		return _fail("A5_PARALLEL_ADVANCE_WORKERS")
	var normalized := _canonical_entries(population)
	if not bool(normalized.get("success", false)):
		return normalized
	var entries: Array = normalized.entries
	var plan_error := SpatialWorksets.validate(plan, field, entries)
	if not plan_error.is_empty():
		return _fail("A5_SPATIAL_WORKSET_PLAN:" + plan_error)
	return _step_population_with_validated_units_parallel_advance(
		field, entries, owner_token, owner_epoch, revision, plan.worksets,
		max_prepare_workers, max_advance_workers)

static func valid_parallel_advance_workers(max_advance_workers: int) -> bool:
	return max_advance_workers >= 1 and max_advance_workers <= MAX_PARALLEL_ADVANCE_WORKERS

static func step_population_with_spatial_plan(field: Dictionary, population: Array,
		owner_token: String, owner_epoch: int, revision: int, plan: Dictionary) -> Dictionary:
	var precondition := _precondition_error(field, population, owner_token, owner_epoch, revision)
	if not precondition.is_empty():
		return _fail(precondition)
	var normalized := _canonical_entries(population)
	if not bool(normalized.get("success", false)):
		return normalized
	var entries: Array = normalized.entries
	var plan_error := SpatialWorksets.validate(plan, field, entries)
	if not plan_error.is_empty():
		return _fail("A5_SPATIAL_WORKSET_PLAN:" + plan_error)
	return _step_population_with_validated_units(
		field, entries, owner_token, owner_epoch, revision, plan.worksets)

static func _precondition_error(field: Dictionary, population: Array, owner_token: String, owner_epoch: int, revision: int) -> String:
	# Preserve the historical A5 public failure precedence exactly.
	if not F.validate_state(field).is_empty():
		return "A5_FIELD"
	if population.is_empty() or population.size() > MAX_POPULATION:
		return "A5_POPULATION_SIZE"
	if owner_token != field.owner_token:
		return "STALE_OWNER"
	if owner_epoch != field.owner_epoch:
		return "STALE_OWNER_EPOCH"
	if revision != field.revision:
		return "STALE_REVISION"
	return ""

static func _canonical_entries(population: Array) -> Dictionary:
	if population.is_empty() or population.size() > MAX_POPULATION:
		return _fail("A5_POPULATION_SIZE")
	var entries: Array = []
	var seen := {}
	for entry in population:
		if not C.keys(entry, ["blueprint", "state"]) or not entry.blueprint is Dictionary or not entry.state is Dictionary:
			return _fail("A5_ENTRY")
		if not BP.validate(entry.blueprint).is_empty() or not LS.validate(entry.state, entry.blueprint).is_empty():
			return _fail("A5_ENTRY_INVALID")
		var id: String = entry.state.individual_id
		if seen.has(id):
			return _fail("A5_DUPLICATE_INDIVIDUAL")
		seen[id] = true
		entries.append({"blueprint": entry.blueprint.duplicate(true), "state": entry.state.duplicate(true)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.state.individual_id < b.state.individual_id)
	return {"success": true, "entries": entries}

static func _step_population_with_entries(field: Dictionary, entries: Array, owner_token: String, owner_epoch: int, revision: int, plan: Dictionary) -> Dictionary:
	var plan_error := Worksets.validate(plan, entries)
	if not plan_error.is_empty():
		return _fail("A5_WORKSET_PLAN:" + plan_error)
	return _step_population_with_validated_units(
		field, entries, owner_token, owner_epoch, revision, plan.worksets)

static func _step_population_with_validated_units(field: Dictionary, entries: Array,
		owner_token: String, owner_epoch: int, revision: int, units: Array) -> Dictionary:
	var guard := _validated_units_precondition(field, owner_token, owner_epoch, revision)
	if not guard.is_empty():
		return _fail(guard)
	var prepared := _prepare_units_serial(field, entries, units)
	if not bool(prepared.get("success", false)):
		return prepared
	return _finish_population_step(
		field, entries, owner_token, owner_epoch, revision, units,
		prepared.samples, prepared.demands)

static func _step_population_with_validated_units_parallel_prepare(field: Dictionary, entries: Array,
		owner_token: String, owner_epoch: int, revision: int, units: Array,
		max_prepare_workers: int) -> Dictionary:
	var guard := _validated_units_precondition(field, owner_token, owner_epoch, revision)
	if not guard.is_empty():
		return _fail(guard)
	if not valid_parallel_prepare_workers(max_prepare_workers):
		return _fail("A5_PARALLEL_PREPARE_WORKERS")
	var prepared := _prepare_units_parallel(field, entries, units, max_prepare_workers)
	if not bool(prepared.get("success", false)):
		return prepared
	var finished := _finish_population_step(
		field, entries, owner_token, owner_epoch, revision, units,
		prepared.samples, prepared.demands)
	if not bool(finished.get("success", false)):
		return finished
	finished["scheduler"] = {
		"parallel_prepare": true,
		"worker_bound": max_prepare_workers,
		"peak_workers": int(prepared.peak_workers),
		"threaded_worksets": int(prepared.threaded_worksets),
		"workset_count": units.size(),
	}
	return finished

static func _step_population_with_validated_units_parallel_advance(
		field: Dictionary, entries: Array,
		owner_token: String, owner_epoch: int, revision: int, units: Array,
		max_prepare_workers: int, max_advance_workers: int) -> Dictionary:
	var guard := _validated_units_precondition(field, owner_token, owner_epoch, revision)
	if not guard.is_empty():
		return _fail(guard)
	if not valid_parallel_prepare_workers(max_prepare_workers):
		return _fail("A5_PARALLEL_PREPARE_WORKERS")
	if not valid_parallel_advance_workers(max_advance_workers):
		return _fail("A5_PARALLEL_ADVANCE_WORKERS")

	var prepared := _prepare_units_parallel(field, entries, units, max_prepare_workers)
	if not bool(prepared.get("success", false)):
		return prepared

	var allocated := _allocate_population_demands(
		field, entries, owner_token, owner_epoch, revision, prepared.demands)
	if not bool(allocated.get("success", false)):
		return allocated

	var advanced := _advance_units_parallel(
		entries, units, prepared.samples, allocated.intake_by_id, max_advance_workers)
	if not bool(advanced.get("success", false)):
		return advanced

	var finished := _population_step_result(
		allocated.field, advanced.population, advanced.propagules)
	finished["scheduler"] = {
		"parallel_prepare": true,
		"prepare_worker_bound": max_prepare_workers,
		"prepare_peak_workers": int(prepared.peak_workers),
		"prepare_threaded_worksets": int(prepared.threaded_worksets),
		"parallel_advance": true,
		"advance_worker_bound": max_advance_workers,
		"advance_peak_workers": int(advanced.peak_workers),
		"advance_threaded_worksets": int(advanced.threaded_worksets),
		"workset_count": units.size(),
	}
	return finished

static func _validated_units_precondition(field: Dictionary,
		owner_token: String, owner_epoch: int, revision: int) -> String:
	if not F.validate_state(field).is_empty():
		return "A5_FIELD"
	if owner_token != field.owner_token:
		return "STALE_OWNER"
	if owner_epoch != field.owner_epoch:
		return "STALE_OWNER_EPOCH"
	if revision != field.revision:
		return "STALE_REVISION"
	return ""

static func _entries_by_id(entries: Array) -> Dictionary:
	var by_id := {}
	for entry in entries:
		by_id[String(entry.state.individual_id)] = entry
	return by_id

static func _prepare_units_serial(field: Dictionary, entries: Array, units: Array) -> Dictionary:
	var by_id := _entries_by_id(entries)
	var samples := {}
	var demands: Array = []
	for unit in units:
		var task_entries: Array = []
		for raw_id in unit.member_ids:
			var id := String(raw_id)
			if not by_id.has(id):
				return _fail("A5_WORKSET_MEMBER")
			task_entries.append(by_id[id])
		var prepared := _prepare_unit_worker(field, task_entries, int(unit.index))
		if not bool(prepared.get("success", false)):
			return prepared
		for id in prepared.samples:
			samples[String(id)] = prepared.samples[id]
		for demand in prepared.demands:
			demands.append(demand)
	return {
		"success": true,
		"samples": samples,
		"demands": demands,
		"peak_workers": 1 if not units.is_empty() else 0,
	}

static func _prepare_units_parallel(field: Dictionary, entries: Array, units: Array,
		max_prepare_workers: int) -> Dictionary:
	var by_id := _entries_by_id(entries)
	var samples := {}
	var demands: Array = []
	var cursor := 0
	var peak_workers := 0
	var threaded_worksets := 0
	while cursor < units.size():
		var stop := mini(units.size(), cursor + max_prepare_workers)
		var active: Array = []
		for unit_index in range(cursor, stop):
			var unit: Dictionary = units[unit_index]
			var task_entries: Array = []
			for raw_id in unit.member_ids:
				var id := String(raw_id)
				if not by_id.has(id):
					for started in active:
						started.thread.wait_to_finish()
					return _fail("A5_WORKSET_MEMBER")
				task_entries.append(by_id[id].duplicate(true))
			var thread := Thread.new()
			var task_field: Dictionary = field.duplicate(true)
			var start_error := thread.start(
				_prepare_unit_worker.bind(task_field, task_entries, int(unit.index)))
			if start_error != OK:
				for started in active:
					started.thread.wait_to_finish()
				return _fail("A5_PARALLEL_PREPARE_THREAD_START")
			active.append({"index": int(unit.index), "thread": thread})
		peak_workers = maxi(peak_workers, active.size())

		var wave_results := {}
		for started in active:
			var result: Variant = started.thread.wait_to_finish()
			wave_results[int(started.index)] = result

		# Completion order is deliberately ignored. Consume results in the exact
		# canonical workset order used by the serial path.
		for unit_index in range(cursor, stop):
			var unit: Dictionary = units[unit_index]
			var result: Variant = wave_results.get(int(unit.index), null)
			if not result is Dictionary:
				return _fail("A5_PARALLEL_PREPARE_RESULT")
			var prepared: Dictionary = result
			if not bool(prepared.get("success", false)):
				return prepared
			if int(prepared.get("unit_index", -1)) != int(unit.index):
				return _fail("A5_PARALLEL_PREPARE_INDEX")
			if bool(prepared.get("worker_is_main_thread", true)):
				return _fail("A5_PARALLEL_PREPARE_THREAD_CONTEXT")
			threaded_worksets += 1
			for id in prepared.samples:
				samples[String(id)] = prepared.samples[id]
			for demand in prepared.demands:
				demands.append(demand)
		cursor = stop

	return {
		"success": true,
		"samples": samples,
		"demands": demands,
		"peak_workers": peak_workers,
		"threaded_worksets": threaded_worksets,
	}

static func _prepare_unit_worker(field: Dictionary, task_entries: Array, unit_index: int) -> Dictionary:
	var samples := {}
	var demands: Array = []
	for entry in task_entries:
		if not entry is Dictionary or not entry.has("blueprint") or not entry.has("state"):
			return _fail("A5_ENTRY")
		var state: Dictionary = entry.state
		if not state.alive:
			continue
		var phenotype := H.compile(state.development, entry.blueprint.genome)
		if phenotype.is_empty():
			return _fail("A5_PHENOTYPE")
		var extent := Ports.sampling_extent_mm(phenotype)
		var request := Ports.sample_request(state.individual_id, state.position_mm, extent)
		var sampled := Field.sample(field, request)
		if not sampled.success:
			return _fail("A5_SAMPLE:" + String(sampled.error))
		var id := String(state.individual_id)
		samples[id] = sampled.sample
		var generated := _demands(state, entry.blueprint, phenotype)
		for demand in generated:
			demands.append(demand)
	return {
		"success": true,
		"unit_index": unit_index,
		"worker_is_main_thread": Thread.is_main_thread(),
		"samples": samples,
		"demands": demands,
	}

static func _finish_population_step(field: Dictionary, entries: Array,
		owner_token: String, owner_epoch: int, revision: int, units: Array,
		samples: Dictionary, demands: Array) -> Dictionary:
	var allocated := _allocate_population_demands(
		field, entries, owner_token, owner_epoch, revision, demands)
	if not bool(allocated.get("success", false)):
		return allocated
	var advanced := _advance_units_serial(
		entries, units, samples, allocated.intake_by_id)
	if not bool(advanced.get("success", false)):
		return advanced
	return _population_step_result(
		allocated.field, advanced.population, advanced.propagules)

static func _allocate_population_demands(field: Dictionary, entries: Array,
		owner_token: String, owner_epoch: int, revision: int, demands: Array) -> Dictionary:
	# Absolute global barrier. Both serial and parallel-advance paths pass
	# through this single helper exactly once before any Phase 2 advance.
	var field_after := field.duplicate(true)
	var intake_by_id := {}
	for entry in entries:
		intake_by_id[String(entry.state.individual_id)] = F.stock()
	if not demands.is_empty():
		var allocated := Field.allocate_demands(
			field, demands, owner_token, owner_epoch, revision)
		if not allocated.success:
			return _fail("A5_ALLOCATION:" + String(allocated.error))
		field_after = allocated.state
		for grant in allocated.grants:
			var id: String = grant.organism_id
			if not intake_by_id.has(id):
				return _fail("A5_GRANT_OWNER")
			intake_by_id[id][grant.resource] += grant.granted
	return {
		"success": true,
		"field": field_after,
		"intake_by_id": intake_by_id,
	}

static func _advance_units_serial(entries: Array, units: Array,
		samples: Dictionary, intake_by_id: Dictionary) -> Dictionary:
	var by_id := _entries_by_id(entries)
	var next_population: Array = []
	var propagules: Array = []
	for unit in units:
		var task_entries: Array = []
		for raw_id in unit.member_ids:
			var id := String(raw_id)
			if not by_id.has(id):
				return _fail("A5_WORKSET_MEMBER")
			task_entries.append(by_id[id])
		var advanced := _advance_unit_worker(
			task_entries, samples, intake_by_id, int(unit.index))
		if not bool(advanced.get("success", false)):
			return advanced
		var consumed := _consume_advance_outcomes(
			unit, advanced.outcomes, next_population, propagules)
		if not bool(consumed.get("success", false)):
			return consumed
	return _canonical_advance_result(next_population, propagules, 0, 0)

static func _advance_units_parallel(entries: Array, units: Array,
		samples: Dictionary, intake_by_id: Dictionary,
		max_advance_workers: int) -> Dictionary:
	if not valid_parallel_advance_workers(max_advance_workers):
		return _fail("A5_PARALLEL_ADVANCE_WORKERS")
	var by_id := _entries_by_id(entries)
	var next_population: Array = []
	var propagules: Array = []
	var cursor := 0
	var peak_workers := 0
	var threaded_worksets := 0

	while cursor < units.size():
		var stop := mini(units.size(), cursor + max_advance_workers)
		var active: Array = []
		for unit_index in range(cursor, stop):
			var unit: Dictionary = units[unit_index]
			var task_entries: Array = []
			var task_samples := {}
			var task_intake := {}
			for raw_id in unit.member_ids:
				var id := String(raw_id)
				if not by_id.has(id):
					for started in active:
						started.thread.wait_to_finish()
					return _fail("A5_WORKSET_MEMBER")
				var entry: Dictionary = by_id[id]
				task_entries.append(entry.duplicate(true))
				if samples.has(id):
					task_samples[id] = samples[id].duplicate(true)
				if intake_by_id.has(id):
					task_intake[id] = intake_by_id[id].duplicate(true)
			var thread := Thread.new()
			var start_error := thread.start(
				_advance_unit_worker.bind(
					task_entries, task_samples, task_intake, int(unit.index)))
			if start_error != OK:
				for started in active:
					started.thread.wait_to_finish()
				return _fail("A5_PARALLEL_ADVANCE_THREAD_START")
			active.append({"index": int(unit.index), "thread": thread})
		peak_workers = maxi(peak_workers, active.size())

		var wave_results := {}
		for started in active:
			var result: Variant = started.thread.wait_to_finish()
			wave_results[int(started.index)] = result

		# Completion order is non-authoritative. Workset and member outcomes are
		# interpreted only on the main thread in canonical order.
		for unit_index in range(cursor, stop):
			var unit: Dictionary = units[unit_index]
			var result: Variant = wave_results.get(int(unit.index), null)
			if not result is Dictionary:
				return _fail("A5_PARALLEL_ADVANCE_RESULT")
			var advanced: Dictionary = result
			if not bool(advanced.get("success", false)):
				return advanced
			if int(advanced.get("unit_index", -1)) != int(unit.index):
				return _fail("A5_PARALLEL_ADVANCE_INDEX")
			if bool(advanced.get("worker_is_main_thread", true)):
				return _fail("A5_PARALLEL_ADVANCE_THREAD_CONTEXT")
			threaded_worksets += 1
			var consumed := _consume_advance_outcomes(
				unit, advanced.outcomes, next_population, propagules)
			if not bool(consumed.get("success", false)):
				return consumed
		cursor = stop

	return _canonical_advance_result(
		next_population, propagules, peak_workers, threaded_worksets)

static func _advance_unit_worker(task_entries: Array, samples: Dictionary,
		intake_by_id: Dictionary, unit_index: int) -> Dictionary:
	var outcomes: Array = []
	for entry in task_entries:
		if not entry is Dictionary or not entry.has("blueprint") or not entry.has("state"):
			return _fail("A5_ENTRY")
		var state: Dictionary = entry.state
		var blueprint: Dictionary = entry.blueprint
		var id := String(state.individual_id)
		if not state.alive:
			var inert := state.duplicate(true)
			inert.last_events = [{
				"outcome": "DEAD_INERT",
				"detail": "no resource requests or lifecycle transitions",
			}]
			outcomes.append({
				"success": true,
				"member_id": id,
				"entry": {
					"blueprint": blueprint.duplicate(true),
					"state": inert,
				},
				"propagules": [],
			})
			continue
		if not samples.has(id):
			outcomes.append({
				"success": false,
				"member_id": id,
				"error": "A5_PREPARE_SAMPLE_MISSING",
			})
			break
		if not intake_by_id.has(id):
			outcomes.append({
				"success": false,
				"member_id": id,
				"error": "A5_GRANT_OWNER",
			})
			break
		var advanced := _advance_individual(
			state, blueprint, samples[id], intake_by_id[id])
		if not advanced.success:
			outcomes.append({
				"success": false,
				"member_id": id,
				"error": String(advanced.error),
			})
			break
		outcomes.append({
			"success": true,
			"member_id": id,
			"entry": {
				"blueprint": blueprint.duplicate(true),
				"state": advanced.state,
			},
			"propagules": advanced.propagules.duplicate(true),
		})

	return {
		"success": true,
		"unit_index": unit_index,
		"worker_is_main_thread": Thread.is_main_thread(),
		"outcomes": outcomes,
	}

static func _consume_advance_outcomes(unit: Dictionary, outcomes: Array,
		next_population: Array, propagules: Array) -> Dictionary:
	if outcomes.is_empty() and not unit.member_ids.is_empty():
		return _fail("A5_ADVANCE_OUTCOME_COUNT")
	if outcomes.size() > unit.member_ids.size():
		return _fail("A5_ADVANCE_OUTCOME_COUNT")

	for member_index in outcomes.size():
		var outcome: Variant = outcomes[member_index]
		if not outcome is Dictionary:
			return _fail("A5_ADVANCE_OUTCOME")
		var expected_id := String(unit.member_ids[member_index])
		if String(outcome.get("member_id", "")) != expected_id:
			return _fail("A5_ADVANCE_OUTCOME_MEMBER")

		# This order is the historical canonical contract:
		# member semantic failure is considered at its member position, while a
		# successful earlier member's propagules are admitted/limited before the
		# next member outcome is considered.
		if not bool(outcome.get("success", false)):
			var error := String(outcome.get("error", ""))
			return _fail(error if not error.is_empty() else "A5_ADVANCE_OUTCOME_ERROR")
		var entry: Variant = outcome.get("entry", null)
		var member_propagules: Variant = outcome.get("propagules", null)
		if not entry is Dictionary or not member_propagules is Array:
			return _fail("A5_ADVANCE_OUTCOME")
		next_population.append(entry)
		for propagule in member_propagules:
			if propagules.size() >= MAX_PROPAGULES_PER_STEP:
				return _fail("A5_PROPAGULE_LIMIT")
			propagules.append(propagule)

	if outcomes.size() != unit.member_ids.size():
		return _fail("A5_ADVANCE_OUTCOME_COUNT")
	return {"success": true}

static func _canonical_advance_result(next_population: Array, propagules: Array,
		peak_workers: int, threaded_worksets: int) -> Dictionary:
	next_population.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.state.individual_id < b.state.individual_id)
	propagules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.id < b.id)
	return {
		"success": true,
		"population": next_population,
		"propagules": propagules,
		"peak_workers": peak_workers,
		"threaded_worksets": threaded_worksets,
	}

static func _population_step_result(field_after: Dictionary,
		next_population: Array, propagules: Array) -> Dictionary:
	return {
		"success": true,
		"field": field_after,
		"population": next_population,
		"propagules": propagules,
		"field_hash": Field.state_hash(field_after),
	}


## A14.5 R1 EXPERIMENTAL: an interruptible A5 lifecycle over immutable
## source inputs. The cursor is NONCANONICAL, transient and fail-closed.
## PREPARE and ADVANCE run bounded *workset counts*. The single global
## ALLOCATE barrier is deliberately indivisible; no wall deadline is claimed.
## A caller may publish biology ONLY after COMPLETE, never between phases.
const STAGED_SCHEMA := "dws.ecology.a5-staged-lifecycle.v1"
## Opt-in LAB R3: host-private nonpersistent R2 global A4 scratch.
## Accepted v1 cursor and default A5 execution are unchanged.
const STAGED_SCHEMA_R3 := "dws.ecology.a5-staged-lifecycle-r3.v1"
const STAGED_R3_ALLOCATOR_MODE := "R2_DETACHED_GLOBAL"
const STAGED_CURSOR_KEYS := [
	"schema", "source_hash", "field", "entries", "units",
	"owner_token", "owner_epoch", "revision", "phase", "index",
	"samples", "demands", "allocated_field", "intake_by_id",
	"next_population", "propagules", "checksum",
]
const STAGED_R3_CURSOR_KEYS := [
	"schema", "source_hash", "field", "entries", "units",
	"owner_token", "owner_epoch", "revision", "phase", "index",
	"samples", "demands", "allocated_field", "intake_by_id",
	"next_population", "propagules", "allocator_mode",
	"allocator_cursor", "checksum",
]

static func staged_begin(field: Dictionary, population: Array,
		owner_token: String, owner_epoch: int, revision: int,
		tile_span_cells: int = SpatialWorksets.DEFAULT_TILE_SPAN_CELLS,
		max_members: int = SpatialWorksets.DEFAULT_MAX_MEMBERS,
		use_r3_allocator: bool = false) -> Dictionary:
	var guard := _precondition_error(field, population, owner_token, owner_epoch, revision)
	if not guard.is_empty():
		return _fail(guard)
	var canonical := _canonical_entries(population)
	if not bool(canonical.get("success", false)):
		return canonical
	var entries: Array = canonical.entries
	var plan := SpatialWorksets.create(field, entries, tile_span_cells, max_members)
	if plan.is_empty():
		return _fail("A5_STAGED_SPATIAL_PLAN")
	var error := SpatialWorksets.validate(plan, field, entries)
	if not error.is_empty():
		return _fail("A5_STAGED_SPATIAL_PLAN:" + error)
	var fingerprint := C.digest({"field": field, "population": population})
	if fingerprint.is_empty():
		return _fail("A5_STAGED_SOURCE_HASH")
	var cursor := {
		"schema": STAGED_SCHEMA,
		"source_hash": fingerprint,
		"field": field.duplicate(true),
		"entries": entries,
		"units": plan.worksets.duplicate(true),
		"owner_token": owner_token, "owner_epoch": owner_epoch,
		"revision": revision, "phase": "PREPARE", "index": 0,
		"samples": {}, "demands": [], "allocated_field": {},
		"intake_by_id": {}, "next_population": [], "propagules": [],
		"checksum": "",
	}
	if use_r3_allocator:
		cursor.schema = STAGED_SCHEMA_R3
		cursor["allocator_mode"] = STAGED_R3_ALLOCATOR_MODE
		cursor["allocator_cursor"] = {}
	cursor = _seal_staged_cursor(cursor)
	if cursor.is_empty():
		return _fail("A5_STAGED_CURSOR_SEAL")
	return {"success": true, "complete": false, "phase": "PREPARE", "cursor": cursor}

static func staged_resume(cursor: Dictionary, source_field: Dictionary,
		source_population: Array, max_worksets_per_call: int = 1,
		max_allocator_items_per_call: int = 16,
		allocator_cap_bytes: int = StagedA4R2.DEFAULT_CURSOR_CAP_BYTES,
		r2c_parallel_workers: int = 1,
		r2e_profile: bool = false) -> Dictionary:
	if not C.integer(max_worksets_per_call, 1, 4096):
		return _fail("A5_STAGED_QUOTA")
	# R2C research-only: existing A13 threading is strictly bounded.
	# The old accepted R3/R2/A14.5 paths still pass the default 1.
	if not valid_parallel_prepare_workers(r2c_parallel_workers) \
			or not valid_parallel_advance_workers(r2c_parallel_workers):
		return _fail("A5_R2C_PARALLEL_WORKERS")
	var r3_mode: bool = String(cursor.get("schema", "")) == STAGED_SCHEMA_R3
	var expected_keys: Array = STAGED_R3_CURSOR_KEYS if r3_mode else STAGED_CURSOR_KEYS
	if not C.keys(cursor, expected_keys) or (not r3_mode \
			and String(cursor.get("schema", "")) != STAGED_SCHEMA):
		return _fail("A5_STAGED_CURSOR_SCHEMA")
	if r3_mode:
		if String(cursor.allocator_mode) != STAGED_R3_ALLOCATOR_MODE \
				or not cursor.allocator_cursor is Dictionary:
			return _fail("A5_STAGED_R3_ALLOCATOR_MODE")
		if not C.integer(max_allocator_items_per_call, 1, StagedA4R2.MAX_QUOTA) \
				or not C.integer(allocator_cap_bytes, 1024, StagedA4R2.MAX_CURSOR_CAP_BYTES):
			return _fail("A5_STAGED_R3_ALLOCATOR_QUOTA")
	if not cursor.field is Dictionary or not cursor.entries is Array \
			or not cursor.units is Array or not cursor.samples is Dictionary \
			or not cursor.demands is Array or not cursor.allocated_field is Dictionary \
			or not cursor.intake_by_id is Dictionary \
			or not cursor.next_population is Array or not cursor.propagules is Array:
		return _fail("A5_STAGED_CURSOR_TYPES")
	# A shallow envelope copy keeps the supplied cursor and every nested
	# array immutable. Deep-cloning the full source/partial outcomes solely
	# for the checksum doubled resident memory and resume latency.
	# The experimental R3 nested A4 scratch has its OWN full checksum,
	# checked by StagedA4R2.resume before every speculative allocation
	# step. Bind that checksum in the A5 envelope instead of digesting
	# megabytes of already-sealed inner data for a second time. Accepted
	# A14.5 v1 continues hashing its complete cursor exactly as before.
	var r2e_cursor_check_start_us: int = Time.get_ticks_usec() if r2e_profile else 0
	var digest: String = _staged_cursor_checksum(cursor)
	if digest.is_empty() or digest != String(cursor.checksum):
		return _fail("A5_STAGED_CURSOR_CHECKSUM")
	var r2e_cursor_check_us: int = Time.get_ticks_usec() - r2e_cursor_check_start_us if r2e_profile else 0
	var r2e_source_start_us: int = Time.get_ticks_usec() if r2e_profile else 0
	var current_source := C.digest({"field": source_field, "population": source_population})
	if current_source.is_empty() or current_source != String(cursor.source_hash):
		return _fail("A5_STAGED_SOURCE_CHANGED")
	var r2e_source_digest_us: int = Time.get_ticks_usec() - r2e_source_start_us if r2e_profile else 0
	if not C.integer(cursor.index, 0, cursor.units.size()):
		return _fail("A5_STAGED_CURSOR_INDEX")
	var phase := String(cursor.phase)
	if not phase in ["PREPARE", "ALLOCATE", "ADVANCE"]:
		return _fail("A5_STAGED_PHASE")
	if r3_mode and phase != "ALLOCATE" and not cursor.allocator_cursor.is_empty():
		return _fail("A5_STAGED_R3_ALLOCATOR_PHASE")
	# R2E: versioned R3-stage cursor copy-on-write. The old R3 source
	# validation + complete sealed checksum above STILL run on every call.
	# A14.5 historical V1 keeps the byte-for-byte original full deep copy.
	# Only clone the R3 collections that THIS stage can write; every other
	# nested container remains a read-only alias. This is NOT a source
	# validation/cache/ownership bypass. The immutable old cursor is still
	# validated on EVERY call and no speculative results are published.
	var r2e_copy_start_us: int = Time.get_ticks_usec() if r2e_profile else 0
	var next: Dictionary = cursor.duplicate(true)
	if r3_mode:
		next = cursor.duplicate(false)
		if phase == "PREPARE":
			# _prepare_units_{serial,parallel} build fresh detached results.
			# PREPARE only extends the sample map and ordered demands array.
			next["samples"] = cursor.samples.duplicate(true)
			next["demands"] = cursor.demands.duplicate(true)
		elif phase == "ADVANCE":
			# _advance_unit_worker never mutates the input entry/samples;
			# _consume_advance_outcomes only appends to these result arrays.
			# Copy the *entire* previous prefix, preserving global
			# MAX_PROPAGULES_PER_STEP and earliest failure precedence.
			next["next_population"] = cursor.next_population.duplicate(true)
			next["propagules"] = cursor.propagules.duplicate(true)
		# ALLOCATE updates only detached top-level references to a sealed
		# R2 A4 cursor and final allocation; nothing nested is mutated.
	var r2e_cow_copy_us: int = Time.get_ticks_usec() - r2e_copy_start_us if r2e_profile else 0
	var r2e_profile_values: Dictionary = {}
	if r2e_profile:
		r2e_profile_values = {
			"cursor_verify_us": r2e_cursor_check_us,
			"source_digest_us": r2e_source_digest_us,
			"cow_copy_us": r2e_cow_copy_us,
			"result_seal_us": 0,
		}
	var units: Array = next.units
	var entries: Array = next.entries
	var index: int = int(next.index)
	var r2c_peak_workers := 0
	var r2c_threaded_worksets := 0
	if phase == "PREPARE":
		var stop := mini(units.size(), index + max_worksets_per_call)
		# Reuse A13 verified detached per-workset threaded PREPARE.
		# Unit results are consumed in stable index order before the
		# SINGLE globally coupled A4 stage begins.
		var fragment_units: Array = units.slice(index, stop)
		var parallel: bool = r3_mode and r2c_parallel_workers > 1 \
			and fragment_units.size() > 1
		var fragment: Dictionary = _prepare_units_parallel(
			next.field, entries, fragment_units, r2c_parallel_workers) if parallel \
			else _prepare_units_serial(next.field, entries, fragment_units)
		if not bool(fragment.get("success", false)):
			return fragment
		if parallel:
			r2c_peak_workers = int(fragment.get("peak_workers", 0))
			r2c_threaded_worksets = int(fragment.get("threaded_worksets", 0))
		for id in fragment.samples:
			next.samples[String(id)] = fragment.samples[id]
		for demand in fragment.demands:
			next.demands.append(demand)
		next.index = stop
		if stop == units.size():
			next.phase = "ALLOCATE"
			next.index = 0
	elif phase == "ALLOCATE":
		# Full PREPARE frontier joins before the ONE global allocation.
		# No speculative resource/grant or organism state is published.
		if index != 0:
			return _fail("A5_STAGED_ALLOCATION_INDEX")
		if r3_mode and not next.demands.is_empty():
			if next.allocator_cursor.is_empty():
				# Begin R2 detached allocator; it can yield between the
				# NORMALIZE, CLAIM, PRIMARY and RESIDUAL steps.
				var started_a4: Dictionary = StagedA4R2.begin(
					next.field, next.demands, String(next.owner_token),
					int(next.owner_epoch), int(next.revision),
					allocator_cap_bytes)
				if not bool(started_a4.get("success", false)):
					return _fail("A5_STAGED_R3_ALLOCATOR_BEGIN:" +
						String(started_a4.get("error", "?")))
				next.allocator_cursor = started_a4.cursor
			else:
				var progressed_a4: Dictionary = StagedA4R2.resume(
					next.field, next.demands, String(next.owner_token),
					int(next.owner_epoch), int(next.revision),
					next.allocator_cursor, max_allocator_items_per_call,
					allocator_cap_bytes)
				if not bool(progressed_a4.get("success", false)):
					return _fail("A5_STAGED_R3_ALLOCATOR_RESUME:" +
						String(progressed_a4.get("error", "?")))
				if bool(progressed_a4.get("complete", false)):
					# R2 FINALIZE independently runs the original A4
					# authoritative allocator and compares every byte.
					if not bool(progressed_a4.get("reference_equal", false)):
						return _fail("A5_STAGED_R3_REFERENCE_NOT_EQUAL")
					var r3_intake := {}
					for entry in entries:
						r3_intake[String(entry.state.individual_id)] = F.stock()
					for grant in progressed_a4.grants:
						var id: String = String(grant.organism_id)
						if not r3_intake.has(id):
							return _fail("A5_GRANT_OWNER")
						r3_intake[id][String(grant.resource)] += int(grant.granted)
					next.allocated_field = progressed_a4.state
					next.intake_by_id = r3_intake
					next.allocator_cursor = {}
					next.phase = "ADVANCE"
					next.index = 0
				else:
					if progressed_a4.has("state") or not progressed_a4.has("cursor"):
						return _fail("A5_STAGED_R3_PARTIAL_GRANTS")
					next.allocator_cursor = progressed_a4.cursor
		else:
			# Historical accepted path, or exact no-demands R3 case.
			var allocated := _allocate_population_demands(next.field, entries,
				String(next.owner_token), int(next.owner_epoch),
				int(next.revision), next.demands)
			if not bool(allocated.get("success", false)):
				return allocated
			next.allocated_field = allocated.field
			next.intake_by_id = allocated.intake_by_id
			next.phase = "ADVANCE"
			next.index = 0
	elif phase == "ADVANCE":
		var stop := mini(units.size(), index + max_worksets_per_call)
		var fragment_units: Array = units.slice(index, stop)
		if r3_mode and r2c_parallel_workers > 1 and fragment_units.size() > 1:
			# Outcomes are joined and CONSUMED in canonical unit/member
			# order, preserving propagule-limit and failure precedence.
			var parallel_result: Dictionary = _r2c_advance_staged_fragment_parallel(
				entries, fragment_units, next.samples, next.intake_by_id,
				next.next_population, next.propagules, r2c_parallel_workers)
			if not bool(parallel_result.get("success", false)):
				return parallel_result
			r2c_peak_workers = int(parallel_result.get("peak_workers", 0))
			r2c_threaded_worksets = int(parallel_result.get("threaded_worksets", 0))
		else:
			var by_id := _entries_by_id(entries)
			for unit_index in range(index, stop):
				var unit: Dictionary = units[unit_index]
				var task_entries: Array = []
				for raw_id in unit.member_ids:
					var id := String(raw_id)
					if not by_id.has(id):
						return _fail("A5_WORKSET_MEMBER")
					task_entries.append(by_id[id])
				var advanced := _advance_unit_worker(task_entries, next.samples,
					next.intake_by_id, int(unit.index))
				if not bool(advanced.get("success", false)):
					return advanced
				var consumed := _consume_advance_outcomes(
					unit, advanced.outcomes, next.next_population, next.propagules)
				if not bool(consumed.get("success", false)):
					return consumed
		next.index = stop
		if stop == units.size():
			var finalized := _canonical_advance_result(
				next.next_population, next.propagules, 0, 0)
			var result := _population_step_result(
				next.allocated_field, finalized.population, finalized.propagules)
			result["complete"] = true
			result["phase"] = "COMPLETE"
			# Host-only counters; absent from canonical state and cursor.
			result["r2c_peak_workers"] = r2c_peak_workers
			result["r2c_threaded_worksets"] = r2c_threaded_worksets
			if r2e_profile:
				result["r2e_profile"] = r2e_profile_values
			return result
	var r2e_seal_start_us: int = Time.get_ticks_usec() if r2e_profile else 0
	next = _seal_staged_cursor(next)
	if next.is_empty():
		return _fail("A5_STAGED_CURSOR_SEAL")
	if r2e_profile:
		r2e_profile_values["result_seal_us"] = Time.get_ticks_usec() - r2e_seal_start_us
	var response: Dictionary = {"success": true, "complete": false,
		"phase": String(next.phase),
		"cursor": next, "processed_worksets": max_worksets_per_call
			if phase != "ALLOCATE" else 0,
		"r2c_peak_workers": r2c_peak_workers,
		"r2c_threaded_worksets": r2c_threaded_worksets}
	if r2e_profile:
		response["r2e_profile"] = r2e_profile_values
	return response

## Stage C: same detached workset thread pattern as the established A13
## parallel-advance path. Work is speculative and each thread is joined
## BEFORE touching the canonical-ordered output arrays. No shared mutable
## alias is handed to nested workers. The single global A4 is upstream.
static func _r2c_advance_staged_fragment_parallel(entries: Array,
		units: Array, samples: Dictionary, intake_by_id: Dictionary,
		next_population: Array, propagules: Array, max_workers: int) -> Dictionary:
	if not valid_parallel_advance_workers(max_workers):
		return _fail("A5_R2C_ADVANCE_WORKERS")
	var by_id: Dictionary = _entries_by_id(entries)
	var offset := 0
	var peak_workers := 0
	var threaded_worksets := 0
	while offset < units.size():
		var stop := mini(units.size(), offset + max_workers)
		var active: Array = []
		for i in range(offset, stop):
			var unit: Dictionary = units[i]
			var task_entries: Array = []
			var task_samples: Dictionary = {}
			var task_intake: Dictionary = {}
			for raw_id in unit.member_ids:
				var id: String = String(raw_id)
				if not by_id.has(id):
					for started in active:
						started.thread.wait_to_finish()
					return _fail("A5_WORKSET_MEMBER")
				var entry: Dictionary = by_id[id]
				task_entries.append(entry.duplicate(true))
				if samples.has(id):
					task_samples[id] = samples[id].duplicate(true)
				if intake_by_id.has(id):
					task_intake[id] = intake_by_id[id].duplicate(true)
			var thread := Thread.new()
			var err: Error = thread.start(_advance_unit_worker.bind(
				task_entries, task_samples, task_intake, int(unit.index)))
			if err != OK:
				for started in active:
					started.thread.wait_to_finish()
				return _fail("A5_R2C_ADVANCE_THREAD_START")
			active.append({"index": int(unit.index), "thread": thread})
		peak_workers = maxi(peak_workers, active.size())
		var results: Dictionary = {}
		for started in active:
			# Always join the ENTIRE wave, even if a later result fails.
			results[int(started.index)] = started.thread.wait_to_finish()
		for i in range(offset, stop):
			var unit: Dictionary = units[i]
			var raw: Variant = results.get(int(unit.index), null)
			if not raw is Dictionary:
				return _fail("A5_R2C_ADVANCE_RESULT")
			var advanced: Dictionary = raw
			if not bool(advanced.get("success", false)):
				return advanced
			if int(advanced.get("unit_index", -1)) != int(unit.index):
				return _fail("A5_R2C_ADVANCE_INDEX")
			if bool(advanced.get("worker_is_main_thread", true)):
				return _fail("A5_R2C_ADVANCE_THREAD_CONTEXT")
			threaded_worksets += 1
			# Append to the EXISTING partial prefix (not a new isolated array)
			# so global MAX_PROPAGULES_PER_STEP and exact error precedence hold.
			var consumed: Dictionary = _consume_advance_outcomes(
				unit, advanced.outcomes, next_population, propagules)
			if not bool(consumed.get("success", false)):
				return consumed
		offset = stop
	return {"success": true, "peak_workers": peak_workers,
		"threaded_worksets": threaded_worksets}

static func _seal_staged_cursor(cursor: Dictionary) -> Dictionary:
	# Called ONLY for the owned cursor from staged_begin() or a detached
	# top-level/per-phase work copy. Never change a caller-provided cursor.
	cursor["checksum"] = ""
	var digest: String = _staged_cursor_checksum(cursor)
	if digest.is_empty():
		return {}
	cursor["checksum"] = digest
	return cursor

static func _staged_cursor_checksum(cursor: Dictionary) -> String:
	# The A14.5 accepted schema MUST keep its historical whole-envelope
	# digest. Only the versioned nonpersistent R3 schema may use a compact
	# binding to the independently sealed A4 R2 nested cursor.
	var unsigned: Dictionary = cursor.duplicate(false)
	unsigned["checksum"] = ""
	if String(cursor.get("schema", "")) == STAGED_SCHEMA_R3:
		var inner: Variant = cursor.get("allocator_cursor", null)
		if not inner is Dictionary:
			return ""
		if not inner.is_empty():
			if not C.keys(inner, StagedA4R2.KEYS) \
					or String(inner.get("schema", "")) != StagedA4R2.SCHEMA:
				return ""
			var inner_hash: String = String(inner.get("checksum", ""))
			if inner_hash.length() != 64:
				return ""
			# The checksum covers the original full R2 cursor. Its
			# contents are verified by R2.resume before any modification.
			unsigned["allocator_cursor"] = {
				"schema": StagedA4R2.SCHEMA, "checksum": inner_hash,
			}
	return C.digest(unsigned)

## Canonical propagule materialization (A5-owned admission).
## Without a mutation receipt the v1 parent-transfer witness applies (child
## blueprint hash bound to the parent's). With a sealed canonical mutation
## receipt (genome_mutation_receipt_v1) plus the parent blueprint, the
## mutated child genome is admitted through the receipt-binding witness.
## Fail-closed: any witness or receipt error returns {} — there is no
## fallback to the parent blueprint inside A5.
static func materialize_propagule(propagule: Dictionary, blueprint: Dictionary, paid_parent_state: Dictionary = {}, mutation_receipt: Dictionary = {}, parent_blueprint: Dictionary = {}) -> Dictionary:
	var state := LS.create_parent_transfer(blueprint, propagule, paid_parent_state, mutation_receipt, parent_blueprint)
	return {"blueprint": blueprint.duplicate(true), "state": state} if not state.is_empty() else {}

static func validate_propagule(v: Variant, blueprint: Dictionary, paid_parent_state: Dictionary = {}) -> String:
	return LS.validate_parent_transfer_witness(v, blueprint, paid_parent_state)

static func _advance_individual(source: Dictionary, blueprint: Dictionary, sample: Dictionary, field_intake: Dictionary) -> Dictionary:
	var state := source.duplicate(true)
	if state.age_ticks >= LS.MAX_AGE_TICK: return _fail("A5_AGE_LIMIT")
	var policy: Dictionary = blueprint.life_history
	var phenotype_before := H.compile(state.development, blueprint.genome)
	if phenotype_before.is_empty() or not F.valid_total_stock(field_intake): return _fail("A5_ADVANCE_INPUT")
	state.age_ticks += 1
	state.last_events = []
	state.last_environment_source = {
		"owner_token": sample.source.owner_token,
		"owner_epoch": sample.source.owner_epoch,
		"revision": sample.source.revision,
		"tick": sample.source.tick,
		"field_hash": sample.source.field_hash,
	}
	var assimilated := B.stock()
	assimilated.material_mg = field_intake.nutrient_mg + field_intake.organic_mg
	assimilated.water_mg = field_intake.water_mg
	var energy_headroom := maxi(0, B.MAX_STOCK - int(state.metabolic_reserves.energy_mj))
	assimilated.energy_mj = _photosynthesis_energy(phenotype_before, sample, field_intake.water_mg, policy, energy_headroom)
	if not _add_field_stock(state.resource_ledger.field_intake, field_intake): return _fail("A5_FIELD_INTAKE_OVERFLOW")
	if state.resource_ledger.external_energy_mj > C.MAX_INT - assimilated.energy_mj: return _fail("A5_ENERGY_SOURCE_OVERFLOW")
	state.resource_ledger.external_energy_mj += assimilated.energy_mj
	if not _add_reserve_stock(state.metabolic_reserves, assimilated): return _fail("A5_RESERVE_OVERFLOW")
	if not _add_cumulative_stock(state.resource_ledger.assimilated, assimilated): return _fail("A5_ASSIMILATED_LEDGER_OVERFLOW")

	var maintenance := _maintenance_cost(state, policy)
	var maintenance_paid := _can_pay(state.metabolic_reserves, maintenance)
	if maintenance_paid:
		if not _add_cumulative_stock(state.resource_ledger.maintenance, maintenance): return _fail("A5_MAINTENANCE_LEDGER_OVERFLOW")
		_pay(state.metabolic_reserves, maintenance)
		state.starvation_ticks = 0
		state.last_events.append({"outcome": "MAINTENANCE_PAID", "detail": "full deterministic maintenance debit"})
	else:
		state.starvation_ticks += 1
		state.last_events.append({"outcome": "MAINTENANCE_STARVED", "detail": "maintenance requirement not fully funded"})
		if state.starvation_ticks >= policy.survival.starvation_limit_ticks:
			state.alive = false
			state.last_events.append({"outcome": "DIED_STARVATION", "detail": "starvation limit reached; corpse resources remain in state"})
			if not LS.validate(state, blueprint).is_empty(): return _fail("A5_DEATH_STATE")
			return {"success": true, "state": state, "propagules": []}

	var activation := _growth_activation(sample, policy)
	var grant := B.stock()
	if maintenance_paid and activation > 0:
		var resuming_open_frame: bool = not state.development.frame.is_empty()
		if not resuming_open_frame:
			grant = _growth_grant(state.metabolic_reserves, policy, activation, state.development)
		else:
			grant = B.stock()
		var development_before: Dictionary = state.development
		var development_result := _advance_development(development_before, blueprint.genome, sample, grant)
		if not development_result.success: return development_result
		var new_modules: int = int(development_result.state.modules.size()) - int(development_before.modules.size())
		if new_modules < 0: return _fail("A5_GROWTH_MODULE_HISTORY")
		var birth_maintenance := _maintenance_cost_for_modules(new_modules, policy)
		var combined_growth_cost := grant.duplicate(true)
		for name in B.RESOURCES:
			combined_growth_cost[name] += birth_maintenance[name]
		if _can_pay(state.metabolic_reserves, combined_growth_cost):
			if not _stock_zero(grant):
				if not _add_cumulative_stock(state.resource_ledger.growth_transferred, grant): return _fail("A5_GROWTH_LEDGER_OVERFLOW")
				_pay(state.metabolic_reserves, grant)
			if new_modules > 0:
				if not _add_cumulative_stock(state.resource_ledger.maintenance, birth_maintenance): return _fail("A5_BIRTH_MAINTENANCE_LEDGER_OVERFLOW")
				_pay(state.metabolic_reserves, birth_maintenance)
				state.last_events.append({"outcome": "MAINTENANCE_PAID", "detail": "birth maintenance for %d new modules" % new_modules})
			state.development = development_result.state
			state.last_events.append({"outcome": "GROWTH_ACTIVE", "detail": "resume paid open frame; activation_permille=%d" % activation} if resuming_open_frame else {"outcome": "GROWTH_ACTIVE", "detail": "activation_permille=%d" % activation})
		else:
			state.last_events.append({"outcome": "GROWTH_SUPPRESSED", "detail": "candidate growth rolled back: birth maintenance budget unavailable"})
	elif maintenance_paid:
		state.last_events.append({"outcome": "GROWTH_SUPPRESSED", "detail": "regulatory gate freezes development and retained A2 reserves"})
	else:
		state.last_events.append({"outcome": "GROWTH_SUPPRESSED", "detail": "maintenance starvation suppresses development"})

	var propagules: Array = []
	var phenotype_after := H.compile(state.development, blueprint.genome)
	if phenotype_after.is_empty(): return _fail("A5_POST_GROWTH_PHENOTYPE")
	if maintenance_paid and _reproduction_ready(state, phenotype_after, policy):
		var reproduction := _reproduce(state, blueprint, policy)
		if reproduction.success:
			state = reproduction.state
			propagules = reproduction.propagules
		else:
			state.last_events.append({"outcome": "REPRODUCTION_WAIT", "detail": "mature body lacks fully funded propagule budget"})
	else:
		state.last_events.append({"outcome": "REPRODUCTION_WAIT", "detail": "maturity, interval, or reproductive module gate not met"})
	var validation := LS.validate(state, blueprint)
	if not validation.is_empty(): return _fail("A5_STATE:" + validation)
	return {"success": true, "state": state, "propagules": propagules}

static func _demands(state: Dictionary, blueprint: Dictionary, phenotype: Dictionary) -> Array:
	var uptake: Dictionary = blueprint.life_history.uptake
	var absorber_count := int(phenotype.module_roles.get("absorber", 0))
	var absorber_reach := int(phenotype.statistics.get("absorber_reach_mm", 0))
	var units := 1 + absorber_count + int(absorber_reach / 100)
	var desired_water := mini(uptake.basal_water_mg + units * uptake.water_per_absorber_unit_mg, F.MAX_REQUEST)
	var desired_nutrient := mini(uptake.basal_nutrient_mg + units * uptake.nutrient_per_absorber_unit_mg, F.MAX_REQUEST)
	var desired_organic := mini(uptake.basal_organic_mg + units * uptake.organic_per_absorber_unit_mg, F.MAX_REQUEST)
	var material_headroom := maxi(0, B.MAX_STOCK - int(state.metabolic_reserves.material_mg))
	var water_headroom := maxi(0, B.MAX_STOCK - int(state.metabolic_reserves.water_mg))
	var material_split := _clip_material_intake(desired_nutrient, desired_organic, material_headroom)
	var amounts := {
		"water_mg": mini(desired_water, water_headroom),
		"nutrient_mg": material_split.nutrient_mg,
		"organic_mg": material_split.organic_mg,
	}
	var out: Array = []
	for resource in F.RESOURCES:
		var amount: int = int(amounts[resource])
		if amount <= 0: continue
		var request_id := _demand_request_id(state.individual_id, state.age_ticks + 1, resource)
		out.append(Ports.demand(request_id, state.individual_id, resource, amount, state.position_mm, Ports.sampling_extent_mm(phenotype)))
	return out

static func _clip_material_intake(desired_nutrient: int, desired_organic: int, headroom: int) -> Dictionary:
	var nutrient := maxi(0, desired_nutrient)
	var organic := maxi(0, desired_organic)
	var available := maxi(0, headroom)
	var total := nutrient + organic
	if total <= available:
		return {"nutrient_mg": nutrient, "organic_mg": organic}
	if available == 0 or total == 0:
		return {"nutrient_mg": 0, "organic_mg": 0}
	var clipped_nutrient := int(available * nutrient / total)
	var clipped_organic := int(available * organic / total)
	var remainder := available - clipped_nutrient - clipped_organic
	# Fixed integer remainder rule: nutrient receives the at-most-one residual unit first.
	clipped_nutrient += mini(remainder, nutrient - clipped_nutrient)
	clipped_organic = available - clipped_nutrient
	return {"nutrient_mg": clipped_nutrient, "organic_mg": clipped_organic}

static func _demand_request_id(individual_id: String, age_tick: int, resource: String) -> String:
	return "life/%s/%06d/%s" % [individual_id.sha256_text(), age_tick, resource]

static func _propagule_id(parent_id: String, sequence: int) -> String:
	return LS.propagule_id(parent_id, sequence)

static func _photosynthesis_energy(phenotype: Dictionary, sample: Dictionary, granted_water_mg: int, policy: Dictionary, energy_headroom: int = B.MAX_STOCK) -> int:
	var area := int(phenotype.statistics.get("collector_area_mm2", 0))
	if area <= 0 or energy_headroom <= 0: return 0
	var light: int = sample.channels.light
	var water_factor := clampi(int(granted_water_mg * 1000 / maxi(1, policy.metabolism.photosynthesis_water_saturation_mg)), 0, 1000)
	var divisor: int = policy.metabolism.photosynthesis_area_divisor_mm2
	var raw := int(area * light * water_factor / maxi(1, divisor) / 1000000)
	return mini(clampi(raw, 0, policy.metabolism.max_photosynthesis_energy_mj), energy_headroom)

static func _maintenance_cost(state: Dictionary, policy: Dictionary) -> Dictionary:
	return _maintenance_cost_for_modules(state.development.modules.size(), policy)

static func _maintenance_cost_for_modules(modules: int, policy: Dictionary) -> Dictionary:
	return {
		"material_mg": 0,
		"water_mg": modules * policy.metabolism.maintenance_water_per_module_mg,
		"energy_mj": modules * policy.metabolism.maintenance_energy_per_module_mj,
	}

static func _growth_activation(sample: Dictionary, policy: Dictionary) -> int:
	var r: Dictionary = policy.regulation
	var light: int = sample.channels.light
	var water: int = sample.channels.water
	var competition: int = sample.channels.competition
	var temperature: int = sample.channels.temperature
	if light < r.growth_light_min or water < r.growth_water_min or competition > r.growth_competition_max:
		return 0
	if temperature < r.growth_temperature_min or temperature > r.growth_temperature_max:
		return 0
	var lf := 1000 if r.growth_light_min >= 1000 else int((light - r.growth_light_min) * 1000 / maxi(1, 1000 - r.growth_light_min))
	var wf := 1000 if r.growth_water_min >= 1000 else int((water - r.growth_water_min) * 1000 / maxi(1, 1000 - r.growth_water_min))
	var cf := 1000 if r.growth_competition_max <= 0 else int((r.growth_competition_max - competition) * 1000 / maxi(1, r.growth_competition_max))
	return clampi(mini(lf, mini(wf, cf)), 0, 1000)

static func _growth_grant(reserves: Dictionary, policy: Dictionary, activation: int, development: Dictionary = {}) -> Dictionary:
	var out := B.stock()
	for resource in B.RESOURCES:
		var fraction := int(reserves[resource] * policy.growth.transfer_permille * activation / 1000000)
		var requested := mini(fraction, policy.growth.max_transfer[resource])
		if development.is_empty():
			out[resource] = requested
		else:
			var headroom := maxi(0, B.MAX_STOCK - int(development.received[resource]))
			out[resource] = mini(requested, headroom)
	return out

static func _advance_development(source: Dictionary, genome: Dictionary, sample: Dictionary, grant: Dictionary) -> Dictionary:
	var state := source.duplicate(true)
	if state.frame.is_empty():
		var opened := K.begin_tick(state, genome, sample, grant, state.grant_seq + 1)
		if not opened.success: return _fail("A5_DEVELOPMENT_BEGIN:" + String(opened.error))
		state = opened.state
	for _slice in 4096:
		var result := K.advance(state, genome, 4096)
		if not result.success: return _fail("A5_DEVELOPMENT_ADVANCE:" + String(result.error))
		state = result.state
		if result.status == "TICK_COMPLETE" or result.status == "BUDGET_BLOCKED":
			return {"success": true, "state": state, "status": result.status}
	return _fail("A5_DEVELOPMENT_SLICE_LIMIT")

static func _reproduction_ready(state: Dictionary, phenotype: Dictionary, policy: Dictionary) -> bool:
	if state.age_ticks < policy.reproduction.maturity_ticks or state.age_ticks < state.next_reproduction_tick: return false
	return int(phenotype.module_roles.get("reproductive", 0)) >= policy.reproduction.required_reproductive_modules

static func _reproduce(source: Dictionary, blueprint: Dictionary, policy: Dictionary) -> Dictionary:
	var count: int = policy.reproduction.offspring_per_event
	var endowment: Dictionary = policy.reproduction.endowment
	var transfer := B.stock()
	for name in B.RESOURCES: transfer[name] = endowment[name] * count
	var fee := B.stock(); fee.energy_mj = policy.reproduction.fee_energy_mj * count
	var needed := B.stock()
	for name in B.RESOURCES: needed[name] = transfer[name] + fee[name]
	if not _can_pay(source.metabolic_reserves, needed): return _fail("A5_REPRODUCTION_RESOURCES")
	if source.reproduction_count > LS.MAX_OFFSPRING_COUNTER - count or source.propagule_seq > LS.MAX_OFFSPRING_COUNTER - count:
		return _fail("A5_OFFSPRING_COUNTER_LIMIT")
	var schedule_tick: int = source.age_ticks + policy.reproduction.interval_ticks
	if schedule_tick > LS.MAX_REPRODUCTION_SCHEDULE_TICK: return _fail("A5_REPRODUCTION_SCHEDULE_LIMIT")
	var state := source.duplicate(true)
	_pay(state.metabolic_reserves, needed)
	if not _add_cumulative_stock(state.resource_ledger.reproduction_transferred, transfer): return _fail("A5_REPRODUCTION_TRANSFER_OVERFLOW")
	if not _add_cumulative_stock(state.resource_ledger.reproduction_cost, fee): return _fail("A5_REPRODUCTION_COST_OVERFLOW")
	var first_sequence: int = state.propagule_seq
	state.propagule_seq += count
	state.reproduction_count += count
	state.next_reproduction_tick = schedule_tick
	state.last_events.append({"outcome": "REPRODUCED", "detail": "offspring=%d" % count})
	var validation := LS.validate(state, blueprint)
	if not validation.is_empty(): return _fail("A5_REPRODUCTION_STATE:" + validation)
	var paid_parent_state_hash := LS.state_hash(state, blueprint)
	if paid_parent_state_hash.is_empty(): return _fail("A5_REPRODUCTION_STATE_HASH")
	var propagules: Array = []
	for offset in count:
		var sequence := first_sequence + offset
		propagules.append({
			"schema": PROPAGULE_SCHEMA,
			"id": _propagule_id(state.individual_id, sequence),
			"parent_id": state.individual_id,
			"sequence": sequence,
			"blueprint_hash": BP.biological_hash(blueprint),
			"birth_tick": state.age_ticks,
			"position_mm": state.position_mm.duplicate(),
			"endowment": endowment.duplicate(true),
			"parent_state_hash": paid_parent_state_hash,
		})
	return {"success": true, "state": state, "propagules": propagules}

static func _can_pay(reserves: Dictionary, cost: Dictionary) -> bool:
	for name in B.RESOURCES:
		if cost[name] < 0 or cost[name] > reserves[name]: return false
	return true

static func _pay(reserves: Dictionary, cost: Dictionary) -> void:
	for name in B.RESOURCES: reserves[name] -= cost[name]

static func _add_reserve_stock(target: Dictionary, delta: Dictionary) -> bool:
	for name in B.RESOURCES:
		if delta[name] < 0 or target[name] > B.MAX_STOCK - delta[name]: return false
	for name in B.RESOURCES: target[name] += delta[name]
	return true

static func _add_cumulative_stock(target: Dictionary, delta: Dictionary) -> bool:
	for name in B.RESOURCES:
		if delta[name] < 0 or target[name] > C.MAX_INT - delta[name]: return false
	for name in B.RESOURCES: target[name] += delta[name]
	return true

static func _add_field_stock(target: Dictionary, delta: Dictionary) -> bool:
	for name in F.RESOURCES:
		if delta[name] < 0 or target[name] > C.MAX_INT - delta[name]: return false
	for name in F.RESOURCES: target[name] += delta[name]
	return true

static func _stock_zero(v: Dictionary) -> bool:
	for name in B.RESOURCES:
		if v[name] != 0: return false
	return true

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
