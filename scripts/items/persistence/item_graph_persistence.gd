extends RefCounted

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")

const SCHEMA: String = "planet_simulator.item_graph.v2"
const LEGACY_SCHEMA: String = "planet_simulator.item_graph.v1"
const SCHEMA_VERSION: int = 2
const LEGACY_SCHEMA_VERSION: int = 1

var domain: Dictionary = {}
var store
var state_key: String = "item-graph"
var metadata: Dictionary = {}


func setup(domain_reference: Dictionary, store_reference, configured_state_key: String = "item-graph") -> void:
	domain = domain_reference
	store = store_reference
	state_key = configured_state_key


func create_snapshot(extra_metadata: Dictionary = {}) -> Dictionary:
	var result: Dictionary = create_snapshot_result(extra_metadata)
	if not bool(result.get("success", false)):
		push_error("Unable to create item graph snapshot: %s" % result)
		return {}
	return Dictionary(result.get("snapshot", {}))


func create_snapshot_result(extra_metadata: Dictionary = {}) -> Dictionary:
	if domain.has("world_entities"):
		var migration_result: Dictionary = domain.world_entities.migrate_legacy_item_relations(domain.items)
		if not bool(migration_result.get("success", false)):
			return _section_failure("world_entity_migration", migration_result)
	var merged_metadata := metadata.duplicate(true)
	merged_metadata.merge(extra_metadata, true)
	merged_metadata = _normalize_metadata_types(merged_metadata)
	return {
		"success": true,
		"snapshot": {
			"schema": SCHEMA,
			"schema_version": SCHEMA_VERSION,
			"items": domain.items.to_dict(),
			"containers": domain.containers.to_dict(),
			"attachments": domain.attachments.to_dict(),
			"operations": domain.operations.to_dict(),
			"world_entities": domain.world_entities.to_dict(),
			"metadata": merged_metadata,
		},
	}


