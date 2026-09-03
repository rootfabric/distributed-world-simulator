extends RefCounted

## ECO.EVO7 VIS5.1 — read-only terrain surface frame adapter.
##
## Converts one canonical ProceduralEarthWorld surface direction into two
## explicitly separated frames:
##   radial_basis  — gravity/radial-up frame for macro plants;
##   terrain_basis — derived geometric-normal frame for low ground cover/rocks.
##
## The adapter never writes terrain/ecology state and never changes the
## canonical source direction or surface point.

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis5_terrain_surface_frame.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS5.1.R1"

const PRESENTATION_ONLY := true
const DEFAULT_SAMPLE_DISTANCE_M := 2.0
const MIN_SAMPLE_DISTANCE_M := 0.05
const MAX_SAMPLE_DISTANCE_M := 64.0


static func build(
	earth_world,
	direction_value: Vector3,
	sample_distance_m: float = DEFAULT_SAMPLE_DISTANCE_M,
	lod_level: int = 0
) -> Dictionary:
	if earth_world == null:
		return {}
	if not earth_world.has_method("get_planet_radius"):
		return {}
	if not earth_world.has_method("get_surface_point"):
		return {}
	if not earth_world.has_method("get_surface_state"):
		return {}
	if not _finite_vec(direction_value) or direction_value.length_squared() < 0.5:
		return {}
	if not is_finite(sample_distance_m):
		return {}
	if sample_distance_m < MIN_SAMPLE_DISTANCE_M or sample_distance_m > MAX_SAMPLE_DISTANCE_M:
		return {}
	if lod_level < 0:
		return {}

	var planet_radius := float(earth_world.get_planet_radius())
	if not is_finite(planet_radius) or planet_radius <= 1.0:
		return {}

	var radial_up := direction_value.normalized()
	var radial_basis := _up_basis(radial_up)
	var angular_step := sample_distance_m / planet_radius

	var center_world_value = earth_world.get_surface_point(radial_up)
	if not center_world_value is Vector3:
		return {}
	var center_world := Vector3(center_world_value)
	if not _finite_vec(center_world):
		return {}

	var state_value = earth_world.get_surface_state(radial_up, lod_level)
	if not state_value is Dictionary:
		return {}
	var surface_state: Dictionary = Dictionary(state_value).duplicate(true)

	var x_plus_direction := (radial_up + radial_basis.x * angular_step).normalized()
	var x_minus_direction := (radial_up - radial_basis.x * angular_step).normalized()
	var z_plus_direction := (radial_up + radial_basis.z * angular_step).normalized()
	var z_minus_direction := (radial_up - radial_basis.z * angular_step).normalized()

	var x_plus_value = earth_world.get_surface_point(x_plus_direction)
	var x_minus_value = earth_world.get_surface_point(x_minus_direction)
	var z_plus_value = earth_world.get_surface_point(z_plus_direction)
	var z_minus_value = earth_world.get_surface_point(z_minus_direction)
	if not x_plus_value is Vector3 or not x_minus_value is Vector3:
		return {}
	if not z_plus_value is Vector3 or not z_minus_value is Vector3:
		return {}

	var x_plus := Vector3(x_plus_value)
	var x_minus := Vector3(x_minus_value)
	var z_plus := Vector3(z_plus_value)
	var z_minus := Vector3(z_minus_value)
	for point in [x_plus, x_minus, z_plus, z_minus]:
		if not _finite_vec(Vector3(point)):
			return {}

	var x_chord := x_plus - x_minus
	var z_chord := z_plus - z_minus
	if x_chord.length_squared() < 0.000001 or z_chord.length_squared() < 0.000001:
		return {}

	var terrain_normal := x_chord.cross(z_chord).normalized()
	if terrain_normal.dot(radial_up) < 0.0:
		terrain_normal = -terrain_normal
	if not _finite_vec(terrain_normal) or terrain_normal.length_squared() < 0.99:
		return {}

	var terrain_x := x_chord - terrain_normal * x_chord.dot(terrain_normal)
	if terrain_x.length_squared() < 0.000001:
		return {}
	terrain_x = terrain_x.normalized()
	var terrain_z := terrain_x.cross(terrain_normal).normalized()
	if terrain_z.length_squared() < 0.99:
		return {}
	var terrain_basis := Basis(terrain_x, terrain_normal, terrain_z)

	var normal_dot_radial := clampf(terrain_normal.dot(radial_up), -1.0, 1.0)
	var slope_deg := rad_to_deg(acos(normal_dot_radial))
	var elevation_m := float(surface_state.get(
		"elevation_m",
		center_world.length() - planet_radius
	))
	if not is_finite(elevation_m) or not is_finite(slope_deg):
		return {}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"presentation_only": PRESENTATION_ONLY,
		"canonical_direction": radial_up,
		"surface_point_world": center_world,
		"surface_state": surface_state,
		"elevation_m": elevation_m,
		"radial_up": radial_up,
		"terrain_normal": terrain_normal,
		"radial_basis": radial_basis,
		"terrain_basis": terrain_basis,
		"slope_deg": slope_deg,
		"sample_distance_m": sample_distance_m,
		"lod_level": lod_level,
		"surface_point_is_canonical": true,
		"terrain_normal_is_derived_presentation": true,
		"canonical_ecology_position_changed": false,
		"growth_graph_changed": false,
	}
	result["frame_hash"] = _seal(result)
	return result


