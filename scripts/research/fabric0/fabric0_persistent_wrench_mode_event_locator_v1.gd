class_name Fabric0PersistentWrenchModeEventLocatorV1
extends RefCounted

const State = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_contact_state_v1.gd")
const EPS := 1.0e-14
const CHANNELS := ["tangent", "rolling", "torsion", "support"]
const KIND_BY_CHANNEL := {
	"tangent": "STICK_TO_SLIDE",
	"rolling": "STICK_TO_ROLL",
	"torsion": "STICK_TO_SPIN",
	"support": "SUPPORT_TO_SEPARATION",
}

static func localize_transition(
	evaluator: Callable,
	channel: String,
	kind: String,
	start_time: float,
	horizon: float,
	root_tolerance: float = 1.0e-9,
	scan_steps: int = 64,
	options: Dictionary = {}
) -> Dictionary:
	var valid := _validate_request(evaluator, channel, kind, start_time, horizon, root_tolerance, scan_steps)
	if not bool(valid.get("ok", false)):
		return valid
	var end_time := start_time + horizon
	var first := _sample(evaluator, start_time, channel, options)
	if not bool(first.get("ok", false)):
		return first
	var g0 := float(first["guard"])
	if g0 <= 0.0:
		return {"ok": false, "code": "TRANSITION_ALREADY_REACHED", "channel": channel, "kind": kind, "time": start_time, "guard": g0}
	var lo_time := start_time
	var lo := first
	var hi_time := INF
	var hi: Dictionary = {}
	for step in range(1, scan_steps + 1):
		var t := start_time + horizon * float(step) / float(scan_steps)
		var current := _sample(evaluator, t, channel, options)
		if not bool(current.get("ok", false)):
			return current
		if float(current["guard"]) <= 0.0:
			hi_time = t
			hi = current
			break
		lo_time = t
		lo = current
	if not is_finite(hi_time):
		return {"ok": false, "code": "NO_TRANSITION_IN_HORIZON", "channel": channel, "kind": kind, "start_time": start_time, "end_time": end_time}

	var iterations := 0
	while hi_time - lo_time > root_tolerance:
		iterations += 1
		if iterations > 256:
			return {"ok": false, "code": "ROOT_LOCALIZATION_ITERATION_LIMIT", "channel": channel, "kind": kind}
		var mid_time := 0.5 * (lo_time + hi_time)
		var mid := _sample(evaluator, mid_time, channel, options)
		if not bool(mid.get("ok", false)):
			return mid
		if float(mid["guard"]) > 0.0:
			lo_time = mid_time
			lo = mid
		else:
			hi_time = mid_time
			hi = mid

	var event_time := hi_time
	var uncertainty := hi_time - lo_time
	var semantic := _semantic_audit(evaluator, channel, kind, event_time, start_time, end_time, root_tolerance, options)
	if not bool(semantic.get("ok", false)):
		return semantic
	return {
		"ok": true,
		"kind": kind,
		"channel": channel,
		"event_id": channel + ":" + kind,
		"time": event_time,
		"bracket": [lo_time, hi_time],
		"uncertainty": uncertainty,
		"guard_before": float(lo["guard"]),
		"guard_after": float(hi["guard"]),
		"iterations": iterations,
		"pre_state": semantic["pre_state"],
		"post_state": semantic["post_state"],
		"transition_hypothesis": semantic["transition_hypothesis"],
		"signature": JSON.stringify({"event_id": channel + ":" + kind, "time": event_time, "bracket": [lo_time, hi_time]}, "", false),
	}

