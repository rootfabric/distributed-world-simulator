# EcologyWorkbench ExperimentController v1 (P2, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: canonical experiment loop wrapper. ZERO own biology: the ONE current
# ecology state trajectory lives in the shared canonical runtime
# (ecology_runtime_v1.gd): A5 executes exactly once per tick on the single
# field/population, mutated genomes enter the lineage only through sealed
# canonical mutation receipts + canonical A5 admission (no fallback), and the
# A6 post-lifecycle feedback transition mutates the SAME field the next tick
# reads. The controller only orchestrates, derives seeds and hashes.
# Layer: 2 (SIMULATION / ORCHESTRATION). Fail-closed: any canonical API
# failure stops the controller and surfaces the error.
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
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const OrganizationProfile = preload("res://scripts/ecology/workbench/organization_profile_v1.gd")
const EnvironmentPatch = preload("res://scripts/ecology/workbench/environment_patch_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")

const SCHEMA := "dws.ecology.workbench.experiment-controller.v1"
const STATE_SCHEMA := "dws.ecology.workbench.experiment-state.v1"
# Controller-declared genesis policy (deterministic, manifest-independent).
const OWNER_TOKEN := "eco-polygon.controller"
const DEFAULT_FOUNDER_ENDOWMENT_STOCK := 200000
const STATUSES := ["READY", "RUNNING", "PAUSED", "FAILED"]
# Historical controller mutation seed stream (deterministic, manifest-derived).
const MUTATION_KEY_PREFIX := "eco-arch2-a10-5/mut"

var _manifest: Dictionary = {}
var _founder_registry: Dictionary = {}
# THE single current ecology state (field + population + feedback
# bookkeeping + accounting + tick). No second field/population exists.
var _runtime: Dictionary = {}
var _status := "IDLE"
var _error := ""
# P12 WORLD_COMPAT: dependency-injected world authority adapter
# (EcoWorkbenchPolygonWorldAdapterV1). Null in LAB mode.
var _world_authority: Object = null

## Attach the WORLD_COMPAT world authority adapter (P12). The adapter is the
## source of world/environment authority (region ACTIVE gate, matter-mapped
## stocks). It MUST be attached before initialize() when manifest.mode ==
## "WORLD_COMPAT" (fail-closed otherwise). LAB mode ignores it.
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

## Validate the manifest and build the canonical initial state through the
## shared runtime: field (zones -> per-cell stocks/signals through the
## owner-write API), founders -> blueprints (inline genomes or hash
## registry), population (FOUNDER_ENDOWMENT) and feedback bookkeeping.
func initialize(manifest: Dictionary, founder_registry: Dictionary = {}) -> Dictionary:
	var manifest_error := Manifest.validate(manifest)
	if not manifest_error.is_empty():
		return _command_fail("CONTROLLER_MANIFEST:" + manifest_error)
	# P12 fail-closed: WORLD_COMPAT requires world authority deps.
	if String(manifest.mode) == "WORLD_COMPAT":
		if _world_authority == null:
			return _command_fail("CONTROLLER_WORLD_AUTHORITY_REQUIRED")
		var authority_check: Dictionary = _world_authority.world_manifest_compatible(manifest)
		if not bool(authority_check.get("success", false)):
			return _command_fail("CONTROLLER_WORLD_AUTHORITY:" + String(authority_check.get("error", "?")))
	var resolution := _resolve_founders(manifest.founders, founder_registry)
	if not resolution.success:
		return resolution
	var blueprints: Dictionary = resolution.blueprints
	var field_result := _build_field(manifest.environment)
	if not field_result.success:
		return field_result
	var field: Dictionary = field_result.field
	var population_result := _build_population(manifest, blueprints, field)
	if not population_result.success:
		return population_result
	var population: Array = population_result.population
	var policy := Feedback.default_policy()
	policy.decomposition_enabled = manifest.feedback.decomposition_enabled
	var created := Runtime.create(String(manifest.experiment_id), field, population, policy, bool(manifest.feedback.enabled))
	if not created.success:
		return _command_fail("CONTROLLER_RUNTIME_CREATE:" + String(created.error))
	_manifest = manifest.duplicate(true)
	_founder_registry = founder_registry.duplicate(true)
	_runtime = created.state
	_status = "READY"
	_error = ""
	return {"success": true, "tick": tick(), "status": _status}

