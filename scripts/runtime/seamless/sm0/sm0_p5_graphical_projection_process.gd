extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const Observer = preload("res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_observer.gd")


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var viewer_authority_id := String(options.get("viewer-authority-id", Contracts.AUTHORITY_A)).strip_edges()
	var observer = Observer.new()
	observer.name = "Sm0P5GraphicalProjectionObserver"
	root.add_child(observer)
	observer.finished.connect(_on_finished)
	var result: Dictionary = observer.setup({
		"viewer_authority_id": viewer_authority_id,
		"listen_host": String(options.get("listen-host", "127.0.0.1")),
		"listen_port": int(options.get("listen-port", "25990")),
		"stop_file": String(options.get("stop-file", "")),
	})
	if not bool(result.get("success", false)):
		print("[SM0_P5_GRAPHICAL_BOOT] setup_failed=%s" % JSON.stringify(result, "", false, true))
		quit(2)
		return
	print("[SM0_P5_GRAPHICAL_BOOT] setup_success viewer=%s" % viewer_authority_id)


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
