extends SceneTree

## P6 R3 zero-write fence: there is NO P6 filesystem-writer exception.
## Durability belongs to scripts/persistence/authoritative_recovery_* via M6.

const P6_DIR := "res://scripts/runtime/networked_gameplay/p6"
const FORBIDDEN_FILESYSTEM_TOKENS: Array[String] = [
	"FileAccess",
	"DirAccess",
	"ConfigFile",
	"ResourceSaver",
	"ResourceLoader",
]

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-zero-write][FAIL] %s" % message)


func _init() -> void:
	var dir := DirAccess.open(P6_DIR)
	_assert(dir != null, "P6 runtime directory is not readable")
	if dir == null:
		_finish()
		return
	var scanned: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with("p6_") and entry.ends_with(".gd"):
			scanned.append(entry)
			var content := FileAccess.get_file_as_string(P6_DIR + "/" + entry)
			for token in FORBIDDEN_FILESYSTEM_TOKENS:
				_assert(content.find(token) == -1, "%s contains forbidden filesystem token %s" % [entry, token])
		entry = dir.get_next()
	dir.list_dir_end()

	_assert(scanned.size() >= 8, "too few P6 runtime modules scanned: %d" % scanned.size())
	_assert(scanned.has("p6_persistence_owner.gd"), "persistence adapter was not scanned")
	_assert(scanned.has("p6_outpost_state.gd"), "projection module was not scanned")
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("[p6-r3-zero-write] all %d assertions passed (%d failures)" % [assertions, failures.size()])
		print("[p6-r3-zero-write][stage] ZERO_PRIVATE_P6_WRITE_PASS")
		quit(0)
	else:
		print("[p6-r3-zero-write] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
