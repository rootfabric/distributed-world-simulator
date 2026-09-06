extends SceneTree
## WP1.2 prepared-asset offline sample boot (no network, no import server).
##
## Loads the prepared bundle manifest and every prepared map from disk and
## proves they decode as images in the exact project Godot build. Run:
##   godot --headless --path <repo> --script res://scripts/world_packs/prepared/prepared_sample_self_check.gd -- --prepared=<bundle_dir>

var prepared_dir := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--prepared="):
			prepared_dir = arg.substr("--prepared=".length())
	if prepared_dir.is_empty():
		push_error("PREPARED_SAMPLE: USAGE ERROR (expected --prepared=<dir>)")
		quit(2)
		return
	_run()

func _run() -> void:
	var manifest_path := prepared_dir.path_join("prepared_manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_error("PREPARED_SAMPLE: FAIL cannot open manifest %s" % manifest_path)
		quit(3)
		return
	var parsed: Dictionary = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed.has("members"):
		push_error("PREPARED_SAMPLE: FAIL manifest is not valid JSON with members")
		quit(3)
		return
	var identity: Dictionary = parsed.get("identity", {})
	if not identity.has("prepared_identity_sha256"):
		push_error("PREPARED_SAMPLE: FAIL manifest lacks prepared identity")
		quit(3)
		return
	var maps := 0
	for member in parsed["members"]:
		var bytes := FileAccess.get_file_as_bytes(prepared_dir.path_join(member["path"]))
		if bytes.is_empty():
			push_error("PREPARED_SAMPLE: FAIL cannot read member %s" % member["path"])
			quit(4)
			return
		var image := Image.new()
		var err := image.load_jpg_from_buffer(bytes)
		if err != OK:
			push_error("PREPARED_SAMPLE: FAIL member %s does not decode as JPG (%d)" % [member["path"], err])
			quit(4)
			return
		if image.get_width() <= 0 or image.get_height() <= 0:
			push_error("PREPARED_SAMPLE: FAIL member %s has zero extent" % member["path"])
			quit(4)
			return
		maps += 1
	print("PREPARED_SAMPLE_IDENTITY=", identity["prepared_identity_sha256"])
	print("PREPARED_SAMPLE_MAPS=", maps)
	print("PREPARED_SAMPLE=PASS (offline, no HTTP/DNS, no import server)")
	quit(0)
