class_name FabricConstruct0FabricPlayback
extends RefCounted

const Trajectory = preload("res://scripts/research/fabric0/fabric0_persistent_contact_trajectory_v1.gd")
const EPS := 1.0e-12

var _run: Dictionary = {}
var _samples: Array = []

func setup(root_tolerance: float = 1.0e-9) -> Dictionary:
	var run := Trajectory.run(root_tolerance)
	if not bool(run.get("ok", false)):
		return {"success": false, "error_code": "CONSTRUCT0_FABRIC_TRAJECTORY_FAILED", "detail": run}
	_run = run
	_samples = _build_samples(run)
	if _samples.is_empty():
		return {"success": false, "error_code": "CONSTRUCT0_FABRIC_PLAYBACK_EMPTY"}
	return {
		"success": true,
		"signature": String(run["signature"]),
		"timeline_ids": Array(run["timeline_ids"]).duplicate(true),
		"timeline_times": Array(run["timeline_times"]).duplicate(true),
		"sample_count": _samples.size(),
		"final_time": float(Trajectory.FINAL_TIME),
	}

func is_ready() -> bool:
	return not _run.is_empty() and not _samples.is_empty()

func reset() -> Dictionary:
	if not is_ready():
		var ready := setup()
		if not bool(ready.get("success", false)):
			return ready
	return sample(0.0)

func sample(time: float) -> Dictionary:
	if not is_ready():
		var ready := setup()
		if not bool(ready.get("success", false)):
			return ready
	if not is_finite(time):
		return {"success": false, "error_code": "CONSTRUCT0_PLAYBACK_TIME_NONFINITE"}
	var t := clampf(time, 0.0, float(Trajectory.FINAL_TIME))
	var impact_time := float(_run["impact"]["time"])
	if t < impact_time:
		return {
			"success": true,
			"time": t,
			"position": Vector3(0.0, float(Trajectory.IMPACT_HEIGHT) + float(Trajectory.IMPACT_VY) * t, 0.0),
			"orientation": Quaternion.IDENTITY,
			"linear_velocity": Vector3(0.0, float(Trajectory.IMPACT_VY), 0.0),
			"angular_velocity": Vector3.ZERO,
			"event_id": "FREE_FALL",
			"phase": "FREE",
		}
	var left: Dictionary = _samples[0]
	for index in range(1, _samples.size()):
		var right: Dictionary = _samples[index]
		if t < float(right["time"]) - EPS:
			return _sample_from(left, t)
		left = right
	return _sample_from(left, t)

func next_event_time(time: float) -> float:
	if not is_ready():
		var ready := setup()
		if not bool(ready.get("success", false)):
			return 0.0
	for raw in _run["timeline_times"]:
		var candidate := float(raw)
		if candidate > time + 1.0e-10:
			return candidate
	return float(Trajectory.FINAL_TIME)

func get_timeline_ids() -> Array:
	return Array(_run.get("timeline_ids", [])).duplicate(true)

func get_timeline_times() -> Array:
	return Array(_run.get("timeline_times", [])).duplicate(true)

func get_signature() -> String:
	return String(_run.get("signature", ""))

func get_final_time() -> float:
	return float(Trajectory.FINAL_TIME)

func timeline_text() -> String:
	if not is_ready():
		return "FABRIC trajectory not prepared"
	var lines: Array[String] = []
	var ids: Array = _run["timeline_ids"]
	var times: Array = _run["timeline_times"]
	for index in range(ids.size()):
		lines.append("%0.9f  %s" % [float(times[index]), String(ids[index])])
	return "\n".join(lines)

func _build_samples(run: Dictionary) -> Array:
	var result: Array = []
	var impact_time := float(run["impact"]["time"])
	var impact_body: Dictionary = run["impact_solve"]["post_body"]
	var position := Vector3.ZERO
	var orientation := Quaternion.IDENTITY
	var current_v: Vector3 = impact_body["v"]
	var current_w: Vector3 = impact_body["w"]
	result.append({
		"time": impact_time,
		"position": position,
		"orientation": orientation,
		"v": current_v,
		"w": current_w,
		"event_id": "impact:ACQUIRE_PERSISTENT_SUPPORT",
		"phase": "PERSISTENT_CONTACT",
	})

	var records: Array = run["events"]
	var state_vector: Array = run["event_state_vector"]
	if state_vector.size() != records.size() * 8:
		return []
	var previous_time := impact_time
	for index in range(records.size()):
		var record: Dictionary = records[index]
		var event_time := float(record["time"])
		var dt := maxf(0.0, event_time - previous_time)
		position += current_v * dt
		orientation = _integrate_orientation(orientation, current_w, dt)
		var offset := index * 8
		current_v = Vector3(
			float(state_vector[offset + 0]),
			float(state_vector[offset + 1]),
			float(state_vector[offset + 2])
		)
		current_w = Vector3(
			float(state_vector[offset + 3]),
			float(state_vector[offset + 4]),
			float(state_vector[offset + 5])
		)
		result.append({
			"time": event_time,
			"position": position,
			"orientation": orientation,
			"v": current_v,
			"w": current_w,
			"event_id": String(record["event_id"]),
			"phase": _phase_after_event(String(record["event_id"])),
		})
		previous_time = event_time

	var final_time := float(Trajectory.FINAL_TIME)
	var final_dt := maxf(0.0, final_time - previous_time)
	position += current_v * final_dt
	orientation = _integrate_orientation(orientation, current_w, final_dt)
	var final_body: Dictionary = run["final_body"]
	var final_v: Vector3 = final_body["v"]
	var final_w: Vector3 = final_body["w"]
	result.append({
		"time": final_time,
		"position": position,
		"orientation": orientation,
		"v": final_v,
		"w": final_w,
		"event_id": "FINAL",
		"phase": "POST_EVENTS",
	})
	return result

func _sample_from(base: Dictionary, time: float) -> Dictionary:
	var dt := maxf(0.0, time - float(base["time"]))
	var v: Vector3 = base["v"]
	var w: Vector3 = base["w"]
	var base_position: Vector3 = base["position"]
	var base_orientation: Quaternion = base["orientation"]
	return {
		"success": true,
		"time": time,
		"position": base_position + v * dt,
		"orientation": _integrate_orientation(base_orientation, w, dt),
		"linear_velocity": v,
		"angular_velocity": w,
		"event_id": String(base["event_id"]),
		"phase": String(base["phase"]),
	}

func _integrate_orientation(base: Quaternion, angular_velocity: Vector3, dt: float) -> Quaternion:
	var speed := angular_velocity.length()
	if speed <= EPS or dt <= 0.0:
		return base
	var delta := Quaternion(angular_velocity / speed, speed * dt)
	return (delta * base).normalized()

func _phase_after_event(event_id: String) -> String:
	if event_id.contains("STICK_TO_SLIDE"):
		return "SLIDE"
	if event_id.contains("STICK_TO_ROLL"):
		return "ROLL"
	if event_id.contains("STICK_TO_SPIN"):
		return "SPIN"
	if event_id.contains("SUPPORT_TO_SEPARATION"):
		return "SEPARATION"
	return "PERSISTENT_CONTACT"