## Advance exactly n canonical ticks. Speed = more ticks per call; dt never
## changes. Any canonical error stops the loop (fail-closed).
func run(n_ticks: int) -> Dictionary:
	var guard := _run_guard(n_ticks)
	if not guard.success:
		return guard
	for _i in n_ticks:
		_tick_once()
		if _status == "FAILED":
			return {"success": false, "error": _error, "status": _status, "tick": tick()}
	_status = "RUNNING"
	return {"success": true, "tick": tick(), "status": _status}

## Pause the loop (no tick is in flight; run/step resume from PAUSED).
func pause() -> Dictionary:
	if _status == "FAILED":
		return _failed_command()
	if _status == "RUNNING":
		_status = "PAUSED"
	return {"success": true, "tick": tick(), "status": _status}

## One canonical tick.
func step() -> Dictionary:
	return run(1)

## Alias of run(n_ticks) (time-mode equivalence contract).
func run_n(n_ticks: int) -> Dictionary:
	return run(n_ticks)

## Advance to an absolute simulation tick (P5 time control). Exactly
## equivalent to run(target - current_tick); wall-clock independent.
func run_to_tick(target_tick: int) -> Dictionary:
	if _status == "IDLE":
		return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED":
		return _failed_command()
	if not C.integer(target_tick, 0, int(_manifest.horizon_ticks)):
		return _command_fail("CONTROLLER_TARGET_TICK")
	if target_tick < tick():
		return _command_fail("CONTROLLER_TARGET_TICK")
	var remaining := target_tick - tick()
	if remaining == 0:
		return {"success": true, "tick": tick(), "status": _status}
	return run(remaining)

## Advance until max lineage depth reaches target_generation (or the horizon
## stops the loop). Returns {"generation": <reached depth>}.
func run_to_generation(target_generation: int) -> Dictionary:
	var guard := _run_guard(1)
	if not guard.success:
		return guard
	if not C.integer(target_generation, 1, C.MAX_INT):
		return _command_fail("CONTROLLER_TARGET_GENERATION")
	while tick() < int(_manifest.horizon_ticks) and _max_lineage_depth() < target_generation:
		_tick_once()
		if _status == "FAILED":
			return {"success": false, "error": _error, "status": _status, "tick": tick()}
	_status = "RUNNING"
	return {"success": true, "tick": tick(), "status": _status, "generation": _max_lineage_depth()}

## Advance until a run condition is met (or the horizon stops the loop).
## condition: {"population_at_least": int} OR {"tick": int} (tick == horizon).
## Returns {"met": bool} — false when the horizon was reached first.
func run_to_condition(condition: Dictionary) -> Dictionary:
	var guard := _run_guard(1)
	if not guard.success:
		return guard
	var error := _validate_condition(condition)
	if not error.is_empty():
		return _command_fail(error)
	while not _condition_met(condition):
		if tick() >= int(_manifest.horizon_ticks):
			return {"success": true, "tick": tick(), "status": _status, "met": false}
		_tick_once()
		if _status == "FAILED":
			return {"success": false, "error": _error, "status": _status, "tick": tick()}
	_status = "RUNNING"
	return {"success": true, "tick": tick(), "status": _status, "met": true}

func _validate_condition(condition: Dictionary) -> String:
	if not condition is Dictionary or condition.size() != 1:
		return "CONTROLLER_CONDITION"
	if condition.has("population_at_least"):
		if not C.integer(condition.population_at_least, 0, C.MAX_INT):
			return "CONTROLLER_CONDITION_POPULATION"
	elif condition.has("tick"):
		if not C.integer(condition.tick, 0, int(_manifest.horizon_ticks)):
			return "CONTROLLER_CONDITION_TICK"
	else:
		return "CONTROLLER_CONDITION"
	return ""

