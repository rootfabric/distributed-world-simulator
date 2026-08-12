extends RefCounted

const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_far_representation_materialization.v1"
const VERSION := "1.0.0"

static func build(representation: Dictionary) -> Dictionary:
	if not bool(representation.get("success", false)):
		return _failure("ECO_PH5_S3_REPRESENTATION_REJECTED")
	var tier := String(representation.get("tier", ""))
	if tier not in [Representation.TIER_2_CANOPY, Representation.TIER_3_IMPOSTOR, Representation.TIER_4_POPULATION_ONLY]:
		return _failure("ECO_PH5_S3_FAR_MATERIALIZER_UNSUPPORTED_TIER", {"tier": tier})

	var mesh: Mesh = null
	var multimesh: MultiMesh = null
	var origin := Vector3.ZERO
	var primitive_count := 0
	var instance_count := 0
	var billboard := false
	var population_layout_hash := ""

	if tier == Representation.TIER_2_CANOPY:
		var canopy: Dictionary = representation.get("canopy_descriptor", representation.get("canopy", {}))
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
		var impostor: Dictionary = representation.get("impostor_descriptor", {})
		var bounds: Dictionary = representation.get("bounds", {})
		var width := float(impostor.get("width_m", float(bounds.get("radius_xz_m", 0.0)) * 2.0))
		var height := float(impostor.get("height_m", bounds.get("height_m", 0.0)))
		width = _finite_positive(width, 0.10)
		height = _finite_positive(height, 0.10)
		var quad := QuadMesh.new()
		quad.size = Vector2(width, height)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.12, 0.42, 0.15, 0.92)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad.material = material
		mesh = quad
		var center := _vec3(Array(impostor.get("center", [0.0, height * 0.5, 0.0])))
		origin = Vector3(center.x, height * 0.5, center.z)
		primitive_count = 1
		instance_count = 1
		billboard = true
	elif representation.has("aggregate_descriptor"):
		var aggregate: Dictionary = representation["aggregate_descriptor"]
		var requested_count := int(representation.get("visual_sample_count", 0))
		if requested_count <= 0 or requested_count > Representation.MAX_POPULATION_VISUAL_INSTANCES:
			return _failure("ECO_PH5_S3_INVALID_POPULATION_VISUAL_SAMPLE_COUNT")
		var population := _build_population_multimesh(representation, aggregate, requested_count)
		multimesh = population["multimesh"]
		population_layout_hash = String(population["layout_hash"])
		origin = _vec3(Array(aggregate.get("center", [0.0, 0.0, 0.0])))
		primitive_count = requested_count
		instance_count = requested_count
		billboard = true

	var result := {
		"success": true,
		"error_code": "",
		"schema": SCHEMA,
		"version": VERSION,
		"derived_representation": true,
		"renderer_version": String(representation.get("renderer_version", Representation.RENDERER_VERSION)),
		"ecological_truth_hash": String(representation.get("ecological_truth_hash", "")),
		"source_ecology_identity": String(representation.get("source_ecology_identity", representation.get("ecological_truth_hash", ""))),
		"source_graph_hash": String(representation.get("source_graph_hash", representation.get("ecological_truth_hash", ""))),
		"representation_hash": String(representation.get("representation_hash", "")),
		"profile_id": String(representation.get("profile_id", representation.get("legacy_profile_id", ""))),
		"profile_hash": String(representation.get("profile_hash", "")),
		"deterministic_seed": int(representation.get("deterministic_seed", representation.get("individual_seed", -1))),
		"tier": tier,
		"mesh": mesh,
		"multimesh": multimesh,
		"origin": origin,
		"primitive_count": primitive_count,
		"instance_count": instance_count,
		"billboard": billboard,
		"individual_node_required": tier != Representation.TIER_4_POPULATION_ONLY,
		"population_layout_hash": population_layout_hash,
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
	var multimesh: MultiMesh = materialization.get("multimesh")
	var multimesh_count := 0 if multimesh == null else multimesh.instance_count
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(materialization.get("renderer_version", "")),
		String(materialization.get("ecological_truth_hash", "")),
		String(materialization.get("source_ecology_identity", "")),
		String(materialization.get("source_graph_hash", "")),
		String(materialization.get("representation_hash", "")),
		String(materialization.get("profile_id", "")),
		String(materialization.get("profile_hash", "")),
		str(int(materialization.get("deterministic_seed", -1))),
		String(materialization.get("tier", "")),
		str(int(materialization.get("primitive_count", 0))),
		str(int(materialization.get("instance_count", 0))),
		str(int(materialization.get("billboard", false))),
		str(int(billboard_mode)),
		str(multimesh_count),
		String(materialization.get("population_layout_hash", "")),
		"%.9f,%.9f,%.9f" % [size.x, size.y, size.z],
	])).sha256_text()

static func _build_population_multimesh(representation: Dictionary, aggregate: Dictionary, count: int) -> Dictionary:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.9)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.62, 0.24, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = count
	var center := _vec3(Array(aggregate.get("center", [0.0, 0.0, 0.0])))
	var radius := _finite_positive(float(aggregate.get("radius_m", 0.0)), 0.25)
	var mean_height := _finite_positive(float(aggregate.get("mean_height_m", 0.0)), 0.10)
	var seed_text := "%s|%d" % [String(representation.get("source_ecology_identity", "")), int(representation.get("deterministic_seed", -1))]
	var tokens := PackedStringArray()
	for index in range(count):
		var radial := radius * sqrt(_unit(seed_text, "population/r/%d" % index))
		var angle := TAU * _unit(seed_text, "population/a/%d" % index)
		var scale_value := lerpf(0.45, 1.10, _unit(seed_text, "population/s/%d" % index))
		var origin := center + Vector3(cos(angle) * radial, mean_height * 0.45 * scale_value, sin(angle) * radial)
		var basis := Basis.IDENTITY.scaled(Vector3(scale_value, mean_height * scale_value, scale_value))
		var transform := Transform3D(basis, origin)
		multimesh.set_instance_transform(index, transform)
		tokens.append("%d|%.9f,%.9f,%.9f|%.9f" % [index, origin.x, origin.y, origin.z, scale_value])
	return {"multimesh": multimesh, "layout_hash": "\n".join(tokens).sha256_text()}

static func _unit(seed_text: String, key: String) -> float:
	var digest := (seed_text + "|" + key).sha256_text()
	return float(digest.substr(0, 12).hex_to_int()) / 281474976710655.0

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
