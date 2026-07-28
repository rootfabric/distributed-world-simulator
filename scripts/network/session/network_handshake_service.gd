extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const HandshakeScript = preload("res://scripts/network/contracts/network_handshake_envelope.gd")
const ResultScript = preload("res://scripts/network/contracts/network_handshake_result_envelope.gd")

const SCHEMA: String = "planet_simulator.network_handshake_service.v1"
const REQUIRED_CONFIG_FIELDS: Array[String] = [
	"server_node_id", "checkpoint", "build_id", "authority_owner_id", "authority_epoch",
	"server_tick", "required_capabilities", "contract_versions",
]

var _config: Dictionary = {}


func configure(config: Dictionary) -> Dictionary:
	if config.size() != REQUIRED_CONFIG_FIELDS.size():
		return _failure("INVALID_SERVICE_CONFIG")
	for field in REQUIRED_CONFIG_FIELDS:
		if not config.has(field):
			return _failure("INVALID_SERVICE_CONFIG")
	for field in ["server_node_id", "checkpoint", "build_id", "authority_owner_id"]:
		if typeof(config[field]) != TYPE_STRING or String(config[field]).strip_edges().is_empty():
			return _failure("INVALID_SERVICE_CONFIG")
	for field in ["authority_epoch", "server_tick"]:
		if not UtilsScript.is_json_integer(config[field]) or int(config[field]) < 0:
			return _failure("INVALID_SERVICE_CONFIG")
	if not config["required_capabilities"] is Array or not config["contract_versions"] is Dictionary:
		return _failure("INVALID_SERVICE_CONFIG")
	var required_capabilities: Array[String] = []
	for item in config["required_capabilities"]:
		if typeof(item) != TYPE_STRING:
			return _failure("INVALID_SERVICE_CONFIG")
		var capability: String = String(item)
		if capability.is_empty() or capability != capability.strip_edges().to_lower() or not _is_identifier(capability) or required_capabilities.has(capability):
			return _failure("INVALID_SERVICE_CONFIG")
		required_capabilities.append(capability)
	required_capabilities.sort()
	if required_capabilities.is_empty():
		return _failure("INVALID_SERVICE_CONFIG")
	for contract_name in config["contract_versions"].keys():
		if typeof(contract_name) != TYPE_STRING:
			return _failure("INVALID_SERVICE_CONFIG")
		var contract_id: String = String(contract_name)
		if contract_id.is_empty() or contract_id != contract_id.strip_edges().to_lower() or not _is_identifier(contract_id):
			return _failure("INVALID_SERVICE_CONFIG")
		if not UtilsScript.is_json_integer(config["contract_versions"][contract_name]) or int(config["contract_versions"][contract_name]) <= 0:
			return _failure("INVALID_SERVICE_CONFIG")
	if config["contract_versions"].is_empty():
		return _failure("INVALID_SERVICE_CONFIG")
	_config = config.duplicate(true)
	_config["required_capabilities"] = required_capabilities
	return _success()


func evaluate(handshake: Dictionary, peer_id: int = 0) -> Dictionary:
	if _config.is_empty():
		return _failure("SERVICE_NOT_CONFIGURED")
	var handshake_id: String = String(handshake.get("handshake_id", "handshake/rejected"))
	if handshake_id.strip_edges().is_empty():
		handshake_id = "handshake/rejected"
	var validation: Dictionary = HandshakeScript.validate(handshake)
	if not bool(validation.get("success", false)):
		return _accepted_result(false, handshake_id, "", String(validation.get("error_code", "INVALID_HANDSHAKE")))
	var client_capabilities: Array = handshake["capabilities"]
	for capability in _config["required_capabilities"]:
		if not client_capabilities.has(capability):
			return _accepted_result(false, handshake_id, "", "MISSING_CAPABILITY")
	var client_versions: Dictionary = handshake["contract_versions"]
	for contract_name in _config["contract_versions"].keys():
		if not client_versions.has(contract_name):
			return _accepted_result(false, handshake_id, "", "MISSING_CONTRACT_VERSION")
		if int(client_versions[contract_name]) != int(_config["contract_versions"][contract_name]):
			return _accepted_result(false, handshake_id, "", "UNSUPPORTED_CONTRACT_VERSION")
	var session_id: String = _create_session_id(handshake, peer_id)
	return _accepted_result(true, handshake_id, session_id, "")


func get_snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": not _config.is_empty(),
		"config": _config.duplicate(true),
	}


func _accepted_result(accepted: bool, handshake_id: String, session_id: String, error_code: String) -> Dictionary:
	var result: Dictionary = ResultScript.create(
		handshake_id,
		accepted,
		session_id,
		String(_config["server_node_id"]),
		String(_config["checkpoint"]),
		String(_config["build_id"]),
		String(_config["authority_owner_id"]),
		int(_config["authority_epoch"]),
		int(_config["server_tick"]),
		_config["required_capabilities"],
		_config["contract_versions"],
		error_code
	)
	return _success({"result": result})


func _create_session_id(handshake: Dictionary, peer_id: int) -> String:
	var seed: Dictionary = {
		"handshake_id": String(handshake["handshake_id"]),
		"client_node_id": String(handshake["client_node_id"]),
		"server_node_id": String(_config["server_node_id"]),
		"peer_id": peer_id,
		"process_id": OS.get_process_id(),
		"ticks_usec": Time.get_ticks_usec(),
	}
	return "session/%s" % UtilsScript.payload_hash(seed).substr(0, 32)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}


func _is_identifier(value: String) -> bool:
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["_", ".", "-"]):
			return false
	return true