func _condition_met(condition: Dictionary) -> bool:
	if condition.has("population_at_least"):
		return _runtime.population.size() >= int(condition.population_at_least)
	if condition.has("tick"):
		return tick() >= int(condition.tick)
	return true

func _max_lineage_depth() -> int:
	var by_id := {}
	for entry in _runtime.population:
		by_id[entry.state.individual_id] = entry
	var depths := {}
	var depth := 0
	for entry in _runtime.population:
		depth = maxi(depth, _lineage_depth(String(entry.state.individual_id), by_id, depths))
	return depth

## Re-initialize from the stored manifest + founder registry (determinism).
func reset() -> Dictionary:
	if _manifest.is_empty():
		return _command_fail("CONTROLLER_NOT_INITIALIZED")
	return initialize(_manifest, _founder_registry)

## Completed immutable snapshot only. No mutation of live state.
func get_snapshot() -> Dictionary:
	if _status == "IDLE":
		return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED":
		return _failed_command()
	var population_hashes: Array = []
	for entry in _runtime.population:
		population_hashes.append({
			"individual_id": entry.state.individual_id,
			"life_state_hash": LifeState.state_hash(entry.state, entry.blueprint),
			"development_biological_hash": OrganismState.biological_hash(entry.state.development),
		})
	var feedback_view: Dictionary = Runtime.feedback_view(_runtime)
	var payload := {
		"tick": tick(),
		"field_hash": Field.state_hash(_runtime.field),
		"population": population_hashes,
		"feedback_hash": C.digest(feedback_view),
	}
	return {
		"success": true,
		"status": _status,
		"tick": tick(),
		"field_hash": payload.field_hash,
		"population": population_hashes,
		"feedback_hash": payload.feedback_hash,
		"canonical_state_hash": Runtime.state_hash(_runtime),
		# Presentation views (P4): read-only per-organism projection from the
		# canonical state. Deliberately OUTSIDE the canonical_state_hash payload
		# (it is a UI projection, not simulation truth).
		"presentation": _presentation_views(),
	}

## Read-only metrics projection (canonical observability only).
func get_metrics() -> Dictionary:
	if _status == "IDLE":
		return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED":
		return _failed_command()
	var alive := 0
	for entry in _runtime.population:
		if entry.state.alive:
			alive += 1
	var metrics := {
		"success": true,
		"status": _status,
		"tick": tick(),
		"population_size": _runtime.population.size(),
		"alive": alive,
		"manifest_hash": Manifest.canonical_hash(_manifest),
	}
	var balance := Runtime.balance(_runtime)
	if balance.get("success", false):
		metrics["feedback_balance"] = balance
	return metrics

## Deep-copied live state for equivalence harnesses (direct canonical loop).
## field/population are the ONE current truth; feedback is the runtime's
## read-only bookkeeping view (no second field/population exists anywhere).
func debug_state() -> Dictionary:
	return {
		"field": _runtime.field.duplicate(true),
		"population": _runtime.population.duplicate(true),
		"feedback": Runtime.feedback_view(_runtime),
		"runtime": _runtime.duplicate(true),
		"tick": tick(),
	}

## Deep-copied stored manifest (input layer; immutable at runtime).
func get_manifest() -> Dictionary:
	return _manifest.duplicate(true)

func status() -> String:
	return _status

func last_error() -> String:
	return _error

func tick() -> int:
	return int(_runtime.get("tick", 0))

# --- deterministic state serialization (P8: checkpoint/fork/replay) -----------
# Canonical-only: the whole controller state is the sealed canonical runtime
# state; the envelope is canonical_value_v1.encode (stable key order, no
# wall-clock, no presentation data — presentation is always re-derived).

