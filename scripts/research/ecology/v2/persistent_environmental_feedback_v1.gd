extends RefCounted
## A6 bounded local research experiment. A4 owns field semantics; A5 owns life semantics.
## The current frame is proved by deterministic replay, not by mutable event/receipt claims.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const R = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const SCHEMA := "dws.ecology.persistent-feedback.v1"
const GENESIS_SCHEMA := "dws.ecology.feedback-genesis.v1"
const FRAME_SCHEMA := "dws.ecology.feedback-frame.v1"
const POLICY_SCHEMA := "dws.ecology.feedback-policy.v1"
const MAX_POPULATION := 32
const MAX_CELLS := 64
const MAX_STEPS := 64
const MAX_REPLAY_WORK := 512
const MAX_PROPAGULES := 128

static func default_policy() -> Dictionary:
	return {"schema": POLICY_SCHEMA, "decomposition_enabled": true, "mineralization_enabled": true,
		"material_return_mg": 1000, "water_return_mg": 1000, "energy_dissipation_mj": 1000,
		"mineralization_per_cell_mg": 1000}

static func validate_policy(v: Variant) -> String:
	if not C.keys(v, ["schema", "decomposition_enabled", "mineralization_enabled", "material_return_mg", "water_return_mg", "energy_dissipation_mj", "mineralization_per_cell_mg"]) or v.schema != POLICY_SCHEMA:
		return "A6_POLICY_SCHEMA"
	if not v.decomposition_enabled is bool or not v.mineralization_enabled is bool:
		return "A6_POLICY_FLAGS"
	for name in ["material_return_mg", "water_return_mg", "energy_dissipation_mj", "mineralization_per_cell_mg"]:
		if not C.integer(v[name], 0, F.MAX_REQUEST): return "A6_POLICY_RATE"
	return ""

static func create(session_id: String, field: Dictionary, population: Array, policy: Dictionary) -> Dictionary:
	if not C.identifier(session_id): return _fail("A6_SESSION_ID")
	if not validate_policy(policy).is_empty(): return _fail(validate_policy(policy))
	if not F.validate_state(field).is_empty(): return _fail("A6_FIELD")
	if population.size() > MAX_POPULATION or field.cells.size() > MAX_CELLS:
		return _fail("A6_INITIAL_BUDGET")
	var entries: Array = []
	var seen := {}
	for entry in population:
		if not C.keys(entry, ["blueprint", "state"]) or not entry.blueprint is Dictionary or not entry.state is Dictionary:
			return _fail("A6_ENTRY")
		if not LS.validate(entry.state, entry.blueprint).is_empty(): return _fail("A6_ENTRY_INVALID")
		if seen.has(entry.state.individual_id): return _fail("A6_DUPLICATE_INDIVIDUAL")
		if _cell_index(field, entry.state.position_mm) < 0: return _fail("A6_POSITION")
		seen[entry.state.individual_id] = true
		entries.append(entry.duplicate(true))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.state.individual_id < b.state.individual_id)
	var payloads: Array = []
	for entry in entries:
		var text := LS.serialize(entry.state, entry.blueprint)
		if text.is_empty() or LS.deserialize(text).is_empty(): return _fail("A6_ENTRY_NOT_PERSISTABLE")
		payloads.append(text)
	var genesis := {"schema": GENESIS_SCHEMA, "session_id": session_id, "field": field.duplicate(true), "population": payloads, "policy": policy.duplicate(true)}
	var state := _seal({"schema": SCHEMA, "genesis": genesis, "genesis_hash": C.digest(genesis), "frame": _initial_frame(genesis), "integrity_hash": ""})
	var error := validate(state)
	return {"success": true, "state": state} if error.is_empty() else _fail(error)

