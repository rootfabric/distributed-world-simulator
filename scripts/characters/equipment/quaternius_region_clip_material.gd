extends RefCounted

const REGION_TORSO := "body.region.torso"
const REGION_ARMS := "body.region.arms"
const REGION_LEGS := "body.region.legs"
const REGION_FEET := "body.region.feet"

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
uniform bool has_albedo_texture = false;
uniform bool has_normal_texture = false;
uniform bool has_roughness_texture = false;

uniform bool hide_torso = false;
uniform bool hide_arms = false;
uniform bool hide_legs = false;
uniform bool hide_feet = false;
uniform float feet_max_y = 0.54;
uniform float legs_max_y = 1.08;
uniform float torso_min_y = 0.88;
uniform float torso_max_y = 1.57;
uniform float torso_half_x = 0.41;
uniform float arms_min_y = 1.32;
uniform float arms_max_y = 1.58;
uniform float arms_inner_abs_x = 0.31;

varying vec3 base_rest_pos;

void vertex() {
	base_rest_pos = VERTEX;
}

void fragment() {
	float y = base_rest_pos.y;
	float ax = abs(base_rest_pos.x);
	bool discard_fragment = false;

	if (hide_feet && y < feet_max_y) {
		discard_fragment = true;
	}
	if (hide_legs && y >= feet_max_y && y < legs_max_y) {
		discard_fragment = true;
	}
	if (hide_torso && y >= torso_min_y && y < torso_max_y && ax <= torso_half_x) {
		discard_fragment = true;
	}
	if (hide_arms && y >= arms_min_y && y < arms_max_y && ax >= arms_inner_abs_x) {
		discard_fragment = true;
	}
	if (discard_fragment) {
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


static func create_from_mesh(mesh_instance: MeshInstance3D, active_regions: Array[String]) -> Dictionary:
	if mesh_instance == null or mesh_instance.mesh == null:
		return _result(false, "REGION_CLIP_MESH_MISSING")
	if mesh_instance.mesh.get_surface_count() != 1:
		return _result(false, "REGION_CLIP_EXPECTS_SINGLE_SURFACE", {
			"surface_count": mesh_instance.mesh.get_surface_count(),
		})

	var source_material: Material = mesh_instance.material_override
	if source_material == null:
		source_material = mesh_instance.get_surface_override_material(0)
	if source_material == null:
		source_material = mesh_instance.mesh.surface_get_material(0)
	if not source_material is BaseMaterial3D:
		return _result(false, "REGION_CLIP_SOURCE_MATERIAL_UNSUPPORTED", {
			"material_class": source_material.get_class() if source_material != null else "",
		})

	var regions: Array[String] = []
	for raw_region in active_regions:
		var region := String(raw_region)
		if region not in [REGION_TORSO, REGION_ARMS, REGION_LEGS, REGION_FEET]:
			return _result(false, "REGION_CLIP_UNSUPPORTED_REGION", {"body_region": region})
		if region not in regions:
			regions.append(region)
	regions.sort()
	if regions.is_empty():
		return _result(false, "REGION_CLIP_REQUIRES_REGION")

	var body_aabb := mesh_instance.get_aabb()
	var min_y := body_aabb.position.y
	var height := body_aabb.size.y
	var width := body_aabb.size.x
	var feet_max_y := min_y + height * 0.30
	var legs_max_y := min_y + height * 0.60
	var torso_min_y := min_y + height * 0.49
	var torso_max_y := min_y + height * 0.87
	var arms_min_y := min_y + height * 0.73
	var arms_max_y := min_y + height * 0.88
	var torso_half_x := width * 0.22
	var arms_inner_abs_x := width * 0.17

	var base := source_material as BaseMaterial3D
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.resource_name = "QuaterniusRegionClip"
	material.set_shader_parameter("hide_torso", REGION_TORSO in regions)
	material.set_shader_parameter("hide_arms", REGION_ARMS in regions)
	material.set_shader_parameter("hide_legs", REGION_LEGS in regions)
	material.set_shader_parameter("hide_feet", REGION_FEET in regions)
	material.set_shader_parameter("feet_max_y", feet_max_y)
	material.set_shader_parameter("legs_max_y", legs_max_y)
	material.set_shader_parameter("torso_min_y", torso_min_y)
	material.set_shader_parameter("torso_max_y", torso_max_y)
	material.set_shader_parameter("torso_half_x", torso_half_x)
	material.set_shader_parameter("arms_min_y", arms_min_y)
	material.set_shader_parameter("arms_max_y", arms_max_y)
	material.set_shader_parameter("arms_inner_abs_x", arms_inner_abs_x)
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
		"active_regions": regions,
		"mesh_name": String(mesh_instance.name),
		"surface_count": mesh_instance.mesh.get_surface_count(),
		"source_material_class": source_material.get_class(),
		"source_material_name": String(source_material.resource_name),
		"thresholds": {
			"feet_max_y": feet_max_y,
			"legs_max_y": legs_max_y,
			"torso_min_y": torso_min_y,
			"torso_max_y": torso_max_y,
			"torso_half_x": torso_half_x,
			"arms_min_y": arms_min_y,
			"arms_max_y": arms_max_y,
			"arms_inner_abs_x": arms_inner_abs_x
		},
		"opaque_discard": true,
		"writes_alpha": false,
	})


static func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
