extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")

const SCHEMA := "distributed_world_simulator.sm0_p7_1_canonical_transfer.v1"
const PHASE_PREPARE := "PREPARE"
const PHASE_PREPARED := "PREPARED"
const PHASE_COMMIT := "COMMIT"
const PHASE_COMMITTED := "COMMITTED"
const PHASES: Array[String] = [PHASE_PREPARE, PHASE_PREPARED, PHASE_COMMIT, PHASE_COMMITTED]

const REQUIRED_FIELDS: Array[String] = [
	"schema", "route_id", "transfer_id", "phase",
	"route_source_authority_id", "route_destination_authority_id",
	"route_path", "hop_index",
	"transfer_source_authority_id", "transfer_target_authority_id",
	"source_epoch", "target_epoch",
	"player_package", "package_hash", "retire_proof",
	"success", "error_code", "checksum",
]

const PACKAGE_FIELDS: Array[String] = [
	"logical_player_id", "player_entity_id", "state_revision", "last_input_sequence",
	"position", "velocity", "orientation_yaw",
]


static func create(
	route_id: String,
	transfer_id: String,
	phase: String,
	transfer_source_authority_id: String,
	transfer_target_authority_id: String,
	source_epoch: int,
	target_epoch: int,
	player_package: Dictionary,
	retire_proof: String = "",
	success: bool = true,
	error_code: String = ""
) -> Dictionary:
	var route_source := transfer_source_authority_id if phase in [PHASE_PREPARE, PHASE_COMMIT] else transfer_target_authority_id
	var route_destination := transfer_target_authority_id if phase in [PHASE_PREPARE, PHASE_COMMIT] else transfer_source_authority_id
	var package := _canonical_package(player_package)
	var package_hash := Utils.payload_hash(package)
	var result := {
		"schema": SCHEMA,
		"route_id": route_id,
		"transfer_id": transfer_id,
		"phase": phase,
		"route_source_authority_id": route_source,
		"route_destination_authority_id": route_destination,
		"route_path": Topology.plan_route(route_source, route_destination),
		"hop_index": 0,
		"transfer_source_authority_id": transfer_source_authority_id,
		"transfer_target_authority_id": transfer_target_authority_id,
		"source_epoch": source_epoch,
		"target_epoch": target_epoch,
		"player_package": package,
		"package_hash": package_hash,
		"retire_proof": retire_proof,
		"success": success,
		"error_code": error_code,
		"checksum": "",
	}
	return _finalize(result)