static func advance(source: Dictionary, owner_token: String, owner_epoch: int, revision: int) -> Dictionary:
	var error := validate(source)
	if not error.is_empty(): return _fail(error)
	if owner_token != source.frame.field.owner_token: return _fail("STALE_OWNER")
	if owner_epoch != source.frame.field.owner_epoch: return _fail("STALE_OWNER_EPOCH")
	if revision != source.frame.step: return _fail("STALE_REVISION")
	if source.frame.step >= MAX_STEPS: return _fail("A6_STEP_BUDGET")
	if (source.frame.step + 1) * maxi(1, source.genesis.population.size()) > MAX_REPLAY_WORK:
		return _fail("A6_REPLAY_WORK_BUDGET")
	var advanced := _advance_frame(source.frame, source.genesis.policy)
	if not advanced.success: return advanced
	var candidate := source.duplicate(true)
	candidate.frame = advanced.frame
	candidate = _seal(candidate)
	error = _envelope_error(candidate)
	if not error.is_empty(): return _fail(error)
	error = _balance_error(candidate.genesis, candidate.frame)
	if not error.is_empty(): return _fail(error)
	# Source was replay-proved; the same deterministic transition produces this next frame.
	return {"success": true, "state": candidate}

static func validate(value: Variant) -> String:
	var error := _envelope_error(value)
	if not error.is_empty(): return error
	error = _genesis_error(value.genesis)
	if not error.is_empty(): return error
	if C.digest(value.genesis) != value.genesis_hash: return "A6_GENESIS_HASH"
	var expected := _initial_frame(value.genesis)
	error = _historical_admission_error(value.genesis, expected)
	if not error.is_empty(): return "A6_UNREACHABLE_HISTORY:" + error
	for _i in int(value.frame.step):
		var advanced := _advance_frame(expected, value.genesis.policy)
		if not advanced.success: return "A6_UNREACHABLE_HISTORY:" + String(advanced.error)
		expected = advanced.frame
		error = _historical_admission_error(value.genesis, expected)
		if not error.is_empty(): return "A6_UNREACHABLE_HISTORY:" + error
	if C.encode(expected) != C.encode(value.frame): return "A6_REPLAY_MISMATCH"
	return _balance_error(value.genesis, expected)

static func _historical_admission_error(genesis: Dictionary, frame: Dictionary) -> String:
	# Replay must obey the same per-step byte/balance boundaries as public advance.
	# A later smaller frame cannot legitimize an oversized earlier snapshot.
	var envelope := {"schema": SCHEMA, "genesis": genesis, "genesis_hash": "0".repeat(64),
		"frame": frame, "integrity_hash": "0".repeat(64)}
	var text := C.encode(envelope)
	if text.is_empty(): return "A6_NONCANONICAL"
	if text.to_utf8_buffer().size() > C.MAX_BYTES: return "A6_SNAPSHOT_BUDGET"
	return _balance_error(genesis, frame)

static func serialize(state: Dictionary) -> String:
	return C.encode(state) if validate(state).is_empty() else ""

static func deserialize(text: String, expected_genesis_hash: String, expected_revision: int) -> Dictionary:
	# Both anchors come from the caller's durable experiment manifest, not from this file.
	if not F.valid_hash(expected_genesis_hash) or not C.integer(expected_revision, 0, MAX_STEPS): return {}
	var decoded := C.decode(text)
	if not decoded.success or not decoded.value is Dictionary: return {}
	var v: Dictionary = decoded.value
	if not _envelope_error(v).is_empty(): return {}
	if v.genesis_hash != expected_genesis_hash or v.frame.step != expected_revision: return {}
	return v if validate(v).is_empty() else {}

static func balance(state: Dictionary) -> Dictionary:
	var error := validate(state)
	return _balance(state.genesis, state.frame) if error.is_empty() else _fail(error)

static func _envelope_error(v: Variant) -> String:
	if not C.keys(v, ["schema", "genesis", "genesis_hash", "frame", "integrity_hash"]) or v.schema != SCHEMA:
		return "A6_SCHEMA"
	if not v.genesis is Dictionary or not v.genesis.get("population") is Array or not v.frame is Dictionary:
		return "A6_ENVELOPE"
	if not C.keys(v.frame, ["schema", "step", "field", "population", "corpses", "propagules", "returned", "mineralized_mg", "dissipated_energy_mj"]) or v.frame.schema != FRAME_SCHEMA:
		return "A6_FRAME_SCHEMA"
	if not C.integer(v.frame.step, 0, MAX_STEPS) or v.genesis.population.size() > MAX_POPULATION:
		return "A6_STEP_BUDGET"
	if v.frame.step * maxi(1, v.genesis.population.size()) > MAX_REPLAY_WORK: return "A6_REPLAY_WORK_BUDGET"
	if not v.frame.population is Array or v.frame.population.size() > MAX_POPULATION or not v.frame.corpses is Array or v.frame.corpses.size() > MAX_POPULATION:
		return "A6_POPULATION_BUDGET"
	if not v.frame.propagules is Array or v.frame.propagules.size() > MAX_PROPAGULES: return "A6_PROPAGULE_BUDGET"
	var text := C.encode(v)
	if text.is_empty(): return "A6_NONCANONICAL"
	if text.to_utf8_buffer().size() > C.MAX_BYTES: return "A6_SNAPSHOT_BUDGET"
	if not F.valid_hash(v.genesis_hash) or not F.valid_hash(v.integrity_hash): return "A6_HASH"
	var payload: Dictionary = v.duplicate(true)
	payload.erase("integrity_hash")
	return "" if C.digest(payload) == v.integrity_hash else "A6_INTEGRITY_HASH"

