extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const ExecutionArtifact = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_artifact_v1.gd")
const ExecutionRuntime = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_runtime_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_hybrid_interface.v1"
const INTERFACE_KIND := "DYNAMIC_ROM_EXECUTION_ARTIFACT_V1"
const CONTINUITY_POLICY := "LAST_ACCEPTED_ROM_STATE_ONLY"
const CANONICAL_STATE_OWNER := "PHYSICAL_SOURCE"
const ROM_STATE_ROLE := "DERIVED_HANDOFF_ONLY"

const FIELDS: Array[String] = [
	"schema", "interface_kind",
	"source_frontier_hash", "source_binding_checksum",
	"physical_topology_hash", "dependency_hash", "boundary_contract_hash",
	"execution_artifact_hash", "execution_artifact_checksum",
	"rom_descriptor_hash", "reduced_state_schema_hash",
	"reduction_binding_hash", "runtime_certification_hash",
	"build_generation", "lifecycle_version",
	"handoff_contract_hash", "interface_hash", "checksum",
]

static func create(artifact: Dictionary, full_model: Dictionary) -> Dictionary:
	var checked := ExecutionArtifact.validate(artifact)
	if not bool(checked.get("success", false)):
		return {}
	checked = FullModel.validate(full_model)
	if not bool(checked.get("success", false)):
		return {}
	if String(artifact["source_binding_checksum"]) != String(full_model["source_binding"]["checksum"]):
		return {}
	if String(artifact["full_model_hash"]) != String(full_model["model_hash"]):
		return {}
	if String(artifact["boundary_contract_hash"]) != String(full_model["boundary_contract"]["contract_hash"]):
		return {}

	var value: Dictionary = {
		"schema": SCHEMA,
		"interface_kind": INTERFACE_KIND,
		"source_frontier_hash": String(full_model["source_binding"]["frontier_hash"]),
		"source_binding_checksum": String(artifact["source_binding_checksum"]),
		"physical_topology_hash": String(full_model["source_binding"]["fabric_graph_hash"]),
		"dependency_hash": String(full_model["source_binding"]["dependency_hash"]),
		"boundary_contract_hash": String(artifact["boundary_contract_hash"]),
		"execution_artifact_hash": String(artifact["artifact_hash"]),
		"execution_artifact_checksum": String(artifact["checksum"]),
		"rom_descriptor_hash": String(artifact["rom_descriptor_hash"]),
		"reduced_state_schema_hash": String(artifact["reduced_state_schema_hash"]),
		"reduction_binding_hash": String(artifact["reduction_binding_hash"]),
		"runtime_certification_hash": String(artifact["runtime_certification_hash"]),
		"build_generation": int(artifact["build_generation"]),
		"lifecycle_version": String(artifact["lifecycle_version"]),
		"handoff_contract_hash": "",
		"interface_hash": "",
		"checksum": "",
	}
	value["handoff_contract_hash"] = _handoff_contract_hash(artifact)
	value["interface_hash"] = Utils.canonical_hash(_interface_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_HYBRID_INTERFACE_SCHEMA")
	if value.get("interface_kind") != INTERFACE_KIND:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_HYBRID_INTERFACE_KIND")
	for field in [
		"source_frontier_hash", "source_binding_checksum",
		"physical_topology_hash", "dependency_hash", "boundary_contract_hash",
		"execution_artifact_hash", "execution_artifact_checksum",
		"rom_descriptor_hash", "reduced_state_schema_hash",
		"reduction_binding_hash", "runtime_certification_hash",
		"handoff_contract_hash", "interface_hash",
	]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_DYNAMIC_ROM_HYBRID_INTERFACE_HASH", {"field": field})
	if not Utils.is_json_integer(value.get("build_generation")) or int(value["build_generation"]) < 1:
		return Utils.failure("INVALID_DYNAMIC_ROM_HYBRID_INTERFACE_GENERATION")
	if value.get("lifecycle_version") != ExecutionArtifact.LIFECYCLE_VERSION:
		return Utils.failure("DYNAMIC_ROM_HYBRID_LIFECYCLE_VERSION_MISMATCH")
	if String(value["interface_hash"]) != Utils.canonical_hash(_interface_payload(value)):
		return Utils.failure("DYNAMIC_ROM_HYBRID_INTERFACE_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func verify_against(value: Dictionary, artifact: Dictionary, full_model: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = ExecutionArtifact.validate(artifact)
	if not bool(checked.get("success", false)):
		return checked
	checked = FullModel.validate(full_model)
	if not bool(checked.get("success", false)):
		return checked
	var expected := create(artifact, full_model)
	if expected.is_empty():
		return Utils.failure("DYNAMIC_ROM_HYBRID_INTERFACE_REBUILD_FAILED")
	if value != expected:
		return Utils.failure("DYNAMIC_ROM_HYBRID_INTERFACE_BINDING_MISMATCH")
	return Utils.success({
		"interface_hash": value["interface_hash"],
		"handoff_contract_hash": value["handoff_contract_hash"],
	})

static func mode_identity_compatible(value: Dictionary, mode_signature: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(mode_signature) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_HYBRID_MODE_SIGNATURE")
	if String(mode_signature.get("source_frontier_hash", "")) != String(value["source_frontier_hash"]):
		return Utils.failure("DYNAMIC_ROM_HYBRID_MODE_FRONTIER_MISMATCH")
	if String(mode_signature.get("physical_topology_hash", "")) != String(value["physical_topology_hash"]):
		return Utils.failure("DYNAMIC_ROM_HYBRID_MODE_TOPOLOGY_MISMATCH")
	if String(mode_signature.get("boundary_contract_hash", "")) != String(value["boundary_contract_hash"]):
		return Utils.failure("DYNAMIC_ROM_HYBRID_MODE_BOUNDARY_MISMATCH")
	return Utils.success({"compatible": true})

static func _handoff_contract_hash(artifact: Dictionary) -> String:
	return Utils.canonical_hash({
		"contract_kind": "B0_4_D_FULL_HANDOFF_INTERFACE_R1",
		"execution_artifact_hash": artifact.get("artifact_hash", ""),
		"rom_descriptor_hash": artifact.get("rom_descriptor_hash", ""),
		"reduced_state_schema_hash": artifact.get("reduced_state_schema_hash", ""),
		"lifecycle_version": artifact.get("lifecycle_version", ""),
		"recovery_modes": artifact.get("recovery_modes", []),
		"continuity_policy": CONTINUITY_POLICY,
		"projection_c_norm_tolerance": ExecutionRuntime.HANDOFF_PROJECTION_C_NORM_TOLERANCE,
		"canonical_state_owner": CANONICAL_STATE_OWNER,
		"rom_state_role": ROM_STATE_ROLE,
	})

static func _interface_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("interface_hash")
	payload.erase("checksum")
	return payload
