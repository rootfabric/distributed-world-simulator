extends RefCounted

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const Snapshot = preload("res://scripts/research/ecology/eco_obs1_spatial_snapshot_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.obs1_spatial_demo_timeline.v1"
const VERSION := "1.0.0"
const DISPERSAL_FRACTIONS := [0.0, 0.08, 0.16, 0.24, 0.32, 0.40]

static func build() -> Dictionary:
	var patch_a := _density([_biomass("alpha", 6.0), _biomass("beta", 4.0)], 10.0)
	var patch_b := _density([_biomass("beta", 2.0)], 2.0)
	var patch_c := _density([], 10.0)
	for density_result in [patch_a, patch_b, patch_c]:
		if not bool(Density.validate_result(density_result).get("success", false)):
			return {}
	var patches := [
		_patch("C", patch_c, 0.0),
		_patch("A", patch_a, 0.25),
		_patch("B", patch_b, 0.0),
	]
	var edges := [
		_edge("B", "C", 1.0),
		_edge("A", "C", 1.0),
		_edge("A", "B", 3.0),
	]
	var frames: Array[Dictionary] = []
	var source_hashes := PackedStringArray()
	for step_index in range(DISPERSAL_FRACTIONS.size()):
		var fraction := float(DISPERSAL_FRACTIONS[step_index])
		var result := Dispersal.disperse(patches, edges, {"dispersal_fraction": fraction})
		if not bool(Dispersal.validate_result(result).get("success", false)):
			return {}
		var source_hash := String(result.get("result_hash", ""))
		var snapshot := Snapshot.from_p3_3(result, step_index, float(step_index))
		if not bool(Snapshot.validate(snapshot).get("success", false)):
			return {}
		if String(result.get("result_hash", "")) != source_hash:
			return {}
		frames.append(snapshot)
		source_hashes.append(source_hash)
	var timeline := {
		"schema": SCHEMA,
		"version": VERSION,
		"frame_count": frames.size(),
		"frames": frames,
		"source_hashes": source_hashes,
		"parent_p3_2_aggregate": Dispersal.PARENT_P3_2_ACCEPTED_AGGREGATE,
	}
	timeline["timeline_hash"] = compute_hash(timeline)
	return timeline

static func validate(timeline: Dictionary) -> Dictionary:
	if String(timeline.get("schema", "")) != SCHEMA or String(timeline.get("version", "")) != VERSION:
		return {"success": false, "error_code": "ECO_OBS1_SPATIAL_TIMELINE_SCHEMA_MISMATCH"}
	if String(timeline.get("parent_p3_2_aggregate", "")) != Dispersal.PARENT_P3_2_ACCEPTED_AGGREGATE:
		return {"success": false, "error_code": "ECO_OBS1_SPATIAL_TIMELINE_PARENT_MISMATCH"}
	if typeof(timeline.get("frames")) != TYPE_ARRAY or typeof(timeline.get("source_hashes")) != TYPE_PACKED_STRING_ARRAY:
		return {"success": false, "error_code": "ECO_OBS1_SPATIAL_TIMELINE_CONTAINER_MISMATCH"}
	var frames: Array = timeline["frames"]
	var source_hashes: PackedStringArray = timeline["source_hashes"]
	if frames.size() != DISPERSAL_FRACTIONS.size() or frames.size() != int(timeline.get("frame_count", -1)) or source_hashes.size() != frames.size():
		return {"success": false, "error_code": "ECO_OBS1_SPATIAL_TIMELINE_COUNT_MISMATCH"}
	for index in range(frames.size()):
		if typeof(frames[index]) != TYPE_DICTIONARY:
			return {"success": false, "error_code": "ECO_OBS1_SPATIAL_TIMELINE_FRAME_TYPE_MISMATCH"}
		var snapshot: Dictionary = frames[index]
		if not bool(Snapshot.validate(snapshot).get("success", false)):
			return {"success": false, "error_code": "ECO_OBS1_SPATIAL_TIMELINE_FRAME_INVALID"}
		if int(snapshot.get("step_index", -1)) != index or absf(float(snapshot.get("dispersal_fraction", -1.0)) - float(DISPERSAL_FRACTIONS[index])) > 0.000000000001:
			return {"success": false, "error_code": "ECO_OBS1_SPATIAL_TIMELINE_STEP_MISMATCH"}
		if String(snapshot.get("source_result_hash", "")) != String(source_hashes[index]):
			return {"success": false, "error_code": "ECO_OBS1_SPATIAL_TIMELINE_SOURCE_MISMATCH"}
	if String(timeline.get("timeline_hash", "")) != compute_hash(timeline):
		return {"success": false, "error_code": "ECO_OBS1_SPATIAL_TIMELINE_HASH_MISMATCH"}
	return {"success": true, "error_code": ""}

static func compute_hash(timeline: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, Dispersal.PARENT_P3_2_ACCEPTED_AGGREGATE])
	for frame_variant in Array(timeline.get("frames", [])):
		if typeof(frame_variant) == TYPE_DICTIONARY:
			tokens.append(String(Dictionary(frame_variant).get("snapshot_hash", "")))
	return "\n".join(tokens).sha256_text()

static func _density(plants: Array, capacity: float) -> Dictionary:
	var competitors: Array = []
	for plant_variant in plants:
		var plant: Dictionary = plant_variant
		competitors.append({"id": String(plant["id"]), "demand": _resources(1.0, 1.0, 1.0), "capture_efficiency": _resources(1.0, 1.0, 1.0)})
	var competition := Competition.compete(_resources(100.0, 100.0, 100.0), competitors)
	if not bool(Competition.validate_result(competition).get("success", false)):
		return {}
	return Density.step(competition, {
		"area_m2": capacity,
		"reference_capacity_kg_m2": 1.0,
		"minimum_capacity_fraction": 0.25,
		"max_recovery_fraction": 0.25,
		"max_decline_fraction": 0.60,
	}, plants)

static func _resources(light: float, water: float, nutrients: float) -> Dictionary:
	return {"light": light, "water": water, "nutrients": nutrients}

static func _biomass(id: String, biomass_kg: float) -> Dictionary:
	return {"id": id, "biomass_kg": biomass_kg}

static func _patch(id: String, density_result: Dictionary, boundary_fraction: float) -> Dictionary:
	return {"id": id, "density_result": density_result, "boundary_export_fraction": boundary_fraction}

static func _edge(from_id: String, to_id: String, weight: float) -> Dictionary:
	return {"from": from_id, "to": to_id, "weight": weight}
