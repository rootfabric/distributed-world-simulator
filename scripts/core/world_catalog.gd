extends RefCounted

var _catalog_path: String = ""
var _default_world_id: String = ""
var _worlds: Dictionary = {}
var _validation_errors: Array[String] = []


func load_catalog(path: String) -> bool:
	_catalog_path = path
	_default_world_id = ""
	_worlds.clear()
	_validation_errors.clear()
	if not FileAccess.file_exists(path):
		_validation_errors.append("Каталог миров не найден: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_validation_errors.append("Не удалось открыть каталог миров: %s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_validation_errors.append("Каталог миров должен быть JSON-объектом")
		return false
	_default_world_id = String(parsed.get("default_world", "")).strip_edges().to_lower()
	var raw_worlds = parsed.get("worlds", [])
	if not raw_worlds is Array:
		_validation_errors.append("Поле worlds должно быть массивом")
		return false
	for raw_world in raw_worlds:
		if not raw_world is Dictionary:
			_validation_errors.append("Описание мира должно быть JSON-объектом")
			continue
		_register_world(raw_world)
	if _default_world_id.is_empty() or not _worlds.has(_default_world_id):
		_validation_errors.append(
			"default_world отсутствует в каталоге: %s" % _default_world_id
		)
	for world_id in _worlds.keys():
		_validate_runtime_resource(String(world_id), _worlds[world_id])
	return _validation_errors.is_empty()


func _register_world(raw_world: Dictionary) -> void:
	var world_id: String = String(raw_world.get("id", "")).strip_edges().to_lower()
	if world_id.is_empty():
		_validation_errors.append("У мира отсутствует id")
		return
	if _worlds.has(world_id):
		_validation_errors.append("Повторяющийся id мира: %s" % world_id)
		return
	var runtime_script: String = String(raw_world.get("runtime_script", ""))
	var runtime_scene: String = String(raw_world.get("runtime_scene", ""))
	if runtime_script.is_empty() == runtime_scene.is_empty():
		_validation_errors.append(
			"Мир %s должен задавать ровно один runtime_script или runtime_scene" % world_id
		)
		return
	var definition: Dictionary = raw_world.duplicate(true)
	definition["id"] = world_id
	definition["display_name"] = String(
		definition.get("display_name", world_id)
	)
	definition["description"] = String(definition.get("description", ""))
	var raw_tags = definition.get("tags", [])
	definition["tags"] = raw_tags.duplicate() if raw_tags is Array else []
	definition["options"] = (
		definition.get("options", {}).duplicate(true)
		if definition.get("options", {}) is Dictionary
		else {}
	)
	_worlds[world_id] = definition


func _validate_runtime_resource(world_id: String, definition: Dictionary) -> void:
	var path: String = String(definition.get("runtime_script", ""))
	if path.is_empty():
		path = String(definition.get("runtime_scene", ""))
	if not ResourceLoader.exists(path):
		_validation_errors.append(
			"Runtime-ресурс мира %s не найден: %s" % [world_id, path]
		)


func is_valid() -> bool:
	return _validation_errors.is_empty() and not _worlds.is_empty()


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func get_default_world_id() -> String:
	return _default_world_id


func has_world(world_id: String) -> bool:
	return _worlds.has(world_id.strip_edges().to_lower())


func get_world(world_id: String) -> Dictionary:
	var normalized: String = world_id.strip_edges().to_lower()
	var definition = _worlds.get(normalized, {})
	return definition.duplicate(true) if definition is Dictionary else {}


func list_worlds() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for world_id_value in _worlds.keys():
		var world_id: String = String(world_id_value)
		var definition: Dictionary = _worlds[world_id]
		result.append({
			"id": world_id,
			"display_name": definition.get("display_name", world_id),
			"description": definition.get("description", ""),
			"tags": definition.get("tags", []).duplicate(),
			"default": world_id == _default_world_id,
		})
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("id", "")) < String(second.get("id", ""))
	)
	return result


func create_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.world_catalog.v1",
		"catalog_path": _catalog_path,
		"default_world_id": _default_world_id,
		"world_count": _worlds.size(),
		"worlds": list_worlds(),
		"valid": is_valid(),
		"validation_errors": get_validation_errors(),
	}
