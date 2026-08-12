class_name HeldItemVisualFactory
extends RefCounted


func create_proxy(
	descriptor: Dictionary,
	fallback_color: Color,
	proxy_name: String,
	render_layer_index: int = 0
) -> Dictionary:
	var proxy := MeshInstance3D.new()
	proxy.name = proxy_name
	var visual_kind := String(descriptor.get("visual_kind", "BOX")).to_upper()
	var mesh: PrimitiveMesh = _build_mesh(visual_kind, descriptor)
	if mesh == null:
		proxy.queue_free()
		return _failure("HELD_VISUAL_FACTORY_KIND_UNSUPPORTED", {"visual_kind": visual_kind})
	proxy.mesh = mesh
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if render_layer_index > 0:
		if render_layer_index > 20:
			proxy.queue_free()
			return _failure("HELD_VISUAL_FACTORY_LAYER_INVALID", {"layer": render_layer_index})
		proxy.layers = 0
		proxy.set_layer_mask_value(render_layer_index, true)

	var color := _descriptor_color(descriptor, fallback_color)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	proxy.material_override = material
	proxy.set_meta("held_visual_profile", String(descriptor.get("profile_id", "generic_box")))
	proxy.set_meta("held_visual_kind", visual_kind)

	return {
		"success": true,
		"error_code": "",
		"details": {
			"proxy": proxy,
			"visual_kind": visual_kind,
			"profile_id": String(descriptor.get("profile_id", "generic_box")),
			"preferred_scene_path": String(descriptor.get("preferred_scene_path", "")),
			"procedural_fallback": true,
		},
	}


func apply_local_transform(target: Node3D, transform_descriptor: Dictionary) -> void:
	if target == null:
		return
	target.position = _vector3_value(transform_descriptor.get("position"), target.position)
	target.rotation_degrees = _vector3_value(transform_descriptor.get("rotation_deg"), target.rotation_degrees)
	target.scale = _vector3_value(transform_descriptor.get("scale"), target.scale)


func _build_mesh(visual_kind: String, descriptor: Dictionary) -> PrimitiveMesh:
	match visual_kind:
		"CYLINDER":
			var cylinder := CylinderMesh.new()
			var radius := maxf(0.005, float(descriptor.get("radius", 0.06)))
			cylinder.top_radius = radius
			cylinder.bottom_radius = radius
			cylinder.height = maxf(radius * 2.0, float(descriptor.get("height", 0.28)))
			return cylinder
		"SPHERE":
			var sphere := SphereMesh.new()
			var sphere_radius := maxf(0.005, float(descriptor.get("radius", 0.10)))
			sphere.radius = sphere_radius
			sphere.height = maxf(sphere_radius * 2.0, float(descriptor.get("height", sphere_radius * 2.0)))
			return sphere
		"CAPSULE":
			var capsule := CapsuleMesh.new()
			var capsule_radius := maxf(0.005, float(descriptor.get("radius", 0.05)))
			capsule.radius = capsule_radius
			capsule.height = maxf(capsule_radius * 2.0, float(descriptor.get("height", 0.30)))
			return capsule
		_:
			var box := BoxMesh.new()
			box.size = _vector3_value(descriptor.get("dimensions"), Vector3(0.13, 0.17, 0.30))
			return box


func _descriptor_color(descriptor: Dictionary, fallback: Color) -> Color:
	var value: Variant = descriptor.get("color")
	if value is Color:
		return value as Color
	if value is Array:
		var components: Array = value
		if components.size() >= 4:
			return Color(
				float(components[0]),
				float(components[1]),
				float(components[2]),
				float(components[3])
			)
	return fallback


func _vector3_value(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array:
		var components: Array = value
		if components.size() >= 3:
			return Vector3(
				float(components[0]),
				float(components[1]),
				float(components[2])
			)
	return fallback


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
