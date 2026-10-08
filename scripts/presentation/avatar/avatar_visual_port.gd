extends Node3D
# CHAR1 visual-only interface. Implementations never own player identity, movement,
# network replication, collision, inventory, or canonical state.
func apply_avatar_state(_state: Dictionary, _delta: float) -> void:
	pass

func get_avatar_report() -> Dictionary:
	return {"visual_type": "base", "contract": "CHAR1_AVATAR_VISUAL_V1"}
