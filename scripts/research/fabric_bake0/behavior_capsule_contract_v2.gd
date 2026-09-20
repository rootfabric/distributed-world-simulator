extends RefCounted
## Generic behavior capsule manifest for non-physical and physical executables.
## V1 remains frozen for T1 PhysicalBake. V2 points to an abstract derived executable artifact.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_behavior_capsule.v2"
const FIELDS: Array[String] = [
	"schema", "capsule_id", "executable_kind", "reduction_class",
	"canonical_source_frontier_hash", "source_graph_hash", "interface_contract_hash",
	"executable_artifact_kind", "executable_artifact_checksum", "executable_descriptor_hash",
	"state_schema_hash", "source_component_count", "full_operation_count",
	"executable_operation_count", "operation_compression_ratio", "component_to_executable_ratio",
	"runtime_source_traversals_per_execute", "build_generation", "capability_tags",
	"compile_provenance_hash", "checksum",
]

static func create(
	capsule_id: String,
	executable_kind: String,
	reduction_class: String,
	canonical_source_frontier_hash: String,
	source_graph_hash: String,
	interface_contract_hash: String,
	executable_artifact_kind: String,
	executable_artifact_checksum: String,
	executable_descriptor_hash: String,
	state_schema_hash: String,
	source_component_count: int,
	full_operation_count: int,
	executable_operation_count: int,
	runtime_source_traversals_per_execute: int,
	build_generation: int,
	capability_tags: Array,
	compile_provenance_hash: String
) -> Dictionary:
	if executable_operation_count <= 0:
		return {}
	var value := {
		"schema": SCHEMA,
		"capsule_id": capsule_id,
		"executable_kind": executable_kind,
		"reduction_class": reduction_class,
		"canonical_source_frontier_hash": canonical_source_frontier_hash,
		"source_graph_hash": source_graph_hash,
		"interface_contract_hash": interface_contract_hash,
		"executable_artifact_kind": executable_artifact_kind,
		"executable_artifact_checksum": executable_artifact_checksum,
		"executable_descriptor_hash": executable_descriptor_hash,
		"state_schema_hash": state_schema_hash,
		"source_component_count": source_component_count,
		"full_operation_count": full_operation_count,
		"executable_operation_count": executable_operation_count,
		"operation_compression_ratio": float(full_operation_count) / float(executable_operation_count),
		"component_to_executable_ratio": float(source_component_count) / float(executable_operation_count),
		"runtime_source_traversals_per_execute": runtime_source_traversals_per_execute,
		"build_generation": build_generation,
		"capability_tags": U.sorted_strings(capability_tags),
		"compile_provenance_hash": compile_provenance_hash,
		"checksum": "",
	}
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_BEHAVIOR_CAPSULE_V2_SCHEMA")
	if not U.is_canonical_id(value.get("capsule_id"), 2):
		return U.failure("INVALID_BEHAVIOR_CAPSULE_V2_ID")
	for field in ["executable_kind", "reduction_class", "executable_artifact_kind"]:
		if not U.is_upper_kind(value.get(field)):
			return U.failure("INVALID_BEHAVIOR_CAPSULE_V2_KIND", {"field": field})
	for field in [
		"canonical_source_frontier_hash", "source_graph_hash", "interface_contract_hash",
		"executable_artifact_checksum", "executable_descriptor_hash", "state_schema_hash",
		"compile_provenance_hash"
	]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_BEHAVIOR_CAPSULE_V2_HASH", {"field": field})
	for field in [
		"source_component_count", "full_operation_count", "executable_operation_count",
		"runtime_source_traversals_per_execute", "build_generation"
	]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return U.failure("INVALID_BEHAVIOR_CAPSULE_V2_INTEGER", {"field": field})
	if int(value.source_component_count) < 1 or int(value.full_operation_count) < 1 or int(value.executable_operation_count) < 1:
		return U.failure("INVALID_BEHAVIOR_CAPSULE_V2_COMPLEXITY")
	if int(value.executable_operation_count) >= int(value.full_operation_count):
		return U.failure("INSUFFICIENT_BEHAVIOR_CAPSULE_V2_REDUCTION")
	if int(value.build_generation) < 1:
		return U.failure("INVALID_BEHAVIOR_CAPSULE_V2_BUILD_GENERATION")
	var expected_operation_ratio := float(value.full_operation_count) / float(value.executable_operation_count)
	var expected_component_ratio := float(value.source_component_count) / float(value.executable_operation_count)
	if absf(float(value.operation_compression_ratio) - expected_operation_ratio) > 1.0e-12:
		return U.failure("BEHAVIOR_CAPSULE_V2_OPERATION_RATIO_MISMATCH")
	if absf(float(value.component_to_executable_ratio) - expected_component_ratio) > 1.0e-12:
		return U.failure("BEHAVIOR_CAPSULE_V2_COMPONENT_RATIO_MISMATCH")
	if float(value.operation_compression_ratio) <= 1.0 or float(value.component_to_executable_ratio) <= 1.0:
		return U.failure("INVALID_BEHAVIOR_CAPSULE_V2_COMPRESSION")
	checked = U.validate_sorted_unique_strings(value.get("capability_tags"), false, true)
	if not checked.success:
		return U.failure("INVALID_BEHAVIOR_CAPSULE_V2_TAGS")
	return U.validate_checksum(value)
