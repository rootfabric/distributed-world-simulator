extends RefCounted

const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.obs1_spatial_snapshot.v1"
const VERSION := "1.0.0"
const EPSILON := 0.000000000001

const SNAPSHOT_FIELDS: Array[String] = [
	"schema",
	"version",
	"step_index",
	"year",
	"source_schema",
	"source_result_hash",
	"parent_p3_2_aggregate",
	"dispersal_fraction",
	"patch_order",
	"patches",
	"edges",
	"boundary_exports",
	"total_source_biomass_kg",
	"total_internal_transfer_biomass_kg",
	"total_boundary_export_biomass_kg",
	"total_final_biomass_kg",
	"conservation_error_kg",
	"snapshot_hash",
]
const PATCH_FIELDS: Array[String] = [
	"id",
	"source_total_biomass_kg",
	"incoming_total_biomass_kg",
	"final_total_biomass_kg",
	"plant_order",
	"plants",
]
const PLANT_FIELDS: Array[String] = ["id", "source_biomass_kg", "final_biomass_kg", "incoming_biomass_kg"]
const EDGE_FIELDS: Array[String] = ["from", "to", "share", "transfer_biomass_kg"]
const BOUNDARY_FIELDS: Array[String] = ["patch_id", "biomass_kg"]

static func from_p3_3(result: Dictionary, step_index: int, year: float) -> Dictionary:
	if step_index < 0 or not is_finite(year) or year < 0.0:
		return {}
	if not bool(Dispersal.validate_result(result).get("success", false)):
		return {}
	var source_hash := String(result.get("result_hash", ""))
	if source_hash.length() != 64:
		return {}
	var config: Dictionary = result.get("config", {})
	var dispersal_fraction := float(config.get("dispersal_fraction", -1.0))
	if not is_finite(dispersal_fraction) or dispersal_fraction < 0.0 or dispersal_fraction > 1.0:
		return {}

	var patch_order := PackedStringArray(result.get("patch_order", PackedStringArray()))
	var patches: Array[Dictionary] = []
	for patch_variant in Array(result.get("patches", [])):
		if typeof(patch_variant) != TYPE_DICTIONARY:
			return {}
		var patch: Dictionary = patch_variant
		var plant_order := PackedStringArray(patch.get("plant_order", PackedStringArray()))
		var plants: Array[Dictionary] = []
		for plant_variant in Array(patch.get("plants", [])):
			if typeof(plant_variant) != TYPE_DICTIONARY:
				return {}
			var plant: Dictionary = plant_variant
			plants.append({
				"id": String(plant.get("id", "")),
				"source_biomass_kg": float(plant.get("source_biomass_kg", 0.0)),
				"final_biomass_kg": float(plant.get("final_biomass_kg", 0.0)),
				"incoming_biomass_kg": float(plant.get("incoming_biomass_kg", 0.0)),
			})
		patches.append({
			"id": String(patch.get("id", "")),
			"source_total_biomass_kg": float(patch.get("source_total_biomass_kg", 0.0)),
			"incoming_total_biomass_kg": float(patch.get("incoming_total_biomass_kg", 0.0)),
			"final_total_biomass_kg": float(patch.get("final_total_biomass_kg", 0.0)),
			"plant_order": plant_order,
			"plants": plants,
		})

	var transfer_by_edge := {}
	for transfer_variant in Array(result.get("transfers", [])):
		if typeof(transfer_variant) != TYPE_DICTIONARY:
			return {}
		var transfer: Dictionary = transfer_variant
		var key := _edge_key(String(transfer.get("from", "")), String(transfer.get("to", "")))
		transfer_by_edge[key] = float(transfer_by_edge.get(key, 0.0)) + float(transfer.get("biomass_kg", 0.0))
		if not is_finite(float(transfer_by_edge[key])):
			return {}

	var edges: Array[Dictionary] = []
	for edge_variant in Array(result.get("edges", [])):
		if typeof(edge_variant) != TYPE_DICTIONARY:
			return {}
		var edge: Dictionary = edge_variant
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		edges.append({
			"from": from_id,
			"to": to_id,
			"share": float(edge.get("share", 0.0)),
			"transfer_biomass_kg": float(transfer_by_edge.get(_edge_key(from_id, to_id), 0.0)),
		})

	var boundary_by_patch := {}
	for boundary_variant in Array(result.get("boundary_exports", [])):
		if typeof(boundary_variant) != TYPE_DICTIONARY:
			return {}
		var boundary: Dictionary = boundary_variant
		var patch_id := String(boundary.get("patch_id", ""))
		boundary_by_patch[patch_id] = float(boundary_by_patch.get(patch_id, 0.0)) + float(boundary.get("biomass_kg", 0.0))
		if not is_finite(float(boundary_by_patch[patch_id])):
			return {}
	var boundary_exports: Array[Dictionary] = []
	for patch_id in patch_order:
		boundary_exports.append({"patch_id": patch_id, "biomass_kg": float(boundary_by_patch.get(patch_id, 0.0))})

	var snapshot := {
		"schema": SCHEMA,
		"version": VERSION,
		"step_index": step_index,
		"year": year,
		"source_schema": String(result.get("schema", "")),
		"source_result_hash": source_hash,
		"parent_p3_2_aggregate": String(result.get("parent_p3_2_accepted_aggregate", "")),
		"dispersal_fraction": dispersal_fraction,
		"patch_order": patch_order,
		"patches": patches,
		"edges": edges,
		"boundary_exports": boundary_exports,
		"total_source_biomass_kg": float(result.get("total_source_biomass_kg", 0.0)),
		"total_internal_transfer_biomass_kg": float(result.get("total_internal_transfer_biomass_kg", 0.0)),
		"total_boundary_export_biomass_kg": float(result.get("total_boundary_export_biomass_kg", 0.0)),
		"total_final_biomass_kg": float(result.get("total_final_biomass_kg", 0.0)),
		"conservation_error_kg": float(result.get("conservation_error_kg", 0.0)),
	}
	snapshot["snapshot_hash"] = compute_hash(snapshot)
	return snapshot