## Serialize the canonical controller state (the shared runtime state + tick)
## into canonical text, bound to the manifest hash. Deterministic: identical
## states always serialize to the identical text.
func serialize_state() -> Dictionary:
	if _status == "IDLE":
		return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED":
		return _failed_command()
	var manifest_hash := Manifest.canonical_hash(_manifest)
	var external_state := {}
	if String(_manifest.mode) == "WORLD_COMPAT":
		if _world_authority == null:
			return _command_fail("CONTROLLER_WORLD_AUTHORITY_REQUIRED")
		external_state = _world_authority.export_state()
		if external_state.is_empty():
			return _command_fail("CONTROLLER_WORLD_STATE_EXPORT")
	var checkpoint := Checkpoint.create(manifest_hash, _runtime, external_state)
	if checkpoint.is_empty():
		return _command_fail("CONTROLLER_CHECKPOINT_CREATE")
	var text := Checkpoint.serialize(checkpoint)
	if text.is_empty():
		return _command_fail("CONTROLLER_STATE_ENCODE")
	return {
		"success": true,
		"state_text": text,
		# Caller-owned admission anchor. load_state requires this exact hash;
		# an attacker cannot rewrite + rehash the payload without also changing
		# the trusted value held by the checkpoint manager/caller.
		"state_checksum": text.sha256_text(),
		"checkpoint_checksum": String(checkpoint.checksum),
		"state_hash": String(checkpoint.runtime_state_hash),
		"external_state_hash": String(checkpoint.external_state_hash),
		"tick": tick(),
		"status": _status,
		"manifest_hash": manifest_hash,
	}

## Restore only from an externally anchored shared runtime checkpoint.
func load_state(state_text: String, expected_manifest_hash: String = "", expected_state_checksum: String = "") -> Dictionary:
	if _status == "IDLE":
		return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if expected_state_checksum.is_empty():
		return _command_fail("CONTROLLER_STATE_EXTERNAL_ANCHOR_REQUIRED")
	var current_manifest_hash := Manifest.canonical_hash(_manifest)
	if not expected_manifest_hash.is_empty() and expected_manifest_hash != current_manifest_hash:
		return _command_fail("CONTROLLER_STATE_MANIFEST_MISMATCH")
	var checkpoint := Checkpoint.deserialize(state_text, expected_state_checksum, current_manifest_hash)
	if checkpoint.is_empty():
		return _command_fail("CONTROLLER_STATE_ADMISSION")
	if String(_manifest.mode) == "WORLD_COMPAT":
		if checkpoint.external_state.is_empty() or String(checkpoint.external_state_hash).is_empty():
			return _command_fail("CONTROLLER_WORLD_STATE_REQUIRED")
		if _world_authority == null:
			return _command_fail("CONTROLLER_WORLD_AUTHORITY_REQUIRED")
		var imported: Dictionary = _world_authority.import_state(checkpoint.external_state, String(checkpoint.external_state_hash))
		if not bool(imported.get("success", false)):
			return _command_fail("CONTROLLER_WORLD_STATE_IMPORT:" + String(imported.get("error", "?")))
	elif not checkpoint.external_state.is_empty() or not String(checkpoint.external_state_hash).is_empty():
		return _command_fail("CONTROLLER_LAB_EXTERNAL_STATE")
	_runtime = checkpoint.runtime_state.duplicate(true)
	_status = "READY"
	_error = ""
	return {"success": true, "tick": tick(), "status": _status}

