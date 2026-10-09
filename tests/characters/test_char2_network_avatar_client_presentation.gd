extends SceneTree

# CHAR2 visual-only two-view client falsifier. It uses real NX5 snapshot clocks
# and the accepted Earth wrapper; no mock network authority or new wire field.
const Remote = preload("res://scripts/characters/runtime/earth_network_avatar_presenter.gd")
const EarthChar1 = preload("res://scripts/app/earth_char1_avatar_app.gd")
const Local = preload("res://scripts/characters/runtime/earth_local_avatar_presenter.gd")

class FakeWorld:
	extends Node3D
	var render_origin := Vector3(0.0, 100.0, 0.0)
	func get_render_origin() -> Vector3:
		return render_origin

class FakeExplorer:
	extends Node3D
	var frame_position := Vector3(0.0, 105.0, 0.0)
	func get_frame_position() -> Vector3:
		return frame_position
	func get_surface_relative_yaw() -> float:
		return 0.0

class WorldHost:
	extends Node3D
	var earth_world

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var app = EarthChar1.new()
	var factory = app._create_m3_remote_player_presenter()
	_check(factory is Remote, "Earth product factory creates the provider-backed remote")
	_check(not factory.has_input_authority(), "factory never gives remote input authority")
	factory.free()
	app.free()

	var host := WorldHost.new()
	var world := FakeWorld.new()
	host.earth_world = world
	root.add_child(host)
	host.add_child(world)
	var record := _record(1, Vector3(1.0, 0.0, 2.0), Vector3(2.0, 0.0, 0.0), 1)
	var snapshot := _snapshot(100, 10, 1)
	var remote = Remote.new()
	host.add_child(remote)
	var initialized: Dictionary = remote.setup(record, snapshot, Callable(self, "_map_position"))
	_check(bool(initialized.get("success", false)), "remote presenter setup through interface")
	if not bool(initialized.get("success", false)):
		_finish(host)
		return
	await process_frame
	var report: Dictionary = remote.get_report()
	var visual: Dictionary = report.get("char2_remote_avatar", {})
	_check(bool(visual.get("ready", false)), "remote avatar provider ready")
	_check(String(visual.get("character_id", "")) == "character/quaternius/regular", "Quaternius character selected")
	_check(String(visual.get("provider_id", "")) == "avatar/quaternius", "real avatar provider registered")
	_check(not bool(visual.get("legacy_capsule_visible", true)), "legacy network capsule hidden")
	_check(not remote.has_input_authority(), "remote cannot own input")
	_check(String(report.get("schema", "")) == "planet_simulator.remote_player_presenter.v2", "original wire presenter schema preserved")
	_check(int(report.get("interpolation", {}).get("latest_server_tick", -1)) == 100, "NX5 canonical snapshot clock used")
	_check(int(visual.get("motion_updates", 0)) >= 1, "remote semantic motion follows interpolator")
	_check(String(visual.get("provider_state", {}).get("presenter", {}).get("engine", {}).get("current_semantic", "")) == "walk", "remote animation follows velocity")
	_check(int(visual.get("motion_failures", -1)) == 0, "no rejected animation mapping")
	var projected := remote.position
	world.render_origin += Vector3(0.0, 25.0, 0.0)
	await process_frame
	_check(absf(remote.position.y - projected.y + 25.0) < 0.01, "remote model follows shared floating-origin frame")
	_check(not remote.get_report().get("char2_remote_avatar", {}).get("legacy_capsule_visible", true), "legacy capsule remains hidden after reprojection")
	var next := _record(2, Vector3(2.0, 0.0, 2.0), Vector3(6.0, 0.0, 0.0), 1)
	var accepted: Dictionary = remote.apply_replica(next, _snapshot(106, 11, 1))
	_check(bool(accepted.get("success", false)), "new network sample accepted unchanged")
	for i in range(8):
		await process_frame
	var motion_report: Dictionary = remote.get_report().get("char2_remote_avatar", {})
	_check(String(motion_report.get("provider_state", {}).get("presenter", {}).get("engine", {}).get("current_semantic", "")) == "run", "remote run animation follows network velocity")
	_check(String(remote.get_report().get("presentation_owner", "")) == "NX5_RENDER_SAMPLE", "NX5 interpolation owner unchanged")
	var rejoin := _record(3, Vector3(10.0, 0.0, 2.0), Vector3.ZERO, 2)
	rejoin["transport_session_id"] = "transport-session/char2/b/restart"
	accepted = remote.apply_replica(rejoin, _snapshot(200, 1, 2))
	_check(bool(accepted.get("success", false)), "reconnect epoch accepted")
	await process_frame
	_check(String(remote.get_report().get("char2_remote_avatar", {}).get("provider_state", {}).get("presenter", {}).get("engine", {}).get("current_semantic", "")) == "idle", "remote avatar returns to idle after reconnect")
	_check(not remote.has_input_authority(), "no input ownership after reconnect")
	_check(not bool(remote.get_report().get("char2_remote_avatar", {}).get("legacy_capsule_visible", true)), "capsule does not reappear across reconnect")

	var local = Local.new()
	host.add_child(local)
	var explorer := FakeExplorer.new()
	host.add_child(explorer)
	var local_setup: Dictionary = local.setup(world, explorer, "character/quaternius/regular")
	_check(bool(local_setup.get("success", false)), "local avatar setup independent of remote")
	if bool(local_setup.get("success", false)):
		_check(not bool(local.create_report().get("local_body_visible", true)), "local first-person body hidden")
		_check(bool(remote.get_report().get("char2_remote_avatar", {}).get("ready", false)), "local first-person does not hide remote")
		local.set_first_person_mode(false)
		_check(bool(local.create_report().get("local_body_visible", false)), "local third-person body shown")
		local.set_first_person_mode(true)
		_check(not bool(local.create_report().get("local_body_visible", true)), "local body rehidden on return")
		_check(bool(remote.get_report().get("char2_remote_avatar", {}).get("ready", false)), "remote remains visible through view switches")
	_finish(host)


func _map_position(x: float, z: float) -> Vector3:
	return Vector3(x, 101.75, z)


func _snapshot(tick: int, revision: int, epoch: int) -> Dictionary:
	return {"server_tick": tick, "revision": revision, "authority_epoch": epoch}


func _record(revision: int, at: Vector3, velocity: Vector3, epoch: int) -> Dictionary:
	return {
		"logical_player_id": "b",
		"player_entity_id": "player/b",
		"transport_session_id": "transport-session/char2/b/initial",
		"ownership_epoch": epoch,
		"connected": true,
		"position": {"x": at.x, "y": at.y, "z": at.z},
		"velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z},
		"inventory": [],
		"last_input_sequence": revision,
		"state_revision": revision,
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}


func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)


func _finish(node: Node) -> void:
	if node != null:
		node.queue_free()
	await process_frame
	if failures.is_empty():
		print("CHAR2 NETWORK AVATAR CLIENT: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for msg in failures:
			push_error("[CHAR2] " + msg)
		print("CHAR2 NETWORK AVATAR CLIENT: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)
