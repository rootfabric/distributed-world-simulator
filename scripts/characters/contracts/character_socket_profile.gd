class_name CharacterSocketProfile
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const SCHEMA := "planet_simulator.character_socket_profile.v1"
const REQUIRED_SOCKETS := ["head", "hand_left", "hand_right"]

var socket_profile_id := ""
var socket_paths: Dictionary = {}

func setup(data: Dictionary) -> Dictionary:
	if not Utils.is_json_safe(data):
		return Utils.failure("SOCKET_PROFILE_NOT_JSON_SAFE")
	socket_profile_id = Utils.normalized_id(data.get("socket_profile_id", ""))
	socket_paths.clear()
	var raw_paths = data.get("socket_paths", {})
	if not raw_paths is Dictionary:
		return Utils.failure("INVALID_SOCKET_PATH_MAP")
	for socket_value in raw_paths:
		var socket_id := Utils.normalized_id(socket_value)
		var path := String(raw_paths[socket_value]).strip_edges()
		if not Utils.is_valid_id(socket_id) or path.is_empty() or path.length() > 240 or path.begins_with("/"):
			return Utils.failure("INVALID_SOCKET_PATH", {"socket_id": socket_id})
		socket_paths[socket_id] = path
	return validate()

func validate() -> Dictionary:
	if not Utils.is_valid_id(socket_profile_id):
		return Utils.failure("INVALID_SOCKET_PROFILE_ID")
	for socket_id in REQUIRED_SOCKETS:
		if not socket_paths.has(socket_id):
			return Utils.failure("MISSING_REQUIRED_SOCKET", {"socket_id": socket_id})
	return Utils.success()

func resolve_path(socket_id: StringName) -> NodePath:
	return NodePath(String(socket_paths.get(Utils.normalized_id(socket_id), "")))

func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "socket_profile_id": socket_profile_id, "socket_paths": socket_paths.duplicate(true)}
