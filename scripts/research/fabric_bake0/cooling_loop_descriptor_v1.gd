extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/cooling_loop_interface_contract_v1.gd")

const SCHEMA := "planet_simulator.fabric_cooling_loop_descriptor.v1"
const FIELDS: Array[String] = [
	"schema", "graph_hash", "material_catalog_hash", "interface_contract",
	"lane_count", "source_thermal_node_count",
	"plate_capacity_j_k", "hot_coolant_capacity_j_k", "radiator_capacity_j_k", "cold_coolant_capacity_j_k",
	"plate_to_hot_conductance_w_k", "cold_to_radiator_conductance_w_k", "radiator_to_ambient_conductance_w_k",
	"coolant_heat_capacity_j_kg_k", "coolant_density_kg_m3", "dynamic_viscosity_pa_s",
	"laminar_reynolds_limit", "channel_flow_area_m2", "channel_hydraulic_diameter_m", "channel_flow_length_m",
	"max_total_mass_flow_kg_s", "total_mass_kg", "min_temperature_k", "max_temperature_k",
	"source_operation_count", "compiled_operation_count", "descriptor_hash", "checksum",
]

static func create(data: Dictionary) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_hash": String(data.graph_hash),
		"material_catalog_hash": String(data.material_catalog_hash),
		"interface_contract": data.interface_contract.duplicate(true),
		"lane_count": int(data.lane_count),
		"source_thermal_node_count": int(data.source_thermal_node_count),
		"plate_capacity_j_k": float(data.plate_capacity_j_k),
		"hot_coolant_capacity_j_k": float(data.hot_coolant_capacity_j_k),
		"radiator_capacity_j_k": float(data.radiator_capacity_j_k),
		"cold_coolant_capacity_j_k": float(data.cold_coolant_capacity_j_k),
		"plate_to_hot_conductance_w_k": float(data.plate_to_hot_conductance_w_k),
		"cold_to_radiator_conductance_w_k": float(data.cold_to_radiator_conductance_w_k),
		"radiator_to_ambient_conductance_w_k": float(data.radiator_to_ambient_conductance_w_k),
		"coolant_heat_capacity_j_kg_k": float(data.coolant_heat_capacity_j_kg_k),
		"coolant_density_kg_m3": float(data.coolant_density_kg_m3),
		"dynamic_viscosity_pa_s": float(data.dynamic_viscosity_pa_s),
		"laminar_reynolds_limit": float(data.laminar_reynolds_limit),
		"channel_flow_area_m2": float(data.channel_flow_area_m2),
		"channel_hydraulic_diameter_m": float(data.channel_hydraulic_diameter_m),
		"channel_flow_length_m": float(data.channel_flow_length_m),
		"max_total_mass_flow_kg_s": float(data.max_total_mass_flow_kg_s),
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
		return U.failure("UNSUPPORTED_COOLING_LOOP_DESCRIPTOR_SCHEMA")
	for field in ["graph_hash", "material_catalog_hash", "descriptor_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_COOLING_LOOP_DESCRIPTOR_HASH", {"field": field})
	checked = Interface.validate(value.interface_contract)
	if not checked.success:
		return checked
	for field in ["lane_count", "source_thermal_node_count", "source_operation_count", "compiled_operation_count"]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return U.failure("INVALID_COOLING_LOOP_DESCRIPTOR_INTEGER", {"field": field})
	if int(value.source_thermal_node_count) != int(value.lane_count) * 4:
		return U.failure("COOLING_LOOP_DESCRIPTOR_NODE_COUNT_MISMATCH")
	for field in [
		"plate_capacity_j_k", "hot_coolant_capacity_j_k", "radiator_capacity_j_k", "cold_coolant_capacity_j_k",
		"plate_to_hot_conductance_w_k", "cold_to_radiator_conductance_w_k", "radiator_to_ambient_conductance_w_k",
		"coolant_heat_capacity_j_kg_k", "coolant_density_kg_m3", "dynamic_viscosity_pa_s",
		"laminar_reynolds_limit", "channel_flow_area_m2", "channel_hydraulic_diameter_m", "channel_flow_length_m",
		"max_total_mass_flow_kg_s", "total_mass_kg", "min_temperature_k", "max_temperature_k"
	]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_COOLING_LOOP_DESCRIPTOR_SCALAR", {"field": field})
	if float(value.min_temperature_k) >= float(value.max_temperature_k):
		return U.failure("COOLING_LOOP_DESCRIPTOR_TEMPERATURE_DOMAIN_EMPTY")
	var expected_max_flow := float(value.laminar_reynolds_limit) * float(value.dynamic_viscosity_pa_s) * float(value.channel_flow_area_m2) / float(value.channel_hydraulic_diameter_m) * float(value.lane_count)
	var flow_scale := maxf(1.0e-18, maxf(absf(expected_max_flow), absf(float(value.max_total_mass_flow_kg_s))))
	if absf(expected_max_flow - float(value.max_total_mass_flow_kg_s)) > 1.0e-12 * flow_scale:
		return U.failure("COOLING_LOOP_DESCRIPTOR_MAX_FLOW_RELATION_MISMATCH")
	if int(value.source_operation_count) <= int(value.compiled_operation_count):
		return U.failure("INSUFFICIENT_COOLING_LOOP_COMPRESSION")
	if String(value.descriptor_hash) != U.canonical_hash(_identity(value)):
		return U.failure("COOLING_LOOP_DESCRIPTOR_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	return payload
