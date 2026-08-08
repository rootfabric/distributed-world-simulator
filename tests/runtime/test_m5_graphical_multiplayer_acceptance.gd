extends SceneTree

const Support = preload("res://scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_support.gd")
const ProcessEnvironment = preload("res://scripts/runtime/networked_gameplay/m5/m5_process_environment.gd")

const POLL_MS := 75
const SERVER_TIMEOUT_MS := 90000
const CLIENT_TIMEOUT_MS := 180000
const EXIT_TIMEOUT_MS := 20000

var failures: Array[String] = []
var assertions := 0
var child_pids: Array[int] = []
var xvfb_pid := -1


func _init() -> void:
	var port := _find_available_port()
	_assert(port > 0, "M5 ENet port allocated")
	if port <= 0:
		_finish()
		return
	var root := ProjectSettings.globalize_path(
		"res://artifacts/test-results/m5-graphical-%d" % OS.get_process_id()
	)
	DirAccess.make_dir_recursive_absolute(root)
	var server_path := root.path_join("server.json")
	var a1_path := root.path_join("a1.json")
	var b_path := root.path_join("b.json")
	var a2_path := root.path_join("a2.json")
	var control_path := root.path_join("control.json")
	var screenshot_dir := root.path_join("screenshots")
	Support.write(control_path, {
		"schema": Support.CONTROL_SCHEMA,
		"go_contention": false,
		"disconnect_a": false,
		"finish": false,
		"reconnect_peer_result_file": "",
	})
	var profiles := [
		ProcessEnvironment.create(root.path_join("profiles"), "server", 0, "disabled"),
		ProcessEnvironment.create(root.path_join("profiles"), "client-a1", 1, "disabled"),
		ProcessEnvironment.create(root.path_join("profiles"), "client-b", 2, "disabled"),
		ProcessEnvironment.create(root.path_join("profiles"), "client-a2", 3, "disabled"),
	]
	var profiles_valid := ProcessEnvironment.validate_unique(profiles)
	_assert(bool(profiles_valid.get("success", false)), "M5 process profiles are isolated")
	var display_name := ""
	if OS.get_name() == "Linux":
		display_name = _start_virtual_display()
		_assert(not display_name.is_empty(), "M5 Xvfb graphical display started")
		if display_name.is_empty():
			_finish()
			return
	var executable := OS.get_executable_path()
	var project_root := ProjectSettings.globalize_path("res://")
	var server_pid := _spawn(
		executable,
		[
			"--headless", "--quiet", "--path", project_root,
			"--audio-driver", "Dummy", "--log-file", root.path_join("server.log"), "--",
			"--role=dedicated-server", "--world=playground",
			"--node-id=m5-dedicated-server", "--server-address=127.0.0.1",
			"--server-port=%d" % port, "--m5-result-file=%s" % server_path,
			"--shutdown-after-ms=300000",
		],
		profiles[0],
		""
	)
	child_pids.append(server_pid)
	_assert(server_pid > 0, "M5 dedicated server process launched")
	var server_ready := _wait_state(server_path, ["READY", "FAILED"], SERVER_TIMEOUT_MS)
	_assert(String(server_ready.get("state", "")) == "READY", "M5 dedicated server ready: %s" % server_ready)
	if String(server_ready.get("state", "")) != "READY":
		_finish()
		return
	var a1_pid := _spawn_client(
		executable, project_root, port, "a", 1, a1_path, b_path, control_path,
		screenshot_dir, root.path_join("a1.log"), profiles[1], display_name
	)
	var b_pid := _spawn_client(
		executable, project_root, port, "b", 2, b_path, a1_path, control_path,
		screenshot_dir, root.path_join("b.log"), profiles[2], display_name
	)
	child_pids.append(a1_pid)
	child_pids.append(b_pid)
	_assert(a1_pid > 0 and b_pid > 0, "two M5 graphical clients launched concurrently")
	var a_ready := _wait_state(a1_path, ["READY_FOR_CONTENTION", "FAILED"], CLIENT_TIMEOUT_MS)
	var b_ready := _wait_state(b_path, ["READY_FOR_CONTENTION", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(a_ready.get("state", "")) == "READY_FOR_CONTENTION", "client A reached UI contention barrier")
	_assert(String(b_ready.get("state", "")) == "READY_FOR_CONTENTION", "client B reached UI contention barrier")
	if String(a_ready.get("state", "")) != "READY_FOR_CONTENTION" or String(b_ready.get("state", "")) != "READY_FOR_CONTENTION":
		_finish()
		return
	_write_control(control_path, {"go_contention": true})
	var a_post := _wait_state(a1_path, ["POST_CONTENTION_READY", "A_CURSOR_PENDING", "FAILED"], CLIENT_TIMEOUT_MS)
	var b_post := _wait_state(b_path, ["POST_CONTENTION_READY", "WAITING_RECONNECT", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(a_post.get("state", "")) != "FAILED", "client A completed UI contention")
	_assert(String(b_post.get("state", "")) != "FAILED", "client B completed UI contention")
	var a_cursor := _wait_state(a1_path, ["A_CURSOR_PENDING", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(a_cursor.get("state", "")) == "A_CURSOR_PENDING", "A created transient cursor after server-confirmed ore pickup")
	_write_control(control_path, {"disconnect_a": true})
	var a_left := _wait_state(a1_path, ["DISCONNECTED_WITH_TRANSIENT", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(bool(a_left.get("passed", false)), "A disconnected with transient UI state only")
	_wait_exit(a1_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(a1_pid), "initial A graphical process exited")
	child_pids.erase(a1_pid)
	var b_wait := _wait_state(b_path, ["WAITING_RECONNECT", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(b_wait.get("state", "")) == "WAITING_RECONNECT", "B continued real InputMap movement while A was offline")
	_write_control(control_path, {"reconnect_peer_result_file": a2_path})
	var a2_pid := _spawn_client(
		executable, project_root, port, "a", 3, a2_path, b_path, control_path,
		screenshot_dir, root.path_join("a2.log"), profiles[3], display_name
	)
	child_pids.append(a2_pid)
	_assert(a2_pid > 0, "A reconnect graphical process launched")
	var a2_ready := _wait_state(a2_path, ["READY_TO_CONVERGE", "CONVERGENCE_LOCKED", "FAILED"], CLIENT_TIMEOUT_MS)
	var b_converge := _wait_state(b_path, ["READY_TO_CONVERGE", "CONVERGENCE_LOCKED", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(String(a2_ready.get("state", "")) in ["READY_TO_CONVERGE", "CONVERGENCE_LOCKED"], "A reconnect reached convergence barrier")
	_assert(String(b_converge.get("state", "")) in ["READY_TO_CONVERGE", "CONVERGENCE_LOCKED"], "B reached convergence barrier")
	# Commit finalization before waiting for the matching pair. The client driver
	# keeps locks revocable while finish=false so late authoritative snapshots can
	# replace stale checksums. Once finish=true is atomically published, the first
	# mutually observed matching lock becomes the committed barrier and can no
	# longer be revoked between parent observation and client shutdown.
	_write_control(control_path, {"finish": true})
	var convergence_pair := _wait_convergence_pair(a2_path, b_path, CLIENT_TIMEOUT_MS)
	a2_ready = Dictionary(convergence_pair.get("a", a2_ready))
	b_converge = Dictionary(convergence_pair.get("b", b_converge))
	_assert(bool(convergence_pair.get("success", false)), "A and B reached identical player and Item Graph checksums")
	_validate_pre_finish(a_ready, b_ready, a_cursor, b_wait, a2_ready, b_converge)
	var a2_final := _wait_state(a2_path, ["COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	var b_final := _wait_state(b_path, ["COMPLETE", "FAILED"], CLIENT_TIMEOUT_MS)
	_assert(bool(a2_final.get("passed", false)), "A reconnect graphical acceptance completed")
	_assert(bool(b_final.get("passed", false)), "B graphical acceptance completed")
	_wait_exit(a2_pid, EXIT_TIMEOUT_MS)
	_wait_exit(b_pid, EXIT_TIMEOUT_MS)
	_assert(not OS.is_process_running(a2_pid) and not OS.is_process_running(b_pid), "M5 graphical clients exited cleanly")
	child_pids.erase(a2_pid)
	child_pids.erase(b_pid)
	var server_final := _wait_server_counts(server_path, 3, 3, 30000)
	_validate_final(a_post, b_post, a_cursor, b_wait, a2_final, b_final, server_final, root)
	_finish()


func _spawn_client(
	executable: String,
	project_root: String,
	port: int,
	client_id: String,
	phase: int,
	result_path: String,
	peer_path: String,
	control_path: String,
	screenshot_dir: String,
	log_path: String,
	profile: Dictionary,
	display_name: String
) -> int:
	return _spawn(
		executable,
		[
			"--quiet", "--path", project_root,
			"--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
			"--log-file", log_path, "--",
			"--role=game-client", "--world=playground",
			"--node-id=m5-client-%s-%d" % [client_id, phase],
			"--server-address=127.0.0.1", "--server-port=%d" % port,
			"--player-identity=%s" % client_id,
			"--connect-timeout-ms=90000", "--command-timeout-ms=15000",
			"--m5-result-file=%s" % result_path,
			"--m5-peer-result-file=%s" % peer_path,
			"--m5-control-file=%s" % control_path,
			"--m5-screenshot-dir=%s" % screenshot_dir,
			"--m5-phase=%d" % phase,
		],
		profile,
		display_name
	)


func _spawn(executable: String, args: Array[String], profile: Dictionary, display_name: String) -> int:
	var environment: Dictionary = Dictionary(profile.get("environment", {})).duplicate(true)
	if not display_name.is_empty():
		environment["DISPLAY"] = display_name
		environment["LIBGL_ALWAYS_SOFTWARE"] = "1"
	var captured: Dictionary = {}
	for name_value in environment.keys():
		var name := String(name_value)
		captured[name] = {"set": OS.has_environment(name), "value": OS.get_environment(name)}
		OS.set_environment(name, String(environment[name]))
	for path_key in ["HOME", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		DirAccess.make_dir_recursive_absolute(String(environment.get(path_key, "")))
	var pid := OS.create_process(executable, args, false)
	for name_value in captured.keys():
		var name := String(name_value)
		var value: Dictionary = captured[name]
		if bool(value.get("set", false)):
			OS.set_environment(name, String(value.get("value", "")))
		else:
			OS.unset_environment(name)
	return pid


func _validate_pre_finish(
	a_ready: Dictionary,
	b_ready: Dictionary,
	a_cursor: Dictionary,
	b_wait: Dictionary,
	a2: Dictionary,
	b: Dictionary
) -> void:
	for report in [a_ready, b_ready, a2, b]:
		_assert(String(report.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "client used a real graphical display")
		_assert(String(report.get("rendering_method", "")) == "gl_compatibility", "client used GL compatibility renderer")
		_assert(bool(report.get("movement_result", {}).get("success", false)), "movement was generated through InputMap")
		_assert(String(report.get("movement_result", {}).get("input_map_action", "")) == "move_forward", "initial movement used move_forward InputMap action")
		_assert(int(report.get("ui", {}).get("authority_references", 1)) == 0, "UI has no authority reference")
		_assert(int(report.get("ui", {}).get("domain_references", 1)) == 0, "UI has no domain reference")
		var screenshot: Dictionary = report.get("screenshot", {})
		var screenshot_details: Dictionary = screenshot.get("details", {})
		_assert(bool(screenshot.get("success", false)), "client captured real viewport screenshot")
		_assert(int(screenshot_details.get("width", 0)) > 0 and int(screenshot_details.get("height", 0)) > 0, "screenshot has dimensions")
		_assert(String(screenshot_details.get("sha256", "")).length() == 64, "screenshot has SHA-256")
	var a_result: Dictionary = a_cursor.get("contention_result", {})
	var b_result: Dictionary = b_wait.get("contention_result", {})
	var winners := int(bool(a_result.get("success", false))) + int(bool(b_result.get("success", false)))
	_assert(winners == 1, "UI contention produced exactly one winner")
	var loser := b_result if bool(a_result.get("success", false)) else a_result
	_assert(String(loser.get("error_code", "")) == "ITEM_ALREADY_CLAIMED", "UI loser received deterministic ITEM_ALREADY_CLAIMED")
	var workflow: Dictionary = a_cursor.get("winner_workflow", {}) if bool(a_result.get("success", false)) else b_wait.get("winner_workflow", {})
	_assert(bool(workflow.get("success", false)), "winner completed UI-driven hotbar/container/mount/drop workflow")
	_assert(bool(a_cursor.get("ui", {}).get("cursor_active", false)), "A cursor was active before disconnect")
	_assert(int(a2.get("initial_ownership_epoch", 0)) == 2, "A reconnect ownership epoch advanced to 2")
	var a1_runtime: Dictionary = a_ready.get("client_runtime", {})
	var a2_runtime: Dictionary = a2.get("client_runtime", {})
	var a1_join_id := String(a1_runtime.get("join_operation_id", ""))
	var a2_join_id := String(a2_runtime.get("join_operation_id", ""))
	_assert(not a1_join_id.is_empty() and not a2_join_id.is_empty(), "A join operation identities are reported")
	_assert(a1_join_id != a2_join_id, "A reconnect uses a distinct transport-bound JOIN identity")
	_assert(
		a1_join_id.ends_with(String(a1_runtime.get("transport_session_id", "")).sha256_text().left(16))
		and a2_join_id.ends_with(String(a2_runtime.get("transport_session_id", "")).sha256_text().left(16)),
		"A JOIN identities are bound to their transport sessions"
	)
	_assert(not bool(a2.get("ui", {}).get("cursor_active", true)), "transient cursor did not survive reconnect")
	_assert(String(a2.get("player_checksum", "")) == String(b.get("player_checksum", "")), "A and B player checksum convergence")
	_assert(String(a2.get("item_checksum", "")) == String(b.get("item_checksum", "")), "A and B Item Graph checksum convergence")
	_assert(String(b_wait.get("movement_result", {}).get("input_map_action", "")) == "move_forward", "B initial movement used InputMap")
	_assert(int(b_wait.get("world", {}).get("remote_despawn_count", 0)) >= 1, "B despawned A after disconnect")


func _validate_final(
	a_post: Dictionary,
	b_post: Dictionary,
	a_cursor: Dictionary,
	b_wait: Dictionary,
	a2: Dictionary,
	b: Dictionary,
	server: Dictionary,
	root: String
) -> void:
	var snapshot: Dictionary = server.get("item_graph_snapshot", {})
	_assert(int(server.get("joins", 0)) == 3, "server saw A, B and A reconnect")
	_assert(int(server.get("leaves", 0)) == 3, "server saw all graceful leaves")
	_assert(int(server.get("connected_peer_count", -1)) == 0, "server has no stale peers")
	_assert(String(snapshot.get("checksum", "")) == String(a2.get("item_checksum", "")), "server and clients Item Graph convergence")
	_assert(_count_item(snapshot, "item/shared/beacon/1") == 1, "canonical Item Graph contains one beacon identity")
	_assert(_item_in_one_inventory(snapshot, "item/shared/beacon/1"), "beacon exists in exactly one player inventory")
	_assert(_item_in_inventory(snapshot, "a", "item/shared/ore/1"), "A ore inventory survived disconnect/reconnect")
	_assert(_all_mounts_empty(snapshot), "mount workflow ended with empty mount")
	_assert(Dictionary(snapshot.get("open_containers", {})).is_empty(), "external container sessions were closed")
	var a_result: Dictionary = a_cursor.get("contention_result", {})
	var winner_id := "a" if bool(a_result.get("success", false)) else "b"
	_assert(_hotbar_has(snapshot, winner_id, 2, "item/shared/beacon/1"), "winner hotbar assignment persisted canonically")
	_assert(int(a_cursor.get("ui", {}).get("ui_rejection_count", 0)) + int(b_wait.get("ui", {}).get("ui_rejection_count", 0)) >= 1, "UI surfaced contention rejection")
	_assert(int(a_cursor.get("ui", {}).get("ui_success_count", 0)) + int(b_wait.get("ui", {}).get("ui_success_count", 0)) >= 8, "UI recorded server-confirmed shared gameplay")
	_assert_clean_log(root.path_join("a1.log"), "A initial")
	_assert_clean_log(root.path_join("b.log"), "B")
	_assert_clean_log(root.path_join("a2.log"), "A reconnect")
	_assert(String(a_post.get("state", "")) != "FAILED" and String(b_post.get("state", "")) != "FAILED", "post-contention reports remained valid")
	_assert(bool(a2.get("passed", false)) and bool(b.get("passed", false)), "final clients passed")


func _write_control(path: String, updates: Dictionary) -> void:
	var current := Support.read(path)
	current["schema"] = Support.CONTROL_SCHEMA
	for key in updates.keys():
		current[key] = updates[key]
	Support.write(path, current)


func _wait_state(path: String, states: Array[String], timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var last: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		last = Support.read(path)
		if String(last.get("state", "")) in states:
			return last
		OS.delay_msec(POLL_MS)
	return last


func _wait_convergence_pair(a_path: String, b_path: String, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var a: Dictionary = {}
	var b: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		a = Support.read(a_path)
		b = Support.read(b_path)
		var a_state := String(a.get("state", ""))
		var b_state := String(b.get("state", ""))
		var a_player := String(a.get("player_checksum", ""))
		var b_player := String(b.get("player_checksum", ""))
		var a_item := String(a.get("item_checksum", ""))
		var b_item := String(b.get("item_checksum", ""))
		if (
			a_state in ["CONVERGENCE_LOCKED", "COMPLETE"]
			and b_state in ["CONVERGENCE_LOCKED", "COMPLETE"]
			and not a_player.is_empty()
			and a_player == b_player
			and not a_item.is_empty()
			and a_item == b_item
		):
			return {"success": true, "a": a, "b": b}
		OS.delay_msec(POLL_MS)
	return {"success": false, "a": a, "b": b}


func _wait_server_counts(path: String, joins: int, leaves: int, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var last: Dictionary = {}
	while Time.get_ticks_msec() - started <= timeout_ms:
		last = Support.read(path)
		if int(last.get("joins", 0)) >= joins and int(last.get("leaves", 0)) >= leaves:
			return last
		OS.delay_msec(POLL_MS)
	return last


func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_MS)


func _start_virtual_display() -> String:
	if not FileAccess.file_exists("/usr/bin/Xvfb"):
		return ""
	var base := 700 + (OS.get_process_id() % 200)
	for offset in range(20):
		var display_name := ":%d" % (base + offset)
		xvfb_pid = OS.create_process(
			"/usr/bin/Xvfb",
			[display_name, "-screen", "0", "1280x720x24", "-nolisten", "tcp", "-noreset"],
			false
		)
		if xvfb_pid <= 0:
			continue
		OS.delay_msec(600)
		if OS.is_process_running(xvfb_pid):
			child_pids.append(xvfb_pid)
			return display_name
	return ""


func _find_available_port() -> int:
	for port in range(45000 + (OS.get_process_id() % 500), 47000):
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "127.0.0.1") == OK:
			udp.close()
			return port
	return 0


func _count_item(snapshot: Dictionary, item_id: String) -> int:
	var count := 0
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			count += 1
	return count


func _item_in_one_inventory(snapshot: Dictionary, item_id: String) -> bool:
	var count := 0
	for value in snapshot.get("inventories", {}).values():
		if value is Dictionary and item_id in Array(value.get("inventory", [])):
			count += 1
	return count == 1


func _item_in_inventory(snapshot: Dictionary, player_id: String, item_id: String) -> bool:
	return item_id in Array(snapshot.get("inventories", {}).get(player_id, {}).get("inventory", []))


func _hotbar_has(snapshot: Dictionary, player_id: String, slot_index: int, item_id: String) -> bool:
	var hotbar: Array = Array(snapshot.get("inventories", {}).get(player_id, {}).get("hotbar", []))
	return slot_index >= 0 and slot_index < hotbar.size() and String(hotbar[slot_index]) == item_id


func _all_mounts_empty(snapshot: Dictionary) -> bool:
	for value in snapshot.get("mounts", []):
		if value is Dictionary and not String(value.get("item_id", "")).is_empty():
			return false
	return true


func _assert_clean_log(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path).to_lower() if FileAccess.file_exists(path) else ""
	_assert(not text.contains("objectdb instances leaked"), "%s has no ObjectDB leak" % label)
	_assert(not text.contains("resources still in use"), "%s has no resource leak" % label)
	_assert(not text.contains("failed to bind runtime bridge"), "%s has no MCP port collision" % label)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	for pid in child_pids.duplicate():
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	child_pids.clear()
	print("M5 graphical multiplayer acceptance: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)