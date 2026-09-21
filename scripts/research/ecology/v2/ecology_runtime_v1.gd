extends RefCounted
## EcologyRuntimeV1 — shared canonical ecology runtime (ECO ARCH2 A10.5
## repair R1). THE single current ecology state trajectory: exactly one
## current field, exactly one current population. The composition of one
## canonical tick is:
##   A5 lifecycle step (exactly once, resource-funded life transitions)
##     -> propagule admission (sealed mutation receipt + canonical A5
##        admission; fail-closed, no parent-blueprint fallback)
##     -> A6 post-lifecycle feedback transition (corpse registration,
##        resource return, decomposition, mineralization, field tick)
##        applied to the SAME resulting field/population.
## A5 owns life semantics, A6 owns death/feedback semantics, A4 owns the
## field, A3 owns genome edits: this runtime owns the STATE and the
## composition only, and duplicates no owner formula. It is reusable beyond
## the polygon workbench (A11+); the workbench controller is a consumer.
## Integrity: every transition re-seals the state and re-checks resource
## conservation over the single truth (fail-closed). Historical replay is a
## journal concern outside this state; determinism is guaranteed by the
## pure-function transition chain.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const Receipt = preload("res://scripts/research/ecology/v2/genome_mutation_receipt_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")

const SCHEMA := "dws.ecology.ecology-runtime-state.v1"
const FEEDBACK_SCHEMA := "dws.ecology.ecology-runtime-feedback.v1"
const ACCOUNTING_SCHEMA := "dws.ecology.ecology-runtime-accounting.v1"
const OUTBOX_SCHEMA := "dws.ecology.ecology-runtime-outbox.v1"
# Deterministic mutation seed stream key prefix. The workbench controller
# passes its historical prefix so its public seed derivation is unchanged.
const MUTATION_KEY_PREFIX_DEFAULT := "eco-runtime-v1/mut"
const MAX_POPULATION := 128  # aligned with A5 lifecycle budget
const MAX_CORPSES := 128
const MAX_OUTBOX := 512  # aligned with A5 propagule budget

const STATE_KEYS := ["schema", "session_id", "tick", "field", "population", "feedback", "accounting", "outbox", "integrity_hash"]
const FEEDBACK_KEYS := ["schema", "enabled", "policy", "step", "corpses", "returned", "mineralized_mg", "dissipated_energy_mj"]
const ACCOUNTING_KEYS := ["schema", "initial"]
const CORPSE_KEYS := ["individual_id", "death_step", "source_hash", "inventory", "remaining", "returned", "dissipated_energy_mj"]
const OUTBOX_KEYS := ["schema", "propagule"]
const PROPAGULE_KEYS := ["schema", "id", "parent_id", "sequence", "blueprint_hash", "birth_tick", "position_mm", "endowment", "parent_state_hash"]

## Build the sealed initial runtime state from canonical genesis inputs.
## field: A4 field (single current field truth). population: Array of
## {blueprint, state} founder entries (single current population truth).
## policy: A6 feedback policy (Feedback.validate_policy). feedback_enabled
## mirrors the manifest feedback.enabled flag: when false the post-lifecycle
## feedback phase is skipped entirely (matching the historical controller).
static func create(session_id: String, field: Dictionary, population: Array, policy: Dictionary, feedback_enabled: bool = true) -> Dictionary:
	if not C.identifier(session_id): return _fail("RUNTIME_SESSION_ID")
	if not feedback_enabled is bool: return _fail("RUNTIME_FEEDBACK_FLAG")
	var policy_error := Feedback.validate_policy(policy)
	if not policy_error.is_empty(): return _fail(policy_error)
	if not F.validate_state(field).is_empty(): return _fail("RUNTIME_FIELD")
	if population.is_empty() or population.size() > MAX_POPULATION: return _fail("RUNTIME_POPULATION_SIZE")
	var entries: Array = []
	var seen := {}
	for entry in population:
		if not C.keys(entry, ["blueprint", "state"]) or not entry.blueprint is Dictionary or not entry.state is Dictionary:
			return _fail("RUNTIME_ENTRY")
		if not BP.validate(entry.blueprint).is_empty() or not LS.validate(entry.state, entry.blueprint).is_empty():
			return _fail("RUNTIME_ENTRY_INVALID")
		if seen.has(entry.state.individual_id): return _fail("RUNTIME_DUPLICATE_INDIVIDUAL")
		if _cell_index(field, entry.state.position_mm) < 0: return _fail("RUNTIME_POSITION")
		seen[entry.state.individual_id] = true
		entries.append(entry.duplicate(true))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.state.individual_id < b.state.individual_id)
	var corpses: Array = []
	if feedback_enabled:
		var seeded := Feedback.register_corpses(entries, [], 0)
		if not bool(seeded.get("success", false)): return seeded
		corpses = seeded.corpses
	var feedback := {
		"schema": FEEDBACK_SCHEMA, "enabled": feedback_enabled,
		"policy": policy.duplicate(true), "step": 0, "corpses": corpses,
		"returned": F.stock(), "mineralized_mg": 0, "dissipated_energy_mj": 0,
	}
	var initial := Feedback.field_inventory(field)
	for entry in entries: _add_stock(initial, Feedback.inventory(entry.state))
	var accounting := {"schema": ACCOUNTING_SCHEMA, "initial": initial}
	var state := {
		"schema": SCHEMA, "session_id": session_id, "tick": 0,
		"field": field.duplicate(true), "population": entries,
		"feedback": feedback, "accounting": accounting, "outbox": [],
		"integrity_hash": "",
	}
	state = _seal(state)
	var error := validate(state)
	return {"success": true, "state": state} if error.is_empty() else _fail(error)