static func next_event_set(
	evaluator: Callable,
	event_specs: Array,
	start_time: float,
	horizon: float,
	root_tolerance: float = 1.0e-9,
	simultaneous_resolution: float = 1.0e-6,
	scan_steps: int = 64,
	options: Dictionary = {}
) -> Dictionary:
	if event_specs.is_empty():
		return {"ok": false, "code": "EMPTY_EVENT_SPEC_SET"}
	if simultaneous_resolution < 0.0 or not is_finite(simultaneous_resolution):
		return {"ok": false, "code": "BAD_SIMULTANEOUS_RESOLUTION"}
	var localized: Array = []
	for spec_any in event_specs:
		if not (spec_any is Dictionary):
			return {"ok": false, "code": "BAD_EVENT_SPEC"}
		var spec: Dictionary = spec_any
		var channel := String(spec.get("channel", ""))
		var kind := String(spec.get("kind", KIND_BY_CHANNEL.get(channel, "")))
		var event := localize_transition(evaluator, channel, kind, start_time, horizon, root_tolerance, scan_steps, options)
		if bool(event.get("ok", false)):
			localized.append(event)
		elif String(event.get("code", "")) != "NO_TRANSITION_IN_HORIZON":
			return event
	if localized.is_empty():
		return {"ok": false, "code": "NO_MODE_EVENT_IN_HORIZON"}
	localized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := float(a["time"])
		var tb := float(b["time"])
		if absf(ta - tb) > EPS:
			return ta < tb
		return String(a["event_id"]) < String(b["event_id"])
	)
	var earliest := float(localized[0]["time"])
	var members: Array = []
	var deferred: Array = []
	for event_any in localized:
		var event: Dictionary = event_any
		if absf(float(event["time"]) - earliest) <= simultaneous_resolution:
			members.append(event)
		else:
			deferred.append(event)
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["event_id"]) < String(b["event_id"]))
	deferred.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["time"]) - float(b["time"])) > EPS:
			return float(a["time"]) < float(b["time"])
		return String(a["event_id"]) < String(b["event_id"])
	)
	var ids: Array = []
	for event_any in members:
		ids.append(String(Dictionary(event_any)["event_id"]))
	return {
		"ok": true,
		"kind": "PERSISTENT_WRENCH_MODE_EVENT_SET",
		"time": earliest,
		"event_ids": ids,
		"members": members,
		"deferred_events": deferred,
		"root_tolerance": root_tolerance,
		"simultaneous_resolution": simultaneous_resolution,
		"signature": JSON.stringify({"time": earliest, "event_ids": ids}, "", false),
	}

static func _validate_request(evaluator: Callable, channel: String, kind: String, start_time: float, horizon: float, root_tolerance: float, scan_steps: int) -> Dictionary:
	if not evaluator.is_valid():
		return {"ok": false, "code": "BAD_EVALUATOR"}
	if not CHANNELS.has(channel):
		return {"ok": false, "code": "BAD_TRANSITION_CHANNEL", "channel": channel}
	if kind != String(KIND_BY_CHANNEL[channel]):
		return {"ok": false, "code": "TRANSITION_KIND_CHANNEL_MISMATCH", "channel": channel, "kind": kind, "expected": KIND_BY_CHANNEL[channel]}
	if not is_finite(start_time) or start_time < 0.0:
		return {"ok": false, "code": "BAD_START_TIME"}
	if not is_finite(horizon) or horizon <= 0.0:
		return {"ok": false, "code": "BAD_HORIZON"}
	if not is_finite(root_tolerance) or root_tolerance <= 0.0 or root_tolerance >= horizon:
		return {"ok": false, "code": "BAD_ROOT_TOLERANCE"}
	if scan_steps < 2:
		return {"ok": false, "code": "BAD_SCAN_STEPS"}
	return {"ok": true}

