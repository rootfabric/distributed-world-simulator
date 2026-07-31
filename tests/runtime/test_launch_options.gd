extends SceneTree

const RuntimeRoleScript = preload("res://scripts/runtime/runtime_role.gd")
const LaunchOptionsScript = preload("res://scripts/runtime/launch_options.gd")
const RuntimeDescriptorScript = preload("res://scripts/runtime/runtime_descriptor.gd")
const SimulatorAppScript = preload("res://scripts/app/simulator_app.gd")
const LunarAppScript = preload("res://scripts/app/lunar_app.gd")

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
		"--shutdown-after-ms=1500",
		"--shutdown-timeout-ms=45000",
		"--user-data-dir=/tmp/planet-sim-test",
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
	_assert(int(options.get("shutdown_after_ms", -1)) == 1500, "Shutdown delay was not parsed")
	_assert(int(options.get("shutdown_timeout_ms", -1)) == 45000, "Shutdown timeout was not parsed")
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
	_assert(String(descriptor.get("requested_user_data_dir", "")) == "/tmp/planet-sim-test", "Requested user data dir was lost")
	_assert(not String(descriptor.get("resolved_user_data_dir", "")).is_empty(), "Resolved user data dir is missing")

	var default_parse: Dictionary = LaunchOptionsScript.parse(PackedStringArray())
	_assert(bool(default_parse.get("success", false)), "Default launch options are invalid")
	_assert(String(default_parse.get("options", {}).get("role", "")) == RuntimeRoleScript.LISTEN_HOST, "Default role is not listen-host")

	var default_descriptor: Dictionary = RuntimeDescriptorScript.create(default_parse.get("options", {}))
	_assert(String(default_descriptor.get("checkpoint", "")) == "v16.10.6-architecture-a3-single-server-multiplayer", "Default descriptor checkpoint is stale")
	_assert(String(default_descriptor.get("build_id", "")) == "a3-single-server-multiplayer-architecture-freeze", "Default descriptor build id is stale")
	_assert(SimulatorAppScript.FOUNDATION_CHECKPOINT == "v16.10.6-architecture-a3-single-server-multiplayer", "Simulator checkpoint is stale")
	_assert(SimulatorAppScript.FOUNDATION_BUILD_ID == "a3-single-server-multiplayer-architecture-freeze", "Simulator build id is stale")
	_assert(LunarAppScript.PROJECT_VERSION == "16.10.6-architecture-a3-single-server-multiplayer", "Lunar project version is stale")
	_assert(LunarAppScript.BUILD_ID == "a3-single-server-multiplayer-architecture-freeze", "Lunar build id is stale")


	var host_parse: Dictionary = LaunchOptionsScript.parse(PackedStringArray(["--role=listen-host"]))
	_assert(bool(host_parse.get("success", false)), "listen-host launch role was rejected")
	var host_options: Dictionary = host_parse.get("options", {})
	_assert(String(host_options.get("role", "")) == RuntimeRoleScript.LISTEN_HOST, "listen-host role was not normalized")
	_assert(RuntimeRoleScript.presentation_enabled(RuntimeRoleScript.LISTEN_HOST), "listen-host must enable presentation")
	_assert(RuntimeRoleScript.accepts_local_input(RuntimeRoleScript.LISTEN_HOST), "listen-host must accept local input")
	_assert(RuntimeRoleScript.is_authoritative(RuntimeRoleScript.LISTEN_HOST), "listen-host must be authoritative")
	var host_descriptor: Dictionary = RuntimeDescriptorScript.create(host_options)
	_assert(bool(host_descriptor.get("client_replica_enabled", false)), "listen-host descriptor must enable client replica")
	_assert(bool(host_descriptor.get("embedded_authority", false)), "listen-host descriptor must embed authority")
	_assert(not bool(host_descriptor.get("direct_client_domain_access_allowed", true)), "listen-host descriptor allowed direct client domain access")

	var unsupported: Dictionary = LaunchOptionsScript.parse(PackedStringArray(["--role=directory-server"]))
	_assert(not bool(unsupported.get("success", true)), "Unsupported role was accepted")
	var unknown: Dictionary = LaunchOptionsScript.parse(PackedStringArray(["--mystery=value"]))
	_assert(not bool(unknown.get("success", true)), "Unknown option was accepted")
	var empty_node: Dictionary = LaunchOptionsScript.parse(PackedStringArray(["--node-id="]))
	_assert(not bool(empty_node.get("success", true)), "Empty node id was accepted")
	var negative_delay: Dictionary = LaunchOptionsScript.parse(PackedStringArray(["--shutdown-after-ms=-1"]))
	_assert(not bool(negative_delay.get("success", true)), "Negative shutdown delay was accepted")
	var zero_timeout: Dictionary = LaunchOptionsScript.parse(PackedStringArray(["--shutdown-timeout-ms=0"]))
	_assert(not bool(zero_timeout.get("success", true)), "Zero shutdown timeout was accepted")

	var m6_dedicated: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=dedicated-server",
		"--m6-persistence-root=user://m6-durable",
		"--m6-result-file=user://m6-result.json",
	]))
	_assert(bool(m6_dedicated.get("success", false)), "Valid M6 dedicated recovery options were rejected")
	_assert(String(m6_dedicated.get("options", {}).get("m6_persistence_root", "")) == "user://m6-durable", "M6 persistence root was not parsed")
	_assert(String(m6_dedicated.get("options", {}).get("m6_result_file", "")) == "user://m6-result.json", "M6 result file was not parsed")
	var m6_root_only: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=dedicated-server",
		"--m6-persistence-root=user://m6-production",
	]))
	_assert(bool(m6_root_only.get("success", false)), "M6 production persistence without acceptance result file was rejected")
	var m6_missing_root: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=dedicated-server",
		"--m6-result-file=user://m6-result.json",
	]))
	_assert(not bool(m6_missing_root.get("success", true)), "M6 result file without persistence root was accepted")
	var m6_client_role: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=game-client",
		"--m6-persistence-root=user://m6-invalid-client",
	]))
	_assert(not bool(m6_client_role.get("success", true)), "M6 persistence options were accepted for a graphical client")

	var m7_server: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=dedicated-server",
		"--network-playground",
	]))
	_assert(bool(m7_server.get("success", false)), "Valid M7 dedicated playground options were rejected")
	_assert(bool(m7_server.get("options", {}).get("network_playground", false)), "M7 playground flag was not parsed")
	_assert(String(m7_server.get("options", {}).get("world", "")) == "playground", "M7 playground did not select the test world")
	var m7_client: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=game-client",
		"--network-playground=true",
		"--network-debug",
		"--network-debug-stay-open",
		"--player-identity=a",
	]))
	_assert(bool(m7_client.get("success", false)), "Valid M7 graphical client options were rejected")
	_assert(bool(m7_client.get("options", {}).get("network_debug", false)), "M7 network debug flag was not parsed")
	_assert(bool(m7_client.get("options", {}).get("network_debug_stay_open", false)), "M7 debug stay-open flag was not parsed")
	var m7_wrong_world: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=game-client",
		"--network-playground",
		"--world=moon",
		"--player-identity=a",
	]))
	_assert(not bool(m7_wrong_world.get("success", true)), "M7 playground accepted a non-playground world")
	var m7_wrong_role: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=listen-host",
		"--network-playground",
	]))
	_assert(not bool(m7_wrong_role.get("success", true)), "M7 playground accepted listen-host authority")

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
