extends RefCounted

const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p3_3_spatial_dispersal.v1"
const VERSION := "1.0.0"
const PARENT_P3_2_ACCEPTED_AGGREGATE := "172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639"
const EPSILON := 0.000000000001

const CONFIG_FIELDS: Array[String] = ["dispersal_fraction"]
const INPUT_PATCH_FIELDS: Array[String] = ["id", "density_result", "boundary_export_fraction"]
const INPUT_EDGE_FIELDS: Array[String] = ["from", "to", "weight"]
const SOURCE_PATCH_FIELDS: Array[String] = ["id", "density_result", "density_result_hash", "boundary_export_fraction"]
const EDGE_FIELDS: Array[String] = ["from", "to", "share", "record_hash"]
const TRANSFER_FIELDS: Array[String] = ["from", "to", "plant_id", "biomass_kg", "record_hash"]
const BOUNDARY_EXPORT_FIELDS: Array[String] = ["patch_id", "plant_id", "biomass_kg", "record_hash"]
const PATCH_PLANT_FIELDS: Array[String] = ["id", "source_biomass_kg", "retained_biomass_kg", "incoming_biomass_kg", "final_biomass_kg", "record_hash"]
const PATCH_RESULT_FIELDS: Array[String] = ["id", "source_total_biomass_kg", "retained_total_biomass_kg", "incoming_total_biomass_kg", "final_total_biomass_kg", "plant_order", "plants", "record_hash"]
const RESULT_FIELDS: Array[String] = [
	"schema",
	"version",
	"parent_p3_2_accepted_aggregate",
	"config",
	"patch_order",
	"source_patches",
	"edges",
	"transfers",
	"boundary_exports",
	"patches",
	"total_source_biomass_kg",
	"total_retained_biomass_kg",
	"total_internal_transfer_biomass_kg",
	"total_boundary_export_biomass_kg",
	"total_final_biomass_kg",
	"conservation_error_kg",
	"result_hash",
]

