extends RefCounted
## T15: per-instance structural divergence over T14/T13.5 shared families.
## A canonical/source-side local rebuild supplies a replacement full bundle whose
## binary differences must be exactly the selected leaf plus its ancestors. T15
## then forks only the affected instance to a new prepared family, projects the
## compatible caller-owned state, fences the superseded binding, and keeps every
## unaffected shared family/model immutable.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const T14 = preload("res://scripts/research/fabric_bake0/r5_t14_observation_refinement_runtime_v1.gd")

const RECEIPT_SCHEMA := "planet_simulator.fabric_t15_local_damage_receipt.v1"

var base = T14.new()
var _family_bundles: Dictionary = {}
var _current_binding_by_instance: Dictionary = {}
var _events: Dictionary = {}

var fork_events := 0
var state_projection_events := 0
var superseded_rejections := 0

func _binary_hash(value) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _instance_id(instance: Dictionary) -> String:
	return String(instance.get("binding", {}).get("instance_id", ""))

func _binding_checksum(instance: Dictionary) -> String:
	return String(instance.get("binding", {}).get("checksum", ""))

func _valid_id(value: String) -> bool:
	return not value.is_empty() and value.length() <= 128

func _current(instance: Dictionary) -> Dictionary:
	if not base.instance_valid(instance):
		return U.failure("T15_INSTANCE_INVALID")
	var instance_id := _instance_id(instance)
	if not _current_binding_by_instance.has(instance_id):
		return U.failure("T15_INSTANCE_NOT_REGISTERED")
	if String(_current_binding_by_instance[instance_id]) != _binding_checksum(instance):
		superseded_rejections += 1
		return U.failure("T15_INSTANCE_SUPERSEDED")
	return U.success()

func _manifest_walk(bundle: Dictionary, path: String, out: Dictionary) -> void:
	out[path] = _binary_hash(bundle)
	var children = bundle.get("children", {})
	if typeof(children) != TYPE_DICTIONARY:
		return
	var keys: Array = children.keys()
	keys.sort()
	for raw_slot in keys:
		var slot := String(raw_slot)
		if typeof(children[slot]) == TYPE_DICTIONARY:
			_manifest_walk(children[slot], path + "/" + slot, out)

