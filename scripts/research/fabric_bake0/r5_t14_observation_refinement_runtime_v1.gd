extends RefCounted
## T14: per-instance observation refinement over T13.5 shared structural families.
## Refinement materializes a detailed compiled-subtree manifest for one instance
## without recompiling, unbaking source leaves, or changing compact execution.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Families = preload("res://scripts/research/fabric_bake0/r5_t13_5_shared_families_runtime_v1.gd")

const REFINEMENT_SCHEMA := "planet_simulator.fabric_t14_observation_refinement.v1"
const SNAPSHOT_SCHEMA := "planet_simulator.fabric_t14_refinement_snapshot.v1"

var families = Families.new()
var _owner_bundles: Dictionary = {}
var _routes: Dictionary = {}
var _refinements: Dictionary = {}

var successful_requests := 0
var restore_count := 0
var release_count := 0
var materialization_count := 0
var detail_nodes_materialized := 0
var source_leaf_traversals := 0
var recompile_events := 0

func _binary_hash(value) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _instance_key(instance: Dictionary) -> String:
	return String(instance.get("binding", {}).get("checksum", ""))

func _instance_id(instance: Dictionary) -> String:
	return String(instance.get("binding", {}).get("instance_id", ""))

func _owner_for_family(family_id: String) -> String:
	return String(_routes.get(family_id, ""))

func register_family(family_id: String, bundle: Dictionary, trusted_checksum: String) -> Dictionary:
	var registered: Dictionary = families.register_family(family_id, bundle, trusted_checksum)
	if not registered.success:
		return registered
	var owner := String(registered.details.owner_family_id)
	_routes[family_id] = owner
	if not _owner_bundles.has(owner):
		_owner_bundles[owner] = bundle.duplicate(true)
	return registered

func create_instance(family_id: String, instance_id: String, world_slot: String, soc: float = 0.8, temperature_k: float = 300.0) -> Dictionary:
	return families.create_instance(family_id, instance_id, world_slot, soc, temperature_k)

func instance_valid(instance: Dictionary) -> bool:
	return families.instance_valid(instance)

func family_subtree_hash(family_id: String, path: String) -> String:
	return families.family_subtree_hash(family_id, path)

func family_identity(family_id: String) -> Dictionary:
	return families.family_identity(family_id)

func family_stats() -> Dictionary:
	return families.reuse_stats()

func all_models_intact() -> bool:
	return families.all_models_intact()

func _subtree(owner: String, path: String) -> Dictionary:
	if not _owner_bundles.has(owner) or path.is_empty():
		return {}
	var parts := path.split("/")
	if parts.is_empty() or String(parts[0]) != "root":
		return {}
	var current: Dictionary = _owner_bundles[owner]
	for index in range(1, parts.size()):
		var slot := String(parts[index])
		var children = current.get("children", {})
		if typeof(children) != TYPE_DICTIONARY or not children.has(slot):
			return {}
		if typeof(children[slot]) != TYPE_DICTIONARY:
			return {}
		current = children[slot]
	return current

func _manifest_walk(bundle: Dictionary, path: String, out: Array) -> void:
	var cap: Dictionary = bundle.get("capsule", {})
	out.append({
		"path": path,
		"kind": String(cap.get("executable_kind", "")),
		"capsule_checksum": String(cap.get("checksum", "")),
		"subtree_hash": _binary_hash(bundle),
		"source_component_count": int(cap.get("source_component_count", 0)),
	})
	var children: Dictionary = bundle.get("children", {})
	var keys: Array = children.keys()
	keys.sort()
	for raw_slot in keys:
		var slot := String(raw_slot)
		_manifest_walk(children[raw_slot], path + "/" + slot, out)

func _detail_manifest(bundle: Dictionary, path: String) -> Array:
	var out: Array = []
	_manifest_walk(bundle, path, out)
	return out

func _leaf_count(bundle: Dictionary) -> int:
	var children: Dictionary = bundle.get("children", {})
	if children.is_empty():
		return 1
	var count := 0
	for child in children.values():
		count += _leaf_count(child)
	return count

func _metadata_for(instance: Dictionary, observation_id: String, path: String, subtree: Dictionary, detail: Array) -> Dictionary:
	var family_id := String(instance.family_id)
	var owner := String(instance.owner_family_id)
	var model: Dictionary = families.family_identity(family_id)
	var metadata := {
		"schema": REFINEMENT_SCHEMA,
		"observation_id": observation_id,
		"instance_id": _instance_id(instance),
		"binding_checksum": _instance_key(instance),
		"family_id": family_id,
		"owner_family_id": owner,
		"path": path,
		"subtree_hash": _binary_hash(subtree),
		"compiled_model_checksum": String(model.get("compiled_model_checksum", "")),
		"compiled_model_hash": String(model.get("compiled_model_hash", "")),
		"state_revision": int(instance.state.state_revision),
		"damage_revision": int(instance.state.damage_revision),
		"detail_node_count": detail.size(),
		"detail_leaf_count": _leaf_count(subtree),
		"detail_manifest_hash": U.canonical_hash(detail),
		"checksum": "",
	}
	metadata.checksum = U.compute_checksum(metadata)
	return metadata

