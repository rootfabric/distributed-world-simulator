extends RefCounted

const EnvGradient = preload("res://scripts/research/ecology/plant_environmental_gradient_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p3_5_seasonal_world.v1"
const VERSION := "1.0.0"
const PARENT_P3_4_CANDIDATE_AGGREGATE := "a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813"
const EPSILON := 0.000000000001
const MAX_EXACT_CYCLE_INDEX := 9007199254740991.0
const CHANNELS := ["temperature_c", "moisture", "light", "nutrients"]
const NORMALIZED_CHANNELS := ["moisture", "light", "nutrients"]
const CONFIG_FIELDS := ["cycle", "temperature_c", "moisture", "light", "nutrients"]
const CYCLE_FIELDS := ["period_years", "epoch_year", "phase_x_slope", "phase_y_slope", "phase_altitude_slope"]
const CHANNEL_CONFIG_FIELDS := ["amplitude", "phase_offset"]
const RESULT_FIELDS := ["schema", "version", "parent_p3_4_candidate_aggregate", "environment_result", "environment_result_hash", "season_config", "time_years", "global_phase01", "cycle_index", "patch_order", "patches", "edge_seasonal_gradients", "summary", "result_hash"]
const PATCH_FIELDS := ["id", "x", "y", "altitude", "parent_patch_record_hash", "local_phase01", "temperature_c", "temperature_delta_c", "moisture", "moisture_delta", "light", "light_delta", "nutrients", "nutrients_delta", "resource_availability", "record_hash"]
const EDGE_FIELDS := ["from", "to", "parent_edge_gradient_record_hash", "temperature_delta_c", "moisture_delta", "light_delta", "nutrients_delta", "record_hash"]
const SUMMARY_FIELDS := ["patch_count", "global_phase01", "temperature_min_c", "temperature_max_c", "moisture_min", "moisture_max", "light_min", "light_max", "nutrients_min", "nutrients_max"]

static func evaluate(environment_result: Dictionary, time_years_value, config: Dictionary) -> Dictionary:
	if not bool(EnvGradient.validate_result(environment_result).get("success", false)):
		return {}
	if typeof(time_years_value) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	var time_years := float(time_years_value)
	if not is_finite(time_years):
		return {}
	var normalized_config := _normalize_config(config)
	if normalized_config.is_empty():
		return {}
	var phase_state := _phase_state(time_years, Dictionary(normalized_config["cycle"]))
	if phase_state.is_empty():
		return {}
	var patch_order := PackedStringArray(environment_result.get("patch_order", PackedStringArray()))
	var parent_patches: Array = environment_result.get("patches", [])
	if parent_patches.size() != patch_order.size():
		return {}
	var parent_origin_value = Dictionary(environment_result.get("field_config", {})).get("origin")
	if typeof(parent_origin_value) != TYPE_DICTIONARY:
		return {}
	var parent_origin: Dictionary = parent_origin_value
	var parent_bounds := _parent_bounds(environment_result)
	if parent_bounds.is_empty():
		return {}

	var patches: Array[Dictionary] = []
	var patches_by_id := {}
	for index in range(parent_patches.size()):
		if typeof(parent_patches[index]) != TYPE_DICTIONARY:
			return {}
		var parent_patch: Dictionary = parent_patches[index]
		if String(parent_patch.get("id", "")) != String(patch_order[index]):
			return {}
		var patch := _seasonal_patch(parent_patch, parent_origin, parent_bounds, float(phase_state["global_phase01"]), normalized_config)
		if patch.is_empty():
			return {}
		patches.append(patch)
		patches_by_id[String(patch["id"])] = patch

	var parent_edges: Array = environment_result.get("edge_gradients", [])
	var edges: Array[Dictionary] = []
	for parent_edge_value in parent_edges:
		if typeof(parent_edge_value) != TYPE_DICTIONARY:
			return {}
		var parent_edge: Dictionary = parent_edge_value
		var from_id := String(parent_edge.get("from", ""))
		var to_id := String(parent_edge.get("to", ""))
		if not patches_by_id.has(from_id) or not patches_by_id.has(to_id):
			return {}
		var from_patch: Dictionary = patches_by_id[from_id]
		var to_patch: Dictionary = patches_by_id[to_id]
		var edge := {
			"from": from_id,
			"to": to_id,
			"parent_edge_gradient_record_hash": String(parent_edge.get("record_hash", "")),
			"temperature_delta_c": float(to_patch["temperature_c"]) - float(from_patch["temperature_c"]),
			"moisture_delta": float(to_patch["moisture"]) - float(from_patch["moisture"]),
			"light_delta": float(to_patch["light"]) - float(from_patch["light"]),
			"nutrients_delta": float(to_patch["nutrients"]) - float(from_patch["nutrients"]),
		}
		if not _numeric_fields_finite(edge, ["temperature_delta_c", "moisture_delta", "light_delta", "nutrients_delta"]):
			return {}
		edge["record_hash"] = _edge_hash(edge)
		edges.append(edge)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_p3_4_candidate_aggregate": PARENT_P3_4_CANDIDATE_AGGREGATE,
		"environment_result": environment_result.duplicate(true),
		"environment_result_hash": String(environment_result.get("result_hash", "")),
		"season_config": normalized_config,
		"time_years": time_years,
		"global_phase01": float(phase_state["global_phase01"]),
		"cycle_index": int(phase_state["cycle_index"]),
		"patch_order": patch_order,
		"patches": patches,
		"edge_seasonal_gradients": edges,
		"summary": _summary(patches, float(phase_state["global_phase01"])),
	}
	result["result_hash"] = compute_result_hash(result)
	return result

