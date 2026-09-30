extends RefCounted
## T13.5: intern compiled subtree identities and route many variant instances to a
## bounded set of prepared T13 family models. Instance hot paths never compile.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/ship_matryoshka_contract_v1.gd")
const Shared = preload("res://scripts/research/fabric_bake0/r5_t13_shared_instances_runtime_v1.gd")

const FAMILY_SCHEMA := "planet_simulator.fabric_t13_5_family.v1"
const INSTANCE_SCHEMA := "planet_simulator.fabric_t13_5_family_instance.v1"

var _owners: Dictionary = {}
var _routes: Dictionary = {}
var _model_hash_to_owner: Dictionary = {}
var _manifests: Dictionary = {}
var _subtree_pool: Dictionary = {}
var _subtree_families: Dictionary = {}

var family_registrations := 0
var alias_registrations := 0
var unique_model_prepares := 0
var instance_count := 0
var subtree_intern_events := 0
var subtree_reuse_hits := 0

func _binary_hash(value) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _valid_id(value: String) -> bool:
	return not value.is_empty() and value.length() <= 128

func _resolve_owner(family_id: String) -> String:
	return String(_routes.get(family_id, ""))

func _index_subtrees(owner: String, bundle: Dictionary, path: String = "root") -> void:
	var hash := _binary_hash(bundle)
	_manifests[owner][path] = hash
	if not _subtree_pool.has(hash):
		_subtree_pool[hash] = bundle.duplicate(true)
		subtree_intern_events += 1
	else:
		subtree_reuse_hits += 1
	var families: Dictionary = _subtree_families.get(hash, {})
	families[owner] = true
	_subtree_families[hash] = families
	var children: Dictionary = bundle.get("children", {})
	var keys: Array = children.keys()
	keys.sort()
	for raw_slot in keys:
		var slot := String(raw_slot)
		_index_subtrees(owner, children[raw_slot], path + "/" + slot)

func register_family(family_id: String, bundle: Dictionary, trusted_checksum: String) -> Dictionary:
	if not _valid_id(family_id) or _routes.has(family_id):
		return U.failure("T13_5_FAMILY_ID_INVALID")
	var checked := C.verify(bundle, trusted_checksum)
	if not checked.success:
		return checked
	if String(bundle.capsule.executable_kind) != "T12_SHIP":
		return U.failure("T13_5_FAMILY_KIND_INVALID")
	var model_hash := _binary_hash(bundle)
	if not U.is_lower_hex_64(model_hash):
		return U.failure("T13_5_MODEL_HASH_INVALID")
	if _model_hash_to_owner.has(model_hash):
		var owner := String(_model_hash_to_owner[model_hash])
		_routes[family_id] = owner
		family_registrations += 1
		alias_registrations += 1
		return U.success({
			"schema": FAMILY_SCHEMA,
			"family_id": family_id,
			"owner_family_id": owner,
			"deduplicated": true,
			"model_hash": model_hash,
			"unique_model_prepares": unique_model_prepares,
		})
	var shared = Shared.new()
	var prepared: Dictionary = shared.prepare(bundle, trusted_checksum)
	if not prepared.success:
		return prepared
	_owners[family_id] = shared
	_routes[family_id] = family_id
	_model_hash_to_owner[model_hash] = family_id
	_manifests[family_id] = {}
	_index_subtrees(family_id, bundle)
	family_registrations += 1
	unique_model_prepares += 1
	return U.success({
		"schema": FAMILY_SCHEMA,
		"family_id": family_id,
		"owner_family_id": family_id,
		"deduplicated": false,
		"model_hash": model_hash,
		"compiled_model_checksum": prepared.details.compiled_model_checksum,
		"compiled_model_hash": prepared.details.compiled_model_hash,
		"source_component_count": prepared.details.source_component_count,
		"state_scalars_per_instance": prepared.details.state_scalars_per_instance,
		"unique_model_prepares": unique_model_prepares,
	})

func family_identity(family_id: String) -> Dictionary:
	var owner := _resolve_owner(family_id)
	if owner.is_empty() or not _owners.has(owner):
		return {}
	var model: Dictionary = _owners[owner].model_identity()
	return {
		"schema": FAMILY_SCHEMA,
		"family_id": family_id,
		"owner_family_id": owner,
		"compiled_model_checksum": model.compiled_model_checksum,
		"compiled_model_hash": model.compiled_model_hash,
		"prepare_count": model.prepare_count,
	}

