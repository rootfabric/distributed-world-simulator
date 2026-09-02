extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/dynamic_rom_descriptor_v1.gd")
const ReductionBinding = preload("res://scripts/research/fabric_bake0/dynamic_rom_artifact_binding_v1.gd")
const Certification = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_certification_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_execution_artifact.v1"
const LIFECYCLE_VERSION := "FABRIC-BAKE/B0.4-D/R1"
const RECOVERY_MODES: Array[String] = ["FULL_FALLBACK", "LOCAL_UNBAKE", "REBUILD"]
const CERTIFIED_COMPONENTS: Array[String] = [
	"ERROR_ENVELOPE",
	"EXECUTION_GATE",
	"RECONSTRUCTION_DESCRIPTOR",
	"RECOVERY_POLICY",
	"REFINEMENT_GUARD",
	"RUNTIME_CERTIFICATION",
	"RUNTIME_ERROR_ESTIMATOR",
	"SOURCE_BINDING_MONITOR",
	"STATE_MAPPING",
	"VALIDATED_DOMAIN",
]
const FIELDS: Array[String] = [
	"schema", "artifact_id", "lifecycle_version", "build_generation",
	"source_binding_checksum", "boundary_contract_hash", "full_model_hash",
	"rom_descriptor_hash", "reduced_state_schema_hash", "reduction_binding_hash",
	"runtime_certification_hash", "certified_components", "recovery_modes",
	"execution_ready", "artifact_hash", "checksum",
]