static func disperse(patches: Array, edges: Array, config: Dictionary) -> Dictionary:
	var normalized_config := _normalize_config(config)
	if normalized_config.is_empty():
		return {}
	var normalized_patches := _normalize_source_patches(patches)
	if normalized_patches.is_empty() and not patches.is_empty():
		return {}
	var patch_ids := PackedStringArray()
	var patch_by_id := {}
	for patch_variant in normalized_patches:
		var patch: Dictionary = patch_variant
		var patch_id := String(patch["id"])
		patch_ids.append(patch_id)
		patch_by_id[patch_id] = patch
	patch_ids.sort()
	var canonical_patches: Array[Dictionary] = []
	for patch_id in patch_ids:
		canonical_patches.append(Dictionary(patch_by_id[patch_id]))

	var canonical_edges := _normalize_edges(edges, patch_ids)
	if canonical_edges.is_empty() and not edges.is_empty():
		return {}

	var outgoing_by_patch := {}
	for patch_id in patch_ids:
		outgoing_by_patch[patch_id] = []
	for edge_variant in canonical_edges:
		var edge: Dictionary = edge_variant
		Array(outgoing_by_patch[String(edge["from"])]).append(edge)

	var state_by_patch := {}
	var total_source_biomass_kg := 0.0
	for source_patch_variant in canonical_patches:
		var source_patch: Dictionary = source_patch_variant
		var patch_id := String(source_patch["id"])
		var density_result: Dictionary = source_patch["density_result"]
		var plant_state := {}
		for plant_variant in Array(density_result["plants"]):
			var plant: Dictionary = plant_variant
			var plant_id := String(plant["id"])
			var source_biomass := float(plant["next_biomass_kg"])
			plant_state[plant_id] = {
				"source_biomass_kg": source_biomass,
				"retained_biomass_kg": 0.0,
				"incoming_biomass_kg": 0.0,
			}
			total_source_biomass_kg += source_biomass
			if not is_finite(total_source_biomass_kg):
				return {}
		state_by_patch[patch_id] = plant_state

	var dispersal_fraction := float(normalized_config["dispersal_fraction"])
	var transfers: Array[Dictionary] = []
	var boundary_exports: Array[Dictionary] = []
	var total_retained_biomass_kg := 0.0
	var total_internal_transfer_biomass_kg := 0.0
	var total_boundary_export_biomass_kg := 0.0

	for source_patch_variant in canonical_patches:
		var source_patch: Dictionary = source_patch_variant
		var from_id := String(source_patch["id"])
		var boundary_fraction := float(source_patch["boundary_export_fraction"])
		var outgoing: Array = outgoing_by_patch[from_id]
		var density_result: Dictionary = source_patch["density_result"]
		for plant_variant in Array(density_result["plants"]):
			var plant: Dictionary = plant_variant
			var plant_id := String(plant["id"])
			var source_biomass := float(plant["next_biomass_kg"])
			var dispersal_pool := source_biomass * dispersal_fraction
			var boundary_export := dispersal_pool * boundary_fraction
			var internal_pool := dispersal_pool - boundary_export
			var retained := source_biomass - boundary_export
			if not outgoing.is_empty():
				retained = source_biomass - dispersal_pool
				for edge_variant in outgoing:
					var edge: Dictionary = edge_variant
					var to_id := String(edge["to"])
					var transfer_biomass := internal_pool * float(edge["share"])
					var destination_state: Dictionary = state_by_patch[to_id]
					if not destination_state.has(plant_id):
						destination_state[plant_id] = {
							"source_biomass_kg": 0.0,
							"retained_biomass_kg": 0.0,
							"incoming_biomass_kg": 0.0,
						}
					var destination_plant: Dictionary = destination_state[plant_id]
					destination_plant["incoming_biomass_kg"] = float(destination_plant["incoming_biomass_kg"]) + transfer_biomass
					var transfer := {
						"from": from_id,
						"to": to_id,
						"plant_id": plant_id,
						"biomass_kg": transfer_biomass,
					}
					transfer["record_hash"] = _transfer_hash(transfer)
					transfers.append(transfer)
					total_internal_transfer_biomass_kg += transfer_biomass
					if not is_finite(total_internal_transfer_biomass_kg):
						return {}
			var source_state: Dictionary = state_by_patch[from_id]
			var source_plant: Dictionary = source_state[plant_id]
			source_plant["retained_biomass_kg"] = retained
			total_retained_biomass_kg += retained
			if not is_finite(total_retained_biomass_kg):
				return {}
			var boundary_record := {
				"patch_id": from_id,
				"plant_id": plant_id,
				"biomass_kg": boundary_export,
			}
			boundary_record["record_hash"] = _boundary_export_hash(boundary_record)
			boundary_exports.append(boundary_record)
			total_boundary_export_biomass_kg += boundary_export
			if not is_finite(total_boundary_export_biomass_kg):
				return {}

	transfers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _transfer_key(a) < _transfer_key(b)
	)
	boundary_exports.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _boundary_key(a) < _boundary_key(b)
	)

	var patch_results: Array[Dictionary] = []
	var total_final_biomass_kg := 0.0
	for patch_id in patch_ids:
		var patch_state: Dictionary = state_by_patch[patch_id]
		var plant_ids := PackedStringArray()
		for plant_id_variant in patch_state.keys():
			plant_ids.append(String(plant_id_variant))
		plant_ids.sort()
		var plant_results: Array[Dictionary] = []
		var source_total := 0.0
		var retained_total := 0.0
		var incoming_total := 0.0
		var final_total := 0.0
		for plant_id in plant_ids:
			var state: Dictionary = patch_state[plant_id]
			var source_biomass := float(state["source_biomass_kg"])
			var retained_biomass := float(state["retained_biomass_kg"])
			var incoming_biomass := float(state["incoming_biomass_kg"])
			var final_biomass := retained_biomass + incoming_biomass
			var plant_result := {
				"id": plant_id,
				"source_biomass_kg": source_biomass,
				"retained_biomass_kg": retained_biomass,
				"incoming_biomass_kg": incoming_biomass,
				"final_biomass_kg": final_biomass,
			}
			plant_result["record_hash"] = _patch_plant_hash(plant_result)
			plant_results.append(plant_result)
			source_total += source_biomass
			retained_total += retained_biomass
			incoming_total += incoming_biomass
			final_total += final_biomass
		var patch_result := {
			"id": patch_id,
			"source_total_biomass_kg": source_total,
			"retained_total_biomass_kg": retained_total,
			"incoming_total_biomass_kg": incoming_total,
			"final_total_biomass_kg": final_total,
			"plant_order": plant_ids,
			"plants": plant_results,
		}
		patch_result["record_hash"] = _patch_hash(patch_result)
		patch_results.append(patch_result)
		total_final_biomass_kg += final_total
		if not is_finite(total_final_biomass_kg):
			return {}

	var conservation_error_kg := absf(total_source_biomass_kg - (total_final_biomass_kg + total_boundary_export_biomass_kg))
	if conservation_error_kg > EPSILON:
		return {}
	if absf(total_internal_transfer_biomass_kg - (total_final_biomass_kg - total_retained_biomass_kg)) > EPSILON:
		return {}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_p3_2_accepted_aggregate": PARENT_P3_2_ACCEPTED_AGGREGATE,
		"config": normalized_config,
		"patch_order": patch_ids,
		"source_patches": canonical_patches,
		"edges": canonical_edges,
		"transfers": transfers,
		"boundary_exports": boundary_exports,
		"patches": patch_results,
		"total_source_biomass_kg": total_source_biomass_kg,
		"total_retained_biomass_kg": total_retained_biomass_kg,
		"total_internal_transfer_biomass_kg": total_internal_transfer_biomass_kg,
		"total_boundary_export_biomass_kg": total_boundary_export_biomass_kg,
		"total_final_biomass_kg": total_final_biomass_kg,
		"conservation_error_kg": conservation_error_kg,
	}
	result["result_hash"] = compute_result_hash(result)
	return result

