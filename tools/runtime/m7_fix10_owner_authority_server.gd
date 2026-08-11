extends SceneTree

const OwnerServerRuntime = preload(
	"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_owner_movement.gd"
)

var server


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var options: Dictionary = _parse_user_args()
	var port: int = int(options.get("server-port", "0"))
	var result_file: String = String(options.get("m7-result-file", "")).strip_edges()
	var shutdown_after_ms: int = int(options.get("shutdown-after-ms", "180000"))
	if port < 1 or result_file.is_empty():
		push_error("M7 owner server requires --server-port and --m7-result-file")
		quit(2)
		return
	server = OwnerServerRuntime.new()
	root.add_child(server)
	var setup: Dictionary = server.setup({
		"host": String(options.get("server-address", "127.0.0.1")),
		"port": port,
		"result_file": result_file,
		"authority_owner_id": String(options.get("node-id", "m7-owner-server")),
		"authority_epoch": 1,
		"playable_sandbox": true,
		"debug_logging": false,
		"world_id": "playground",
		"network_condition_profile": String(options.get("network-profile", "LOCAL")),
	})
	if not bool(setup.get("success", false)):
		push_error("M7 owner server setup failed: %s" % setup)
		quit(3)
		return
	if shutdown_after_ms > 0:
		await create_timer(float(shutdown_after_ms) / 1000.0).timeout
	quit(0)


func _parse_user_args() -> Dictionary:
	var result: Dictionary = {}
	for value in OS.get_cmdline_user_args():
		var argument: String = String(value).strip_edges()
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator: int = argument.find("=")
		result[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return result