static func validate(snapshot: Dictionary) -> Dictionary:
	if not _has_exact_fields(snapshot, SNAPSHOT_FIELDS):
		return _failure("ECO_OBS1_SPATIAL_FIELDS_MISMATCH")
	if String(snapshot.get("schema", "")) != SCHEMA or String(snapshot.get("version", "")) != VERSION:
		return _failure("ECO_OBS1_SPATIAL_SCHEMA_MISMATCH")
	if typeof(snapshot.get("step_index")) != TYPE_INT or int(snapshot.get("step_index", -1)) < 0:
		return _failure("ECO_OBS1_SPATIAL_INVALID_STEP")
	if typeof(snapshot.get("year")) not in [TYPE_INT, TYPE_FLOAT] or not _finite_nonnegative(snapshot.get("year")):
		return _failure("ECO_OBS1_SPATIAL_INVALID_YEAR")
	if String(snapshot.get("source_schema", "")) != Dispersal.SCHEMA:
		return _failure("ECO_OBS1_SPATIAL_SOURCE_SCHEMA_MISMATCH")
	if String(snapshot.get("source_result_hash", "")).length() != 64:
		return _failure("ECO_OBS1_SPATIAL_SOURCE_HASH_INVALID")
	if String(snapshot.get("parent_p3_2_aggregate", "")) != Dispersal.PARENT_P3_2_ACCEPTED_AGGREGATE:
		return _failure("ECO_OBS1_SPATIAL_PARENT_MISMATCH")
	var fraction_raw = snapshot.get("dispersal_fraction")
	if typeof(fraction_raw) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("ECO_OBS1_SPATIAL_FRACTION_TYPE_MISMATCH")
	var dispersal_fraction := float(fraction_raw)
	if not is_finite(dispersal_fraction) or dispersal_fraction < 0.0 or dispersal_fraction > 1.0:
		return _failure("ECO_OBS1_SPATIAL_FRACTION_INVALID")

	if typeof(snapshot.get("patch_order")) != TYPE_PACKED_STRING_ARRAY or typeof(snapshot.get("patches")) != TYPE_ARRAY:
		return _failure("ECO_OBS1_SPATIAL_PATCH_CONTAINER_MISMATCH")
	var patch_order: PackedStringArray = snapshot["patch_order"]
	var sorted_patch_order := patch_order.duplicate()
	sorted_patch_order.sort()
	if sorted_patch_order != patch_order:
		return _failure("ECO_OBS1_SPATIAL_PATCH_ORDER_NOT_CANONICAL")
	var patches: Array = snapshot["patches"]
	if patches.size() != patch_order.size():
		return _failure("ECO_OBS1_SPATIAL_PATCH_COUNT_MISMATCH")
	var source_sum := 0.0
	var incoming_sum := 0.0
	var final_sum := 0.0
	for patch_index in range(patches.size()):
		if typeof(patches[patch_index]) != TYPE_DICTIONARY:
			return _failure("ECO_OBS1_SPATIAL_PATCH_TYPE_MISMATCH")
		var patch: Dictionary = patches[patch_index]
		if not _has_exact_fields(patch, PATCH_FIELDS):
			return _failure("ECO_OBS1_SPATIAL_PATCH_FIELDS_MISMATCH")
		if String(patch.get("id", "")) != String(patch_order[patch_index]):
			return _failure("ECO_OBS1_SPATIAL_PATCH_ORDER_MISMATCH")
		for field_name in ["source_total_biomass_kg", "incoming_total_biomass_kg", "final_total_biomass_kg"]:
			if not _finite_nonnegative(patch.get(field_name)):
				return _failure("ECO_OBS1_SPATIAL_PATCH_NUMERIC_INVALID", {"field": field_name})
		if typeof(patch.get("plant_order")) != TYPE_PACKED_STRING_ARRAY or typeof(patch.get("plants")) != TYPE_ARRAY:
			return _failure("ECO_OBS1_SPATIAL_PLANT_CONTAINER_MISMATCH")
		var plant_order: PackedStringArray = patch["plant_order"]
		var sorted_plant_order := plant_order.duplicate()
		sorted_plant_order.sort()
		if sorted_plant_order != plant_order:
			return _failure("ECO_OBS1_SPATIAL_PLANT_ORDER_NOT_CANONICAL")
		var plants: Array = patch["plants"]
		if plants.size() != plant_order.size():
			return _failure("ECO_OBS1_SPATIAL_PLANT_COUNT_MISMATCH")
		var patch_source := 0.0
		var patch_incoming := 0.0
		var patch_final := 0.0
		for plant_index in range(plants.size()):
			if typeof(plants[plant_index]) != TYPE_DICTIONARY:
				return _failure("ECO_OBS1_SPATIAL_PLANT_TYPE_MISMATCH")
			var plant: Dictionary = plants[plant_index]
			if not _has_exact_fields(plant, PLANT_FIELDS):
				return _failure("ECO_OBS1_SPATIAL_PLANT_FIELDS_MISMATCH")
			if String(plant.get("id", "")) != String(plant_order[plant_index]):
				return _failure("ECO_OBS1_SPATIAL_PLANT_ORDER_MISMATCH")
			if not _finite_nonnegative(plant.get("source_biomass_kg")) or not _finite_nonnegative(plant.get("final_biomass_kg")) or not _finite_nonnegative(plant.get("incoming_biomass_kg")):
				return _failure("ECO_OBS1_SPATIAL_PLANT_NUMERIC_INVALID")
			patch_source += float(plant["source_biomass_kg"])
			patch_incoming += float(plant["incoming_biomass_kg"])
			patch_final += float(plant["final_biomass_kg"])
		if absf(patch_source - float(patch["source_total_biomass_kg"])) > EPSILON:
			return _failure("ECO_OBS1_SPATIAL_PATCH_SOURCE_MISMATCH")
		if absf(patch_incoming - float(patch["incoming_total_biomass_kg"])) > EPSILON:
			return _failure("ECO_OBS1_SPATIAL_PATCH_INCOMING_MISMATCH")
		if absf(patch_final - float(patch["final_total_biomass_kg"])) > EPSILON:
			return _failure("ECO_OBS1_SPATIAL_PATCH_FINAL_MISMATCH")
		source_sum += float(patch["source_total_biomass_kg"])
		incoming_sum += float(patch["incoming_total_biomass_kg"])
		final_sum += float(patch["final_total_biomass_kg"])

	if typeof(snapshot.get("edges")) != TYPE_ARRAY:
		return _failure("ECO_OBS1_SPATIAL_EDGE_CONTAINER_MISMATCH")
	var edges: Array = snapshot["edges"]
	var previous_edge_key := ""
	var edge_transfer_sum := 0.0
	var share_sum_by_source := {}
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			return _failure("ECO_OBS1_SPATIAL_EDGE_TYPE_MISMATCH")
		var edge: Dictionary = edge_variant
		if not _has_exact_fields(edge, EDGE_FIELDS):
			return _failure("ECO_OBS1_SPATIAL_EDGE_FIELDS_MISMATCH")
		var from_id := String(edge.get("from", ""))
		var to_id := String(edge.get("to", ""))
		if from_id.is_empty() or to_id.is_empty() or not from_id in patch_order or not to_id in patch_order:
			return _failure("ECO_OBS1_SPATIAL_EDGE_PATCH_MISMATCH")
		var key := _edge_key(from_id, to_id)
		if not previous_edge_key.is_empty() and key <= previous_edge_key:
			return _failure("ECO_OBS1_SPATIAL_EDGE_ORDER_NOT_CANONICAL")
		previous_edge_key = key
		var share_raw = edge.get("share")
		if typeof(share_raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(share_raw)) or float(share_raw) < 0.0 or float(share_raw) > 1.0:
			return _failure("ECO_OBS1_SPATIAL_EDGE_SHARE_INVALID")
		if not _finite_nonnegative(edge.get("transfer_biomass_kg")):
			return _failure("ECO_OBS1_SPATIAL_EDGE_TRANSFER_INVALID")
		edge_transfer_sum += float(edge["transfer_biomass_kg"])
		share_sum_by_source[from_id] = float(share_sum_by_source.get(from_id, 0.0)) + float(edge["share"])
	for source_id in share_sum_by_source.keys():
		if absf(float(share_sum_by_source[source_id]) - 1.0) > EPSILON:
			return _failure("ECO_OBS1_SPATIAL_EDGE_SHARE_SUM_MISMATCH", {"source": String(source_id)})

	if typeof(snapshot.get("boundary_exports")) != TYPE_ARRAY:
		return _failure("ECO_OBS1_SPATIAL_BOUNDARY_CONTAINER_MISMATCH")
	var boundary_exports: Array = snapshot["boundary_exports"]
	if boundary_exports.size() != patch_order.size():
		return _failure("ECO_OBS1_SPATIAL_BOUNDARY_COUNT_MISMATCH")
	var boundary_sum := 0.0
	for boundary_index in range(boundary_exports.size()):
		if typeof(boundary_exports[boundary_index]) != TYPE_DICTIONARY:
			return _failure("ECO_OBS1_SPATIAL_BOUNDARY_TYPE_MISMATCH")
		var boundary: Dictionary = boundary_exports[boundary_index]
		if not _has_exact_fields(boundary, BOUNDARY_FIELDS):
			return _failure("ECO_OBS1_SPATIAL_BOUNDARY_FIELDS_MISMATCH")
		if String(boundary.get("patch_id", "")) != String(patch_order[boundary_index]) or not _finite_nonnegative(boundary.get("biomass_kg")):
			return _failure("ECO_OBS1_SPATIAL_BOUNDARY_INVALID")
		boundary_sum += float(boundary["biomass_kg"])

	for field_name in ["total_source_biomass_kg", "total_internal_transfer_biomass_kg", "total_boundary_export_biomass_kg", "total_final_biomass_kg", "conservation_error_kg"]:
		if not _finite_nonnegative(snapshot.get(field_name)):
			return _failure("ECO_OBS1_SPATIAL_TOTAL_INVALID", {"field": field_name})
	if absf(source_sum - float(snapshot["total_source_biomass_kg"])) > EPSILON:
		return _failure("ECO_OBS1_SPATIAL_SOURCE_TOTAL_MISMATCH")
	if absf(incoming_sum - float(snapshot["total_internal_transfer_biomass_kg"])) > EPSILON or absf(edge_transfer_sum - float(snapshot["total_internal_transfer_biomass_kg"])) > EPSILON:
		return _failure("ECO_OBS1_SPATIAL_TRANSFER_TOTAL_MISMATCH")
	if absf(boundary_sum - float(snapshot["total_boundary_export_biomass_kg"])) > EPSILON:
		return _failure("ECO_OBS1_SPATIAL_BOUNDARY_TOTAL_MISMATCH")
	if absf(final_sum - float(snapshot["total_final_biomass_kg"])) > EPSILON:
		return _failure("ECO_OBS1_SPATIAL_FINAL_TOTAL_MISMATCH")
	var conservation_error := absf(float(snapshot["total_source_biomass_kg"]) - (float(snapshot["total_final_biomass_kg"]) + float(snapshot["total_boundary_export_biomass_kg"])))
	if absf(conservation_error - float(snapshot["conservation_error_kg"])) > EPSILON:
		return _failure("ECO_OBS1_SPATIAL_CONSERVATION_ERROR_MISMATCH")
	if String(snapshot.get("snapshot_hash", "")) != compute_hash(snapshot):
		return _failure("ECO_OBS1_SPATIAL_HASH_MISMATCH")
	return _success()