static func _genesis_error(g: Dictionary) -> String:
	if not C.keys(g, ["schema", "session_id", "field", "population", "policy"]) or g.schema != GENESIS_SCHEMA or not C.identifier(g.session_id):
		return "A6_GENESIS_SCHEMA"
	if not validate_policy(g.policy).is_empty(): return "A6_GENESIS_POLICY"
	if not F.validate_state(g.field).is_empty() or g.field.cells.size() > MAX_CELLS: return "A6_GENESIS_FIELD"
	var prior := ""
	for text in g.population:
		if not text is String: return "A6_GENESIS_ENTRY"
		var entry := LS.deserialize(text)
		if entry.is_empty() or LS.serialize(entry.state, entry.blueprint) != text: return "A6_GENESIS_ENTRY"
		var id: String = entry.state.individual_id
		if not prior.is_empty() and id <= prior: return "A6_GENESIS_ID_ORDER"
		if _cell_index(g.field, entry.state.position_mm) < 0: return "A6_POSITION"
		prior = id
	return ""

static func _initial_frame(genesis: Dictionary) -> Dictionary:
	var corpses: Array = []
	for text in genesis.population:
		var entry := LS.deserialize(text)
		if not entry.state.alive: corpses.append(_corpse(entry.state, 0))
	return {"schema": FRAME_SCHEMA, "step": 0, "field": genesis.field.duplicate(true),
		"population": genesis.population.duplicate(), "corpses": corpses, "propagules": [],
		"returned": F.stock(), "mineralized_mg": 0, "dissipated_energy_mj": 0}

static func _advance_frame(source: Dictionary, policy: Dictionary) -> Dictionary:
	var frame := source.duplicate(true)
	var entries: Array = []
	var living: Array = []
	for text in frame.population:
		var entry := LS.deserialize(text)
		if entry.is_empty(): return _fail("A6_ENTRY_INVALID")
		entries.append(entry)
		if entry.state.alive: living.append(entry)
	if not living.is_empty():
		var f: Dictionary = frame.field
		var result := R.step_population(f, living, f.owner_token, f.owner_epoch, f.revision)
		if not result.success: return _fail("A6_LIFECYCLE:" + String(result.error))
		frame.field = result.field
		var by_id := {}
		for entry in result.population: by_id[entry.state.individual_id] = entry
		for i in entries.size():
			if by_id.has(entries[i].state.individual_id): entries[i] = by_id[entries[i].state.individual_id]
		if frame.propagules.size() + result.propagules.size() > MAX_PROPAGULES: return _fail("A6_PROPAGULE_BUDGET")
		for p in result.propagules:
			var parent: Dictionary = by_id[p.parent_id]
			var parent_text := LS.serialize(parent.state, parent.blueprint)
			# Outbox stores an emission, not a newly materialized descendant. Start
			# the existing witness check at depth zero; child materialization still
			# uses A5's stricter extra-generation budget at its own API boundary.
			if parent_text.is_empty() or not LS.validate_parent_transfer_witness(p, parent.blueprint, parent.state, 0).is_empty(): return _fail("A6_PAID_PROPAGULE")
			frame.propagules.append({"propagule": p.duplicate(true), "parent_payload": parent_text})
	frame.propagules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.propagule.id < b.propagule.id)
	var ids := {}
	for entry in entries: ids[entry.state.individual_id] = true
	var prior_seed := ""
	for receipt in frame.propagules:
		var id: String = receipt.propagule.id
		if ids.has(id) or id == prior_seed: return _fail("A6_PROPAGULE_ID_CONFLICT")
		prior_seed = id
	frame.population = []
	var corpses_by_id := {}
	for corpse in frame.corpses: corpses_by_id[corpse.individual_id] = true
	for entry in entries:
		var text := LS.serialize(entry.state, entry.blueprint)
		if text.is_empty() or LS.deserialize(text).is_empty(): return _fail("A6_ENTRY_NOT_PERSISTABLE")
		frame.population.append(text)
		if not entry.state.alive and not corpses_by_id.has(entry.state.individual_id):
			frame.corpses.append(_corpse(entry.state, frame.step + 1))
	frame.corpses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.individual_id < b.individual_id)
	var returned := _return_corpses(frame, entries, policy)
	if not returned.success: return returned
	frame = returned.frame
	var mineralized := _mineralize(frame, policy)
	if not mineralized.success: return mineralized
	frame = mineralized.frame
	var f: Dictionary = frame.field
	var tick := Field.advance_tick(f, f.owner_token, f.owner_epoch, f.revision)
	if not tick.success: return _fail("A6_FIELD_TICK:" + String(tick.error))
	frame.field = tick.state
	frame.step += 1
	return {"success": true, "frame": frame}

