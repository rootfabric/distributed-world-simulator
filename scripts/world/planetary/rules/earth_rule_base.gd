extends RefCounted

var descriptor: Dictionary = {}
var world_seed: int = 0


func setup(descriptor_value: Dictionary, seed_value: int) -> void:
	descriptor = descriptor_value.duplicate(true)
	world_seed = seed_value
	configure()


func configure() -> void:
	pass


func get_rule_id() -> String:
	return String(descriptor.get("id", get_script().resource_path.get_file()))


func get_stage() -> int:
	return int(descriptor.get("stage", 0))


func get_lod_max() -> int:
	return int(descriptor.get("lod_max", 2))


func is_enabled() -> bool:
	return bool(descriptor.get("enabled", true))


func get_parameter(name: String, default_value):
	var parameters = descriptor.get("parameters", {})
	if parameters is Dictionary:
		return parameters.get(name, default_value)
	return default_value


func get_requires() -> Array[String]:
	return []


func get_writes() -> Array[String]:
	return []


func apply(_state: Dictionary) -> void:
	pass