static func validate_result(result: Dictionary) -> Dictionary:
	if not _has_exact_fields(result, RESULT_FIELDS):
		return _failure("ECO_P3_3_RESULT_FIELDS_MISMATCH")
	if String(result.get("schema", "")) != SCHEMA:
		return _failure("ECO_P3_3_SCHEMA_MISMATCH")
	if String(result.get("version", "")) != VERSION:
		return _failure("ECO_P3_3_VERSION_MISMATCH")
	if String(result.get("parent_p3_2_accepted_aggregate", "")) != PARENT_P3_2_ACCEPTED_AGGREGATE:
		return _failure("ECO_P3_3_P3_2_PARENT_MISMATCH")
	if typeof(result.get("config")) != TYPE_DICTIONARY:
		return _failure("ECO_P3_3_CONFIG_TYPE_MISMATCH")
	var config := _normalize_config(Dictionary(result["config"]))
	if config.is_empty():
		return _failure("ECO_P3_3_CONFIG_INVALID")
	if typeof(result.get("source_patches")) != TYPE_ARRAY or typeof(result.get("edges")) != TYPE_ARRAY:
		return _failure("ECO_P3_3_SOURCE_CONTAINER_TYPE_MISMATCH")
	if typeof(result.get("patch_order")) != TYPE_PACKED_STRING_ARRAY:
		return _failure("ECO_P3_3_PATCH_ORDER_TYPE_MISMATCH")
	var source_patches: Array = result["source_patches"]
	var normalized_patches := _normalize_source_patches(_source_patches_to_input(source_patches))
	if normalized_patches.is_empty() and not source_patches.is_empty():
		return _failure("ECO_P3_3_SOURCE_PATCH_INVALID")
	var expected_order := PackedStringArray()
	for patch_variant in normalized_patches:
		expected_order.append(String(Dictionary(patch_variant)["id"]))
	expected_order.sort()
	if PackedStringArray(result["patch_order"]) != expected_order:
		return _failure("ECO_P3_3_PATCH_ORDER_MISMATCH")
	for index in range(source_patches.size()):
		if typeof(source_patches[index]) != TYPE_DICTIONARY:
			return _failure("ECO_P3_3_SOURCE_PATCH_TYPE_MISMATCH")
		var patch: Dictionary = source_patches[index]
		if not _has_exact_fields(patch, SOURCE_PATCH_FIELDS):
			return _failure("ECO_P3_3_SOURCE_PATCH_FIELDS_MISMATCH")
		if String(patch.get("id", "")) != String(expected_order[index]):
			return _failure("ECO_P3_3_SOURCE_PATCH_ORDER_NOT_CANONICAL")
		if String(patch.get("density_result_hash", "")) != String(Dictionary(patch.get("density_result", {})).get("result_hash", "")):
			return _failure("ECO_P3_3_DENSITY_HASH_MISMATCH")
	var input_edges := _canonical_edges_to_input(Array(result["edges"]))
	var expected_edges := _normalize_edges(input_edges, expected_order)
	if expected_edges.is_empty() and not input_edges.is_empty():
		return _failure("ECO_P3_3_EDGE_INVALID")
	if not _edge_arrays_equal(Array(result["edges"]), expected_edges):
		return _failure("ECO_P3_3_EDGE_DERIVED_STATE_MISMATCH")
	for edge_variant in Array(result["edges"]):
		if typeof(edge_variant) != TYPE_DICTIONARY or not _has_exact_fields(Dictionary(edge_variant), EDGE_FIELDS):
			return _failure("ECO_P3_3_EDGE_FIELDS_MISMATCH")
		var edge: Dictionary = edge_variant
		if String(edge.get("record_hash", "")) != _edge_hash(edge):
			return _failure("ECO_P3_3_EDGE_HASH_MISMATCH")
	for transfer_variant in Array(result.get("transfers", [])):
		if typeof(transfer_variant) != TYPE_DICTIONARY or not _has_exact_fields(Dictionary(transfer_variant), TRANSFER_FIELDS):
			return _failure("ECO_P3_3_TRANSFER_FIELDS_MISMATCH")
		var transfer: Dictionary = transfer_variant
		if not _finite_nonnegative(transfer.get("biomass_kg")) or String(transfer.get("record_hash", "")) != _transfer_hash(transfer):
			return _failure("ECO_P3_3_TRANSFER_INVALID")
	for boundary_variant in Array(result.get("boundary_exports", [])):
		if typeof(boundary_variant) != TYPE_DICTIONARY or not _has_exact_fields(Dictionary(boundary_variant), BOUNDARY_EXPORT_FIELDS):
			return _failure("ECO_P3_3_BOUNDARY_FIELDS_MISMATCH")
		var boundary: Dictionary = boundary_variant
		if not _finite_nonnegative(boundary.get("biomass_kg")) or String(boundary.get("record_hash", "")) != _boundary_export_hash(boundary):
			return _failure("ECO_P3_3_BOUNDARY_INVALID")
	for patch_variant in Array(result.get("patches", [])):
		if typeof(patch_variant) != TYPE_DICTIONARY or not _has_exact_fields(Dictionary(patch_variant), PATCH_RESULT_FIELDS):
			return _failure("ECO_P3_3_PATCH_RESULT_FIELDS_MISMATCH")
		var patch: Dictionary = patch_variant
		if typeof(patch.get("plant_order")) != TYPE_PACKED_STRING_ARRAY or typeof(patch.get("plants")) != TYPE_ARRAY:
			return _failure("ECO_P3_3_PATCH_PLANT_CONTAINER_MISMATCH")
		for total_field in ["source_total_biomass_kg", "retained_total_biomass_kg", "incoming_total_biomass_kg", "final_total_biomass_kg"]:
			if not _finite_nonnegative(patch.get(total_field)):
				return _failure("ECO_P3_3_PATCH_TOTAL_INVALID", {"field": total_field})
		var plants: Array = patch["plants"]
		var plant_order: PackedStringArray = patch["plant_order"]
		if plants.size() != plant_order.size():
			return _failure("ECO_P3_3_PATCH_PLANT_COUNT_MISMATCH")
		var sorted_order := plant_order.duplicate()
		sorted_order.sort()
		if sorted_order != plant_order:
			return _failure("ECO_P3_3_PATCH_PLANT_ORDER_NOT_CANONICAL")
		for plant_index in range(plants.size()):
			var plant_variant = plants[plant_index]
			if typeof(plant_variant) != TYPE_DICTIONARY or not _has_exact_fields(Dictionary(plant_variant), PATCH_PLANT_FIELDS):
				return _failure("ECO_P3_3_PATCH_PLANT_FIELDS_MISMATCH")
			var plant: Dictionary = plant_variant
			if String(plant.get("id", "")) != String(plant_order[plant_index]):
				return _failure("ECO_P3_3_PATCH_PLANT_ORDER_MISMATCH")
			for field_name in ["source_biomass_kg", "retained_biomass_kg", "incoming_biomass_kg", "final_biomass_kg"]:
				if not _finite_nonnegative(plant.get(field_name)):
					return _failure("ECO_P3_3_PATCH_PLANT_NUMERIC_INVALID", {"field": field_name})
			if String(plant.get("record_hash", "")) != _patch_plant_hash(plant):
				return _failure("ECO_P3_3_PATCH_PLANT_HASH_MISMATCH")
		if String(patch.get("record_hash", "")) != _patch_hash(patch):
			return _failure("ECO_P3_3_PATCH_HASH_MISMATCH")
	var expected := disperse(_source_patches_to_input(source_patches), input_edges, config)
	if expected.is_empty():
		return _failure("ECO_P3_3_RECONSTRUCTION_FAILED")
	if String(result.get("result_hash", "")) != compute_result_hash(result):
		return _failure("ECO_P3_3_RESULT_HASH_MISMATCH")
	if String(result.get("result_hash", "")) != String(expected.get("result_hash", "")):
		return _failure("ECO_P3_3_DERIVED_STATE_MISMATCH")
	return _success()

