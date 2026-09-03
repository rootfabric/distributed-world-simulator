extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bridge2_entry_contract.v1"
const AUTHORIZATION := "EXECUTABLE_RESEARCH_AUTHORIZED"

const REPRESENTATIONS: Array[String] = [
	"FULL",
	"STRUCTURAL_BAKE",
	"CONTACT_BAKE",
	"DYNAMIC_ROM",
	"HYBRID_BAKE",
]

const CANONICAL_OWNER := "PHYSICAL_SOURCE"
const REPRESENTATION_ROLE := "DERIVED_EXECUTION_ONLY"
const PHYSICAL_EVENT_OWNER := "FABRIC_PHYSICAL_EVENT"
const CANONICAL_REVISION_POLICY := "EXTERNAL_AUTHORITY_ONLY"
const REGION_POLICY := "EXPLICIT_NON_OVERLAPPING_REGION_OWNERSHIP"
const INTERFACE_POLICY := "PHYSICAL_BOUNDARY_CONTRACT_EFFORT_FLOW_ONLY"
const INVALIDATION_POLICY := "CANONICAL_MUTATION_THEN_REPRESENTATION_INVALIDATION_THEN_BAKE_INVALIDATION"
const RECOVERY_POLICY := "REFINE_RECONSTRUCT_OR_FULL_NO_SAFE_BAKE"
const UNKNOWN_REPRESENTATION_POLICY := "FULL_OR_NO_SAFE_BAKE"

const FIELDS: Array[String] = [
	"schema", "authorization", "representations",
	"canonical_owner", "representation_role", "physical_event_owner",
	"canonical_revision_policy", "region_policy", "interface_policy",
	"invalidation_policy", "recovery_policy", "unknown_representation_policy",
	"required_predecessors", "first_falsifier", "fabric0_19_policy",
	"contract_hash", "checksum",
]

