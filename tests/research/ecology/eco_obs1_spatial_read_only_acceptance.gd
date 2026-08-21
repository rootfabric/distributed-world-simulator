extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const Snapshot = preload("res://scripts/research/ecology/eco_obs1_spatial_snapshot_v1.gd")
const Timeline = preload("res://scripts/research/ecology/eco_obs1_spatial_demo_timeline_v1.gd")
const EPSILON := 0.000000001

var assertion_count := 0

func _init() -> void:
	var failure := _run()
	if failure.is_empty():
		return
	push_error(failure)
	quit(1)

func _run() -> String:
	var source := _source_result(0.24)
	var failure := _assert(bool(Dispersal.validate_result(source).get("success", false)), "source P3.3 result validates")
	if not failure.is_empty(): return failure
	var source_before := source.duplicate(true)
	var source_hash_before := String(source["result_hash"])
	var snapshot := Snapshot.from_p3_3(source, 3, 3.0)
	failure = _assert(not snapshot.is_empty(), "snapshot conversion succeeds")
	if not failure.is_empty(): return failure
	failure = _assert(bool(Snapshot.validate(snapshot).get("success", false)), "snapshot validates")
	if not failure.is_empty(): return failure
	failure = _assert(source == source_before, "snapshot conversion does not mutate source dictionary")
	if not failure.is_empty(): return failure
	failure = _assert(String(source["result_hash"]) == source_hash_before, "snapshot conversion preserves source hash")
	if not failure.is_empty(): return failure
	failure = _assert(String(snapshot["source_result_hash"]) == source_hash_before, "snapshot pins exact source hash")
	if not failure.is_empty(): return failure
	failure = _assert(String(snapshot["parent_p3_2_aggregate"]) == Dispersal.PARENT_P3_2_ACCEPTED_AGGREGATE, "snapshot pins accepted P3.2 aggregate")
	if not failure.is_empty(): return failure
	failure = _assert(Array(snapshot["patch_order"]) == ["A", "B", "C"], "snapshot patch order canonical")
	if not failure.is_empty(): return failure
	failure = _assert(Array(snapshot["edges"]).size() == 3, "snapshot has three canonical edges")
	if not failure.is_empty(): return failure
	failure = _near(float(snapshot["dispersal_fraction"]), 0.24, "snapshot dispersal fraction")
	if not failure.is_empty(): return failure
	failure = _near(float(snapshot["total_source_biomass_kg"]), 12.0, "snapshot source total")
	if not failure.is_empty(): return failure
	failure = _near(float(snapshot["total_internal_transfer_biomass_kg"]), 2.28, "snapshot internal transfer total")
	if not failure.is_empty(): return failure
	failure = _near(float(snapshot["total_boundary_export_biomass_kg"]), 0.6, "snapshot boundary export total")
	if not failure.is_empty(): return failure
	failure = _near(float(snapshot["total_final_biomass_kg"]), 11.4, "snapshot final total")
	if not failure.is_empty(): return failure
	failure = _near(float(_patch(snapshot, "A")["final_total_biomass_kg"]), 7.6, "patch A final")
	if not failure.is_empty(): return failure
	failure = _near(float(_patch(snapshot, "B")["final_total_biomass_kg"]), 2.87, "patch B final")
	if not failure.is_empty(): return failure
	failure = _near(float(_patch(snapshot, "C")["final_total_biomass_kg"]), 0.93, "patch C final")
	if not failure.is_empty(): return failure
	failure = _near(float(_edge(snapshot, "A", "B")["share"]), 0.75, "A->B share")
	if not failure.is_empty(): return failure
	failure = _near(float(_edge(snapshot, "A", "B")["transfer_biomass_kg"]), 1.35, "A->B aggregate transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(_edge(snapshot, "A", "C")["transfer_biomass_kg"]), 0.45, "A->C aggregate transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(_edge(snapshot, "B", "C")["transfer_biomass_kg"]), 0.48, "B->C aggregate transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(_boundary(snapshot, "A")["biomass_kg"]), 0.6, "A boundary summary")
	if not failure.is_empty(): return failure
	failure = _near(float(_boundary(snapshot, "B")["biomass_kg"]), 0.0, "B boundary summary")
	if not failure.is_empty(): return failure
	failure = _near(float(_plant(snapshot, "C", "alpha")["final_biomass_kg"]), 0.27, "alpha shown as colonized C biomass")
	if not failure.is_empty(): return failure

	var same_snapshot := Snapshot.from_p3_3(source, 3, 3.0)
	failure = _assert(String(same_snapshot.get("snapshot_hash", "")) == String(snapshot["snapshot_hash"]), "same source metadata gives same snapshot hash")
	if not failure.is_empty(): return failure
	var next_year := Snapshot.from_p3_3(source, 3, 4.0)
	failure = _assert(String(next_year.get("snapshot_hash", "")) != String(snapshot["snapshot_hash"]), "year metadata participates in observer hash")
	if not failure.is_empty(): return failure
	failure = _assert(Snapshot.from_p3_3(source, -1, 0.0).is_empty(), "negative step rejected")
	if not failure.is_empty(): return failure
	failure = _assert(Snapshot.from_p3_3(source, 0, -1.0).is_empty(), "negative year rejected")
	if not failure.is_empty(): return failure
	var tampered_source := source.duplicate(true)
	tampered_source["total_final_biomass_kg"] = 999.0
	failure = _assert(Snapshot.from_p3_3(tampered_source, 0, 0.0).is_empty(), "tampered P3.3 source rejected")
	if not failure.is_empty(): return failure

	var tampered_transfer := snapshot.duplicate(true)
	tampered_transfer["edges"][0]["transfer_biomass_kg"] = 99.0
	failure = _assert(not bool(Snapshot.validate(tampered_transfer).get("success", false)), "tampered observer edge transfer rejected")
	if not failure.is_empty(): return failure
	var tampered_patch := snapshot.duplicate(true)
	tampered_patch["patches"][0]["final_total_biomass_kg"] = 99.0
	failure = _assert(not bool(Snapshot.validate(tampered_patch).get("success", false)), "tampered observer patch total rejected")
	if not failure.is_empty(): return failure
	var tampered_hash := snapshot.duplicate(true)
	tampered_hash["source_result_hash"] = "deadbeef"
	failure = _assert(not bool(Snapshot.validate(tampered_hash).get("success", false)), "invalid observer source hash rejected")
	if not failure.is_empty(): return failure
	var tampered_parent := snapshot.duplicate(true)
	tampered_parent["parent_p3_2_aggregate"] = "deadbeef"
	failure = _assert(not bool(Snapshot.validate(tampered_parent).get("success", false)), "invalid observer parent pin rejected")
	if not failure.is_empty(): return failure
	var tampered_order := snapshot.duplicate(true)
	tampered_order["patch_order"] = PackedStringArray(["C", "B", "A"])
	failure = _assert(not bool(Snapshot.validate(tampered_order).get("success", false)), "non-canonical observer patch order rejected")
	if not failure.is_empty(): return failure

	seed(77123)
	var rng_before_a := randi()
	var rng_snapshot := Snapshot.from_p3_3(source, 3, 3.0)
	var rng_after_a := randi()
	seed(77123)
	var rng_before_b := randi()
	var rng_after_b := randi()
	failure = _assert(not rng_snapshot.is_empty() and rng_before_a == rng_before_b and rng_after_a == rng_after_b, "snapshot adapter consumes no global RNG")
	if not failure.is_empty(): return failure

	var timeline := Timeline.build()
	failure = _assert(not timeline.is_empty(), "spatial demo timeline exists")
	if not failure.is_empty(): return failure
	failure = _assert(bool(Timeline.validate(timeline).get("success", false)), "spatial demo timeline validates")
	if not failure.is_empty(): return failure
	failure = _assert(int(timeline["frame_count"]) == 6, "spatial timeline has six deterministic frames")
	if not failure.is_empty(): return failure
	var frame_zero: Dictionary = Array(timeline["frames"])[0]
	var frame_last: Dictionary = Array(timeline["frames"])[5]
	failure = _near(float(frame_zero["dispersal_fraction"]), 0.0, "timeline starts at zero dispersal")
	if not failure.is_empty(): return failure
	failure = _near(float(frame_zero["total_internal_transfer_biomass_kg"]), 0.0, "zero frame has no internal transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(frame_zero["total_boundary_export_biomass_kg"]), 0.0, "zero frame has no boundary export")
	if not failure.is_empty(): return failure
	failure = _near(float(frame_last["dispersal_fraction"]), 0.40, "timeline ends at 40 percent dispersal")
	if not failure.is_empty(): return failure
	failure = _near(float(frame_last["total_internal_transfer_biomass_kg"]), 3.8, "last frame internal transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(frame_last["total_boundary_export_biomass_kg"]), 1.0, "last frame boundary export")
	if not failure.is_empty(): return failure
	failure = _near(float(frame_last["total_final_biomass_kg"]), 11.0, "last frame final biomass")
	if not failure.is_empty(): return failure
	var timeline_repeat := Timeline.build()
	failure = _assert(String(timeline_repeat.get("timeline_hash", "")) == String(timeline["timeline_hash"]), "timeline repeats deterministically")
	if not failure.is_empty(): return failure

	seed(55119)
	var timeline_rng_before_a := randi()
	var rng_timeline := Timeline.build()
	var timeline_rng_after_a := randi()
	seed(55119)
	var timeline_rng_before_b := randi()
	var timeline_rng_after_b := randi()
	failure = _assert(not rng_timeline.is_empty() and timeline_rng_before_a == timeline_rng_before_b and timeline_rng_after_a == timeline_rng_after_b, "demo timeline consumes no global RNG")
	if not failure.is_empty(): return failure

	print("ECO.OBS1.2 Spatial Read-only Boundary: PASS (%d assertions)" % assertion_count)
	print("snapshot_hash=%s" % String(snapshot["snapshot_hash"]))
	print("timeline_hash=%s" % String(timeline["timeline_hash"]))
	print("source_p3_3=%s" % source_hash_before)
	print("parent_p3_2=%s" % Dispersal.PARENT_P3_2_ACCEPTED_AGGREGATE)
	quit(0)
	return ""

func _source_result(fraction: float) -> Dictionary:
	var patch_a := _density([_biomass("alpha", 6.0), _biomass("beta", 4.0)], 10.0)
	var patch_b := _density([_biomass("beta", 2.0)], 2.0)
	var patch_c := _density([], 10.0)
	return Dispersal.disperse([
		_patch_input("C", patch_c, 0.0),
		_patch_input("A", patch_a, 0.25),
		_patch_input("B", patch_b, 0.0),
	], [
		_edge_input("B", "C", 1.0),
		_edge_input("A", "C", 1.0),
		_edge_input("A", "B", 3.0),
	], {"dispersal_fraction": fraction})

func _density(plants: Array, capacity: float) -> Dictionary:
	var competitors: Array = []
	for plant_variant in plants:
		var plant: Dictionary = plant_variant
		competitors.append({"id": String(plant["id"]), "demand": _resources(1.0, 1.0, 1.0), "capture_efficiency": _resources(1.0, 1.0, 1.0)})
	var competition := Competition.compete(_resources(100.0, 100.0, 100.0), competitors)
	return Density.step(competition, {
		"area_m2": capacity,
		"reference_capacity_kg_m2": 1.0,
		"minimum_capacity_fraction": 0.25,
		"max_recovery_fraction": 0.25,
		"max_decline_fraction": 0.60,
	}, plants)

func _resources(light: float, water: float, nutrients: float) -> Dictionary:
	return {"light": light, "water": water, "nutrients": nutrients}

func _biomass(id: String, biomass_kg: float) -> Dictionary:
	return {"id": id, "biomass_kg": biomass_kg}

func _patch_input(id: String, density_result: Dictionary, boundary: float) -> Dictionary:
	return {"id": id, "density_result": density_result, "boundary_export_fraction": boundary}

func _edge_input(from_id: String, to_id: String, weight: float) -> Dictionary:
	return {"from": from_id, "to": to_id, "weight": weight}

func _patch(snapshot: Dictionary, id: String) -> Dictionary:
	for patch_variant in Array(snapshot.get("patches", [])):
		var patch: Dictionary = patch_variant
		if String(patch.get("id", "")) == id:
			return patch
	return {}

func _edge(snapshot: Dictionary, from_id: String, to_id: String) -> Dictionary:
	for edge_variant in Array(snapshot.get("edges", [])):
		var edge: Dictionary = edge_variant
		if String(edge.get("from", "")) == from_id and String(edge.get("to", "")) == to_id:
			return edge
	return {}

func _boundary(snapshot: Dictionary, patch_id: String) -> Dictionary:
	for boundary_variant in Array(snapshot.get("boundary_exports", [])):
		var boundary: Dictionary = boundary_variant
		if String(boundary.get("patch_id", "")) == patch_id:
			return boundary
	return {}

func _plant(snapshot: Dictionary, patch_id: String, plant_id: String) -> Dictionary:
	var patch := _patch(snapshot, patch_id)
	for plant_variant in Array(patch.get("plants", [])):
		var plant: Dictionary = plant_variant
		if String(plant.get("id", "")) == plant_id:
			return plant
	return {}

func _assert(condition: bool, message: String) -> String:
	assertion_count += 1
	if condition:
		return ""
	return "ASSERTION FAILED: " + message

func _near(actual: float, expected: float, message: String) -> String:
	return _assert(absf(actual - expected) <= EPSILON, "%s actual=%.12f expected=%.12f" % [message, actual, expected])
