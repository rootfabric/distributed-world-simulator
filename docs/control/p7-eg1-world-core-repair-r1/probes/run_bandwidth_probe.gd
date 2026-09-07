extends SceneTree

const PortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")


func _init() -> void:
	# The external script path lets CI test the same probe against an untouched
	# baseline checkout: res:// still resolves its actual production adapter.
	var probe_path: String = get_script().resource_path.get_base_dir().path_join("enet_bandwidth_probe.gd")
	var probe: GDScript = load(probe_path)
	var report: Dictionary = probe.run(PortScript)
	var output: String = "res://artifacts/p7-bandwidth-probe.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	output = ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("BANDWIDTH_REPORT_WRITE_FAILED: %s" % output)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print(JSON.stringify(report))
	quit(0 if bool(report.get("passed", false)) else 1)
