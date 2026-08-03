extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const InputSequence = preload("res://scripts/network/simulation/input_sequence.gd")

const SCHEMA: String = "planet_simulator.player_input_batch.v2"
const MAX_INPUTS: int = 3
const MAX_DELTA_SECONDS: float = 0.25
const HISTORY_POLICY: String = "LAST_THREE_STATE_TRANSITIONS_FIXED_TICK_V1"
const SERVER_DELTA_POLICY: String = "IGNORED_SERVER_FIXED_TICK_V1"
const SEQUENCE_ORDER_POLICY: String = "WRAP_AWARE_FORWARD_ORDER_V1"
const FIELDS: Array[String] = [
	"schema", "batch_id", "logical_player_id", "ownership_epoch",
	"operation_id", "latest_sequence", "inputs", "checksum",
]
const WIRE_INPUT_FIELDS: Array[String] = ["s", "t", "m", "x", "z", "y", "p", "j", "r", "d"]


static func create(
	batch_id: String,
	logical_player_id: String,
	ownership_epoch: int,
	inputs: Array,
	operation_id: String = ""
) -> Dictionary:
	var compact_inputs: Array = []
	var latest_sequence: int = 0
	var latest_operation_id: String = operation_id.strip_edges()
	for input_value in inputs:
		if not input_value is Dictionary:
			continue
		var input: Dictionary = Dictionary(input_value)
		var intent: Dictionary = Dictionary(input.get("intent", {}))
		var sequence: int = int(input.get("input_sequence", 0))
		latest_sequence = sequence
		if latest_operation_id.is_empty():
			latest_operation_id = String(input.get("operation_id", "")).strip_edges()
		compact_inputs.append({
			"s": sequence,
			"t": int(input.get("client_tick", sequence)),
			"m": int(input.get("client_sent_at_ms", 0)),
			"x": float(intent.get("move_x", 0.0)),
			"z": float(intent.get("move_z", 0.0)),
			"y": float(intent.get("look_yaw", 0.0)),
			"p": float(intent.get("look_pitch", 0.0)),
			"j": bool(intent.get("jump_pressed", false)),
			"r": bool(intent.get("sprint", false)),
			"d": float(intent.get("delta_seconds", 1.0 / 60.0)),
		})
	var body: Dictionary = {
		"schema": SCHEMA,
		"batch_id": batch_id.strip_edges(),
		"logical_player_id": logical_player_id.strip_edges().to_lower(),
		"ownership_epoch": ownership_epoch,
		"operation_id": latest_operation_id,
		"latest_sequence": latest_sequence,
		"inputs": compact_inputs,
	}
	var round_trip: Dictionary = Utils.json_round_trip(body)
	if bool(round_trip.get("success", false)) and round_trip.get("value") is Dictionary:
		body = Dictionary(round_trip.get("value", {}))
	body["checksum"] = Utils.payload_hash(body)
	return body


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return _failure("PLAYER_INPUT_BATCH_FIELD_SET_MISMATCH")
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("INVALID_PLAYER_INPUT_BATCH_SCHEMA")
	if not _canonical_id(String(value.get("batch_id", "")), "input-batch"):
		return _failure("INVALID_PLAYER_INPUT_BATCH_ID")
	var player_id: String = String(value.get("logical_player_id", ""))
	if player_id.is_empty() or player_id != player_id.to_lower():
		return _failure("INVALID_PLAYER_INPUT_BATCH_PLAYER")
	if not Utils.is_json_integer(value.get("ownership_epoch")) or int(value.get("ownership_epoch", 0)) < 1:
		return _failure("INVALID_PLAYER_INPUT_BATCH_OWNERSHIP")
	if not _canonical_id(String(value.get("operation_id", "")), "operation"):
		return _failure("INVALID_PLAYER_INPUT_OPERATION")
	if not Utils.is_json_integer(value.get("latest_sequence")) or int(value.get("latest_sequence", 0)) < 1:
		return _failure("INVALID_PLAYER_INPUT_BATCH_LATEST_SEQUENCE")
	if not value.get("inputs") is Array:
		return _failure("INVALID_PLAYER_INPUT_BATCH_INPUTS")
	var inputs: Array = value.get("inputs", [])
	if inputs.is_empty() or inputs.size() > MAX_INPUTS:
		return _failure("INVALID_PLAYER_INPUT_BATCH_SIZE")
	var previous_sequence: int = 0
	for input_value in inputs:
		if not input_value is Dictionary:
			return _failure("INVALID_PLAYER_INPUT_ENTRY")
		var input: Dictionary = input_value
		if not bool(Utils.validate_exact_fields(input, WIRE_INPUT_FIELDS).get("success", false)):
			return _failure("PLAYER_INPUT_ENTRY_FIELD_SET_MISMATCH")
		if not Utils.is_json_integer(input.get("s")):
			return _failure("INVALID_PLAYER_INPUT_SEQUENCE_ORDER")
		var sequence: int = int(input.get("s", 0))
		if not InputSequence.is_valid(sequence):
			return _failure("INVALID_PLAYER_INPUT_SEQUENCE_ORDER")
		if previous_sequence != 0 and not InputSequence.is_newer(sequence, previous_sequence):
			return _failure("INVALID_PLAYER_INPUT_SEQUENCE_ORDER")
		previous_sequence = sequence
		for integer_field in ["t", "m"]:
			if not Utils.is_json_integer(input.get(integer_field)) or int(input.get(integer_field, -1)) < 0:
				return _failure("INVALID_PLAYER_INPUT_TIMESTAMP")
		for number_field in ["x", "z", "y", "p", "d"]:
			if not _finite_number(input.get(number_field)):
				return _failure("INVALID_PLAYER_INPUT_INTENT_NUMBER")
		var delta_seconds: float = float(input.get("d", 0.0))
		if delta_seconds <= 0.0 or delta_seconds > MAX_DELTA_SECONDS:
			return _failure("INVALID_PLAYER_INPUT_DELTA_SECONDS")
		for bool_field in ["j", "r"]:
			if typeof(input.get(bool_field)) != TYPE_BOOL:
				return _failure("INVALID_PLAYER_INPUT_INTENT_FLAG")
	if previous_sequence != int(value.get("latest_sequence", 0)):
		return _failure("PLAYER_INPUT_BATCH_LATEST_SEQUENCE_MISMATCH")
	var copy: Dictionary = value.duplicate(true)
	var checksum: String = String(copy.get("checksum", ""))
	copy.erase("checksum")
	if checksum.is_empty() or checksum != Utils.payload_hash(copy):
		return _failure("PLAYER_INPUT_BATCH_CHECKSUM_MISMATCH")
	return _success()