static func resource_supply_for_patch(base_supply: Dictionary, seasonal_patch: Dictionary) -> Dictionary:
	if not _exact(base_supply, ["light", "water", "nutrients"]):
		return {}
	if not _numeric_fields_finite(base_supply, ["light", "water", "nutrients"]):
		return {}
	for resource in ["light", "water", "nutrients"]:
		if float(base_supply[resource]) < 0.0:
			return {}
	if not _exact(seasonal_patch, PATCH_FIELDS):
		return {}
	if typeof(seasonal_patch.get("resource_availability")) != TYPE_DICTIONARY:
		return {}
	var resources: Dictionary = seasonal_patch["resource_availability"]
	if not _exact(resources, ["light", "water", "nutrients"]) or not _numeric_fields_finite(resources, ["light", "water", "nutrients"]):
		return {}
	if String(seasonal_patch.get("record_hash", "")) != _patch_hash(seasonal_patch):
		return {}
	var result := {}
	for resource in ["light", "water", "nutrients"]:
		var value := float(base_supply[resource]) * float(resources[resource])
		if not is_finite(value) or value < 0.0:
			return {}
		result[resource] = value
	return result

static func validate_result(result: Dictionary) -> Dictionary:
	if not _exact(result, RESULT_FIELDS):
		return _failure("RESULT_FIELDS_MISMATCH")
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION:
		return _failure("SCHEMA_OR_VERSION_MISMATCH")
	if String(result.get("parent_p3_4_candidate_aggregate", "")) != PARENT_P3_4_CANDIDATE_AGGREGATE:
		return _failure("PARENT_MISMATCH")
	if typeof(result.get("environment_result")) != TYPE_DICTIONARY:
		return _failure("ENVIRONMENT_RESULT_TYPE")
	var environment_result: Dictionary = result["environment_result"]
	if not bool(EnvGradient.validate_result(environment_result).get("success", false)):
		return _failure("ENVIRONMENT_RESULT_INVALID")
	if String(result.get("environment_result_hash", "")) != String(environment_result.get("result_hash", "")):
		return _failure("ENVIRONMENT_RESULT_HASH_MISMATCH")
	if typeof(result.get("season_config")) != TYPE_DICTIONARY:
		return _failure("SEASON_CONFIG_TYPE")
	if typeof(result.get("time_years")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(result["time_years"])):
		return _failure("TIME_INVALID")
	if typeof(result.get("global_phase01")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(result["global_phase01"])):
		return _failure("PHASE_INVALID")
	if float(result["global_phase01"]) < 0.0 or float(result["global_phase01"]) >= 1.0:
		return _failure("PHASE_RANGE")
	if typeof(result.get("cycle_index")) != TYPE_INT:
		return _failure("CYCLE_INDEX_TYPE")
	if typeof(result.get("patch_order")) != TYPE_PACKED_STRING_ARRAY or typeof(result.get("patches")) != TYPE_ARRAY or typeof(result.get("edge_seasonal_gradients")) != TYPE_ARRAY or typeof(result.get("summary")) != TYPE_DICTIONARY:
		return _failure("DERIVED_CONTAINER_TYPE")
	if not _derived_records_valid(result, environment_result):
		return _failure("DERIVED_RECORD_INVALID")
	var expected := evaluate(environment_result, float(result["time_years"]), Dictionary(result["season_config"]))
	if expected.is_empty():
		return _failure("RECONSTRUCTION_FAILED")
	var current_hash := compute_result_hash(result)
	if current_hash.is_empty() or String(result.get("result_hash", "")) != current_hash:
		return _failure("RESULT_HASH_MISMATCH")
	if String(result.get("result_hash", "")) != String(expected.get("result_hash", "")):
		return _failure("DERIVED_STATE_MISMATCH")
	return {"success": true, "error": ""}

