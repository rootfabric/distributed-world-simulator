extends SceneTree

## WP0.1 — headless validator for WORLD PACKS manifests.
##
## Validates pack manifests against res://config/world_packs/pack_schema.v1.json.
##
## Supported JSON Schema subset (sufficient for the WP0.1 contract):
##   type, const, enum, pattern, minLength, minItems, maxItems,
##   uniqueItems, items, required, properties,
##   additionalProperties (boolean only).
## Unknown schema keywords and unknown manifest fields are ignored:
## the WP0.1 contract explicitly allows unknown optional fields.
##
## Headless usage:
##   godot --headless --path <project_dir> --script res://tools/world_packs/validate_pack.gd -- --pack=res://path/to/manifest.json
##   godot --headless --path <project_dir> --script res://tools/world_packs/validate_pack.gd -- --dir=res://config/world_packs/packs
##
## Exit codes:
##   0 = every validated manifest conforms to the schema
##   1 = at least one manifest failed validation
##   2 = usage or IO error (nothing was validated)

const DEFAULT_SCHEMA_PATH: String = "res://config/world_packs/pack_schema.v1.json"

const _TYPE_MAP: Dictionary = {
	"object": TYPE_DICTIONARY,
	"array": TYPE_ARRAY,
	"string": TYPE_STRING,
	"number": TYPE_FLOAT,
	"integer": TYPE_INT,
	"boolean": TYPE_BOOL,
	"null": TYPE_NIL,
}

var _schema: Dictionary = {}


func _init() -> void:
	var options: Dictionary = _parse_options(OS.get_cmdline_user_args())
	if options.is_empty():
		print("WORLD_PACKS_VALIDATE: USAGE ERROR (expected --pack=PATH and/or --dir=DIR)")
		quit(2)
		return
	var schema_path: String = String(options.get("schema", DEFAULT_SCHEMA_PATH))
	_schema = _read_json(schema_path)
	if _schema.is_empty():
		print("WORLD_PACKS_VALIDATE: USAGE ERROR (cannot load schema: %s)" % schema_path)
		quit(2)
		return

	var files: PackedStringArray = PackedStringArray()
	for pack_path in options["packs"]:
		files.append(String(pack_path))
	for dir_path in options["dirs"]:
		var discovered: PackedStringArray = _list_json_files(String(dir_path))
		if discovered.is_empty():
			print("WORLD_PACKS_VALIDATE: USAGE ERROR (no *.json found in: %s)" % String(dir_path))
			quit(2)
			return
		files.append_array(discovered)
	if files.is_empty():
		print("WORLD_PACKS_VALIDATE: USAGE ERROR (nothing to validate)")
		quit(2)
		return

	var failed: int = 0
	for file_path in files:
		if not _validate_file(file_path):
			failed += 1

	if failed == 0:
		print("WORLD_PACKS_VALIDATE: PASS (%d manifest(s))" % files.size())
		quit(0)
	else:
		print("WORLD_PACKS_VALIDATE: FAIL (%d of %d manifest(s) invalid)" % [failed, files.size()])
		quit(1)


