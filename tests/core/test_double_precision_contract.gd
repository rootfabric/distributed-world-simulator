extends SceneTree


func _init() -> void:
	var large_coordinate := Vector3(1_000_000_000.125, 0.0, 0.0)
	var preserved_fraction: bool = (
		absf(large_coordinate.x - 1_000_000_000.125) < 0.01
	)
	if preserved_fraction:
		print("Double precision contract: PASS")
		quit(0)
		return
	push_error(
		"Single-precision Godot detected. Use a precision=double editor build."
	)
	print("Double precision contract: FAIL")
	quit(1)
