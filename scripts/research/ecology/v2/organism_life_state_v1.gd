extends RefCounted
## A5 persistent lifecycle state. Resource accounting is separate from A2 body accounting.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const S = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const SCHEMA := "dws.ecology.organism-life-state.v1"
const ORIGINS := ["FOUNDER_ENDOWMENT", "PARENT_TRANSFER"]
const OUTCOMES := ["MAINTENANCE_PAID", "MAINTENANCE_STARVED", "GROWTH_ACTIVE", "GROWTH_SUPPRESSED", "REPRODUCED", "REPRODUCTION_WAIT", "DIED_STARVATION", "DEAD_INERT"]
const MAX_AGE_TICK := 1000000
const MAX_REPRODUCTION_SCHEDULE_TICK := 2000000
const MAX_OFFSPRING_PER_EVENT := 4
const MAX_OFFSPRING_COUNTER := MAX_AGE_TICK * MAX_OFFSPRING_PER_EVENT

static func create(blueprint: Dictionary, individual_id: String, position_mm: Array, endowment: Dictionary = {}, origin_kind: String = "FOUNDER_ENDOWMENT") -> Dictionary:
	if not BP.validate(blueprint).is_empty() or not C.identifier(individual_id) or not C.vector(position_mm, F.MAX_PORT_COORD_MM) or not origin_kind in ORIGINS:
		return {}
	var initial := B.stock() if endowment.is_empty() else endowment.duplicate(true)
	if not B.valid_stock(initial): return {}
	var development := S.create(blueprint.genome, individual_id, B.stock())
	if development.is_empty(): return {}
	var state := {
		"schema": SCHEMA,
		"blueprint_hash": BP.biological_hash(blueprint),
		"individual_id": individual_id,
		"position_mm": position_mm.duplicate(),
		"origin_kind": origin_kind,
		"alive": true,
		"age_ticks": 0,
		"starvation_ticks": 0,
		"next_reproduction_tick": blueprint.life_history.reproduction.maturity_ticks,
		"reproduction_count": 0,
		"propagule_seq": 0,
		"metabolic_reserves": initial.duplicate(true),
		"resource_ledger": {
			"initial": initial.duplicate(true),
			"field_intake": F.stock(),
			"external_energy_mj": 0,
			"assimilated": B.stock(),
			"maintenance": B.stock(),
			"growth_transferred": B.stock(),
			"reproduction_transferred": B.stock(),
			"reproduction_cost": B.stock(),
		},
		"development": development,
		"last_environment_source": {},
		"last_events": [],
	}
	return state if validate(state, blueprint).is_empty() else {}

