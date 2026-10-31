extends RefCounted

## Explicit, opt-in RELEASE LAUNCH configuration. Never a gameplay authority.
const PROFILE_ID := "PLAYTEST_R1_SAFE60"
const PROFILE_PATH := "res://config/release/playtest-r1.json"

static func enabled() -> bool:
	return OS.get_environment("DWS_PLAYTEST_PROFILE") == PROFILE_ID

static func load_profile() -> Dictionary:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var value = JSON.parse_string(file.get_as_text())
	if not value is Dictionary or String(value.get("id", "")) != PROFILE_ID:
		return {}
	return value

static func prepare(user_args: PackedStringArray, data_root: String, source_head: String) -> Dictionary:
	var profile := load_profile()
	if profile.is_empty() or data_root.is_empty() or source_head.length() != 40:
		return {"success":false,"error_code":"PLAYTEST_PROFILE_OR_IDENTITY_MISSING"}
	var role := ""
	var player := ""
	var port := "24580"
	for arg in user_args:
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--player-identity="): player = arg.trim_prefix("--player-identity=")
		if arg.begins_with("--server-port="): port = arg.trim_prefix("--server-port=")
	if role not in ["dedicated-server", "game-client"] or not user_args.has("--network-mvp") or not user_args.has("--world=earth"):
		return {"success":false,"error_code":"PLAYTEST_EARTH_PRODUCT_ROLE_REQUIRED"}
	var server := role == "dedicated-server"
	if not server and player.is_empty():
		return {"success":false,"error_code":"PLAYTEST_PLAYER_ID_REQUIRED"}
	var env := {}
	for group in ["server_environment", "client_environment"]:
		for key in Dictionary(profile.get(group, {})):
			env[key] = "0"
	for key in profile.get("disabled_environment", []): env[key] = "0"
	for key in Dictionary(profile.get("server_environment" if server else "client_environment", {})):
		env[key] = "1"
	var suffix := "server-" + port if server else "client-" + player
	var root := data_root.path_join(suffix)
	env["HOME"] = root
	env["USERPROFILE"] = root
	env["APPDATA"] = root.path_join("data")
	env["LOCALAPPDATA"] = root.path_join("data")
	env["XDG_DATA_HOME"] = root.path_join("data")
	env["XDG_CONFIG_HOME"] = root.path_join("config")
	env["XDG_CACHE_HOME"] = root.path_join("cache")
	env["BREAKPOINT_RUNTIME_DISABLED"] = "1"
	env["GODOT_SILENCE_ROOT_WARNING"] = "1"
	var args := PackedStringArray()
	for arg in user_args:
		if arg.begins_with("--network-build-id=") or arg.begins_with("--network-git-commit=") or arg.begins_with("--connect-timeout-ms="):
			continue
		args.append("--server-address=0.0.0.0" if server and arg.begins_with("--server-address=") else arg)
	args.append("--network-build-id=" + String(profile["network_build_id"]))
	args.append("--network-git-commit=" + source_head)
	args.append("--print-runtime-descriptor")
	if not server: args.append("--connect-timeout-ms=120000")
	var engine := PackedStringArray(profile["common_engine_args"])
	if not server: engine.append_array(PackedStringArray(["--rendering-driver", "opengl3"]))
	return {"success":true,"error_code":"","role":role,"profile_root":root,"engine_args":engine,"user_args":args,"environment":env,"profile":PROFILE_ID}

static func apply_environment(values: Dictionary) -> Dictionary:
	var saved := {}
	for key in values:
		saved[key] = OS.get_environment(key) if OS.has_environment(key) else null
		OS.set_environment(key, String(values[key]))
	return saved

static func restore_environment(saved: Dictionary) -> void:
	for key in saved:
		if saved[key] == null: OS.unset_environment(key)
		else: OS.set_environment(key, String(saved[key]))
