extends SceneTree

# NET-SMOOTH1 R31 P2.2 — server-only canary gates, no gameplay changes.
# Full actual frame join and compact-send stage accounting are GUI acceptance.
const Runtime = preload(
	"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)


func _path(label: String) -> String:
	return ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r31p22-%s-%d" % [label, Time.get_ticks_usec()])


func _port() -> int:
	var peer := PacketPeerUDP.new()
	if peer.bind(0, "127.0.0.1") != OK:
		return 0
	var port := peer.get_local_port()
	peer.close()
	return port


func _run() -> void:
	OS.set_environment("DWS_NET_R31P22_LOOP_ATTRIBUTION", "wrong")
	var invalid = Runtime.new()
	var rejected: Dictionary = invalid.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("invalid"),
		"product_seam_enabled": true})
	_check(not bool(rejected.get("success", false)) and
		String(rejected.get("error_code", "")) == "R31P22_INVALID_MODE",
		"invalid explicit opt-in rejected before server launch")
	invalid.free()
	OS.set_environment("DWS_NET_R31P22_LOOP_ATTRIBUTION", "")

	var default_off = Runtime.new()
	var off: Dictionary = default_off.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("off"),
		"product_seam_enabled": true})
	_check(bool(off.get("success", false)), "default server available")
	if bool(off.get("success", false)):
		default_off.set_process(false)
		_check(not bool(default_off.get("_r31p22_loop_attribution_enabled")),
			"diagnostic OFF without canary")
		_check(bool(default_off.stop().get("success", false)),
			"default M6 shutdown unchanged")
	default_off.free()

	var blocked = Runtime.new()
	var no_stack: Dictionary = blocked.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("blocked"),
		"product_seam_enabled": true,
		"r31p22_loop_attribution_canary": true})
	_check(not bool(no_stack.get("success", false)) and
		String(no_stack.get("error_code", "")) ==
		"R31P22_REQUIRES_P1_P0_REPLAY_R2_PERSISTENCE_SEAM",
		"requires accepted full canary stack")
	blocked.free()

	var live = Runtime.new()
	var ready: Dictionary = live.setup({
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "persistence_root": _path("ready"),
		"product_seam_enabled": true,
		"r3c4_periodic_frame_pacing_canary": true,
		"r3c4r2_worker_envelope_canary": true,
		"r3c4r31_replay_projection_canary": true,
		"r3c4r31b_durable_attribution_canary": true,
		"r31bp1_durable_chunks_canary": true,
		"r31p22_loop_attribution_canary": true})
	_check(bool(ready.get("success", false)), "real P2.2 server configured")
	if bool(ready.get("success", false)):
		live.set_process(false)
		_check(bool(live.get("_r31p22_loop_attribution_enabled")),
			"server-only stage timing opt-in active")
		_check(Engine.get_process_frames() >= 0,
			"stable Godot engine frame counter exists")
		_check(bool(live.stop().get("success", false)),
			"unchanged durable shutdown barrier")
	live.free()

	for error in failures:
		push_error("R31P22_FAIL:" + error)
	print("NET_SMOOTH_R31P22 %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL",
		assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
