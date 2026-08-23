extends SceneTree

## P6.7 zero-write fence extension: within scripts/runtime/networked_gameplay/p6/,
## ONLY p6_persistence_owner.gd (the single persistence owner
## "p6-owner/directory-one-writer") may touch the filesystem. Every other p6_*
## runtime module must hold ZERO file-write references.

const P6_DIR := "res://scripts/runtime/networked_gameplay/p6"
const OWNER_FILE_NAME := "p6_persistence_owner.gd"

const FORBIDDEN_TOKENS: Array[String] = [
	"FileAccess",
	"ConfigFile",
	"DirAccess",
	"ResourceSaver",
	"store_",
	"save(",
	"open(",
]

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.7-zero-write-fence][FAIL] %s" % message)


func _init() -> void:
	var dir := DirAccess.open(P6_DIR)
	_assert(dir != null, "p6 runtime directory not readable")
	if dir == null:
		quit(1)
		return
	var scanned: Array[String] = []
	var owner_content := ""
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with("p6_") and entry.ends_with(".gd"):
			var content := FileAccess.get_file_as_string(P6_DIR + "/" + entry)
			if String(entry) == OWNER_FILE_NAME:
				owner_content = content
			else:
				scanned.append(entry)
				for token in FORBIDDEN_TOKENS:
					if content.find(token) != -1:
						_assert(false, "%s contains forbidden file-write token '%s'" % [entry, token])
		entry = dir.get_next()
	dir.list_dir_end()

	# The fence must actually see the modules it guards...
	_assert(scanned.size() >= 6, "fence scanned too few p6 modules (%d)" % scanned.size())
	_assert(scanned.has("p6_outpost_state.gd"), "outpost state module not scanned")
	_assert(scanned.has("p6_ownership_map.gd"), "ownership map module not scanned")
	# ...and the single exception must exist and really be the writer.
	_assert(not owner_content.is_empty(), "persistence owner file missing from p6 runtime dir")
	_assert(owner_content.find("FileAccess") != -1, "persistence owner unexpectedly holds no file access")

	if failures.is_empty():
		print("[p6.7-zero-write-fence] all %d assertions passed (%d modules scanned, 1 owner exception)" % [assertions, scanned.size()])
		print("[p6.7-zero-write-fence][stage] P6_ZERO_WRITE_FENCE_PASS")
		quit(0)
	else:
		print("[p6.7-zero-write-fence] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