static func compute_result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		PARENT_P3_2_ACCEPTED_AGGREGATE,
		"dispersal_fraction=%.12f" % float(Dictionary(result.get("config", {})).get("dispersal_fraction", 0.0)),
	])
	for patch_variant in Array(result.get("source_patches", [])):
		if typeof(patch_variant) == TYPE_DICTIONARY:
			var patch: Dictionary = patch_variant
			tokens.append("source|%s|density=%s|boundary=%.12f" % [String(patch.get("id", "")), String(patch.get("density_result_hash", "")), float(patch.get("boundary_export_fraction", 0.0))])
	for edge_variant in Array(result.get("edges", [])):
		if typeof(edge_variant) == TYPE_DICTIONARY:
			tokens.append("edge|%s" % String(Dictionary(edge_variant).get("record_hash", "")))
	for transfer_variant in Array(result.get("transfers", [])):
		if typeof(transfer_variant) == TYPE_DICTIONARY:
			tokens.append("transfer|%s" % String(Dictionary(transfer_variant).get("record_hash", "")))
	for boundary_variant in Array(result.get("boundary_exports", [])):
		if typeof(boundary_variant) == TYPE_DICTIONARY:
			tokens.append("boundary|%s" % String(Dictionary(boundary_variant).get("record_hash", "")))
	for patch_variant in Array(result.get("patches", [])):
		if typeof(patch_variant) == TYPE_DICTIONARY:
			tokens.append("patch|%s" % String(Dictionary(patch_variant).get("record_hash", "")))
	for field_name in ["total_source_biomass_kg", "total_retained_biomass_kg", "total_internal_transfer_biomass_kg", "total_boundary_export_biomass_kg", "total_final_biomass_kg", "conservation_error_kg"]:
		tokens.append("%s=%.12f" % [field_name, float(result.get(field_name, 0.0))])
	return "\n".join(tokens).sha256_text()

