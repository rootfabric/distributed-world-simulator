extends RefCounted

const CONFIG_PATH: String = "res://config/generation/earth_rules.json"
const INITIAL_FIELDS := [
	"direction",
	"latitude_rad",
	"longitude_rad",
	"lod_level",
]

var rules: Array = []
var validation_errors: Array[String] = []
var seed: int = 0
var sample_count: int = 0
var last_batch_label: String = "-"
var last_batch_sample_count: int = 0
var last_batch_elapsed_ms: float = 0.0
var batch_started_usec: int = 0
var batch_started_sample_count: int = 0


func setup(config_path: String = CONFIG_PATH) -> bool:
	rules.clear()
	validation_errors.clear()
	var config: Dictionary = _load_json(config_path)
	if config.is_empty():
		validation_errors.append("Cannot load rule pipeline config: %s" % config_path)
		return false
	seed = int(config.get("seed", 20260726))
	var descriptors = config.get("rules", [])
	if not descriptors is Array:
		validation_errors.append("The rules field must be an array")
		return false
	var sorted_descriptors: Array = descriptors.duplicate(true)
	_sort_descriptors_by_stage(sorted_descriptors)
	for descriptor_value in sorted_descriptors:
		if not descriptor_value is Dictionary:
			continue
		var descriptor: Dictionary = descriptor_value
		if not bool(descriptor.get("enabled", true)):
			continue
		var script_path: String = String(descriptor.get("script", ""))
		var rule_script = load(script_path)
		if rule_script == null:
			validation_errors.append("Cannot load rule script: %s" % script_path)
			continue
		var rule = rule_script.new()
		rule.setup(descriptor, seed)
		rules.append(rule)
	_validate_contracts()
	return validation_errors.is_empty()


func sample(direction_value: Vector3, lod_level: int = 0) -> Dictionary:
	var direction: Vector3 = direction_value.normalized()
	var state := {
		"direction": direction,
		"latitude_rad": asin(clampf(direction.y, -1.0, 1.0)),
		"longitude_rad": atan2(direction.z, direction.x),
		"lod_level": lod_level,
	}
	for rule in rules:
		if lod_level <= rule.get_lod_max():
			rule.apply(state)
	sample_count += 1
	return state


func begin_batch(label: String) -> void:
	last_batch_label = label
	batch_started_usec = Time.get_ticks_usec()
	batch_started_sample_count = sample_count


func end_batch() -> Dictionary:
	last_batch_sample_count = sample_count - batch_started_sample_count
	last_batch_elapsed_ms = float(Time.get_ticks_usec() - batch_started_usec) / 1000.0
	return get_performance_snapshot()


func get_performance_snapshot() -> Dictionary:
	return {
		"active_rule_count": rules.size(),
		"total_sample_count": sample_count,
		"last_batch_label": last_batch_label,
		"last_batch_sample_count": last_batch_sample_count,
		"last_batch_elapsed_ms": last_batch_elapsed_ms,
		"validation_errors": validation_errors.duplicate(),
	}


func get_active_rule_ids() -> Array[String]:
	var result: Array[String] = []
	for rule in rules:
		result.append(rule.get_rule_id())
	return result


func get_validation_errors() -> Array[String]:
	return validation_errors.duplicate()


func biome_name(code: int) -> String:
	match code:
		0:
			return "ocean"
		1:
			return "river_or_lake"
		2:
			return "desert"
		3:
			return "tundra"
		4:
			return "forest"
		5:
			return "grassland"
		6:
			return "alpine_snow"
		7:
			return "rock"
		_:
			return "unknown"


func _validate_contracts() -> void:
	var available: Dictionary = {}
	var writer_by_field: Dictionary = {}
	for field_name in INITIAL_FIELDS:
		available[String(field_name)] = true
	for rule in rules:
		var rule_id: String = rule.get_rule_id()
		for required_field in rule.get_requires():
			if not available.has(required_field):
				validation_errors.append(
					"Rule '%s' requires missing field '%s'" % [rule_id, required_field]
				)
		for written_field in rule.get_writes():
			if writer_by_field.has(written_field):
				validation_errors.append(
					"Field '%s' is written by both '%s' and '%s'" % [
						written_field,
						String(writer_by_field[written_field]),
						rule_id,
					]
				)
			writer_by_field[written_field] = rule_id
			available[written_field] = true


func _sort_descriptors_by_stage(values: Array) -> void:
	for index in range(1, values.size()):
		var current = values[index]
		var current_stage: int = int(current.get("stage", 0)) if current is Dictionary else 0
		var cursor: int = index - 1
		while cursor >= 0:
			var previous = values[cursor]
			var previous_stage: int = int(previous.get("stage", 0)) if previous is Dictionary else 0
			if previous_stage <= current_stage:
				break
			values[cursor + 1] = previous
			cursor -= 1
		values[cursor + 1] = current


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