static func advance(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result["hop_index"] = int(value.get("hop_index", -1)) + 1
	return _finalize(result)


static func validate(value: Dictionary) -> Dictionary:
	var fields := Utils.validate_exact_fields(value, REQUIRED_FIELDS)
	if not bool(fields.get("success", false)):
		return _failure("SM0_P7_1_TRANSFER_FIELDS_INVALID", {"cause": fields})
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("SM0_P7_1_TRANSFER_SCHEMA_INVALID")
	var route_id := String(value.get("route_id", "")).strip_edges()
	var transfer_id := String(value.get("transfer_id", "")).strip_edges()
	var phase := String(value.get("phase", ""))
	if route_id.is_empty() or transfer_id.is_empty():
		return _failure("SM0_P7_1_TRANSFER_ID_REQUIRED")
	if phase not in PHASES:
		return _failure("SM0_P7_1_TRANSFER_PHASE_INVALID")
	var transfer_source := String(value.get("transfer_source_authority_id", ""))
	var transfer_target := String(value.get("transfer_target_authority_id", ""))
	if transfer_source not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C] or transfer_target not in [Topology.AUTHORITY_A, Topology.AUTHORITY_C] or transfer_source == transfer_target:
		return _failure("SM0_P7_1_TRANSFER_ENDPOINT_INVALID")
	var expected_route_source := transfer_source if phase in [PHASE_PREPARE, PHASE_COMMIT] else transfer_target
	var expected_route_destination := transfer_target if phase in [PHASE_PREPARE, PHASE_COMMIT] else transfer_source
	if String(value.get("route_source_authority_id", "")) != expected_route_source or String(value.get("route_destination_authority_id", "")) != expected_route_destination:
		return _failure("SM0_P7_1_TRANSFER_ROUTE_DIRECTION_INVALID")
	var route_path: Array = Array(value.get("route_path", []))
	var route_check := Topology.validate_route(route_path, expected_route_source, expected_route_destination)
	if not bool(route_check.get("success", false)):
		return route_check
	if not Utils.is_json_integer(value.get("hop_index")):
		return _failure("SM0_P7_1_TRANSFER_HOP_INDEX_INVALID")
	var hop_index := int(value.get("hop_index", -1))
	if hop_index < 0 or hop_index >= route_path.size():
		return _failure("SM0_P7_1_TRANSFER_HOP_INDEX_INVALID")
	if not Utils.is_json_integer(value.get("source_epoch")) or not Utils.is_json_integer(value.get("target_epoch")):
		return _failure("SM0_P7_1_TRANSFER_EPOCH_INVALID")
	var source_epoch := int(value.get("source_epoch", 0))
	var target_epoch := int(value.get("target_epoch", 0))
	if source_epoch < 1 or target_epoch != source_epoch + 1:
		return _failure("SM0_P7_1_TRANSFER_EPOCH_INVALID")
	if not value.get("player_package") is Dictionary:
		return _failure("SM0_P7_1_TRANSFER_PACKAGE_INVALID")
	var package: Dictionary = Dictionary(value.get("player_package", {}))
	var package_check := validate_player_package(package)
	if not bool(package_check.get("success", false)):
		return package_check
	var package_hash := String(value.get("package_hash", ""))
	if package_hash.is_empty() or package_hash != Utils.payload_hash(_canonical_package(package)):
		return _failure("SM0_P7_1_TRANSFER_PACKAGE_HASH_MISMATCH")
	if typeof(value.get("success")) != TYPE_BOOL or typeof(value.get("error_code")) != TYPE_STRING:
		return _failure("SM0_P7_1_TRANSFER_RESULT_INVALID")
	if bool(value.get("success", false)) and not String(value.get("error_code", "")).is_empty():
		return _failure("SM0_P7_1_TRANSFER_RESULT_INVALID")
	var retire_proof := String(value.get("retire_proof", ""))
	if phase in [PHASE_COMMIT, PHASE_COMMITTED]:
		if retire_proof != create_retire_proof(transfer_id, package_hash, source_epoch, target_epoch):
			return _failure("SM0_P7_1_RETIRE_PROOF_INVALID")
	elif not retire_proof.is_empty():
		return _failure("SM0_P7_1_RETIRE_PROOF_PREMATURE")
	var checksum := String(value.get("checksum", ""))
	if checksum.is_empty() or checksum != Utils.payload_hash(_checksum_payload(value)):
		return _failure("SM0_P7_1_TRANSFER_CHECKSUM_MISMATCH")
	return _success()


static func validate_player_package(package: Dictionary) -> Dictionary:
	var fields := Utils.validate_exact_fields(package, PACKAGE_FIELDS)
	if not bool(fields.get("success", false)):
		return _failure("SM0_P7_1_TRANSFER_PACKAGE_FIELDS_INVALID", {"cause": fields})
	if String(package.get("logical_player_id", "")) != "a" or String(package.get("player_entity_id", "")) != "player/a":
		return _failure("SM0_P7_1_TRANSFER_PLAYER_IDENTITY_INVALID")
	if not Utils.is_json_integer(package.get("state_revision")) or int(package.get("state_revision", 0)) < 1:
		return _failure("SM0_P7_1_TRANSFER_STATE_REVISION_INVALID")
	if not Utils.is_json_integer(package.get("last_input_sequence")) or int(package.get("last_input_sequence", -1)) < 0:
		return _failure("SM0_P7_1_TRANSFER_INPUT_SEQUENCE_INVALID")
	for field in ["position", "velocity"]:
		if not package.get(field) is Dictionary:
			return _failure("SM0_P7_1_TRANSFER_SPATIAL_STATE_INVALID")
		var vector: Dictionary = Dictionary(package.get(field, {}))
		for axis in ["x", "y", "z"]:
			if typeof(vector.get(axis)) not in [TYPE_INT, TYPE_FLOAT]:
				return _failure("SM0_P7_1_TRANSFER_SPATIAL_STATE_INVALID")
	if typeof(package.get("orientation_yaw")) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("SM0_P7_1_TRANSFER_ORIENTATION_INVALID")
	return _success()


