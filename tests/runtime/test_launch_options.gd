extends SceneTree

const RuntimeRoleScript = preload("res://scripts/runtime/runtime_role.gd")
const LaunchOptionsScript = preload("res://scripts/runtime/launch_options.gd")
const RuntimeDescriptorScript = preload("res://scripts/runtime/runtime_descriptor.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var parsed: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=simulation-server",
		"--world=playground",
		"--node-id=sim-01",
		"--instance-id=network-test-001",
		"--space-id=moon",
		"--authority-region=region/moon/a",
		"--run-tests=core",
		"--print-runtime-descriptor",
	]))
	_assert(bool(parsed.get("success", false)), "Valid launch options were rejected")
	var options: Dictionary = parsed.get("options", {})
	_assert(String(options.get("role", "")) == RuntimeRoleScript.SIMULATION_SERVER, "Runtime role was not parsed")
	_assert(String(options.get("world", "")) == "playground", "World option was not parsed")
	_assert(String(options.get("node_id", "")) == "sim-01", "Node id was not parsed")
	_assert(String(options.get("instance_id", "")) == "network-test-001", "Instance id was not parsed")
	_assert(String(options.get("space_id", "")) == "moon", "Space id was not parsed")
	_assert(bool(options.get("print_runtime_descriptor", false)), "Descriptor flag was not parsed")
	_assert(not RuntimeRoleScript.presentation_enabled(String(options.get("role", ""))), "Simulation server unexpectedly enables presentation")
	_assert(RuntimeRoleScript.is_authoritative(String(options.get("role", ""))), "Simulation server must be authoritative")

	var descriptor: Dictionary = RuntimeDescriptorScript.create(options, {
		"checkpoint": "test-checkpoint",
		"build_id": "test-build",
	})
	_assert(bool(RuntimeDescriptorScript.validate(descriptor).get("success", false)), "Runtime descriptor is invalid")
	_assert(String(descriptor.get("node_id", "")) == "sim-01", "Runtime descriptor lost node id")
	_assert(String(descriptor.get("runtime_role", "")) == RuntimeRoleScript.SIMULATION_SERVER, "Runtime descriptor lost role")
	_assert(not bool(descriptor.get("presentation_enabled", true)), "Runtime descriptor enables presentation for server")
	_assert(int(descriptor.get("process_id", 0)) > 0, "Runtime descriptor has no process id")

	var default_parse: Dictionary = LaunchOptionsScript.parse(PackedStringArray())
	_assert(bool(default_parse.get("success", false)), "Default launch options are invalid")
	_assert(String(default_parse.get("options", {}).get("role", "")) == RuntimeRoleScript.OFFLINE, "Default role is not offline")

	var unsupported: Dictionary = LaunchOptionsScript.parse(PackedStringArray(["--role=directory-server"]))
	_assert(not bool(unsupported.get("success", true)), "Unsupported role was accepted")
	var unknown: Dictionary = LaunchOptionsScript.parse(PackedStringArray(["--mystery=value"]))
	_assert(not bool(unknown.get("success", true)), "Unknown option was accepted")
	var empty_node: Dictionary = LaunchOptionsScript.parse(PackedStringArray(["--node-id="]))
	_assert(not bool(empty_node.get("success", true)), "Empty node id was accepted")

	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Runtime launch option contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Runtime launch option contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