static func compute_hash(snapshot: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		"step=%d" % int(snapshot.get("step_index", 0)),
		"year=%.12f" % float(snapshot.get("year", 0.0)),
		"source=%s" % String(snapshot.get("source_result_hash", "")),
		"parent_p3_2=%s" % String(snapshot.get("parent_p3_2_aggregate", "")),
		"dispersal_fraction=%.12f" % float(snapshot.get("dispersal_fraction", 0.0)),
	])
	for patch_variant in Array(snapshot.get("patches", [])):
		if typeof(patch_variant) != TYPE_DICTIONARY:
			continue
		var patch: Dictionary = patch_variant
		tokens.append("patch|%s|source=%.12f|incoming=%.12f|final=%.12f" % [String(patch.get("id", "")), float(patch.get("source_total_biomass_kg", 0.0)), float(patch.get("incoming_total_biomass_kg", 0.0)), float(patch.get("final_total_biomass_kg", 0.0))])
		for plant_variant in Array(patch.get("plants", [])):
			if typeof(plant_variant) == TYPE_DICTIONARY:
				var plant: Dictionary = plant_variant
				tokens.append("plant|%s|source=%.12f|final=%.12f|incoming=%.12f" % [String(plant.get("id", "")), float(plant.get("source_biomass_kg", 0.0)), float(plant.get("final_biomass_kg", 0.0)), float(plant.get("incoming_biomass_kg", 0.0))])
	for edge_variant in Array(snapshot.get("edges", [])):
		if typeof(edge_variant) == TYPE_DICTIONARY:
			var edge: Dictionary = edge_variant
			tokens.append("edge|%s|%s|share=%.12f|transfer=%.12f" % [String(edge.get("from", "")), String(edge.get("to", "")), float(edge.get("share", 0.0)), float(edge.get("transfer_biomass_kg", 0.0))])
	for boundary_variant in Array(snapshot.get("boundary_exports", [])):
		if typeof(boundary_variant) == TYPE_DICTIONARY:
			var boundary: Dictionary = boundary_variant
			tokens.append("boundary|%s|%.12f" % [String(boundary.get("patch_id", "")), float(boundary.get("biomass_kg", 0.0))])
	for field_name in ["total_source_biomass_kg", "total_internal_transfer_biomass_kg", "total_boundary_export_biomass_kg", "total_final_biomass_kg", "conservation_error_kg"]:
		tokens.append("%s=%.12f" % [field_name, float(snapshot.get(field_name, 0.0))])
	return "\n".join(tokens).sha256_text()

static func _edge_key(from_id: String, to_id: String) -> String:
	return "%s\u001f%s" % [from_id, to_id]

static func _finite_nonnegative(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0

static func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field_name in fields:
		if not value.has(field_name):
			return false
	return true

static func _success() -> Dictionary:
	return {"success": true, "error_code": ""}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "error_code": code}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result
