extends RefCounted
## Shared canonical A5+A6 composition runtime for A10.5 and A11.
## Exactly ONE field/population trajectory: A5 runs once, then the A6
## post-lifecycle hook applies corpse/mineralization effects to that SAME field.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")

const SCHEMA := "dws.ecology.composed-runtime.v1"
const MAX_MUTATION_EVENTS := 1024

static func create(field: Dictionary, population: Array, policy: Dictionary) -> Dictionary:
	if not F.validate_state(field).is_empty() or not Feedback.validate_policy(policy).is_empty(): return {}
	var value := {"schema": SCHEMA, "tick": int(field.tick), "field": field.duplicate(true), "population": population.duplicate(true),
		"corpses": [], "policy": policy.duplicate(true), "returned": F.stock(), "mineralized_mg": 0,
		"dissipated_energy_mj": 0, "mutation_events": [], "integrity_hash": ""}
	value = _seal(value)
	return value if validate(value).is_empty() else {}

static func step(source: Dictionary, mutation: Dictionary, experiment_seed: int) -> Dictionary:
	var error := validate(source)
	if not error.is_empty(): return _fail(error)
	var merror := _mutation_error(mutation)
	if not merror.is_empty() or not C.integer(experiment_seed, 0, C.MAX_INT): return _fail(merror if not merror.is_empty() else "RUNTIME_SEED")
	var life := Lifecycle.step_population(source.field, source.population, source.field.owner_token, source.field.owner_epoch, source.field.revision)
	if not life.success: return _fail("RUNTIME_A5:" + String(life.error))
	var population: Array = life.population.duplicate(true)
	var events: Array = []
	for propagule in life.propagules:
		var parent: Dictionary = {}
		for entry in population:
			if String(entry.state.individual_id) == String(propagule.parent_id):
				parent = entry
				break
		if parent.is_empty(): return _fail("RUNTIME_PARENT")
		var child_blueprint: Dictionary = parent.blueprint
		var receipt: Dictionary = {}
		var event := {"parent_id": String(propagule.parent_id), "child_id": String(propagule.id), "applied": false,
			"operator": "", "event_hash": "", "parent_genome_hash": C.digest(parent.blueprint.genome), "child_genome_hash": C.digest(parent.blueprint.genome)}
		if bool(mutation.enabled):
			var seed := Mutation.draw(experiment_seed, "runtime/%06d/%s" % [int(source.tick) + 1, String(propagule.parent_id)], C.MAX_INT + 1)
			var mutated: Dictionary = Mutation.mutate_with_bias(parent.blueprint.genome, seed, mutation.bias) if not mutation.bias.is_empty() else Mutation.mutate(parent.blueprint.genome, seed, String(mutation.operator))
			if bool(mutated.get("success", false)):
				var candidate := BP.create(mutated.genome, parent.blueprint.life_history)
				if candidate.is_empty(): return _fail("RUNTIME_MUTATION_BLUEPRINT")
				if BP.biological_hash(candidate) != BP.biological_hash(parent.blueprint):
					var selected := String(mutated.get("selected_operator", mutated.event.operator))
					receipt = LS.create_mutation_receipt(parent.blueprint, candidate, seed, selected, String(mutated.event_hash))
					if receipt.is_empty(): return _fail("RUNTIME_MUTATION_RECEIPT")
					child_blueprint = candidate
					event.applied = true
					event.operator = selected
					event.event_hash = String(mutated.event_hash)
					event.child_genome_hash = C.digest(candidate.genome)
		var child := Lifecycle.materialize_propagule(propagule, child_blueprint, parent.state, receipt)
		if child.is_empty(): return _fail("RUNTIME_MATERIALIZE")
		population.append(child)
		events.append(event)
	if population.size() > Lifecycle.MAX_POPULATION: return _fail("RUNTIME_POPULATION_LIMIT")
	population.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.state.individual_id) < String(b.state.individual_id))
	var post := Feedback.post_lifecycle_feedback(life.field, population, source.corpses, source.policy, int(source.tick))
	if not post.success: return _fail("RUNTIME_A6:" + String(post.error))
	var next := source.duplicate(true)
	next.tick = int(source.tick) + 1
	next.field = post.field
	next.population = population
	next.corpses = post.corpses
	for resource in F.RESOURCES:
		next.returned[resource] = int(next.returned[resource]) + int(post.returned[resource])
	next.mineralized_mg = int(next.mineralized_mg) + int(post.mineralized_mg)
	next.dissipated_energy_mj = int(next.dissipated_energy_mj) + int(post.dissipated_energy_mj)
	for event in events:
		if next.mutation_events.size() >= MAX_MUTATION_EVENTS: return _fail("RUNTIME_MUTATION_EVENT_LIMIT")
		next.mutation_events.append(event)
	next = _seal(next)
	error = validate(next)
	return {"success": true, "state": next, "events": events} if error.is_empty() else _fail(error)

