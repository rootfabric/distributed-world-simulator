extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_hybrid_transition_descriptor.v1"
const GUARD_FIELDS: Array[String] = [
	"guard_id", "kind", "direction", "observed_quantity_id", "dimension",
	"nominal", "threshold", "mapped_source_region",
]
const HANDOFF_FIELDS: Array[String] = [
	"contract_kind", "interface_status",
	"from_state_mapping_checksum", "to_state_mapping_checksum",
	"from_reconstruction_descriptor_checksum", "to_reconstruction_descriptor_checksum",
	"conservation_envelope_checksum",
]
const OWNERSHIP_FIELDS: Array[String] = [
	"owner", "semantics", "canonical_revision_policy",
	"event_commit_policy", "replay_policy",
]
const FIELDS: Array[String] = [
	"schema", "transition_id", "source_frontier_hash",
	"from_mode_hash", "to_mode_hash", "guard", "reset_handoff",
	"topology_transaction_kind", "event_ownership", "priority",
	"execution_qualification", "transition_hash", "checksum",
]
const GUARD_KINDS: Array[String] = ["CROSSING", "CONDITION"]
const TOPOLOGY_KINDS: Array[String] = ["NONE", "FABRIC_TOPOLOGY_TRANSACTION"]
const INTERFACE_STATUSES: Array[String] = ["UNRESOLVED_B0_4_INTERFACE", "B0_4_INTERFACE_BOUND"]

static func unresolved_handoff(conservation_envelope_checksum: String) -> Dictionary:
	return {
		"contract_kind": "B0_4_STATE_HANDOFF_INTERFACE",
		"interface_status": "UNRESOLVED_B0_4_INTERFACE",
		"from_state_mapping_checksum": "",
		"to_state_mapping_checksum": "",
		"from_reconstruction_descriptor_checksum": "",
		"to_reconstruction_descriptor_checksum": "",
		"conservation_envelope_checksum": conservation_envelope_checksum,
	}

static func exactly_once_event_ownership() -> Dictionary:
	return {
		"owner": "FABRIC_PHYSICAL_EVENT",
		"semantics": "EXACTLY_ONCE",
		"canonical_revision_policy": "EXTERNAL_AUTHORITY_ONLY",
		"event_commit_policy": "OWNER_COMMITS_ONCE",
		"replay_policy": "REJECT_DUPLICATE_EVENT_ID",
	}