static func _corpse(state: Dictionary, death_step: int) -> Dictionary:
	var inventory := _inventory(state)
	return {"individual_id": state.individual_id, "death_step": death_step, "source_hash": C.digest(state),
		"inventory": inventory, "remaining": inventory.duplicate(true), "returned": F.stock(), "dissipated_energy_mj": 0}

static func _inventory(state: Dictionary) -> Dictionary:
	var out: Dictionary = state.metabolic_reserves.duplicate(true)
	for name in B.RESOURCES: out[name] += state.development.reserves[name]
	# Only material cost is retained body matter. Construction water/energy are sinks.
	for module in state.development.modules: out.material_mg += module.cost.material_mg
	return out

static func _return_corpses(frame: Dictionary, entries: Array, policy: Dictionary) -> Dictionary:
	if not policy.decomposition_enabled: return {"success": true, "frame": frame}
	var states := {}
	for entry in entries: states[entry.state.individual_id] = entry.state
	var rooms: Array = []
	for cell in frame.field.cells:
		rooms.append({"water_mg": cell.capacities.water_mg - cell.stocks.water_mg, "organic_mg": cell.capacities.organic_mg - cell.stocks.organic_mg})
	var effects: Array = []
	for corpse in frame.corpses:
		var state: Dictionary = states[corpse.individual_id]
		var index := _cell_index(frame.field, state.position_mm)
		if index < 0: return _fail("A6_POSITION")
		for resource in ["water_mg", "organic_mg"]:
			var internal: String = "material_mg" if resource == "organic_mg" else "water_mg"
			var rate: int = policy.material_return_mg if resource == "organic_mg" else policy.water_return_mg
			var amount: int = mini(rate, mini(corpse.remaining[internal], rooms[index][resource]))
			if amount == 0: continue
			var effect_id := "a6/return/%s/%d/%s" % [String(corpse.individual_id).sha256_text(), frame.step + 1, resource]
			effects.append(Ports.effect(effect_id, corpse.individual_id, "deposit", resource, amount, state.position_mm, 0, "A6_CORPSE_RETURN"))
			rooms[index][resource] -= amount
			corpse.remaining[internal] -= amount
			corpse.returned[resource] += amount
			frame.returned[resource] += amount
		var heat: int = mini(corpse.remaining.energy_mj, policy.energy_dissipation_mj)
		corpse.remaining.energy_mj -= heat
		corpse.dissipated_energy_mj += heat
		frame.dissipated_energy_mj += heat
	return _apply_effects(frame, effects)

