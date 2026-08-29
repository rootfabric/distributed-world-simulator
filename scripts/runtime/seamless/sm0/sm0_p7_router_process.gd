extends SceneTree

const RouterNode = preload("res://scripts/runtime/seamless/sm0/sm0_p7_router_node.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var authority_id := String(options.get("authority-id", "")).strip_edges()
	var zone_id := String(options.get("zone-id", Topology.zone_for_authority(authority_id))).strip_edges()
	var neighbor_endpoints: Dictionary = {}
	for neighbor in Topology.neighbors(authority_id):
		var slug := neighbor.get_slice("/", 2)
		var port_key := "neighbor-%s-port" % slug
		var host_key := "neighbor-%s-host" % slug
		var port := int(options.get(port_key, "0"))
		if port > 0:
			neighbor_endpoints[neighbor] = {
				"host": String(options.get(host_key, "127.0.0.1")),
				"port": port,
			}
	var router := RouterNode.new()
	router.name = "Sm0P7Router"
	root.add_child(router)
	router.finished.connect(_on_finished)
	var result: Dictionary = router.setup({
		"authority_id": authority_id,
		"zone_id": zone_id,
		"listen_host": String(options.get("listen-host", "127.0.0.1")),
		"listen_port": int(options.get("listen-port", "0")),
		"neighbor_endpoints": neighbor_endpoints,
		"start_file": String(options.get("start-file", "")),
		"stop_file": String(options.get("stop-file", "")),
		"auto_probe_destination": String(options.get("auto-probe-destination", "")),
	})
	if not bool(result.get("success", false)):
		print("[SM0_P7_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		push_error("SM0 P7 router setup failed: %s" % result)
		quit(2)
		return
	print("[SM0_P7_BOOT] setup_success authority=%s zone=%s" % [authority_id, zone_id])


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
