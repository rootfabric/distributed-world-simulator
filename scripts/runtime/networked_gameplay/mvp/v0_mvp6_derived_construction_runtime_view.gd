extends Node

const RequestScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const SynchronizerScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_synchronizer.gd")

var _client_id: String = ""
var _synchronizer
var _last_construct_id: String = ""
var _last_source_checksum: String = ""
var _last_descriptor_checksum: String = ""


func _init() -> void:
	_synchronizer = SynchronizerScript.new()
	_synchronizer.name = "CanonicalConstructionRuntimeProjection"
	add_child(_synchronizer)


func setup(client_id: String) -> Dictionary:
	var normalized := client_id.strip_edges()
	if normalized.is_empty() or normalized != client_id or not normalized.begins_with("client/"):
		return _failure("MVP6_DERIVED_CONSTRUCTION_CLIENT_ID_INVALID")
	_client_id = normalized
	return _success({"client_id": _client_id, "direct_authority_references": 0})


func apply_snapshot(
	construct_snapshot: Dictionary,
	item_projections: Array = [],
	world_origin_m: Array = [0.0, 0.0, 0.0],
	world_rotation_quaternion: Array = [0.0, 0.0, 0.0, 1.0],
	collision_layer: int = 1,
	collision_mask: int = 1
) -> Dictionary:
	if _client_id.is_empty():
		return _failure("MVP6_DERIVED_CONSTRUCTION_VIEW_NOT_CONFIGURED")
	var request := RequestScript.create(
		construct_snapshot,
		item_projections,
		{},
		{},
		world_origin_m,
		world_rotation_quaternion,
		collision_layer,
		collision_mask
	)
	var checked: Dictionary = RequestScript.validate(request)
	if not bool(checked.get("success", false)):
		return checked
	var applied: Dictionary = _synchronizer.upsert(request)
	if not bool(applied.get("success", false)):
		return applied
	var construct_id := String(construct_snapshot.get("construct_id", ""))
	var descriptor: Dictionary = _synchronizer.get_descriptor(construct_id)
	var node = _synchronizer.get_construct_node(construct_id)
	if descriptor.is_empty() or node == null or not is_instance_valid(node):
		return _failure("MVP6_DERIVED_CONSTRUCTION_RUNTIME_NODE_MISSING")
	_last_construct_id = construct_id
	_last_source_checksum = String(construct_snapshot.get("checksum", ""))
	_last_descriptor_checksum = String(descriptor.get("checksum", ""))
	var colliding_parts := 0
	for part in descriptor.get("part_descriptors", []):
		if part is Dictionary and bool(part.get("collision_enabled", false)):
			colliding_parts += 1
	return _success({
		"client_id": _client_id,
		"construct_id": construct_id,
		"construct_checksum": _last_source_checksum,
		"descriptor_checksum": _last_descriptor_checksum,
		"construct_revision": int(descriptor.get("construct_revision", -1)),
		"part_count": Array(descriptor.get("part_descriptors", [])).size(),
		"collision_part_count": colliding_parts,
		"body_kind": String(descriptor.get("body_kind", "")),
		"replay": bool(applied.get("replay", false)),
		"direct_authority_references": 0,
		"canonical_truth_owner": false,
	})


func get_construct_node(construct_id: String = ""):
	var resolved := construct_id if not construct_id.is_empty() else _last_construct_id
	return _synchronizer.get_construct_node(resolved) if not resolved.is_empty() else null


func get_descriptor(construct_id: String = "") -> Dictionary:
	var resolved := construct_id if not construct_id.is_empty() else _last_construct_id
	return _synchronizer.get_descriptor(resolved) if not resolved.is_empty() else {}


func get_report() -> Dictionary:
	return {
		"client_id": _client_id,
		"construct_id": _last_construct_id,
		"source_checksum": _last_source_checksum,
		"descriptor_checksum": _last_descriptor_checksum,
		"construct_count": _synchronizer.get_construct_count(),
		"world_checksum": _synchronizer.get_world_checksum(),
		"presentation_generation": _synchronizer.get_presentation_generation(),
		"direct_authority_references": 0,
		"canonical_truth_owner": false,
	}


static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
