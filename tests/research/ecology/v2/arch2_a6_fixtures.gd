extends RefCounted
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const LH = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const R = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const A6 = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")

static func stock(m: int, w: int, e: int) -> Dictionary:
	return {"material_mg": m, "water_mg": w, "energy_mj": e}

static func field(stocks: Dictionary = F.stock(), capacity: int = 1000000, origin: Array = [0, 0, 0], width: int = 1) -> Dictionary:
	return Field.create("a6.patch", 1, origin, 1000, width, 1, stocks, F.stock(capacity), F.signals(1000, 500, 0, 0))

static func policy() -> Dictionary:
	var p := LH.create_default()
	for k in p.uptake: p.uptake[k] = 0
	p.metabolism.maintenance_water_per_module_mg = 0
	p.metabolism.maintenance_energy_per_module_mj = 0
	p.growth.transfer_permille = 0
	p.growth.max_transfer = B.stock()
	p.regulation.growth_water_min = 0
	p.reproduction.maturity_ticks = 1000000
	return p

static func genome(reproductive: bool = false) -> Dictionary:
	var actions: Array = [P.action("retire")]
	if reproductive: actions.push_front(P.action("differentiate", "reproductive", [0, 10, 0], 1))
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 32, "max_depth": 1, "rules": [P.rule("start", actions, "start")]}, "A6 paid lifecycle witness")

static func root(id: String, reserve: Dictionary, dying: bool = false, position: Array = [500, 0, 500]) -> Dictionary:
	var p := policy()
	if dying:
		p.metabolism.maintenance_water_per_module_mg = 10
		p.survival.starvation_limit_ticks = 1
	return R.individual(BP.create(genome(), p), id, position, reserve)

static func recipient() -> Dictionary:
	var p := policy()
	p.uptake.basal_nutrient_mg = 100
	return R.individual(BP.create(genome(), p), "recipient", [500, 0, 500], B.stock())

static func reproductive() -> Dictionary:
	var p := policy()
	p.uptake.basal_water_mg = 5000
	p.uptake.basal_nutrient_mg = 5000
	p.uptake.basal_organic_mg = 5000
	p.metabolism.maintenance_water_per_module_mg = 2500
	p.survival.starvation_limit_ticks = 1
	p.growth.transfer_permille = 500
	p.growth.max_transfer = B.stock(20000)
	p.reproduction.maturity_ticks = 1
	p.reproduction.interval_ticks = 1
	p.reproduction.endowment = stock(100, 50, 20)
	p.reproduction.fee_energy_mj = 1
	return R.individual(BP.create(genome(true), p), "donor", [500, 0, 500], B.stock(3000))

static func prepared_donor() -> Dictionary:
	var donor := reproductive()
	var f := field(F.stock(900000))
	var prepared := R.step_population(f, [donor], f.owner_token, f.owner_epoch, f.revision)
	if not prepared.success or prepared.propagules.size() != 1: return {}
	return prepared.population[0]

static func step(state: Dictionary) -> Dictionary:
	return A6.advance(state, state.frame.field.owner_token, state.frame.field.owner_epoch, state.frame.step)

static func entry(state: Dictionary, id: String) -> Dictionary:
	for text in state.frame.population:
		var e := LS.deserialize(text)
		if not e.is_empty() and e.state.individual_id == id: return e
	return {}

static func reseal(state: Dictionary) -> Dictionary:
	var s := state.duplicate(true)
	s.erase("integrity_hash")
	var hash := C.digest(s)
	s["integrity_hash"] = hash
	return s
