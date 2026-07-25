extends RefCounted

const NEAR_ALBEDO_PATH := "res://assets/textures/generated/regolith_near_albedo.png"
const NEAR_NORMAL_PATH := "res://assets/textures/generated/regolith_near_normal.png"
const NEAR_ROUGHNESS_PATH := "res://assets/textures/generated/regolith_near_roughness.png"
const MID_ALBEDO_PATH := "res://assets/textures/generated/regolith_mid_albedo.png"
const MID_NORMAL_PATH := "res://assets/textures/generated/regolith_mid_normal.png"
const MID_ROUGHNESS_PATH := "res://assets/textures/generated/regolith_mid_roughness.png"
const GLOBAL_ALBEDO_PATH := "res://assets/textures/generated/regolith_global_albedo.png"
const GLOBAL_NORMAL_PATH := "res://assets/textures/generated/regolith_global_normal.png"
const GLOBAL_ROUGHNESS_PATH := "res://assets/textures/generated/regolith_global_roughness.png"
const ROCK_ALBEDO_PATH := "res://assets/textures/generated/rock_surface_albedo.png"
const ROCK_NORMAL_PATH := "res://assets/textures/generated/rock_surface_normal.png"
const ROCK_ROUGHNESS_PATH := "res://assets/textures/generated/rock_surface_roughness.png"

const STYLE_REALISTIC: int = 0
const STYLE_SURVEY: int = 1
const STYLE_RAW: int = 2

var style_index: int = STYLE_REALISTIC
var local_materials: Array[StandardMaterial3D] = []
var regional_materials: Array[StandardMaterial3D] = []
var global_materials: Array[StandardMaterial3D] = []
var rock_materials: Array[StandardMaterial3D] = []


func setup() -> void:
	local_materials = [
		_create_surface_material(NEAR_ALBEDO_PATH, NEAR_NORMAL_PATH, NEAR_ROUGHNESS_PATH, 1.35, 0.91, 1.00),
		_create_surface_material(NEAR_ALBEDO_PATH, NEAR_NORMAL_PATH, NEAR_ROUGHNESS_PATH, 2.05, 0.96, 1.10),
		_create_raw_material(),
	]
	regional_materials = [
		_create_surface_material(MID_ALBEDO_PATH, MID_NORMAL_PATH, MID_ROUGHNESS_PATH, 0.82, 0.94, 0.96),
		_create_surface_material(MID_ALBEDO_PATH, MID_NORMAL_PATH, MID_ROUGHNESS_PATH, 1.20, 0.98, 1.08),
		_create_raw_material(),
	]
	global_materials = [
		_create_surface_material(GLOBAL_ALBEDO_PATH, GLOBAL_NORMAL_PATH, GLOBAL_ROUGHNESS_PATH, 0.24, 0.96, 0.90),
		_create_surface_material(GLOBAL_ALBEDO_PATH, GLOBAL_NORMAL_PATH, GLOBAL_ROUGHNESS_PATH, 0.42, 0.98, 1.04),
		_create_raw_material(),
	]
	rock_materials = [
		_create_surface_material(ROCK_ALBEDO_PATH, ROCK_NORMAL_PATH, ROCK_ROUGHNESS_PATH, 1.25, 0.88, 0.92),
		_create_surface_material(ROCK_ALBEDO_PATH, ROCK_NORMAL_PATH, ROCK_ROUGHNESS_PATH, 1.85, 0.94, 1.02),
		_create_raw_material(),
	]


func cycle_style() -> int:
	style_index = (style_index + 1) % 3
	return style_index


func get_local_material() -> StandardMaterial3D:
	return local_materials[style_index]


func get_regional_material() -> StandardMaterial3D:
	return regional_materials[style_index]


func get_global_material() -> StandardMaterial3D:
	return global_materials[style_index]


func get_rock_material() -> StandardMaterial3D:
	return rock_materials[style_index]


func get_style_name() -> String:
	match style_index:
		STYLE_REALISTIC:
			return "NASA-like realistic"
		STYLE_SURVEY:
			return "Survey high contrast"
		_:
			return "Raw geometry"


func _create_surface_material(
	albedo_path: String,
	normal_path: String,
	roughness_path: String,
	normal_strength: float,
	roughness_value: float,
	brightness: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(brightness, brightness, brightness, 1.0)
	material.albedo_texture = load(albedo_path)
	material.vertex_color_use_as_albedo = true
	material.normal_enabled = true
	material.normal_texture = load(normal_path)
	material.normal_scale = normal_strength
	material.roughness = roughness_value
	material.roughness_texture = load(roughness_path)
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_repeat = true
	return material


func _create_raw_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