static func validate(frame: Dictionary) -> bool:
	if frame.is_empty():
		return false
	if String(frame.get("schema", "")) != SCHEMA:
		return false
	if String(frame.get("version", "")) != VERSION:
		return false
	if String(frame.get("revision", "")) != REVISION:
		return false
	if not bool(frame.get("presentation_only", false)):
		return false
	if not bool(frame.get("surface_point_is_canonical", false)):
		return false
	if not bool(frame.get("terrain_normal_is_derived_presentation", false)):
		return false
	if bool(frame.get("canonical_ecology_position_changed", true)):
		return false
	if bool(frame.get("growth_graph_changed", true)):
		return false

	for key in ["canonical_direction", "surface_point_world", "radial_up", "terrain_normal"]:
		var value = frame.get(key)
		if not value is Vector3 or not _finite_vec(Vector3(value)):
			return false
	var radial_up := Vector3(frame["radial_up"])
	var terrain_normal := Vector3(frame["terrain_normal"])
	if absf(radial_up.length() - 1.0) > 0.000001:
		return false
	if absf(terrain_normal.length() - 1.0) > 0.000001:
		return false
	if terrain_normal.dot(radial_up) <= 0.0:
		return false

	for key in ["radial_basis", "terrain_basis"]:
		var value = frame.get(key)
		if not value is Basis:
			return false
		var basis := Basis(value)
		if not _basis_orthonormal(basis):
			return false

	var radial_basis := Basis(frame["radial_basis"])
	var terrain_basis := Basis(frame["terrain_basis"])
	if radial_basis.y.dot(radial_up) < 0.999999:
		return false
	if terrain_basis.y.dot(terrain_normal) < 0.999999:
		return false

	var slope_deg := float(frame.get("slope_deg", NAN))
	var sample_distance_m := float(frame.get("sample_distance_m", NAN))
	var elevation_m := float(frame.get("elevation_m", NAN))
	if not is_finite(slope_deg) or slope_deg < 0.0 or slope_deg > 90.0:
		return false
	if not is_finite(sample_distance_m):
		return false
	if sample_distance_m < MIN_SAMPLE_DISTANCE_M or sample_distance_m > MAX_SAMPLE_DISTANCE_M:
		return false
	if not is_finite(elevation_m):
		return false
	if int(frame.get("lod_level", -1)) < 0:
		return false
	if not frame.get("surface_state") is Dictionary:
		return false

	var expected_slope := rad_to_deg(acos(clampf(terrain_normal.dot(radial_up), -1.0, 1.0)))
	if absf(expected_slope - slope_deg) > 0.000001:
		return false

	var frame_hash := String(frame.get("frame_hash", ""))
	return frame_hash.length() == 64 and frame_hash == _seal(frame)


static func _seal(frame: Dictionary) -> String:
	var radial_basis := Basis(frame.get("radial_basis", Basis.IDENTITY))
	var terrain_basis := Basis(frame.get("terrain_basis", Basis.IDENTITY))
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		_vector_token(Vector3(frame.get("canonical_direction", Vector3.ZERO))),
		_vector_token(Vector3(frame.get("surface_point_world", Vector3.ZERO))),
		"%.9f" % float(frame.get("elevation_m", 0.0)),
		_vector_token(Vector3(frame.get("radial_up", Vector3.ZERO))),
		_vector_token(Vector3(frame.get("terrain_normal", Vector3.ZERO))),
		_basis_token(radial_basis),
		_basis_token(terrain_basis),
		"%.9f" % float(frame.get("slope_deg", 0.0)),
		"%.9f" % float(frame.get("sample_distance_m", 0.0)),
		str(int(frame.get("lod_level", -1))),
		str(bool(frame.get("surface_point_is_canonical", false))),
		str(bool(frame.get("terrain_normal_is_derived_presentation", false))),
		str(bool(frame.get("canonical_ecology_position_changed", true))),
		str(bool(frame.get("growth_graph_changed", true))),
	])
	return "|".join(tokens).sha256_text()


static func _up_basis(up: Vector3) -> Basis:
	var helper := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis := helper.cross(up).normalized()
	var z_axis := x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)


static func _basis_orthonormal(basis: Basis) -> bool:
	for axis in [basis.x, basis.y, basis.z]:
		if not _finite_vec(Vector3(axis)):
			return false
		if absf(Vector3(axis).length() - 1.0) > 0.000001:
			return false
	if absf(basis.x.dot(basis.y)) > 0.000001:
		return false
	if absf(basis.x.dot(basis.z)) > 0.000001:
		return false
	if absf(basis.y.dot(basis.z)) > 0.000001:
		return false
	return basis.determinant() > 0.999999


static func _vector_token(value: Vector3) -> String:
	return "%.9f,%.9f,%.9f" % [value.x, value.y, value.z]


static func _basis_token(value: Basis) -> String:
	return "%s;%s;%s" % [
		_vector_token(value.x),
		_vector_token(value.y),
		_vector_token(value.z),
	]


static func _finite_vec(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
