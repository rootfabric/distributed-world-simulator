extends SceneTree

## EG5 zero-write fence: locator + probe simulator modules hold ZERO
## references to product canonical mutation surfaces and forbidden paths.
## Mirrors the EG4 / EG4.5 fence pattern.

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const FORBIDDEN_TOKENS: Array[String] = [
	"canonical_multiplayer_item_graph",
	"networked_gameplay_service",
	"handle_canonical_item_command",
	"submit_movement_intent",
	"create_canonical_item_graph_snapshot",
	"canonical_item_graph",
	"persistence_save",
	"persistence_load",
	"private_save",
	"persistence::",
]

const FORBIDDEN_PATHS: Array[String] = [
	"scripts/persistence/",
	"scripts/runtime/networked_gameplay/m7/",
]

const EG5_PATTERNS: Array[String] = [
	"scripts/network/gateway/runtime/eg5_*.gd",
]

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg5-fence][FAIL] %s" % message)


func _expand_patterns() -> Array[String]:
	var files: Array[String] = []
	for pattern in EG5_PATTERNS:
		var parts2: PackedStringArray = pattern.split("/")
		var dir_path := "res://" + "/".join(parts2.slice(0, parts2.size() - 1))
		var glob := parts2[parts2.size() - 1]
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var entry := d.get_next()
		while entry != "":
			if not d.current_is_dir() and _match_glob(entry, glob):
				files.append(dir_path.trim_prefix("res://") + "/" + entry)
			entry = d.get_next()
		d.list_dir_end()
	return files


func _match_glob(name: String, glob: String) -> bool:
	if glob == "*":
		return true
	var star := glob.find("*")
	if star == -1:
		return name == glob
	var prefix := glob.substr(0, star)
	var suffix := glob.substr(star + 1)
	if not name.begins_with(prefix):
		return false
	if not name.ends_with(suffix):
		return false
	return name.length() >= prefix.length() + suffix.length()


func _init() -> void:
	var files: Array[String] = _expand_patterns()
	_assert(files.size() > 0, "EG5 fence pattern matched zero files")
	var per_file_assertions: int = 0
	for file_path in files:
		var content: String = FileAccess.get_file_as_string(file_path)
		if content.is_empty():
			_assert(false, "could not read %s" % file_path)
			continue
		for token in FORBIDDEN_TOKENS:
			if content.find(token) != -1:
				_assert(false, "%s contains forbidden token %s" % [file_path, token])
				per_file_assertions += 1
		for forbidden_path in FORBIDDEN_PATHS:
			if file_path.find(forbidden_path) != -1:
				_assert(false, "%s lives under forbidden path %s" % [file_path, forbidden_path])
				per_file_assertions += 1
		_assert(true, "%s scanned (%d tokens, %d paths)" % [file_path, FORBIDDEN_TOKENS.size(), FORBIDDEN_PATHS.size()])
		per_file_assertions += 1
	var summary := {
		"test": "eg5_zero_write_fence",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg5-fence] L0 PASS (%d assertions, %d files scanned)" % [assertions, files.size()])
		quit(0)
	else:
		print("[eg5-fence] L0 FAIL")
		quit(1)
