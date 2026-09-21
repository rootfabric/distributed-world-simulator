extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/thermal_filter_interface_contract_v1.gd")

const SCHEMA := "planet_simulator.fabric_thermal_filter_descriptor.v1"
const FIELDS: Array[String] = [
	"schema", "graph_hash", "material_catalog_hash", "interface_contract",
	"layer_count", "lane_count", "source_cell_count", "layer_capacity_j_k",
	"layer_link_conductance_w_k", "ambient_conductance_w_k", "total_mass_kg",
	"min_temperature_k", "max_temperature_k", "source_operation_count",
	"compiled_operation_count", "descriptor_hash", "checksum",
]

static func create(data: Dictionary) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_hash": String(data.graph_hash),
		"material_catalog_hash": String(data.material_catalog_hash),
		"interface_contract": data.interface_contract.duplicate(true),
		"layer_count": int(data.layer_count),
		"lane_count": int(data.lane_count),
		"source_cell_count": int(data.source_cell_count),
		"layer_capacity_j_k": data.layer_capacity_j_k.duplicate(),
		"layer_link_conductance_w_k": data.layer_link_conductance_w_k.duplicate(),
		"ambient_conductance_w_k": float(data.ambient_conductance_w_k),
		"total_mass_kg": float(data.total_mass_kg),
		"min_temperature_k": float(data.min_temperature_k),
		"max_temperature_k": float(data.max_temperature_k),
		"source_operation_count": int(data.source_operation_count),
		"compiled_operation_count": int(data.compiled_operation_count),
		"descriptor_hash": "",
		"checksum": "",
	}
	value.descriptor_hash = U.canonical_hash(_identity(value))
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_THERMAL_FILTER_DESCRIPTOR_SCHEMA")
	for field in ["graph_hash", "material_catalog_hash", "descriptor_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_THERMAL_FILTER_DESCRIPTOR_HASH", {"field": field})
	checked = Interface.validate(value.interface_contract)
	if not checked.success:
		return checked
	for field in ["layer_count", "lane_count", "source_cell_count", "source_operation_count", "compiled_operation_count"]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return U.failure("INVALID_THERMAL_FILTER_DESCRIPTOR_INTEGER", {"field": field})
	if int(value.layer_count) < 2 or int(value.source_cell_count) != int(value.layer_count) * int(value.lane_count):
		return U.failure("THERMAL_FILTER_DESCRIPTOR_TOPOLOGY_INVALID")
	if typeof(value.get("layer_capacity_j_k")) != TYPE_ARRAY or value.layer_capacity_j_k.size() != int(value.layer_count):
		return U.failure("THERMAL_FILTER_LAYER_CAPACITY_SIZE")
	if typeof(value.get("layer_link_conductance_w_k")) != TYPE_ARRAY or value.layer_link_conductance_w_k.size() != int(value.layer_count) - 1:
		return U.failure("THERMAL_FILTER_LINK_CONDUCTANCE_SIZE")
	for number in value.layer_capacity_j_k:
		if not U.is_positive_number(number):
			return U.failure("INVALID_THERMAL_FILTER_LAYER_CAPACITY")
	for number in value.layer_link_conductance_w_k:
		if not U.is_positive_number(number):
			return U.failure("INVALID_THERMAL_FILTER_LINK_CONDUCTANCE")
	for field in ["ambient_conductance_w_k", "total_mass_kg", "min_temperature_k", "max_temperature_k"]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_THERMAL_FILTER_SCALAR", {"field": field})
	if float(value.min_temperature_k) >= float(value.max_temperature_k):
		return U.failure("THERMAL_FILTER_TEMPERATURE_DOMAIN_EMPTY")
	if int(value.source_operation_count) <= int(value.compiled_operation_count):
		return U.failure("INSUFFICIENT_THERMAL_FILTER_COMPRESSION")
	if String(value.descriptor_hash) != U.canonical_hash(_identity(value)):
		return U.failure("THERMAL_FILTER_DESCRIPTOR_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	return payload