func apply_field_patch(patch: Dictionary) -> Dictionary:
	if _status == "IDLE" or _status == "FAILED":
		return _command_fail("CONTROLLER_NOT_INITIALIZED")
	var applied := EnvironmentPatch.apply_patch(_manifest, patch)
	if not bool(applied.get("success", false)):
		return _command_fail("CONTROLLER_FIELD_PATCH:" + String(applied.get("error", "?")))
	var next_manifest: Dictionary = applied.manifest
	# Deltas are computed against the ORIGINAL manifest zone values (the
	# patched manifest already carries the new declared values).
	var zones: Array = _manifest.environment.zones
	var total: int = int(next_manifest.environment.spatial.width) * int(next_manifest.environment.spatial.depth)
	var field: Dictionary = _runtime.field
	var effects: Array = []
	var signal_updates: Array = []
	for index in total:
		var zone: Dictionary = zones[mini(zones.size() - 1, index * zones.size() / total)]
		if not patch.zones.has(String(zone.id)):
			continue
		var edits: Dictionary = patch.zones[String(zone.id)]
		var center := _cell_center(field, index)
		for resource in FieldContract.RESOURCES:
			if not edits.has(resource):
				continue
			var delta: int = int(edits[resource]) - int(zone[resource])
			if delta == 0:
				continue
			# Canonical effects are bounded by FieldContract.MAX_REQUEST per
			# effect; larger deltas are split into deterministic chunks.
			var remaining := absi(delta)
			var chunk_index := 0
			while remaining > 0:
				var chunk: int = mini(remaining, FieldContract.MAX_REQUEST)
				effects.append(Ports.effect("branch-patch/%06d/%s/%03d" % [index, resource, chunk_index], OWNER_TOKEN, "deposit" if delta > 0 else "sink", resource, chunk, center, 0, "CONTROLLER_BRANCH_PATCH"))
				remaining -= chunk
				chunk_index += 1
		if edits.has("light") or edits.has("temperature"):
			signal_updates.append({
				"index": index,
				"signals": FieldContract.signals(int(edits.get("light", zone.light)), int(edits.get("temperature", zone.temperature)), 0, 0),
			})
	if not effects.is_empty():
		var effect_result := Field.apply_effects(field, effects, OWNER_TOKEN, int(field.owner_epoch), int(field.revision))
		if not bool(effect_result.get("success", false)):
			return _command_fail("CONTROLLER_FIELD_PATCH_EFFECTS:" + String(effect_result.get("error", "?")))
		field = effect_result.state
	for update in signal_updates:
		var index: int = int(update.index)
		var set_result := Field.set_cell_signals(field, index % int(field.width), int(index / int(field.width)), update.signals, OWNER_TOKEN, int(field.owner_epoch), int(field.revision))
		if not bool(set_result.get("success", false)):
			return _command_fail("CONTROLLER_FIELD_PATCH_SIGNALS:" + String(set_result.get("error", "?")))
		field = set_result.state
	var adopted := Runtime.adopt_field(_runtime, field)
	if not bool(adopted.get("success", false)):
		return _command_fail("CONTROLLER_FIELD_PATCH_ADOPT:" + String(adopted.get("error", "?")))
	_runtime = adopted.state
	_manifest = next_manifest
	return {"success": true, "tick": tick(), "field_hash": Field.state_hash(_runtime.field), "manifest_hash": Manifest.canonical_hash(_manifest)}

# --- P12 WORLD_COMPAT bridge: world-authority environment sampling -----------
# Minimal adapter-layer bridge (§23): the A10 matter_resource_mapping_v1
# admission (canonical, explicit-only) produces per-resource stock totals;
# they enter the A4 field EXCLUSIVELY through the canonical owner-write API
# (Field.apply_effects deposits) — the same path as genesis. No formula and
# no field truth is duplicated here; the patched field is adopted into the
# single runtime truth with an exact accounting re-anchor.