static func compute_result_hash(result: Dictionary) -> String:
	if typeof(result.get("season_config")) != TYPE_DICTIONARY or typeof(result.get("patch_order")) != TYPE_PACKED_STRING_ARRAY or typeof(result.get("patches")) != TYPE_ARRAY or typeof(result.get("edge_seasonal_gradients")) != TYPE_ARRAY or typeof(result.get("summary")) != TYPE_DICTIONARY:
		return ""
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		PARENT_P3_4_CANDIDATE_AGGREGATE,
		String(result.get("environment_result_hash", "")),
		"time_years=%.12f" % float(result.get("time_years", 0.0)),
		"global_phase01=%.12f" % float(result.get("global_phase01", 0.0)),
		"cycle_index=%d" % int(result.get("cycle_index", 0)),
	])
	var config: Dictionary = result["season_config"]
	var cycle: Dictionary = config.get("cycle", {})
	for field_name in CYCLE_FIELDS:
		tokens.append("cycle|%s=%.12f" % [field_name, float(cycle.get(field_name, 0.0))])
	for channel in CHANNELS:
		var channel_config: Dictionary = config.get(channel, {})
		for field_name in CHANNEL_CONFIG_FIELDS:
			tokens.append("channel|%s|%s=%.12f" % [channel, field_name, float(channel_config.get(field_name, 0.0))])
	for patch_id in PackedStringArray(result["patch_order"]):
		tokens.append("order|%s" % String(patch_id))
	for patch_value in Array(result["patches"]):
		if typeof(patch_value) != TYPE_DICTIONARY:
			return ""
		var patch: Dictionary = patch_value
		tokens.append("patch|%s|%s" % [String(patch.get("id", "")), String(patch.get("record_hash", ""))])
	for edge_value in Array(result["edge_seasonal_gradients"]):
		if typeof(edge_value) != TYPE_DICTIONARY:
			return ""
		var edge: Dictionary = edge_value
		tokens.append("edge|%s|%s|%s" % [String(edge.get("from", "")), String(edge.get("to", "")), String(edge.get("record_hash", ""))])
	var summary: Dictionary = result["summary"]
	for field_name in SUMMARY_FIELDS:
		tokens.append("summary|%s=%s" % [field_name, str(summary.get(field_name, 0))])
	return "\n".join(tokens).sha256_text()

