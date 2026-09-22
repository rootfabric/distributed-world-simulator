extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/laser_cannon_interface_contract_v1.gd")

const SCHEMA := "planet_simulator.fabric_laser_cannon_descriptor.v1"
const FIELDS: Array[String] = [
	"schema","graph_hash","interface_contract",
	"power_stage_capsule_checksum","laser_emitter_capsule_checksum","cooling_capsule_checksum",
	"optics_surface_transmission_ratio","optics_total_transmission_ratio",
	"optical_expansion_ratio","clear_aperture_diameter_m","max_surface_fluence_j_m2",
	"source_component_count","source_operation_count","compiled_operation_count",
	"descriptor_hash","checksum",
]

static func create(data: Dictionary) -> Dictionary:
	var value := {
		"schema":SCHEMA,
		"graph_hash":String(data.graph_hash),
		"interface_contract":data.interface_contract.duplicate(true),
		"power_stage_capsule_checksum":String(data.power_stage_capsule_checksum),
		"laser_emitter_capsule_checksum":String(data.laser_emitter_capsule_checksum),
		"cooling_capsule_checksum":String(data.cooling_capsule_checksum),
		"optics_surface_transmission_ratio":float(data.optics_surface_transmission_ratio),
		"optics_total_transmission_ratio":float(data.optics_total_transmission_ratio),
		"optical_expansion_ratio":float(data.optical_expansion_ratio),
		"clear_aperture_diameter_m":float(data.clear_aperture_diameter_m),
		"max_surface_fluence_j_m2":float(data.max_surface_fluence_j_m2),
		"source_component_count":int(data.source_component_count),
		"source_operation_count":int(data.source_operation_count),
		"compiled_operation_count":int(data.compiled_operation_count),
		"descriptor_hash":"",
		"checksum":"",
	}
	value.descriptor_hash = U.canonical_hash(_identity(value))
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value,FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_LASER_CANNON_DESCRIPTOR_SCHEMA")
	if not U.is_lower_hex_64(value.get("graph_hash")) or not U.is_lower_hex_64(value.get("descriptor_hash")):
		return U.failure("INVALID_LASER_CANNON_DESCRIPTOR_HASH")
	for field in ["power_stage_capsule_checksum","laser_emitter_capsule_checksum","cooling_capsule_checksum"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_LASER_CANNON_SUBCAPSULE_CHECKSUM",{"field":field})
	checked = Interface.validate(value.interface_contract)
	if not checked.success:
		return checked
	for field in ["optics_surface_transmission_ratio","optics_total_transmission_ratio","optical_expansion_ratio","clear_aperture_diameter_m","max_surface_fluence_j_m2"]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_LASER_CANNON_DESCRIPTOR_SCALAR",{"field":field})
	if float(value.optics_surface_transmission_ratio) >= 1.0 or float(value.optics_total_transmission_ratio) >= 1.0:
		return U.failure("LASER_CANNON_TRANSMISSION_INVALID")
	var expected_total := pow(float(value.optics_surface_transmission_ratio),4.0)
	if absf(float(value.optics_total_transmission_ratio)-expected_total) > 1.0e-12*maxf(1.0e-18,expected_total):
		return U.failure("LASER_CANNON_DESCRIPTOR_TRANSMISSION_RELATION_MISMATCH")
	for field in ["source_component_count","source_operation_count","compiled_operation_count"]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return U.failure("INVALID_LASER_CANNON_DESCRIPTOR_INTEGER",{"field":field})
	if int(value.source_operation_count) <= int(value.compiled_operation_count):
		return U.failure("INSUFFICIENT_LASER_CANNON_COMPRESSION")
	if String(value.descriptor_hash) != U.canonical_hash(_identity(value)):
		return U.failure("LASER_CANNON_DESCRIPTOR_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	return payload