## Deposit one admitted Matter batch TOTAL through the canonical owner-write
## API. A total has no spatial meaning, so multi-cell fields fail closed until
## a production allocation witness exists. WORLD_COMPAT only.
func apply_world_stocks(resources: Dictionary, source_tag: String) -> Dictionary:
	if _status == "IDLE":
		return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED":
		return _failed_command()
	if String(_manifest.mode) != "WORLD_COMPAT":
		return _command_fail("CONTROLLER_WORLD_STOCKS_LAB")
	if not FieldContract.valid_total_stock(resources) or source_tag.is_empty():
		return _command_fail("CONTROLLER_WORLD_STOCKS_INPUT")
	# A Matter admission supplies a total batch amount, not a spatial
	# allocation. Replicating that total into every cell violates mass
	# conservation. Until production provides an allocation witness, only a
	# one-cell field can admit a total batch; multi-cell fails closed.
	if int(_runtime.field.width) * int(_runtime.field.depth) != 1:
		return _command_fail("CONTROLLER_WORLD_STOCKS_SPATIAL_ALLOCATION_REQUIRED")
	var field: Dictionary = _runtime.field
	var position := _cell_center(field, 0)
	var deposits: Array = []
	for resource in FieldContract.RESOURCES:
		var amount: int = int(resources[resource])
		if amount <= 0:
			continue
		var room := int(field.cells[0].capacities[resource]) - int(field.cells[0].stocks[resource])
		if amount > room:
			return _command_fail("CONTROLLER_WORLD_STOCK_CAPACITY:" + resource)
		var remaining := amount
		var chunk_index := 0
		while remaining > 0:
			var chunk: int = mini(remaining, FieldContract.MAX_REQUEST)
			deposits.append(Ports.effect("world/%s/%s/%03d" % [source_tag, resource, chunk_index], OWNER_TOKEN, "deposit", resource, chunk, position, 0, "CONTROLLER_WORLD_COMPAT"))
			remaining -= chunk
			chunk_index += 1
	if deposits.is_empty():
		return {"success": true, "tick": tick(), "field_hash": Field.state_hash(field), "deposited": false}
	var applied := Field.apply_effects(field, deposits, OWNER_TOKEN, int(field.owner_epoch), int(field.revision))
	if not bool(applied.get("success", false)):
		return _command_fail("CONTROLLER_WORLD_STOCKS_EFFECTS:" + String(applied.get("error", "?")))
	var adopted := Runtime.adopt_field(_runtime, applied.state)
	if not bool(adopted.get("success", false)):
		return _command_fail("CONTROLLER_WORLD_STOCKS_ADOPT:" + String(adopted.get("error", "?")))
	_runtime = adopted.state
	return {"success": true, "tick": tick(), "field_hash": Field.state_hash(_runtime.field), "deposited": true}

# --- presentation views (P4): read-only canonical projection -----------------

## Per-organism presentation view derived read-only from canonical state:
## {individual_id, position_mm, alive, zone_id, development_summary
##  {module_count, age_ticks}, parent_id, origin_kind, lineage_depth}.
## lineage_depth = max lineage depth: founders 0, children 1 + parent depth,
## computed from the organism_life_state parent chain (origin_receipt).
func _presentation_views() -> Array:
	var by_id := {}
	for entry in _runtime.population:
		by_id[entry.state.individual_id] = entry
	var depths := {}
	var views: Array = []
	for entry in _runtime.population:
		var state: Dictionary = entry.state
		var parent_id := ""
		if state.origin_kind == "PARENT_TRANSFER" and not state.origin_receipt.is_empty():
			parent_id = String(state.origin_receipt.parent_id)
		views.append({
			"individual_id": String(state.individual_id),
			"position_mm": [int(state.position_mm[0]), int(state.position_mm[1]), int(state.position_mm[2])],
			"alive": bool(state.alive),
			"zone_id": _zone_id_at(state.position_mm),
			"development_summary": {
				"module_count": int(state.development.modules.size()),
				"age_ticks": int(state.age_ticks),
			},
			"parent_id": parent_id,
			"origin_kind": String(state.origin_kind),
			"lineage_depth": _lineage_depth(String(state.individual_id), by_id, depths),
		})
	return views

func _lineage_depth(individual_id: String, by_id: Dictionary, memo: Dictionary) -> int:
	if memo.has(individual_id):
		return int(memo[individual_id])
	var depth := 0
	var entry: Dictionary = by_id.get(individual_id, {})
	if not entry.is_empty() \
			and entry.state.origin_kind == "PARENT_TRANSFER" \
			and not entry.state.origin_receipt.is_empty():
		var parent_id := String(entry.state.origin_receipt.parent_id)
		if by_id.has(parent_id):
			depth = 1 + _lineage_depth(parent_id, by_id, memo)
		else:
			depth = 1
	memo[individual_id] = depth
	return depth

