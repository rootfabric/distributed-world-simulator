extends "res://scripts/persistence/canonical_state_port.gd"


func save_state(_state_key: String, _state: Dictionary) -> Dictionary:
	return _failure("NOT_IMPLEMENTED")


func load_state(_state_key: String) -> Dictionary:
	return _failure("NOT_IMPLEMENTED")


func delete_state(_state_key: String) -> Dictionary:
	return _failure("NOT_IMPLEMENTED")


func has_state(_state_key: String) -> bool:
	return false