static func _normalize_config(config: Dictionary) -> Dictionary:
	if not _has_exact_fields(config, CONFIG_FIELDS):
		return {}
	var raw = config["dispersal_fraction"]
	if typeof(raw) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	var value := float(raw)
	if not is_finite(value) or value < 0.0 or value > 1.0:
		return {}
	return {"dispersal_fraction": value}

static func _normalize_source_patches(patches: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for patch_variant in patches:
		if typeof(patch_variant) != TYPE_DICTIONARY:
			return []
		var patch: Dictionary = patch_variant
		if not _has_exact_fields(patch, INPUT_PATCH_FIELDS):
			return []
		var patch_id := String(patch.get("id", ""))
		if patch_id.is_empty() or seen.has(patch_id):
			return []
		seen[patch_id] = true
		if typeof(patch.get("density_result")) != TYPE_DICTIONARY:
			return []
		var density_result: Dictionary = patch["density_result"]
		if not bool(Density.validate_result(density_result).get("success", false)):
			return []
		var raw_boundary = patch.get("boundary_export_fraction")
		if typeof(raw_boundary) not in [TYPE_INT, TYPE_FLOAT]:
			return []
		var boundary_fraction := float(raw_boundary)
		if not is_finite(boundary_fraction) or boundary_fraction < 0.0 or boundary_fraction > 1.0:
			return []
		result.append({
			"id": patch_id,
			"density_result": density_result.duplicate(true),
			"density_result_hash": String(density_result["result_hash"]),
			"boundary_export_fraction": boundary_fraction,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["id"]) < String(b["id"])
	)
	return result

static func _normalize_edges(edges: Array, patch_ids: PackedStringArray) -> Array[Dictionary]:
	var valid_patch := {}
	for patch_id in patch_ids:
		valid_patch[patch_id] = true
	var raw_edges: Array[Dictionary] = []
	var seen := {}
	var total_weight_by_source := {}
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			return []
		var edge: Dictionary = edge_variant
		if not _has_exact_fields(edge, INPUT_EDGE_FIELDS):
			return []
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
			return []
		if not valid_patch.has(from_id) or not valid_patch.has(to_id):
			return []
		var raw_weight = edge.get("weight")
		if typeof(raw_weight) not in [TYPE_INT, TYPE_FLOAT]:
			return []
		var weight := float(raw_weight)
		if not is_finite(weight) or weight <= 0.0:
			return []
		var key := "%s\u001f%s" % [from_id, to_id]
		if seen.has(key):
			return []
		seen[key] = true
		raw_edges.append({"from": from_id, "to": to_id, "weight": weight})
		total_weight_by_source[from_id] = float(total_weight_by_source.get(from_id, 0.0)) + weight
		if not is_finite(float(total_weight_by_source[from_id])):
			return []
	raw_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _edge_key(a) < _edge_key(b)
	)
	var result: Array[Dictionary] = []
	for raw_edge in raw_edges:
		var share := float(raw_edge["weight"]) / float(total_weight_by_source[String(raw_edge["from"])])
		var edge := {"from": String(raw_edge["from"]), "to": String(raw_edge["to"]), "share": share}
		edge["record_hash"] = _edge_hash(edge)
		result.append(edge)
	return result

