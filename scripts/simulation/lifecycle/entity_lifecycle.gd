extends RefCounted

const DORMANT: String = "DORMANT"
const WARM: String = "WARM"
const ACTIVE: String = "ACTIVE"
const UNLOADING: String = "UNLOADING"
const DESTROYED: String = "DESTROYED"

const STATES: Array[String] = [DORMANT, WARM, ACTIVE, UNLOADING, DESTROYED]


static func is_valid(state: String) -> bool:
	return state in STATES


static func can_transition(current: String, next: String) -> bool:
	if not is_valid(current) or not is_valid(next):
		return false
	if current == next:
		return true
	match current:
		DORMANT:
			return next == WARM or next == DESTROYED
		WARM:
			return next in [ACTIVE, DORMANT, UNLOADING, DESTROYED]
		ACTIVE:
			return next in [WARM, UNLOADING, DESTROYED]
		UNLOADING:
			return next in [DORMANT, WARM, DESTROYED]
		DESTROYED:
			return false
	return false


static func transition(current: String, next: String) -> Dictionary:
	if not is_valid(current):
		return _failure("INVALID_CURRENT_LIFECYCLE_STATE", current, next)
	if not is_valid(next):
		return _failure("INVALID_TARGET_LIFECYCLE_STATE", current, next)
	if not can_transition(current, next):
		return _failure("ILLEGAL_LIFECYCLE_TRANSITION", current, next)
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