static func _seasonal_patch(parent_patch: Dictionary, parent_origin: Dictionary, parent_bounds: Dictionary, global_phase01: float, config: Dictionary) -> Dictionary:
	for field_name in ["id", "x", "y", "altitude", "temperature_c", "moisture", "light", "nutrients", "record_hash"]:
		if not parent_patch.has(field_name):
			return {}
	if not _numeric_fields_finite(parent_patch, ["x", "y", "altitude", "temperature_c", "moisture", "light", "nutrients"]):
		return {}
	if not _numeric_fields_finite(parent_origin, ["x", "y", "altitude"]):
		return {}
	var cycle: Dictionary = config["cycle"]
	var dx := float(parent_patch["x"]) - float(parent_origin["x"])
	var dy := float(parent_patch["y"]) - float(parent_origin["y"])
	var da := float(parent_patch["altitude"]) - float(parent_origin["altitude"])
	if not is_finite(dx) or not is_finite(dy) or not is_finite(da):
		return {}
	var phase_delta := float(cycle["phase_x_slope"]) * dx + float(cycle["phase_y_slope"]) * dy + float(cycle["phase_altitude_slope"]) * da
	if not is_finite(phase_delta):
		return {}
	var local_phase01 := _wrap01(global_phase01 + phase_delta)
	if not is_finite(local_phase01):
		return {}

	var values := {}
	var deltas := {}
	for channel in CHANNELS:
		var channel_config: Dictionary = config[channel]
		var channel_phase := _wrap01(local_phase01 + float(channel_config["phase_offset"]))
		var seasonal_signal := _triangle_signal(channel_phase)
		var raw := float(parent_patch[channel]) + float(channel_config["amplitude"]) * seasonal_signal
		if not is_finite(raw):
			return {}
		var bounds: Dictionary = parent_bounds[channel]
		var value := clampf(raw, float(bounds["min"]), float(bounds["max"]))
		if not is_finite(value):
			return {}
		values[channel] = value
		deltas[channel] = value - float(parent_patch[channel])

	var resources := {
		"light": float(values["light"]),
		"water": float(values["moisture"]),
		"nutrients": float(values["nutrients"]),
	}
	var patch := {
		"id": String(parent_patch["id"]),
		"x": float(parent_patch["x"]),
		"y": float(parent_patch["y"]),
		"altitude": float(parent_patch["altitude"]),
		"parent_patch_record_hash": String(parent_patch["record_hash"]),
		"local_phase01": local_phase01,
		"temperature_c": float(values["temperature_c"]),
		"temperature_delta_c": float(deltas["temperature_c"]),
		"moisture": float(values["moisture"]),
		"moisture_delta": float(deltas["moisture"]),
		"light": float(values["light"]),
		"light_delta": float(deltas["light"]),
		"nutrients": float(values["nutrients"]),
		"nutrients_delta": float(deltas["nutrients"]),
		"resource_availability": resources,
	}
	patch["record_hash"] = _patch_hash(patch)
	return patch

static func _derived_records_valid(result: Dictionary, environment_result: Dictionary) -> bool:
	var patch_order: PackedStringArray = result["patch_order"]
	var parent_order := PackedStringArray(environment_result.get("patch_order", PackedStringArray()))
	if patch_order != parent_order:
		return false
	var patches: Array = result["patches"]
	var parent_patches: Array = environment_result.get("patches", [])
	if patches.size() != patch_order.size() or patches.size() != parent_patches.size():
		return false
	for index in range(patches.size()):
		if typeof(patches[index]) != TYPE_DICTIONARY or typeof(parent_patches[index]) != TYPE_DICTIONARY:
			return false
		var patch: Dictionary = patches[index]
		var parent_patch: Dictionary = parent_patches[index]
		if not _exact(patch, PATCH_FIELDS):
			return false
		if String(patch.get("id", "")) != String(patch_order[index]) or String(patch.get("id", "")) != String(parent_patch.get("id", "")):
			return false
		if String(patch.get("parent_patch_record_hash", "")) != String(parent_patch.get("record_hash", "")):
			return false
		if not _numeric_fields_finite(patch, ["x", "y", "altitude", "local_phase01", "temperature_c", "temperature_delta_c", "moisture", "moisture_delta", "light", "light_delta", "nutrients", "nutrients_delta"]):
			return false
		if float(patch["local_phase01"]) < 0.0 or float(patch["local_phase01"]) >= 1.0:
			return false
		if float(patch["moisture"]) < 0.0 or float(patch["moisture"]) > 1.0 or float(patch["light"]) < 0.0 or float(patch["light"]) > 1.0 or float(patch["nutrients"]) < 0.0 or float(patch["nutrients"]) > 1.0:
			return false
		if typeof(patch.get("resource_availability")) != TYPE_DICTIONARY:
			return false
		var resources: Dictionary = patch["resource_availability"]
		if not _exact(resources, ["light", "water", "nutrients"]) or not _numeric_fields_finite(resources, ["light", "water", "nutrients"]):
			return false
		if absf(float(resources["light"]) - float(patch["light"])) > EPSILON or absf(float(resources["water"]) - float(patch["moisture"])) > EPSILON or absf(float(resources["nutrients"]) - float(patch["nutrients"])) > EPSILON:
			return false
		if String(patch.get("record_hash", "")) != _patch_hash(patch):
			return false

	var edges: Array = result["edge_seasonal_gradients"]
	var parent_edges: Array = environment_result.get("edge_gradients", [])
	if edges.size() != parent_edges.size():
		return false
	for index in range(edges.size()):
		if typeof(edges[index]) != TYPE_DICTIONARY or typeof(parent_edges[index]) != TYPE_DICTIONARY:
			return false
		var edge: Dictionary = edges[index]
		var parent_edge: Dictionary = parent_edges[index]
		if not _exact(edge, EDGE_FIELDS):
			return false
		if String(edge.get("from", "")) != String(parent_edge.get("from", "")) or String(edge.get("to", "")) != String(parent_edge.get("to", "")):
			return false
		if String(edge.get("parent_edge_gradient_record_hash", "")) != String(parent_edge.get("record_hash", "")):
			return false
		if not _numeric_fields_finite(edge, ["temperature_delta_c", "moisture_delta", "light_delta", "nutrients_delta"]):
			return false
		if String(edge.get("record_hash", "")) != _edge_hash(edge):
			return false

	var summary: Dictionary = result["summary"]
	if not _exact(summary, SUMMARY_FIELDS):
		return false
	if typeof(summary.get("patch_count")) != TYPE_INT or int(summary["patch_count"]) != patches.size():
		return false
	if not _numeric_fields_finite(summary, ["global_phase01", "temperature_min_c", "temperature_max_c", "moisture_min", "moisture_max", "light_min", "light_max", "nutrients_min", "nutrients_max"]):
		return false
	if absf(float(summary["global_phase01"]) - float(result["global_phase01"])) > EPSILON:
		return false
	return true

