extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const Server = preload("res://scripts/runtime/seamless/sm0/sm0_p6_projection_pivot_server.gd")


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var authority_id := String(options.get("authority-id", Contracts.AUTHORITY_A)).strip_edges()
	var zone_id := String(options.get("zone-id", Contracts.ZONE_A if authority_id == Contracts.AUTHORITY_A else Contracts.ZONE_B)).strip_edges()
	var server = Server.new()
	server.name = "Sm0P6ProjectionPivotServer"
	root.add_child(server)
	server.finished.connect(_on_finished)
	var result: Dictionary = server.setup({
		"authority_id": authority_id,
		"zone_id": zone_id,
		"gameplay_host": String(options.get("gameplay-host", "127.0.0.1")),
		"gameplay_port": int(options.get("gameplay-port", "24580")),
		"control_host": String(options.get("control-host", "127.0.0.1")),
		"control_port": int(options.get("control-port", "24680")),
		"peer_control_host": String(options.get("peer-control-host", "127.0.0.1")),
		"peer_control_port": int(options.get("peer-control-port", "24681")),
		"view_host": String(options.get("view-host", "127.0.0.1")),
		"view_port": int(options.get("view-port", "26100")),
		"stop_file": String(options.get("stop-file", "")),
		"manifest_hash": String(options.get("manifest-hash", "sm0-two-zone-v1")),
		"recovery_dir": String(options.get("recovery-dir", "")),
	})
	if not bool(result.get("success", false)):
		print("[SM0_P6_SERVER_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		quit(2)
		return
	print("[SM0_P6_SERVER_BOOT] setup_success authority=%s view_port=%d" % [authority_id, int(options.get("view-port", "26100"))])


func _on_finished(exit_code: int) -> void:
	quit(exit_code)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for raw_arg in args:
		var arg := String(raw_arg)
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var separator := arg.find("=")
		result[arg.substr(2, separator - 2)] = arg.substr(separator + 1)
	return result