extends RefCounted

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Snapshot = preload("res://scripts/research/ecology/eco_obs1_snapshot_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.obs1_demo_timeline.v1"
const VERSION := "1.0.0"
const FRAME_COUNT := 16

static func build() -> Dictionary:
	var competitors := [
		_competitor("fern", 1.6, 2.2, 1.2, 0.72, 0.82, 0.70),
		_competitor("grass", 1.3, 1.7, 1.0, 0.84, 0.73, 0.78),
		_competitor("oak", 2.4, 2.8, 1.7, 0.91, 0.88, 0.84),
		_competitor("shrub", 1.8, 2.0, 1.3, 0.79, 0.80, 0.82),
	]
	var competition := Competition.compete(_resources(8.0, 4.2, 6.0), competitors)
	if not bool(Competition.validate_result(competition).get("success", false)):
		return {}
	var patch := {
		"area_m2": 12.0,
		"reference_capacity_kg_m2": 1.0,
		"minimum_capacity_fraction": 0.35,
		"max_recovery_fraction": 0.20,
		"max_decline_fraction": 0.45,
	}
	var biomass: Array = [
		{"id": "fern", "biomass_kg": 2.2},
		{"id": "grass", "biomass_kg": 2.7},
		{"id": "oak", "biomass_kg": 4.8},
		{"id": "shrub", "biomass_kg": 2.9},
	]
	var frames: Array[Dictionary] = []
	var source_hashes := PackedStringArray()
	for step_index in range(FRAME_COUNT):
		var result := Density.step(competition, patch, biomass)
		if not bool(Density.validate_result(result).get("success", false)):
			return {}
		var source_hash := String(result["result_hash"])
		var snapshot := Snapshot.from_p3_2(result, step_index, float(step_index))
		if not bool(Snapshot.validate(snapshot).get("success", false)):
			return {}
		if String(result.get("result_hash", "")) != source_hash:
			return {}
		frames.append(snapshot)
		source_hashes.append(source_hash)
		biomass = _next_biomass(result)
	var timeline := {
		"schema": SCHEMA,
		"version": VERSION,
		"frame_count": frames.size(),
		"frames": frames,
		"source_hashes": source_hashes,
		"competition_result_hash": String(competition["result_hash"]),
	}
	timeline["timeline_hash"] = _timeline_hash(timeline)
	return timeline

static func validate(timeline: Dictionary) -> Dictionary:
	if String(timeline.get("schema", "")) != SCHEMA or String(timeline.get("version", "")) != VERSION:
		return {"success": false, "error_code": "ECO_OBS1_TIMELINE_SCHEMA_MISMATCH"}
	if typeof(timeline.get("frames")) != TYPE_ARRAY or typeof(timeline.get("source_hashes")) != TYPE_PACKED_STRING_ARRAY:
		return {"success": false, "error_code": "ECO_OBS1_TIMELINE_CONTAINER_MISMATCH"}
	var frames: Array = timeline["frames"]
	var source_hashes: PackedStringArray = timeline["source_hashes"]
	if frames.size() != int(timeline.get("frame_count", -1)) or frames.size() != source_hashes.size() or frames.is_empty():
		return {"success": false, "error_code": "ECO_OBS1_TIMELINE_COUNT_MISMATCH"}
	for index in range(frames.size()):
		if typeof(frames[index]) != TYPE_DICTIONARY:
			return {"success": false, "error_code": "ECO_OBS1_TIMELINE_FRAME_TYPE_MISMATCH"}
		var snapshot: Dictionary = frames[index]
		if not bool(Snapshot.validate(snapshot).get("success", false)):
			return {"success": false, "error_code": "ECO_OBS1_TIMELINE_FRAME_INVALID"}
		if int(snapshot["step_index"]) != index:
			return {"success": false, "error_code": "ECO_OBS1_TIMELINE_STEP_MISMATCH"}
		if String(snapshot["source_result_hash"]) != String(source_hashes[index]):
			return {"success": false, "error_code": "ECO_OBS1_TIMELINE_SOURCE_HASH_MISMATCH"}
	if String(timeline.get("timeline_hash", "")) != _timeline_hash(timeline):
		return {"success": false, "error_code": "ECO_OBS1_TIMELINE_HASH_MISMATCH"}
	return {"success": true, "error_code": ""}

static func _timeline_hash(timeline: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		String(timeline.get("competition_result_hash", "")),
	])
	for frame_value in Array(timeline.get("frames", [])):
		if typeof(frame_value) == TYPE_DICTIONARY:
			tokens.append(String(Dictionary(frame_value).get("snapshot_hash", "")))
	return "\n".join(tokens).sha256_text()

static func _next_biomass(result: Dictionary) -> Array:
	var next: Array = []
	for plant_value in Array(result.get("plants", [])):
		var plant: Dictionary = plant_value
		next.append({"id": String(plant["id"]), "biomass_kg": float(plant["next_biomass_kg"])})
	return next

static func _competitor(id: String, light: float, water: float, nutrients: float, light_eff: float, water_eff: float, nutrient_eff: float) -> Dictionary:
	return {
		"id": id,
		"demand": _resources(light, water, nutrients),
		"capture_efficiency": _resources(light_eff, water_eff, nutrient_eff),
	}

static func _resources(light: float, water: float, nutrients: float) -> Dictionary:
	return {"light": light, "water": water, "nutrients": nutrients}
