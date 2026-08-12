extends RefCounted

const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_far_representation_materialization.v1"
const VERSION := "1.0.0"

static func build(representation: Dictionary) -> Dictionary:
	if not bool(representation.get("success", false)):
		return _failure("ECO_PH5_S3_REPRESENTATION_REJECTED")
	var tier := String(representation.get("tier", ""))
	if not tier in [Representation.TIER_2_CANOPY, Representation.TIER_3_IMPOSTOR, Representation.TIER_4_POPULATION_ONLY]:
		return _failure("ECO_PH5_S3_FAR_MATERIALIZER_UNSUPPORTED_TIER", {"tier": tier})

	var mesh: Mesh = null
	var origin := Vector3.ZERO
	var primitive_count := 0
	var billboard := false
	if tier == Representation.TIER_2_CANOPY:
		var canopy: Dictionary = representation.get("canopy", {})
		var center := _vec3(Array(canopy.get("center", [0.0, 0.0, 0.0])))
		var radius := _finite_positive(float(canopy.get("radius_xz_m", 0.0)), 0.05)
		var height := _finite_positive(float(canopy.get("height_m", 0.0)), radius * 2.0)
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = maxf(height, radius * 2.0)
		sphere.radial_segments = 12
		sphere.rings = 6
		mesh = sphere
		origin = center
		primitive_count = 1
	elif tier == Representation.TIER_3_IMPOSTOR:
		var bounds: Dictionary = representation.get("bounds", {})
		var radius := _finite_positive(float(bounds.get("radius_xz_m", 0.0)), 0.05)
		var height := _finite_positive(float(bounds.get("height_m", 0.0)), 0.10)
		var quad := QuadMesh.new()
		quad.size = Vector2(radius * 2.0, height)
		var material := StandardMaterial3D.new()
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad.material = material
		mesh = quad
		origin = Vector3(0.0, height * 0.5, 0.0)
		primitive_count = 1
		billboard = true

	var result := {
		"success": true,
		"error_code": "",
		"schema": SCHEMA,
		"version": VERSION,
		"derived_representation": true,
		"ecological_truth_hash": String(representation.get("ecological_truth_hash", "")),
		"representation_hash": String(representation.get("representation_hash", "")),
		"tier": tier,
		"mesh": mesh,
		"origin": origin,
		"primitive_count": primitive_count,
		"billboard": billboard,
		"individual_node_required": tier != Representation.TIER_4_POPULATION_ONLY,
	}
	result["materialization_hash"] = compute_hash(result)
	return result

static func compute_hash(materialization: Dictionary) -> String:
	var mesh: Mesh = materialization.get("mesh")
	var size := Vector3.ZERO
	var billboard_mode := BaseMaterial3D.BILLBOARD_DISABLED
	if mesh != null:
		size = mesh.get_aabb().size
		if mesh.material is BaseMaterial3D:
			billboard_mode = (mesh.material as BaseMaterial3D).billboard_mode
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(materialization.get("ecological_truth_hash", "")),
		String(materialization.get("representation_hash", "")),
		String(materialization.get("tier", "")),
		str(int(materialization.get("primitive_count", 0))),
		str(int(materialization.get("billboard", false))),
		str(int(billboard_mode)),
		"%.9f,%.9f,%.9f" % [size.x, size.y, size.z],
	])).sha256_text()

static func _finite_positive(value: float, fallback: float) -> float:
	return value if is_finite(value) and value > 0.0 else fallback

static func _vec3(values: Array) -> Vector3:
	if values.size() != 3:
		return Vector3.ZERO
	var result := Vector3(float(values[0]), float(values[1]), float(values[2]))
	if not is_finite(result.x) or not is_finite(result.y) or not is_finite(result.z):
		return Vector3.ZERO
	return result

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
