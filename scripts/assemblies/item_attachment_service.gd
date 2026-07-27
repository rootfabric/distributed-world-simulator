extends RefCounted

const Relations = preload("res://scripts/items/domain/item_relations.gd")

const SCHEMA: String = "planet_simulator.item_attachments.v1"
const SCHEMA_VERSION: int = 1

var transfer_service
var item_registry
var sockets: Dictionary = {}


func setup(new_transfer_service, new_item_registry) -> void:
	transfer_service = new_transfer_service
	item_registry = new_item_registry
	if not transfer_service.relation_changed.is_connected(_on_relation_changed):
		transfer_service.relation_changed.connect(_on_relation_changed)


func register_socket(assembly_id: String, parent_item_id: String, socket_id: String, accepted_tags: Array) -> void:
	var normalized_tags: Array[String] = []
	for tag in accepted_tags:
		normalized_tags.append(String(tag))
	sockets[_key(assembly_id, socket_id)] = {
		"assembly_id": assembly_id,
		"parent_item_id": parent_item_id,
		"socket_id": socket_id,
		"accepted_tags": normalized_tags,
		"item_id": "",
	}


func ensure_socket(assembly_id: String, parent_item_id: String, socket_id: String, accepted_tags: Array) -> Dictionary:
	var key := _key(assembly_id, socket_id)
	var existing = sockets.get(key)
	if existing != null:
		# Rebinding a persisted socket must not clear the item already mounted in it.
		existing["parent_item_id"] = parent_item_id
		var normalized_existing: Array[String] = []
		for tag in accepted_tags:
			normalized_existing.append(String(tag))
		existing["accepted_tags"] = normalized_existing
		return Dictionary(existing).duplicate(true)
	register_socket(assembly_id, parent_item_id, socket_id, accepted_tags)
	return get_socket_state(assembly_id, socket_id)


func attach(item_id: String, assembly_id: String, socket_id: String, operation_id: String, expected_revision: int = -1) -> Dictionary:
	var socket = sockets.get(_key(assembly_id, socket_id))
	if socket == null:
		return {"success": false, "error_code": "SOCKET_NOT_FOUND"}
	if not String(socket.item_id).is_empty():
		return {"success": false, "error_code": "SOCKET_OCCUPIED"}
	var item = item_registry.get_item(item_id)
	if item == null:
		return {"success": false, "error_code": "ITEM_NOT_FOUND"}
	var definition = item_registry.get_definition(item.definition_id)
	var accepted_tags: Array = socket.accepted_tags
	if not accepted_tags.is_empty():
		var accepted := false
		for tag in accepted_tags:
			if definition.has_tag(String(tag)):
				accepted = true
				break
		if not accepted:
			return {"success": false, "error_code": "SOCKET_TAG_REJECTED"}
	var result: Dictionary = transfer_service.move_item(
		item_id,
		Relations.attachment(assembly_id, String(socket.parent_item_id), socket_id),
		operation_id,
		expected_revision
	)
	if bool(result.get("success", false)):
		socket.item_id = String(result.get("result_item_id", item_id))
	return result


func detach_to_container(item_id: String, container_id: String, operation_id: String, expected_revision: int = -1) -> Dictionary:
	var item = item_registry.get_item(item_id)
	if item == null or Relations.kind_of(item.relation) != Relations.ATTACHMENT:
		return {"success": false, "error_code": "ITEM_NOT_ATTACHED"}
	var assembly_id := String(item.relation.get("assembly_id", ""))
	var socket_id := String(item.relation.get("socket_id", ""))
	var result: Dictionary = transfer_service.move_item(item_id, Relations.container(container_id), operation_id, expected_revision)
	if bool(result.get("success", false)):
		var socket = sockets.get(_key(assembly_id, socket_id))
		if socket != null:
			socket.item_id = ""
	return result


