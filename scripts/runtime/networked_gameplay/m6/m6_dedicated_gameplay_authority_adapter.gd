extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")

const SCHEMA := "planet_simulator.m6_dedicated_gameplay_authority_adapter.v1"
const ENTITY_ID := "aggregate/m6/dedicated-gameplay"
const ENTITY_TYPE := "networked_gameplay_runtime"

var _service
var _logical_session_id := "session/m6/dedicated"


func setup(service_reference, logical_session_id: String = "session/m6/dedicated") -> Dictionary:
	if service_reference == null:
		return _failure("M6_GAMEPLAY_SERVICE_REQUIRED")
	for method_name in ["export_durable_state", "restore_durable_state", "validate_durable_state", "get_report"]:
		if not service_reference.has_method(method_name):
			return _failure("M6_GAMEPLAY_SERVICE_METHOD_MISSING", {"method": method_name})
	var normalized_session := logical_session_id.strip_edges().to_lower()
	if not _is_canonical_id(normalized_session):
		return _failure("INVALID_M6_LOGICAL_SESSION_ID")
	_service = service_reference
	_logical_session_id = normalized_session
	return _success()


func export_recovery_state() -> Dictionary:
	if _service == null:
		return {}
	var durable_state: Dictionary = _service.export_durable_state()
	if durable_state.is_empty():
		return {}
	var authority_owner_id := String(durable_state.get("authority_owner_id", ""))
	var authority_epoch := int(durable_state.get("authority_epoch", 0))
	var state_revision := int(durable_state.get("revision", 0))
	var server_tick := int(durable_state.get("server_tick", 0))
	var snapshot := EntitySnapshot.create(
		"snapshot/m6/dedicated/%d" % state_revision,
		ENTITY_ID,
		ENTITY_TYPE,
		state_revision,
		authority_owner_id,
		authority_epoch,
		server_tick,
		_spatial_ref(server_tick),
		{"region_id": String(durable_state.get("region_id", ""))},
		{},
		{
			"networked_gameplay_state": durable_state,
			"durable_state_checksum": String(durable_state.get("checksum", "")),
		}
	)
	return {
		"schema": SCHEMA,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"server_tick": server_tick,
		"session_id": _logical_session_id,
		"current_snapshot": snapshot,
		"durable_state_checksum": String(durable_state.get("checksum", "")),
	}


func restore_recovery_state(value: Dictionary) -> Dictionary:
	if _service == null:
		return _failure("M6_AUTHORITY_ADAPTER_NOT_CONFIGURED")
	var validation := validate_recovery_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var snapshot: Dictionary = value.get("current_snapshot", {})
	var components: Dictionary = snapshot.get("domain_components", {})
	var durable_state: Dictionary = components.get("networked_gameplay_state", {})
	var restored: Dictionary = _service.restore_durable_state(durable_state)
	if not bool(restored.get("success", false)):
		return _failure("M6_GAMEPLAY_STATE_RESTORE_FAILED", {"cause": restored})
	var round_trip: Dictionary = _service.export_durable_state()
	if String(round_trip.get("checksum", "")) != String(durable_state.get("checksum", "")):
		return _failure("M6_GAMEPLAY_STATE_ROUNDTRIP_MISMATCH")
	return _success({
		"state_revision": int(snapshot.get("state_revision", -1)),
		"server_tick": int(snapshot.get("server_tick", -1)),
		"durable_state_checksum": String(round_trip.get("checksum", "")),
	})


func validate_recovery_state(value: Dictionary) -> Dictionary:
	if _service == null:
		return _failure("M6_AUTHORITY_ADAPTER_NOT_CONFIGURED")
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("INVALID_M6_AUTHORITY_STATE_SCHEMA")
	for field in ["authority_owner_id", "authority_epoch", "server_tick", "session_id", "current_snapshot", "durable_state_checksum"]:
		if not value.has(field):
			return _failure("M6_AUTHORITY_STATE_FIELD_MISSING", {"field": field})
	if String(value.get("session_id", "")) != _logical_session_id:
		return _failure("M6_LOGICAL_SESSION_MISMATCH")
	var snapshot_value = value.get("current_snapshot", {})
	if not snapshot_value is Dictionary:
		return _failure("INVALID_M6_AUTHORITY_SNAPSHOT")
	var snapshot: Dictionary = snapshot_value
	var snapshot_validation := EntitySnapshot.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return _failure("INVALID_M6_AUTHORITY_SNAPSHOT", {"cause": snapshot_validation})
	if String(snapshot.get("entity_id", "")) != ENTITY_ID or String(snapshot.get("entity_type", "")) != ENTITY_TYPE:
		return _failure("INVALID_M6_AUTHORITY_ENTITY")
	if String(snapshot.get("authority_owner_id", "")) != String(value.get("authority_owner_id", "")):
		return _failure("M6_AUTHORITY_OWNER_MISMATCH")
	if int(snapshot.get("authority_epoch", 0)) != int(value.get("authority_epoch", 0)):
		return _failure("M6_AUTHORITY_EPOCH_MISMATCH")
	if int(snapshot.get("server_tick", -1)) != int(value.get("server_tick", -2)):
		return _failure("M6_AUTHORITY_TICK_MISMATCH")
	var components: Dictionary = snapshot.get("domain_components", {})
	var durable_state_value = components.get("networked_gameplay_state", {})
	if not durable_state_value is Dictionary:
		return _failure("M6_GAMEPLAY_STATE_MISSING")
	var durable_state: Dictionary = durable_state_value
	if String(durable_state.get("checksum", "")) != String(value.get("durable_state_checksum", "")):
		return _failure("M6_DURABLE_STATE_CHECKSUM_MISMATCH")
	if String(components.get("durable_state_checksum", "")) != String(value.get("durable_state_checksum", "")):
		return _failure("M6_DURABLE_COMPONENT_CHECKSUM_MISMATCH")
	var service_validation: Dictionary = _service.validate_durable_state(durable_state)
	if not bool(service_validation.get("success", false)):
		return _failure("INVALID_M6_GAMEPLAY_STATE", {"cause": service_validation})
	if int(durable_state.get("revision", -1)) != int(snapshot.get("state_revision", -2)):
		return _failure("M6_GAMEPLAY_REVISION_MISMATCH")
	if int(durable_state.get("server_tick", -1)) != int(snapshot.get("server_tick", -2)):
		return _failure("M6_GAMEPLAY_TICK_MISMATCH")
	var safe := Utils.canonicalize(value, "$.m6_authority_state")
	if not bool(safe.get("success", false)):
		return _failure("M6_AUTHORITY_STATE_NOT_JSON_SAFE", {"message": String(safe.get("error", ""))})
	return _success()


func _spatial_ref(server_tick: int) -> Dictionary:
	return {
		"schema": EntitySnapshot.SPATIAL_REF_SCHEMA,
		"universe_id": "planet-simulator",
		"instance_id": "m6-dedicated",
		"space_id": "networked-gameplay",
		"frame_id": "frame/m6/dedicated",
		"position_m": [0.0, 0.0, 0.0],
		"rotation_xyzw": [0.0, 0.0, 0.0, 1.0],
		"linear_velocity_mps": [0.0, 0.0, 0.0],
		"angular_velocity_rps": [0.0, 0.0, 0.0],
		"sample_time_s": float(server_tick),
	}


func _is_canonical_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["/", "_", ".", "-"]):
			return false
	return true


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
