extends SceneTree

# Test-only process driver. All mutations go through the public ENet client.
const Client = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const Outpost = preload("res://scripts/runtime/networked_gameplay/m3/m3_mvp_outpost_client_adapter.gd")
const Resolver = preload("res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd")

var client
var outpost
var folder := ""
var last_id := ""
var elapsed := 0.0
var busy := false
var destination: Variant = null
var movement_error: Dictionary = {}
var config: Dictionary = {}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--driver-config="):
			config = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--driver-config=")))
	folder = String(config.get("folder", ""))
	call_deferred("_start")


func _start() -> void:
	if folder.is_empty():
		quit(2)
		return
	client = Client.new()
	root.add_child(client)
	var result: Dictionary = client.setup(config)
	outpost = Outpost.new()
	if bool(result.get("success", false)):
		result = outpost.setup(client)
	_write("setup.json", result)
	if not bool(result.get("success", false)):
		quit(2)


func _process(delta: float) -> bool:
	if client == null or busy:
		return false
	elapsed += delta
	if elapsed < 0.1:
		return false
	elapsed = 0.0
	if destination != null and client.is_ready():
		var p: Dictionary = client.get_local_player_record().get("position", {})
		var direction: Vector3 = (destination - Vector3(float(p.get("x", 0)), 0, float(p.get("z", 0)))).slide(Vector3.UP)
		var arrived := direction.length() <= 0.45
		var intent := {"move_x": 0.0, "move_z": 0.0 if arrived else 1.0,
			"look_yaw": atan2(-direction.x, -direction.z), "look_pitch": 0.0,
			"jump_pressed": false, "sprint": false, "delta_seconds": 0.1}
		var moved: Dictionary = client.submit_movement_intent_nonblocking(intent)
		if not bool(moved.get("success", false)):
			movement_error = moved
		if arrived:
			destination = null
	var request_path := folder.path_join("request.json")
	if FileAccess.file_exists(request_path):
		var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(request_path))
		if request is Dictionary and String(request.get("id", "")) != last_id:
			last_id = String(request.get("id", ""))
			busy = true
			var start := Time.get_ticks_msec()
			var result: Dictionary = _execute(request)
			_write("reply.json", {"id": last_id, "result": result, "duration_ms": Time.get_ticks_msec() - start})
			busy = false
	_write("state.json", _state())
	return false


func _execute(request: Dictionary) -> Dictionary:
	var params: Dictionary = request.get("params", {})
	var operation_id := String(request.get("operation_id", ""))
	match String(request.get("method", "")):
		"item":
			return client.execute_item_command_blocking(String(params.get("command", "")), params.get("payload", {}), operation_id)
		"mine":
			return client.execute_resource_mine_blocking("resource/earth/ore-demo/1", int(params.get("quantity", 1)), operation_id)
		"build":
			return outpost.build_next_stage_blocking()
		"move":
			destination = Vector3(float(params["x"]), 0, float(params["z"]))
			movement_error.clear()
			return {"success": true}
		"reconnect":
			destination = null
			return client.request_reconnect_now()
		"quit":
			destination = null
			var result: Dictionary = client.stop()
			quit(0)
			return result
	return {"success": false, "error_code": "UNKNOWN_DRIVER_METHOD"}


func _state() -> Dictionary:
	var resource: Dictionary = client.get_resource_mining_snapshot()
	var target: Dictionary = {}
	for node in resource.get("nodes", []):
		if node.get("resource_node_id", "") == "resource/earth/ore-demo/1":
			var resolver = Resolver.new()
			resolver.setup()
			target = resolver.resolve_planar(node.get("spatial", {})).get("details", {}).get("planar_position", {})
	return {"pid": OS.get_process_id(), "ticks_ms": Time.get_ticks_msec(),
		"report": client.get_report(), "player": client.get_local_player_record(),
		"players": client.get_snapshot(), "items": client.get_item_graph_snapshot(),
		"resource": resource, "construction": client.get_construction_bundle(),
		"outpost": outpost.get_status(), "seam": client.get_product_seam_state(),
		"resource_target": target, "moving": destination != null, "movement_error": movement_error}


func _write(name: String, value: Dictionary) -> void:
	var path := folder.path_join(name)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		quit(3)
		return
	file.store_string(JSON.stringify(value))
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		quit(3)
