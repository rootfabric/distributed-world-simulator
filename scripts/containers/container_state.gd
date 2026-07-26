extends RefCounted

var container_id: String = ""
var owner_kind: String = "SYSTEM"
var owner_id: String = ""
var slot_count: int = 0
var maximum_mass_kg: float = INF
var maximum_volume_l: float = INF
var allow_nested_containers: bool = true
var maximum_nested_depth: int = 8
var accepted_tags: PackedStringArray = PackedStringArray()
var item_ids: Array[String] = []
var revision: int = 0


func _init(data: Dictionary = {}) -> void:
	container_id = String(data.get("container_id", ""))
	owner_kind = String(data.get("owner_kind", "SYSTEM"))
	owner_id = String(data.get("owner_id", ""))
	slot_count = maxi(0, int(data.get("slot_count", 0)))
	maximum_mass_kg = float(data.get("maximum_mass_kg", INF))
	maximum_volume_l = float(data.get("maximum_volume_l", INF))
	allow_nested_containers = bool(data.get("allow_nested_containers", true))
	maximum_nested_depth = maxi(0, int(data.get("maximum_nested_depth", 8)))
	accepted_tags = PackedStringArray(data.get("accepted_tags", []))
	for item_id in data.get("item_ids", []):
		item_ids.append(String(item_id))
	revision = int(data.get("revision", 0))


func has_free_slot() -> bool:
	return slot_count == 0 or item_ids.size() < slot_count


func to_dict() -> Dictionary:
	return {
		"container_id": container_id,
		"owner_kind": owner_kind,
		"owner_id": owner_id,
		"slot_count": slot_count,
		"maximum_mass_kg": maximum_mass_kg,
		"maximum_volume_l": maximum_volume_l,
		"allow_nested_containers": allow_nested_containers,
		"maximum_nested_depth": maximum_nested_depth,
		"accepted_tags": Array(accepted_tags),
		"item_ids": item_ids.duplicate(),
		"revision": revision,
	}
