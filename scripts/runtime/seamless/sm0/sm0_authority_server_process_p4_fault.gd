extends SceneTree

const FaultServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_fault.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var authority_id := String(options.get("authority-id", Contracts.AUTHORITY_B))
	var zone_id := String(options.get("zone-id", Contracts.ZONE_B))
	var fault_profile := String(options.get("p4-fault-profile", "")).strip_edges().to_lower()
	var server = FaultServerNode.new()
	server.name = "Sm0P4FaultAuthorityServer"
	root.add_child(server)
	server.finished.connect(_on_finished)
	var result: Dictionary = server.setup({
		"authority_id": authority_id,
		"zone_id": zone_id,
		"gameplay_host": String(options.get("gameplay-host", "127.0.0.1")),
		"gameplay_port": int(options.get("gameplay-port", "24581")),
		"control_host": String(options.get("control-host", "127.0.0.1")),
		"control_port": int(options.get("control-port", "24681")),
		"peer_control_host": String(options.get("peer-control-host", "127.0.0.1")),
		"peer_control_port": int(options.get("peer-control-port", "24680")),
		"stop_file": String(options.get("stop-file", "")),
		"manifest_hash": String(options.get("manifest-hash", "sm0-two-zone-v1")),
		"recovery_dir": String(options.get("recovery-dir", OS.get_environment("SM0_P4_RECOVERY_DIR"))),
		"p4_fault_profile": fault_profile,
	})
	if not bool(result.get("success", false)):
		print("[SM0_P4_FAULT_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		push_error("SM0 P4 fault server setup failed: %s" % result)
		quit(2)
		return
	print("[SM0_P4_FAULT_BOOT] setup_success authority=%s fault_profile=%s" % [authority_id, fault_profile])


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
