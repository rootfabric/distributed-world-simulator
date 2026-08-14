extends SceneTree

const ProjectorScript = preload("res://scripts/app/earth_surface_render_projector.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var surface_direction := Vector3(0.37, 0.81, -0.45).normalized()
	var surface_point := surface_direction * 6_371_123.0
	var canonical_anchor: Transform3D = ProjectorScript.create_surface_anchor(
		surface_point,
		0.25
	)
	var canonical_origin := canonical_anchor.origin
	var canonical_basis := canonical_anchor.basis

	_assert(
		canonical_origin.distance_to(surface_point + surface_direction * 0.25) < 0.000001,
		"foundation center is lifted by half-height from the surface"
	)
	_assert(
		canonical_basis.y.normalized().distance_to(surface_direction) < 0.000001,
		"construction up axis follows Earth surface normal"
	)

	var eye_origin := surface_point + surface_direction * 1.75
	var near_transform: Transform3D = ProjectorScript.project_anchor(
		canonical_anchor,
		eye_origin,
		Basis.IDENTITY
	)
	_assert(
		near_transform.origin.distance_to(surface_direction * -1.5) < 0.000001,
		"near render origin is observer-relative without changing anchor"
	)

	var walked_origin := eye_origin + canonical_basis.x * 10.0
	var walked_transform: Transform3D = ProjectorScript.project_anchor(
		canonical_anchor,
		walked_origin,
		Basis.IDENTITY
	)
	_assert(
		(walked_transform.origin - near_transform.origin).distance_to(
			canonical_basis.x * -10.0
		) < 0.000001,
		"walking moves only the derived render transform"
	)

	var jumped_origin := eye_origin + surface_direction * 3.0
	var jumped_transform: Transform3D = ProjectorScript.project_anchor(
		canonical_anchor,
		jumped_origin,
		Basis.IDENTITY
	)
	_assert(
		(jumped_transform.origin - near_transform.origin).distance_to(
			surface_direction * -3.0
		) < 0.000001,
		"jumping moves construction down relative to observer while world anchor stays fixed"
	)

	var spectator_delta := Vector3(125.0, -40.0, 310.0)
	var spectator_transform: Transform3D = ProjectorScript.project_anchor(
		canonical_anchor,
		eye_origin + spectator_delta,
		Basis.IDENTITY
	)
	_assert(
		(spectator_transform.origin - near_transform.origin).distance_to(
			-spectator_delta
		) < 0.000001,
		"spectator translation is reflected exactly in derived construction position"
	)

	var rotated_frame := Basis(Vector3.UP, 0.47).orthonormalized()
	var rotated_transform: Transform3D = ProjectorScript.project_anchor(
		canonical_anchor,
		eye_origin,
		rotated_frame
	)
	_assert(
		rotated_transform.origin.distance_to(
			rotated_frame * (canonical_anchor.origin - eye_origin)
		) < 0.000001,
		"reference-frame conversion is applied only during presentation projection"
	)
	_assert(
		rotated_transform.basis.y.normalized().distance_to(
			(rotated_frame * surface_direction).normalized()
		) < 0.000001,
		"surface orientation survives reference-frame conversion"
	)

	_assert(
		canonical_anchor.origin.distance_to(canonical_origin) < 0.000001,
		"canonical anchor origin is immutable across observer movement"
	)
	_assert(
		canonical_anchor.basis.x.distance_to(canonical_basis.x) < 0.000001
		and canonical_anchor.basis.y.distance_to(canonical_basis.y) < 0.000001
		and canonical_anchor.basis.z.distance_to(canonical_basis.z) < 0.000001,
		"canonical anchor basis is immutable across observer movement"
	)

	_finish()


func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-C2A Earth surface render projector: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-C2A Earth surface render projector: FAIL (%d failures)" % failures.size())
	quit(1)
