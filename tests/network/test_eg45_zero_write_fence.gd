extends SceneTree

## EG4.5 zero-write fence: gateway-runtime / tools-network / scripts-network-
## gateway additions hold ZERO references to product canonical mutation
## surfaces (canonical_multiplayer_item_graph, networked_gameplay_service,
## persistence, save). Mirrors the EG1 / EG4 fence pattern with the EG4.5
## file set added dynamically.

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const FORBIDDEN_TOKENS: Array[String] = [
	"canonical_multiplayer_item_graph",
	"networked_gameplay_service",
	"handle_canonical_item_command",
	"submit_movement_intent",
	"create_canonical_item_graph_snapshot",
	"canonical_item_graph",
	"item_graph",
	"persistence_save",
	"persistence_load",
	"private_save",
	"persistence::",
]

const FORBIDDEN_PATHS: Array[String] = [
	"scripts/persistence/",
	"scripts/runtime/networked_gameplay/m7/",
]

const EG45_RUNTIME_PATTERNS: Array[String] = [
	"scripts/network/gateway/runtime/eg45_*.gd",
	"scripts/network/gateway/cwip_contract_utils.gd",
	"scripts/network/gateway/effect_commit_request.gd",
	"scripts/network/gateway/effect_commit_result.gd",
	"scripts/network/gateway/cross_world_interaction_intent.gd",
	"scripts/network/gateway/interaction_domain_segment.gd",
	"scripts/network/gateway/collision_query.gd",
	"scripts/network/gateway/collision_proof.gd",
	"scripts/network/gateway/interaction_resolution.gd",
	"scripts/network/gateway/reference_frame_evidence.gd",
	"scripts/network/gateway/interaction_time.gd",
	"tools/network/eg45_*.gd",
]

var assertions := 0
var failures: Array[String] = []

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg45-fence][FAIL] %s" % message)


func _files_matching(pattern: String) -> Array[String]:
	var results: Array[String] = []
	var parts: PackedStringArray = pattern.split("/")
	var dir_path := "/".join(parts.slice(0, parts.size() - 1))
	var glob := parts[parts.size() - 1]
	var d := DirAccess.open(dir_path)
	if d == null:
		return results
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full_path := dir_path + "/" + entry
		if d.current_is_dir():
			if not entry.begins_with("."):
				var sub_pattern := pattern
				results.append_array(_files_matching(sub_pattern.replace(parts[parts.size() - 1], entry + "/" + parts[parts.size() - 1])))
		elif _match_glob(entry, glob):
			results.append(full_path)
		entry = d.get_next()
	d.list_dir_end()
	return results


func _match_glob(name: String, glob: String) -> bool:
	if glob == "*":
		return true
	if glob.begins_with("*"):
		return name.ends_with(glob.substr(1))
	if glob.ends_with("*"):
		return name.begins_with(glob.substr(0, glob.length() - 1))
	return name == glob


func _expand_patterns() -> Array[String]:
	var files: Array[String] = []
	for pattern in EG45_RUNTIME_PATTERNS:
		var parts2: PackedStringArray = pattern.split("/")
		var dir_path := "/".join(parts2.slice(0, parts2.size() - 1))
		var glob := parts2[parts2.size() - 1]
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var entry := d.get_next()
		while entry != "":
			if not d.current_is_dir() and _match_glob(entry, glob):
				files.append(dir_path + "/" + entry)
			entry = d.get_next()
		d.list_dir_end()
	return files


func _init() -> void:
	var files: Array[String] = _expand_patterns()
	_assert(files.size() > 0, "EG4.5 fence pattern matched zero files")
	for file_path in files:
		var content: String = FileAccess.get_file_as_string(file_path)
		if content.is_empty():
			_assert(false, "could not read %s" % file_path)
			continue
		for token in FORBIDDEN_TOKENS:
			if content.find(token) != -1:
				_assert(false, "%s contains forbidden token %s" % [file_path, token])
		for forbidden_path in FORBIDDEN_PATHS:
			if file_path.find(forbidden_path) != -1:
				_assert(false, "%s lives under forbidden path %s" % [file_path, forbidden_path])
	var summary := {
		"test": "eg45_zero_write_fence",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg45-fence] L0 PASS (%d assertions, %d files scanned)" % [assertions, files.size()])
		quit(0)
	else:
		print("[eg45-fence] L0 FAIL")
		quit(1)