func _manifest(bundle: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	_manifest_walk(bundle, "root", out)
	return out

func _affected_chain(path: String) -> Array:
	var parts := path.split("/")
	if parts.is_empty() or String(parts[0]) != "root":
		return []
	var out: Array = []
	for count in range(parts.size(), 0, -1):
		out.append("/".join(parts.slice(0, count)))
	out.sort()
	return out

func _changed_paths(old_bundle: Dictionary, new_bundle: Dictionary) -> Dictionary:
	var old_manifest := _manifest(old_bundle)
	var new_manifest := _manifest(new_bundle)
	var old_keys: Array = old_manifest.keys()
	var new_keys: Array = new_manifest.keys()
	old_keys.sort()
	new_keys.sort()
	if old_keys != new_keys:
		return U.failure("T15_TOPOLOGY_SHAPE_CHANGED", {
			"old_paths": old_keys,
			"new_paths": new_keys,
		})
	var changed: Array = []
	for raw_path in old_keys:
		var path := String(raw_path)
		if old_manifest[path] != new_manifest[path]:
			changed.append(path)
	return U.success({
		"changed_paths": changed,
		"unchanged_paths": old_keys.size() - changed.size(),
		"old_manifest": old_manifest,
		"new_manifest": new_manifest,
	})

func register_family(family_id: String, bundle: Dictionary, trusted_checksum: String) -> Dictionary:
	var registered: Dictionary = base.register_family(family_id, bundle, trusted_checksum)
	if registered.success:
		_family_bundles[family_id] = bundle.duplicate(true)
	return registered

func create_instance(family_id: String, instance_id: String, world_slot: String, soc: float = 0.8, temperature_k: float = 300.0) -> Dictionary:
	if not _valid_id(instance_id) or _current_binding_by_instance.has(instance_id):
		return U.failure("T15_INSTANCE_ID_DUPLICATE_OR_INVALID")
	var created: Dictionary = base.create_instance(family_id, instance_id, world_slot, soc, temperature_k)
	if created.success:
		_current_binding_by_instance[instance_id] = _binding_checksum(created.details)
	return created

func instance_valid(instance: Dictionary) -> bool:
	return _current(instance).success

func family_subtree_hash(family_id: String, path: String) -> String:
	return base.family_subtree_hash(family_id, path)

func family_identity(family_id: String) -> Dictionary:
	return base.family_identity(family_id)

func family_stats() -> Dictionary:
	return base.family_stats()

func all_models_intact() -> bool:
	return base.all_models_intact()

func request_observation(instance: Dictionary, path: String, observation_id: String) -> Dictionary:
	var checked := _current(instance)
	if not checked.success:
		return checked
	return base.request_refinement(instance, path, observation_id)

func release_observation(instance: Dictionary, observation_id: String) -> Dictionary:
	var checked := _current(instance)
	if not checked.success:
		return checked
	return base.release_refinement(instance, observation_id)

func execute(instance: Dictionary, commands: Dictionary, ambient_k: float, dt: float) -> Dictionary:
	var checked := _current(instance)
	if not checked.success:
		return checked
	return base.execute(instance, commands, ambient_k, dt)

func fork_instance(
	instance: Dictionary,
	new_family_id: String,
	replacement_bundle: Dictionary,
	trusted_checksum: String,
	selected_path: String,
	event_id: String,
	mutation_kind: String
) -> Dictionary:
	var checked := _current(instance)
	if not checked.success:
		return checked
	if not _valid_id(new_family_id) or not _valid_id(event_id):
		return U.failure("T15_EVENT_OR_FAMILY_ID_INVALID")
	if _events.has(event_id):
		return U.failure("T15_EVENT_ALREADY_APPLIED")
	if not ["DAMAGE", "REPAIR"].has(mutation_kind):
		return U.failure("T15_MUTATION_KIND_INVALID")
	if selected_path == "root" or not selected_path.begins_with("root/"):
		return U.failure("T15_SELECTED_PATH_INVALID")
	if not base.refinement_info(instance).is_empty():
		return U.failure("T15_ACTIVE_OBSERVATION_MUST_RELEASE")
	var old_family := String(instance.family_id)
	if not _family_bundles.has(old_family):
		return U.failure("T15_SOURCE_FAMILY_BUNDLE_MISSING")
	var old_bundle: Dictionary = _family_bundles[old_family]
	var diff := _changed_paths(old_bundle, replacement_bundle)
	if not diff.success:
		return diff
	var expected := _affected_chain(selected_path)
	if expected.is_empty() or diff.details.changed_paths != expected:
		return U.failure("T15_DIVERGENCE_NOT_LOCAL_TO_SELECTED_CHAIN", {
			"selected_path": selected_path,
			"expected_changed_paths": expected,
			"actual_changed_paths": diff.details.changed_paths,
		})
	var old_subtree_hash := String(diff.details.old_manifest.get(selected_path, ""))
	var new_subtree_hash := String(diff.details.new_manifest.get(selected_path, ""))
	if not U.is_lower_hex_64(old_subtree_hash) or not U.is_lower_hex_64(new_subtree_hash) or old_subtree_hash == new_subtree_hash:
		return U.failure("T15_SELECTED_SUBTREE_DID_NOT_DIVERGE")
	var old_model: Dictionary = base.family_identity(old_family)
	if old_model.is_empty():
		return U.failure("T15_OLD_MODEL_IDENTITY_MISSING")
	var registered: Dictionary = base.register_family(new_family_id, replacement_bundle, trusted_checksum)
	if not registered.success:
		return registered
	if bool(registered.details.get("deduplicated", false)):
		return U.failure("T15_DIVERGENT_FAMILY_UNEXPECTEDLY_ALIASED")
	_family_bundles[new_family_id] = replacement_bundle.duplicate(true)
	var created: Dictionary = base.create_instance(
		new_family_id,
		_instance_id(instance),
		String(instance.binding.world_slot),
		0.5,
		300.0
	)
	if not created.success:
		return created
	var next_instance: Dictionary = created.details
	var projected: Dictionary = next_instance.state.duplicate(true)
	projected.physical = instance.state.physical.duplicate(true)
	projected.state_revision = int(instance.state.state_revision) + 1
	projected.damage_revision = int(instance.state.damage_revision) + 1
	projected.disabled = bool(instance.state.disabled)
	next_instance.state = projected
	if not base.instance_valid(next_instance):
		return U.failure("T15_STATE_PROJECTION_UNSAFE")
	var before_physical_hash := _binary_hash(instance.state.physical)
	var after_physical_hash := _binary_hash(next_instance.state.physical)
	if before_physical_hash != after_physical_hash:
		return U.failure("T15_STATE_PROJECTION_CHANGED_PHYSICS")
	var new_model: Dictionary = base.family_identity(new_family_id)
	if new_model.is_empty():
		return U.failure("T15_NEW_MODEL_IDENTITY_MISSING")
	var receipt := {
		"schema": RECEIPT_SCHEMA,
		"event_id": event_id,
		"mutation_kind": mutation_kind,
		"instance_id": _instance_id(instance),
		"world_slot": String(instance.binding.world_slot),
		"selected_path": selected_path,
		"old_family_id": old_family,
		"new_family_id": new_family_id,
		"old_binding_checksum": _binding_checksum(instance),
		"new_binding_checksum": _binding_checksum(next_instance),
		"old_compiled_model_checksum": String(old_model.compiled_model_checksum),
		"old_compiled_model_hash": String(old_model.compiled_model_hash),
		"new_compiled_model_checksum": String(new_model.compiled_model_checksum),
		"new_compiled_model_hash": String(new_model.compiled_model_hash),
		"old_subtree_hash": old_subtree_hash,
		"new_subtree_hash": new_subtree_hash,
		"changed_paths": diff.details.changed_paths.duplicate(),
		"unchanged_paths": int(diff.details.unchanged_paths),
		"state_revision_before": int(instance.state.state_revision),
		"state_revision_after": int(next_instance.state.state_revision),
		"damage_revision_before": int(instance.state.damage_revision),
		"damage_revision_after": int(next_instance.state.damage_revision),
		"physical_state_hash_before": before_physical_hash,
		"physical_state_hash_after": after_physical_hash,
		"checksum": "",
	}
	receipt.checksum = U.compute_checksum(receipt)
	if not U.validate_checksum(receipt).success:
		return U.failure("T15_RECEIPT_INVALID")
	_current_binding_by_instance[_instance_id(instance)] = _binding_checksum(next_instance)
	_events[event_id] = receipt.duplicate(true)
	fork_events += 1
	state_projection_events += 1
	return U.success({
		"next_instance": next_instance,
		"receipt": receipt,
		"unique_model_prepares": int(base.family_stats().unique_model_prepares),
		"changed_paths": diff.details.changed_paths.duplicate(),
		"unchanged_paths": int(diff.details.unchanged_paths),
	})

func stats() -> Dictionary:
	return {
		"fork_events": fork_events,
		"state_projection_events": state_projection_events,
		"superseded_rejections": superseded_rejections,
		"event_receipts": _events.size(),
		"current_instances": _current_binding_by_instance.size(),
		"unique_model_prepares": int(base.family_stats().unique_model_prepares),
	}