static func _normalize_config(config: Dictionary) -> Dictionary:
	if not _exact(config, CONFIG_FIELDS) or typeof(config.get("cycle")) != TYPE_DICTIONARY:
		return {}
	var cycle := _numeric_map(Dictionary(config["cycle"]), CYCLE_FIELDS)
	if cycle.is_empty() or float(cycle["period_years"]) <= EPSILON:
		return {}
	var result := {"cycle": cycle}
	for channel in CHANNELS:
		if typeof(config.get(channel)) != TYPE_DICTIONARY:
			return {}
		var channel_config := _numeric_map(Dictionary(config[channel]), CHANNEL_CONFIG_FIELDS)
		if channel_config.is_empty() or float(channel_config["amplitude"]) < 0.0:
			return {}
		if channel in NORMALIZED_CHANNELS and float(channel_config["amplitude"]) > 1.0:
			return {}
		channel_config["phase_offset"] = _wrap01(float(channel_config["phase_offset"]))
		result[channel] = channel_config
	return result

static func _parent_bounds(environment_result: Dictionary) -> Dictionary:
	var field_config_value = environment_result.get("field_config")
	if typeof(field_config_value) != TYPE_DICTIONARY:
		return {}
	var field_config: Dictionary = field_config_value
	var result := {}
	for channel in CHANNELS:
		if typeof(field_config.get(channel)) != TYPE_DICTIONARY:
			return {}
		var channel_config: Dictionary = field_config[channel]
		var min_value = channel_config.get("min")
		var max_value = channel_config.get("max")
		if typeof(min_value) not in [TYPE_INT, TYPE_FLOAT] or typeof(max_value) not in [TYPE_INT, TYPE_FLOAT]:
			return {}
		var lo := float(min_value)
		var hi := float(max_value)
		if not is_finite(lo) or not is_finite(hi) or lo > hi:
			return {}
		result[channel] = {"min": lo, "max": hi}
	return result

static func _phase_state(time_years: float, cycle: Dictionary) -> Dictionary:
	var period := float(cycle["period_years"])
	var epoch := float(cycle["epoch_year"])
	var relative := (time_years - epoch) / period
	if not is_finite(relative):
		return {}
	var cycle_floor: float = floor(relative)
	if not is_finite(cycle_floor) or absf(cycle_floor) > MAX_EXACT_CYCLE_INDEX:
		return {}
	var phase: float = relative - cycle_floor
	if phase < 0.0:
		phase += 1.0
	if phase >= 1.0:
		phase = 0.0
	return {"global_phase01": phase, "cycle_index": int(cycle_floor)}

static func _triangle_signal(phase01: float) -> float:
	return 1.0 - 4.0 * absf(phase01 - 0.5)

static func _wrap01(value: float) -> float:
	if not is_finite(value):
		return NAN
	var floor_value: float = floor(value)
	if not is_finite(floor_value):
		return NAN
	var wrapped: float = value - floor_value
	if wrapped < 0.0:
		wrapped += 1.0
	if wrapped >= 1.0:
		wrapped = 0.0
	return wrapped