static func validate(v: Variant, blueprint: Dictionary) -> String:
	if not BP.validate(blueprint).is_empty(): return "LIFE_STATE_BLUEPRINT"
	var keys := ["schema", "blueprint_hash", "individual_id", "position_mm", "origin_kind", "alive", "age_ticks", "starvation_ticks", "next_reproduction_tick", "reproduction_count", "propagule_seq", "metabolic_reserves", "resource_ledger", "development", "last_environment_source", "last_events"]
	if not C.keys(v, keys) or v.schema != SCHEMA: return "LIFE_STATE_SCHEMA"
	if v.blueprint_hash != BP.biological_hash(blueprint) or not C.identifier(v.individual_id): return "LIFE_STATE_BINDING"
	if not C.vector(v.position_mm, F.MAX_PORT_COORD_MM) or not v.origin_kind in ORIGINS or not v.alive is bool: return "LIFE_STATE_IDENTITY"
	if not C.integer(v.age_ticks, 0, MAX_AGE_TICK) or not C.integer(v.starvation_ticks, 0, MAX_AGE_TICK): return "LIFE_STATE_AGE"
	if v.starvation_ticks > v.age_ticks: return "LIFE_STARVATION_CAUSALITY"
	var starvation_limit: int = blueprint.life_history.survival.starvation_limit_ticks
	if v.alive:
		if v.starvation_ticks >= starvation_limit: return "LIFE_STARVATION_POLICY"
	elif v.starvation_ticks != starvation_limit:
		return "LIFE_STARVATION_POLICY"
	if not C.integer(v.next_reproduction_tick, 0, MAX_REPRODUCTION_SCHEDULE_TICK) or not C.integer(v.reproduction_count, 0, MAX_OFFSPRING_COUNTER) or not C.integer(v.propagule_seq, 0, MAX_OFFSPRING_COUNTER): return "LIFE_STATE_COUNTER"
	if v.propagule_seq != v.reproduction_count: return "LIFE_PROPAGULE_SEQUENCE"
	if v.reproduction_count > v.age_ticks * MAX_OFFSPRING_PER_EVENT: return "LIFE_REPRODUCTION_CAUSALITY"
	var reproduction: Dictionary = blueprint.life_history.reproduction
	var offspring_per_event: int = reproduction.offspring_per_event
	if v.reproduction_count % offspring_per_event != 0: return "LIFE_REPRODUCTION_EVENT_ALIGNMENT"
	var event_count: int = int(v.reproduction_count / offspring_per_event)
	var maturity_tick: int = reproduction.maturity_ticks
	var interval_ticks: int = reproduction.interval_ticks
	var last_reproduction_tick := -1
	if event_count == 0:
		if v.next_reproduction_tick != maturity_tick: return "LIFE_REPRODUCTION_SCHEDULE"
	else:
		last_reproduction_tick = v.next_reproduction_tick - interval_ticks
		if last_reproduction_tick < maturity_tick or last_reproduction_tick > v.age_ticks: return "LIFE_REPRODUCTION_SCHEDULE"
		var schedule_events: int = 1 + int((last_reproduction_tick - maturity_tick) / interval_ticks)
		if event_count > schedule_events: return "LIFE_REPRODUCTION_FREQUENCY"
		var max_events: int = 0 if v.age_ticks < maturity_tick else 1 + int((v.age_ticks - maturity_tick) / interval_ticks)
		if event_count > max_events: return "LIFE_REPRODUCTION_CAUSALITY"
		if last_reproduction_tick > v.age_ticks - v.starvation_ticks: return "LIFE_REPRODUCTION_STARVATION_WINDOW"
	if not B.valid_stock(v.metabolic_reserves): return "LIFE_STATE_RESERVES"
	if not _valid_ledger(v.resource_ledger): return "LIFE_STATE_LEDGER"
	if v.resource_ledger.assimilated.material_mg != v.resource_ledger.field_intake.nutrient_mg + v.resource_ledger.field_intake.organic_mg: return "LIFE_FIELD_MATERIAL_SOURCE"
	if v.resource_ledger.assimilated.water_mg != v.resource_ledger.field_intake.water_mg: return "LIFE_FIELD_WATER_SOURCE"
	if v.resource_ledger.assimilated.energy_mj != v.resource_ledger.external_energy_mj: return "LIFE_EXTERNAL_ENERGY_SOURCE"
	for name in B.RESOURCES:
		var expected_transfer: int = v.reproduction_count * reproduction.endowment[name]
		if v.resource_ledger.reproduction_transferred[name] != expected_transfer:
			return "LIFE_REPRODUCTION_TRANSFER_%s" % name
		var expected_cost: int = v.reproduction_count * reproduction.fee_energy_mj if name == "energy_mj" else 0
		if v.resource_ledger.reproduction_cost[name] != expected_cost:
			return "LIFE_REPRODUCTION_COST_%s" % name
	if not v.development is Dictionary or v.development.individual_id != v.individual_id: return "LIFE_STATE_DEVELOPMENT_BINDING"
	var development_error := S.validate(v.development, blueprint.genome)
	if not development_error.is_empty(): return development_error
	for name in B.RESOURCES:
		if v.resource_ledger.growth_transferred[name] != v.development.received[name]:
			return "LIFE_A2_TRANSFER_%s" % name
	if event_count > 0:
		var phenotype := H.compile(v.development, blueprint.genome)
		if phenotype.is_empty(): return "LIFE_REPRODUCTION_PHENOTYPE"
		if int(phenotype.module_roles.get("reproductive", 0)) < reproduction.required_reproductive_modules:
			return "LIFE_REPRODUCTION_MODULE_HISTORY"
	if not _source_valid(v.last_environment_source): return "LIFE_STATE_ENVIRONMENT_SOURCE"
	if not _events_valid(v.last_events): return "LIFE_STATE_EVENTS"
	var sources := B.stock()
	var sinks := B.stock()
	for name in B.RESOURCES:
		sources[name] = v.resource_ledger.initial[name] + v.resource_ledger.assimilated[name]
		sinks[name] = v.metabolic_reserves[name] + v.resource_ledger.maintenance[name] + v.resource_ledger.growth_transferred[name] + v.resource_ledger.reproduction_transferred[name] + v.resource_ledger.reproduction_cost[name]
		if sources[name] != sinks[name]: return "LIFE_RESOURCE_CONSERVATION_%s" % name
	return "NONCANONICAL_LIFE_STATE" if C.encode(v).is_empty() else ""

