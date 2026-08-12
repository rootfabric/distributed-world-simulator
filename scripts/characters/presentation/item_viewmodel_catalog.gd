class_name ItemViewmodelCatalog
extends RefCounted

const VISUAL_BOX := "BOX"
const VISUAL_CYLINDER := "CYLINDER"
const VISUAL_SPHERE := "SPHERE"
const VISUAL_CAPSULE := "CAPSULE"
const VALID_VISUAL_KINDS: Array[String] = [
	VISUAL_BOX,
	VISUAL_CYLINDER,
	VISUAL_SPHERE,
	VISUAL_CAPSULE,
]


func resolve(
	definition_id: String,
	tags = [],
	metadata: Dictionary = {},
	world_scene_path: String = "",
	fallback_color: Color = Color(0.65, 0.68, 0.72, 1.0)
) -> Dictionary:
	var normalized_id := _normalize_token(definition_id)
	var normalized_tags := _normalize_tags(tags)
	var profile_id := "generic_box"
	var visual_kind := VISUAL_BOX
	var dimensions := Vector3(0.13, 0.17, 0.30)
	var radius := 0.06
	var height := 0.28
	var source := "DEFAULT"

	var metadata_kind := String(metadata.get("held_visual_kind", "")).strip_edges().to_upper()
	if metadata_kind in VALID_VISUAL_KINDS:
		visual_kind = metadata_kind
		profile_id = String(metadata.get("held_visual_profile", "metadata")).strip_edges()
		if profile_id.is_empty():
			profile_id = "metadata"
		source = "METADATA"
	elif _contains_any(normalized_id, normalized_tags, ["flashlight", "torch", "lamp"]):
		profile_id = "flashlight"
		visual_kind = VISUAL_CYLINDER
		radius = 0.045
		height = 0.28
		source = "HEURISTIC"
	elif _contains_any(normalized_id, normalized_tags, ["beacon", "signal", "locator"]):
		profile_id = "beacon"
		visual_kind = VISUAL_CYLINDER
		radius = 0.055
		height = 0.24
		source = "HEURISTIC"
	elif _contains_any(normalized_id, normalized_tags, ["backpack", "rucksack", "pack"]):
		profile_id = "backpack"
		visual_kind = VISUAL_BOX
		dimensions = Vector3(0.24, 0.30, 0.12)
		source = "HEURISTIC"
	elif _contains_any(normalized_id, normalized_tags, ["helmet", "headgear"]):
		profile_id = "helmet"
		visual_kind = VISUAL_SPHERE
		radius = 0.12
		height = 0.18
		source = "HEURISTIC"
	elif _contains_any(normalized_id, normalized_tags, ["tool", "wrench", "hammer", "scanner"]):
		profile_id = "hand_tool"
		visual_kind = VISUAL_CAPSULE
		radius = 0.045
		height = 0.30
		source = "HEURISTIC"

	dimensions = _metadata_vector3(metadata, "held_dimensions", dimensions)
	radius = maxf(0.005, float(metadata.get("held_radius", radius)))
	height = maxf(radius * 2.0, float(metadata.get("held_height", height)))
	var color := _metadata_color(metadata, fallback_color)
	var preferred_scene_path := String(metadata.get("held_scene_path", "")).strip_edges()
	if preferred_scene_path.is_empty():
		preferred_scene_path = world_scene_path.strip_edges()

	return {
		"schema": "planet_simulator.item_viewmodel_descriptor.v1",
		"definition_id": definition_id,
		"profile_id": profile_id,
		"visual_kind": visual_kind,
		"dimensions": [dimensions.x, dimensions.y, dimensions.z],
		"radius": radius,
		"height": height,
		"color": [color.r, color.g, color.b, color.a],
		"preferred_scene_path": preferred_scene_path,
		"resolution_source": source,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
	}


func _contains_any(normalized_id: String, normalized_tags: Array[String], needles: Array[String]) -> bool:
	for needle in needles:
		var normalized_needle := _normalize_token(needle)
		if normalized_id.contains(normalized_needle):
			return true
		for tag in normalized_tags:
			if tag.contains(normalized_needle):
				return true
	return false


func _normalize_tags(tags) -> Array[String]:
	var result: Array[String] = []
	for raw_tag in tags:
		result.append(_normalize_token(String(raw_tag)))
	return result


func _normalize_token(value: String) -> String:
	var normalized := value.to_lower()
	for token in ["_", "-", ".", ":", " ", "/", "\\"]:
		normalized = normalized.replace(token, "")
	return normalized


func _metadata_vector3(metadata: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var value: Variant = metadata.get(key)
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


func _metadata_color(metadata: Dictionary, fallback: Color) -> Color:
	var value: Variant = metadata.get("held_color")
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
