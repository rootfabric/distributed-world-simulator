extends SceneTree

const ASSET_ROOTS: Array[String] = [
	"res://assets/external/quaternius/base_characters",
	"res://assets/external/quaternius/animation_library",
]

var changed_files := 0
var changed_uris := 0
var recovered_export_uris := 0
var scanned_gltf := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for root_path in ASSET_ROOTS:
		_scan_directory(root_path)
	if failures.is_empty():
		print(
			"CH4 Quaternius asset preflight: PASS (%d glTF, %d files normalized, %d URI fixes, %d export-name recoveries)"
			% [scanned_gltf, changed_files, changed_uris, recovered_export_uris]
		)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH4 Quaternius asset preflight: FAIL (%d problems)" % failures.size())
	quit(1)


func _scan_directory(root_path: String) -> void:
	var directory := DirAccess.open(root_path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var path := root_path.path_join(entry)
		if directory.current_is_dir():
			_scan_directory(path)
		elif entry.to_lower().ends_with(".gltf"):
			_normalize_gltf(path)
	directory.list_dir_end()


func _normalize_gltf(path: String) -> void:
	scanned_gltf += 1
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		failures.append("EMPTY_GLTF: %s" % path)
		return
	var uri_regex := RegEx.new()
	var compile_error := uri_regex.compile("\\\"uri\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
	if compile_error != OK:
		failures.append("URI_REGEX_COMPILE_FAILED: %s" % path)
		return
	var matches := uri_regex.search_all(text)
	var replacements: Array[Dictionary] = []
	for match_value in matches:
		var original := match_value.get_string(1)
		if _is_external_or_embedded_uri(original):
			continue
		var resolution := _resolve_relative_uri(path.get_base_dir(), original)
		var canonical := String(resolution.get("uri", ""))
		if canonical.is_empty():
			var reason := String(resolution.get("reason", "UNRESOLVED"))
			var candidates: Array = resolution.get("candidates", [])
			var suffix := ""
			if not candidates.is_empty():
				suffix = " candidates=%s" % JSON.stringify(candidates)
			failures.append("UNRESOLVED_GLTF_URI[%s]: %s -> %s%s" % [reason, path, original, suffix])
			continue
		if bool(resolution.get("recovered_export_name", false)):
			recovered_export_uris += 1
		if canonical != original:
			replacements.append({
				"start": match_value.get_start(1),
				"end": match_value.get_end(1),
				"value": canonical,
			})
	if replacements.is_empty():
		return
	for index in range(replacements.size() - 1, -1, -1):
		var replacement: Dictionary = replacements[index]
		var start_offset := int(replacement.get("start", 0))
		var end_offset := int(replacement.get("end", start_offset))
		text = (
			text.substr(0, start_offset)
			+ String(replacement.get("value", ""))
			+ text.substr(end_offset)
		)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("GLTF_WRITE_FAILED: %s" % path)
		return
	file.store_string(text)
	file.close()
	changed_files += 1
	changed_uris += replacements.size()


func _resolve_relative_uri(base_dir: String, uri: String) -> Dictionary:
	if uri.is_empty() or _is_external_or_embedded_uri(uri):
		return {"uri": uri, "recovered_export_name": false}
	var exact := _canonical_relative_uri_exact(base_dir, uri)
	if not exact.is_empty():
		return {"uri": exact, "recovered_export_name": false}
	return _recover_exported_filename(base_dir, uri)


func _canonical_relative_uri_exact(base_dir: String, uri: String) -> String:
	var normalized_uri := uri.replace("\\", "/")
	var current_dir := base_dir
	var output_segments: Array[String] = []
	for raw_segment in normalized_uri.split("/", false):
		if raw_segment == ".":
			continue
		if raw_segment == "..":
			current_dir = current_dir.get_base_dir()
			output_segments.append("..")
			continue
		var requested_name := String(raw_segment).uri_decode()
		var actual_name := _find_case_insensitive_entry(current_dir, requested_name)
		if actual_name.is_empty():
			return ""
		output_segments.append(actual_name.uri_encode())
		current_dir = current_dir.path_join(actual_name)
	return "/".join(output_segments)


func _recover_exported_filename(base_dir: String, uri: String) -> Dictionary:
	var normalized_uri := uri.replace("\\", "/")
	var requested_leaf := normalized_uri.get_file().uri_decode()
	var alias_leaf := _known_export_filename_alias(requested_leaf)
	if alias_leaf.is_empty() or alias_leaf == requested_leaf:
		return {"uri": "", "reason": "NO_SAFE_ALIAS", "candidates": []}

	var parent_uri := normalized_uri.get_base_dir()
	if parent_uri == ".":
		parent_uri = ""
	var resolved_parent := base_dir
	var canonical_parent := ""
	if not parent_uri.is_empty():
		canonical_parent = _canonical_relative_uri_exact(base_dir, parent_uri)
		if not canonical_parent.is_empty():
			resolved_parent = _apply_relative_path(base_dir, canonical_parent)
		else:
			resolved_parent = ""
	if not resolved_parent.is_empty():
		var local_name := _find_case_insensitive_entry(resolved_parent, alias_leaf)
		if not local_name.is_empty():
			var local_uri := local_name.uri_encode()
			if not canonical_parent.is_empty():
				local_uri = canonical_parent.path_join(local_uri)
			return {"uri": local_uri, "recovered_export_name": true}

	var search_root := _asset_root_for_path(base_dir)
	if search_root.is_empty():
		return {"uri": "", "reason": "ASSET_ROOT_NOT_FOUND", "candidates": []}
	var candidates: Array[String] = []
	_collect_matching_files(search_root, alias_leaf, candidates)
	if candidates.is_empty():
		return {"uri": "", "reason": "ALIAS_TARGET_NOT_FOUND", "candidates": []}
	var best_candidates := _closest_candidates(base_dir, candidates)
	if best_candidates.size() != 1:
		var display_candidates: Array[String] = []
		for candidate in best_candidates:
			display_candidates.append(_relative_uri(base_dir, candidate))
		return {
			"uri": "",
			"reason": "AMBIGUOUS_ALIAS_TARGET",
			"candidates": display_candidates,
		}
	return {
		"uri": _relative_uri(base_dir, best_candidates[0]),
		"recovered_export_name": true,
	}


func _known_export_filename_alias(requested_name: String) -> String:
	var lower := requested_name.to_lower()
	for extension in ["png", "jpg", "jpeg", "webp"]:
		var duplicated_suffix := "_%s.%s" % [extension, extension]
		if lower.ends_with(duplicated_suffix):
			return requested_name.substr(0, requested_name.length() - duplicated_suffix.length()) + "." + extension
	return ""


func _find_case_insensitive_entry(directory_path: String, requested_name: String) -> String:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return ""
	var actual_name := ""
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.nocasecmp_to(requested_name) == 0:
			actual_name = entry
			break
	directory.list_dir_end()
	return actual_name


func _apply_relative_path(base_dir: String, relative_uri: String) -> String:
	var current := base_dir
	for raw_segment in relative_uri.split("/", false):
		if raw_segment == ".":
			continue
		if raw_segment == "..":
			current = current.get_base_dir()
		else:
			current = current.path_join(String(raw_segment).uri_decode())
	return current


func _asset_root_for_path(path: String) -> String:
	for root_path in ASSET_ROOTS:
		if path == root_path or path.begins_with(root_path + "/"):
			return root_path
	return ""


func _collect_matching_files(root_path: String, requested_name: String, result: Array[String]) -> void:
	var directory := DirAccess.open(root_path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var path := root_path.path_join(entry)
		if directory.current_is_dir():
			_collect_matching_files(path, requested_name, result)
		elif entry.nocasecmp_to(requested_name) == 0:
			result.append(path)
	directory.list_dir_end()


func _closest_candidates(base_dir: String, candidates: Array[String]) -> Array[String]:
	var best_depth := -1
	var result: Array[String] = []
	for candidate in candidates:
		var depth := _common_path_depth(base_dir, candidate.get_base_dir())
		if depth > best_depth:
			best_depth = depth
			result = [candidate]
		elif depth == best_depth:
			result.append(candidate)
	result.sort()
	return result


func _common_path_depth(left: String, right: String) -> int:
	var left_segments := left.trim_prefix("res://").split("/", false)
	var right_segments := right.trim_prefix("res://").split("/", false)
	var depth := 0
	var limit := mini(left_segments.size(), right_segments.size())
	while depth < limit and String(left_segments[depth]).nocasecmp_to(String(right_segments[depth])) == 0:
		depth += 1
	return depth


func _relative_uri(from_dir: String, target_path: String) -> String:
	var from_segments := from_dir.trim_prefix("res://").split("/", false)
	var target_segments := target_path.trim_prefix("res://").split("/", false)
	var common := 0
	var limit := mini(from_segments.size(), target_segments.size())
	while common < limit and String(from_segments[common]).nocasecmp_to(String(target_segments[common])) == 0:
		common += 1
	var output: Array[String] = []
	for _index in range(common, from_segments.size()):
		output.append("..")
	for index in range(common, target_segments.size()):
		output.append(String(target_segments[index]).uri_encode())
	return "/".join(output)


func _is_external_or_embedded_uri(uri: String) -> bool:
	var normalized := uri.strip_edges().to_lower()
	return (
		normalized.begins_with("data:")
		or normalized.begins_with("http://")
		or normalized.begins_with("https://")
	)
