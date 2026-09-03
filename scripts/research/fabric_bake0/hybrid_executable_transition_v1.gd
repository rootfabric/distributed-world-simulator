extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const P0Transition = preload("res://scripts/research/fabric_bake0/hybrid_transition_descriptor_v1.gd")
const ExecutableMode = preload("res://scripts/research/fabric_bake0/hybrid_executable_mode_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_hybrid_executable_transition.v1"
const QUALIFICATION := "B0_5_A_EXECUTABLE"
const RESET_POLICY := "IDENTITY_FULL_HANDOFF_R1"
const FIELDS: Array[String] = [
	"schema", "p0_transition", "from_mode_contract_hash", "to_mode_contract_hash",
	"reset_policy", "execution_qualification", "transition_contract_hash", "checksum",
]

static func create(
	p0_transition: Dictionary,
	from_mode_contract: Dictionary,
	to_mode_contract: Dictionary
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"p0_transition": p0_transition.duplicate(true),
		"from_mode_contract_hash": String(from_mode_contract.get("mode_contract_hash", "")),
		"to_mode_contract_hash": String(to_mode_contract.get("mode_contract_hash", "")),
		"reset_policy": RESET_POLICY,
		"execution_qualification": QUALIFICATION,
		"transition_contract_hash": "",
		"checksum": "",
	}
	value["transition_contract_hash"] = Utils.canonical_hash(_identity_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value, from_mode_contract, to_mode_contract).get("success", false)) else {}

static func validate(
	value: Dictionary,
	from_mode_contract: Dictionary,
	to_mode_contract: Dictionary
) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_HYBRID_EXECUTABLE_TRANSITION_SCHEMA")
	if typeof(value.get("p0_transition")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_HYBRID_EXECUTABLE_P0_TRANSITION")
	checked = P0Transition.validate(value["p0_transition"])
	if not bool(checked.get("success", false)):
		return checked
	for field in ["from_mode_contract_hash", "to_mode_contract_hash", "transition_contract_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_HYBRID_EXECUTABLE_TRANSITION_HASH", {"field": field})
	if String(value["from_mode_contract_hash"]) != String(from_mode_contract.get("mode_contract_hash", "")):
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_FROM_MODE_MISMATCH")
	if String(value["to_mode_contract_hash"]) != String(to_mode_contract.get("mode_contract_hash", "")):
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_TO_MODE_MISMATCH")
	if String(value["p0_transition"]["from_mode_hash"]) != String(from_mode_contract.get("mode_hash", "")):
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_FROM_HASH_MISMATCH")
	if String(value["p0_transition"]["to_mode_hash"]) != String(to_mode_contract.get("mode_hash", "")):
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_TO_HASH_MISMATCH")
	var handoff: Dictionary = value["p0_transition"]["reset_handoff"]
	if String(handoff.get("interface_status", "")) != "B0_4_INTERFACE_BOUND":
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_REQUIRES_BOUND_HANDOFF")
	if String(handoff["from_state_mapping_checksum"]) != String(from_mode_contract.get("state_mapping_checksum", "")):
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_FROM_MAPPING_MISMATCH")
	if String(handoff["to_state_mapping_checksum"]) != String(to_mode_contract.get("state_mapping_checksum", "")):
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_TO_MAPPING_MISMATCH")
	if String(handoff["from_reconstruction_descriptor_checksum"]) != String(from_mode_contract.get("reconstruction_descriptor_checksum", "")):
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_FROM_RECONSTRUCTION_MISMATCH")
	if String(handoff["to_reconstruction_descriptor_checksum"]) != String(to_mode_contract.get("reconstruction_descriptor_checksum", "")):
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_TO_RECONSTRUCTION_MISMATCH")
	if String(value.get("reset_policy", "")) != RESET_POLICY:
		return Utils.failure("UNSUPPORTED_HYBRID_EXECUTABLE_RESET_POLICY")
	if String(value.get("execution_qualification", "")) != QUALIFICATION:
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_NOT_AUTHORIZED")
	if String(value["transition_contract_hash"]) != Utils.canonical_hash(_identity_payload(value)):
		return Utils.failure("HYBRID_EXECUTABLE_TRANSITION_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func _identity_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("transition_contract_hash")
	payload.erase("checksum")
	return payload
