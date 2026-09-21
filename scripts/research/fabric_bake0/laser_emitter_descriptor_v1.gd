extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/laser_emitter_interface_contract_v1.gd")

const SCHEMA := "planet_simulator.fabric_laser_emitter_descriptor.v1"
const FIELDS: Array[String] = [
	"schema", "graph_hash", "material_catalog_hash", "interface_contract",
	"source_cell_count", "active_cell_count", "profile_id",
	"per_cell_resistance_ref_ohm", "per_cell_threshold_current_a", "per_cell_max_current_a",
	"per_cell_aperture_area_m2", "forward_voltage_v",
	"reference_optical_efficiency_ratio", "efficiency_temp_coefficient_per_k",
	"reference_temperature_k", "min_temperature_k", "max_temperature_k",
	"wavelength_m", "beam_quality_m2", "effective_aperture_area_m2",
	"beam_divergence_half_angle_rad", "total_threshold_current_a", "total_max_current_a",
	"total_physical_mass_kg", "source_operation_count", "compiled_operation_count",
	"descriptor_hash", "checksum",
]

static func create(data: Dictionary) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_hash": String(data.graph_hash),
		"material_catalog_hash": String(data.material_catalog_hash),
		"interface_contract": data.interface_contract.duplicate(true),
		"source_cell_count": int(data.source_cell_count),
		"active_cell_count": int(data.active_cell_count),
		"profile_id": String(data.profile_id),
		"per_cell_resistance_ref_ohm": float(data.per_cell_resistance_ref_ohm),
		"per_cell_threshold_current_a": float(data.per_cell_threshold_current_a),
		"per_cell_max_current_a": float(data.per_cell_max_current_a),
		"per_cell_aperture_area_m2": float(data.per_cell_aperture_area_m2),
		"forward_voltage_v": float(data.forward_voltage_v),
		"reference_optical_efficiency_ratio": float(data.reference_optical_efficiency_ratio),
		"efficiency_temp_coefficient_per_k": float(data.efficiency_temp_coefficient_per_k),
		"reference_temperature_k": float(data.reference_temperature_k),
		"min_temperature_k": float(data.min_temperature_k),
		"max_temperature_k": float(data.max_temperature_k),
		"wavelength_m": float(data.wavelength_m),
		"beam_quality_m2": float(data.beam_quality_m2),
		"effective_aperture_area_m2": float(data.effective_aperture_area_m2),
		"beam_divergence_half_angle_rad": float(data.beam_divergence_half_angle_rad),
		"total_threshold_current_a": float(data.total_threshold_current_a),
		"total_max_current_a": float(data.total_max_current_a),
		"total_physical_mass_kg": float(data.total_physical_mass_kg),
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
		return U.failure("UNSUPPORTED_LASER_EMITTER_DESCRIPTOR_SCHEMA")
	for field in ["graph_hash", "material_catalog_hash", "descriptor_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_LASER_EMITTER_DESCRIPTOR_HASH", {"field": field})
	checked = Interface.validate(value.interface_contract)
	if not checked.success:
		return checked
	for field in ["source_cell_count", "active_cell_count", "source_operation_count", "compiled_operation_count"]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return U.failure("INVALID_LASER_EMITTER_DESCRIPTOR_INTEGER", {"field": field})
	if int(value.active_cell_count) > int(value.source_cell_count):
		return U.failure("LASER_EMITTER_ACTIVE_CELL_COUNT_INVALID")
	if not U.is_canonical_id(value.get("profile_id"), 2):
		return U.failure("INVALID_LASER_EMITTER_DESCRIPTOR_PROFILE_ID")
	for field in [
		"per_cell_resistance_ref_ohm", "per_cell_threshold_current_a", "per_cell_max_current_a",
		"per_cell_aperture_area_m2", "forward_voltage_v", "reference_optical_efficiency_ratio",
		"reference_temperature_k", "min_temperature_k", "max_temperature_k",
		"wavelength_m", "beam_quality_m2", "effective_aperture_area_m2",
		"beam_divergence_half_angle_rad", "total_threshold_current_a", "total_max_current_a",
		"total_physical_mass_kg"
	]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_LASER_EMITTER_DESCRIPTOR_SCALAR", {"field": field})
	if not U.is_non_negative_number(value.get("efficiency_temp_coefficient_per_k")):
		return U.failure("INVALID_LASER_EMITTER_DESCRIPTOR_TEMP_COEFFICIENT")
	if float(value.reference_optical_efficiency_ratio) >= 1.0:
		return U.failure("LASER_EMITTER_DESCRIPTOR_EFFICIENCY_INVALID")
	if float(value.min_temperature_k) >= float(value.reference_temperature_k) or float(value.reference_temperature_k) >= float(value.max_temperature_k):
		return U.failure("LASER_EMITTER_DESCRIPTOR_TEMPERATURE_ORDER_INVALID")
	if float(value.beam_quality_m2) < 1.0:
		return U.failure("LASER_EMITTER_DESCRIPTOR_BEAM_QUALITY_INVALID")
	var n := float(value.active_cell_count)
	var expected_threshold := n * float(value.per_cell_threshold_current_a)
	var expected_max := n * float(value.per_cell_max_current_a)
	var expected_aperture := n * float(value.per_cell_aperture_area_m2)
	var waist_radius := sqrt(expected_aperture / PI)
	var expected_divergence := float(value.beam_quality_m2) * float(value.wavelength_m) / (PI * waist_radius)
	for relation in [
		["total_threshold_current_a", float(value.total_threshold_current_a), expected_threshold],
		["total_max_current_a", float(value.total_max_current_a), expected_max],
		["effective_aperture_area_m2", float(value.effective_aperture_area_m2), expected_aperture],
		["beam_divergence_half_angle_rad", float(value.beam_divergence_half_angle_rad), expected_divergence],
	]:
		var actual := float(relation[1])
		var expected := float(relation[2])
		var scale := maxf(1.0e-18, maxf(absf(actual), absf(expected)))
		if absf(actual - expected) > 1.0e-12 * scale:
			return U.failure("LASER_EMITTER_DESCRIPTOR_RELATION_MISMATCH", {"field": String(relation[0]), "actual": actual, "expected": expected})
	if float(value.total_max_current_a) <= float(value.total_threshold_current_a):
		return U.failure("LASER_EMITTER_DESCRIPTOR_CURRENT_WINDOW_EMPTY")
	if int(value.source_operation_count) <= int(value.compiled_operation_count):
		return U.failure("INSUFFICIENT_LASER_EMITTER_COMPRESSION")
	if String(value.descriptor_hash) != U.canonical_hash(_identity(value)):
		return U.failure("LASER_EMITTER_DESCRIPTOR_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	return payload