static func _sample(evaluator: Callable, time: float, channel: String, options: Dictionary) -> Dictionary:
	var raw = evaluator.call(time)
	if not (raw is Dictionary):
		return {"ok": false, "code": "EVALUATOR_NON_DICTIONARY", "time": time}
	var sample: Dictionary = raw
	if not bool(sample.get("ok", false)):
		return {"ok": false, "code": "EVALUATOR_FAILED", "time": time, "detail": sample}
	if not sample.has("observation") or not sample.has("solved") or not sample.has("guards"):
		return {"ok": false, "code": "EVALUATOR_INCOMPLETE", "time": time}
	var guards = sample["guards"]
	if not (guards is Dictionary) or not Dictionary(guards).has(channel):
		return {"ok": false, "code": "EVALUATOR_GUARD_MISSING", "channel": channel, "time": time}
	var guard_value = Dictionary(guards)[channel]
	if not (guard_value is int or guard_value is float) or not is_finite(float(guard_value)):
		return {"ok": false, "code": "EVALUATOR_GUARD_NONFINITE", "channel": channel, "time": time}
	var state := State.begin(Dictionary(sample["observation"]), Dictionary(sample["solved"]), time, options)
	if not bool(state.get("ok", false)):
		return {"ok": false, "code": "EVALUATOR_STATE_INVALID", "channel": channel, "time": time, "detail": state}
	return {"ok": true, "guard": float(guard_value), "sample": sample, "state": state}

static func _semantic_audit(evaluator: Callable, channel: String, kind: String, event_time: float, start_time: float, end_time: float, root_tolerance: float, options: Dictionary) -> Dictionary:
	var probe := maxf(float(options.get("semantic_probe", 1.0e-7)), 32.0 * root_tolerance)
	var before_time := maxf(start_time, event_time - probe)
	var after_time := minf(end_time, event_time + probe)
	if before_time >= event_time or after_time <= event_time:
		return {"ok": false, "code": "SEMANTIC_PROBE_WINDOW_COLLAPSED", "channel": channel, "kind": kind}
	var before := _sample(evaluator, before_time, channel, options)
	if not bool(before.get("ok", false)):
		return before
	var after := _sample(evaluator, after_time, channel, options)
	if not bool(after.get("ok", false)):
		return after
	if float(before["guard"]) <= 0.0 or float(after["guard"]) >= 0.0:
		return {"ok": false, "code": "TRANSITION_GUARD_DIRECTION_INVALID", "channel": channel, "kind": kind, "before_guard": before["guard"], "after_guard": after["guard"]}
	var pre_state: Dictionary = before["state"]
	var post_state: Dictionary
	var hypothesis: Dictionary = {}
	if channel == "support":
		if not bool(pre_state.get("active", false)):
			return {"ok": false, "code": "SUPPORT_PRE_STATE_NOT_ACTIVE"}
		if bool(Dictionary(after["state"]).get("active", true)):
			return {"ok": false, "code": "SUPPORT_POST_STATE_STILL_ACTIVE"}
		post_state = State.separate(pre_state, after_time)
		if not bool(post_state.get("ok", false)):
			return {"ok": false, "code": "SEPARATION_STATE_BUILD_FAILED", "detail": post_state}
		hypothesis = Dictionary(post_state.get("mode_transition_hypothesis", {}))
	else:
		if String(Dictionary(pre_state["modes"])[channel]) != "stick":
			return {"ok": false, "code": "PRE_TRANSITION_MODE_NOT_STICK", "channel": channel, "mode": Dictionary(pre_state["modes"])[channel]}
		post_state = State.advance(pre_state, Dictionary(Dictionary(after["sample"])["observation"]), Dictionary(Dictionary(after["sample"])["solved"]), after_time, options)
		if not bool(post_state.get("ok", false)):
			return {"ok": false, "code": "POST_TRANSITION_STATE_INVALID", "channel": channel, "detail": post_state}
		var expected_mode: String = String({"tangent": "slide", "rolling": "roll", "torsion": "spin"}[channel])
		if String(Dictionary(post_state["modes"])[channel]) != String(expected_mode):
			return {"ok": false, "code": "POST_TRANSITION_MODE_MISMATCH", "channel": channel, "expected": expected_mode, "actual": Dictionary(post_state["modes"])[channel]}
		hypothesis = Dictionary(post_state.get("mode_transition_hypothesis", {}))
	return {"ok": true, "pre_state": pre_state, "post_state": post_state, "transition_hypothesis": hypothesis}