func family_subtree_hash(family_id: String, path: String) -> String:
	var owner := _resolve_owner(family_id)
	if owner.is_empty() or not _manifests.has(owner):
		return ""
	return String(_manifests[owner].get(path, ""))

func reuse_stats() -> Dictionary:
	var shared_hashes := 0
	var max_family_reuse := 0
	for hash in _subtree_families:
		var count := int(_subtree_families[hash].size())
		if count > 1:
			shared_hashes += 1
		max_family_reuse = maxi(max_family_reuse, count)
	var occurrences := 0
	for owner in _manifests:
		occurrences += int(_manifests[owner].size())
	return {
		"family_registrations": family_registrations,
		"alias_registrations": alias_registrations,
		"unique_model_prepares": unique_model_prepares,
		"unique_subtree_hashes": _subtree_pool.size(),
		"subtree_occurrences": occurrences,
		"shared_subtree_hashes": shared_hashes,
		"max_family_reuse": max_family_reuse,
		"subtree_intern_events": subtree_intern_events,
		"subtree_reuse_hits": subtree_reuse_hits,
		"instance_count": instance_count,
	}

func create_instance(family_id: String, instance_id: String, world_slot: String, soc: float = 0.8, temperature_k: float = 300.0) -> Dictionary:
	var owner := _resolve_owner(family_id)
	if owner.is_empty() or not _owners.has(owner):
		return U.failure("T13_5_FAMILY_UNKNOWN")
	var shared = _owners[owner]
	var bound: Dictionary = shared.create_binding(instance_id, world_slot)
	if not bound.success:
		return bound
	var state: Dictionary = shared.initial_state(bound.details, soc, temperature_k)
	if state.is_empty():
		return U.failure("T13_5_INSTANCE_STATE_INVALID")
	instance_count += 1
	return U.success({
		"schema": INSTANCE_SCHEMA,
		"family_id": family_id,
		"owner_family_id": owner,
		"binding": bound.details,
		"state": state,
	})

func instance_valid(instance: Dictionary) -> bool:
	if instance.size() != 5 or instance.get("schema") != INSTANCE_SCHEMA:
		return false
	var family_id := String(instance.get("family_id", ""))
	var owner := _resolve_owner(family_id)
	if owner.is_empty() or owner != String(instance.get("owner_family_id", "")) or not _owners.has(owner):
		return false
	if typeof(instance.get("binding")) != TYPE_DICTIONARY or typeof(instance.get("state")) != TYPE_DICTIONARY:
		return false
	return _owners[owner].state_valid(instance.binding, instance.state)

func execute(instance: Dictionary, commands: Dictionary, ambient_k: float, dt: float) -> Dictionary:
	if not instance_valid(instance):
		return U.failure("T13_5_INSTANCE_INVALID")
	var owner := String(instance.owner_family_id)
	var step: Dictionary = _owners[owner].execute(instance.binding, instance.state, commands, ambient_k, dt)
	if not step.success:
		return step
	var next_instance: Dictionary = instance.duplicate(true)
	next_instance.state = step.details.next_state
	return U.success({
		"next_instance": next_instance,
		"physical": step.details.physical,
		"family_id": instance.family_id,
		"owner_family_id": owner,
		"prepare_count": unique_model_prepares,
		"instance_compile_events": 0,
	})

func apply_damage(instance: Dictionary, disabled: bool = true) -> Dictionary:
	if not instance_valid(instance):
		return U.failure("T13_5_INSTANCE_INVALID")
	var owner := String(instance.owner_family_id)
	var damaged: Dictionary = _owners[owner].apply_damage(instance.binding, instance.state, disabled)
	if not damaged.success:
		return damaged
	var next_instance: Dictionary = instance.duplicate(true)
	next_instance.state = damaged.details.next_state
	return U.success({
		"next_instance": next_instance,
		"family_id": instance.family_id,
		"owner_family_id": owner,
		"prepare_count": unique_model_prepares,
		"instance_compile_events": 0,
	})

func all_models_intact() -> bool:
	for owner in _owners:
		if not _owners[owner].model_intact():
			return false
	return true
