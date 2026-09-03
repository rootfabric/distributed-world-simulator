extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/dynamic_rom_descriptor_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_artifact_binding.v1"
const REQUIRED_BEFORE_EXECUTION: Array[String] = [
	"ERROR_ENVELOPE",
	"RECONSTRUCTION_DESCRIPTOR",
	"REFINEMENT_GUARD",
	"RUNTIME_ERROR_ESTIMATOR",
	"STATE_MAPPING",
	"VALIDATED_DOMAIN",
]
const FIELDS: Array[String] = [
	"schema", "reduction_class", "source_binding_checksum",
	"boundary_contract_hash", "reduced_model_descriptor_hash",
	"reduced_state_schema_hash", "execution_ready",
	"required_before_execution", "binding_hash", "checksum",
]

static func create(descriptor: Dictionary) -> Dictionary:
	var checked := Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return {}
	var value: Dictionary = {
		"schema": SCHEMA,
		"reduction_class": "APPROXIMATE",
		"source_binding_checksum": String(descriptor["source_binding_checksum"]),
		"boundary_contract_hash": String(descriptor["boundary_contract_hash"]),
		"reduced_model_descriptor_hash": String(descriptor["descriptor_hash"]),
		"reduced_state_schema_hash": String(descriptor["reduced_state_schema_hash"]),
		"execution_ready": false,
		"required_before_execution": REQUIRED_BEFORE_EXECUTION.duplicate(),
		"binding_hash": "",
		"checksum": "",
	}
	value["binding_hash"] = Utils.canonical_hash(_binding_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_ARTIFACT_BINDING_SCHEMA")
	if value.get("reduction_class") != "APPROXIMATE":
		return Utils.failure("INVALID_DYNAMIC_ROM_REDUCTION_CLASS")
	for field in [
		"source_binding_checksum", "boundary_contract_hash",
		"reduced_model_descriptor_hash", "reduced_state_schema_hash", "binding_hash",
	]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_DYNAMIC_ROM_ARTIFACT_BINDING_HASH", {"field": field})
	if value.get("execution_ready") != false:
		return Utils.failure("B0_4_B_ROM_EXECUTION_MUST_REMAIN_BLOCKED")
	if value.get("required_before_execution") != REQUIRED_BEFORE_EXECUTION:
		return Utils.failure("DYNAMIC_ROM_EXECUTION_REQUIREMENTS_MISMATCH")
	if String(value["binding_hash"]) != Utils.canonical_hash(_binding_payload(value)):
		return Utils.failure("DYNAMIC_ROM_ARTIFACT_BINDING_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func _binding_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("binding_hash")
	payload.erase("checksum")
	return payload
