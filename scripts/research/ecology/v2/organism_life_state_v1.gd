extends RefCounted
## A5 persistent lifecycle state. Resource accounting is separate from A2 body accounting.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")\nconst Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const S = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const SCHEMA := "dws.ecology.organism-life-state.v1"
const PROPAGULE_SCHEMA := "dws.ecology.propagule.v1"
const PARENT_TRANSFER_RECEIPT_SCHEMA := "dws.ecology.parent-transfer-origin-receipt.v1"
const ORIGINS := ["FOUNDER_ENDOWMENT", "PARENT_TRANSFER"]
const OUTCOMES := ["MAINTENANCE_PAID", "MAINTENANCE_STARVED", "GROWTH_ACTIVE", "GROWTH_SUPPRESSED", "REPRODUCED", "REPRODUCTION_WAIT", "DIED_STARVATION", "DEAD_INERT"]
const MAX_AGE_TICK := 1000000
const MAX_REPRODUCTION_SCHEDULE_TICK := 2000000
const MAX_OFFSPRING_PER_EVENT := 4
const MAX_OFFSPRING_COUNTER := MAX_AGE_TICK * MAX_OFFSPRING_PER_EVENT
# CanonicalValueV1 rejects nesting deeper than 24. A full A5 state can consume
# depth 7 before lineage nesting, the state-file wrapper adds 1, and each exact
# embedded parent state adds 2. Eight parent-transfer links fit the canonical
# budget; the ninth is rejected before a noncanonical persisted state can exist.
const MAX_PARENT_PROOF_DEPTH := 8

static func create(blueprint: Dictionary, individual_id: String, position_mm: Array, endowment: Dictionary = {}, origin_kind: String = "FOUNDER_ENDOWMENT") -> Dictionary:
	# Public generic construction is founder-only. Parent transfers require an exact paid-parent witness.
	if origin_kind != "FOUNDER_ENDOWMENT": return {}
	if not BP.validate(blueprint).is_empty() or not C.identifier(individual_id) or not C.vector(position_mm, F.MAX_PORT_COORD_MM):
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
		"origin_kind": "FOUNDER_ENDOWMENT",
		"origin_receipt": {},
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