## Zone of a canonical position using the SAME contiguous-band mapping as
## _build_field (zone index = min(zones-1, cell_index * zones / cells)).
func _zone_id_at(position_mm: Array) -> String:
	if _manifest.is_empty():
		return ""
	var cell := _cell_index(_runtime.field, position_mm)
	if cell < 0:
		return ""
	var environment: Dictionary = _manifest.environment
	var zones: Array = environment.zones
	var total: int = int(environment.spatial.width) * int(environment.spatial.depth)
	return String(zones[mini(zones.size() - 1, cell * zones.size() / total)].id)

# --- canonical tick: the ONLY place where state changes ---------------------
# One canonical tick = ONE shared-runtime step: A5 lifecycle (once) ->
# receipt-only propagule admission -> A6 post-lifecycle feedback on the SAME
# field. The controller adds no state transition of its own.

func _tick_once() -> void:
	# P12 WORLD_COMPAT: ACTIVE-only execution. The world authority gate runs
	# BEFORE any canonical mutation: a rejected admission leaves the whole
	# controller state untouched (fail-closed, state unchanged).
	if String(_manifest.mode) == "WORLD_COMPAT":
		var admitted: Dictionary = _world_authority.admit_execution()
		if not bool(admitted.get("success", false)):
			_fail("CONTROLLER_WORLD_AUTHORITY:" + String(admitted.get("error", "?")))
			return
	var profile := OrganizationProfile.preset(String(_manifest.organization_profile))
	var bias := {}
	if String(profile.rule_class) == "DEVELOPMENT_BIAS":
		var applied_bias := OrganizationProfile.apply_development_bias(profile)
		if not bool(applied_bias.get("success", false)) or not bool(applied_bias.get("applied", false)):
			_fail("CONTROLLER_DEVELOPMENT_BIAS")
			return
		bias = applied_bias.bias
	var stepped := Runtime.step(_runtime, {
		"mutations_enabled": bool(_manifest.mutation.mutations_enabled),
		"operator": String(_manifest.mutation.operator),
		"bias": bias,
		"seed": int(_manifest.seed),
		"mutation_key_prefix": MUTATION_KEY_PREFIX,
	})
	if not bool(stepped.get("success", false)):
		_fail("CONTROLLER_TICK:" + String(stepped.get("error", "?")))
		return
	_runtime = stepped.state

# --- deterministic seed derivation (no own RNG) ------------------------------

## Deterministic mutation seed from (manifest.seed, tick, parent_id), derived
## exclusively through the canonical genome_mutation_v1.draw stream with the
## historical controller key prefix (delegates to the shared runtime).
static func mutation_seed(seed: int, tick: int, parent_id: String) -> int:
	return Runtime.mutation_seed(seed, tick, parent_id, MUTATION_KEY_PREFIX)

# --- genesis builders --------------------------------------------------------

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
		if blueprint.is_empty():
			return _command_fail("CONTROLLER_FOUNDER_BLUEPRINT:" + founder.founder_id)
		blueprints[founder.founder_id] = blueprint
	return {"success": true, "blueprints": blueprints}

