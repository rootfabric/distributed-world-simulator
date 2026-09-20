extends RefCounted
## Generic derived behavior-capsule manifest.
## It never owns canonical state, identity, authority or mutation history.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_behavior_capsule.v1"
const FIELDS: Array[String] = [
	"schema", "capsule_id", "executable_kind", "reduction_class",
	"physical_bake_artifact_checksum", "source_binding_checksum",
	"source_frontier_hash", "fabric_graph_hash", "boundary_contract_hash",
	"executable_descriptor_hash", "reduced_state_schema_hash",
	"source_component_count", "full_equation_count", "executable_equation_count",
	"equation_compression_ratio", "component_to_executable_ratio",
	"runtime_source_traversals_per_execute", "build_generation",
	"capability_tags", "compile_provenance_hash", "checksum",
]

static func create(
	capsule_id: String,
	executable_kind: String,
	reduction_class: String,
	physical_bake_artifact_checksum: String,
	source_binding_checksum: String,
	source_frontier_hash: String,
	fabric_graph_hash: String,
	boundary_contract_hash: String,
	executable_descriptor_hash: String,
	reduced_state_schema_hash: String,
	source_component_count: int,
	full_equation_count: int,
	executable_equation_count: int,
	runtime_source_traversals_per_execute: int,
	build_generation: int,
	capability_tags: Array,
	compile_provenance_hash: String
) -> Dictionary:
	if executable_equation_count <= 0:
		return {}
	var tags := U.sorted_strings(capability_tags)
	var value := {
		"schema": SCHEMA,
		"capsule_id": capsule_id,
		"executable_kind": executable_kind,
		"reduction_class": reduction_class,
		"physical_bake_artifact_checksum": physical_bake_artifact_checksum,
		"source_binding_checksum": source_binding_checksum,
		"source_frontier_hash": source_frontier_hash,
		"fabric_graph_hash": fabric_graph_hash,
		"boundary_contract_hash": boundary_contract_hash,
		"executable_descriptor_hash": executable_descriptor_hash,
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"source_component_count": source_component_count,
		"full_equation_count": full_equation_count,
		"executable_equation_count": executable_equation_count,
		"equation_compression_ratio": float(full_equation_count) / float(executable_equation_count),
		"component_to_executable_ratio": float(source_component_count) / float(executable_equation_count),
		"runtime_source_traversals_per_execute": runtime_source_traversals_per_execute,
		"build_generation": build_generation,
		"capability_tags": tags,
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
		return U.failure("UNSUPPORTED_BEHAVIOR_CAPSULE_SCHEMA")
	if not U.is_canonical_id(value.get("capsule_id"), 2):
		return U.failure("INVALID_BEHAVIOR_CAPSULE_ID")
	for field in ["executable_kind", "reduction_class"]:
		if not U.is_upper_kind(value.get(field)):
			return U.failure("INVALID_BEHAVIOR_CAPSULE_KIND", {"field": field})
	for field in [
		"physical_bake_artifact_checksum", "source_binding_checksum",
		"source_frontier_hash", "fabric_graph_hash", "boundary_contract_hash",
		"executable_descriptor_hash", "reduced_state_schema_hash",
		"compile_provenance_hash"
	]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_BEHAVIOR_CAPSULE_HASH", {"field": field})
	for field in [
		"source_component_count", "full_equation_count", "executable_equation_count",
		"runtime_source_traversals_per_execute", "build_generation"
	]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return U.failure("INVALID_BEHAVIOR_CAPSULE_INTEGER", {"field": field})
	if int(value.source_component_count) < 1 or int(value.full_equation_count) < 1 or int(value.executable_equation_count) < 1:
		return U.failure("INVALID_BEHAVIOR_CAPSULE_COMPLEXITY")
	if int(value.executable_equation_count) >= int(value.full_equation_count):
		return U.failure("INSUFFICIENT_BEHAVIOR_CAPSULE_REDUCTION")
	if int(value.build_generation) < 1:
		return U.failure("INVALID_BEHAVIOR_CAPSULE_BUILD_GENERATION")
	for field in ["equation_compression_ratio", "component_to_executable_ratio"]:
		if not U.is_positive_number(value.get(field)) or float(value[field]) <= 1.0:
			return U.failure("INVALID_BEHAVIOR_CAPSULE_COMPRESSION", {"field": field})
	var expected_eq_ratio := float(value.full_equation_count) / float(value.executable_equation_count)
	var expected_component_ratio := float(value.source_component_count) / float(value.executable_equation_count)
	if absf(float(value.equation_compression_ratio) - expected_eq_ratio) > 1.0e-12:
		return U.failure("BEHAVIOR_CAPSULE_EQUATION_RATIO_MISMATCH")
	if absf(float(value.component_to_executable_ratio) - expected_component_ratio) > 1.0e-12:
		return U.failure("BEHAVIOR_CAPSULE_COMPONENT_RATIO_MISMATCH")
	checked = U.validate_sorted_unique_strings(value.get("capability_tags"), false, true)
	if not checked.success:
		return U.failure("INVALID_BEHAVIOR_CAPSULE_TAGS")
	return U.validate_checksum(value)