func request_refinement(instance: Dictionary, path: String, observation_id: String) -> Dictionary:
	if not families.instance_valid(instance):
		return U.failure("T14_INSTANCE_INVALID")
	if observation_id.is_empty() or observation_id.length() > 128:
		return U.failure("T14_OBSERVATION_ID_INVALID")
	if path == "root":
		return U.failure("T14_ROOT_REFINEMENT_FORBIDDEN")
	if not path.begins_with("root/"):
		return U.failure("T14_REFINEMENT_PATH_INVALID")
	var key := _instance_key(instance)
	if key.is_empty():
		return U.failure("T14_INSTANCE_IDENTITY_INVALID")
	if _refinements.has(key):
		return U.failure("T14_INSTANCE_ALREADY_REFINED")
	var family_id := String(instance.family_id)
	var owner := _owner_for_family(family_id)
	if owner.is_empty() or owner != String(instance.owner_family_id):
		return U.failure("T14_FAMILY_ROUTE_INVALID")
	var subtree := _subtree(owner, path)
	if subtree.is_empty():
		return U.failure("T14_REFINEMENT_PATH_UNKNOWN")
	var subtree_hash := _binary_hash(subtree)
	if subtree_hash != families.family_subtree_hash(family_id, path):
		return U.failure("T14_REFINEMENT_ANCHOR_MISMATCH")
	var detail := _detail_manifest(subtree, path)
	if detail.is_empty():
		return U.failure("T14_DETAIL_EMPTY")
	var metadata := _metadata_for(instance, observation_id, path, subtree, detail)
	if not U.validate_checksum(metadata).success or not U.is_lower_hex_64(String(metadata.detail_manifest_hash)):
		return U.failure("T14_REFINEMENT_METADATA_INVALID")
	_refinements[key] = {
		"metadata": metadata.duplicate(true),
		"detail": detail.duplicate(true),
	}
	successful_requests += 1
	materialization_count += 1
	detail_nodes_materialized += detail.size()
	return U.success({
		"refinement": metadata.duplicate(true),
		"detail": detail.duplicate(true),
		"active_refinements": _refinements.size(),
		"detail_nodes_materialized": detail_nodes_materialized,
		"source_leaf_traversals": source_leaf_traversals,
		"recompile_events": recompile_events,
		"unique_model_prepares": int(families.reuse_stats().unique_model_prepares),
	})

func refinement_info(instance: Dictionary) -> Dictionary:
	if not families.instance_valid(instance):
		return {}
	var key := _instance_key(instance)
	if not _refinements.has(key):
		return {}
	return _refinements[key].duplicate(true)

func path_resolution(instance: Dictionary, path: String) -> String:
	if not families.instance_valid(instance):
		return "INVALID"
	var family_id := String(instance.family_id)
	var owner := _owner_for_family(family_id)
	if owner.is_empty() or owner != String(instance.owner_family_id):
		return "INVALID"
	if _subtree(owner, path).is_empty():
		return "INVALID"
	var key := _instance_key(instance)
	if not _refinements.has(key):
		return "COMPACT"
	var selected := String(_refinements[key].metadata.path)
	if path == selected or path.begins_with(selected + "/"):
		return "DETAILED"
	if selected.begins_with(path + "/"):
		return "MIXED"
	return "COMPACT"

func resolution_summary(instances: Dictionary) -> Dictionary:
	var refined := 0
	for instance in instances.values():
		if typeof(instance) != TYPE_DICTIONARY or not families.instance_valid(instance):
			continue
		if _refinements.has(_instance_key(instance)):
			refined += 1
	return {
		"instances": instances.size(),
		"refined_instances": refined,
		"compact_instances": instances.size() - refined,
		"active_refinements": _refinements.size(),
	}

func execute(instance: Dictionary, commands: Dictionary, ambient_k: float, dt: float) -> Dictionary:
	if not families.instance_valid(instance):
		return U.failure("T14_INSTANCE_INVALID")
	var step: Dictionary = families.execute(instance, commands, ambient_k, dt)
	if not step.success:
		return step
	var key := _instance_key(instance)
	var active_path := ""
	if _refinements.has(key):
		active_path = String(_refinements[key].metadata.path)
	return U.success({
		"next_instance": step.details.next_instance,
		"physical": step.details.physical,
		"family_id": step.details.family_id,
		"owner_family_id": step.details.owner_family_id,
		"active_refinement_path": active_path,
		"instance_compile_events": 0,
		"recompile_events": recompile_events,
		"unique_model_prepares": int(families.reuse_stats().unique_model_prepares),
	})

func snapshot_refinement(instance: Dictionary) -> Dictionary:
	var info := refinement_info(instance)
	if info.is_empty():
		return U.failure("T14_REFINEMENT_NOT_ACTIVE")
	var envelope := {
		"schema": SNAPSHOT_SCHEMA,
		"metadata": info.metadata.duplicate(true),
	}
	var text := JSON.stringify(envelope, "", true)
	return U.success({"text": text, "sha256": text.sha256_text()})

