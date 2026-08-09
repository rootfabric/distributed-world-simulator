extends SceneTree

const POLL_MS := 50
const SERVER_CONVERGENCE_TIMEOUT_MS := 10000

var failures: Array[String] = []
var assertions := 0
var pids: Array[int] = []
var xvfb_pid := -1


func _init() -> void:
	var port := _find_port()
	_assert(port > 0, "port allocation")
	if port <= 0:
		_finish()
		return

	var out := ProjectSettings.globalize_path("res://artifacts/test-results/m4-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	var server_file := out.path_join("server.json")
	var a_file := out.path_join("a.json")
	var b_file := out.path_join("b.json")
	var display := ""
	if OS.get_name() == "Linux":
		display = _start_xvfb()
		_assert(not display.is_empty(), "Xvfb graphical display")

	var exe := OS.get_executable_path()
	var root_path := ProjectSettings.globalize_path("res://")
	var server := _spawn(
		exe,
		[
			"--headless",
			"--quiet",
			"--path",
			root_path,
			"--log-file",
			out.path_join("server.log"),
			"--",
			"--role=dedicated-server",
			"--world=moon",
			"--server-address=127.0.0.1",
			"--server-port=%d" % port,
			"--m3-result-file=%s" % server_file,
			"--shutdown-after-ms=180000",
		],
		out.path_join("user-server"),
		""
	)
	pids.append(server)
	_assert(server > 0, "dedicated server launch")
	var ready := _wait_state(server_file, ["READY", "FAILED"], 30000)
	_assert(String(ready.get("state", "")) == "READY", "dedicated server ready")
	if String(ready.get("state", "")) != "READY":
		_finish()
		return

	var a := _spawn_worker(
		exe, root_path, port, "a", 1, a_file, b_file,
		out.path_join("a.log"), out.path_join("user-a"), display
	)
	pids.append(a)
	_assert(a > 0, "graphical client A launch")
	var a_pick := _wait_state(a_file, ["A_PICKUP_DONE", "FAILED"], 60000)
	_assert(String(a_pick.get("state", "")) == "A_PICKUP_DONE", "A wins first pickup")

	var b := _spawn_worker(
		exe, root_path, port, "b", 2, b_file, a_file,
		out.path_join("b.log"), out.path_join("user-b"), display
	)
	pids.append(b)
	_assert(b > 0, "graphical client B launch while A connected")
	var ar := _wait_state(a_file, ["COMPLETE", "FAILED"], 90000)
	var br := _wait_state(b_file, ["COMPLETE", "FAILED"], 90000)
	_assert(bool(ar.get("passed", false)), "A canonical gameplay complete: %s" % ar)
	_assert(bool(br.get("passed", false)), "B contention and permission complete: %s" % br)

	_wait_exit(a, 10000)
	_wait_exit(b, 10000)

	# A and B only publish COMPLETE after their item replicas reach revision 12.
	# The server report is updated again while graceful LEAVE/disconnect is being
	# processed. On Windows AtomicJson's replace can expose a brief path gap, so
	# a one-shot FileAccess read here can observe {} even though authority and
	# both replicas have already converged. Wait for the authoritative report to
	# publish the exact checksum acknowledged by both clients instead of treating
	# the transient replace window as canonical state loss.
	var a_checksum := String(ar.get("item_graph", {}).get("checksum", ""))
	var b_checksum := String(br.get("item_graph", {}).get("checksum", ""))
	var expected_server_checksum := a_checksum if a_checksum == b_checksum else ""
	var final_server := _wait_server_item_graph(
		server_file,
		expected_server_checksum,
		SERVER_CONVERGENCE_TIMEOUT_MS
	)
	var snap: Dictionary = final_server.get("item_graph_snapshot", {})

	_assert(String(ar.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "A is graphical")
	_assert(String(br.get("display_server", "")).to_lower() not in ["", "headless", "dummy"], "B is graphical")
	_assert(String(ar.get("details", {}).get("pickup", {}).get("error_code", "")) == "", "A pickup succeeded")
	_assert(String(br.get("details", {}).get("pickup", {}).get("error_code", "")) == "ITEM_ALREADY_CLAIMED", "B deterministic contention rejection")
	_assert(String(br.get("details", {}).get("permission", {}).get("error_code", "")) == "PLAYER_PERMISSION_DENIED", "foreign inventory write rejected")
	_assert(_count_item(snap, "item/shared/beacon/1") == 1, "server canonical graph has one beacon")
	_assert(_container_has(snap, "container/shared/crate/1", "item/shared/beacon/1"), "beacon replicated in shared container")
	_assert(String(snap.get("checksum", "")).length() == 64, "server item graph checksum")
	_assert(a_checksum.length() == 64, "A received item graph replica")
	_assert(b_checksum.length() == 64, "B received item graph replica")
	_assert(a_checksum == b_checksum, "A and B item graph checksum convergence")
	_assert(String(snap.get("checksum", "")) == a_checksum, "server and clients item graph checksum convergence")
	_assert_clean(out.path_join("a.log"), "A")
	_assert_clean(out.path_join("b.log"), "B")
	_finish()


func _spawn_worker(
	exe: String,
	root_path: String,
	port: int,
	id: String,
	phase: int,
	result: String,
	peer: String,
	log: String,
	user: String,
	display: String
) -> int:
	return _spawn(
		exe,
		[
			"--quiet",
			"--path",
			root_path,
			"--rendering-method",
			"gl_compatibility",
			"--audio-driver",
			"Dummy",
			"--log-file",
			log,
			"--script",
			"res://tools/runtime/m4_graphical_item_client.gd",
			"--",
			"--host=127.0.0.1",
			"--port=%d" % port,
			"--client-id=%s" % id,
			"--phase=%d" % phase,
			"--result-file=%s" % result,
			"--peer-file=%s" % peer,
		],
		user,
		display
	)


func _spawn(exe: String, args: Array[String], user: String, display: String) -> int:
	var names := [
		"HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
		"APPDATA", "LOCALAPPDATA", "DISPLAY", "LIBGL_ALWAYS_SOFTWARE",
	]
	var old: Dictionary = {}
	for n in names:
		old[n] = {"set": OS.has_environment(n), "value": OS.get_environment(n)}
	for path in [user, user.path_join("data"), user.path_join("config"), user.path_join("cache")]:
		DirAccess.make_dir_recursive_absolute(path)
	OS.set_environment("HOME", user)
	OS.set_environment("XDG_DATA_HOME", user.path_join("data"))
	OS.set_environment("XDG_CONFIG_HOME", user.path_join("config"))
	OS.set_environment("XDG_CACHE_HOME", user.path_join("cache"))
	OS.set_environment("APPDATA", user.path_join("data"))
	OS.set_environment("LOCALAPPDATA", user.path_join("data"))
	if not display.is_empty():
		OS.set_environment("DISPLAY", display)
		OS.set_environment("LIBGL_ALWAYS_SOFTWARE", "1")
	var pid := OS.create_process(exe, args, false)
	for n in names:
		if bool(old[n]["set"]):
			OS.set_environment(n, String(old[n]["value"]))
		else:
			OS.unset_environment(n)
	return pid


func _start_xvfb() -> String:
	if not FileAccess.file_exists("/usr/bin/Xvfb"):
		return ""
	var d := ":%d" % (500 + OS.get_process_id() % 300)
	xvfb_pid = OS.create_process(
		"/usr/bin/Xvfb",
		[d, "-screen", "0", "1280x720x24", "-nolisten", "tcp", "-noreset"],
		false
	)
	pids.append(xvfb_pid)
	OS.delay_msec(500)
	return d if OS.is_process_running(xvfb_pid) else ""


func _wait_state(path: String, states: Array[String], timeout: int) -> Dictionary:
	var start := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - start < timeout:
		value = _read(path)
		if String(value.get("state", "")) in states:
			return value
		OS.delay_msec(POLL_MS)
	return value


func _wait_server_item_graph(path: String, expected_checksum: String, timeout: int) -> Dictionary:
	var start := Time.get_ticks_msec()
	var value: Dictionary = {}
	while Time.get_ticks_msec() - start < timeout:
		value = _read(path)
		var snapshot_value = value.get("item_graph_snapshot", {})
		if snapshot_value is Dictionary:
			var snapshot: Dictionary = snapshot_value
			var checksum := String(snapshot.get("checksum", ""))
			if not expected_checksum.is_empty() and checksum == expected_checksum:
				return value
		OS.delay_msec(POLL_MS)
	return value


func _wait_exit(pid: int, timeout: int) -> void:
	var start := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - start < timeout:
		OS.delay_msec(POLL_MS)


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}


func _count_item(s: Dictionary, id: String) -> int:
	var n := 0
	for item in s.get("items", []):
		if String(item.get("item_id", "")) == id:
			n += 1
	return n


func _container_has(s: Dictionary, cid: String, id: String) -> bool:
	for c in s.get("containers", []):
		if String(c.get("container_id", "")) == cid:
			return id in Array(c.get("slots", []))
	return false


func _assert_clean(path: String, label: String) -> void:
	var text := FileAccess.get_file_as_string(path).to_lower() if FileAccess.file_exists(path) else ""
	_assert(
		not text.contains("objectdb instances leaked") and not text.contains("resources still in use"),
		"%s clean shutdown" % label
	)


func _find_port() -> int:
	for p in range(42000 + OS.get_process_id() % 500, 44000):
		var udp := PacketPeerUDP.new()
		if udp.bind(p, "127.0.0.1") == OK:
			udp.close()
			return p
	return 0


func _assert(ok: bool, msg: String) -> void:
	assertions += 1
	if ok:
		print("PASS: %s" % msg)
	else:
		failures.append(msg)
		push_error("FAIL: %s" % msg)


func _finish() -> void:
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	print("M4 graphical shared gameplay: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