static func _mineralize(frame: Dictionary, policy: Dictionary) -> Dictionary:
	if not policy.mineralization_enabled: return {"success": true, "frame": frame}
	var effects: Array = []
	var f: Dictionary = frame.field
	for cell in f.cells:
		var amount: int = mini(policy.mineralization_per_cell_mg, mini(cell.stocks.organic_mg, cell.capacities.nutrient_mg - cell.stocks.nutrient_mg))
		if amount == 0: continue
		var position := [int(f.origin_mm[0]) + int(cell.x) * int(f.cell_size_mm) + int(f.cell_size_mm / 2), int(f.origin_mm[1]), int(f.origin_mm[2]) + int(cell.z) * int(f.cell_size_mm) + int(f.cell_size_mm / 2)]
		var prefix := "a6/mineral/%d/%s/" % [frame.step + 1, cell.id]
		# Both effects commit through one A4 batch, including rollback on any failed effect.
		effects.append(Ports.effect(prefix + "0", "abiotic", "sink", "organic_mg", amount, position, 0, "A6_ABIOTIC_MINERALIZATION"))
		effects.append(Ports.effect(prefix + "1", "abiotic", "deposit", "nutrient_mg", amount, position, 0, "A6_ABIOTIC_MINERALIZATION"))
		frame.mineralized_mg += amount
	return _apply_effects(frame, effects)

static func _apply_effects(frame: Dictionary, effects: Array) -> Dictionary:
	if not effects.is_empty():
		var f: Dictionary = frame.field
		var applied := Field.apply_effects(f, effects, f.owner_token, f.owner_epoch, f.revision)
		if not applied.success: return _fail("A6_EFFECT:" + String(applied.error))
		frame.field = applied.state
	return {"success": true, "frame": frame}

static func _cell_index(field: Dictionary, position: Array) -> int:
	var x: int = position[0] - field.origin_mm[0]
	var z: int = position[2] - field.origin_mm[2]
	if x < 0 or z < 0 or x >= field.width * field.cell_size_mm or z >= field.depth * field.cell_size_mm:
		return -1
	return int(z / field.cell_size_mm) * int(field.width) + int(x / field.cell_size_mm)

static func _balance(genesis: Dictionary, frame: Dictionary) -> Dictionary:
	var initial := _field_inventory(genesis.field)
	var current := _field_inventory(frame.field)
	var external := B.stock()
	var sinks := B.stock()
	var initial_by_id := {}
	for text in genesis.population:
		var entry := LS.deserialize(text)
		initial_by_id[entry.state.individual_id] = entry.state
		_sum(initial, _inventory(entry.state))
	for text in frame.population:
		var entry := LS.deserialize(text)
		var state: Dictionary = entry.state
		var old: Dictionary = initial_by_id[state.individual_id]
		if state.alive: _sum(current, _inventory(state))
		external.energy_mj += state.resource_ledger.external_energy_mj - old.resource_ledger.external_energy_mj
		for name in B.RESOURCES:
			sinks[name] += state.resource_ledger.maintenance[name] - old.resource_ledger.maintenance[name]
			sinks[name] += state.resource_ledger.reproduction_cost[name] - old.resource_ledger.reproduction_cost[name]
		for name in ["water_mg", "energy_mj"]:
			sinks[name] += state.development.spent[name] - old.development.spent[name]
	for corpse in frame.corpses: _sum(current, corpse.remaining)
	for receipt in frame.propagules: _sum(current, receipt.propagule.endowment)
	sinks.energy_mj += frame.dissipated_energy_mj
	return {"initial": initial, "external": external, "current": current, "sinks": sinks}

static func _balance_error(genesis: Dictionary, frame: Dictionary) -> String:
	var accounts := _balance(genesis, frame)
	for account in accounts.values():
		if not LS.valid_cumulative_stock(account): return "A6_BALANCE_RANGE"
	for name in B.RESOURCES:
		if accounts.initial[name] + accounts.external[name] != accounts.current[name] + accounts.sinks[name]:
			return "A6_CONSERVATION_%s" % name
	return ""

static func _field_inventory(field: Dictionary) -> Dictionary:
	var total := F.totals(field.cells)
	return {"material_mg": total.organic_mg + total.nutrient_mg, "water_mg": total.water_mg, "energy_mj": 0}

static func _sum(target: Dictionary, delta: Dictionary) -> void:
	for name in B.RESOURCES: target[name] += delta[name]

static func _seal(state: Dictionary) -> Dictionary:
	var out := state.duplicate(true)
	out.erase("integrity_hash")
	var hash := C.digest(out)
	out["integrity_hash"] = hash
	return out

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
