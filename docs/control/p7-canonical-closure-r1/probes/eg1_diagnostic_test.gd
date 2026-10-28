extends "res://tests/network/test_eg1_gateway_processes.gd"

# Original assertions/transport untouched. Only the client adds read-only logs.
func _launch(executable: String, project_root: String, worker: String, args: Array) -> int:
	if worker != "eg1_client_worker.gd":
		return super._launch(executable, project_root, worker, args)
	var probe: String = get_script().resource_path.get_base_dir().path_join("eg1_diagnostic_client.gd")
	var full_args: Array = ["--headless", "--path", project_root, "--script", probe, "--"]
	full_args.append_array(args)
	return OS.create_process(executable, full_args, false)