## ONE canonical ecology tick over the single truth. options:
## {mutations_enabled: bool, operator: String, seed: int,
##  mutation_key_prefix: String (optional)}. Fail-closed: any primitive
## failure leaves the input state untouched and reports the error.
static func step(state: Dictionary, options: Dictionary) -> Dictionary:
	var lifecycle := step_lifecycle(state)
	if not bool(lifecycle.get("success", false)): return lifecycle
	var admitted := admit_propagules(lifecycle.state, options)
	if not bool(admitted.get("success", false)): return admitted
	return step_feedback(admitted.state)

## Primitive 1: the A5 lifecycle step — executed EXACTLY once per tick.
## Advances life state and field intake on the single current truth.
## Emitted propagules enter the state outbox as paid-but-unmaterialized
## endowments (the value stays visible to the conservation invariant).
static func step_lifecycle(state: Dictionary) -> Dictionary:
	var error := validate(state)
	if not error.is_empty(): return _fail(error)
	var field: Dictionary = state.field
	var result := Lifecycle.step_population(field, state.population, field.owner_token, field.owner_epoch, field.revision)
	if not result.success: return _fail("RUNTIME_LIFECYCLE:" + String(result.error))
	var next := state.duplicate(true)
	next.field = result.field
	next.population = result.population.duplicate(true)
	var outbox: Array = []
	for propagule in result.propagules:
		outbox.append({"schema": OUTBOX_SCHEMA, "propagule": propagule.duplicate(true)})
	next.outbox = outbox
	return {"success": true, "state": _seal(next)}

