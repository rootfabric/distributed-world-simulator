extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const CommandEnvelopeScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultEnvelopeScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const SnapshotEnvelopeScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var first_payload: Dictionary = {"z": 3, "nested": {"b": 2, "a": 1}, "a": [1.0, 2.0]}
	var second_payload: Dictionary = {"a": [1.0, 2.0], "nested": {"a": 1, "b": 2}, "z": 3}
	var first: Dictionary = CommandEnvelopeScript.create(
		"message/1", "operation/1", "entity/probe", "probe.move",
		first_payload, 7, 3, 100, 200
	)
	var second: Dictionary = CommandEnvelopeScript.create(
		"message/2", "operation/1", "entity/probe", "probe.move",
		second_payload, 7, 3, 100, 999
	)
	_assert(bool(CommandEnvelopeScript.validate(first).get("success", false)), "Valid command envelope was rejected")
	_assert(CommandEnvelopeScript.command_fingerprint(first) == CommandEnvelopeScript.command_fingerprint(second), "Command fingerprint depends on dictionary order or transport metadata")
	_assert(not CommandEnvelopeScript.canonical_json(first).is_empty(), "Command canonical JSON is empty")

	var round_trip: Dictionary = UtilsScript.json_round_trip(first)
	_assert(bool(round_trip.get("success", false)), "Command envelope JSON round-trip failed")
	_assert(bool(CommandEnvelopeScript.validate(round_trip.get("value", {})).get("success", false)), "Round-tripped command envelope is invalid")
	_assert(CommandEnvelopeScript.command_fingerprint(first) == CommandEnvelopeScript.command_fingerprint(round_trip.get("value", {})), "Command fingerprint changes across JSON numeric normalization")

	var future: Dictionary = first.duplicate(true)
	future["protocol_version"] = 2
	_assert(String(CommandEnvelopeScript.validate(future).get("error_code", "")) == "UNSUPPORTED_PROTOCOL", "Future protocol was not rejected")
	var stale: Dictionary = first.duplicate(true)
	stale["authority_epoch"] = 0
	_assert(String(CommandEnvelopeScript.validate(stale).get("error_code", "")) == "INVALID_AUTHORITY_EPOCH", "Invalid authority epoch was accepted")

	var missing_payload: Dictionary = first.duplicate(true)
	missing_payload.erase("payload")
	_assert(_error_code(CommandEnvelopeScript.validate(missing_payload)) == "MISSING_FIELD", "Missing command payload was accepted")
	var numeric_message_id: Dictionary = first.duplicate(true)
	numeric_message_id["message_id"] = 42
	_assert(_error_code(CommandEnvelopeScript.validate(numeric_message_id)) == "INVALID_FIELD_TYPE", "Numeric message_id was normalized into a String")
	var string_revision: Dictionary = first.duplicate(true)
	string_revision["expected_revision"] = "7"
	_assert(_error_code(CommandEnvelopeScript.validate(string_revision)) == "INVALID_FIELD_TYPE", "String expected_revision was normalized into an integer")
	var fractional_revision: Dictionary = first.duplicate(true)
	fractional_revision["expected_revision"] = 7.5
	_assert(_error_code(CommandEnvelopeScript.validate(fractional_revision)) == "INVALID_FIELD_TYPE", "Fractional expected_revision was truncated")
	var extra_command_field: Dictionary = first.duplicate(true)
	extra_command_field["debug_only"] = true
	_assert(_error_code(CommandEnvelopeScript.validate(extra_command_field)) == "UNEXPECTED_FIELD", "Additional command envelope field was accepted")

	var unsafe_command_integer: Dictionary = first.duplicate(true)
	unsafe_command_integer["payload"] = {"nested": {"counter": 9007199254740993}}
	_assert(_error_code(CommandEnvelopeScript.validate(unsafe_command_integer)) == "NON_CANONICAL_PAYLOAD", "Unsafe nested command integer was accepted")

	var forbidden_node := Node.new()
	var forbidden: Dictionary = first.duplicate(true)
	forbidden["payload"] = {"node": forbidden_node}
	_assert(String(CommandEnvelopeScript.validate(forbidden).get("error_code", "")) == "NON_CANONICAL_PAYLOAD", "Godot Node leaked into network DTO")
	forbidden_node.free()

	var result: Dictionary = ResultEnvelopeScript.create(
		"message/1", "operation/1", "SUCCEEDED", "", 8, 3, {"accepted": true}
	)
	_assert(bool(ResultEnvelopeScript.validate(result).get("success", false)), "Valid result envelope was rejected")
	var result_round_trip: Dictionary = UtilsScript.json_round_trip(result)
	_assert(bool(ResultEnvelopeScript.validate(result_round_trip.get("value", {})).get("success", false)), "Round-tripped result envelope is invalid")
	var invalid_status: Dictionary = result.duplicate(true)
	invalid_status["status"] = "MAYBE"
	_assert(_error_code(ResultEnvelopeScript.validate(invalid_status)) == "INVALID_STATUS", "Unknown result status was accepted")
	var result_string_revision: Dictionary = result.duplicate(true)
	result_string_revision["result_revision"] = "8"
	_assert(_error_code(ResultEnvelopeScript.validate(result_string_revision)) == "INVALID_FIELD_TYPE", "String result_revision was normalized")
	var result_extra_field: Dictionary = result.duplicate(true)
	result_extra_field["server_debug"] = {}
	_assert(_error_code(ResultEnvelopeScript.validate(result_extra_field)) == "UNEXPECTED_FIELD", "Additional result envelope field was accepted")
	var result_missing_payload: Dictionary = result.duplicate(true)
	result_missing_payload.erase("payload")
	_assert(_error_code(ResultEnvelopeScript.validate(result_missing_payload)) == "MISSING_FIELD", "Missing result payload was accepted")
	var unsafe_result_integer: Dictionary = result.duplicate(true)
	unsafe_result_integer["payload"] = {"nested": {"counter": 9007199254740993}}
	_assert(_error_code(ResultEnvelopeScript.validate(unsafe_result_integer)) == "NON_CANONICAL_PAYLOAD", "Unsafe nested result integer was accepted")

	var spatial_ref: Dictionary = SpatialRefScript.create(
		"body/moon/fixed",
		Vector3(10.0, 20.0, 30.0),
		Basis.IDENTITY,
		Vector3(1.0, 2.0, 3.0),
		Vector3(0.1, 0.2, 0.3),
		42.0,
		"main",
		"sol",
		"persistent"
	)
	var snapshot: Dictionary = SnapshotEnvelopeScript.create(
		"snapshot/1", "entity/probe", "world_item", 12, "sim-01", 4, 500,
		spatial_ref,
		{},
		{"mass_kg": 5.0},
		{"item": {"definition_id": "survey_beacon"}}
	)
	_assert(bool(SnapshotEnvelopeScript.validate(snapshot).get("success", false)), "Valid entity snapshot envelope was rejected")
	_assert(not SnapshotEnvelopeScript.snapshot_hash(snapshot).is_empty(), "Entity snapshot hash is empty")
	var snapshot_round_trip: Dictionary = SnapshotEnvelopeScript.normalize(snapshot)
	_assert(bool(SnapshotEnvelopeScript.validate(snapshot_round_trip).get("success", false)), "Normalized entity snapshot is invalid")
	_assert(String(snapshot_round_trip.get("spatial_ref", {}).get("frame_id", "")) == "body/moon/fixed", "Snapshot lost reference frame")
	_assert(SnapshotEnvelopeScript.snapshot_hash(snapshot) == SnapshotEnvelopeScript.snapshot_hash(snapshot_round_trip), "Snapshot hash changes across JSON numeric normalization")
	var bad_snapshot: Dictionary = snapshot.duplicate(true)
	bad_snapshot["spatial_ref"] = {}
	_assert(_error_code(SnapshotEnvelopeScript.validate(bad_snapshot)) == "INVALID_SPATIAL_REF", "Invalid SpatialRef was accepted")
	var numeric_frame_snapshot: Dictionary = snapshot.duplicate(true)
	numeric_frame_snapshot["spatial_ref"] = spatial_ref.duplicate(true)
	numeric_frame_snapshot["spatial_ref"]["frame_id"] = 42
	_assert(_error_code(SnapshotEnvelopeScript.validate(numeric_frame_snapshot)) == "INVALID_SPATIAL_REF", "Numeric spatial_ref frame_id was normalized")
	var missing_sample_time_snapshot: Dictionary = snapshot.duplicate(true)
	missing_sample_time_snapshot["spatial_ref"] = spatial_ref.duplicate(true)
	missing_sample_time_snapshot["spatial_ref"].erase("sample_time_s")
	_assert(_error_code(SnapshotEnvelopeScript.validate(missing_sample_time_snapshot)) == "INVALID_SPATIAL_REF", "Missing spatial_ref sample_time_s was accepted")
	var extra_spatial_field_snapshot: Dictionary = snapshot.duplicate(true)
	extra_spatial_field_snapshot["spatial_ref"] = spatial_ref.duplicate(true)
	extra_spatial_field_snapshot["spatial_ref"]["debug_origin"] = "forbidden"
	_assert(_error_code(SnapshotEnvelopeScript.validate(extra_spatial_field_snapshot)) == "INVALID_SPATIAL_REF", "Additional spatial_ref field was accepted")
	var oversized_position_snapshot: Dictionary = snapshot.duplicate(true)
	oversized_position_snapshot["spatial_ref"] = spatial_ref.duplicate(true)
	oversized_position_snapshot["spatial_ref"]["position_m"] = [10.0, 20.0, 30.0, 40.0]
	_assert(_error_code(SnapshotEnvelopeScript.validate(oversized_position_snapshot)) == "INVALID_SPATIAL_REF", "Oversized spatial_ref position array was accepted")
	var non_unit_rotation_snapshot: Dictionary = snapshot.duplicate(true)
	non_unit_rotation_snapshot["spatial_ref"] = spatial_ref.duplicate(true)
	non_unit_rotation_snapshot["spatial_ref"]["rotation_xyzw"] = [0.0, 0.0, 0.0, 2.0]
	_assert(_error_code(SnapshotEnvelopeScript.validate(non_unit_rotation_snapshot)) == "INVALID_SPATIAL_REF", "Non-unit spatial_ref quaternion was accepted")
	var negative_rotation_snapshot: Dictionary = snapshot.duplicate(true)
	negative_rotation_snapshot["spatial_ref"] = spatial_ref.duplicate(true)
	negative_rotation_snapshot["spatial_ref"]["rotation_xyzw"] = [0.0, 0.0, 0.0, -1.0]
	_assert(bool(SnapshotEnvelopeScript.validate(negative_rotation_snapshot).get("success", false)), "Equivalent negative quaternion was rejected")
	_assert(SnapshotEnvelopeScript.snapshot_hash(snapshot) == SnapshotEnvelopeScript.snapshot_hash(negative_rotation_snapshot), "Equivalent quaternion signs produced different snapshot hashes")
	_assert(float(SnapshotEnvelopeScript.normalize(negative_rotation_snapshot).get("spatial_ref", {}).get("rotation_xyzw", [0.0, 0.0, 0.0, 0.0])[3]) == 1.0, "Snapshot normalization did not canonicalize quaternion sign")
	var unsafe_physics_integer_snapshot: Dictionary = snapshot.duplicate(true)
	unsafe_physics_integer_snapshot["physics_state"] = {"nested": {"counter": 9007199254740993}}
	_assert(_error_code(SnapshotEnvelopeScript.validate(unsafe_physics_integer_snapshot)) == "NON_CANONICAL_PAYLOAD", "Unsafe nested physics integer was accepted")
	var unsafe_component_integer_snapshot: Dictionary = snapshot.duplicate(true)
	unsafe_component_integer_snapshot["domain_components"] = {"item": {"serial": 9007199254740993}}
	_assert(_error_code(SnapshotEnvelopeScript.validate(unsafe_component_integer_snapshot)) == "NON_CANONICAL_PAYLOAD", "Unsafe nested component integer was accepted")
	var snapshot_string_revision: Dictionary = snapshot.duplicate(true)
	snapshot_string_revision["state_revision"] = "12"
	_assert(_error_code(SnapshotEnvelopeScript.validate(snapshot_string_revision)) == "INVALID_FIELD_TYPE", "String snapshot revision was normalized")
	var snapshot_fractional_tick: Dictionary = snapshot.duplicate(true)
	snapshot_fractional_tick["server_tick"] = 500.25
	_assert(_error_code(SnapshotEnvelopeScript.validate(snapshot_fractional_tick)) == "INVALID_FIELD_TYPE", "Fractional simulation tick was truncated")
	var snapshot_extra_field: Dictionary = snapshot.duplicate(true)
	snapshot_extra_field["presentation_node"] = "forbidden"
	_assert(_error_code(SnapshotEnvelopeScript.validate(snapshot_extra_field)) == "UNEXPECTED_FIELD", "Additional snapshot envelope field was accepted")

	_finish()


func _error_code(validation: Dictionary) -> String:
	return String(validation.get("error_code", ""))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N0 network contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N0 network contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
