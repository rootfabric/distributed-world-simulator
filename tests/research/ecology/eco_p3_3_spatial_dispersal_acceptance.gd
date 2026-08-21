extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const EPSILON := 0.000000001
var assertion_count := 0

func _init() -> void:
	var failure := _run()
	if failure.is_empty():
		return
	push_error(failure)
	quit(1)

func _run() -> String:
	var patch_a := _density([_biomass("alpha", 6.0), _biomass("beta", 4.0)], 10.0)
	var patch_b := _density([_biomass("beta", 2.0)], 2.0)
	var patch_c := _density([], 10.0)
	var failure := _assert(bool(Density.validate_result(patch_a).get("success", false)), "patch A P3.2 parent validates")
	if not failure.is_empty(): return failure
	failure = _assert(bool(Density.validate_result(patch_b).get("success", false)), "patch B P3.2 parent validates")
	if not failure.is_empty(): return failure
	failure = _assert(bool(Density.validate_result(patch_c).get("success", false)), "patch C P3.2 parent validates")
	if not failure.is_empty(): return failure

	var patches := [
		_patch("C", patch_c, 0.0),
		_patch("A", patch_a, 0.25),
		_patch("B", patch_b, 0.0),
	]
	var edges := [
		_edge("A", "C", 1.0),
		_edge("A", "B", 3.0),
	]
	var result := Dispersal.disperse(patches, edges, {"dispersal_fraction": 0.2})
	failure = _assert(not result.is_empty(), "spatial dispersal result exists")
	if not failure.is_empty(): return failure
	failure = _assert(bool(Dispersal.validate_result(result).get("success", false)), "spatial dispersal result validates")
	if not failure.is_empty(): return failure
	failure = _assert(String(result["parent_p3_2_accepted_aggregate"]) == Dispersal.PARENT_P3_2_ACCEPTED_AGGREGATE, "accepted P3.2 parent aggregate pinned")
	if not failure.is_empty(): return failure
	failure = _assert(Array(result["patch_order"]) == ["A", "B", "C"], "patch order canonical")
	if not failure.is_empty(): return failure
	failure = _assert(Array(result["edges"]).size() == 2, "two canonical edges")
	if not failure.is_empty(): return failure
	failure = _near(float(_edge_record(result, "A", "B")["share"]), 0.75, "A->B normalized share")
	if not failure.is_empty(): return failure
	failure = _near(float(_edge_record(result, "A", "C")["share"]), 0.25, "A->C normalized share")
	if not failure.is_empty(): return failure

	failure = _near(float(_transfer(result, "A", "B", "alpha")["biomass_kg"]), 0.675, "alpha A->B transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(_transfer(result, "A", "C", "alpha")["biomass_kg"]), 0.225, "alpha A->C transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(_transfer(result, "A", "B", "beta")["biomass_kg"]), 0.45, "beta A->B transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(_transfer(result, "A", "C", "beta")["biomass_kg"]), 0.15, "beta A->C transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(_boundary(result, "A", "alpha")["biomass_kg"]), 0.3, "alpha boundary export")
	if not failure.is_empty(): return failure
	failure = _near(float(_boundary(result, "A", "beta")["biomass_kg"]), 0.2, "beta boundary export")
	if not failure.is_empty(): return failure

	failure = _near(float(_patch_record(result, "A")["final_total_biomass_kg"]), 8.0, "A final after export/dispersal")
	if not failure.is_empty(): return failure
	failure = _near(float(_plant_record(result, "A", "alpha")["retained_biomass_kg"]), 4.8, "A alpha retained")
	if not failure.is_empty(): return failure
	failure = _near(float(_patch_record(result, "B")["final_total_biomass_kg"]), 3.125, "B receives weighted migration")
	if not failure.is_empty(): return failure
	failure = _near(float(_plant_record(result, "B", "alpha")["source_biomass_kg"]), 0.0, "alpha absent from B source")
	if not failure.is_empty(): return failure
	failure = _near(float(_plant_record(result, "B", "alpha")["incoming_biomass_kg"]), 0.675, "alpha colonizes B by incoming transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(_plant_record(result, "B", "beta")["final_biomass_kg"]), 2.45, "B beta source retained plus incoming")
	if not failure.is_empty(): return failure
	failure = _near(float(_patch_record(result, "C")["final_total_biomass_kg"]), 0.375, "empty C colonized by incoming biomass")
	if not failure.is_empty(): return failure

	failure = _near(float(result["total_source_biomass_kg"]), 12.0, "total source biomass")
	if not failure.is_empty(): return failure
	failure = _near(float(result["total_retained_biomass_kg"]), 10.0, "total retained biomass")
	if not failure.is_empty(): return failure
	failure = _near(float(result["total_internal_transfer_biomass_kg"]), 1.5, "total internal transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(result["total_boundary_export_biomass_kg"]), 0.5, "total explicit boundary export")
	if not failure.is_empty(): return failure
	failure = _near(float(result["total_final_biomass_kg"]), 11.5, "total final biomass")
	if not failure.is_empty(): return failure
	failure = _near(float(result["conservation_error_kg"]), 0.0, "closed accounting conservation")
	if not failure.is_empty(): return failure
	failure = _near(float(result["total_source_biomass_kg"]), float(result["total_final_biomass_kg"]) + float(result["total_boundary_export_biomass_kg"]), "source equals final plus explicit boundary sink")
	if not failure.is_empty(): return failure

	var permuted := Dispersal.disperse([patches[1], patches[0], patches[2]], [edges[1], edges[0]], {"dispersal_fraction": 0.2})
	failure = _assert(String(permuted.get("result_hash", "")) == String(result["result_hash"]), "patch and edge permutation does not alter result hash")
	if not failure.is_empty(): return failure
	var scaled_weights := Dispersal.disperse(patches, [_edge("A", "B", 30.0), _edge("A", "C", 10.0)], {"dispersal_fraction": 0.2})
	failure = _assert(String(scaled_weights.get("result_hash", "")) == String(result["result_hash"]), "common edge-weight scaling canonicalizes to same shares/hash")
	if not failure.is_empty(): return failure
	var repeat := Dispersal.disperse(patches, edges, {"dispersal_fraction": 0.2})
	failure = _assert(String(repeat.get("result_hash", "")) == String(result["result_hash"]), "same spatial input repeats deterministically")
	if not failure.is_empty(): return failure

	var closed_patches := [_patch("A", patch_a, 0.0), _patch("B", patch_b, 0.0), _patch("C", patch_c, 0.0)]
	var closed := Dispersal.disperse(closed_patches, edges, {"dispersal_fraction": 0.2})
	failure = _assert(bool(Dispersal.validate_result(closed).get("success", false)), "closed system validates")
	if not failure.is_empty(): return failure
	failure = _near(float(closed["total_boundary_export_biomass_kg"]), 0.0, "closed system has no boundary sink")
	if not failure.is_empty(): return failure
	failure = _near(float(closed["total_source_biomass_kg"]), float(closed["total_final_biomass_kg"]), "closed system conserves total biomass")
	if not failure.is_empty(): return failure

	var isolated := Dispersal.disperse([_patch("ISO", patch_a, 0.5)], [], {"dispersal_fraction": 0.2})
	failure = _assert(bool(Dispersal.validate_result(isolated).get("success", false)), "isolated boundary patch validates")
	if not failure.is_empty(): return failure
	failure = _near(float(isolated["total_source_biomass_kg"]), 10.0, "isolated source")
	if not failure.is_empty(): return failure
	failure = _near(float(isolated["total_internal_transfer_biomass_kg"]), 0.0, "isolated patch has no internal transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(isolated["total_boundary_export_biomass_kg"]), 1.0, "isolated explicit boundary export")
	if not failure.is_empty(): return failure
	failure = _near(float(isolated["total_final_biomass_kg"]), 9.0, "non-exported isolated dispersal pool is retained")
	if not failure.is_empty(): return failure

	var no_dispersal := Dispersal.disperse(patches, edges, {"dispersal_fraction": 0.0})
	failure = _assert(bool(Dispersal.validate_result(no_dispersal).get("success", false)), "zero dispersal validates")
	if not failure.is_empty(): return failure
	failure = _near(float(no_dispersal["total_final_biomass_kg"]), 12.0, "zero dispersal leaves total in patches")
	if not failure.is_empty(): return failure
	failure = _near(float(no_dispersal["total_internal_transfer_biomass_kg"]), 0.0, "zero dispersal has zero transfer")
	if not failure.is_empty(): return failure
	failure = _near(float(no_dispersal["total_boundary_export_biomass_kg"]), 0.0, "zero dispersal has zero boundary export")
	if not failure.is_empty(): return failure

	var empty := Dispersal.disperse([], [], {"dispersal_fraction": 0.3})
	failure = _assert(bool(Dispersal.validate_result(empty).get("success", false)), "empty spatial system validates")
	if not failure.is_empty(): return failure
	failure = _near(float(empty["total_source_biomass_kg"]), 0.0, "empty source zero")
	if not failure.is_empty(): return failure
	failure = _near(float(empty["total_final_biomass_kg"]), 0.0, "empty final zero")
	if not failure.is_empty(): return failure

	failure = _assert(Dispersal.disperse(patches, edges, {"dispersal_fraction": -0.01}).is_empty(), "negative dispersal fraction fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Dispersal.disperse(patches, edges, {"dispersal_fraction": 1.01}).is_empty(), "dispersal fraction above one fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Dispersal.disperse(patches, edges, {"dispersal_fraction": 0.2, "unexpected": 1}).is_empty(), "unexpected config field fails closed")
	if not failure.is_empty(): return failure
	var duplicate_patches := [patches[0], patches[0]]
	failure = _assert(Dispersal.disperse(duplicate_patches, [], {"dispersal_fraction": 0.2}).is_empty(), "duplicate patch IDs fail closed")
	if not failure.is_empty(): return failure
	var bad_boundary := _patch("A", patch_a, 1.01)
	failure = _assert(Dispersal.disperse([bad_boundary], [], {"dispersal_fraction": 0.2}).is_empty(), "boundary fraction above one fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Dispersal.disperse(patches, [_edge("A", "A", 1.0)], {"dispersal_fraction": 0.2}).is_empty(), "self edge fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Dispersal.disperse(patches, [_edge("A", "MISSING", 1.0)], {"dispersal_fraction": 0.2}).is_empty(), "edge to missing patch fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Dispersal.disperse(patches, [_edge("A", "B", 1.0), _edge("A", "B", 2.0)], {"dispersal_fraction": 0.2}).is_empty(), "duplicate directed edge fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Dispersal.disperse(patches, [_edge("A", "B", 0.0)], {"dispersal_fraction": 0.2}).is_empty(), "zero edge weight fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Dispersal.disperse(patches, [_edge("A", "B", 1.0e308), _edge("A", "C", 1.0e308)], {"dispersal_fraction": 0.2}).is_empty(), "non-finite outgoing weight sum fails closed")
	if not failure.is_empty(): return failure
	var unexpected_patch := _patch("A", patch_a, 0.0)
	unexpected_patch["unexpected"] = true
	failure = _assert(Dispersal.disperse([unexpected_patch], [], {"dispersal_fraction": 0.2}).is_empty(), "unexpected patch field fails closed")
	if not failure.is_empty(): return failure
	var unexpected_edge := _edge("A", "B", 1.0)
	unexpected_edge["unexpected"] = true
	failure = _assert(Dispersal.disperse(patches, [unexpected_edge], {"dispersal_fraction": 0.2}).is_empty(), "unexpected edge field fails closed")
	if not failure.is_empty(): return failure
	var malformed_density := patch_a.duplicate(true)
	malformed_density["density_feedback"] = 123.0
	failure = _assert(Dispersal.disperse([_patch("A", malformed_density, 0.0)], [], {"dispersal_fraction": 0.2}).is_empty(), "tampered P3.2 parent fails closed")
	if not failure.is_empty(): return failure

	var tampered_transfer := result.duplicate(true)
	tampered_transfer["transfers"][0]["biomass_kg"] = 99.0
	failure = _assert(not bool(Dispersal.validate_result(tampered_transfer).get("success", false)), "tampered transfer rejected")
	if not failure.is_empty(): return failure
	var tampered_patch := result.duplicate(true)
	tampered_patch["patches"][0]["final_total_biomass_kg"] = 99.0
	failure = _assert(not bool(Dispersal.validate_result(tampered_patch).get("success", false)), "tampered patch derived state rejected")
	if not failure.is_empty(): return failure
	var tampered_order := result.duplicate(true)
	var reversed_order: PackedStringArray = PackedStringArray(tampered_order["patches"][0]["plant_order"])
	reversed_order.reverse()
	tampered_order["patches"][0]["plant_order"] = reversed_order
	failure = _assert(not bool(Dispersal.validate_result(tampered_order).get("success", false)), "tampered patch plant order rejected")
	if not failure.is_empty(): return failure
	var tampered_parent := result.duplicate(true)
	tampered_parent["parent_p3_2_accepted_aggregate"] = "deadbeef"
	failure = _assert(not bool(Dispersal.validate_result(tampered_parent).get("success", false)), "tampered parent pin rejected")
	if not failure.is_empty(): return failure

	seed(90210)
	var rng_before_a := randi()
	var rng_probe := Dispersal.disperse(patches, edges, {"dispersal_fraction": 0.2})
	var rng_after_a := randi()
	seed(90210)
	var rng_before_b := randi()
	var rng_after_b := randi()
	failure = _assert(not rng_probe.is_empty() and rng_before_a == rng_before_b and rng_after_a == rng_after_b, "P3.3 consumes no global RNG")
	if not failure.is_empty(): return failure

	var aggregate := "\n".join(PackedStringArray([
		Dispersal.PARENT_P3_2_ACCEPTED_AGGREGATE,
		String(result["result_hash"]),
		String(closed["result_hash"]),
		String(isolated["result_hash"]),
		String(no_dispersal["result_hash"]),
		String(empty["result_hash"]),
	])).sha256_text()
	print("ECO.P3.3 Spatial Dispersal: PASS (%d assertions)" % assertion_count)
	print("aggregate_hash=%s" % aggregate)
	print("network_hash=%s" % String(result["result_hash"]))
	print("closed_hash=%s" % String(closed["result_hash"]))
	print("isolated_hash=%s" % String(isolated["result_hash"]))
	print("parent_p3_2=%s" % Dispersal.PARENT_P3_2_ACCEPTED_AGGREGATE)
	quit(0)
	return ""

func _density(plants: Array, capacity: float) -> Dictionary:
	var competitors: Array = []
	for plant_variant in plants:
		var plant: Dictionary = plant_variant
		competitors.append(_competitor(String(plant["id"])))
	var competition := Competition.compete(_resources(100.0, 100.0, 100.0), competitors)
	return Density.step(competition, _density_patch(capacity), plants)

func _competitor(id: String) -> Dictionary:
	return {"id": id, "demand": _resources(1.0, 1.0, 1.0), "capture_efficiency": _resources(1.0, 1.0, 1.0)}

func _resources(light: float, water: float, nutrients: float) -> Dictionary:
	return {"light": light, "water": water, "nutrients": nutrients}

func _density_patch(capacity: float) -> Dictionary:
	return {
		"area_m2": capacity,
		"reference_capacity_kg_m2": 1.0,
		"minimum_capacity_fraction": 0.25,
		"max_recovery_fraction": 0.25,
		"max_decline_fraction": 0.60,
	}

func _biomass(id: String, biomass_kg: float) -> Dictionary:
	return {"id": id, "biomass_kg": biomass_kg}

func _patch(id: String, density_result: Dictionary, boundary_fraction: float) -> Dictionary:
	return {"id": id, "density_result": density_result, "boundary_export_fraction": boundary_fraction}

func _edge(from_id: String, to_id: String, weight: float) -> Dictionary:
	return {"from": from_id, "to": to_id, "weight": weight}

func _edge_record(result: Dictionary, from_id: String, to_id: String) -> Dictionary:
	for edge_variant in Array(result.get("edges", [])):
		var edge: Dictionary = edge_variant
		if String(edge.get("from", "")) == from_id and String(edge.get("to", "")) == to_id:
			return edge
	return {}

func _transfer(result: Dictionary, from_id: String, to_id: String, plant_id: String) -> Dictionary:
	for transfer_variant in Array(result.get("transfers", [])):
		var transfer: Dictionary = transfer_variant
		if String(transfer.get("from", "")) == from_id and String(transfer.get("to", "")) == to_id and String(transfer.get("plant_id", "")) == plant_id:
			return transfer
	return {}

func _boundary(result: Dictionary, patch_id: String, plant_id: String) -> Dictionary:
	for boundary_variant in Array(result.get("boundary_exports", [])):
		var boundary: Dictionary = boundary_variant
		if String(boundary.get("patch_id", "")) == patch_id and String(boundary.get("plant_id", "")) == plant_id:
			return boundary
	return {}

func _patch_record(result: Dictionary, patch_id: String) -> Dictionary:
	for patch_variant in Array(result.get("patches", [])):
		var patch: Dictionary = patch_variant
		if String(patch.get("id", "")) == patch_id:
			return patch
	return {}

func _plant_record(result: Dictionary, patch_id: String, plant_id: String) -> Dictionary:
	var patch := _patch_record(result, patch_id)
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
