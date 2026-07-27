extends RefCounted

const DORMANT: String = "DORMANT"
const WARM: String = "WARM"
const ACTIVE: String = "ACTIVE"
const UNLOADING: String = "UNLOADING"

const STATES: Array[String] = [DORMANT, WARM, ACTIVE, UNLOADING]


static func is_valid(state: String) -> bool:
	return state in STATES


static func can_transition(current: String, next: String) -> bool:
	if not is_valid(current) or not is_valid(next):
		return false
	if current == next:
		return true
	match current:
		DORMANT:
			return next == WARM
		WARM:
			return next in [DORMANT, ACTIVE, UNLOADING]
		ACTIVE:
			return next in [WARM, UNLOADING]
		UNLOADING:
			return next in [DORMANT, WARM]
	return false


static func transition(current: String, next: String) -> Dictionary:
	if not is_valid(current):
		return _failure("INVALID_CURRENT_CHUNK_STATE", current, next)
	if not is_valid(next):
		return _failure("INVALID_TARGET_CHUNK_STATE", current, next)
	if not can_transition(current, next):
		return _failure("ILLEGAL_CHUNK_TRANSITION", current, next)
	return {
		"success": true,
		"changed": current != next,
		"previous_state": current,
		"state": next,
	}


static func _failure(code: String, current: String, next: String) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"previous_state": current,
		"requested_state": next,
	}