## Primitive 2: propagule admission. Every emission in the state outbox is
## admitted through the canonical A5 parent-transfer witness — with a sealed
## canonical mutation receipt when mutations are enabled, without one
## otherwise. A successful mutation MUST enter the lineage through its
## receipt or the whole tick fails closed: the silent fallback to the parent
## blueprint is removed. The outbox is consumed by admission.
static func admit_propagules(state: Dictionary, options: Dictionary) -> Dictionary:
	var error := validate(state)
	if not error.is_empty(): return _fail(error)
	var mutations_enabled: bool = bool(options.get("mutations_enabled", false))
	if options.has("mutations_enabled") and not options.mutations_enabled is bool: return _fail("RUNTIME_MUTATION_FLAG")
	var operator_name: String = String(options.get("operator", "small"))
	var seed_base: int = int(options.get("seed", 0))
	if options.has("seed") and not C.integer(options.seed, 0, C.MAX_INT): return _fail("RUNTIME_MUTATION_SEED")
	var key_prefix: String = String(options.get("mutation_key_prefix", MUTATION_KEY_PREFIX_DEFAULT))
	var bias: Dictionary = Dictionary(options.get("bias", {})).duplicate(true)
	if mutations_enabled and not bias.is_empty():
		var bias_error := Mutation.validate_bias(bias)
		if not bias_error.is_empty(): return _fail("RUNTIME_MUTATION_BIAS:" + bias_error)
	elif mutations_enabled and not operator_name in Mutation.OPERATORS:
		return _fail("RUNTIME_MUTATION_OPERATOR")
	var next := state.duplicate(true)
	var population: Array = next.population
	var children: Array = []
	for outbox_entry in next.outbox:
		var propagule: Dictionary = outbox_entry.propagule
		var parent := _find_by_id(population, String(propagule.parent_id))
		if parent.is_empty(): return _fail("RUNTIME_PROPAGULE_PARENT:" + String(propagule.id))
		var blueprint: Dictionary = parent.blueprint
		var receipt := {}
		if mutations_enabled:
			var seed := mutation_seed(seed_base, int(next.tick) + 1, String(propagule.parent_id), key_prefix)
			var mutated := Mutation.mutate(parent.blueprint.genome, seed, operator_name) if bias.is_empty() else Mutation.mutate_with_bias(parent.blueprint.genome, seed, bias)
			if not bool(mutated.get("success", false)):
				return _fail("RUNTIME_MUTATION_REJECTED:" + String(mutated.get("reason", "?")))
			var actual_operator := String(mutated.get("selected_operator", operator_name))
			var candidate := BP.create(mutated.genome, parent.blueprint.life_history)
			if candidate.is_empty(): return _fail("RUNTIME_MUTATION_BLUEPRINT")
			var bias_hash := "" if bias.is_empty() else C.digest(bias)
			receipt = Receipt.issue(parent.blueprint, mutated.genome, actual_operator, seed, bias_hash)
			if receipt.is_empty(): return _fail("RUNTIME_MUTATION_RECEIPT")
			blueprint = candidate
		var child := Lifecycle.materialize_propagule(propagule, blueprint, parent.state, receipt, {} if receipt.is_empty() else parent.blueprint)
		if child.is_empty(): return _fail("RUNTIME_PROPAGULE_ADMISSION:" + String(propagule.id))
		# Conservation anchor for births: the paid endowment moves parent ->
		# child (already conserved), while the born organism's structural body
		# (the blueprint's genesis modules) enters the anchor exactly like the
		# founder bodies did at create. Without this anchor the child's
		# structural material would appear in current with no source.
		for module in child.state.development.modules:
			next.accounting.initial.material_mg += int(module.cost.material_mg)
		children.append(child)
	next.outbox = []
	population.append_array(children)
	if population.size() > MAX_POPULATION: return _fail("RUNTIME_POPULATION_LIMIT")
	population.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.state.individual_id < b.state.individual_id)
	return {"success": true, "state": _seal(next), "materialized": children.size()}

## Primitive 3: the A6-owned post-lifecycle feedback transition, applied to
## the SAME single field/population the lifecycle produced, followed by the
## conservation gate over the resulting truth and the tick advance.
static func step_feedback(state: Dictionary) -> Dictionary:
	var error := validate(state)
	if not error.is_empty(): return _fail(error)
	var next := state.duplicate(true)
	var feedback: Dictionary = next.feedback
	if bool(feedback.enabled):
		var advanced := Feedback.advance_after_lifecycle(next.field, next.population, feedback.corpses, feedback.policy, int(feedback.step))
		if not bool(advanced.get("success", false)):
			return _fail("RUNTIME_FEEDBACK:" + String(advanced.get("error", "?")))
		next.field = advanced.field
		feedback.corpses = advanced.corpses
		for resource in F.RESOURCES: feedback.returned[resource] += advanced.returned[resource]
		feedback.mineralized_mg = int(feedback.mineralized_mg) + int(advanced.mineralized_mg)
		feedback.dissipated_energy_mj = int(feedback.dissipated_energy_mj) + int(advanced.dissipated_energy_mj)
		feedback.step = int(feedback.step) + 1
	var conservation := Feedback.accounts_error(_balance_unchecked(next))
	if not conservation.is_empty(): return _fail("RUNTIME_CONSERVATION:" + conservation)
	next.tick = int(next.tick) + 1
	return {"success": true, "state": _seal(next)}

## Adopt an externally produced field (the same canonical owner-write API
## used by genesis/patches, e.g. controller apply_field_patch) into the
## single truth and re-anchor the accounting by the exact inventory delta.
static func adopt_field(state: Dictionary, new_field: Dictionary) -> Dictionary:
	var error := validate(state)
	if not error.is_empty(): return _fail(error)
	if not F.validate_state(new_field).is_empty(): return _fail("RUNTIME_ADOPT_FIELD")
	var delta := Feedback.field_inventory(new_field)
	var previous := Feedback.field_inventory(state.field)
	var initial: Dictionary = state.accounting.initial.duplicate(true)
	for name in B.RESOURCES: initial[name] += int(delta[name]) - int(previous[name])
	if not LS.valid_cumulative_stock(initial): return _fail("RUNTIME_ADOPT_ACCOUNTING")
	var next := state.duplicate(true)
	next.field = new_field.duplicate(true)
	next.accounting.initial = initial
	return {"success": true, "state": _seal(next), "field_hash": Field.state_hash(next.field)}

