extends RefCounted

const Relations = preload("res://scripts/items/domain/item_relations.gd")

var transfer_service
var item_registry
var sockets: Dictionary = {}


func setup(new_transfer_service, new_item_registry) -> void:
	transfer_service = new_transfer_service
	item_registry = new_item_registry


func register_socket(assembly_id: String, parent_item_id: String, socket_id: String, accepted_tags: Array[String]) -> void:
	sockets[_key(assembly_id, socket_id)] = {
		"assembly_id": assembly_id,
		"parent_item_id": parent_item_id,
		"socket_id": socket_id,
		"accepted_tags": accepted_tags.duplicate(),
		"item_id": "",
	}


func attach(item_id: String, assembly_id: String, socket_id: String, operation_id: String) -> Dictionary:
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
	var result := transfer_service.move_item(
		item_id,
		Relations.attachment(assembly_id, String(socket.parent_item_id), socket_id),
		operation_id
	)
	if bool(result.get("success", false)):
		socket.item_id = item_id
	return result


func detach_to_container(item_id: String, container_id: String, operation_id: String) -> Dictionary:
	var item = item_registry.get_item(item_id)
	if item == null or Relations.kind_of(item.relation) != Relations.ATTACHMENT:
		return {"success": false, "error_code": "ITEM_NOT_ATTACHED"}
	var assembly_id := String(item.relation.get("assembly_id", ""))
	var socket_id := String(item.relation.get("socket_id", ""))
	var result := transfer_service.move_item(item_id, Relations.container(container_id), operation_id)
	if bool(result.get("success", false)):
		var socket = sockets.get(_key(assembly_id, socket_id))
		if socket != null:
			socket.item_id = ""
	return result


func detach_to_world(item_id: String, transform: Transform3D, velocity: Vector3, operation_id: String) -> Dictionary:
	var item = item_registry.get_item(item_id)
	if item == null or Relations.kind_of(item.relation) != Relations.ATTACHMENT:
		return {"success": false, "error_code": "ITEM_NOT_ATTACHED"}
	var assembly_id := String(item.relation.get("assembly_id", ""))
	var socket_id := String(item.relation.get("socket_id", ""))
	var result := transfer_service.move_item(item_id, Relations.world(transform, velocity), operation_id)
	if bool(result.get("success", false)):
		var socket = sockets.get(_key(assembly_id, socket_id))
		if socket != null:
			socket.item_id = ""
	return result


func _key(assembly_id: String, socket_id: String) -> String:
	return assembly_id + "::" + socket_id
