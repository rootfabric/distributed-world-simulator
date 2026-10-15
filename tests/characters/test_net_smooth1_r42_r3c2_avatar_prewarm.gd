extends SceneTree

# R3C.2: fail if client JOIN_ACK/reconnect instantiates the expensive
# Quaternius provider a second time. No network ownership or wire changes.
const Remote = preload("res://scripts/characters/runtime/earth_network_avatar_presenter.gd")
const Earth = preload("res://scripts/app/earth_char1_avatar_app.gd")

class FrameHost:
	extends Node3D
	var earth_world
	func _init():
		earth_world = Node3D.new()

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_host = FrameHost.new()
	root.add_child(root_host)
	var remote = Remote.new()
	remote.set_visual_character_id("character/quaternius/regular")
	var warmed: Dictionary = remote.prewarm_visual()
	check(bool(warmed.get("success", false)), "prewarm builds visual before any network JOIN")
	if not bool(warmed.get("success", false)):
		remote.free()
		_finish(root_host)
		return
	var original_host = remote.get("_avatar_host")
	check(original_host != null, "remote rig exists while no replica owner exists")
	check(remote.get("_delegate") == null, "no NX5 delegate/authority pre-JOIN")
	check(not remote.has_input_authority(), "prewarm grants no input authority")
	var again: Dictionary = remote.prewarm_visual("character/quaternius/regular")
	check(bool(again.get("success", false)) and bool(again.get("details", {}).get("reused", false)),
		"repeated prewarm is idempotent")
	check(remote.get("_avatar_host") == original_host, "same rig after repeat prewarm")
	check(not bool(remote.prewarm_visual("character/procedural/standard").get("success", false)),
		"prewarm with different character ID is rejected")

	root_host.add_child(remote)
	var original: Dictionary = remote.setup(
		_record(1, 1), _snapshot(100, 10, 1), Callable(self, "_map"))
	check(bool(original.get("success", false)), "canonical first remote setup accepted")
	if not bool(original.get("success", false)):
		_finish(root_host)
		return
	check(remote.get("_avatar_host") == original_host, "initial JOIN reused preloaded Quaternius rig")
	var original_delegate = remote.get("_delegate")
	check(original_delegate != null, "live canonical NX5 delegate created on first JOIN")
	var status: Dictionary = remote.get_report().get("char2_remote_avatar", {})
	check(status.get("provider_id", "") == "avatar/quaternius", "real provider retained")
	check(not bool(status.get("legacy_capsule_visible", true)), "legacy capsule never visible")
	await process_frame

	remote.visible = false
	remote.set_process(false)
	var rejoin: Dictionary = remote.setup(
		_record(2, 2), _snapshot(260, 1, 2), Callable(self, "_map"))
	check(bool(rejoin.get("success", false)), "fresh transport/recovery epoch accepted")
	check(remote.get("_avatar_host") == original_host, "reconnect cannot reload GLTF rig")
	check(remote.get("_delegate") != original_delegate, "fresh NX5 interpolation owner for new epoch")
	check(not remote.has_input_authority(), "reconnect never gives visual authority")
	check(String(remote.get_report().get("char2_remote_avatar", {}).get("provider_id", "")) == "avatar/quaternius",
		"remote provider unchanged after rebind")
	check(not bool(remote.get_report().get("char2_remote_avatar", {}).get("legacy_capsule_visible", true)),
		"no legacy body on reconnect")

	var app = Earth.new()
	app.set("_r3c2_visual_prewarm_enabled", true)
	var retained = Remote.new()
	app.add_child(retained)
	app.call("_retire_m3_remote_player_presenter", "b", retained)
	check(not retained.visible, "stale remote visual hidden")
	check(int(app.get("_r3c2_retained_remote_presenters").size()) == 1,
		"exact one bounded detached presentation cache record")
	var reused = app.call("_create_m3_remote_player_presenter_for", "b")
	check(reused == retained, "matching logical-player presenter reclaimed")
	check(reused.visible, "reclaimed visual is visible again")
	check(app.get("_r3c2_retained_remote_presenters").is_empty(),
		"claimed cache record removed, no duplicates")
	app.free()
	_finish(root_host)


func _snapshot(tick: int, rev: int, epoch: int) -> Dictionary:
	return {"server_tick": tick, "revision": rev, "authority_epoch": epoch}


func _record(rev: int, epoch: int) -> Dictionary:
	return {
		"logical_player_id": "b", "player_entity_id": "player/b",
		"transport_session_id": "transport-session/r3c2/b/%d" % epoch,
		"ownership_epoch": epoch, "connected": true,
		"position": {"x": 2.0, "y": 0.0, "z": 2.0},
		"velocity": {"x": 1.0, "y": 0.0, "z": 0.0},
		"inventory": [], "last_input_sequence": rev,
		"state_revision": rev, "orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}


func _map(x: float, z: float) -> Vector3:
	return Vector3(x, 100.0, z)


func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)


func _finish(host: Node) -> void:
	if host != null:
		host.queue_free()
	await process_frame
	for message in failures:
		push_error("[R3C2] " + message)
	print("NET_SMOOTH_R3C2_AVATAR_PREWARM %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
