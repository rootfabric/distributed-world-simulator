class_name Fabric0PersistentWrenchModeTransitionExperimentsV1
extends RefCounted

const Locator = preload("res://scripts/research/fabric0/fabric0_persistent_wrench_mode_event_locator_v1.gd")

static func evaluator(config: Dictionary) -> Callable:
	return func(time: float) -> Dictionary:
		return _ramp_eval(time, config)

static func single_channel_config(channel: String, root_time: float, reverse_identity: bool = false) -> Dictionary:
	var config := {
		"normal_initial": 10.0,
		"normal_rate": 0.0,
		"tangent_limit": 10.0,
		"tangent_rate": 0.0,
		"rolling_limit": 10.0,
		"rolling_rate": 0.0,
		"torsion_limit": 10.0,
		"torsion_rate": 0.0,
		"mobility": 2.0,
		"reverse_identity": reverse_identity,
	}
	if channel == "tangent":
		config["tangent_limit"] = root_time
		config["tangent_rate"] = 1.0
	elif channel == "rolling":
		config["rolling_limit"] = root_time
		config["rolling_rate"] = 1.0
	elif channel == "torsion":
		config["torsion_limit"] = root_time
		config["torsion_rate"] = 1.0
	elif channel == "support":
		config["normal_initial"] = root_time
		config["normal_rate"] = 1.0
	else:
		return {"bad_channel": channel}
	return config

static func near_coincident_config(reverse_identity: bool = false) -> Dictionary:
	return {
		"normal_initial": 2.0,
		"normal_rate": 0.5, # support separation at 4.0
		"tangent_limit": 1.0,
		"tangent_rate": 1.0,
		"rolling_limit": 1.0002,
		"rolling_rate": 1.0,
		"torsion_limit": 1.5,
		"torsion_rate": 1.0,
		"mobility": 2.0,
		"reverse_identity": reverse_identity,
	}

static func refinement_probe(channel: String, exact_root: float = 1.123456789) -> Dictionary:
	var config := single_channel_config(channel, exact_root)
	if config.has("bad_channel"):
		return {"ok": false, "code": "BAD_CHANNEL"}
	var eval := evaluator(config)
	var tolerances := [1.0e-4, 1.0e-6, 1.0e-8, 1.0e-10]
	var events: Array = []
	var errors: Array = []
	var uncertainties: Array = []
	var kind := String(Locator.KIND_BY_CHANNEL[channel])
	for tolerance_any in tolerances:
		var tolerance := float(tolerance_any)
		var event := Locator.localize_transition(eval, channel, kind, 0.0, exact_root + 0.5, tolerance, 63)
		if not bool(event.get("ok", false)):
			return {"ok": false, "code": "REFINEMENT_LOCALIZATION_FAILED", "channel": channel, "tolerance": tolerance, "detail": event}
		events.append(event)
		errors.append(absf(float(event["time"]) - exact_root))
		uncertainties.append(float(event["uncertainty"]))
	return {"ok": true, "channel": channel, "exact_root": exact_root, "tolerances": tolerances, "events": events, "errors": errors, "uncertainties": uncertainties}

static func near_coincident_probe(simultaneous_resolution: float, reverse_identity: bool = false, reverse_specs: bool = false) -> Dictionary:
	var specs: Array = [
		{"channel": "tangent", "kind": "STICK_TO_SLIDE"},
		{"channel": "rolling", "kind": "STICK_TO_ROLL"},
	]
	if reverse_specs:
		specs.reverse()
	return Locator.next_event_set(evaluator(near_coincident_config(reverse_identity)), specs, 0.0, 1.2, 1.0e-10, simultaneous_resolution, 64)

static func all_transition_probe() -> Dictionary:
	var roots := {"tangent": 0.812345679, "rolling": 1.012345679, "torsion": 1.212345679, "support": 1.412345679}
	var events: Dictionary = {}
	for channel in ["tangent", "rolling", "torsion", "support"]:
		var config := single_channel_config(channel, float(roots[channel]))
		var event := Locator.localize_transition(evaluator(config), channel, String(Locator.KIND_BY_CHANNEL[channel]), 0.0, 2.0, 1.0e-10, 64)
		if not bool(event.get("ok", false)):
			return {"ok": false, "code": "TRANSITION_PROBE_FAILED", "channel": channel, "detail": event}
		events[channel] = event
	return {"ok": true, "roots": roots, "events": events}

static func _ramp_eval(time: float, config: Dictionary) -> Dictionary:
	if time < 0.0 or not is_finite(time):
		return {"ok": false, "code": "BAD_TIME"}
	var normal_raw := float(config.get("normal_initial", 10.0)) - float(config.get("normal_rate", 0.0)) * time
	var tangent_limit := float(config.get("tangent_limit", 10.0))
	var rolling_limit := float(config.get("rolling_limit", 10.0))
	var torsion_limit := float(config.get("torsion_limit", 10.0))
	var tangent_demand := float(config.get("tangent_rate", 0.0)) * time
	var rolling_demand := float(config.get("rolling_rate", 0.0)) * time
	var torsion_demand := float(config.get("torsion_rate", 0.0)) * time
	var mobility := float(config.get("mobility", 2.0))
	var tangent_excess := maxf(0.0, absf(tangent_demand) - tangent_limit)
	var rolling_excess := maxf(0.0, absf(rolling_demand) - rolling_limit)
	var torsion_excess := maxf(0.0, absf(torsion_demand) - torsion_limit)
	var impulse := [
		minf(absf(tangent_demand), tangent_limit) * signf(tangent_demand),
		0.0,
		minf(absf(rolling_demand), rolling_limit) * signf(rolling_demand),
		0.0,
		minf(absf(torsion_demand), torsion_limit) * signf(torsion_demand),
	]
	var velocity := [
		tangent_excess * mobility * signf(tangent_demand),
		0.0,
		rolling_excess * mobility * signf(rolling_demand),
		0.0,
		torsion_excess * mobility * signf(torsion_demand),
	]
	var observation := {"body_a": "floor", "body_b": "body", "members": ["p0", "p1", "p2", "p3"]}
	if bool(config.get("reverse_identity", false)):
		observation = {"body_a": "body", "body_b": "floor", "members": ["p3", "p2", "p1", "p0"]}
	return {
		"ok": true,
		"observation": observation,
		"solved": {
			"normal_support": maxf(0.0, normal_raw),
			"generalized_impulse": impulse,
			"generalized_velocity_after": velocity,
			"limits": {"tangent": tangent_limit, "rolling": rolling_limit, "torsion": torsion_limit},
		},
		"guards": {
			"tangent": tangent_limit - absf(tangent_demand),
			"rolling": rolling_limit - absf(rolling_demand),
			"torsion": torsion_limit - absf(torsion_demand),
			"support": normal_raw,
		},
		"stick_demand": {"tangent": tangent_demand, "rolling": rolling_demand, "torsion": torsion_demand},
	}
