extends SceneTree
const OuterNode = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_node.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")
func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var authority_id := String(options.get("authority-id", "")).strip_edges()
	var neighbors: Dictionary = {}
	for neighbor in Topology.neighbors(authority_id):
		var slug := neighbor.get_slice("/",2); var key := "neighbor-%s-port" % slug
		var port := int(options.get(key,"0"))
		if port > 0: neighbors[neighbor] = {"host":String(options.get("neighbor-%s-host" % slug,"127.0.0.1")),"port":port}
	var node := OuterNode.new(); node.name="Sm0P8Outer"; root.add_child(node); node.finished.connect(_on_finished)
	var result: Dictionary = node.setup({
		"authority_id":authority_id,"listen_host":String(options.get("listen-host","127.0.0.1")),"listen_port":int(options.get("listen-port","0")),"neighbor_endpoints":neighbors,
		"anchor_host":String(options.get("anchor-host","127.0.0.1")),"anchor_port":int(options.get("anchor-port","0")),"start_file":String(options.get("start-file","")),"stop_file":String(options.get("stop-file","")),
		"auto_start_target":String(options.get("auto-start-target","")),"auto_return_target":String(options.get("auto-return-target","")),
		"initial_writer":String(options.get("initial-writer","true" if authority_id == Topology.AUTHORITY_A else "false")).to_lower() in ["1","true","yes","on"],
		"initial_outer_epoch":int(options.get("initial-outer-epoch","1")),"initial_simulation_tick":int(options.get("initial-simulation-tick","0")),
		"initial_world_position":{"x":float(options.get("initial-x","-1.0")),"y":float(options.get("initial-y","0.0")),"z":float(options.get("initial-z","0.0"))},
		"linear_velocity":{"x":float(options.get("velocity-x","0.8")),"y":float(options.get("velocity-y","0.0")),"z":float(options.get("velocity-z","0.0"))},
		"world_yaw":float(options.get("world-yaw","0.0")),"angular_velocity_yaw":float(options.get("angular-velocity-yaw","0.2")),
	})
	if not bool(result.get("success",false)):
		print("[SM0_P8_OUTER_BOOT] setup_failed=%s" % JSON.stringify(result,"",false,true)); push_error("SM0 P8 outer setup failed: %s" % result); quit(2); return
	print("[SM0_P8_OUTER_BOOT] setup_success authority=%s zone=%s" % [authority_id,Topology.zone_for_authority(authority_id)])
func _on_finished(exit_code: int) -> void: quit(exit_code)
func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for value in args:
		var arg:=String(value)
		if not arg.begins_with("--") or not arg.contains("="): continue
		var separator:=arg.find("="); result[arg.substr(2,separator-2)] = arg.substr(separator+1)
	return result
