extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Snapshot = preload("res://scripts/research/ecology/eco_obs1_snapshot_v1.gd")
const Timeline = preload("res://scripts/research/ecology/eco_obs1_demo_timeline_v1.gd")

var assertion_count := 0

func _init() -> void:
	var failure := _run()
	if not failure.is_empty():
		push_error(failure)
		quit(1)

func _run() -> String:
	var competition := Competition.compete(_resources(3.0, 1.0, 3.0), [
		_competitor("b", 1.0, 1.0, 1.0),
		_competitor("a", 1.0, 1.0, 1.0),
	])
	var result := Density.step(competition, _patch(), [
		{"id": "b", "biomass_kg": 2.0},
		{"id": "a", "biomass_kg": 1.0},
	])
	var failure := _assert(bool(Density.validate_result(result).get("success", false)), "source P3.2 result validates")
	if not failure.is_empty(): return failure
	var source_hash_before := String(result["result_hash"])
	var source_copy := result.duplicate(true)

	var snapshot := Snapshot.from_p3_2(result, 7, 7.0)
	failure = _assert(bool(Snapshot.validate(snapshot).get("success", false)), "OBS1 snapshot validates")
	if not failure.is_empty(): return failure
	failure = _assert(String(result["result_hash"]) == source_hash_before, "snapshot conversion does not alter source hash")
	if not failure.is_empty(): return failure
	failure = _assert(result == source_copy, "snapshot conversion does not mutate source dictionary")
	if not failure.is_empty(): return failure
	failure = _assert(Array(snapshot["plant_order"]) == ["a", "b"], "snapshot keeps canonical plant order")
	if not failure.is_empty(): return failure
	failure = _assert(String(snapshot["limiting_resource"]) == "WATER", "snapshot exposes limiting resource")
	if not failure.is_empty(): return failure
	failure = _assert(String(snapshot["source_result_hash"]) == source_hash_before, "snapshot pins exact source result")
	if not failure.is_empty(): return failure
	var snapshot_repeat := Snapshot.from_p3_2(result, 7, 7.0)
	failure = _assert(String(snapshot_repeat["snapshot_hash"]) == String(snapshot["snapshot_hash"]), "snapshot adapter deterministic")
	if not failure.is_empty(): return failure

	seed(0x514F4253)
	var expected_first := randi()
	var expected_second := randi()
	seed(0x514F4253)
	var actual_first := randi()
	var rng_snapshot := Snapshot.from_p3_2(result, 8, 8.0)
	failure = _assert(not rng_snapshot.is_empty(), "RNG probe snapshot exists")
	if not failure.is_empty(): return failure
	var actual_second := randi()
	failure = _assert(actual_first == expected_first and actual_second == expected_second, "snapshot adapter consumes no global RNG")
	if not failure.is_empty(): return failure

	var tampered := snapshot.duplicate(true)
	tampered["density_ratio"] = float(tampered["density_ratio"]) + 0.25
	failure = _assert(not bool(Snapshot.validate(tampered).get("success", false)), "tampered snapshot rejected")
	if not failure.is_empty(): return failure
	var malformed_source := result.duplicate(true)
	malformed_source["result_hash"] = "0".repeat(64)
	failure = _assert(Snapshot.from_p3_2(malformed_source, 0, 0.0).is_empty(), "invalid P3.2 source fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Snapshot.from_p3_2(result, -1, 0.0).is_empty(), "negative step fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Snapshot.from_p3_2(result, 0, -1.0).is_empty(), "negative year fails closed")
	if not failure.is_empty(): return failure

	var timeline := Timeline.build()
	failure = _assert(bool(Timeline.validate(timeline).get("success", false)), "demo timeline validates")
	if not failure.is_empty(): return failure
	failure = _assert(int(timeline["frame_count"]) == Timeline.FRAME_COUNT, "demo timeline frame count")
	if not failure.is_empty(): return failure
	var timeline_repeat := Timeline.build()
	failure = _assert(String(timeline_repeat["timeline_hash"]) == String(timeline["timeline_hash"]), "timeline deterministic")
	if not failure.is_empty(): return failure
	var frames: Array = timeline["frames"]
	for index in range(frames.size()):
		var frame: Dictionary = frames[index]
		failure = _assert(bool(Snapshot.validate(frame).get("success", false)), "timeline frame validates %d" % index)
		if not failure.is_empty(): return failure
		failure = _assert(String(frame["source_result_hash"]) == String(timeline["source_hashes"][index]), "timeline source hash pinned %d" % index)
		if not failure.is_empty(): return failure

	print("ECO.OBS1 Read-only Snapshot Boundary: PASS (%d assertions)" % assertion_count)
	print("snapshot_hash=%s" % String(snapshot["snapshot_hash"]))
	print("timeline_hash=%s" % String(timeline["timeline_hash"]))
	print("source_p3_2=%s" % source_hash_before)
	quit(0)
	return ""

func _resources(light: float, water: float, nutrients: float) -> Dictionary:
	return {"light": light, "water": water, "nutrients": nutrients}

func _competitor(id: String, light: float, water: float, nutrients: float) -> Dictionary:
	return {"id": id, "demand": _resources(light, water, nutrients), "capture_efficiency": _resources(1.0, 1.0, 1.0)}

func _patch() -> Dictionary:
	return {
		"area_m2": 10.0,
		"reference_capacity_kg_m2": 1.0,
		"minimum_capacity_fraction": 0.25,
		"max_recovery_fraction": 0.25,
		"max_decline_fraction": 0.60,
	}

func _assert(condition: bool, message: String) -> String:
	assertion_count += 1
	if condition:
		return ""
	return "ASSERTION FAILED: " + message
