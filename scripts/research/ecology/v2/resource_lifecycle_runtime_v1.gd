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
	var state := LS.create(blueprint, individual_id, position_mm, endowment, origin_kind)
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

static func materialize_propagule(propagule: Dictionary, blueprint: Dictionary) -> Dictionary:
	if not validate_propagule(propagule, blueprint).is_empty(): return {}
	return individual(blueprint, propagule.id, propagule.position_mm, propagule.endowment, "PARENT_TRANSFER")

static func validate_propagule(v: Variant, blueprint: Dictionary) -> String:
	if not BP.validate(blueprint).is_empty(): return "PROPAGULE_BLUEPRINT"
	var keys := ["schema", "id", "parent_id", "blueprint_hash", "birth_tick", "position_mm", "endowment", "parent_state_hash"]
	if not C.keys(v, keys) or v.schema != PROPAGULE_SCHEMA: return "PROPAGULE_SCHEMA"
	if not C.identifier(v.id) or not C.identifier(v.parent_id) or v.blueprint_hash != BP.biological_hash(blueprint): return "PROPAGULE_IDENTITY"
	if not C.integer(v.birth_tick, 1, 1000000) or not C.vector(v.position_mm, F.MAX_PORT_COORD_MM): return "PROPAGULE_POSITION"
	if not B.valid_stock(v.endowment) or not F.valid_hash(v.parent_state_hash): return "PROPAGULE_RESOURCE"
	return ""

static func _advance_individual(source: Dictionary, blueprint: Dictionary, sample: Dictionary, field_intake: Dictionary) -> Dictionary:
	var state := source.duplicate(true)
	if state.age_ticks >= 1000000: return _fail("A5_AGE_LIMIT")
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
	assimilated.energy_mj = _photosynthesis_energy(phenotype_before, sample, field_intake.water_mg, policy)
	if not _add_field_stock(state.resource_ledger.field_intake, field_intake): return _fail("A5_FIELD_INTAKE_OVERFLOW")
	if state.resource_ledger.external_energy_mj > B.MAX_STOCK - assimilated.energy_mj: return _fail("A5_ENERGY_SOURCE_OVERFLOW")
	state.resource_ledger.external_energy_mj += assimilated.energy_mj
	if not _add_stock(state.metabolic_reserves, assimilated) or not _add_stock(state.resource_ledger.assimilated, assimilated):
		return _fail("A5_RESOURCE_OVERFLOW")

	var maintenance := _maintenance_cost(state, policy)
	var maintenance_paid := _can_pay(state.metabolic_reserves, maintenance)
	if maintenance_paid:
		_pay(state.metabolic_reserves, maintenance)
		_add_stock(state.resource_ledger.maintenance, maintenance)
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
	if maintenance_paid:
		if state.development.frame.is_empty() and activation > 0:
			grant = _growth_grant(state.metabolic_reserves, policy, activation)
			state.last_events.append({"outcome": "GROWTH_ACTIVE", "detail": "activation_permille=%d" % activation})
		else:
			state.last_events.append({"outcome": "GROWTH_SUPPRESSED", "detail": "regulation or unfinished development frame suppressed new grant"})
		if not state.development.frame.is_empty():
			grant = B.stock()
		var development_result := _advance_development(state.development, blueprint.genome, sample, grant)
		if not development_result.success: return development_result
		if not _stock_zero(grant):
			if not _can_pay(state.metabolic_reserves, grant): return _fail("A5_GROWTH_DEBIT")
			_pay(state.metabolic_reserves, grant)
			_add_stock(state.resource_ledger.growth_transferred, grant)
		state.development = development_result.state
	else:
		state.last_events.append({"outcome": "GROWTH_SUPPRESSED", "detail": "maintenance starvation suppresses development"})

	var propagules: Array = []
	var phenotype_after := H.compile(state.development, blueprint.genome)
	if phenotype_after.is_empty(): return _fail("A5_POST_GROWTH_PHENOTYPE")
	if _reproduction_ready(state, phenotype_after, policy):
		var reproduction := _reproduce(state, blueprint, policy)
		if reproduction.success:
			state = reproduction.state
			propagules = reproduction.propagules
			state.last_events.append({"outcome": "REPRODUCED", "detail": "offspring=%d" % propagules.size()})
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
	var amounts := {
		"water_mg": uptake.basal_water_mg + units * uptake.water_per_absorber_unit_mg,
		"nutrient_mg": uptake.basal_nutrient_mg + units * uptake.nutrient_per_absorber_unit_mg,
		"organic_mg": uptake.basal_organic_mg + units * uptake.organic_per_absorber_unit_mg,
	}
	var out: Array = []
	for resource in F.RESOURCES:
		var amount := mini(int(amounts[resource]), F.MAX_REQUEST)
		if amount <= 0: continue
		var request_id := "%s.life.%06d.%s" % [state.individual_id, state.age_ticks + 1, resource]
		out.append(Ports.demand(request_id, state.individual_id, resource, amount, state.position_mm, Ports.sampling_extent_mm(phenotype)))
	return out

