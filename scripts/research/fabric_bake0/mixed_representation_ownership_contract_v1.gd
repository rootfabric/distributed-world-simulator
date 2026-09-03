extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_mixed_representation_ownership.v1"
const RESOLUTION_SCHEMA := "planet_simulator.fabric_bake_mixed_event_ownership_resolution.v1"
const QUALIFICATION := "BRIDGE_2_A_RESEARCH_CONTRACT"
const CANONICAL_TRUTH_OWNER := "CONSTRUCTION_MATTER"
const SOURCE_REVISION_POLICY := "EXTERNAL_CANONICAL_AUTHORITY_ONLY"
const EVENT_COMMIT_POLICY := "EXACTLY_ONCE"
const DERIVED_EVENT_COMMIT_OWNER := "FABRIC_PHYSICAL_EVENT"

const REPRESENTATION_KINDS: Array[String] = [
	"CONTACT_BAKE",
	"DYNAMIC_ROM",
	"FULL",
	"HYBRID_BAKE",
	"STRUCTURAL_BAKE",
]
const OWNERSHIP_ROLES: Array[String] = ["ACTIVE_EXECUTION", "OBSERVER"]
const CANONICAL_EFFECTS: Array[String] = ["CANONICAL_MUTATION", "DERIVED_PHYSICAL_EVENT"]

const FIELDS: Array[String] = [
	"schema",
	"canonical_source_frontier",
	"authority_envelope",
	"canonical_truth_owner",
	"source_revision_policy",
	"event_commit_policy",
	"representations",
	"region_bindings",
	"execution_qualification",
	"contract_hash",
	"checksum",
]
const REPRESENTATION_FIELDS: Array[String] = [
	"representation_id",
	"representation_kind",
	"derived_only",
	"canonical_write_authorized",
	"source_frontier_hash",
	"authority_epoch_binding",
]
const REGION_BINDING_FIELDS: Array[String] = [
	"region_id",
	"representation_id",
	"ownership_role",
]
const EVENT_FIELDS: Array[String] = [
	"event_id",
	"region_id",
	"event_kind",
	"canonical_effect",
	"candidate_representation_ids",
]
const RESOLUTION_FIELDS: Array[String] = [
	"schema",
	"event_id",
	"region_id",
	"event_kind",
	"canonical_effect",
	"evaluator_representation_id",
	"evaluator_representation_kind",
	"observer_representation_ids",
	"commit_owner",
	"canonical_revision_policy",
	"event_commit_policy",
	"evaluator_canonical_write_authorized",
	"source_frontier_hash",
	"authority_epoch_binding",
	"contract_hash",
	"resolution_hash",
	"checksum",
]