static func _source_patches_to_input(source_patches: Array) -> Array:
	var result: Array = []
	for patch_variant in source_patches:
		if typeof(patch_variant) != TYPE_DICTIONARY:
			return []
		var patch: Dictionary = patch_variant
		result.append({
			"id": String(patch.get("id", "")),
			"density_result": Dictionary(patch.get("density_result", {})).duplicate(true),
			"boundary_export_fraction": patch.get("boundary_export_fraction"),
		})
	return result

static func _canonical_edges_to_input(edges: Array) -> Array:
	var result: Array = []
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			return []
		var edge: Dictionary = edge_variant
		result.append({"from": String(edge.get("from", "")), "to": String(edge.get("to", "")), "weight": edge.get("share")})
	return result

static func _edge_arrays_equal(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in range(actual.size()):
		if typeof(actual[index]) != TYPE_DICTIONARY or typeof(expected[index]) != TYPE_DICTIONARY:
			return false
		var a: Dictionary = actual[index]
		var b: Dictionary = expected[index]
		if String(a.get("from", "")) != String(b.get("from", "")) or String(a.get("to", "")) != String(b.get("to", "")):
			return false
		if absf(float(a.get("share", -1.0)) - float(b.get("share", -2.0))) > EPSILON:
			return false
		if String(a.get("record_hash", "")) != String(b.get("record_hash", "")):
			return false
	return true

static func _edge_key(edge: Dictionary) -> String:
	return "%s\u001f%s" % [String(edge.get("from", "")), String(edge.get("to", ""))]

static func _transfer_key(transfer: Dictionary) -> String:
	return "%s\u001f%s\u001f%s" % [String(transfer.get("from", "")), String(transfer.get("to", "")), String(transfer.get("plant_id", ""))]

static func _boundary_key(boundary: Dictionary) -> String:
	return "%s\u001f%s" % [String(boundary.get("patch_id", "")), String(boundary.get("plant_id", ""))]

static func _edge_hash(edge: Dictionary) -> String:
	return ("edge|%s|%s|%.12f" % [String(edge.get("from", "")), String(edge.get("to", "")), float(edge.get("share", 0.0))]).sha256_text()

static func _transfer_hash(transfer: Dictionary) -> String:
	return ("transfer|%s|%s|%s|%.12f" % [String(transfer.get("from", "")), String(transfer.get("to", "")), String(transfer.get("plant_id", "")), float(transfer.get("biomass_kg", 0.0))]).sha256_text()

static func _boundary_export_hash(boundary: Dictionary) -> String:
	return ("boundary|%s|%s|%.12f" % [String(boundary.get("patch_id", "")), String(boundary.get("plant_id", "")), float(boundary.get("biomass_kg", 0.0))]).sha256_text()

static func _patch_plant_hash(plant: Dictionary) -> String:
	return ("plant|%s|source=%.12f|retained=%.12f|incoming=%.12f|final=%.12f" % [
		String(plant.get("id", "")),
		float(plant.get("source_biomass_kg", 0.0)),
		float(plant.get("retained_biomass_kg", 0.0)),
		float(plant.get("incoming_biomass_kg", 0.0)),
		float(plant.get("final_biomass_kg", 0.0)),
	]).sha256_text()

static func _patch_hash(patch: Dictionary) -> String:
	var tokens := PackedStringArray(["patch", String(patch.get("id", ""))])
	if typeof(patch.get("plant_order")) == TYPE_PACKED_STRING_ARRAY:
		for plant_id in PackedStringArray(patch["plant_order"]):
			tokens.append("order|%s" % plant_id)
	for plant_variant in Array(patch.get("plants", [])):
		if typeof(plant_variant) == TYPE_DICTIONARY:
			tokens.append(String(Dictionary(plant_variant).get("record_hash", "")))
	for field_name in ["source_total_biomass_kg", "retained_total_biomass_kg", "incoming_total_biomass_kg", "final_total_biomass_kg"]:
		tokens.append("%s=%.12f" % [field_name, float(patch.get(field_name, 0.0))])
	return "\n".join(tokens).sha256_text()

static func _finite_nonnegative(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0

static func _has_exact_fields(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for field_name in expected:
		if not value.has(field_name):
			return false
	return true

static func _success() -> Dictionary:
	return {"success": true, "error": ""}

static func _failure(error: String, details: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "error": error}
	if not details.is_empty():
		result["details"] = details
	return result
