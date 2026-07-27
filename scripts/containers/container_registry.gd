extends RefCounted

const ContainerStateScript = preload("res://scripts/containers/container_state.gd")

const SCHEMA: String = "planet_simulator.container_registry.v2"
const SCHEMA_VERSION: int = 2

var containers: Dictionary = {}


func add_container(container) -> bool:
	if container == null or String(container.container_id).is_empty():
		return false
	if containers.has(container.container_id):
		return false
	containers[container.container_id] = container
	return true


func get_container(container_id: String) -> Variant:
	return containers.get(container_id)


func all_containers() -> Array:
	return containers.values()


func remove_container(container_id: String) -> bool:
	var container = get_container(container_id)
	if container == null or not container.item_ids.is_empty():
		return false
	return containers.erase(container_id)


func to_dict() -> Dictionary:
	var rows: Array = []
	var ids := containers.keys()
	ids.sort()
	for container_id in ids:
		rows.append(containers[container_id].to_dict())
	return {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"containers": rows,
	}


func load_dict(data: Dictionary) -> Dictionary:
	var schema := String(data.get("schema", ""))
	if not schema.is_empty() and schema != SCHEMA:
		return _failure("UNSUPPORTED_CONTAINER_REGISTRY_SCHEMA")
	if schema == SCHEMA and int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		return _failure("UNSUPPORTED_CONTAINER_REGISTRY_VERSION")
	var rows = data.get("containers", [])
	if not rows is Array:
		return _failure("INVALID_CONTAINER_ROWS")
	var next_containers: Dictionary = {}
	for row_value in rows:
		if not row_value is Dictionary:
			return _failure("INVALID_CONTAINER_ROW")
		var row := Dictionary(row_value)
		var container := ContainerStateScript.new(row)
		if container.container_id.is_empty():
			return _failure("CONTAINER_ID_REQUIRED")
		if next_containers.has(container.container_id):
			return _failure("DUPLICATE_CONTAINER_ID", {"container_id": container.container_id})
		if container.storage_mode == ContainerStateScript.STORAGE_SLOTS:
			if container.slot_count <= 0:
				return _failure("INVALID_SLOT_COUNT", {"container_id": container.container_id})
			for slot_key in container.slot_assignments.keys():
				var slot_index := int(slot_key)
				if slot_index < 0 or slot_index >= container.slot_count:
					return _failure("INVALID_SLOT_ASSIGNMENT", {"container_id": container.container_id})
				var item_id := String(container.slot_assignments[slot_key])
				if not container.item_ids.has(item_id):
					return _failure("SLOT_MEMBER_MISSING", {"container_id": container.container_id, "item_id": item_id})
		if container.revision < 0:
			return _failure("INVALID_CONTAINER_REVISION", {"container_id": container.container_id})
		next_containers[container.container_id] = container
	containers = next_containers
	return {"success": true, "schema_version": SCHEMA_VERSION}


func replace_from(other_registry) -> void:
	containers = other_registry.containers.duplicate()


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