## Zone -> cells mapping: zone index = min(zones-1, cell_index * zones / cells)
## (deterministic contiguous bands by cell index). Zone stocks/signals are
## per-cell and are written ONLY through the canonical owner-write API
## (apply_effects deposits + set_cell_signals).
func _build_field(environment: Dictionary) -> Dictionary:
	var spatial: Dictionary = environment.spatial
	var zones: Array = environment.zones
	var field := Field.create(OWNER_TOKEN, 0, spatial.origin_mm, spatial.cell_size_mm, spatial.width, spatial.depth, FieldContract.stock(0), FieldContract.stock(FieldContract.MAX_CELL_STOCK), FieldContract.signals(0, 0))
	if field.is_empty():
		return _command_fail("CONTROLLER_FIELD_CREATE")
	var total: int = spatial.width * spatial.depth
	var deposits: Array = []
	for index in total:
		var zone: Dictionary = zones[mini(zones.size() - 1, index * zones.size() / total)]
		var position := _cell_center(field, index)
		for resource in FieldContract.RESOURCES:
			var amount: int = int(zone[resource])
			if amount <= 0:
				continue
			# Manifest accepts the full canonical per-cell stock range while one
			# A4 effect is bounded by MAX_REQUEST. Split deterministically instead
			# of introducing a second, smaller workbench stock ceiling.
			var remaining := amount
			var chunk_index := 0
			while remaining > 0:
				var chunk := mini(remaining, FieldContract.MAX_REQUEST)
				deposits.append(Ports.effect("setup/deposit/%04d/%s/%03d" % [index, resource, chunk_index], OWNER_TOKEN, "deposit", resource, chunk, position, 0, "CONTROLLER_GENESIS"))
				remaining -= chunk
				chunk_index += 1
	if not deposits.is_empty():
		var applied := Field.apply_effects(field, deposits, OWNER_TOKEN, 0, field.revision)
		if not applied.success:
			return _command_fail("CONTROLLER_FIELD_STOCKS:" + String(applied.error))
		field = applied.state
	for index in total:
		var zone: Dictionary = zones[mini(zones.size() - 1, index * zones.size() / total)]
		var signals := FieldContract.signals(int(zone.light), int(zone.temperature), 0, 0)
		var set := Field.set_cell_signals(field, index % int(spatial.width), int(index / int(spatial.width)), signals, OWNER_TOKEN, 0, field.revision)
		if not set.success:
			return _command_fail("CONTROLLER_FIELD_SIGNALS:" + String(set.error))
		field = set.state
	return {"success": true, "field": field}

func _build_population(manifest: Dictionary, blueprints: Dictionary, field: Dictionary) -> Dictionary:
	var population: Array = []
	var entries: Array = manifest.placement.entries
	var founder_endowment := B.stock(DEFAULT_FOUNDER_ENDOWMENT_STOCK)
	if manifest.has("genesis"):
		founder_endowment = manifest.genesis.founder_endowment.duplicate(true)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var blueprint: Dictionary = blueprints[entry.founder_ref]
		if _cell_index(field, entry.position_mm) < 0:
			return _command_fail("CONTROLLER_PLACEMENT_OUTSIDE_FIELD:%d" % index)
		var individual := Lifecycle.individual(blueprint, "founder/%04d" % index, entry.position_mm, founder_endowment)
		if individual.is_empty():
			return _command_fail("CONTROLLER_FOUNDER_STATE:%d" % index)
		population.append(individual)
	return {"success": true, "population": population}

# --- helpers ------------------------------------------------------------------

func _run_guard(n_ticks: int) -> Dictionary:
	if _status == "IDLE":
		return _command_fail("CONTROLLER_NOT_INITIALIZED")
	if _status == "FAILED":
		return _failed_command()
	if n_ticks < 1:
		return _command_fail("CONTROLLER_RUN_TICKS")
	if tick() + n_ticks > int(_manifest.horizon_ticks):
		return _command_fail("CONTROLLER_HORIZON")
	return {"success": true}

func _fail(error: String) -> void:
	_status = "FAILED"
	_error = error

func _failed_command() -> Dictionary:
	return {"success": false, "error": _error, "status": _status, "tick": tick()}

func _command_fail(error: String) -> Dictionary:
	return {"success": false, "error": error, "status": _status}

static func _cell_center(field: Dictionary, index: int) -> Array:
	var x: int = index % int(field.width)
	var z: int = int(index / int(field.width))
	return [int(field.origin_mm[0]) + x * int(field.cell_size_mm) + int(field.cell_size_mm / 2), int(field.origin_mm[1]), int(field.origin_mm[2]) + z * int(field.cell_size_mm) + int(field.cell_size_mm / 2)]

static func _cell_index(field: Dictionary, position: Array) -> int:
	var x: int = position[0] - field.origin_mm[0]
	var z: int = position[2] - field.origin_mm[2]
	if x < 0 or z < 0 or x >= field.width * field.cell_size_mm or z >= field.depth * field.cell_size_mm:
		return -1
	return int(z / field.cell_size_mm) * int(field.width) + int(x / field.cell_size_mm)