static func _photosynthesis_energy(phenotype: Dictionary, sample: Dictionary, granted_water_mg: int, policy: Dictionary) -> int:
	var area := int(phenotype.statistics.get("collector_area_mm2", 0))
	if area <= 0: return 0
	var light: int = sample.channels.light
	var water_factor := clampi(int(granted_water_mg * 1000 / maxi(1, policy.metabolism.photosynthesis_water_saturation_mg)), 0, 1000)
	var divisor: int = policy.metabolism.photosynthesis_area_divisor_mm2
	var raw := int(area * light * water_factor / maxi(1, divisor) / 1000000)
	return clampi(raw, 0, policy.metabolism.max_photosynthesis_energy_mj)

static func _maintenance_cost(state: Dictionary, policy: Dictionary) -> Dictionary:
	var modules: int = state.development.modules.size()
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

static func _growth_grant(reserves: Dictionary, policy: Dictionary, activation: int) -> Dictionary:
	var out := B.stock()
	for resource in B.RESOURCES:
		var fraction := int(reserves[resource] * policy.growth.transfer_permille * activation / 1000000)
		out[resource] = mini(fraction, policy.growth.max_transfer[resource])
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
	var state := source.duplicate(true)
	_pay(state.metabolic_reserves, needed)
	_add_stock(state.resource_ledger.reproduction_transferred, transfer)
	_add_stock(state.resource_ledger.reproduction_cost, fee)
	var propagules: Array = []
	for _i in count:
		var id := "seed/%s/%06d" % [state.individual_id.sha256_text().substr(0, 16), state.propagule_seq]
		state.propagule_seq += 1
		propagules.append({
			"schema": PROPAGULE_SCHEMA,
			"id": id,
			"parent_id": state.individual_id,
			"blueprint_hash": BP.biological_hash(blueprint),
			"birth_tick": state.age_ticks,
			"position_mm": state.position_mm.duplicate(),
			"endowment": endowment.duplicate(true),
			"parent_state_hash": LS.state_hash(source, blueprint),
		})
	state.reproduction_count += count
	state.next_reproduction_tick = state.age_ticks + policy.reproduction.interval_ticks
	return {"success": true, "state": state, "propagules": propagules}

static func _can_pay(reserves: Dictionary, cost: Dictionary) -> bool:
	for name in B.RESOURCES:
		if cost[name] < 0 or cost[name] > reserves[name]: return false
	return true

static func _pay(reserves: Dictionary, cost: Dictionary) -> void:
	for name in B.RESOURCES: reserves[name] -= cost[name]

static func _add_stock(target: Dictionary, delta: Dictionary) -> bool:
	for name in B.RESOURCES:
		if delta[name] < 0 or target[name] > B.MAX_STOCK - delta[name]: return false
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
