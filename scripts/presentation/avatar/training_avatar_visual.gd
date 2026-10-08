extends "res://scripts/presentation/avatar/avatar_visual_port.gd"
# Minimal example of a completely independent avatar implementation.
# It can be replaced with an imported rig/AnimationTree scene later.
var _received_state: Dictionary = {}
func apply_avatar_state(state: Dictionary, _delta: float) -> void:
	_received_state = state.duplicate(true)
func get_avatar_report() -> Dictionary:
	return {"contract": "CHAR1_AVATAR_VISUAL_V1", "visual_type": "training", "state_received": not _received_state.is_empty()}
