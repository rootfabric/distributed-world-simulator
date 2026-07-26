extends RefCounted

var id: String = ""
var display_name: String = ""
var max_stack: int = 1
var unit_mass_kg: float = 0.0
var external_volume_l: float = 0.0
var tags: PackedStringArray = PackedStringArray()
var world_scene_path: String = ""
var metadata: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	id = String(data.get("id", ""))
	display_name = String(data.get("display_name", id))
	max_stack = maxi(1, int(data.get("max_stack", 1)))
	unit_mass_kg = maxf(0.0, float(data.get("unit_mass_kg", 0.0)))
	external_volume_l = maxf(0.0, float(data.get("external_volume_l", 0.0)))
	tags = PackedStringArray(data.get("tags", []))
	world_scene_path = String(data.get("world_scene_path", ""))
	metadata = Dictionary(data.get("metadata", {})).duplicate(true)


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"max_stack": max_stack,
		"unit_mass_kg": unit_mass_kg,
		"external_volume_l": external_volume_l,
		"tags": Array(tags),
		"world_scene_path": world_scene_path,
		"metadata": metadata.duplicate(true),
	}
