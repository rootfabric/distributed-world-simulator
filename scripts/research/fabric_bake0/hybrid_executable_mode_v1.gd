extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const ModeSignature = preload("res://scripts/research/fabric_bake0/hybrid_mode_signature_v1.gd")
const ModeDescriptor = preload("res://scripts/research/fabric_bake0/hybrid_bake_mode_descriptor_v1.gd")
const PhysicalArtifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_hybrid_executable_mode.v1"
const QUALIFICATION := "B0_5_A_EXECUTABLE"
const FIELDS: Array[String] = [
	"schema", "mode_id", "mode_hash", "mode_descriptor_checksum",
	"physical_artifact_checksum", "physical_bundle_hash",
	"rom_descriptor_hash", "runtime_certification_hash",
	"state_mapping_checksum", "reconstruction_descriptor_checksum",
	"build_generation", "execution_qualification", "mode_contract_hash", "checksum",
]

static func create(
	mode_id: String,
	mode_descriptor: Dictionary,
	physical_bundle: Dictionary,
	rom_descriptor_hash: String,
	runtime_certification_hash: String
) -> Dictionary:
	if typeof(physical_bundle.get("physical_artifact")) != TYPE_DICTIONARY:
		return {}
	var physical: Dictionary = physical_bundle["physical_artifact"]
	var value: Dictionary = {
		"schema": SCHEMA,
		"mode_id": mode_id,
		"mode_hash": String(mode_descriptor.get("mode_signature", {}).get("mode_hash", "")),
		"mode_descriptor_checksum": String(mode_descriptor.get("checksum", "")),
		"physical_artifact_checksum": String(physical.get("checksum", "")),
		"physical_bundle_hash": String(physical_bundle.get("bundle_hash", "")),
		"rom_descriptor_hash": rom_descriptor_hash,
		"runtime_certification_hash": runtime_certification_hash,
		"state_mapping_checksum": String(physical.get("state_mapping", {}).get("checksum", "")),
		"reconstruction_descriptor_checksum": String(physical.get("reconstruction_descriptor", {}).get("checksum", "")),
		"build_generation": int(physical.get("build_generation", 0)),
		"execution_qualification": QUALIFICATION,
		"mode_contract_hash": "",
		"checksum": "",
	}
	value["mode_contract_hash"] = Utils.canonical_hash(_identity_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value, mode_descriptor, physical_bundle).get("success", false)) else {}

static func validate(value: Dictionary, mode_descriptor: Dictionary, physical_bundle: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_HYBRID_EXECUTABLE_MODE_SCHEMA")
	if not Utils.is_canonical_id(value.get("mode_id"), 2):
		return Utils.failure("INVALID_HYBRID_EXECUTABLE_MODE_ID")
	checked = ModeDescriptor.validate(mode_descriptor)
	if not bool(checked.get("success", false)):
		return checked
	if String(mode_descriptor.get("execution_qualification", "")) != "B0_4_INTERFACE_BOUND":
		return Utils.failure("HYBRID_EXECUTABLE_MODE_REQUIRES_RESOLVED_B0_4")
	if typeof(physical_bundle.get("physical_artifact")) != TYPE_DICTIONARY:
		return Utils.failure("HYBRID_EXECUTABLE_MODE_REQUIRES_PHYSICAL_ARTIFACT")
	var physical: Dictionary = physical_bundle["physical_artifact"]
	checked = PhysicalArtifact.validate(physical)
	if not bool(checked.get("success", false)):
		return checked
	for field in [
		"mode_hash", "mode_descriptor_checksum", "physical_artifact_checksum",
		"physical_bundle_hash", "rom_descriptor_hash", "runtime_certification_hash",
		"state_mapping_checksum", "reconstruction_descriptor_checksum", "mode_contract_hash",
	]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_HYBRID_EXECUTABLE_MODE_HASH", {"field": field})
	if String(value["mode_hash"]) != String(mode_descriptor["mode_signature"]["mode_hash"]):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_HASH_MISMATCH")
	if String(value["mode_descriptor_checksum"]) != String(mode_descriptor["checksum"]):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_DESCRIPTOR_MISMATCH")
	if String(value["physical_artifact_checksum"]) != String(physical["checksum"]):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_ARTIFACT_MISMATCH")
	if String(value["physical_bundle_hash"]) != String(physical_bundle.get("bundle_hash", "")):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_BUNDLE_MISMATCH")
	if String(value["state_mapping_checksum"]) != String(physical["state_mapping"]["checksum"]):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_STATE_MAPPING_MISMATCH")
	if String(value["reconstruction_descriptor_checksum"]) != String(physical["reconstruction_descriptor"]["checksum"]):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_RECONSTRUCTION_MISMATCH")
	var binding: Dictionary = mode_descriptor["dynamic_rom_binding"]
	if String(binding["artifact_checksum"]) != String(physical["checksum"]):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_P0_ARTIFACT_BINDING_MISMATCH")
	if String(binding["reduced_state_schema_hash"]) != String(physical["reduced_state_schema_hash"]):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_P0_SCHEMA_BINDING_MISMATCH")
	if String(binding["state_mapping_checksum"]) != String(physical["state_mapping"]["checksum"]):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_P0_MAPPING_BINDING_MISMATCH")
	if String(binding["reconstruction_descriptor_checksum"]) != String(physical["reconstruction_descriptor"]["checksum"]):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_P0_RECONSTRUCTION_BINDING_MISMATCH")
	if not Utils.is_json_integer(value.get("build_generation")) or int(value["build_generation"]) < 1:
		return Utils.failure("INVALID_HYBRID_EXECUTABLE_MODE_GENERATION")
	if int(value["build_generation"]) != int(physical["build_generation"]):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_GENERATION_MISMATCH")
	if String(value.get("execution_qualification", "")) != QUALIFICATION:
		return Utils.failure("HYBRID_EXECUTABLE_MODE_NOT_AUTHORIZED")
	if String(value["mode_contract_hash"]) != Utils.canonical_hash(_identity_payload(value)):
		return Utils.failure("HYBRID_EXECUTABLE_MODE_CONTRACT_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func _identity_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("mode_contract_hash")
	payload.erase("checksum")
	return payload