static func create(
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary,
	artifact_id: String = "artifact/dynamic-rom-b0-4-d-r1",
	build_generation: int = 1
) -> Dictionary:
	var checked := FullModel.validate(full_model)
	if not bool(checked.get("success", false)):
		return {}
	checked = Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return {}
	checked = ReductionBinding.validate(reduction_binding)
	if not bool(checked.get("success", false)):
		return {}
	checked = Certification.validate(certification)
	if not bool(checked.get("success", false)):
		return {}
	if not Utils.is_canonical_id(artifact_id, 2) or build_generation < 1:
		return {}
	if not bool(_bindings_match(full_model, descriptor, reduction_binding, certification).get("success", false)):
		return {}
	var value: Dictionary = {
		"schema": SCHEMA,
		"artifact_id": artifact_id,
		"lifecycle_version": LIFECYCLE_VERSION,
		"build_generation": build_generation,
		"source_binding_checksum": String(descriptor["source_binding_checksum"]),
		"boundary_contract_hash": String(descriptor["boundary_contract_hash"]),
		"full_model_hash": String(descriptor["full_model_hash"]),
		"rom_descriptor_hash": String(descriptor["descriptor_hash"]),
		"reduced_state_schema_hash": String(descriptor["reduced_state_schema_hash"]),
		"reduction_binding_hash": String(reduction_binding["binding_hash"]),
		"runtime_certification_hash": String(certification["certification_hash"]),
		"certified_components": CERTIFIED_COMPONENTS.duplicate(),
		"recovery_modes": RECOVERY_MODES.duplicate(),
		"execution_ready": true,
		"artifact_hash": "",
		"checksum": "",
	}
	value["artifact_hash"] = Utils.canonical_hash(_artifact_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_EXECUTION_ARTIFACT_SCHEMA")
	if not Utils.is_canonical_id(value.get("artifact_id"), 2):
		return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_ARTIFACT_ID")
	if value.get("lifecycle_version") != LIFECYCLE_VERSION:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_EXECUTION_LIFECYCLE_VERSION")
	if not Utils.is_json_integer(value.get("build_generation")) or int(value["build_generation"]) < 1:
		return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_BUILD_GENERATION")
	for field in [
		"source_binding_checksum", "boundary_contract_hash", "full_model_hash",
		"rom_descriptor_hash", "reduced_state_schema_hash", "reduction_binding_hash",
		"runtime_certification_hash", "artifact_hash",
	]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_ARTIFACT_HASH", {"field": field})
	if value.get("certified_components") != CERTIFIED_COMPONENTS:
		return Utils.failure("DYNAMIC_ROM_EXECUTION_CERTIFIED_COMPONENTS_MISMATCH")
	if value.get("recovery_modes") != RECOVERY_MODES:
		return Utils.failure("DYNAMIC_ROM_EXECUTION_RECOVERY_MODES_MISMATCH")
	if value.get("execution_ready") != true:
		return Utils.failure("DYNAMIC_ROM_EXECUTION_ARTIFACT_NOT_READY")
	if String(value["artifact_hash"]) != Utils.canonical_hash(_artifact_payload(value)):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_ARTIFACT_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func verify_bindings(
	artifact: Dictionary,
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary
) -> Dictionary:
	var checked := validate(artifact)
	if not bool(checked.get("success", false)):
		return checked
	checked = FullModel.validate(full_model)
	if not bool(checked.get("success", false)):
		return checked
	checked = Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = ReductionBinding.validate(reduction_binding)
	if not bool(checked.get("success", false)):
		return checked
	checked = Certification.validate(certification)
	if not bool(checked.get("success", false)):
		return checked
	checked = _bindings_match(full_model, descriptor, reduction_binding, certification)
	if not bool(checked.get("success", false)):
		return checked
	var expected := {
		"source_binding_checksum": String(descriptor["source_binding_checksum"]),
		"boundary_contract_hash": String(descriptor["boundary_contract_hash"]),
		"full_model_hash": String(descriptor["full_model_hash"]),
		"rom_descriptor_hash": String(descriptor["descriptor_hash"]),
		"reduced_state_schema_hash": String(descriptor["reduced_state_schema_hash"]),
		"reduction_binding_hash": String(reduction_binding["binding_hash"]),
		"runtime_certification_hash": String(certification["certification_hash"]),
	}
	for field in expected.keys():
		if String(artifact[field]) != String(expected[field]):
			return Utils.failure("DYNAMIC_ROM_EXECUTION_ARTIFACT_BINDING_MISMATCH", {"field": field})
	return Utils.success({"artifact_hash": artifact["artifact_hash"], "execution_ready": true})

static func _bindings_match(
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary
) -> Dictionary:
	if String(descriptor["full_model_hash"]) != String(full_model["model_hash"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_FULL_MODEL_MISMATCH")
	if String(descriptor["source_binding_checksum"]) != String(full_model["source_binding"]["checksum"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_SOURCE_BINDING_MISMATCH")
	if String(descriptor["boundary_contract_hash"]) != String(full_model["boundary_contract"]["contract_hash"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_BOUNDARY_MISMATCH")
	if String(reduction_binding["source_binding_checksum"]) != String(descriptor["source_binding_checksum"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_REDUCTION_SOURCE_MISMATCH")
	if String(reduction_binding["boundary_contract_hash"]) != String(descriptor["boundary_contract_hash"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_REDUCTION_BOUNDARY_MISMATCH")
	if String(reduction_binding["reduced_model_descriptor_hash"]) != String(descriptor["descriptor_hash"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_REDUCTION_DESCRIPTOR_MISMATCH")
	if String(reduction_binding["reduced_state_schema_hash"]) != String(descriptor["reduced_state_schema_hash"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_REDUCTION_SCHEMA_MISMATCH")
	if String(certification["rom_descriptor_hash"]) != String(descriptor["descriptor_hash"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_CERTIFICATION_ROM_MISMATCH")
	if String(certification["full_model_hash"]) != String(full_model["model_hash"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_CERTIFICATION_FULL_MISMATCH")
	if String(certification["source_binding_checksum"]) != String(descriptor["source_binding_checksum"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_CERTIFICATION_SOURCE_MISMATCH")
	return Utils.success()

static func _artifact_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("artifact_hash")
	payload.erase("checksum")
	return payload
