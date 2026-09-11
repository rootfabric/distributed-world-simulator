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
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const MAX_POPULATION := 128
const MAX_PROPAGULES_PER_STEP := 512
const PROPAGULE_SCHEMA := "dws.ecology.propagule.v1"

static func individual(blueprint: Dictionary, individual_id: String, position_mm: Array, endowment: Dictionary = {}, origin_kind: String = "FOUNDER_ENDOWMENT") -> Dictionary:
	if origin_kind != "FOUNDER_ENDOWMENT": return {}
	var state := LS.create(blueprint, individual_id, position_mm, endowment, "FOUNDER_ENDOWMENT")
	return {"blueprint": blueprint.duplicate(true), "state": state} if not state.is_empty() else {}

static func step_population(field: Dictionary, population: Array, owner_token: String, owner_epoch: int, revision: int) -> Dictionary:
	if not F.validate_state(field).is_empty(): return _fail("A5_FIELD")
	if population.is_empty() or population.size() > MAX_POPULATION: return _fail("A5_POPULATION_SIZE")
	if owner_token != field.owner_token: return _fail("STALE_OWNER")
	if owner_epoch != field.owner_epoch: return _fail("STALE_OWNER_EPOCH")
	if revision != field.revision: return _fail("STALE_REVISION")
	var entries: Array = []
	var seen := {}
	for entry in population:
		if not C.keys(entry, ["blueprint", "state"]) or not entry.blueprint is Dictionary or not entry.state is Dictionary:
			return _fail("A5_ENTRY")
		if not BP.validate(entry.blueprint).is_empty() or not LS.validate(entry.state, entry.blueprint).is_empty():
			return _fail("A5_ENTRY_INVALID")
		var id: String = entry.state.individual_id
		if seen.has(id): return _fail("A5_DUPLICATE_INDIVIDUAL")
		seen[id] = true
		entries.append({"blueprint": entry.blueprint.duplicate(true), "state": entry.state.duplicate(true)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.state.individual_id < b.state.individual_id)

	var samples := {}
	var demands: Array = []
	for entry in entries:
		var state: Dictionary = entry.state
		if not state.alive:
			continue
		var phenotype := H.compile(state.development, entry.blueprint.genome)
		if phenotype.is_empty(): return _fail("A5_PHENOTYPE")
		var extent := Ports.sampling_extent_mm(phenotype)
		var request := Ports.sample_request(state.individual_id, state.position_mm, extent)
		var sampled := Field.sample(field, request)
		if not sampled.success: return _fail("A5_SAMPLE:" + String(sampled.error))
		samples[state.individual_id] = sampled.sample
		var generated := _demands(state, entry.blueprint, phenotype)
		for demand in generated:
			demands.append(demand)

	var field_after := field.duplicate(true)
	var intake_by_id := {}
	for entry in entries:
		intake_by_id[entry.state.individual_id] = F.stock()
	if not demands.is_empty():
		var allocated := Field.allocate_demands(field, demands, owner_token, owner_epoch, revision)
		if not allocated.success: return _fail("A5_ALLOCATION:" + String(allocated.error))
		field_after = allocated.state
		for grant in allocated.grants:
			var id: String = grant.organism_id
			if not intake_by_id.has(id): return _fail("A5_GRANT_OWNER")
			intake_by_id[id][grant.resource] += grant.granted

	var next_population: Array = []
	var propagules: Array = []
	for entry in entries:
		var state: Dictionary = entry.state
		var blueprint: Dictionary = entry.blueprint
		if not state.alive:
			var inert := state.duplicate(true)
			inert.last_events = [{"outcome": "DEAD_INERT", "detail": "no resource requests or lifecycle transitions"}]
			next_population.append({"blueprint": blueprint, "state": inert})
			continue
		var advanced := _advance_individual(state, blueprint, samples[state.individual_id], intake_by_id[state.individual_id])
		if not advanced.success: return advanced
		next_population.append({"blueprint": blueprint, "state": advanced.state})
		for propagule in advanced.propagules:
			if propagules.size() >= MAX_PROPAGULES_PER_STEP: return _fail("A5_PROPAGULE_LIMIT")
			propagules.append(propagule)
	next_population.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.state.individual_id < b.state.individual_id)
	propagules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return {"success": true, "field": field_after, "population": next_population, "propagules": propagules, "field_hash": Field.state_hash(field_after)}

static func materialize_propagule(propagule: Dictionary, blueprint: Dictionary, paid_parent_state: Dictionary = {}) -> Dictionary:
	var state := LS.create_parent_transfer(blueprint, propagule, paid_parent_state)
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
		var resuming_open_frame := not state.development.frame.is_empty()
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