func _parse_options(user_args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {
		"packs": PackedStringArray(),
		"dirs": PackedStringArray(),
	}
	for raw_arg in user_args:
		var arg: String = String(raw_arg)
		if not arg.begins_with("--") or arg.find("=") < 0:
			print("WORLD_PACKS_VALIDATE: USAGE ERROR (expected --key=value, got: %s)" % arg)
			return {}
		var split_at: int = arg.find("=")
		var key: String = arg.substr(2, split_at - 2)
		var value: String = arg.substr(split_at + 1)
		match key:
			"pack":
				options["packs"].append(value)
			"dir":
				options["dirs"].append(value)
			"schema":
				options["schema"] = value
			_:
				print("WORLD_PACKS_VALIDATE: USAGE ERROR (unknown option: --%s)" % key)
				return {}
	return options


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("WORLD_PACKS_VALIDATE: IO ERROR (cannot open: %s)" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		print("WORLD_PACKS_VALIDATE: IO ERROR (root is not a JSON object: %s)" % path)
		return {}
	return parsed


func _validate_file(file_path: String) -> bool:
	var manifest: Dictionary = _read_json(file_path)
	if manifest.is_empty():
		print("FAIL %s (unreadable or not a JSON object)" % file_path)
		return false
	var errors: PackedStringArray = PackedStringArray()
	_validate(manifest, _schema, "", errors)
	if errors.is_empty():
		print("PASS %s" % file_path)
		return true
	for error in errors:
		print("FAIL %s: %s" % [file_path, error])
	return false


func _validate(instance: Variant, schema: Dictionary, path: String, errors: PackedStringArray) -> void:
	if schema.has("const") and instance != schema["const"]:
		errors.append("%s: expected const %s, got %s" % [
			_label(path), JSON.stringify(schema["const"]), JSON.stringify(instance),
		])
	if schema.has("enum"):
		var matched: bool = false
		for allowed in schema["enum"]:
			if instance == allowed:
				matched = true
				break
		if not matched:
			errors.append("%s: %s is not one of %s" % [
				_label(path), JSON.stringify(instance), JSON.stringify(schema["enum"]),
			])
	if schema.has("type") and not _type_matches(instance, schema["type"]):
		errors.append("%s: expected type %s, got %s" % [
			_label(path), JSON.stringify(schema["type"]), type_string(typeof(instance)),
		])
		return

	match typeof(instance):
		TYPE_STRING:
			_validate_string(instance, schema, path, errors)
		TYPE_ARRAY:
			_validate_array(instance, schema, path, errors)
		TYPE_DICTIONARY:
			_validate_object(instance, schema, path, errors)


func _validate_string(instance: Variant, schema: Dictionary, path: String, errors: PackedStringArray) -> void:
	var value: String = String(instance)
	if schema.has("pattern"):
		var regex: RegEx = RegEx.create_from_string(String(schema["pattern"]))
		if regex == null:
			errors.append("%s: schema pattern is invalid: %s" % [_label(path), String(schema["pattern"])])
		elif regex.search(value) == null:
			errors.append("%s: %s does not match pattern %s" % [
				_label(path), JSON.stringify(instance), String(schema["pattern"]),
			])
	if schema.has("minLength") and value.length() < int(schema["minLength"]):
		errors.append("%s: string shorter than minLength=%d" % [_label(path), int(schema["minLength"])])


func _validate_array(instance: Variant, schema: Dictionary, path: String, errors: PackedStringArray) -> void:
	var array: Array = instance
	if schema.has("minItems") and array.size() < int(schema["minItems"]):
		errors.append("%s: array has %d item(s), minItems=%d" % [
			_label(path), array.size(), int(schema["minItems"]),
		])
	if schema.has("maxItems") and array.size() > int(schema["maxItems"]):
		errors.append("%s: array has %d item(s), maxItems=%d" % [
			_label(path), array.size(), int(schema["maxItems"]),
		])
	if bool(schema.get("uniqueItems", false)):
		var seen: Dictionary = {}
		for element in array:
			var key: String = JSON.stringify(element)
			if seen.has(key):
				errors.append("%s: duplicate array item %s" % [_label(path), key])
			seen[key] = true
	if schema.has("items") and typeof(schema["items"]) == TYPE_DICTIONARY:
		for index in array.size():
			_validate(array[index], schema["items"], "%s[%d]" % [path, index], errors)


func _validate_object(instance: Variant, schema: Dictionary, path: String, errors: PackedStringArray) -> void:
	var object: Dictionary = instance
	var properties: Dictionary = schema.get("properties", {})
	for required_key in schema.get("required", []):
		if not object.has(String(required_key)):
			errors.append("%s: missing required field '%s'" % [_label(path), String(required_key)])
	for property_name in properties:
		if object.has(String(property_name)):
			_validate(
				object[String(property_name)],
				properties[property_name],
				_join(path, String(property_name)),
				errors
			)
	if schema.has("additionalProperties") and bool(schema["additionalProperties"]) == false:
		for key in object:
			if not properties.has(String(key)):
				errors.append("%s: unknown field '%s' is not allowed" % [_label(path), String(key)])


func _type_matches(instance: Variant, type_decl: Variant) -> bool:
	if typeof(type_decl) == TYPE_ARRAY:
		for type_name in type_decl:
			if _single_type_matches(instance, String(type_name)):
				return true
		return false
	return _single_type_matches(instance, String(type_decl))


func _single_type_matches(instance: Variant, type_name: String) -> bool:
	if not _TYPE_MAP.has(type_name):
		return false
	var expected: int = int(_TYPE_MAP[type_name])
	var actual: int = typeof(instance)
	if expected == TYPE_FLOAT:
		return actual == TYPE_FLOAT or actual == TYPE_INT
	return actual == expected


func _label(path: String) -> String:
	return path if not path.is_empty() else "<root>"


func _join(path: String, key: String) -> String:
	return key if path.is_empty() else "%s.%s" % [path, key]


func _list_json_files(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		print("WORLD_PACKS_VALIDATE: IO ERROR (cannot open dir: %s)" % dir_path)
		return result
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			if dir_path.ends_with("/"):
				result.append(dir_path + entry)
			else:
				result.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result
