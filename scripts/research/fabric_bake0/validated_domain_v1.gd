extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_validated_domain.v1"
const RANGE_FIELDS: Array[String] = ["quantity_id", "dimension", "minimum", "maximum"]
const FIELDS: Array[String] = [
	"schema", "exact_frontier_hash", "exact_fabric_graph_hash",
	"scalar_ranges", "allowed_modes", "time_horizon_s", "checksum",
]

static func create(exact_frontier_hash: String, exact_fabric_graph_hash: String, scalar_ranges: Array = [], allowed_modes: Array = [], time_horizon_s: float = 0.0) -> Dictionary:
	var ranges := Utils.sorted_dicts(scalar_ranges, "quantity_id")
	var modes := Utils.sorted_strings(allowed_modes)
	var value: Dictionary = {
		"schema": SCHEMA,
		"exact_frontier_hash": exact_frontier_hash,
		"exact_fabric_graph_hash": exact_fabric_graph_hash,
		"scalar_ranges": ranges,
		"allowed_modes": modes,
		"time_horizon_s": time_horizon_s,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_VALIDATED_DOMAIN_SCHEMA")
	for field in ["exact_frontier_hash", "exact_fabric_graph_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_VALIDATED_DOMAIN_HASH", {"field": field})
	if typeof(value.get("scalar_ranges")) != TYPE_ARRAY:
		return Utils.failure("INVALID_VALIDATED_DOMAIN_RANGES")
	var previous := ""
	for index in range(value["scalar_ranges"].size()):
		var raw = value["scalar_ranges"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_VALIDATED_DOMAIN_RANGE", {"index": index})
		var range_value: Dictionary = raw
		checked = Utils.validate_exact_fields(range_value, RANGE_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(range_value.get("quantity_id"), 2):
			return Utils.failure("INVALID_VALIDATED_DOMAIN_QUANTITY", {"index": index})
		checked = Utils.validate_dimension(range_value.get("dimension"))
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_finite_number(range_value.get("minimum")) or not Utils.is_finite_number(range_value.get("maximum")):
			return Utils.failure("INVALID_VALIDATED_DOMAIN_RANGE", {"index": index})
		if float(range_value["minimum"]) > float(range_value["maximum"]):
			return Utils.failure("INVALID_VALIDATED_DOMAIN_RANGE_ORDER", {"index": index})
		var current := String(range_value["quantity_id"])
		if index > 0 and current <= previous:
			return Utils.failure("VALIDATED_DOMAIN_RANGES_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	checked = Utils.validate_sorted_unique_strings(value.get("allowed_modes"), true, true)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_non_negative_number(value.get("time_horizon_s")):
		return Utils.failure("INVALID_VALIDATED_DOMAIN_HORIZON")
	return Utils.validate_checksum(value)

static func contains(value: Dictionary, runtime_context: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_lower_hex_64(runtime_context.get("source_frontier_hash")) or String(runtime_context["source_frontier_hash"]) != String(value["exact_frontier_hash"]):
		return Utils.failure("BAKE_VALIDITY_EXIT_SOURCE_FRONTIER")
	if not Utils.is_lower_hex_64(runtime_context.get("fabric_graph_hash")) or String(runtime_context["fabric_graph_hash"]) != String(value["exact_fabric_graph_hash"]):
		return Utils.failure("BAKE_VALIDITY_EXIT_FABRIC_GRAPH")
	if not Utils.is_non_negative_number(runtime_context.get("elapsed_s")):
		return Utils.failure("INVALID_BAKE_RUNTIME_ELAPSED")
	if float(value["time_horizon_s"]) > 0.0 and float(runtime_context["elapsed_s"]) > float(value["time_horizon_s"]):
		return Utils.failure("BAKE_VALIDITY_EXIT_HORIZON")
	if typeof(runtime_context.get("mode")) != TYPE_STRING:
		return Utils.failure("INVALID_BAKE_RUNTIME_MODE")
	if not value["allowed_modes"].is_empty() and not value["allowed_modes"].has(String(runtime_context["mode"])):
		return Utils.failure("BAKE_VALIDITY_EXIT_MODE")
	if typeof(runtime_context.get("quantities")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_RUNTIME_QUANTITIES")
	for range_value in value["scalar_ranges"]:
		var quantity_id := String(range_value["quantity_id"])
		if not runtime_context["quantities"].has(quantity_id) or not Utils.is_finite_number(runtime_context["quantities"][quantity_id]):
			return Utils.failure("BAKE_VALIDITY_EXIT_QUANTITY_MISSING", {"quantity_id": quantity_id})
		var sample := float(runtime_context["quantities"][quantity_id])
		if sample < float(range_value["minimum"]) or sample > float(range_value["maximum"]):
			return Utils.failure("BAKE_VALIDITY_EXIT_QUANTITY", {"quantity_id": quantity_id})
	return Utils.success()