func release_refinement(instance: Dictionary, observation_id: String) -> Dictionary:
	if not families.instance_valid(instance):
		return U.failure("T14_INSTANCE_INVALID")
	var key := _instance_key(instance)
	if not _refinements.has(key):
		return U.failure("T14_REFINEMENT_NOT_ACTIVE")
	if String(_refinements[key].metadata.observation_id) != observation_id:
		return U.failure("T14_OBSERVATION_ID_MISMATCH")
	_refinements.erase(key)
	release_count += 1
	return U.success({
		"active_refinements": _refinements.size(),
		"recompile_events": recompile_events,
	})

func restore_refinement(instance: Dictionary, text: String, trusted_hash: String) -> Dictionary:
	if not families.instance_valid(instance):
		return U.failure("T14_INSTANCE_INVALID")
	if text.length() > 8192 or not U.is_lower_hex_64(trusted_hash) or text.sha256_text() != trusted_hash:
		return U.failure("T14_SNAPSHOT_ANCHOR_MISMATCH")
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or parsed.size() != 2 or parsed.get("schema") != SNAPSHOT_SCHEMA:
		return U.failure("T14_SNAPSHOT_SHAPE_INVALID")
	if typeof(parsed.get("metadata")) != TYPE_DICTIONARY:
		return U.failure("T14_SNAPSHOT_METADATA_INVALID")
	var metadata: Dictionary = parsed.metadata
	# JSON has one numeric type. Normalize integer-valued revision/count fields
	# back to int before checksum validation so a valid snapshot round-trip does
	# not depend on parser Variant numeric representation.
	for field in ["state_revision", "damage_revision", "detail_node_count", "detail_leaf_count"]:
		if not U.is_json_integer(metadata.get(field)):
			return U.failure("T14_SNAPSHOT_METADATA_INVALID")
		metadata[field] = int(metadata[field])
	if not U.validate_checksum(metadata).success or metadata.get("schema") != REFINEMENT_SCHEMA:
		return U.failure("T14_SNAPSHOT_METADATA_INVALID")
	if metadata.get("binding_checksum") != _instance_key(instance) or metadata.get("instance_id") != _instance_id(instance):
		return U.failure("T14_SNAPSHOT_INSTANCE_MISMATCH")
	if metadata.get("family_id") != instance.family_id or metadata.get("owner_family_id") != instance.owner_family_id:
		return U.failure("T14_SNAPSHOT_FAMILY_MISMATCH")
	var current_model: Dictionary = families.family_identity(String(instance.family_id))
	if metadata.get("compiled_model_checksum") != current_model.get("compiled_model_checksum") or metadata.get("compiled_model_hash") != current_model.get("compiled_model_hash"):
		return U.failure("T14_SNAPSHOT_MODEL_MISMATCH")
	if int(metadata.get("state_revision", -1)) != int(instance.state.state_revision) or int(metadata.get("damage_revision", -1)) != int(instance.state.damage_revision):
		return U.failure("T14_SNAPSHOT_STATE_REVISION_MISMATCH")
	var key := _instance_key(instance)
	if _refinements.has(key):
		return U.failure("T14_INSTANCE_ALREADY_REFINED")
	var path := String(metadata.path)
	var subtree := _subtree(String(instance.owner_family_id), path)
	if subtree.is_empty() or _binary_hash(subtree) != String(metadata.subtree_hash):
		return U.failure("T14_SNAPSHOT_SUBTREE_MISMATCH")
	if families.family_subtree_hash(String(instance.family_id), path) != String(metadata.subtree_hash):
		return U.failure("T14_SNAPSHOT_FAMILY_ANCHOR_MISMATCH")
	var detail := _detail_manifest(subtree, path)
	if detail.size() != int(metadata.detail_node_count) or _leaf_count(subtree) != int(metadata.detail_leaf_count):
		return U.failure("T14_SNAPSHOT_DETAIL_SHAPE_MISMATCH")
	if U.canonical_hash(detail) != String(metadata.detail_manifest_hash):
		return U.failure("T14_SNAPSHOT_DETAIL_HASH_MISMATCH")
	_refinements[key] = {
		"metadata": metadata.duplicate(true),
		"detail": detail.duplicate(true),
	}
	restore_count += 1
	materialization_count += 1
	detail_nodes_materialized += detail.size()
	return U.success({
		"refinement": metadata.duplicate(true),
		"detail": detail.duplicate(true),
		"active_refinements": _refinements.size(),
		"detail_nodes_materialized": detail_nodes_materialized,
		"source_leaf_traversals": source_leaf_traversals,
		"recompile_events": recompile_events,
	})

func stats() -> Dictionary:
	return {
		"successful_requests": successful_requests,
		"restore_count": restore_count,
		"release_count": release_count,
		"materialization_count": materialization_count,
		"detail_nodes_materialized": detail_nodes_materialized,
		"source_leaf_traversals": source_leaf_traversals,
		"recompile_events": recompile_events,
		"active_refinements": _refinements.size(),
		"unique_model_prepares": int(families.reuse_stats().unique_model_prepares),
	}
