extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const Host = preload("res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_host.gd")


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var authority_id := String(options.get("authority-id", Contracts.AUTHORITY_A)).strip_edges()
	var zone_id := String(options.get("zone-id", Contracts.ZONE_A if authority_id == Contracts.AUTHORITY_A else Contracts.ZONE_B)).strip_edges()
	var local_player_id := String(options.get("local-player-id", "a" if authority_id == Contracts.AUTHORITY_A else "b")).strip_edges()
	var host = Host.new()
	host.name = "Sm0P5GraphicalProjectionHost"
	root.add_child(host)
	host.finished.connect(_on_finished)
	var result: Dictionary = host.setup({
		"authority_id": authority_id,
		"zone_id": zone_id,
		"local_player_id": local_player_id,
		"control_host": String(options.get("control-host", "127.0.0.1")),
		"control_port": int(options.get("control-port", "25980")),
		"peer_control_host": String(options.get("peer-control-host", "127.0.0.1")),
		"peer_control_port": int(options.get("peer-control-port", "25981")),
		"view_host": String(options.get("view-host", "127.0.0.1")),
		"view_port": int(options.get("view-port", "25990")),
		"stop_file": String(options.get("stop-file", "")),
		"demo_motion": String(options.get("demo-motion", "false")).strip_edges().to_lower() in ["1", "true", "yes", "on"],
	})
	if not bool(result.get("success", false)):
		print("[SM0_P5_GRAPHICAL_HOST_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		quit(2)
		return
	print("[SM0_P5_GRAPHICAL_HOST_BOOT] setup_success authority=%s player=%s" % [authority_id, local_player_id])


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