func save(extra_metadata: Dictionary = {}) -> Dictionary:
	if store == null or not store.has_method("save_state"):
		return _failure("ITEM_STATE_STORE_REQUIRED")
	var snapshot_result: Dictionary = create_snapshot_result(extra_metadata)
	if not bool(snapshot_result.get("success", false)):
		return snapshot_result
	var snapshot: Dictionary = Dictionary(snapshot_result.get("snapshot", {}))
	var validation := validate_snapshot(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	var result: Dictionary = store.save_state(state_key, snapshot)
	if bool(result.get("success", false)):
		metadata = _normalize_metadata_types(Dictionary(snapshot.get("metadata", {})))
	return result


func load() -> Dictionary:
	if store == null or not store.has_method("load_state"):
		return _failure("ITEM_STATE_STORE_REQUIRED")
	var loaded: Dictionary = store.load_state(state_key)
	if not bool(loaded.get("success", false)):
		return loaded
	var state_value = loaded.get("state", {})
	if not state_value is Dictionary:
		return _failure("INVALID_ITEM_GRAPH_STATE")
	return load_snapshot(Dictionary(state_value))


func has_state() -> bool:
	return store != null and store.has_method("has_state") and bool(store.has_state(state_key))


func delete_state() -> Dictionary:
	if store == null or not store.has_method("delete_state"):
		return _failure("ITEM_STATE_STORE_REQUIRED")
	return store.delete_state(state_key)


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var staged := Factory.create(int(domain.operations.maximum_entries) if domain.has("operations") else 2048)
	return _load_into_staged(staged, snapshot)


func load_snapshot(snapshot: Dictionary) -> Dictionary:
	var staged := Factory.create(int(domain.operations.maximum_entries) if domain.has("operations") else 2048)
	var staged_result := _load_into_staged(staged, snapshot)
	if not bool(staged_result.get("success", false)):
		return staged_result
	# Commit only after every registry and graph invariant has passed.
	domain.items.definitions = staged.items.definitions.duplicate()
	domain.items.items = staged.items.items.duplicate()
	domain.containers.replace_from(staged.containers)
	domain.operations.records = staged.operations.records.duplicate(true)
	domain.operations.next_sequence = staged.operations.next_sequence
	domain.operations.maximum_entries = staged.operations.maximum_entries
	domain.attachments.replace_from(staged.attachments)
	domain.world_entities.replace_from(staged.world_entities)
	metadata = _normalize_metadata_types(Dictionary(snapshot.get("metadata", {})))
	return {
		"success": true,
		"item_count": domain.items.items.size(),
		"container_count": domain.containers.containers.size(),
		"socket_count": domain.attachments.sockets.size(),
		"operation_count": domain.operations.size(),
		"world_entity_count": domain.world_entities.size(),
		"migrated_relation_count": int(staged_result.get("migrated_relation_count", 0)),
		"source_schema_version": int(staged_result.get("source_schema_version", SCHEMA_VERSION)),
		"metadata": metadata.duplicate(true),
	}


func _load_into_staged(staged: Dictionary, snapshot: Dictionary) -> Dictionary:
	var source_schema: String = String(snapshot.get("schema", ""))
	var source_version: int = int(snapshot.get("schema_version", 0))
	if source_schema == LEGACY_SCHEMA:
		if source_version != LEGACY_SCHEMA_VERSION:
			return _failure("UNSUPPORTED_ITEM_GRAPH_VERSION")
	elif source_schema == SCHEMA:
		if source_version != SCHEMA_VERSION:
			return _failure("UNSUPPORTED_ITEM_GRAPH_VERSION")
	else:
		return _failure("UNSUPPORTED_ITEM_GRAPH_SCHEMA")
	for required_key in ["items", "containers", "attachments", "operations"]:
		if not snapshot.get(required_key, {}) is Dictionary:
			return _failure("INVALID_ITEM_GRAPH_SECTION", {"section": required_key})
	var items_result: Dictionary = staged.items.load_dict(Dictionary(snapshot.items))
	if not bool(items_result.get("success", false)):
		return _section_failure("items", items_result)
	var containers_result: Dictionary = staged.containers.load_dict(Dictionary(snapshot.containers))
	if not bool(containers_result.get("success", false)):
		return _section_failure("containers", containers_result)
	var attachments_result: Dictionary = staged.attachments.load_dict(Dictionary(snapshot.attachments))
	if not bool(attachments_result.get("success", false)):
		return _section_failure("attachments", attachments_result)
	var operations_result: Dictionary = staged.operations.load_dict(Dictionary(snapshot.operations))
	if not bool(operations_result.get("success", false)):
		return _section_failure("operations", operations_result)
	if source_version == SCHEMA_VERSION:
		if not snapshot.get("world_entities", {}) is Dictionary:
			return _failure("INVALID_ITEM_GRAPH_SECTION", {"section": "world_entities"})
		var entities_result: Dictionary = staged.world_entities.load_dict(Dictionary(snapshot.world_entities))
		if not bool(entities_result.get("success", false)):
			return _section_failure("world_entities", entities_result)
	var migration_result: Dictionary = staged.world_entities.migrate_legacy_item_relations(staged.items)
	if not bool(migration_result.get("success", false)):
		return _section_failure("world_entity_migration", migration_result)
	var graph_result: Dictionary = staged.validator.validate_graph()
	if not bool(graph_result.get("success", false)):
		return _section_failure("graph", graph_result)
	var binding_result: Dictionary = staged.world_entities.validate_item_bindings(staged.items)
	if not bool(binding_result.get("success", false)):
		return _section_failure("world_entity_bindings", binding_result)
	if not snapshot.get("metadata", {}) is Dictionary:
		return _failure("INVALID_ITEM_GRAPH_METADATA")
	return {
		"success": true,
		"source_schema_version": source_version,
		"migrated_relation_count": int(migration_result.get("migrated_relation_count", 0)),
	}


func _normalize_metadata_types(value):
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key_value in value.keys():
			var key := String(key_value)
			var child = _normalize_metadata_types(value[key_value])
			if child is float and (key.ends_with("_index") or key.ends_with("_count") or key.ends_with("_revision")):
				child = int(child)
			normalized[key] = child
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for child in value:
			normalized_array.append(_normalize_metadata_types(child))
		return normalized_array
	return value


func _section_failure(section: String, result: Dictionary) -> Dictionary:
	return {
		"success": false,
		"error_code": String(result.get("error_code", "ITEM_GRAPH_SECTION_FAILED")),
		"section": section,
		"cause": result.duplicate(true),
	}


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