static func current_authority(value: Dictionary) -> String:
	var route_path: Array = Array(value.get("route_path", []))
	var index := int(value.get("hop_index", -1))
	return String(route_path[index]) if index >= 0 and index < route_path.size() else ""


static func previous_authority(value: Dictionary) -> String:
	var route_path: Array = Array(value.get("route_path", []))
	var index := int(value.get("hop_index", -1))
	return String(route_path[index - 1]) if index > 0 and index < route_path.size() else ""


static func next_authority(value: Dictionary) -> String:
	var route_path: Array = Array(value.get("route_path", []))
	var index := int(value.get("hop_index", -1))
	return String(route_path[index + 1]) if index >= 0 and index + 1 < route_path.size() else ""


static func immutable_fingerprint(value: Dictionary) -> String:
	return Utils.payload_hash({
		"route_id": String(value.get("route_id", "")),
		"transfer_id": String(value.get("transfer_id", "")),
		"phase": String(value.get("phase", "")),
		"route_source_authority_id": String(value.get("route_source_authority_id", "")),
		"route_destination_authority_id": String(value.get("route_destination_authority_id", "")),
		"route_path": Array(value.get("route_path", [])).duplicate(true),
		"transfer_source_authority_id": String(value.get("transfer_source_authority_id", "")),
		"transfer_target_authority_id": String(value.get("transfer_target_authority_id", "")),
		"source_epoch": int(value.get("source_epoch", 0)),
		"target_epoch": int(value.get("target_epoch", 0)),
		"package_hash": String(value.get("package_hash", "")),
		"retire_proof": String(value.get("retire_proof", "")),
		"success": bool(value.get("success", false)),
		"error_code": String(value.get("error_code", "")),
	})


static func create_retire_proof(transfer_id: String, package_hash: String, source_epoch: int, target_epoch: int) -> String:
	return ("%s|%s|%d|%d|SOURCE_RETIRED" % [transfer_id, package_hash, source_epoch, target_epoch]).sha256_text()


static func _canonical_package(package: Dictionary) -> Dictionary:
	var position: Dictionary = Dictionary(package.get("position", {}))
	var velocity: Dictionary = Dictionary(package.get("velocity", {}))
	return {
		"logical_player_id": String(package.get("logical_player_id", "")),
		"player_entity_id": String(package.get("player_entity_id", "")),
		"state_revision": int(package.get("state_revision", 0)),
		"last_input_sequence": int(package.get("last_input_sequence", 0)),
		"position": {
			"x": float(position.get("x", 0.0)), "y": float(position.get("y", 0.0)), "z": float(position.get("z", 0.0)),
		},
		"velocity": {
			"x": float(velocity.get("x", 0.0)), "y": float(velocity.get("y", 0.0)), "z": float(velocity.get("z", 0.0)),
		},
		"orientation_yaw": float(package.get("orientation_yaw", 0.0)),
	}


static func _checksum_payload(value: Dictionary) -> Dictionary:
	var route_path: Array[String] = []
	for item in Array(value.get("route_path", [])):
		route_path.append(String(item))
	return {
		"schema": String(value.get("schema", "")),
		"route_id": String(value.get("route_id", "")),
		"transfer_id": String(value.get("transfer_id", "")),
		"phase": String(value.get("phase", "")),
		"route_source_authority_id": String(value.get("route_source_authority_id", "")),
		"route_destination_authority_id": String(value.get("route_destination_authority_id", "")),
		"route_path": route_path,
		"hop_index": int(value.get("hop_index", -1)),
		"transfer_source_authority_id": String(value.get("transfer_source_authority_id", "")),
		"transfer_target_authority_id": String(value.get("transfer_target_authority_id", "")),
		"source_epoch": int(value.get("source_epoch", 0)),
		"target_epoch": int(value.get("target_epoch", 0)),
		"player_package": _canonical_package(Dictionary(value.get("player_package", {}))),
		"package_hash": String(value.get("package_hash", "")),
		"retire_proof": String(value.get("retire_proof", "")),
		"success": bool(value.get("success", false)),
		"error_code": String(value.get("error_code", "")),
	}


static func _finalize(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result["checksum"] = Utils.payload_hash(_checksum_payload(result))
	return result


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}