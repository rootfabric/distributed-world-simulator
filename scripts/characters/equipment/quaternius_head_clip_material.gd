extends RefCounted

const SHADER_CODE := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D normal_texture : hint_normal;
uniform sampler2D roughness_texture;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float roughness_value = 1.0;
uniform float metallic_value = 0.0;
uniform float normal_scale_value = 1.0;
uniform float clip_local_y = 1.48;
uniform bool has_albedo_texture = false;
uniform bool has_normal_texture = false;
uniform bool has_roughness_texture = false;

varying float base_rest_y;

void vertex() {
	// Keep the clip plane in imported model/rest coordinates. The character
	// skeleton remains authoritative for animation; this shader only controls
	// presentation visibility of the fused base-body surface.
	base_rest_y = VERTEX.y;
}

void fragment() {
	if (base_rest_y < clip_local_y) {
		discard;
	}

	vec4 base = albedo_tint;
	if (has_albedo_texture) {
		base *= texture(albedo_texture, UV);
	}
	ALBEDO = base.rgb;
	ROUGHNESS = roughness_value;
	if (has_roughness_texture) {
		ROUGHNESS *= texture(roughness_texture, UV).r;
	}
	METALLIC = metallic_value;
	if (has_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale_value;
	}
}
"""


static func create_from_mesh(mesh_instance: MeshInstance3D, clip_local_y: float) -> Dictionary:
	if mesh_instance == null or mesh_instance.mesh == null:
		return _result(false, "HEAD_CLIP_MESH_MISSING")
	if mesh_instance.mesh.get_surface_count() != 1:
		return _result(false, "HEAD_CLIP_EXPECTS_SINGLE_SURFACE", {
			"surface_count": mesh_instance.mesh.get_surface_count(),
		})

	var source_material: Material = mesh_instance.material_override
	if source_material == null:
		source_material = mesh_instance.get_surface_override_material(0)
	if source_material == null:
		source_material = mesh_instance.mesh.surface_get_material(0)
	if not source_material is BaseMaterial3D:
		return _result(false, "HEAD_CLIP_SOURCE_MATERIAL_UNSUPPORTED", {
			"material_class": source_material.get_class() if source_material != null else "",
		})

	var base := source_material as BaseMaterial3D
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.resource_name = "QuaterniusHeadClip"
	material.set_shader_parameter("clip_local_y", clip_local_y)
	material.set_shader_parameter("albedo_tint", base.albedo_color)
	material.set_shader_parameter("roughness_value", base.roughness)
	material.set_shader_parameter("metallic_value", base.metallic)
	material.set_shader_parameter("normal_scale_value", base.normal_scale)

	if base.albedo_texture != null:
		material.set_shader_parameter("albedo_texture", base.albedo_texture)
		material.set_shader_parameter("has_albedo_texture", true)
	if base.normal_enabled and base.normal_texture != null:
		material.set_shader_parameter("normal_texture", base.normal_texture)
		material.set_shader_parameter("has_normal_texture", true)
	if base.roughness_texture != null:
		material.set_shader_parameter("roughness_texture", base.roughness_texture)
		material.set_shader_parameter("has_roughness_texture", true)

	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"material": material,
		"clip_local_y": clip_local_y,
		"mesh_name": String(mesh_instance.name),
		"surface_count": mesh_instance.mesh.get_surface_count(),
		"source_material_class": source_material.get_class(),
		"source_material_name": String(source_material.resource_name),
		"opaque_discard": true,
		"writes_alpha": false,
	})


static func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details,
	}
