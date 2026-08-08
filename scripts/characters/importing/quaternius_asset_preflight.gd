extends SceneTree

const ASSET_ROOTS: Array[String] = [
	"res://assets/external/quaternius/base_characters",
	"res://assets/external/quaternius/animation_library",
]

var changed_files := 0
var changed_uris := 0
var scanned_gltf := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for root_path in ASSET_ROOTS:
		_scan_directory(root_path)
	if failures.is_empty():
		print(
			"CH4 Quaternius asset preflight: PASS (%d glTF, %d files normalized, %d URI fixes)"
			% [scanned_gltf, changed_files, changed_uris]
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
		var canonical := _canonical_relative_uri(path.get_base_dir(), original)
		if canonical.is_empty():
			failures.append("UNRESOLVED_GLTF_URI: %s -> %s" % [path, original])
			continue
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


func _canonical_relative_uri(base_dir: String, uri: String) -> String:
	if uri.is_empty() or _is_external_or_embedded_uri(uri):
		return uri
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
		var directory := DirAccess.open(current_dir)
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
		if actual_name.is_empty():
			return ""
		output_segments.append(actual_name.uri_encode())
		current_dir = current_dir.path_join(actual_name)
	return "/".join(output_segments)


func _is_external_or_embedded_uri(uri: String) -> bool:
	var normalized := uri.strip_edges().to_lower()
	return (
		normalized.begins_with("data:")
		or normalized.begins_with("http://")
		or normalized.begins_with("https://")
	)
