extends SceneTree
const Interpolator = preload("res://scripts/network/interpolation/remote_snapshot_interpolator.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void:
	for speed in [0.0, 3.0, -5.0, 10.0]:
		for horizon in [0.0, 6.0]:
			var it = Interpolator.new()
			check(bool(it.configure({"max_extrapolation_ticks": horizon}).get("success", false)), "configure")
			check(bool(it.push_snapshot(record(0.0, speed, 1), 100, 1, 1).get("success", false)), "first snapshot")
			check(bool(it.push_snapshot(record(speed * 0.05, speed, 2), 103, 2, 1).get("success", false)), "second snapshot")
			var edge: Dictionary = it.sample_at_render_tick(103.0 + horizon).get("details", {})
			var held: Dictionary = it.sample_at_render_tick(103.0001 + horizon).get("details", {})
			check(String(held.get("mode", "")) == "HOLD_EXTRAPOLATION_LIMIT", "bounded HOLD mode")
			check((edge.get("position", Vector3.ZERO) as Vector3).distance_to(held.get("position", Vector3.ZERO)) < 0.000001, "NO_BACKWARD_JUMP_AT_HOLD speed=%s horizon=%s" % [speed, horizon])
			var later: Dictionary = it.sample_at_render_tick(10000.0).get("details", {})
			check((held.get("position", Vector3.ZERO) as Vector3).is_equal_approx(later.get("position", Vector3.ZERO)), "HOLD remains bounded")
			check(bool(it.push_snapshot(record(speed * 0.3, speed, 3), 118, 3, 1).get("success", false)), "resume snapshot accepted")
			var resumed: Dictionary = it.sample_at_render_tick(118.0).get("details", {})
			check((resumed.get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(speed * 0.3, 0, 0)), "new authoritative endpoint exact")
			it.reset()
			check(not bool(it.sample_at_render_tick(1000).get("success", true)), "reset removes extrapolated state")
	for f in failures: push_error(f)
	print("NET_SMOOTH1_HOLD: %s assertions=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func record(x: float, speed: float, revision: int) -> Dictionary:
	return {"logical_player_id":"b", "player_entity_id":"player/b", "transport_session_id":"transport-session/smooth/b/1", "ownership_epoch":1, "connected":true, "position":{"x":x,"y":0.0,"z":0.0}, "velocity":{"x":speed,"y":0.0,"z":0.0}, "inventory":[], "last_input_sequence":revision, "state_revision":revision, "orientation_yaw":0.0, "flashlight_enabled":false}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