static func _summary(patches: Array[Dictionary], global_phase01: float) -> Dictionary:
	if patches.is_empty():
		return {"patch_count": 0, "global_phase01": global_phase01, "temperature_min_c": 0.0, "temperature_max_c": 0.0, "moisture_min": 0.0, "moisture_max": 0.0, "light_min": 0.0, "light_max": 0.0, "nutrients_min": 0.0, "nutrients_max": 0.0}
	var first: Dictionary = patches[0]
	var summary := {
		"patch_count": patches.size(),
		"global_phase01": global_phase01,
		"temperature_min_c": float(first["temperature_c"]),
		"temperature_max_c": float(first["temperature_c"]),
		"moisture_min": float(first["moisture"]),
		"moisture_max": float(first["moisture"]),
		"light_min": float(first["light"]),
		"light_max": float(first["light"]),
		"nutrients_min": float(first["nutrients"]),
		"nutrients_max": float(first["nutrients"]),
	}
	for patch in patches:
		summary["temperature_min_c"] = minf(float(summary["temperature_min_c"]), float(patch["temperature_c"]))
		summary["temperature_max_c"] = maxf(float(summary["temperature_max_c"]), float(patch["temperature_c"]))
		summary["moisture_min"] = minf(float(summary["moisture_min"]), float(patch["moisture"]))
		summary["moisture_max"] = maxf(float(summary["moisture_max"]), float(patch["moisture"]))
		summary["light_min"] = minf(float(summary["light_min"]), float(patch["light"]))
		summary["light_max"] = maxf(float(summary["light_max"]), float(patch["light"]))
		summary["nutrients_min"] = minf(float(summary["nutrients_min"]), float(patch["nutrients"]))
		summary["nutrients_max"] = maxf(float(summary["nutrients_max"]), float(patch["nutrients"]))
	return summary

static func _patch_hash(patch: Dictionary) -> String:
	var resources: Dictionary = patch.get("resource_availability", {})
	var tokens := PackedStringArray([
		String(patch.get("id", "")),
		"x=%.12f" % float(patch.get("x", 0.0)),
		"y=%.12f" % float(patch.get("y", 0.0)),
		"altitude=%.12f" % float(patch.get("altitude", 0.0)),
		"parent=%s" % String(patch.get("parent_patch_record_hash", "")),
		"phase=%.12f" % float(patch.get("local_phase01", 0.0)),
		"temperature_c=%.12f" % float(patch.get("temperature_c", 0.0)),
		"temperature_delta_c=%.12f" % float(patch.get("temperature_delta_c", 0.0)),
		"moisture=%.12f" % float(patch.get("moisture", 0.0)),
		"moisture_delta=%.12f" % float(patch.get("moisture_delta", 0.0)),
		"light=%.12f" % float(patch.get("light", 0.0)),
		"light_delta=%.12f" % float(patch.get("light_delta", 0.0)),
		"nutrients=%.12f" % float(patch.get("nutrients", 0.0)),
		"nutrients_delta=%.12f" % float(patch.get("nutrients_delta", 0.0)),
		"resource_light=%.12f" % float(resources.get("light", 0.0)),
		"resource_water=%.12f" % float(resources.get("water", 0.0)),
		"resource_nutrients=%.12f" % float(resources.get("nutrients", 0.0)),
	])
	return "|".join(tokens).sha256_text()

static func _edge_hash(edge: Dictionary) -> String:
	return ("%s|%s|%s|%.12f|%.12f|%.12f|%.12f" % [String(edge.get("from", "")), String(edge.get("to", "")), String(edge.get("parent_edge_gradient_record_hash", "")), float(edge.get("temperature_delta_c", 0.0)), float(edge.get("moisture_delta", 0.0)), float(edge.get("light_delta", 0.0)), float(edge.get("nutrients_delta", 0.0))]).sha256_text()

static func _numeric_map(dictionary: Dictionary, fields: Array) -> Dictionary:
	if not _exact(dictionary, fields):
		return {}
	var result := {}
	for field_name in fields:
		var raw = dictionary.get(field_name)
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT]:
			return {}
		var value := float(raw)
		if not is_finite(value):
			return {}
		result[field_name] = value
	return result

static func _numeric_fields_finite(dictionary: Dictionary, fields: Array) -> bool:
	for field_name in fields:
		var raw = dictionary.get(field_name)
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
			return false
	return true

static func _exact(dictionary: Dictionary, fields: Array) -> bool:
	if dictionary.size() != fields.size():
		return false
	for field_name in fields:
		if not dictionary.has(field_name):
			return false
	return true

static func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error": "ECO_P3_5_" + error_code}