static func expand_inputs(value: Dictionary) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	var expanded: Array[Dictionary] = []
	var latest_sequence: int = int(value.get("latest_sequence", 0))
	var player_id: String = String(value.get("logical_player_id", ""))
	for input_value in value.get("inputs", []):
		var input: Dictionary = Dictionary(input_value)
		var sequence: int = int(input.get("s", 0))
		var operation_id: String = String(value.get("operation_id", ""))
		if sequence != latest_sequence:
			operation_id = "operation/nx2/redundant/%s/%d" % [player_id, sequence]
		expanded.append({
			"input_sequence": sequence,
			"operation_id": operation_id,
			"client_tick": int(input.get("t", sequence)),
			"client_sent_at_ms": int(input.get("m", 0)),
			"intent": {
				"move_x": float(input.get("x", 0.0)),
				"move_z": float(input.get("z", 0.0)),
				"look_yaw": float(input.get("y", 0.0)),
				"look_pitch": float(input.get("p", 0.0)),
				"jump_pressed": bool(input.get("j", false)),
				"sprint": bool(input.get("r", false)),
				"delta_seconds": float(input.get("d", 1.0 / 60.0)),
			},
		})
	return _success({"inputs": expanded})


static func append_to_history(history: Array, entry: Dictionary) -> Array:
	var result: Array = history.duplicate(true)
	var candidate: Dictionary = entry.duplicate(true)
	if not result.is_empty() and result.back() is Dictionary:
		var previous: Dictionary = Dictionary(result.back())
		if _same_continuous_state(previous, candidate):
			result[result.size() - 1] = candidate
			return result
	result.append(candidate)
	while result.size() > MAX_INPUTS:
		result.pop_front()
	return result


static func _same_continuous_state(previous: Dictionary, candidate: Dictionary) -> bool:
	var previous_intent: Dictionary = Dictionary(previous.get("intent", {}))
	var candidate_intent: Dictionary = Dictionary(candidate.get("intent", {}))
	if bool(previous_intent.get("jump_pressed", false)) or bool(candidate_intent.get("jump_pressed", false)):
		return false
	return is_equal_approx(float(previous_intent.get("move_x", 0.0)), float(candidate_intent.get("move_x", 0.0))) \
		and is_equal_approx(float(previous_intent.get("move_z", 0.0)), float(candidate_intent.get("move_z", 0.0))) \
		and bool(previous_intent.get("sprint", false)) == bool(candidate_intent.get("sprint", false))


static func _canonical_id(value: String, prefix: String) -> bool:
	return value.begins_with(prefix + "/") and value.length() > prefix.length() + 1 and value == value.strip_edges()


static func _finite_number(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number: float = float(value)
	return not is_nan(number) and not is_inf(number)


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