static func create() -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"authorization": AUTHORIZATION,
		"representations": REPRESENTATIONS.duplicate(),
		"canonical_owner": CANONICAL_OWNER,
		"representation_role": REPRESENTATION_ROLE,
		"physical_event_owner": PHYSICAL_EVENT_OWNER,
		"canonical_revision_policy": CANONICAL_REVISION_POLICY,
		"region_policy": REGION_POLICY,
		"interface_policy": INTERFACE_POLICY,
		"invalidation_policy": INVALIDATION_POLICY,
		"recovery_policy": RECOVERY_POLICY,
		"unknown_representation_policy": UNKNOWN_REPRESENTATION_POLICY,
		"required_predecessors": {
			"bridge1_structural": "CLOSED",
			"b0_3_contact_wrench": "CLOSED",
			"b0_4_dynamic_rom": "CLOSED",
			"b0_5_a_executable_hybrid": "CLOSED",
		},
		"first_falsifier": {
			"subject": "MIXED_GENERIC_MACHINE_R1",
			"required_region_kinds": REPRESENTATIONS.duplicate(),
			"same_canonical_frontier": true,
			"explicit_region_owner": true,
			"exactly_once_physical_event": true,
			"stale_execution_forbidden": true,
			"deterministic_mixed_replay": true,
			"full_reference_required": true,
		},
		"fabric0_19_policy": {
			"authorized": false,
			"reason": "NO_MISSING_GENERIC_PHYSICAL_CORE_PRIMITIVE_OBSERVED",
			"future_trigger": "CONCRETE_EXECUTABLE_FAILURE_NOT_EXPRESSIBLE_WITH_FABRIC0_18_FLOW_JUMP_TOPOLOGY_EVENT_SEMANTICS",
		},
		"contract_hash": "",
		"checksum": "",
	}
	value["contract_hash"] = Utils.canonical_hash(_identity_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BRIDGE2_ENTRY_CONTRACT_SCHEMA")
	if value.get("authorization") != AUTHORIZATION:
		return Utils.failure("BRIDGE2_ENTRY_NOT_EXECUTABLE_RESEARCH_AUTHORIZED")
	if value.get("representations") != REPRESENTATIONS:
		return Utils.failure("BRIDGE2_ENTRY_REPRESENTATION_SET_MISMATCH")
	if value.get("canonical_owner") != CANONICAL_OWNER:
		return Utils.failure("BRIDGE2_CANONICAL_OWNER_MISMATCH")
	if value.get("representation_role") != REPRESENTATION_ROLE:
		return Utils.failure("BRIDGE2_REPRESENTATION_ROLE_MISMATCH")
	if value.get("physical_event_owner") != PHYSICAL_EVENT_OWNER:
		return Utils.failure("BRIDGE2_EVENT_OWNER_MISMATCH")
	if value.get("canonical_revision_policy") != CANONICAL_REVISION_POLICY:
		return Utils.failure("BRIDGE2_CANONICAL_REVISION_POLICY_MISMATCH")
	if value.get("region_policy") != REGION_POLICY:
		return Utils.failure("BRIDGE2_REGION_POLICY_MISMATCH")
	if value.get("interface_policy") != INTERFACE_POLICY:
		return Utils.failure("BRIDGE2_INTERFACE_POLICY_MISMATCH")
	if value.get("invalidation_policy") != INVALIDATION_POLICY:
		return Utils.failure("BRIDGE2_INVALIDATION_POLICY_MISMATCH")
	if value.get("recovery_policy") != RECOVERY_POLICY:
		return Utils.failure("BRIDGE2_RECOVERY_POLICY_MISMATCH")
	if value.get("unknown_representation_policy") != UNKNOWN_REPRESENTATION_POLICY:
		return Utils.failure("BRIDGE2_UNKNOWN_REPRESENTATION_POLICY_MISMATCH")
	if typeof(value.get("required_predecessors")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BRIDGE2_PREDECESSOR_SET")
	for key in ["bridge1_structural", "b0_3_contact_wrench", "b0_4_dynamic_rom", "b0_5_a_executable_hybrid"]:
		if String(value["required_predecessors"].get(key, "")) != "CLOSED":
			return Utils.failure("BRIDGE2_PREDECESSOR_NOT_CLOSED", {"predecessor": key})
	if typeof(value.get("first_falsifier")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BRIDGE2_FIRST_FALSIFIER")
	var falsifier: Dictionary = value["first_falsifier"]
	if falsifier.get("required_region_kinds") != REPRESENTATIONS:
		return Utils.failure("BRIDGE2_FIRST_FALSIFIER_REPRESENTATION_SET_MISMATCH")
	for field in ["same_canonical_frontier", "explicit_region_owner", "exactly_once_physical_event", "stale_execution_forbidden", "deterministic_mixed_replay", "full_reference_required"]:
		if typeof(falsifier.get(field)) != TYPE_BOOL or not bool(falsifier[field]):
			return Utils.failure("BRIDGE2_FIRST_FALSIFIER_REQUIREMENT_MISSING", {"field": field})
	if typeof(value.get("fabric0_19_policy")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_FABRIC0_19_POLICY")
	if bool(value["fabric0_19_policy"].get("authorized", true)):
		return Utils.failure("FABRIC0_19_PREMATURELY_AUTHORIZED")
	if String(value["fabric0_19_policy"].get("reason", "")) != "NO_MISSING_GENERIC_PHYSICAL_CORE_PRIMITIVE_OBSERVED":
		return Utils.failure("FABRIC0_19_POLICY_REASON_MISMATCH")
	if not Utils.is_lower_hex_64(value.get("contract_hash")):
		return Utils.failure("INVALID_BRIDGE2_ENTRY_CONTRACT_HASH")
	if String(value["contract_hash"]) != Utils.canonical_hash(_identity_payload(value)):
		return Utils.failure("BRIDGE2_ENTRY_CONTRACT_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func permits_transition(from_kind: String, to_kind: String) -> Dictionary:
	if not REPRESENTATIONS.has(from_kind) or not REPRESENTATIONS.has(to_kind):
		return Utils.failure("UNKNOWN_BRIDGE2_REPRESENTATION_KIND")
	if from_kind == to_kind:
		return Utils.success({"permitted": true, "handoff_required": false})
	return Utils.success({
		"permitted": true,
		"handoff_required": true,
		"state_rule": "RECONSTRUCT_OR_EXACT_FULL_STATE_THEN_PROJECT",
		"event_rule": "FABRIC_OWNS_PHYSICAL_EVENT",
		"fallback": "FULL_OR_NO_SAFE_BAKE",
	})

static func _identity_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("contract_hash")
	payload.erase("checksum")
	return payload
