extends SceneTree

const NestedNode = preload("res://scripts/runtime/seamless/sm0/sm0_p8_nested_authority_node.gd")
const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_contract.gd")

func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var auto_local_motion := _parse_bool_option(options, "auto-local-motion", true)
	var node := NestedNode.new()
	node.name = "Sm0P8NestedAuthority"
	root.add_child(node)
	node.finished.connect(_on_finished)
	var result: Dictionary = node.setup({
		"anchor_host": String(options.get("anchor-host", "127.0.0.1")),
		"anchor_port": int(options.get("anchor-port", "0")),
		"view_host": String(options.get("view-host", "127.0.0.1")),
		"view_port": int(options.get("view-port", "0")),
		"stop_file": String(options.get("stop-file", "")),
		"auto_local_motion": auto_local_motion,
	})
	if not bool(result.get("success", false)):
		print("[SM0_P8_NESTED_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		push_error("SM0 P8 nested setup failed: %s" % result)
		quit(2)
		return
	print("[SM0_P8_NESTED_BOOT] setup_success island_authority=%s auto_local_motion=%s" % [
		Contract.ISLAND_AUTHORITY_ID,
		"true" if auto_local_motion else "false",
	])

func _on_finished(exit_code: int) -> void:
	quit(exit_code)

func _parse_args(args: PackedStringArray) -> Dictionary:
	var result := {}
	for value in args:
		var arg := String(value)
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var separator := arg.find("=")
		result[arg.substr(2, separator - 2)] = arg.substr(separator + 1)
	return result

func _parse_bool_option(options: Dictionary, key: String, default_value: bool) -> bool:
	if not options.has(key):
		return default_value
	var normalized := String(options.get(key, "")).strip_edges().to_lower()
	if normalized in ["1", "true", "yes", "on"]:
		return true
	if normalized in ["0", "false", "no", "off"]:
		return false
	return default_value
