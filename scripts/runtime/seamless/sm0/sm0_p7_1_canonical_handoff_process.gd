extends SceneTree

const HandoffNode = preload("res://scripts/runtime/seamless/sm0/sm0_p7_1_canonical_handoff_node.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var authority_id := String(options.get("authority-id", "")).strip_edges()
	var zone_id := String(options.get("zone-id", Topology.zone_for_authority(authority_id))).strip_edges()
	var neighbor_endpoints: Dictionary = {}
	for neighbor in Topology.neighbors(authority_id):
		var slug := neighbor.get_slice("/", 2)
		var port := int(options.get("neighbor-%s-port" % slug, "0"))
		if port > 0:
			neighbor_endpoints[neighbor] = {
				"host": String(options.get("neighbor-%s-host" % slug, "127.0.0.1")),
				"port": port,
			}
	var node := HandoffNode.new()
	node.name = "Sm0P71CanonicalHandoff"
	root.add_child(node)
	node.finished.connect(_on_finished)
	var result: Dictionary = node.setup({
		"authority_id": authority_id,
		"zone_id": zone_id,
		"listen_host": String(options.get("listen-host", "127.0.0.1")),
		"listen_port": int(options.get("listen-port", "0")),
		"neighbor_endpoints": neighbor_endpoints,
		"stop_file": String(options.get("stop-file", "")),
		"start_file": String(options.get("start-file", "")),
		"auto_start_target": String(options.get("auto-start-target", "")),
		"auto_return_target": String(options.get("auto-return-target", "")),
		"initial_owner_authority_id": String(options.get("initial-owner-authority-id", Topology.AUTHORITY_A)),
		"initial_authority_epoch": int(options.get("initial-authority-epoch", "1")),
		"initial_directory_revision": int(options.get("initial-directory-revision", "1")),
	})
	if not bool(result.get("success", false)):
		print("[SM0_P7_1_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		push_error("SM0 P7.1 canonical handoff setup failed: %s" % result)
		quit(2)
		return
	print("[SM0_P7_1_BOOT] setup_success authority=%s zone=%s" % [authority_id, zone_id])


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