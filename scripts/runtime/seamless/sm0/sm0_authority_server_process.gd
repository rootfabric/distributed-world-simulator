extends SceneTree

const HealthyServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_v2.gd")
const FaultServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_fault.gd")
const RecoveryServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery.gd")
const RecoveryFaultServerNode = preload("res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_fault.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

const H2_2_RECOVERY_FAULT_PROFILE := "h2-target-crash-after-commit-persist-v1"


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var authority_id := String(options.get("authority-id", ""))
	var zone_id := String(options.get("zone-id", ""))
	if authority_id.is_empty():
		authority_id = Contracts.AUTHORITY_A
	if zone_id.is_empty():
		zone_id = Contracts.ZONE_A if authority_id == Contracts.AUTHORITY_A else Contracts.ZONE_B
	var fault_profile := String(options.get("fault-profile", OS.get_environment("SM0_FAULT_PROFILE"))).strip_edges()
	var recovery_dir := String(options.get("recovery-dir", "")).strip_edges()
	print("[SM0_BOOT] authority=%s zone=%s gameplay_port=%s control_port=%s peer_control_port=%s fault_profile=%s recovery_dir=%s" % [
		authority_id,
		zone_id,
		String(options.get("gameplay-port", "24580")),
		String(options.get("control-port", "24680")),
		String(options.get("peer-control-port", "24681")),
		fault_profile if not fault_profile.is_empty() else "none",
		recovery_dir if not recovery_dir.is_empty() else "none",
	])
	var server
	if fault_profile == H2_2_RECOVERY_FAULT_PROFILE:
		server = RecoveryFaultServerNode.new()
	elif not fault_profile.is_empty():
		server = FaultServerNode.new()
	elif not recovery_dir.is_empty():
		server = RecoveryServerNode.new()
	else:
		server = HealthyServerNode.new()
	server.name = "Sm0AuthorityServer"
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
		"stop_file": String(options.get("stop-file", "")),
		"manifest_hash": String(options.get("manifest-hash", "sm0-two-zone-v1")),
		"fault_profile": fault_profile,
		"recovery_dir": recovery_dir,
	})
	if not bool(result.get("success", false)):
		print("[SM0_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		push_error("SM0 server setup failed: %s" % result)
		quit(2)
		return
	print("[SM0_BOOT] setup_success authority=%s fault_profile=%s recovery_dir=%s" % [
		authority_id,
		fault_profile if not fault_profile.is_empty() else "none",
		recovery_dir if not recovery_dir.is_empty() else "none",
	])


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