func detach_to_world(item_id: String, transform: Transform3D, velocity: Vector3, operation_id: String, expected_revision: int = -1) -> Dictionary:
	var item = item_registry.get_item(item_id)
	if item == null or Relations.kind_of(item.relation) != Relations.ATTACHMENT:
		return {"success": false, "error_code": "ITEM_NOT_ATTACHED"}
	var assembly_id := String(item.relation.get("assembly_id", ""))
	var socket_id := String(item.relation.get("socket_id", ""))
	var result: Dictionary = transfer_service.move_item(item_id, Relations.world(transform, velocity), operation_id, expected_revision)
	if bool(result.get("success", false)):
		var socket = sockets.get(_key(assembly_id, socket_id))
		if socket != null:
			socket.item_id = ""
	return result


func get_socket_state(assembly_id: String, socket_id: String) -> Dictionary:
	var socket = sockets.get(_key(assembly_id, socket_id))
	return {} if socket == null else Dictionary(socket).duplicate(true)


func all_socket_states() -> Array:
	var result: Array = []
	var keys := sockets.keys()
	keys.sort()
	for socket_key in keys:
		result.append(Dictionary(sockets[socket_key]).duplicate(true))
	return result


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"sockets": all_socket_states(),
	}


func load_dict(data: Dictionary) -> Dictionary:
	if String(data.get("schema", "")) != SCHEMA:
		return _failure("UNSUPPORTED_ATTACHMENT_SCHEMA")
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		return _failure("UNSUPPORTED_ATTACHMENT_VERSION")
	var rows = data.get("sockets", [])
	if not rows is Array:
		return _failure("INVALID_ATTACHMENT_ROWS")
	var next_sockets: Dictionary = {}
	for row_value in rows:
		if not row_value is Dictionary:
			return _failure("INVALID_ATTACHMENT_ROW")
		var row := Dictionary(row_value)
		var assembly_id := String(row.get("assembly_id", ""))
		var parent_item_id := String(row.get("parent_item_id", ""))
		var socket_id := String(row.get("socket_id", ""))
		if assembly_id.is_empty() or parent_item_id.is_empty() or socket_id.is_empty():
			return _failure("INVALID_ATTACHMENT_IDENTITY")
		if item_registry.get_item(parent_item_id) == null:
			return _failure("ATTACHMENT_PARENT_NOT_FOUND", {"parent_item_id": parent_item_id})
		var key := _key(assembly_id, socket_id)
		if next_sockets.has(key):
			return _failure("DUPLICATE_ATTACHMENT_SOCKET", {"socket": key})
		var accepted: Array[String] = []
		for tag in row.get("accepted_tags", []):
			accepted.append(String(tag))
		var item_id := String(row.get("item_id", ""))
		if not item_id.is_empty():
			var item = item_registry.get_item(item_id)
			if item == null:
				return _failure("ATTACHED_ITEM_NOT_FOUND", {"item_id": item_id})
			if Relations.kind_of(item.relation) != Relations.ATTACHMENT:
				return _failure("ATTACHED_ITEM_RELATION_MISMATCH", {"item_id": item_id})
			if String(item.relation.get("assembly_id", "")) != assembly_id or String(item.relation.get("socket_id", "")) != socket_id:
				return _failure("ATTACHED_ITEM_SOCKET_MISMATCH", {"item_id": item_id})
		next_sockets[key] = {
			"assembly_id": assembly_id,
			"parent_item_id": parent_item_id,
			"socket_id": socket_id,
			"accepted_tags": accepted,
			"item_id": item_id,
		}
	sockets = next_sockets
	return {"success": true, "socket_count": sockets.size()}


func replace_from(other_service) -> void:
	sockets = other_service.sockets.duplicate(true)


func _key(assembly_id: String, socket_id: String) -> String:
	return assembly_id + "::" + socket_id


func _on_relation_changed(item_id: String, old_relation: Dictionary, new_relation: Dictionary) -> void:
	if Relations.kind_of(old_relation) == Relations.ATTACHMENT:
		var old_socket = sockets.get(_key(String(old_relation.get("assembly_id", "")), String(old_relation.get("socket_id", ""))))
		if old_socket != null and String(old_socket.get("item_id", "")) == item_id:
			old_socket["item_id"] = ""
	if Relations.kind_of(new_relation) == Relations.ATTACHMENT:
		var new_socket = sockets.get(_key(String(new_relation.get("assembly_id", "")), String(new_relation.get("socket_id", ""))))
		if new_socket != null:
			new_socket["item_id"] = item_id


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