## Deterministic mutation seed from (seed, tick, parent_id) through the
## canonical A3 draw stream. key_prefix keeps derivation streams separable
## per host (the workbench controller passes its historical prefix).
static func mutation_seed(seed: int, tick: int, parent_id: String, key_prefix: String = MUTATION_KEY_PREFIX_DEFAULT) -> int:
	return Mutation.draw(seed, "%s/%06d/%s" % [key_prefix, tick, parent_id], C.MAX_INT + 1)

## Read-only feedback bookkeeping view: derived data only, and deliberately
## carrying NO field or population copy (there is no second truth to show).
static func feedback_view(state: Dictionary) -> Dictionary:
	return {"frame": {
		"enabled": bool(state.feedback.enabled),
		"step": int(state.feedback.step),
		"policy": state.feedback.policy.duplicate(true),
		"corpses": state.feedback.corpses.duplicate(true),
		"returned": state.feedback.returned.duplicate(true),
		"mineralized_mg": int(state.feedback.mineralized_mg),
		"dissipated_energy_mj": int(state.feedback.dissipated_energy_mj),
	}}

## Read-only conservation accounts over the single truth (same account shape
## as the historical A6 frame balance).
static func balance(state: Dictionary) -> Dictionary:
	var error := validate(state)
	if not error.is_empty(): return _fail(error)
	return _balance_unchecked(state)

static func mineralized_total(state: Dictionary) -> int:
	if validate(state).is_empty(): return int(state.feedback.mineralized_mg)
	return -1

static func state_hash(state: Dictionary) -> String:
	return String(state.integrity_hash) if validate(state).is_empty() else ""

## Full structural validation of the single-truth state: envelopes, canonical
## field, every life state (including durable mutation provenance), feedback
## bookkeeping, conservation over the stored accounting anchor, integrity
## seal and canonical encodability (nesting/byte budgets are the canonical
## envelope: a state that cannot encode cannot exist).
static func validate(value: Variant) -> String:
	if not C.keys(value, STATE_KEYS) or value.schema != SCHEMA:
		return "RUNTIME_SCHEMA"
	if not C.identifier(value.session_id): return "RUNTIME_SESSION"
	if not C.integer(value.tick, 0, F.MAX_TICK): return "RUNTIME_TICK"
	if not F.validate_state(value.field).is_empty(): return "RUNTIME_FIELD"
	if not value.population is Array or value.population.is_empty() or value.population.size() > MAX_POPULATION:
		return "RUNTIME_POPULATION"
	var seen := {}
	var prior := ""
	for entry in value.population:
		if not C.keys(entry, ["blueprint", "state"]) or not entry.blueprint is Dictionary or not entry.state is Dictionary:
			return "RUNTIME_ENTRY"
		var life_error := LS.validate(entry.state, entry.blueprint)
		if not life_error.is_empty(): return "RUNTIME_ENTRY_INVALID:" + life_error
		var id := String(entry.state.individual_id)
		if seen.has(id): return "RUNTIME_DUPLICATE_INDIVIDUAL"
		if not prior.is_empty() and id <= prior: return "RUNTIME_ID_ORDER"
		if _cell_index(value.field, entry.state.position_mm) < 0: return "RUNTIME_POSITION"
		prior = id
		seen[id] = true
	var feedback: Dictionary = value.feedback
	if not C.keys(feedback, FEEDBACK_KEYS) or feedback.schema != FEEDBACK_SCHEMA:
		return "RUNTIME_FEEDBACK_SCHEMA"
	if not feedback.enabled is bool: return "RUNTIME_FEEDBACK_FLAG"
	var policy_error := Feedback.validate_policy(feedback.policy)
	if not policy_error.is_empty(): return "RUNTIME_FEEDBACK_POLICY:" + policy_error
	if not C.integer(feedback.step, 0, F.MAX_TICK): return "RUNTIME_FEEDBACK_STEP"
	if not feedback.corpses is Array or feedback.corpses.size() > MAX_CORPSES: return "RUNTIME_CORPSES"
	var population_ids := {}
	for entry in value.population: population_ids[entry.state.individual_id] = true
	var corpse_ids := {}
	for corpse in feedback.corpses:
		if not C.keys(corpse, CORPSE_KEYS): return "RUNTIME_CORPSE_RECORD"
		if not LS.valid_cumulative_stock(corpse.remaining) or not LS.valid_cumulative_stock(corpse.inventory): return "RUNTIME_CORPSE_STOCK"
		if not C.keys(corpse.returned, F.RESOURCES): return "RUNTIME_CORPSE_RETURNED"
		if not C.integer(corpse.death_step, 0, F.MAX_TICK) or not F.valid_hash(corpse.source_hash): return "RUNTIME_CORPSE_RECORD"
		if not population_ids.has(corpse.individual_id) or corpse_ids.has(corpse.individual_id): return "RUNTIME_CORPSE_ID"
		corpse_ids[corpse.individual_id] = true
	if not feedback.returned is Dictionary or not C.keys(feedback.returned, F.RESOURCES): return "RUNTIME_FEEDBACK_RETURNED"
	for resource in F.RESOURCES:
		if not C.integer(feedback.returned[resource], 0, C.MAX_INT): return "RUNTIME_FEEDBACK_RETURNED"
	if not C.integer(feedback.mineralized_mg, 0, C.MAX_INT) or not C.integer(feedback.dissipated_energy_mj, 0, C.MAX_INT):
		return "RUNTIME_FEEDBACK_COUNTERS"
	var accounting: Dictionary = value.accounting
	if not C.keys(accounting, ACCOUNTING_KEYS) or accounting.schema != ACCOUNTING_SCHEMA:
		return "RUNTIME_ACCOUNTING_SCHEMA"
	if not LS.valid_cumulative_stock(accounting.initial): return "RUNTIME_ACCOUNTING_INITIAL"
	var outbox: Array = value.outbox
	if not outbox is Array or outbox.size() > MAX_OUTBOX: return "RUNTIME_OUTBOX"
	for outbox_entry in outbox:
		if not C.keys(outbox_entry, OUTBOX_KEYS) or outbox_entry.schema != OUTBOX_SCHEMA:
			return "RUNTIME_OUTBOX_ENTRY"
		var propagule: Dictionary = outbox_entry.propagule
		if not C.keys(propagule, PROPAGULE_KEYS) or propagule.schema != LS.PROPAGULE_SCHEMA:
			return "RUNTIME_OUTBOX_PROPAGULE"
		if not C.identifier(propagule.id) or not B.valid_stock(propagule.endowment):
			return "RUNTIME_OUTBOX_PROPAGULE"
	var conservation := Feedback.accounts_error(_balance_unchecked(value))
	if not conservation.is_empty(): return "RUNTIME_CONSERVATION:" + conservation
	if not F.valid_hash(value.integrity_hash) or value.integrity_hash != _integrity(value):
		return "RUNTIME_INTEGRITY_HASH"
	return "NONCANONICAL_RUNTIME_STATE" if C.encode(value).is_empty() else ""

