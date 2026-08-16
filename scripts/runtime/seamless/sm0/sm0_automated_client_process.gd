extends SceneTree

const ClientNode = preload("res://scripts/runtime/seamless/sm0/sm0_automated_client_node_p4_hardened.gd")


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var client := ClientNode.new()
	client.name = "Sm0AutomatedClient"
	root.add_child(client)
	client.finished.connect(_on_finished)
	var result := client.setup({
		"server_host": String(options.get("server-host", "127.0.0.1")),
		"server_a_port": int(options.get("server-a-port", "24580")),
		"server_b_port": int(options.get("server-b-port", "24581")),
		"client_port": int(options.get("client-port", "24780")),
		"handoffs": int(options.get("handoffs", "4")),
		"timeout_ms": int(options.get("timeout-ms", "60000")),
		"result_file": String(options.get("result-file", "")),
		"post_handoff_settle_steps": int(options.get("post-handoff-settle-steps", "0")),
	})
	if not bool(result.get("success", false)):
		push_error("SM0 client setup failed: %s" % result)
		quit(2)


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