static func create(
	transition_id: String,
	source_frontier_hash: String,
	from_mode_hash: String,
	to_mode_hash: String,
	guard: Dictionary,
	reset_handoff: Dictionary,
	topology_transaction_kind: String,
	event_ownership: Dictionary,
	priority: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"transition_id": transition_id,
		"source_frontier_hash": source_frontier_hash,
		"from_mode_hash": from_mode_hash,
		"to_mode_hash": to_mode_hash,
		"guard": guard.duplicate(true),
		"reset_handoff": reset_handoff.duplicate(true),
		"topology_transaction_kind": topology_transaction_kind,
		"event_ownership": event_ownership.duplicate(true),
		"priority": priority,
		"execution_qualification": "PREFLIGHT_ONLY",
		"transition_hash": "",
		"checksum": "",
	}
	value["transition_hash"] = identity_hash(value)
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_HYBRID_TRANSITION_SCHEMA")
	if not Utils.is_canonical_id(value.get("transition_id"), 2):
		return Utils.failure("INVALID_HYBRID_TRANSITION_ID")
	for field in ["source_frontier_hash", "from_mode_hash", "to_mode_hash", "transition_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_HYBRID_TRANSITION_HASH", {"field": field})
	if String(value["from_mode_hash"]) == String(value["to_mode_hash"]):
		return Utils.failure("HYBRID_TRANSITION_REQUIRES_DISTINCT_MODES")
	if typeof(value.get("guard")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_HYBRID_TRANSITION_GUARD")
	checked = Utils.validate_exact_fields(value["guard"], GUARD_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	var guard: Dictionary = value["guard"]
	if not Utils.is_canonical_id(guard.get("guard_id"), 2):
		return Utils.failure("INVALID_HYBRID_TRANSITION_GUARD_ID")
	if not GUARD_KINDS.has(String(guard.get("kind", ""))):
		return Utils.failure("INVALID_HYBRID_TRANSITION_GUARD_KIND")
	if not Utils.is_json_integer(guard.get("direction")) or int(guard["direction"]) < -1 or int(guard["direction"]) > 1:
		return Utils.failure("INVALID_HYBRID_TRANSITION_GUARD_DIRECTION")
	if not Utils.is_canonical_id(guard.get("observed_quantity_id"), 2):
		return Utils.failure("INVALID_HYBRID_TRANSITION_GUARD_QUANTITY")
	checked = Utils.validate_dimension(guard.get("dimension"))
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_positive_number(guard.get("nominal")) or not Utils.is_finite_number(guard.get("threshold")):
		return Utils.failure("INVALID_HYBRID_TRANSITION_GUARD_SCALE")
	if not Utils.is_canonical_id(guard.get("mapped_source_region"), 2):
		return Utils.failure("INVALID_HYBRID_TRANSITION_GUARD_REGION")
	if typeof(value.get("reset_handoff")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_HYBRID_TRANSITION_HANDOFF")
	checked = Utils.validate_exact_fields(value["reset_handoff"], HANDOFF_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	var handoff: Dictionary = value["reset_handoff"]
	if String(handoff.get("contract_kind", "")) != "B0_4_STATE_HANDOFF_INTERFACE":
		return Utils.failure("HYBRID_TRANSITION_REQUIRES_B0_4_HANDOFF_INTERFACE")
	var interface_status := String(handoff.get("interface_status", ""))
	if not INTERFACE_STATUSES.has(interface_status):
		return Utils.failure("INVALID_HYBRID_TRANSITION_HANDOFF_STATUS")
	if not Utils.is_lower_hex_64(handoff.get("conservation_envelope_checksum")):
		return Utils.failure("INVALID_HYBRID_TRANSITION_CONSERVATION_REFERENCE")
	for field in ["from_state_mapping_checksum", "to_state_mapping_checksum", "from_reconstruction_descriptor_checksum", "to_reconstruction_descriptor_checksum"]:
		if interface_status == "UNRESOLVED_B0_4_INTERFACE":
			if String(handoff.get(field, "")) != "":
				return Utils.failure("UNRESOLVED_B0_4_HANDOFF_MUST_NOT_CLAIM_RUNTIME_HASH", {"field": field})
		else:
			if not Utils.is_lower_hex_64(handoff.get(field)):
				return Utils.failure("INVALID_HYBRID_TRANSITION_HANDOFF_HASH", {"field": field})
	if not TOPOLOGY_KINDS.has(String(value.get("topology_transaction_kind", ""))):
		return Utils.failure("INVALID_HYBRID_TOPOLOGY_TRANSACTION_KIND")
	if typeof(value.get("event_ownership")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_HYBRID_EVENT_OWNERSHIP")
	checked = Utils.validate_exact_fields(value["event_ownership"], OWNERSHIP_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	var ownership: Dictionary = value["event_ownership"]
	if String(ownership.get("owner", "")) != "FABRIC_PHYSICAL_EVENT":
		return Utils.failure("HYBRID_EVENT_OWNER_MUST_BE_PHYSICAL")
	if String(ownership.get("semantics", "")) != "EXACTLY_ONCE":
		return Utils.failure("HYBRID_EVENT_MUST_BE_EXACTLY_ONCE")
	if String(ownership.get("canonical_revision_policy", "")) != "EXTERNAL_AUTHORITY_ONLY":
		return Utils.failure("HYBRID_RESET_MUST_NOT_ADVANCE_CANONICAL_REVISION")
	if String(ownership.get("event_commit_policy", "")) != "OWNER_COMMITS_ONCE":
		return Utils.failure("INVALID_HYBRID_EVENT_COMMIT_POLICY")
	if String(ownership.get("replay_policy", "")) != "REJECT_DUPLICATE_EVENT_ID":
		return Utils.failure("INVALID_HYBRID_EVENT_REPLAY_POLICY")
	if not Utils.is_json_integer(value.get("priority")) or int(value["priority"]) < 0:
		return Utils.failure("INVALID_HYBRID_TRANSITION_PRIORITY")
	if String(value.get("execution_qualification", "")) != "PREFLIGHT_ONLY":
		return Utils.failure("B0_5_P0_TRANSITION_EXECUTION_FORBIDDEN")
	if String(value["transition_hash"]) != identity_hash(value):
		return Utils.failure("HYBRID_TRANSITION_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func identity_hash(value: Dictionary) -> String:
	return Utils.canonical_hash({
		"transition_id": value.get("transition_id", ""),
		"source_frontier_hash": value.get("source_frontier_hash", ""),
		"from_mode_hash": value.get("from_mode_hash", ""),
		"to_mode_hash": value.get("to_mode_hash", ""),
		"guard": value.get("guard", {}),
		"reset_handoff": value.get("reset_handoff", {}),
		"topology_transaction_kind": value.get("topology_transaction_kind", ""),
		"event_ownership": value.get("event_ownership", {}),
		"priority": value.get("priority", -1),
	})
