class_name FirstPersonGrabAuthorityBridge
extends RefCounted

const MODE_FAIL_CLOSED := "FAIL_CLOSED"
const MODE_LOCAL_SANDBOX := "LOCAL_SANDBOX"
const MODE_AUTHORITATIVE := "AUTHORITATIVE"

var authoritative_submitter: Callable
var allow_local_sandbox := false
var operation_counter := 1
var submitted_authoritative := 0
var accepted_local_sandbox := 0
var rejected := 0
var last_result: Dictionary = {}


func setup(
	p_authoritative_submitter: Callable = Callable(),
	p_allow_local_sandbox: bool = false
) -> Dictionary:
	authoritative_submitter = p_authoritative_submitter
	allow_local_sandbox = p_allow_local_sandbox
	operation_counter = 1
	submitted_authoritative = 0
	accepted_local_sandbox = 0
	rejected = 0
	last_result = _success({
		"canonical_grab_authority_ready": authoritative_submitter.is_valid(),
		"local_sandbox_enabled": allow_local_sandbox,
	})
	return last_result.duplicate(true)


func request_grab(
	hand_id: String,
	target: Node,
	hit_position: Vector3,
	hit_normal: Vector3
) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _remember(_failure("FPE_INVALID_HAND", {"hand_id": hand_id}))
	if target == null or not is_instance_valid(target):
		return _remember(_failure("FPE_GRAB_TARGET_REQUIRED", {"hand_id": hand}))

	var canonical_item_id := String(target.get_meta("item_id", "")).strip_edges()
	if canonical_item_id.is_empty():
		canonical_item_id = String(target.get_meta("canonical_item_id", "")).strip_edges()

	if not canonical_item_id.is_empty():
		if not authoritative_submitter.is_valid():
			rejected += 1
			return _remember(_failure("FPE_CANONICAL_GRAB_AUTHORITY_UNAVAILABLE", {
				"hand_id": hand,
				"item_id": canonical_item_id,
				"authority_policy": MODE_FAIL_CLOSED,
				"required_contract": "hand.grab",
			}))
		var operation_id := _next_operation_id("grab", hand)
		var value = authoritative_submitter.call(
			"hand.grab",
			{
				"hand_id": hand,
				"item_id": canonical_item_id,
				"hit_position": _vector_payload(hit_position),
				"hit_normal": _vector_payload(hit_normal),
			},
			operation_id
		)
		if not value is Dictionary:
			rejected += 1
			return _remember(_failure("FPE_INVALID_AUTHORITATIVE_GRAB_RESULT", {
				"hand_id": hand,
				"item_id": canonical_item_id,
				"operation_id": operation_id,
			}))
		var result: Dictionary = Dictionary(value).duplicate(true)
		if bool(result.get("success", false)):
			submitted_authoritative += 1
		else:
			rejected += 1
		result["fpe_authority_mode"] = MODE_AUTHORITATIVE
		result["hand_id"] = hand
		result["item_id"] = canonical_item_id
		return _remember(result)

	if allow_local_sandbox and bool(target.get_meta("fpe_local_sandbox_grabbable", false)):
		accepted_local_sandbox += 1
		return _remember(_success({
			"hand_id": hand,
			"authority_mode": MODE_LOCAL_SANDBOX,
			"local_sandbox": true,
			"target_instance_id": target.get_instance_id(),
			"target_path": String(target.get_path()),
		}))

	rejected += 1
	return _remember(_failure("FPE_GRAB_TARGET_NOT_AUTHORIZED", {
		"hand_id": hand,
		"target_path": String(target.get_path()),
		"authority_policy": MODE_FAIL_CLOSED,
	}))


func request_release(hand_id: String, canonical_item_id: String = "") -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _remember(_failure("FPE_INVALID_HAND", {"hand_id": hand_id}))
	var item_id := canonical_item_id.strip_edges()
	if item_id.is_empty():
		return _remember(_success({
			"hand_id": hand,
			"authority_mode": MODE_LOCAL_SANDBOX,
			"local_sandbox": true,
		}))
	if not authoritative_submitter.is_valid():
		rejected += 1
		return _remember(_failure("FPE_CANONICAL_GRAB_AUTHORITY_UNAVAILABLE", {
			"hand_id": hand,
			"item_id": item_id,
			"required_contract": "hand.release",
		}))
	var operation_id := _next_operation_id("release", hand)
	var value = authoritative_submitter.call(
		"hand.release",
		{"hand_id": hand, "item_id": item_id},
		operation_id
	)
	if not value is Dictionary:
		rejected += 1
		return _remember(_failure("FPE_INVALID_AUTHORITATIVE_RELEASE_RESULT", {
			"hand_id": hand,
			"item_id": item_id,
			"operation_id": operation_id,
		}))
	var result: Dictionary = Dictionary(value).duplicate(true)
	if bool(result.get("success", false)):
		submitted_authoritative += 1
	else:
		rejected += 1
	result["fpe_authority_mode"] = MODE_AUTHORITATIVE
	result["hand_id"] = hand
	result["item_id"] = item_id
	return _remember(result)


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.first_person_grab_authority_bridge.v1",
		"canonical_grab_authority_ready": authoritative_submitter.is_valid(),
		"local_sandbox_enabled": allow_local_sandbox,
		"submitted_authoritative": submitted_authoritative,
		"accepted_local_sandbox": accepted_local_sandbox,
		"rejected": rejected,
		"last_result": last_result.duplicate(true),
		"owns_network_state": false,
		"owns_item_state": false,
		"authority_policy": MODE_AUTHORITATIVE if authoritative_submitter.is_valid() else MODE_FAIL_CLOSED,
	}


func _next_operation_id(verb: String, hand_id: String) -> String:
	var value := "fpe-%s-%s-%d-%d" % [verb, hand_id, Time.get_ticks_msec(), operation_counter]
	operation_counter += 1
	return value


func _normalize_hand(hand_id: String) -> String:
	var normalized := hand_id.strip_edges().to_lower()
	return normalized if normalized in ["left", "right"] else ""


func _vector_payload(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


func _remember(result: Dictionary) -> Dictionary:
	last_result = result.duplicate(true)
	return result


func _success(details: Dictionary = {}) -> Dictionary:
	return {
		"success": true,
		"error_code": "",
		"details": details.duplicate(true),
	}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
