extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const P5Server = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_server_node.gd")


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var authority_id := String(options.get("authority-id", Contracts.AUTHORITY_A)).strip_edges()
	var zone_id := String(options.get(
		"zone-id",
		Contracts.ZONE_A if authority_id == Contracts.AUTHORITY_A else Contracts.ZONE_B
	)).strip_edges()
	var local_player_id := String(options.get(
		"local-player-id",
		"a" if authority_id == Contracts.AUTHORITY_A else "b"
	)).strip_edges()

	var server = P5Server.new()
	server.name = "Sm0P5ProjectionServer"
	root.add_child(server)
	server.finished.connect(_on_finished)
	var result: Dictionary = server.setup({
		"authority_id": authority_id,
		"zone_id": zone_id,
		"local_player_id": local_player_id,
		"control_host": String(options.get("control-host", "127.0.0.1")),
		"control_port": int(options.get("control-port", "25880")),
		"peer_control_host": String(options.get("peer-control-host", "127.0.0.1")),
		"peer_control_port": int(options.get("peer-control-port", "25881")),
		"stop_file": String(options.get("stop-file", "")),
	})
	if not bool(result.get("success", false)):
		print("[SM0_P5_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		quit(2)
		return
	print("[SM0_P5_BOOT] setup_success authority=%s player=%s" % [authority_id, local_player_id])


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