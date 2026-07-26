extends SceneTree

const FrameGraphScript = preload(
	"res://scripts/simulation/frames/frame_graph.gd"
)
const OrbitProviderScript = preload(
	"res://scripts/simulation/frames/providers/orbit_provider.gd"
)
const RotationProviderScript = preload(
	"res://scripts/simulation/frames/providers/rotation_provider.gd"
)
const FrameMotionProviderScript = preload(
	"res://scripts/simulation/frames/providers/frame_motion_provider.gd"
)
const SpatialRefScript = preload(
	"res://scripts/simulation/spatial/spatial_ref.gd"
)

var failures: Array[String] = []


func _init() -> void:
	var graph = FrameGraphScript.new()
	_assert(graph.setup("system.root"), "Root frame setup failed.")

	var orbit = OrbitProviderScript.new()
	orbit.setup({
		"type": "static",
		"position_m": [100.0, 0.0, 0.0],
		"velocity_mps": [0.0, 0.0, 0.0],
	})
	var inertial_motion = FrameMotionProviderScript.new()
	inertial_motion.setup(orbit, null)
	_assert(
		graph.add_frame("body.inertial", "system.root", inertial_motion),
		"Inertial frame registration failed."
	)

	var rotation = RotationProviderScript.new()
	rotation.setup({
		"type": "uniform",
		"period_s": TAU,
		"phase_deg": 0.0,
	})
	var fixed_motion = FrameMotionProviderScript.new()
	fixed_motion.setup(null, rotation)
	_assert(
		graph.add_frame("body.fixed", "body.inertial", fixed_motion),
		"Body-fixed frame registration failed."
	)

	var local_point := Vector3(10.0, 0.0, 0.0)
	var root_at_zero: Vector3 = graph.transform_point(
		local_point,
		"body.fixed",
		"system.root",
		0.0
	)
	var root_at_one: Vector3 = graph.transform_point(
		local_point,
		"body.fixed",
		"system.root",
		1.0
	)
	_assert(
		root_at_zero.distance_to(Vector3(110.0, 0.0, 0.0)) < 0.000001,
		"Unexpected body-fixed point at epoch."
	)
	_assert(
		root_at_zero.distance_to(root_at_one) > 1.0,
		"Rotating body-fixed point did not move in root frame."
	)
	var roundtrip: Vector3 = graph.transform_point(
		root_at_one,
		"system.root",
		"body.fixed",
		1.0
	)
	_assert(
		roundtrip.distance_to(local_point) < 0.000001,
		"Frame point roundtrip lost precision."
	)

	var surface_ref: Dictionary = SpatialRefScript.create(
		"body.fixed",
		local_point,
		Basis.IDENTITY,
		Vector3.ZERO,
		Vector3.ZERO,
		0.0
	)
	var root_ref: Dictionary = graph.transform_spatial_ref(
		surface_ref,
		"system.root",
		0.0
	)
	var root_velocity: Vector3 = SpatialRefScript.get_linear_velocity(root_ref)
	_assert(
		absf(root_velocity.length() - 10.0) < 0.000001,
		"Rotating-frame velocity term is missing."
	)
	var restored_ref: Dictionary = graph.transform_spatial_ref(
		root_ref,
		"body.fixed",
		0.0
	)
	_assert(
		SpatialRefScript.get_position(restored_ref).distance_to(local_point) < 0.000001,
		"SpatialRef roundtrip failed."
	)
	_assert(
		SpatialRefScript.get_linear_velocity(restored_ref).length() < 0.000001,
		"SpatialRef velocity roundtrip failed."
	)
	_assert(
		String(root_ref.get("instance_id", "")) == "persistent",
		"Frame transform lost the universe instance namespace."
	)
	var foreign_ref: Dictionary = surface_ref.duplicate(true)
	foreign_ref["instance_id"] = "parallel-scenario"
	_assert(
		graph.transform_spatial_ref(foreign_ref, "system.root", 0.0).is_empty(),
		"Frame graph accepted a SpatialRef from another instance."
	)
	_assert(
		graph.setup("second.root", {"instance_id": "scenario-a"}),
		"Frame graph could not be reconfigured."
	)
	_assert(graph.instance_id == "scenario-a", "Frame graph did not apply new identity.")
	_assert(
		graph.setup("default.root"),
		"Frame graph could not reset to default identity."
	)
	_assert(
		graph.instance_id == SpatialRefScript.DEFAULT_INSTANCE_ID,
		"Frame graph leaked identity across setup calls."
	)
	_assert(
		not graph.setup("invalid.root", {"instance_id": "invalid/path"}),
		"Frame graph accepted an invalid instance namespace."
	)
	var invalid_spatial_ref: Dictionary = SpatialRefScript.create(
		"body.fixed",
		Vector3.ZERO,
		Basis.IDENTITY,
		Vector3.ZERO,
		Vector3.ZERO,
		0.0,
		"main",
		"sol",
		"invalid/path"
	)
	_assert(
		not SpatialRefScript.is_valid(invalid_spatial_ref),
		"SpatialRef accepted an invalid instance namespace."
	)

	if failures.is_empty():
		print("Reference frame graph tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Reference frame graph tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
