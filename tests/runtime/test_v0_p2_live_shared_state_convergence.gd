extends SceneTree

const POLL_MS := 50
const READY_TIMEOUT_MS := 60000
const CLIENT_TIMEOUT_MS := 90000
const EXIT_TIMEOUT_MS := 15000

var assertions := 0
var failures: Array[String] = []
var child_pids: Array[int] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var port := _find_port()
	_assert(port > 0, "V0-P2 shared-state UDP port allocated")
	if port <= 0:
		_finish()
		return
	var root_path := ProjectSettings.globalize_path("res://artifacts/test-results/v0-p2-live-shared-state-%d" % OS.get_process_id())
	_remove_tree(root_path)
	DirAccess.make_dir_recursive_absolute(root_path)
	var control_file := root_path.path_join("control.json")
	var server_log := root_path.path_join("server.log")
	var actor_file := root_path.path_join("actor.json")
	var before_file := root_path.path_join("b-before.json")
	var after_file := root_path.path_join("b-after.json")
	var actor_log := root_path.path_join("actor.log")
	var before_log := root_path.path_join("b-before.log")
	var after_log := root_path.path_join("b-after.log")
	var executable := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")
	_write_control(control_file, "BOOT")

	var server_pid := _spawn_server(executable, project_root, port, server_log, root_path.path_join("user-server"))
	child_pids.append(server_pid)
	_assert(server_pid > 0, "V0-P2 dedicated server launched")
	if server_pid <= 0:
		_finish(); return
	_assert(_wait_log_marker(server_pid, server_log, "\"event\":\"SERVER_READY\"", READY_TIMEOUT_MS), "V0-P2 server reports SERVER_READY")
	_assert(_wait_log_marker(server_pid, server_log, "\"event\":\"earth_runtime_ready\"", READY_TIMEOUT_MS), "V0-P2 Earth runtime ready")
	var lifecycle_ready := _wait_log_marker(server_pid, server_log, "\"event\":\"node_ready\"", READY_TIMEOUT_MS)
	var role_ready := _wait_log_marker(server_pid, server_log, "\"runtime_role\":\"dedicated-server\"", READY_TIMEOUT_MS)
	_assert(lifecycle_ready and role_ready, "V0-P2 dedicated-server lifecycle fully ready")
	if not lifecycle_ready or not role_ready:
		_finish(); return

	var actor_pid := _spawn_client(executable, project_root, port, "actor", actor_file, control_file, {}, actor_log, root_path.path_join("user-actor"))
	child_pids.append(actor_pid)
	_assert(actor_pid > 0, "V0-P2 actor A launched")
	var actor_ready := _wait_state(actor_file, ["ACTOR_READY", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(actor_ready, "ACTOR_READY"), "V0-P2 actor A reaches composite-ready state")
	if not _passed_state(actor_ready, "ACTOR_READY"):
		_finish(); return

	var before_pid := _spawn_client(executable, project_root, port, "before", before_file, control_file, {}, before_log, root_path.path_join("user-b-before"))
	child_pids.append(before_pid)
	_assert(before_pid > 0, "V0-P2 initial B launched")
	var before := _wait_state(before_file, ["BEFORE_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(before, "BEFORE_COMPLETE"), "V0-P2 initial B captures canonical components and leaves")
	_wait_exit(before_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(before_pid), "V0-P2 initial B exits before absent-peer mutations")
	child_pids.erase(before_pid)
	if not _passed_state(before, "BEFORE_COMPLETE"):
		_finish(); return
	var before_details: Dictionary = before.get("details", {})
	var before_session := String(before_details.get("transport_session_id", ""))
	var before_entity := String(before_details.get("player_entity_id", ""))
	var before_epoch := int(before_details.get("ownership_epoch", 0))
	var before_item_checksum := String(before_details.get("item_graph_checksum", ""))
	var before_construction_checksum := String(before_details.get("construction_checksum", ""))
	var before_construction_generation := int(before_details.get("construction_generation", -1))
	_assert(before_session.length() > 0 and before_entity == "player/b" and before_epoch >= 1, "V0-P2 captures B reconnect identity provenance")
	_assert(before_item_checksum.length() == 64, "V0-P2 captures pre-mutation Item Graph checksum")
	_assert(before_construction_checksum.length() == 64 and before_construction_generation >= 0, "V0-P2 captures pre-mutation Construction state")

	_write_control(control_file, "MUTATE")
	var actor_mutated := _wait_state(actor_file, ["ACTOR_MUTATED", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(actor_mutated, "ACTOR_MUTATED"), "V0-P2 A mutates Item Graph and Construction while B absent")
	if not _passed_state(actor_mutated, "ACTOR_MUTATED"):
		_finish(); return
	var actor_details: Dictionary = actor_mutated.get("details", {})
	var item_checksum := String(actor_details.get("item_graph_checksum", ""))
	var construction_checksum := String(actor_details.get("construction_checksum", ""))
	var construction_generation := int(actor_details.get("construction_generation", -1))
	_assert(item_checksum.length() == 64 and item_checksum != before_item_checksum, "V0-P2 absent-peer Item Graph mutation has new checksum")
	_assert(construction_checksum.length() == 64 and construction_checksum != before_construction_checksum, "V0-P2 absent-peer Construction mutation has new checksum")
	_assert(construction_generation > before_construction_generation, "V0-P2 absent-peer Construction generation advances")
	_assert(String(actor_details.get("beacon_location", "")) == "CONTAINER", "V0-P2 beacon leaves WORLD")
	_assert(String(actor_details.get("beacon_container_id", "")) == "container/shared/crate/1" and int(actor_details.get("beacon_slot_index", -1)) == 0, "V0-P2 beacon lands in canonical crate slot 0")
	_assert(String(actor_details.get("composite_checksum", "")).length() == 64, "V0-P2 actor post-mutation composite fingerprint captured")

	var after_pid := _spawn_client(executable, project_root, port, "after", after_file, control_file, {
		"expected-item-checksum": item_checksum,
		"expected-construction-checksum": construction_checksum,
		"expected-construction-generation": str(construction_generation),
		"previous-session-id": before_session,
		"previous-player-entity-id": before_entity,
		"previous-ownership-epoch": str(before_epoch),
	}, after_log, root_path.path_join("user-b-after"))
	child_pids.append(after_pid)
	_assert(after_pid > 0, "V0-P2 reconnect B launched")
	var after_ready := _wait_state(after_file, ["RECONNECT_READY", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(after_ready, "RECONNECT_READY"), "V0-P2 reconnect B reconstructs both canonical domains")
	if not _passed_state(after_ready, "RECONNECT_READY"):
		_finish(); return
	var after_details: Dictionary = after_ready.get("details", {})
	_assert(String(after_details.get("item_graph_checksum", "")) == item_checksum, "V0-P2 reconnect B exact Item Graph checksum")
	_assert(String(after_details.get("construction_checksum", "")) == construction_checksum, "V0-P2 reconnect B exact Construction checksum")
	_assert(int(after_details.get("construction_generation", -1)) == construction_generation, "V0-P2 reconnect B exact Construction generation")
	_assert(String(after_details.get("transport_session_id", "")) != before_session, "V0-P2 reconnect B gets new transport session")
	_assert(String(after_details.get("player_entity_id", "")) == before_entity, "V0-P2 reconnect B preserves canonical entity")
	_assert(int(after_details.get("ownership_epoch", 0)) > before_epoch, "V0-P2 reconnect B advances ownership epoch")

	var actor_reconnect := _wait_state(actor_file, ["ACTOR_RECONNECT_SEEN", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(actor_reconnect, "ACTOR_RECONNECT_SEEN"), "V0-P2 A remains live and observes B return")
	if not _passed_state(actor_reconnect, "ACTOR_RECONNECT_SEEN"):
		_finish(); return
	var actor_final: Dictionary = actor_reconnect.get("details", {})
	_assert(String(actor_final.get("item_graph_checksum", "")) == item_checksum, "V0-P2 reconnect itself does not mutate Item Graph")
	_assert(String(actor_final.get("construction_checksum", "")) == construction_checksum, "V0-P2 reconnect itself does not mutate Construction")
	var actor_composite := String(actor_final.get("composite_checksum", ""))
	var b_composite := String(after_details.get("composite_checksum", ""))
	_assert(actor_composite.length() == 64 and actor_composite == b_composite, "V0-P2 A/B bounded composite canonical fingerprints converge")
	_assert(_positions_close(Dictionary(actor_final.get("actor_player", {})), Dictionary(after_details.get("actor_player", {})), 0.05), "V0-P2 reconnect B converges to A authoritative transform")

	_write_control(control_file, "FINISH")
	var after_complete := _wait_state(after_file, ["RECONNECT_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	var actor_complete := _wait_state(actor_file, ["ACTOR_COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(_passed_state(after_complete, "RECONNECT_COMPLETE"), "V0-P2 reconnect B leaves cleanly")
	_assert(_passed_state(actor_complete, "ACTOR_COMPLETE"), "V0-P2 actor A remains healthy through full shared-state cycle")
	_wait_exit(after_pid, EXIT_TIMEOUT_MS)
	_wait_exit(actor_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(after_pid) and not OS.is_process_running(actor_pid), "V0-P2 both client processes exit")
	child_pids.erase(after_pid); child_pids.erase(actor_pid)
	if server_pid > 0 and OS.is_process_running(server_pid):
		OS.kill(server_pid); OS.delay_msec(300)
	child_pids.erase(server_pid)
	_assert(true, "V0-P2 dedicated server termination signal sent")
	for entry in [
		{"path": server_log, "label": "server"}, {"path": actor_log, "label": "actor-a"},
		{"path": before_log, "label": "client-b-before"}, {"path": after_log, "label": "client-b-after"},
	]:
		_assert_clean(String(entry["path"]), String(entry["label"]))
	_finish()


func _spawn_server(executable: String, project_root: String, port: int, log_file: String, user_root: String) -> int:
	return _spawn(executable, ["--headless", "--path", project_root, "--log-file", log_file, "--", "--network-mvp", "--role=dedicated-server", "--world=earth", "--server-address=127.0.0.1", "--server-port=%d" % port, "--network-debug", "--network-debug-stay-open", "--shutdown-after-ms=180000"], user_root)

func _spawn_client(executable: String, project_root: String, port: int, mode: String, result_file: String, control_file: String, extra: Dictionary, log_file: String, user_root: String) -> int:
	var args: Array[String] = ["--headless", "--path", project_root, "--log-file", log_file, "--script", "res://tools/runtime/v0_p2_live_reconnect_client.gd", "--", "--host=127.0.0.1", "--port=%d" % port, "--mode=%s" % mode, "--result-file=%s" % result_file, "--control-file=%s" % control_file]
	var keys := extra.keys(); keys.sort()
	for key_value in keys: args.append("--%s=%s" % [String(key_value), String(extra[key_value])])
	return _spawn(executable, args, user_root)

func _spawn(executable: String, args: Array[String], user_root: String) -> int:
	var names: Array[String] = ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA", "BREAKPOINT_RUNTIME_DISABLED", "GODOT_SILENCE_ROOT_WARNING"]
	var old: Dictionary = {}
	for name in names: old[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
	for path in [user_root, user_root.path_join("data"), user_root.path_join("config"), user_root.path_join("cache")]: DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user_root); OS.set_environment("XDG_DATA_HOME", user_root.path_join("data")); OS.set_environment("XDG_CONFIG_HOME", user_root.path_join("config")); OS.set_environment("XDG_CACHE_HOME", user_root.path_join("cache")); OS.set_environment("APPDATA", user_root.path_join("data")); OS.set_environment("LOCALAPPDATA", user_root.path_join("data")); OS.set_environment("BREAKPOINT_RUNTIME_DISABLED", "1"); OS.set_environment("GODOT_SILENCE_ROOT_WARNING", "1")
	var pid := OS.create_process(executable, args, false)
	for name in names:
		if bool(old[name]["set"]): OS.set_environment(name, String(old[name]["value"]))
		else: OS.unset_environment(name)
	return pid

func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec(); var report: Dictionary = {}
	while Time.get_ticks_msec() - started < timeout_ms:
		report = _read(path)
		if String(report.get("state", "")) in states: return report
		OS.delay_msec(POLL_MS)
	return report

func _wait_log_marker(pid: int, path: String, marker: String, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		if pid > 0 and not OS.is_process_running(pid): return false
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains(marker): return true
		OS.delay_msec(POLL_MS)
	return false

func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started < timeout_ms: OS.delay_msec(POLL_MS)

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text()); file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}

func _write_control(path: String, phase: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"phase": phase}, "  ")); file.close()

func _assert_clean(path: String, label: String) -> void:
	var content := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var clean := true
	for marker in ["SCRIPT ERROR:", "Parse Error:", "Compile Error:", "Failed to load script", "V0_P2_RECONNECT_SERVER_DISCONNECTED"]:
		if content.contains(marker): clean = false
	_assert(clean, "%s log contains no reconnect/parser/runtime failure" % label)

func _positions_close(a: Dictionary, b: Dictionary, tolerance: float) -> bool:
	var pa: Dictionary = a.get("position", {}); var pb: Dictionary = b.get("position", {})
	return Vector3(float(pa.get("x", 0.0)), float(pa.get("y", 0.0)), float(pa.get("z", 0.0))).distance_to(Vector3(float(pb.get("x", 0.0)), float(pb.get("y", 0.0)), float(pb.get("z", 0.0)))) <= tolerance

func _passed_state(report: Dictionary, state: String) -> bool:
	return String(report.get("state", "")) == state and bool(report.get("passed", false))

func _find_port() -> int:
	for candidate in range(48720, 48820):
		var udp := PacketPeerUDP.new()
		var error := udp.bind(candidate, "127.0.0.1")
		udp.close()
		if error == OK: return candidate
	return 0

func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty(): break
		if name == "." or name == "..": continue
		var child := path.path_join(name)
		if dir.current_is_dir(): _remove_tree(child)
		else: DirAccess.remove_absolute(child)
	dir.list_dir_end(); DirAccess.remove_absolute(path)

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition: print("PASS: %s" % message)
	else: failures.append(message); push_error("FAIL: %s" % message)

func _finish() -> void:
	for pid in child_pids:
		if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	if failures.is_empty():
		print("V0-P2 live shared state convergence: %d assertions, 0 failures" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("V0-P2 live shared state convergence: %d assertions, %d failures" % [assertions, failures.size()]); quit(1)
