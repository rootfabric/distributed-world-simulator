# EcologyWorkbench ExperimentController v1 — Repair R1.
# Thin orchestration over the shared canonical composed runtime. There is ONE
# mutable ecology trajectory only: ecology_composed_runtime_v1 owns field,
# population, corpses and A6 accounting. UI/presentation never own biology.
class_name EcoWorkbenchExperimentControllerV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LifeState = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const OrganismState = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_composed_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const EnvironmentPatch = preload("res://scripts/ecology/workbench/environment_patch_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const OrganizationProfile = preload("res://scripts/ecology/workbench/organization_profile_v1.gd")

const SCHEMA := "dws.ecology.workbench.experiment-controller.v1"
const STATE_SCHEMA := "dws.ecology.workbench.experiment-state.v2"
const OWNER_TOKEN := "eco-polygon.controller"
const DEFAULT_FOUNDER_ENDOWMENT_STOCK := 200000
const STATUSES := ["READY", "RUNNING", "PAUSED", "FAILED"]

var _manifest: Dictionary = {}
var _founder_registry: Dictionary = {}
var _runtime: Dictionary = {}
var _tick := 0
var _status := "IDLE"
var _error := ""
var _world_authority: Object = null
var _last_transition_events: Array = []

func attach_world_authority(authority: Object) -> Dictionary:
	if authority == null \
			or not authority.has_method("admit_execution") \
			or not authority.has_method("world_manifest_compatible") \
			or not authority.has_method("apply_environment") \
			or not authority.has_method("export_state") \
			or not authority.has_method("import_state"):
		return _command_fail("CONTROLLER_WORLD_AUTHORITY_INVALID")
	_world_authority = authority
	return {"success": true}

func initialize(manifest: Dictionary, founder_registry: Dictionary = {}) -> Dictionary:
	var manifest_error := Manifest.validate(manifest)
	if not manifest_error.is_empty():
		return _command_fail("CONTROLLER_MANIFEST:" + manifest_error)
	if String(manifest.mode) == "WORLD_COMPAT":
		if _world_authority == null:
			return _command_fail("CONTROLLER_WORLD_AUTHORITY_REQUIRED")
		var authority_check: Dictionary = _world_authority.world_manifest_compatible(manifest)
		if not bool(authority_check.get("success", false)):
			return _command_fail("CONTROLLER_WORLD_AUTHORITY:" + String(authority_check.get("error", "?")))
	var resolution := _resolve_founders(manifest.founders, founder_registry)
	if not resolution.success: return resolution
	var field_result := _build_field(manifest.environment)
	if not field_result.success: return field_result
	var population_result := _build_population(manifest, resolution.blueprints, field_result.field)
	if not population_result.success: return population_result
	var policy := Feedback.default_policy()
	policy.decomposition_enabled = bool(manifest.feedback.enabled) and bool(manifest.feedback.decomposition_enabled)
	policy.mineralization_enabled = bool(manifest.feedback.enabled) and bool(manifest.feedback.decomposition_enabled)
	var runtime := Runtime.create(field_result.field, population_result.population, policy)
	if runtime.is_empty():
		return _command_fail("CONTROLLER_RUNTIME_CREATE")
	_manifest = manifest.duplicate(true)
	_founder_registry = founder_registry.duplicate(true)
	_runtime = runtime
	_tick = int(runtime.tick)
	_status = "READY"
	_error = ""
	_last_transition_events = []
	return {"success": true, "tick": _tick, "status": _status}

func run(n_ticks: int) -> Dictionary:
	var guard := _run_guard(n_ticks)
	if not guard.success: return guard
	for _i in n_ticks:
		_tick_once()
		if _status == "FAILED": return {"success": false, "error": _error, "status": _status, "tick": _tick}
	_status = "RUNNING"
	return {"success": true, "tick": _tick, "status": _status}

func pause() -> Dictionary:
	if _status == "FAILED": return _failed_command()
	if _status == "RUNNING": _status = "PAUSED"
	return {"success": true, "tick": _tick, "status": _status}

func step() -> Dictionary:
	return run(1)

func run_n(n_ticks: int) -> Dictionary:
	return run(n_ticks)

func run_to_tick(target_tick: int) -> Dictionary:
	if _status == "IDLE": return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED": return _failed_command()
	if not C.integer(target_tick, 0, int(_manifest.horizon_ticks)) or target_tick < _tick:
		return _command_fail("CONTROLLER_TARGET_TICK")
	return {"success": true, "tick": _tick, "status": _status} if target_tick == _tick else run(target_tick - _tick)

func run_to_generation(target_generation: int) -> Dictionary:
	var guard := _run_guard(1)
	if not guard.success: return guard
	if not C.integer(target_generation, 1, C.MAX_INT): return _command_fail("CONTROLLER_TARGET_GENERATION")
	while _tick < int(_manifest.horizon_ticks) and _max_lineage_depth() < target_generation:
		_tick_once()
		if _status == "FAILED": return {"success": false, "error": _error, "status": _status, "tick": _tick}
	_status = "RUNNING"
	return {"success": true, "tick": _tick, "status": _status, "generation": _max_lineage_depth()}

func run_to_condition(condition: Dictionary) -> Dictionary:
	var guard := _run_guard(1)
	if not guard.success: return guard
	var error := _validate_condition(condition)
	if not error.is_empty(): return _command_fail(error)
	while not _condition_met(condition):
		if _tick >= int(_manifest.horizon_ticks):
			return {"success": true, "tick": _tick, "status": _status, "met": false}
		_tick_once()
		if _status == "FAILED": return {"success": false, "error": _error, "status": _status, "tick": _tick}
	_status = "RUNNING"
	return {"success": true, "tick": _tick, "status": _status, "met": true}

func _validate_condition(condition: Dictionary) -> String:
	if not condition is Dictionary or condition.size() != 1: return "CONTROLLER_CONDITION"
	if condition.has("population_at_least"):
		return "" if C.integer(condition.population_at_least, 0, C.MAX_INT) else "CONTROLLER_CONDITION_POPULATION"
	if condition.has("tick"):
		return "" if C.integer(condition.tick, 0, int(_manifest.horizon_ticks)) else "CONTROLLER_CONDITION_TICK"
	return "CONTROLLER_CONDITION"

func _condition_met(condition: Dictionary) -> bool:
	if condition.has("population_at_least"): return _runtime.population.size() >= int(condition.population_at_least)
	if condition.has("tick"): return _tick >= int(condition.tick)
	return true

func _max_lineage_depth() -> int:
	var by_id := {}
	for entry in _runtime.population: by_id[entry.state.individual_id] = entry
	var memo := {}
	var depth := 0
	for entry in _runtime.population:
		depth = maxi(depth, _lineage_depth(String(entry.state.individual_id), by_id, memo))
	return depth

func reset() -> Dictionary:
	if _manifest.is_empty(): return _command_fail("CONTROLLER_NOT_INITIALIZED")
	return initialize(_manifest, _founder_registry)

func get_snapshot() -> Dictionary:
	if _status == "IDLE": return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED": return _failed_command()
	var population_hashes: Array = []
	for entry in _runtime.population:
		population_hashes.append({
			"individual_id": entry.state.individual_id,
			"life_state_hash": LifeState.state_hash(entry.state, entry.blueprint),
			"development_biological_hash": OrganismState.biological_hash(entry.state.development),
		})
	var feedback := _feedback_view()
	return {
		"success": true, "status": _status, "tick": _tick,
		"field_hash": Field.state_hash(_runtime.field),
		"population": population_hashes,
		"feedback_hash": C.digest(feedback),
		"canonical_state_hash": String(_runtime.integrity_hash),
		"presentation": _presentation_views(),
	}

func get_metrics() -> Dictionary:
	if _status == "IDLE": return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED": return _failed_command()
	var alive := 0
	for entry in _runtime.population:
		if entry.state.alive: alive += 1
	return {
		"success": true, "status": _status, "tick": _tick, "population_size": _runtime.population.size(), "alive": alive,
		"manifest_hash": Manifest.canonical_hash(_manifest),
		"feedback_balance": {"success": true, "returned": _runtime.returned.duplicate(true),
			"mineralized_mg": int(_runtime.mineralized_mg), "dissipated_energy_mj": int(_runtime.dissipated_energy_mj)},
	}

func debug_state() -> Dictionary:
	return {"field": _runtime.field.duplicate(true), "population": _runtime.population.duplicate(true),
		"feedback": _feedback_view(), "runtime": _runtime.duplicate(true), "tick": _tick,
		"transition_events": _last_transition_events.duplicate(true)}

func get_manifest() -> Dictionary:
	return _manifest.duplicate(true)

func status() -> String:
	return _status

func last_error() -> String:
	return _error

func current_runtime_state() -> Dictionary:
	return _runtime.duplicate(true)

func serialize_state() -> Dictionary:
	if _status == "IDLE": return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED": return _failed_command()
	var manifest_hash := Manifest.canonical_hash(_manifest)
	var checkpoint := Checkpoint.create(manifest_hash, _runtime)
	if checkpoint.is_empty(): return _command_fail("CONTROLLER_CHECKPOINT_CREATE")
	var world_state := {}
	if String(_manifest.mode) == "WORLD_COMPAT":
		if _world_authority == null: return _command_fail("CONTROLLER_WORLD_AUTHORITY_REQUIRED")
		world_state = _world_authority.export_state()
		if world_state.is_empty(): return _command_fail("CONTROLLER_WORLD_STATE_EXPORT")
	var envelope := {"schema": STATE_SCHEMA, "manifest_hash": manifest_hash, "checkpoint": checkpoint,
		"world_state": world_state, "world_state_hash": "" if world_state.is_empty() else C.digest(world_state)}
	var text := C.encode(envelope)
	if text.is_empty(): return _command_fail("CONTROLLER_STATE_ENCODE")
	return {
		"success": true, "state_text": text, "state_checksum": text.sha256_text(),
		"checkpoint_checksum": String(checkpoint.checksum), "state_hash": String(checkpoint.runtime_state_hash),
		"tick": _tick, "status": _status, "manifest_hash": manifest_hash,
	}

func load_state(state_text: String, expected_manifest_hash: String = "", expected_state_checksum: String = "") -> Dictionary:
	if _status == "IDLE": return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if expected_state_checksum.is_empty() or state_text.sha256_text() != expected_state_checksum:
		return _command_fail("CONTROLLER_STATE_EXTERNAL_ANCHOR")
	var parsed := C.decode(state_text)
	if not bool(parsed.get("success", false)) or not parsed.value is Dictionary:
		return _command_fail("CONTROLLER_STATE_DECODE")
	var envelope: Dictionary = parsed.value
	if not C.keys(envelope, ["schema","manifest_hash","checkpoint","world_state","world_state_hash"]) or envelope.schema != STATE_SCHEMA:
		return _command_fail("CONTROLLER_STATE_SCHEMA")
	var current_manifest_hash := Manifest.canonical_hash(_manifest)
	if String(envelope.manifest_hash) != current_manifest_hash:
		return _command_fail("CONTROLLER_STATE_MANIFEST_MISMATCH")
	if not expected_manifest_hash.is_empty() and String(envelope.manifest_hash) != expected_manifest_hash:
		return _command_fail("CONTROLLER_STATE_MANIFEST_MISMATCH")
	var checkpoint: Dictionary = envelope.checkpoint
	var admitted := Checkpoint.admit(checkpoint, String(checkpoint.get("checksum", "")), current_manifest_hash)
	if not bool(admitted.get("success", false)):
		return _command_fail("CONTROLLER_CHECKPOINT:" + String(admitted.get("error", "?")))
	if not envelope.world_state is Dictionary:
		return _command_fail("CONTROLLER_WORLD_STATE")
	if not envelope.world_state.is_empty():
		if _world_authority == null or C.digest(envelope.world_state) != String(envelope.world_state_hash):
			return _command_fail("CONTROLLER_WORLD_STATE_ANCHOR")
		var imported: Dictionary = _world_authority.import_state(envelope.world_state, String(envelope.world_state_hash))
		if not bool(imported.get("success", false)):
			return _command_fail("CONTROLLER_WORLD_STATE_IMPORT:" + String(imported.get("error", "?")))
	elif not String(envelope.world_state_hash).is_empty():
		return _command_fail("CONTROLLER_WORLD_STATE_HASH")
	_runtime = checkpoint.runtime_state.duplicate(true)
	_tick = int(_runtime.tick)
	_status = "READY"
	_error = ""
	_last_transition_events = []
	return {"success": true, "tick": _tick, "status": _status}

func apply_field_patch(patch: Dictionary) -> Dictionary:
	if _status == "IDLE" or _status == "FAILED": return _command_fail("CONTROLLER_NOT_INITIALIZED")
	var applied := EnvironmentPatch.apply_patch(_manifest, patch)
	if not bool(applied.get("success", false)): return _command_fail("CONTROLLER_FIELD_PATCH:" + String(applied.get("error", "?")))
	var next_manifest: Dictionary = applied.manifest
	var zones: Array = _manifest.environment.zones
	var total: int = int(next_manifest.environment.spatial.width) * int(next_manifest.environment.spatial.depth)
	var field: Dictionary = _runtime.field.duplicate(true)
	var effects: Array = []
	var signal_updates: Array = []
	for index in total:
		var zone: Dictionary = zones[mini(zones.size() - 1, index * zones.size() / total)]
		if not patch.zones.has(String(zone.id)): continue
		var edits: Dictionary = patch.zones[String(zone.id)]
		var center := _cell_center(field, index)
		for resource in FieldContract.RESOURCES:
			if not edits.has(resource): continue
			var delta: int = int(edits[resource]) - int(zone[resource])
			var remaining := absi(delta)
			var chunk_index := 0
			while remaining > 0:
				var chunk := mini(remaining, FieldContract.MAX_REQUEST)
				effects.append(Ports.effect("branch-patch/%06d/%s/%03d" % [index, resource, chunk_index], OWNER_TOKEN,
					"deposit" if delta > 0 else "sink", resource, chunk, center, 0, "CONTROLLER_BRANCH_PATCH"))
				remaining -= chunk
				chunk_index += 1
		if edits.has("light") or edits.has("temperature"):
			signal_updates.append({"index": index, "signals": FieldContract.signals(int(edits.get("light", zone.light)), int(edits.get("temperature", zone.temperature)), 0, 0)})
	if not effects.is_empty():
		var effect_result := Field.apply_effects(field, effects, OWNER_TOKEN, int(field.owner_epoch), int(field.revision))
		if not effect_result.success: return _command_fail("CONTROLLER_FIELD_PATCH_EFFECTS:" + String(effect_result.error))
		field = effect_result.state
	for update in signal_updates:
		var index := int(update.index)
		var set_result := Field.set_cell_signals(field, index % int(field.width), int(index / int(field.width)), update.signals, OWNER_TOKEN, int(field.owner_epoch), int(field.revision))
		if not set_result.success: return _command_fail("CONTROLLER_FIELD_PATCH_SIGNALS:" + String(set_result.error))
		field = set_result.state
	var replaced := Runtime.replace_field(_runtime, field)
	if replaced.is_empty(): return _command_fail("CONTROLLER_FIELD_PATCH_RUNTIME")
	_runtime = replaced
	_manifest = next_manifest
	return {"success": true, "tick": _tick, "field_hash": Field.state_hash(_runtime.field), "manifest_hash": Manifest.canonical_hash(_manifest)}

## WORLD_COMPAT currently has a canonical batch total but no spatial allocation
## witness. Therefore exact mass conservation is possible only for a one-cell
## field; multi-cell use fails closed until a production allocation witness exists.
func apply_world_stocks(resources: Dictionary, source_tag: String) -> Dictionary:
	if _status == "IDLE": return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED": return _failed_command()
	if String(_manifest.mode) != "WORLD_COMPAT": return _command_fail("CONTROLLER_WORLD_STOCKS_LAB")
	if not FieldContract.valid_total_stock(resources) or source_tag.is_empty(): return _command_fail("CONTROLLER_WORLD_STOCKS_INPUT")
	if int(_runtime.field.width) * int(_runtime.field.depth) != 1:
		return _command_fail("CONTROLLER_WORLD_STOCKS_SPATIAL_ALLOCATION_REQUIRED")
	var field: Dictionary = _runtime.field.duplicate(true)
	var position := _cell_center(field, 0)
	var deposits: Array = []
	for resource in FieldContract.RESOURCES:
		var amount := int(resources[resource])
		if amount <= 0: continue
		if amount > int(field.cells[0].capacities[resource]) - int(field.cells[0].stocks[resource]):
			return _command_fail("CONTROLLER_WORLD_STOCK_CAPACITY:" + resource)
		var remaining := amount
		var chunk_index := 0
		while remaining > 0:
			var chunk := mini(remaining, FieldContract.MAX_REQUEST)
			deposits.append(Ports.effect("world/%s/%s/%03d" % [source_tag, resource, chunk_index], OWNER_TOKEN, "deposit", resource, chunk, position, 0, "CONTROLLER_WORLD_COMPAT"))
			remaining -= chunk
			chunk_index += 1
	if deposits.is_empty(): return {"success": true, "tick": _tick, "field_hash": Field.state_hash(field), "deposited": false}
	var applied := Field.apply_effects(field, deposits, OWNER_TOKEN, int(field.owner_epoch), int(field.revision))
	if not applied.success: return _command_fail("CONTROLLER_WORLD_STOCKS_EFFECTS:" + String(applied.error))
	var replaced := Runtime.replace_field(_runtime, applied.state)
	if replaced.is_empty(): return _command_fail("CONTROLLER_WORLD_STOCKS_RUNTIME")
	_runtime = replaced
	return {"success": true, "tick": _tick, "field_hash": Field.state_hash(_runtime.field), "deposited": true}

func _presentation_views() -> Array:
	var by_id := {}
	for entry in _runtime.population: by_id[entry.state.individual_id] = entry
	var depths := {}
	var views: Array = []
	for entry in _runtime.population:
		var state: Dictionary = entry.state
		var parent_id := ""
		if state.origin_kind in ["PARENT_TRANSFER","PARENT_MUTATION_TRANSFER"] and not state.origin_receipt.is_empty():
			parent_id = String(state.origin_receipt.parent_id)
		views.append({
			"individual_id": String(state.individual_id), "position_mm": state.position_mm.duplicate(true), "alive": bool(state.alive),
			"zone_id": _zone_id_at(state.position_mm),
			"development_summary": {"module_count": int(state.development.modules.size()), "age_ticks": int(state.age_ticks)},
			"parent_id": parent_id, "origin_kind": String(state.origin_kind),
			"lineage_depth": _lineage_depth(String(state.individual_id), by_id, depths),
		})
	return views

func _lineage_depth(individual_id: String, by_id: Dictionary, memo: Dictionary) -> int:
	if memo.has(individual_id): return int(memo[individual_id])
	var depth := 0
	var entry: Dictionary = by_id.get(individual_id, {})
	if not entry.is_empty() and entry.state.origin_kind in ["PARENT_TRANSFER","PARENT_MUTATION_TRANSFER"] and not entry.state.origin_receipt.is_empty():
		var parent_id := String(entry.state.origin_receipt.parent_id)
		depth = 1 + _lineage_depth(parent_id, by_id, memo) if by_id.has(parent_id) else 1
	memo[individual_id] = depth
	return depth

func _zone_id_at(position_mm: Array) -> String:
	if _manifest.is_empty(): return ""
	var cell := _cell_index(_runtime.field, position_mm)
	if cell < 0: return ""
	var zones: Array = _manifest.environment.zones
	var total := int(_manifest.environment.spatial.width) * int(_manifest.environment.spatial.depth)
	return String(zones[mini(zones.size() - 1, cell * zones.size() / total)].id)

func _tick_once() -> void:
	if String(_manifest.mode) == "WORLD_COMPAT":
		var admitted: Dictionary = _world_authority.admit_execution()
		if not bool(admitted.get("success", false)):
			_fail("CONTROLLER_WORLD_AUTHORITY:" + String(admitted.get("error", "?")))
			return
	var plan := _mutation_plan()
	if not bool(plan.get("success", false)):
		_fail(String(plan.get("error", "CONTROLLER_MUTATION_PLAN")))
		return
	var stepped := Runtime.step(_runtime, plan.mutation, int(_manifest.seed))
	if not bool(stepped.get("success", false)):
		_fail("CONTROLLER_RUNTIME_STEP:" + String(stepped.get("error", "?")))
		return
	_runtime = stepped.state
	_last_transition_events = stepped.events
	_tick = int(_runtime.tick)

func _mutation_plan() -> Dictionary:
	var profile := OrganizationProfile.preset(String(_manifest.organization_profile))
	var bias := {}
	if String(profile.rule_class) == "DEVELOPMENT_BIAS":
		var applied := OrganizationProfile.apply_development_bias(profile)
		if not bool(applied.get("success", false)) or not bool(applied.get("applied", false)):
			return {"success": false, "error": "CONTROLLER_DEVELOPMENT_BIAS"}
		bias = applied.bias
	return {"success": true, "mutation": {"enabled": bool(_manifest.mutation.mutations_enabled), "operator": String(_manifest.mutation.operator), "bias": bias}}

static func mutation_seed(seed: int, tick: int, parent_id: String) -> int:
	return Mutation.draw(seed, "runtime/%06d/%s" % [tick, parent_id], C.MAX_INT + 1)

func _resolve_founders(founders: Array, registry: Dictionary) -> Dictionary:
	var blueprints := {}
	for founder in founders:
		var genome: Dictionary = {}
		if founder.genome != null:
			genome = founder.genome
		else:
			if not registry is Dictionary or not registry.has(founder.biological_hash):
				return _command_fail("CONTROLLER_FOUNDER_UNRESOLVED:" + founder.founder_id)
			var candidate: Variant = registry[founder.biological_hash]
			if not candidate is Dictionary or not Genome.validate(candidate).is_empty():
				return _command_fail("CONTROLLER_FOUNDER_REGISTRY:" + founder.founder_id)
			if Genome.biological_hash(candidate) != founder.biological_hash:
				return _command_fail("CONTROLLER_FOUNDER_HASH_MISMATCH:" + founder.founder_id)
			genome = candidate
		var blueprint := Blueprint.create(genome)
		if blueprint.is_empty(): return _command_fail("CONTROLLER_FOUNDER_BLUEPRINT:" + founder.founder_id)
		blueprints[founder.founder_id] = blueprint
	return {"success": true, "blueprints": blueprints}

func _build_field(environment: Dictionary) -> Dictionary:
	var spatial: Dictionary = environment.spatial
	var zones: Array = environment.zones
	var capacity := FieldContract.stock(FieldContract.MAX_CELL_STOCK)
	var field := Field.create(OWNER_TOKEN, 0, spatial.origin_mm, spatial.cell_size_mm, spatial.width, spatial.depth, FieldContract.stock(0), capacity, FieldContract.signals(0, 0))
	if field.is_empty(): return _command_fail("CONTROLLER_FIELD_CREATE")
	var total := int(spatial.width) * int(spatial.depth)
	var deposits: Array = []
	for index in total:
		var zone: Dictionary = zones[mini(zones.size() - 1, index * zones.size() / total)]
		var position := _cell_center(field, index)
		for resource in FieldContract.RESOURCES:
			var remaining := int(zone[resource])
			var chunk_index := 0
			while remaining > 0:
				var chunk := mini(remaining, FieldContract.MAX_REQUEST)
				deposits.append(Ports.effect("setup/deposit/%04d/%s/%03d" % [index, resource, chunk_index], OWNER_TOKEN, "deposit", resource, chunk, position, 0, "CONTROLLER_GENESIS"))
				remaining -= chunk
				chunk_index += 1
	if not deposits.is_empty():
		var applied := Field.apply_effects(field, deposits, OWNER_TOKEN, 0, int(field.revision))
		if not applied.success: return _command_fail("CONTROLLER_FIELD_STOCKS:" + String(applied.error))
		field = applied.state
	for index in total:
		var zone: Dictionary = zones[mini(zones.size() - 1, index * zones.size() / total)]
		var set := Field.set_cell_signals(field, index % int(spatial.width), int(index / int(spatial.width)),
			FieldContract.signals(int(zone.light), int(zone.temperature), 0, 0), OWNER_TOKEN, 0, int(field.revision))
		if not set.success: return _command_fail("CONTROLLER_FIELD_SIGNALS:" + String(set.error))
		field = set.state
	return {"success": true, "field": field}

func _build_population(manifest: Dictionary, blueprints: Dictionary, field: Dictionary) -> Dictionary:
	var population: Array = []
	var endowment := B.stock(DEFAULT_FOUNDER_ENDOWMENT_STOCK)
	if manifest.has("genesis"): endowment = manifest.genesis.founder_endowment.duplicate(true)
	for index in manifest.placement.entries.size():
		var entry: Dictionary = manifest.placement.entries[index]
		if _cell_index(field, entry.position_mm) < 0: return _command_fail("CONTROLLER_PLACEMENT_OUTSIDE_FIELD:%d" % index)
		var individual := Lifecycle.individual(blueprints[entry.founder_ref], "founder/%04d" % index, entry.position_mm, endowment)
		if individual.is_empty(): return _command_fail("CONTROLLER_FOUNDER_STATE:%d" % index)
		population.append(individual)
	return {"success": true, "population": population}

func _feedback_view() -> Dictionary:
	if _runtime.is_empty(): return {}
	return {"frame": {"step": int(_runtime.tick), "field": _runtime.field.duplicate(true), "population": _runtime.population.duplicate(true),
		"corpses": _runtime.corpses.duplicate(true), "returned": _runtime.returned.duplicate(true),
		"mineralized_mg": int(_runtime.mineralized_mg), "dissipated_energy_mj": int(_runtime.dissipated_energy_mj)}}

func _run_guard(n_ticks: int) -> Dictionary:
	if _status == "IDLE": return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED": return _failed_command()
	if n_ticks < 1: return _command_fail("CONTROLLER_RUN_TICKS")
	if _tick + n_ticks > int(_manifest.horizon_ticks): return _command_fail("CONTROLLER_HORIZON")
	return {"success": true}

func _fail(error: String) -> void:
	_status = "FAILED"
	_error = error

func _failed_command() -> Dictionary:
	return {"success": false, "error": _error, "status": _status, "tick": _tick}

func _command_fail(error: String) -> Dictionary:
	return {"success": false, "error": error, "status": _status}

static func _cell_center(field: Dictionary, index: int) -> Array:
	var x := index % int(field.width)
	var z := int(index / int(field.width))
	return [int(field.origin_mm[0]) + x * int(field.cell_size_mm) + int(field.cell_size_mm / 2), int(field.origin_mm[1]), int(field.origin_mm[2]) + z * int(field.cell_size_mm) + int(field.cell_size_mm / 2)]

static func _cell_index(field: Dictionary, position: Array) -> int:
	var x: int = position[0] - field.origin_mm[0]
	var z: int = position[2] - field.origin_mm[2]
	if x < 0 or z < 0 or x >= field.width * field.cell_size_mm or z >= field.depth * field.cell_size_mm: return -1
	return int(z / field.cell_size_mm) * int(field.width) + int(x / field.cell_size_mm)