static func create_parent_transfer(blueprint: Dictionary, propagule: Dictionary, paid_parent_state: Dictionary) -> Dictionary:
	if not validate_parent_transfer_witness(propagule, blueprint, paid_parent_state).is_empty(): return {}
	var individual_id: String = propagule.id
	var position_mm: Array = propagule.position_mm
	var initial: Dictionary = propagule.endowment.duplicate(true)
	var development := S.create(blueprint.genome, individual_id, B.stock())
	if development.is_empty(): return {}
	var receipt := {
		"schema": PARENT_TRANSFER_RECEIPT_SCHEMA,
		"blueprint_hash": propagule.blueprint_hash,
		"parent_id": propagule.parent_id,
		"sequence": propagule.sequence,
		"birth_tick": propagule.birth_tick,
		"position_mm": propagule.position_mm.duplicate(),
		"endowment": propagule.endowment.duplicate(true),
		"parent_state_hash": propagule.parent_state_hash,
		"parent_state": paid_parent_state.duplicate(true),
	}
	var state := {
		"schema": SCHEMA,
		"blueprint_hash": BP.biological_hash(blueprint),
		"individual_id": individual_id,
		"position_mm": position_mm.duplicate(),
		"origin_kind": "PARENT_TRANSFER",
		"origin_receipt": receipt,
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


## Build a caller-verifiable receipt proving that child_blueprint is exactly
## the result of the canonical A3 mutation applied to parent_blueprint.
static func create_mutation_receipt(parent_blueprint: Dictionary, child_blueprint: Dictionary, seed: int, operator: String, event_hash: String) -> Dictionary:
	if not BP.validate(parent_blueprint).is_empty() or not BP.validate(child_blueprint).is_empty(): return {}
	if not C.integer(seed, 0, C.MAX_INT) or not operator in Mutation.OPERATORS or not F.valid_hash(event_hash): return {}
	if child_blueprint.life_history != parent_blueprint.life_history: return {}
	var replay := Mutation.mutate(parent_blueprint.genome, seed, operator)
	if not bool(replay.get("success", false)) or String(replay.get("event_hash", "")) != event_hash: return {}
	var expected := BP.create(replay.genome, parent_blueprint.life_history)
	if expected.is_empty() or BP.biological_hash(expected) != BP.biological_hash(child_blueprint): return {}
	return {
		"schema": MUTATION_RECEIPT_SCHEMA,
		"parent_blueprint": parent_blueprint.duplicate(true),
		"parent_blueprint_hash": BP.biological_hash(parent_blueprint),
		"child_blueprint_hash": BP.biological_hash(child_blueprint),
		"operator": operator,
		"seed": seed,
		"event_hash": event_hash,
	}

static func validate_mutation_receipt(receipt: Variant, child_blueprint: Dictionary) -> String:
	if not C.keys(receipt, ["schema", "parent_blueprint", "parent_blueprint_hash", "child_blueprint_hash", "operator", "seed", "event_hash"]) or receipt.schema != MUTATION_RECEIPT_SCHEMA:
		return "MUTATION_RECEIPT_SCHEMA"
	if not receipt.parent_blueprint is Dictionary or not BP.validate(receipt.parent_blueprint).is_empty(): return "MUTATION_RECEIPT_PARENT"
	if receipt.parent_blueprint_hash != BP.biological_hash(receipt.parent_blueprint): return "MUTATION_RECEIPT_PARENT_HASH"
	if BP.validate(child_blueprint) != "" or receipt.child_blueprint_hash != BP.biological_hash(child_blueprint): return "MUTATION_RECEIPT_CHILD_HASH"
	if child_blueprint.life_history != receipt.parent_blueprint.life_history: return "MUTATION_RECEIPT_LIFE_HISTORY"
	if not receipt.operator is String or not String(receipt.operator) in Mutation.OPERATORS or not C.integer(receipt.seed, 0, C.MAX_INT) or not F.valid_hash(receipt.event_hash):
		return "MUTATION_RECEIPT_INPUT"
	var replay := Mutation.mutate(receipt.parent_blueprint.genome, int(receipt.seed), String(receipt.operator))
	if not bool(replay.get("success", false)) or String(replay.get("event_hash", "")) != String(receipt.event_hash): return "MUTATION_RECEIPT_REPLAY"
	var expected := BP.create(replay.genome, receipt.parent_blueprint.life_history)
	return "" if not expected.is_empty() and BP.biological_hash(expected) == BP.biological_hash(child_blueprint) else "MUTATION_RECEIPT_CHILD"

static func create_mutated_parent_transfer(blueprint: Dictionary, propagule: Dictionary, paid_parent_state: Dictionary, mutation_receipt: Dictionary) -> Dictionary:
	var receipt_error := validate_mutation_receipt(mutation_receipt, blueprint)
	if not receipt_error.is_empty(): return {}
	var parent_blueprint: Dictionary = mutation_receipt.parent_blueprint
	if not validate_parent_transfer_witness(propagule, parent_blueprint, paid_parent_state).is_empty(): return {}
	var individual_id: String = propagule.id
	var initial: Dictionary = propagule.endowment.duplicate(true)
	var development := S.create(blueprint.genome, individual_id, B.stock())
	if development.is_empty(): return {}
	var origin := {
		"schema": MUTATION_TRANSFER_RECEIPT_SCHEMA,
		"child_blueprint_hash": BP.biological_hash(blueprint),
		"parent_blueprint_hash": BP.biological_hash(parent_blueprint),
		"parent_id": propagule.parent_id,
		"sequence": propagule.sequence,
		"birth_tick": propagule.birth_tick,
		"position_mm": propagule.position_mm.duplicate(),
		"endowment": propagule.endowment.duplicate(true),
		"parent_state_hash": propagule.parent_state_hash,
		"parent_state": paid_parent_state.duplicate(true),
		"mutation_receipt": mutation_receipt.duplicate(true),
	}
	var state := {
		"schema": SCHEMA, "blueprint_hash": BP.biological_hash(blueprint), "individual_id": individual_id,
		"position_mm": propagule.position_mm.duplicate(), "origin_kind": "PARENT_MUTATION_TRANSFER", "origin_receipt": origin,
		"alive": true, "age_ticks": 0, "starvation_ticks": 0,
		"next_reproduction_tick": blueprint.life_history.reproduction.maturity_ticks,
		"reproduction_count": 0, "propagule_seq": 0,
		"metabolic_reserves": initial.duplicate(true),
		"resource_ledger": {"initial": initial.duplicate(true), "field_intake": F.stock(), "external_energy_mj": 0,
			"assimilated": B.stock(), "maintenance": B.stock(), "growth_transferred": B.stock(), "reproduction_transferred": B.stock(), "reproduction_cost": B.stock()},
		"development": development, "last_environment_source": {}, "last_events": [],
	}
	return state if validate(state, blueprint).is_empty() else {}

static func propagule_id(parent_id: String, sequence: int) -> String:
	return "seed/%s/%06d" % [parent_id.sha256_text(), sequence]

static func validate_parent_transfer_witness(v: Variant, blueprint: Dictionary, paid_parent_state: Dictionary, parent_proof_depth: int = 1) -> String:
	if parent_proof_depth < 0 or parent_proof_depth > MAX_PARENT_PROOF_DEPTH: return "PROPAGULE_PARENT_PROOF_DEPTH"
	if not BP.validate(blueprint).is_empty(): return "PROPAGULE_BLUEPRINT"
	var keys := ["schema", "id", "parent_id", "sequence", "blueprint_hash", "birth_tick", "position_mm", "endowment", "parent_state_hash"]
	if not C.keys(v, keys) or v.schema != PROPAGULE_SCHEMA: return "PROPAGULE_SCHEMA"
	if not C.identifier(v.parent_id) or not C.integer(v.sequence, 0, MAX_OFFSPRING_COUNTER - 1): return "PROPAGULE_IDENTITY"
	if not C.identifier(v.id) or v.id != propagule_id(v.parent_id, v.sequence) or v.blueprint_hash != BP.biological_hash(blueprint): return "PROPAGULE_IDENTITY"
	if not C.integer(v.birth_tick, 1, MAX_AGE_TICK) or not C.vector(v.position_mm, F.MAX_PORT_COORD_MM): return "PROPAGULE_POSITION"
	if not B.valid_stock(v.endowment) or not F.valid_hash(v.parent_state_hash): return "PROPAGULE_RESOURCE"
	if v.endowment != blueprint.life_history.reproduction.endowment: return "PROPAGULE_ENDOWMENT"
	if paid_parent_state.is_empty(): return "PROPAGULE_PARENT_STATE_REQUIRED"
	var parent_validation := validate(paid_parent_state, blueprint, parent_proof_depth)
	if not parent_validation.is_empty(): return "PROPAGULE_PARENT_STATE"
	if paid_parent_state.individual_id != v.parent_id: return "PROPAGULE_PARENT_ID"
	var paid_parent_hash := C.digest(paid_parent_state)
	if paid_parent_hash.is_empty() or paid_parent_hash != v.parent_state_hash: return "PROPAGULE_PARENT_HASH"
	var reproduction: Dictionary = blueprint.life_history.reproduction
	var event_size: int = reproduction.offspring_per_event
	if paid_parent_state.reproduction_count < event_size: return "PROPAGULE_PARENT_SEQUENCE"
	var first_sequence: int = paid_parent_state.reproduction_count - event_size
	if v.sequence < first_sequence or v.sequence >= paid_parent_state.reproduction_count: return "PROPAGULE_PARENT_SEQUENCE"
	var last_reproduction_tick: int = paid_parent_state.next_reproduction_tick - reproduction.interval_ticks
	if v.birth_tick != paid_parent_state.age_ticks or v.birth_tick != last_reproduction_tick: return "PROPAGULE_PARENT_BIRTH"
	if v.position_mm != paid_parent_state.position_mm: return "PROPAGULE_PARENT_POSITION"
	var reproduced_event := false
	for event in paid_parent_state.last_events:
		if event.outcome == "REPRODUCED":
			reproduced_event = true
			break
	if not reproduced_event: return "PROPAGULE_PARENT_EVENT"
	return ""

static func validate(v: Variant, blueprint: Dictionary, parent_proof_depth: int = 0) -> String:
	if parent_proof_depth < 0 or parent_proof_depth > MAX_PARENT_PROOF_DEPTH: return "LIFE_PARENT_TRANSFER_DEPTH"
	if not BP.validate(blueprint).is_empty(): return "LIFE_STATE_BLUEPRINT"
	var keys := ["schema", "blueprint_hash", "individual_id", "position_mm", "origin_kind", "origin_receipt", "alive", "age_ticks", "starvation_ticks", "next_reproduction_tick", "reproduction_count", "propagule_seq", "metabolic_reserves", "resource_ledger", "development", "last_environment_source", "last_events"]
	if not C.keys(v, keys) or v.schema != SCHEMA: return "LIFE_STATE_SCHEMA"
	if v.blueprint_hash != BP.biological_hash(blueprint) or not C.identifier(v.individual_id): return "LIFE_STATE_BINDING"
	if not C.vector(v.position_mm, F.MAX_PORT_COORD_MM) or not v.origin_kind in ORIGINS or not v.origin_receipt is Dictionary or not v.alive is bool: return "LIFE_STATE_IDENTITY"
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
	var max_field_intake_per_resource: int = int(v.age_ticks) * F.MAX_REQUEST
	for resource in F.RESOURCES:
		if int(v.resource_ledger.field_intake[resource]) > max_field_intake_per_resource:
			return "LIFE_FIELD_INTAKE_CAUSALITY"
	if v.age_ticks == 0 and not v.last_environment_source.is_empty():
		return "LIFE_FIELD_INTAKE_CAUSALITY"
	if v.resource_ledger.assimilated.material_mg != v.resource_ledger.field_intake.nutrient_mg + v.resource_ledger.field_intake.organic_mg: return "LIFE_FIELD_MATERIAL_SOURCE"
	if v.resource_ledger.assimilated.water_mg != v.resource_ledger.field_intake.water_mg: return "LIFE_FIELD_WATER_SOURCE"
	if v.resource_ledger.assimilated.energy_mj != v.resource_ledger.external_energy_mj: return "LIFE_EXTERNAL_ENERGY_SOURCE"
	var origin_error := _validate_origin_receipt(v, blueprint, parent_proof_depth)
	if not origin_error.is_empty(): return origin_error
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
	var paid_prefix_ticks: int = v.age_ticks - v.starvation_ticks
	if v.development.tick > paid_prefix_ticks or v.development.grant_seq > paid_prefix_ticks:
		return "LIFE_DEVELOPMENT_CAUSALITY"
	var survival_paid_ticks := 0
	if paid_prefix_ticks > 0:
		survival_paid_ticks = int((paid_prefix_ticks + starvation_limit - 1) / starvation_limit)
	var required_paid_ticks: int = maxi(event_count, maxi(survival_paid_ticks, int(v.development.grant_seq)))
	var guaranteed_root_payment_ticks: int = required_paid_ticks
	# Every committed non-root module paid a one-time birth-maintenance debit after its
	# successful A2 creation and before reproduction. This structural floor never depends
	# on mutable A2 event arrays. Additional proven later paid ticks are added below.
	var guaranteed_nonroot_payment_ticks: int = maxi(0, v.development.modules.size() - 1)
	if event_count > 0:
		# Reproduction proves at least one paid event tick. Count additional paid ticks that are
		# provably after the first event separately so max()-combination cannot erase their root cost.
		var latest_first_reproduction_tick: int = last_reproduction_tick - (event_count - 1) * interval_ticks
		var suffix_ticks: int = maxi(0, v.age_ticks - latest_first_reproduction_tick)
		var suffix_nonstarved_ticks: int = maxi(0, suffix_ticks - v.starvation_ticks)
		var suffix_survival_paid_ticks := 0
		if suffix_nonstarved_ticks > 0:
			suffix_survival_paid_ticks = int((suffix_nonstarved_ticks + starvation_limit - 1) / starvation_limit)
		var suffix_development_paid_ticks: int = maxi(0, int(v.development.grant_seq) - latest_first_reproduction_tick)
		var suffix_reproduction_or_terminal_paid_ticks: int = maxi(0, event_count - 1)
		if paid_prefix_ticks > last_reproduction_tick:
			# The last paid tick implied by the current starvation suffix lies after every reproduction
			# event and is therefore an additional distinct paid tick.
			suffix_reproduction_or_terminal_paid_ticks += 1
		var post_reproduction_paid_ticks: int = maxi(suffix_reproduction_or_terminal_paid_ticks, maxi(suffix_survival_paid_ticks, suffix_development_paid_ticks))
		guaranteed_root_payment_ticks = maxi(required_paid_ticks, 1 + post_reproduction_paid_ticks)
		if reproduction.required_reproductive_modules > 0:
			# Birth maintenance is already counted once for every current non-root module above.
			# Every provably paid later tick must additionally pay the persistent reproductive modules.
			guaranteed_nonroot_payment_ticks += post_reproduction_paid_ticks * int(reproduction.required_reproductive_modules)
	var guaranteed_module_payment_ticks: int = guaranteed_root_payment_ticks + guaranteed_nonroot_payment_ticks
	var metabolism: Dictionary = blueprint.life_history.metabolism
	var minimum_maintenance_water: int = guaranteed_module_payment_ticks * int(metabolism.maintenance_water_per_module_mg)
	var minimum_maintenance_energy: int = guaranteed_module_payment_ticks * int(metabolism.maintenance_energy_per_module_mj)
	if v.resource_ledger.maintenance.water_mg < minimum_maintenance_water or v.resource_ledger.maintenance.energy_mj < minimum_maintenance_energy:
		return "LIFE_REPRODUCTION_MAINTENANCE" if event_count > 0 else "LIFE_MAINTENANCE_HISTORY"
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

static func _validate_origin_receipt(state: Dictionary, blueprint: Dictionary, parent_proof_depth: int) -> String:
	var receipt: Dictionary = state.origin_receipt
	if state.origin_kind == "FOUNDER_ENDOWMENT":
		return "" if receipt.is_empty() else "LIFE_FOUNDER_ORIGIN_RECEIPT"
	if parent_proof_depth >= MAX_PARENT_PROOF_DEPTH: return "LIFE_PARENT_TRANSFER_DEPTH"
	if state.origin_kind == "PARENT_TRANSFER":
		var keys := ["schema", "blueprint_hash", "parent_id", "sequence", "birth_tick", "position_mm", "endowment", "parent_state_hash", "parent_state"]
		if not C.keys(receipt, keys) or receipt.schema != PARENT_TRANSFER_RECEIPT_SCHEMA: return "LIFE_PARENT_TRANSFER_RECEIPT"
		if receipt.blueprint_hash != BP.biological_hash(blueprint): return "LIFE_PARENT_TRANSFER_RECEIPT"
		if not receipt.parent_state is Dictionary: return "LIFE_PARENT_TRANSFER_PARENT_STATE"
		if state.position_mm != receipt.position_mm: return "LIFE_PARENT_TRANSFER_POSITION"
		if not B.valid_stock(receipt.endowment) or receipt.endowment != blueprint.life_history.reproduction.endowment: return "LIFE_PARENT_TRANSFER_ENDOWMENT"
		if state.resource_ledger.initial != receipt.endowment: return "LIFE_PARENT_TRANSFER_INITIAL"
		var reconstructed := {"schema": PROPAGULE_SCHEMA, "id": state.individual_id, "parent_id": receipt.parent_id,
			"sequence": receipt.sequence, "blueprint_hash": receipt.blueprint_hash, "birth_tick": receipt.birth_tick,
			"position_mm": receipt.position_mm, "endowment": receipt.endowment, "parent_state_hash": receipt.parent_state_hash}
		return "" if validate_parent_transfer_witness(reconstructed, blueprint, receipt.parent_state, parent_proof_depth + 1).is_empty() else "LIFE_PARENT_TRANSFER_PARENT_STATE"
	if state.origin_kind == "PARENT_MUTATION_TRANSFER":
		var keys2 := ["schema", "child_blueprint_hash", "parent_blueprint_hash", "parent_id", "sequence", "birth_tick", "position_mm", "endowment", "parent_state_hash", "parent_state", "mutation_receipt"]
		if not C.keys(receipt, keys2) or receipt.schema != MUTATION_TRANSFER_RECEIPT_SCHEMA: return "LIFE_MUTATION_TRANSFER_RECEIPT"
		if receipt.child_blueprint_hash != BP.biological_hash(blueprint): return "LIFE_MUTATION_TRANSFER_CHILD"
		if not receipt.mutation_receipt is Dictionary: return "LIFE_MUTATION_TRANSFER_MUTATION"
		var mutation_error := validate_mutation_receipt(receipt.mutation_receipt, blueprint)
		if not mutation_error.is_empty(): return "LIFE_MUTATION_TRANSFER_MUTATION:" + mutation_error
		var parent_blueprint: Dictionary = receipt.mutation_receipt.parent_blueprint
		if receipt.parent_blueprint_hash != BP.biological_hash(parent_blueprint): return "LIFE_MUTATION_TRANSFER_PARENT"
		if not receipt.parent_state is Dictionary: return "LIFE_MUTATION_TRANSFER_PARENT_STATE"
		if state.position_mm != receipt.position_mm or state.resource_ledger.initial != receipt.endowment: return "LIFE_MUTATION_TRANSFER_BINDING"
		var reconstructed2 := {"schema": PROPAGULE_SCHEMA, "id": state.individual_id, "parent_id": receipt.parent_id,
			"sequence": receipt.sequence, "blueprint_hash": receipt.parent_blueprint_hash, "birth_tick": receipt.birth_tick,
			"position_mm": receipt.position_mm, "endowment": receipt.endowment, "parent_state_hash": receipt.parent_state_hash}
		return "" if validate_parent_transfer_witness(reconstructed2, parent_blueprint, receipt.parent_state, parent_proof_depth + 1).is_empty() else "LIFE_MUTATION_TRANSFER_PARENT_STATE"
	return "LIFE_ORIGIN_KIND"

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
