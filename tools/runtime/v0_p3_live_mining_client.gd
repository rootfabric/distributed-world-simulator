extends "res://tools/runtime/v0_p3_live_mining_client_base.gd"

# Test-only stability adapter. The production mining range and canonical
# resource location remain unchanged; the live driver simply allows enough
# authoritative movement-intent acknowledgements to reach the demo node from
# player A's deterministic spawn under slow/loaded CI scheduling.

const MIN_RESOURCE_APPROACH_STEPS := 12


func _move_toward(target: Vector3, steps: int) -> Dictionary:
	return await super._move_toward(target, maxi(steps, MIN_RESOURCE_APPROACH_STEPS))
