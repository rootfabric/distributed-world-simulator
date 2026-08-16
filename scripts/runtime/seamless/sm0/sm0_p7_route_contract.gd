extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")

const SCHEMA := "distributed_world_simulator.sm0_p7_route_envelope.v1"
const KIND_PLAYER_ROUTE_PROBE := "PLAYER_ROUTE_PROBE"

const REQUIRED_FIELDS: Array[String] = [
	"schema", "route_id", "kind", "source_authority_id", "destination_authority_id",
	"route_path", "hop_index", "authority_epoch", "payload", "payload_hash", "checksum",
]


static func create_probe(route_id: String, source_authority_id: String, destination_authority_id: String, authority_epoch: int, payload: Dictionary) -> Dictionary:
	var route_path := Topology.plan_route(source_authority_id, destination_authority_id)
	var canonical_payload := _canonical_payload(payload)
	return _finalize({
		"schema": SCHEMA,
		"route_id": route_id,
		"kind": KIND_PLAYER_ROUTE_PROBE,
		"source_authority_id": source_authority_id,
		"destination_authority_id": destination_authority_id,
		"route_path": route_path,
		"hop_index": 0,
		"authority_epoch": authority_epoch,
		"payload": canonical_payload,
		"payload_hash": _payload_hash(canonical_payload),
		"checksum": "",
	})


static func advance(value: Dictionary) -> Dictionary:
	var next := value.duplicate(true)
	next["hop_index"] = int(value.get("hop_index", -1)) + 1
	return _finalize(next)


static func validate(value: Dictionary) -> Dictionary:
	var fields := Utils.validate_exact_fields(value, REQUIRED_FIELDS)
	if not bool(fields.get("success", false)):
		return _failure("SM0_P7_ROUTE_FIELDS_INVALID", {"cause": fields})
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("SM0_P7_ROUTE_SCHEMA_INVALID")
	if String(value.get("route_id", "")).strip_edges().is_empty():
		return _failure("SM0_P7_ROUTE_ID_REQUIRED")
	if String(value.get("kind", "")) != KIND_PLAYER_ROUTE_PROBE:
		return _failure("SM0_P7_ROUTE_KIND_INVALID")
	var source := String(value.get("source_authority_id", ""))
	var destination := String(value.get("destination_authority_id", ""))
	var route_path: Array = Array(value.get("route_path", []))
	var route_check := Topology.validate_route(route_path, source, destination)
	if not bool(route_check.get("success", false)):
		return route_check
	if not Utils.is_json_integer(value.get("hop_index")):
		return _failure("SM0_P7_ROUTE_HOP_INDEX_INVALID")
	var hop_index := int(value.get("hop_index", -1))
	if hop_index < 0 or hop_index >= route_path.size():
		return _failure("SM0_P7_ROUTE_HOP_INDEX_INVALID")
	if not Utils.is_json_integer(value.get("authority_epoch")) or int(value.get("authority_epoch", 0)) < 1:
		return _failure("SM0_P7_ROUTE_AUTHORITY_EPOCH_INVALID")
	if not value.get("payload") is Dictionary:
		return _failure("SM0_P7_ROUTE_PAYLOAD_INVALID")
	var payload: Dictionary = Dictionary(value.get("payload", {}))
	if String(payload.get("logical_player_id", "")) != "a" or String(payload.get("player_entity_id", "")) != "player/a":
		return _failure("SM0_P7_ROUTE_PLAYER_IDENTITY_INVALID")
	if not Utils.is_json_integer(payload.get("state_revision")) or int(payload.get("state_revision", 0)) < 1:
		return _failure("SM0_P7_ROUTE_STATE_REVISION_INVALID")
	if not payload.get("position") is Dictionary:
		return _failure("SM0_P7_ROUTE_POSITION_INVALID")
	for axis in ["x", "y", "z"]:
		if typeof(Dictionary(payload.get("position", {})).get(axis)) not in [TYPE_INT, TYPE_FLOAT]:
			return _failure("SM0_P7_ROUTE_POSITION_INVALID")
	var payload_hash := String(value.get("payload_hash", ""))
	if payload_hash.is_empty() or payload_hash != _payload_hash(payload):
		return _failure("SM0_P7_ROUTE_PAYLOAD_HASH_MISMATCH")
	var expected_checksum := String(value.get("checksum", ""))
	if expected_checksum.is_empty() or expected_checksum != Utils.payload_hash(_checksum_payload(value)):
		return _failure("SM0_P7_ROUTE_CHECKSUM_MISMATCH")
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
	return "%s|%s|%s|%s|%d|%s" % [
		String(value.get("kind", "")),
		String(value.get("source_authority_id", "")),
		String(value.get("destination_authority_id", "")),
		JSON.stringify(Array(value.get("route_path", [])), "", false, true),
		int(value.get("authority_epoch", 0)),
		String(value.get("payload_hash", "")),
	]


static func _canonical_payload(payload: Dictionary) -> Dictionary:
	var position: Dictionary = Dictionary(payload.get("position", {}))
	return {
		"logical_player_id": String(payload.get("logical_player_id", "")),
		"player_entity_id": String(payload.get("player_entity_id", "")),
		"state_revision": int(payload.get("state_revision", 0)),
		"position": {
			"x": float(position.get("x", 0.0)),
			"y": float(position.get("y", 0.0)),
			"z": float(position.get("z", 0.0)),
		},
	}


static func _payload_hash(payload: Dictionary) -> String:
	return Utils.payload_hash(_canonical_payload(payload))


static func _checksum_payload(value: Dictionary) -> Dictionary:
	var path: Array[String] = []
	for item in Array(value.get("route_path", [])):
		path.append(String(item))
	return {
		"schema": String(value.get("schema", "")),
		"route_id": String(value.get("route_id", "")),
		"kind": String(value.get("kind", "")),
		"source_authority_id": String(value.get("source_authority_id", "")),
		"destination_authority_id": String(value.get("destination_authority_id", "")),
		"route_path": path,
		"hop_index": int(value.get("hop_index", -1)),
		"authority_epoch": int(value.get("authority_epoch", 0)),
		"payload": _canonical_payload(Dictionary(value.get("payload", {}))),
		"payload_hash": String(value.get("payload_hash", "")),
	}


static func _finalize(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result["checksum"] = Utils.payload_hash(_checksum_payload(result))
	return result


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