static func replace_field(source: Dictionary, field: Dictionary) -> Dictionary:
	if not validate(source).is_empty() or not F.validate_state(field).is_empty(): return {}
	if int(field.tick) != int(source.tick): return {}
	var next := source.duplicate(true)
	next.field = field.duplicate(true)
	next = _seal(next)
	return next if validate(next).is_empty() else {}

static func validate(v: Variant) -> String:
	var fields := ["schema","tick","field","population","corpses","policy","returned","mineralized_mg","dissipated_energy_mj","mutation_events","integrity_hash"]
	if not C.keys(v, fields) or v.schema != SCHEMA: return "RUNTIME_SCHEMA"
	if not C.integer(v.tick, 0, Feedback.MAX_STEPS) or not v.field is Dictionary or int(v.field.get("tick", -1)) != int(v.tick): return "RUNTIME_TICK"
	if not F.validate_state(v.field).is_empty() or not Feedback.validate_policy(v.policy).is_empty(): return "RUNTIME_FIELD_POLICY"
	if not v.population is Array or v.population.is_empty() or v.population.size() > Lifecycle.MAX_POPULATION: return "RUNTIME_POPULATION"
	var ids := {}
	for entry in v.population:
		if not C.keys(entry, ["blueprint","state"]) or not entry.blueprint is Dictionary or not entry.state is Dictionary: return "RUNTIME_ENTRY"
		if not BP.validate(entry.blueprint).is_empty() or not LS.validate(entry.state, entry.blueprint).is_empty(): return "RUNTIME_ENTRY_INVALID"
		var id := String(entry.state.individual_id)
		if ids.has(id): return "RUNTIME_DUPLICATE"
		ids[id] = true
	if not v.corpses is Array: return "RUNTIME_CORPSES"
	for corpse in v.corpses:
		if not corpse is Dictionary or not corpse.has_all(["individual_id","death_step","source_hash","inventory","remaining","returned","dissipated_energy_mj"]): return "RUNTIME_CORPSE"
		if not ids.has(String(corpse.individual_id)) or bool(_entry(v.population, String(corpse.individual_id)).state.alive): return "RUNTIME_CORPSE_BINDING"
		if not B.valid_stock(corpse.inventory) or not B.valid_stock(corpse.remaining) or not F.valid_total_stock(corpse.returned): return "RUNTIME_CORPSE_STOCK"
	if not F.valid_total_stock(v.returned) or not C.integer(v.mineralized_mg, 0, C.MAX_INT) or not C.integer(v.dissipated_energy_mj, 0, C.MAX_INT): return "RUNTIME_ACCOUNTING"
	if not v.mutation_events is Array or v.mutation_events.size() > MAX_MUTATION_EVENTS: return "RUNTIME_EVENTS"
	if not F.valid_hash(v.integrity_hash): return "RUNTIME_HASH"
	var payload: Dictionary = v.duplicate(true)
	payload.integrity_hash = ""
	return "" if C.digest(payload) == v.integrity_hash else "RUNTIME_INTEGRITY"

static func _mutation_error(v: Variant) -> String:
	if not C.keys(v, ["enabled","operator","bias"]) or not v.enabled is bool or not v.operator is String or not v.bias is Dictionary: return "RUNTIME_MUTATION"
	if not String(v.operator) in Mutation.OPERATORS: return "RUNTIME_MUTATION_OPERATOR"
	if not v.bias.is_empty():
		var error := Mutation.validate_bias(v.bias)
		if not error.is_empty(): return error
	return ""

static func _entry(population: Array, id: String) -> Dictionary:
	for entry in population:
		if String(entry.state.individual_id) == id: return entry
	return {}

static func _seal(v: Dictionary) -> Dictionary:
	var next := v.duplicate(true)
	next.integrity_hash = ""
	next.integrity_hash = C.digest(next)
	return next

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
