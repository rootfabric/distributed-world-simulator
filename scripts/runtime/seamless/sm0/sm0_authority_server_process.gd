extends SceneTree

const ServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_v2.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var authority_id := String(options.get("authority-id", ""))
	var zone_id := String(options.get("zone-id", ""))
	if authority_id.is_empty():
		authority_id = Contracts.AUTHORITY_A
	if zone_id.is_empty():
		zone_id = Contracts.ZONE_A if authority_id == Contracts.AUTHORITY_A else Contracts.ZONE_B
	print("[SM0_BOOT] authority=%s zone=%s gameplay_port=%s control_port=%s peer_control_port=%s" % [
		authority_id,
		zone_id,
		String(options.get("gameplay-port", "24580")),
		String(options.get("control-port", "24680")),
		String(options.get("peer-control-port", "24681")),
	])
	var server := ServerNode.new()
	server.name = "Sm0AuthorityServer"
	root.add_child(server)
	server.finished.connect(_on_finished)
	var result := server.setup({
		"authority_id": authority_id,
		"zone_id": zone_id,
		"gameplay_host": String(options.get("gameplay-host", "127.0.0.1")),
		"gameplay_port": int(options.get("gameplay-port", "24580")),
		"control_host": String(options.get("control-host", "127.0.0.1")),
		"control_port": int(options.get("control-port", "24680")),
		"peer_control_host": String(options.get("peer-control-host", "127.0.0.1")),
		"peer_control_port": int(options.get("peer-control-port", "24681")),
		"stop_file": String(options.get("stop-file", "")),
		"manifest_hash": String(options.get("manifest-hash", "sm0-two-zone-v1")),
	})
	if not bool(result.get("success", false)):
		print("[SM0_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		push_error("SM0 server setup failed: %s" % result)
		quit(2)
		return
	print("[SM0_BOOT] setup_success authority=%s" % authority_id)


func _on_finished(exit_code: int) -> void:
	quit(exit_code)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg_value in args:
		var arg := String(arg_value)
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var separator := arg.find("=")
		result[arg.substr(2, separator - 2)] = arg.substr(separator + 1)
	return result