static func compile(
	canonical_source_frontier: Dictionary,
	authority_envelope: Dictionary,
	representations: Array,
	region_bindings: Array
) -> Dictionary:
	var checked := Frontier.validate(canonical_source_frontier)
	if not bool(checked.get("success", false)):
		return checked
	checked = AuthorityEnvelope.validate_b0_safety(authority_envelope)
	if not bool(checked.get("success", false)):
		return checked

	var normalized_representations: Array = []
	for raw in representations:
		normalized_representations.append(raw.duplicate(true) if typeof(raw) == TYPE_DICTIONARY else raw)
	normalized_representations.sort_custom(func(a, b): return String(a.get("representation_id", "")) < String(b.get("representation_id", "")))

	var normalized_bindings: Array = []
	for raw in region_bindings:
		normalized_bindings.append(raw.duplicate(true) if typeof(raw) == TYPE_DICTIONARY else raw)
	normalized_bindings.sort_custom(func(a, b): return _binding_key(a) < _binding_key(b))

	var value: Dictionary = {
		"schema": SCHEMA,
		"canonical_source_frontier": canonical_source_frontier.duplicate(true),
		"authority_envelope": authority_envelope.duplicate(true),
		"canonical_truth_owner": CANONICAL_TRUTH_OWNER,
		"source_revision_policy": SOURCE_REVISION_POLICY,
		"event_commit_policy": EVENT_COMMIT_POLICY,
		"representations": normalized_representations,
		"region_bindings": normalized_bindings,
		"execution_qualification": QUALIFICATION,
		"contract_hash": "",
		"checksum": "",
	}
	value["contract_hash"] = Utils.canonical_hash(_contract_identity(value))
	value["checksum"] = Utils.compute_checksum(value)
	checked = validate(value)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"contract": value})

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BRIDGE2_A_OWNERSHIP_SCHEMA")
	checked = Frontier.validate(value["canonical_source_frontier"] if typeof(value.get("canonical_source_frontier")) == TYPE_DICTIONARY else {})
	if not bool(checked.get("success", false)):
		return checked
	checked = AuthorityEnvelope.validate_b0_safety(value["authority_envelope"] if typeof(value.get("authority_envelope")) == TYPE_DICTIONARY else {})
	if not bool(checked.get("success", false)):
		return checked
	if String(value.get("canonical_truth_owner", "")) != CANONICAL_TRUTH_OWNER:
		return Utils.failure("BRIDGE2_A_CANONICAL_TRUTH_OWNER_MISMATCH")
	if String(value.get("source_revision_policy", "")) != SOURCE_REVISION_POLICY:
		return Utils.failure("BRIDGE2_A_SOURCE_REVISION_POLICY_MISMATCH")
	if String(value.get("event_commit_policy", "")) != EVENT_COMMIT_POLICY:
		return Utils.failure("BRIDGE2_A_EVENT_COMMIT_POLICY_MISMATCH")
	if String(value.get("execution_qualification", "")) != QUALIFICATION:
		return Utils.failure("BRIDGE2_A_EXECUTION_NOT_QUALIFIED")

	var frontier_hash := String(value["canonical_source_frontier"]["frontier_hash"])
	var authority_binding := String(value["authority_envelope"]["authority_epoch_binding"])
	if typeof(value.get("representations")) != TYPE_ARRAY or value["representations"].is_empty():
		return Utils.failure("BRIDGE2_A_REPRESENTATIONS_REQUIRED")
	var representation_ids: Array[String] = []
	var previous_representation := ""
	for index in range(value["representations"].size()):
		var raw = value["representations"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("BRIDGE2_A_INVALID_REPRESENTATION", {"index": index})
		var representation: Dictionary = raw
		checked = Utils.validate_exact_fields(representation, REPRESENTATION_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var representation_id := String(representation.get("representation_id", ""))
		if not Utils.is_canonical_id(representation_id, 2):
			return Utils.failure("BRIDGE2_A_INVALID_REPRESENTATION_ID", {"index": index})
		if index > 0 and representation_id <= previous_representation:
			return Utils.failure("BRIDGE2_A_REPRESENTATIONS_NOT_SORTED_UNIQUE", {"index": index})
		previous_representation = representation_id
		representation_ids.append(representation_id)
		if not REPRESENTATION_KINDS.has(String(representation.get("representation_kind", ""))):
			return Utils.failure("BRIDGE2_A_UNSUPPORTED_REPRESENTATION_KIND", {"representation_id": representation_id})
		if typeof(representation.get("derived_only")) != TYPE_BOOL or not bool(representation["derived_only"]):
			return Utils.failure("BRIDGE2_A_REPRESENTATION_MUST_BE_DERIVED", {"representation_id": representation_id})
		if typeof(representation.get("canonical_write_authorized")) != TYPE_BOOL:
			return Utils.failure("BRIDGE2_A_INVALID_CANONICAL_WRITE_FLAG", {"representation_id": representation_id})
		if bool(representation["canonical_write_authorized"]):
			return Utils.failure("BRIDGE2_A_DERIVED_CANONICAL_WRITE_FORBIDDEN", {"representation_id": representation_id})
		if String(representation.get("source_frontier_hash", "")) != frontier_hash:
			return Utils.failure("BRIDGE2_A_REPRESENTATION_FRONTIER_MISMATCH", {"representation_id": representation_id})
		if String(representation.get("authority_epoch_binding", "")) != authority_binding:
			return Utils.failure("BRIDGE2_A_REPRESENTATION_AUTHORITY_MISMATCH", {"representation_id": representation_id})

	if typeof(value.get("region_bindings")) != TYPE_ARRAY or value["region_bindings"].is_empty():
		return Utils.failure("BRIDGE2_A_REGION_BINDINGS_REQUIRED")
	var previous_binding := ""
	var region_representation_pairs := {}
	var active_by_region := {}
	var all_regions := {}
	for index in range(value["region_bindings"].size()):
		var raw = value["region_bindings"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("BRIDGE2_A_INVALID_REGION_BINDING", {"index": index})
		var binding: Dictionary = raw
		checked = Utils.validate_exact_fields(binding, REGION_BINDING_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var key := _binding_key(binding)
		if index > 0 and key <= previous_binding:
			return Utils.failure("BRIDGE2_A_REGION_BINDINGS_NOT_SORTED_UNIQUE", {"index": index})
		previous_binding = key
		var region_id := String(binding.get("region_id", ""))
		var representation_id := String(binding.get("representation_id", ""))
		var ownership_role := String(binding.get("ownership_role", ""))
		if not Utils.is_canonical_id(region_id, 2):
			return Utils.failure("BRIDGE2_A_INVALID_REGION_ID", {"index": index})
		if not representation_ids.has(representation_id):
			return Utils.failure("BRIDGE2_A_REGION_REFERENCES_UNKNOWN_REPRESENTATION", {"representation_id": representation_id})
		if not OWNERSHIP_ROLES.has(ownership_role):
			return Utils.failure("BRIDGE2_A_UNSUPPORTED_OWNERSHIP_ROLE", {"ownership_role": ownership_role})
		var pair_key := "%s|%s" % [region_id, representation_id]
		if region_representation_pairs.has(pair_key):
			return Utils.failure("BRIDGE2_A_DUPLICATE_REGION_REPRESENTATION_BINDING", {"region_id": region_id, "representation_id": representation_id})
		region_representation_pairs[pair_key] = true
		all_regions[region_id] = true
		if ownership_role == "ACTIVE_EXECUTION":
			if active_by_region.has(region_id):
				return Utils.failure("BRIDGE2_A_MULTIPLE_ACTIVE_REGION_OWNERS", {
					"region_id": region_id,
					"first": active_by_region[region_id],
					"second": representation_id,
				})
			active_by_region[region_id] = representation_id
	for region_id in all_regions.keys():
		if not active_by_region.has(region_id):
			return Utils.failure("BRIDGE2_A_REGION_ACTIVE_OWNER_REQUIRED", {"region_id": region_id})

	if not Utils.is_lower_hex_64(value.get("contract_hash")):
		return Utils.failure("BRIDGE2_A_INVALID_CONTRACT_HASH")
	if String(value["contract_hash"]) != Utils.canonical_hash(_contract_identity(value)):
		return Utils.failure("BRIDGE2_A_CONTRACT_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func resolve_event(value: Dictionary, event_request: Dictionary, committed_event_ids: Array = []) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = Utils.validate_exact_fields(event_request, EVENT_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	var event_id := String(event_request.get("event_id", ""))
	var region_id := String(event_request.get("region_id", ""))
	if not Utils.is_canonical_id(event_id, 2):
		return Utils.failure("BRIDGE2_A_INVALID_EVENT_ID")
	if not Utils.is_canonical_id(region_id, 2):
		return Utils.failure("BRIDGE2_A_INVALID_EVENT_REGION")
	if not Utils.is_upper_kind(event_request.get("event_kind")):
		return Utils.failure("BRIDGE2_A_INVALID_EVENT_KIND")
	var canonical_effect := String(event_request.get("canonical_effect", ""))
	if not CANONICAL_EFFECTS.has(canonical_effect):
		return Utils.failure("BRIDGE2_A_INVALID_CANONICAL_EFFECT")
	checked = Utils.validate_sorted_unique_strings(event_request.get("candidate_representation_ids"), false)
	if not bool(checked.get("success", false)):
		return Utils.failure("BRIDGE2_A_INVALID_EVENT_CANDIDATES", {"cause": checked.get("error_code", "INVALID_CANDIDATES")})
	checked = Utils.validate_sorted_unique_strings(committed_event_ids, true)
	if not bool(checked.get("success", false)):
		return Utils.failure("BRIDGE2_A_INVALID_COMMITTED_EVENT_LEDGER", {"cause": checked.get("error_code", "INVALID_LEDGER")})
	if committed_event_ids.has(event_id):
		return Utils.failure("BRIDGE2_A_EVENT_ALREADY_COMMITTED", {"event_id": event_id})

	var region_bindings := _bindings_for_region(value, region_id)
	if region_bindings.is_empty():
		return Utils.failure("BRIDGE2_A_EVENT_REGION_NOT_BOUND", {"region_id": region_id})
	var active_representation_id := ""
	var bound_ids: Array[String] = []
	for binding in region_bindings:
		var representation_id := String(binding["representation_id"])
		bound_ids.append(representation_id)
		if String(binding["ownership_role"]) == "ACTIVE_EXECUTION":
			active_representation_id = representation_id
	for candidate in event_request["candidate_representation_ids"]:
		if not bound_ids.has(String(candidate)):
			return Utils.failure("BRIDGE2_A_EVENT_CANDIDATE_OUTSIDE_REGION", {
				"region_id": region_id,
				"representation_id": candidate,
			})
	if not event_request["candidate_representation_ids"].has(active_representation_id):
		return Utils.failure("BRIDGE2_A_ACTIVE_OWNER_NOT_CANDIDATE", {
			"region_id": region_id,
			"active_representation_id": active_representation_id,
		})

	var evaluator := _representation_by_id(value, active_representation_id)
	if evaluator.is_empty():
		return Utils.failure("BRIDGE2_A_ACTIVE_OWNER_REPRESENTATION_MISSING")
	var observers: Array[String] = []
	for candidate in event_request["candidate_representation_ids"]:
		if String(candidate) != active_representation_id:
			observers.append(String(candidate))
	observers.sort()

	var commit_owner := DERIVED_EVENT_COMMIT_OWNER
	var canonical_revision_policy := "NO_CANONICAL_REVISION"
	if canonical_effect == "CANONICAL_MUTATION":
		commit_owner = String(value["authority_envelope"]["execution_owner"])
		canonical_revision_policy = SOURCE_REVISION_POLICY

	var resolution: Dictionary = {
		"schema": RESOLUTION_SCHEMA,
		"event_id": event_id,
		"region_id": region_id,
		"event_kind": String(event_request["event_kind"]),
		"canonical_effect": canonical_effect,
		"evaluator_representation_id": active_representation_id,
		"evaluator_representation_kind": String(evaluator["representation_kind"]),
		"observer_representation_ids": observers,
		"commit_owner": commit_owner,
		"canonical_revision_policy": canonical_revision_policy,
		"event_commit_policy": EVENT_COMMIT_POLICY,
		"evaluator_canonical_write_authorized": false,
		"source_frontier_hash": String(value["canonical_source_frontier"]["frontier_hash"]),
		"authority_epoch_binding": String(value["authority_envelope"]["authority_epoch_binding"]),
		"contract_hash": String(value["contract_hash"]),
		"resolution_hash": "",
		"checksum": "",
	}
	resolution["resolution_hash"] = Utils.canonical_hash(_resolution_identity(resolution))
	resolution["checksum"] = Utils.compute_checksum(resolution)
	checked = validate_resolution(resolution, value)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"resolution": resolution})

static func validate_resolution(resolution: Dictionary, value: Dictionary) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = Utils.validate_exact_fields(resolution, RESOLUTION_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if resolution.get("schema") != RESOLUTION_SCHEMA:
		return Utils.failure("UNSUPPORTED_BRIDGE2_A_RESOLUTION_SCHEMA")
	if String(resolution.get("contract_hash", "")) != String(value["contract_hash"]):
		return Utils.failure("BRIDGE2_A_RESOLUTION_CONTRACT_MISMATCH")
	if String(resolution.get("source_frontier_hash", "")) != String(value["canonical_source_frontier"]["frontier_hash"]):
		return Utils.failure("BRIDGE2_A_RESOLUTION_FRONTIER_MISMATCH")
	if String(resolution.get("authority_epoch_binding", "")) != String(value["authority_envelope"]["authority_epoch_binding"]):
		return Utils.failure("BRIDGE2_A_RESOLUTION_AUTHORITY_MISMATCH")
	if String(resolution.get("event_commit_policy", "")) != EVENT_COMMIT_POLICY:
		return Utils.failure("BRIDGE2_A_RESOLUTION_COMMIT_POLICY_MISMATCH")
	if typeof(resolution.get("evaluator_canonical_write_authorized")) != TYPE_BOOL or bool(resolution["evaluator_canonical_write_authorized"]):
		return Utils.failure("BRIDGE2_A_RESOLUTION_CANONICAL_WRITE_FORBIDDEN")
	var region_id := String(resolution.get("region_id", ""))
	var active := active_owner_for_region(value, region_id)
	if active.is_empty() or String(resolution.get("evaluator_representation_id", "")) != active:
		return Utils.failure("BRIDGE2_A_RESOLUTION_EVALUATOR_MISMATCH")
	var evaluator := _representation_by_id(value, active)
	if evaluator.is_empty() or String(resolution.get("evaluator_representation_kind", "")) != String(evaluator["representation_kind"]):
		return Utils.failure("BRIDGE2_A_RESOLUTION_EVALUATOR_KIND_MISMATCH")
	var canonical_effect := String(resolution.get("canonical_effect", ""))
	if not CANONICAL_EFFECTS.has(canonical_effect):
		return Utils.failure("BRIDGE2_A_INVALID_CANONICAL_EFFECT")
	if canonical_effect == "CANONICAL_MUTATION":
		if String(resolution.get("commit_owner", "")) != String(value["authority_envelope"]["execution_owner"]):
			return Utils.failure("BRIDGE2_A_CANONICAL_COMMIT_OWNER_MISMATCH")
		if String(resolution.get("canonical_revision_policy", "")) != SOURCE_REVISION_POLICY:
			return Utils.failure("BRIDGE2_A_CANONICAL_REVISION_POLICY_MISMATCH")
	else:
		if String(resolution.get("commit_owner", "")) != DERIVED_EVENT_COMMIT_OWNER:
			return Utils.failure("BRIDGE2_A_DERIVED_EVENT_OWNER_MISMATCH")
		if String(resolution.get("canonical_revision_policy", "")) != "NO_CANONICAL_REVISION":
			return Utils.failure("BRIDGE2_A_DERIVED_EVENT_REVISION_FORBIDDEN")
	checked = Utils.validate_sorted_unique_strings(resolution.get("observer_representation_ids"), true)
	if not bool(checked.get("success", false)):
		return Utils.failure("BRIDGE2_A_INVALID_RESOLUTION_OBSERVERS")
	if resolution["observer_representation_ids"].has(active):
		return Utils.failure("BRIDGE2_A_EVALUATOR_CANNOT_BE_OBSERVER")
	if not Utils.is_lower_hex_64(resolution.get("resolution_hash")):
		return Utils.failure("BRIDGE2_A_INVALID_RESOLUTION_HASH")
	if String(resolution["resolution_hash"]) != Utils.canonical_hash(_resolution_identity(resolution)):
		return Utils.failure("BRIDGE2_A_RESOLUTION_HASH_MISMATCH")
	return Utils.validate_checksum(resolution)

static func active_owner_for_region(value: Dictionary, region_id: String) -> String:
	for binding in value.get("region_bindings", []):
		if String(binding.get("region_id", "")) == region_id and String(binding.get("ownership_role", "")) == "ACTIVE_EXECUTION":
			return String(binding.get("representation_id", ""))
	return ""

static func _bindings_for_region(value: Dictionary, region_id: String) -> Array:
	var output: Array = []
	for binding in value.get("region_bindings", []):
		if String(binding.get("region_id", "")) == region_id:
			output.append(binding)
	return output

static func _representation_by_id(value: Dictionary, representation_id: String) -> Dictionary:
	for representation in value.get("representations", []):
		if String(representation.get("representation_id", "")) == representation_id:
			return representation
	return {}

static func _binding_key(value) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return str(value)
	return "%s|%s" % [
		String(value.get("region_id", "")),
		String(value.get("representation_id", "")),
	]

static func _contract_identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("contract_hash")
	payload.erase("checksum")
	return payload

static func _resolution_identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("resolution_hash")
	payload.erase("checksum")
	return payload
