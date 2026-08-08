extends SceneTree

const HeadClipMaterial = preload("res://scripts/characters/equipment/quaternius_head_clip_material.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "SyntheticFusedBody"
	mesh_instance.mesh = BoxMesh.new()
	var source := StandardMaterial3D.new()
	source.resource_name = "SyntheticSkin"
	source.albedo_color = Color(0.72, 0.51, 0.38, 1.0)
	source.roughness = 0.63
	source.metallic = 0.07
	source.normal_scale = 0.85
	mesh_instance.material_override = source
	root.add_child(mesh_instance)

	var result: Dictionary = HeadClipMaterial.create_from_mesh(mesh_instance, 1.4836)
	_assert(bool(result.get("success", false)), "Synthetic head clip material creation failed")
	var details: Dictionary = result.get("details", {})
	var material = details.get("material")
	_assert(material is ShaderMaterial, "Head clip did not return ShaderMaterial")
	_assert(String(details.get("mesh_name", "")) == "SyntheticFusedBody", "Head clip report lost mesh identity")
	_assert(int(details.get("surface_count", 0)) == 1, "Head clip contract expects one fused surface")
	_assert(String(details.get("source_material_class", "")) == "StandardMaterial3D", "Head clip did not use material_override as source")
	_assert(String(details.get("source_material_name", "")) == "SyntheticSkin", "Head clip source material name mismatch")
	_assert(bool(details.get("opaque_discard", false)), "Head clip must remain in opaque discard path")
	_assert(not bool(details.get("writes_alpha", true)), "Head clip must not depend on transparent ALPHA path")

	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		_assert(shader_material.shader != null, "Head clip ShaderMaterial has no Shader")
		_assert(shader_material.shader != null and shader_material.shader.code.contains("discard"), "Head clip shader does not discard body fragments")
		_assert(shader_material.shader != null and shader_material.shader.code.contains("base_rest_y = VERTEX.y"), "Head clip shader lost model-space clip coordinate")
		_assert(is_equal_approx(float(shader_material.get_shader_parameter("clip_local_y")), 1.4836), "Head clip Y parameter mismatch")
		var tint: Color = shader_material.get_shader_parameter("albedo_tint")
		_assert(tint.is_equal_approx(source.albedo_color), "Head clip did not preserve albedo tint")
		_assert(is_equal_approx(float(shader_material.get_shader_parameter("roughness_value")), source.roughness), "Head clip did not preserve roughness")
		_assert(is_equal_approx(float(shader_material.get_shader_parameter("metallic_value")), source.metallic), "Head clip did not preserve metallic")
		_assert(is_equal_approx(float(shader_material.get_shader_parameter("normal_scale_value")), source.normal_scale), "Head clip did not preserve normal scale")

	var multi_surface := MeshInstance3D.new()
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _triangle_arrays(-0.5))
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _triangle_arrays(0.5))
	multi_surface.mesh = array_mesh
	multi_surface.material_override = source
	root.add_child(multi_surface)
	var rejected: Dictionary = HeadClipMaterial.create_from_mesh(multi_surface, 0.0)
	_assert(not bool(rejected.get("success", true)), "Multi-surface fused body was unexpectedly accepted")
	_assert(String(rejected.get("code", "")) == "HEAD_CLIP_EXPECTS_SINGLE_SURFACE", "Multi-surface rejection code mismatch")

	mesh_instance.queue_free()
	multi_surface.queue_free()
	_finish()


func _triangle_arrays(y: float) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.1, y, 0.0),
		Vector3(0.1, y, 0.0),
		Vector3(0.0, y + 0.1, 0.0),
	])
	return arrays


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH7.8 Quaternius head clip material: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH7.8 Quaternius head clip material: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)