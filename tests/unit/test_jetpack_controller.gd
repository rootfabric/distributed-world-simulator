extends SceneTree

const JetpackControllerScript = preload(
	"res://scripts/actors/controllers/jetpack_controller.gd"
)

var failures: Array[String] = []


func _init() -> void:
	var controller = JetpackControllerScript.new()
	var up := Vector3.UP
	var pitched_view := Basis(Vector3.RIGHT, deg_to_rad(-45.0))
	var axes: Dictionary = controller.get_view_relative_flight_axes(
		up,
		pitched_view
	)
	var forward: Vector3 = axes.get("forward", Vector3.ZERO)
	var expected_forward: Vector3 = -pitched_view.z.normalized()
	_assert(
		forward.dot(expected_forward) > 0.999999,
		"Jetpack forward movement does not follow the camera center."
	)
	_assert(
		absf(forward.dot(up)) > 0.1,
		"Jetpack forward movement was incorrectly flattened to the horizon."
	)
	var right: Vector3 = axes.get("right", Vector3.ZERO)
	_assert(
		right.dot(pitched_view.x.normalized()) > 0.999999,
		"Jetpack strafe direction does not follow the camera."
	)
	controller.free()
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("Jetpack controller tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Jetpack controller tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