static func state_hash(v: Dictionary, blueprint: Dictionary) -> String:
	return C.digest(v) if validate(v, blueprint).is_empty() else ""

static func serialize(v: Dictionary, blueprint: Dictionary) -> String:
	if not validate(v, blueprint).is_empty(): return ""
	return C.encode({"schema": "dws.ecology.life-state-file.v1", "blueprint": blueprint, "state": v, "state_hash": C.digest(v)})

static func deserialize(text: String) -> Dictionary:
	var decoded := C.decode(text)
	if not decoded.success or not decoded.value is Dictionary: return {}
	var v: Dictionary = decoded.value
	if not C.keys(v, ["schema", "blueprint", "state", "state_hash"]) or v.schema != "dws.ecology.life-state-file.v1": return {}
	if not v.blueprint is Dictionary or not v.state is Dictionary: return {}
	if not validate(v.state, v.blueprint).is_empty() or C.digest(v.state) != v.state_hash: return {}
	return {"blueprint": v.blueprint, "state": v.state}

static func valid_cumulative_stock(v: Variant) -> bool:
	if not C.keys(v, B.RESOURCES): return false
	for name in B.RESOURCES:
		if not C.integer(v[name], 0, C.MAX_INT): return false
	return true

static func _valid_ledger(v: Variant) -> bool:
	var cumulative_keys := ["assimilated", "maintenance", "growth_transferred", "reproduction_transferred", "reproduction_cost"]
	var keys := ["initial", "field_intake", "external_energy_mj", "assimilated", "maintenance", "growth_transferred", "reproduction_transferred", "reproduction_cost"]
	if not C.keys(v, keys): return false
	if not B.valid_stock(v.initial): return false
	for k in cumulative_keys:
		if not valid_cumulative_stock(v[k]): return false
	if not F.valid_total_stock(v.field_intake): return false
	return C.integer(v.external_energy_mj, 0, C.MAX_INT)

static func _source_valid(v: Variant) -> bool:
	if not v is Dictionary: return false
	if v.is_empty(): return true
	if not C.keys(v, ["owner_token", "owner_epoch", "revision", "tick", "field_hash"]): return false
	if not C.identifier(v.owner_token) or not C.integer(v.owner_epoch, 0, F.MAX_OWNER_EPOCH): return false
	if not C.integer(v.revision, 0, F.MAX_REVISION) or not C.integer(v.tick, 0, F.MAX_TICK): return false
	return F.valid_hash(v.field_hash)

static func _events_valid(v: Variant) -> bool:
	if not v is Array or v.size() > 64: return false
	for event in v:
		if not C.keys(event, ["outcome", "detail"]) or not event.outcome in OUTCOMES or not event.detail is String or event.detail.length() > 128:
			return false
	return true