# --- internals ------------------------------------------------------------------

static func _balance_unchecked(state: Dictionary) -> Dictionary:
	var pairs: Array = []
	# One conservation invariant over every phase of the tick: each resource
	# unit sits in exactly one of field / living inventory / dead-but-unregistered
	# inventory (the limbo between the A5 death and the A6 corpse registration
	# inside the same tick) / corpse remaining / paid-but-unmaterialized
	# outbox endowments (the limbo between the A5 emission and the admission
	# inside the same tick). Registered corpses replace the dead entry's
	# inventory and materialized children replace the outbox; at rest (post
	# step) neither limbo exists.
	var corpse_ids := {}
	for corpse in state.feedback.corpses:
		corpse_ids[corpse.individual_id] = true
	for entry in state.population:
		var in_current: bool = bool(entry.state.alive) or not corpse_ids.has(entry.state.individual_id)
		pairs.append({"state": entry.state, "baseline": {}, "in_current": in_current})
	var outbox_endowments: Array = []
	for outbox_entry in state.outbox:
		outbox_endowments.append(outbox_entry.propagule.endowment)
	return Feedback.balance_over(state.field, pairs, state.feedback.corpses, outbox_endowments, state.accounting.initial, int(state.feedback.dissipated_energy_mj))

static func _find_by_id(population: Array, individual_id: String) -> Dictionary:
	for entry in population:
		if String(entry.state.individual_id) == individual_id:
			return entry
	return {}

static func _add_stock(target: Dictionary, delta: Dictionary) -> void:
	for name in B.RESOURCES: target[name] += delta[name]

static func _cell_index(field: Dictionary, position: Array) -> int:
	var x: int = position[0] - field.origin_mm[0]
	var z: int = position[2] - field.origin_mm[2]
	if x < 0 or z < 0 or x >= field.width * field.cell_size_mm or z >= field.depth * field.cell_size_mm:
		return -1
	return int(z / field.cell_size_mm) * int(field.width) + int(x / field.cell_size_mm)

static func _integrity(state: Dictionary) -> String:
	var out: Dictionary = state.duplicate(true)
	out.erase("integrity_hash")
	return C.digest(out)

static func _seal(state: Dictionary) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	out.erase("integrity_hash")
	out["integrity_hash"] = C.digest(out)
	return out

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
