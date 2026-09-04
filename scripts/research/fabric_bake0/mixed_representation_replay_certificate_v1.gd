extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Ordering = preload("res://scripts/research/fabric_bake0/mixed_representation_invalidation_ordering_v1.gd")

const INVALIDATION_SCHEMA := "planet_simulator.fabric_bake_mixed_replay_invalidation_capsule.v1"
const RECOVERY_SCHEMA := "planet_simulator.fabric_bake_mixed_replay_recovery_capsule.v1"
const CERTIFICATE_SCHEMA := "planet_simulator.fabric_bake_mixed_replay_certificate.v1"
const QUALIFICATION := "BRIDGE_2_E_DETERMINISTIC_MIXED_REPLAY"

const INVALIDATION_FIELDS: Array[String] = [
	"schema", "event_id", "event_sequence", "event_hash",
	"previous_source_frontier_hash", "current_source_frontier_hash",
	"route_hash", "commit_hash", "old_subject_hash", "old_ownership_contract_hash",
	"ordering_trace_hash", "stale_records", "invalidation_hashes",
	"transaction_checksum", "split_records", "split_state_records",
	"topology_event_commit_hash", "diagnostics_hash", "final_structural_state_hash",
	"replay_qualification", "capsule_hash", "checksum",
]
const RECOVERY_FIELDS: Array[String] = [
	"schema", "event_id", "current_source_frontier_hash",
	"old_ownership_contract_hash", "fresh_ownership_contract_hash",
	"ordering_trace_hash", "recovery_records", "fresh_full_model_hash",
	"fresh_structural_artifact_hashes", "fresh_dynamic_artifact_hash",
	"fresh_dynamic_session_hash", "fresh_hybrid_package_hash", "fresh_hybrid_session_hash",
	"fresh_execution_signature_hash", "final_recovery_state_hash",
	"replay_qualification", "capsule_hash", "checksum",
]
const CERTIFICATE_FIELDS: Array[String] = [
	"schema", "event_id", "event_sequence", "event_hash",
	"previous_source_frontier_hash", "current_source_frontier_hash",
	"route_hash", "commit_hash", "old_subject_hash",
	"old_ownership_contract_hash", "fresh_ownership_contract_hash",
	"invalidation_capsule_hash", "recovery_capsule_hash",
	"stale_set_hash", "split_identity_hash", "post_split_structural_state_hash",
	"fresh_execution_identity_hash", "final_recovery_state_hash", "final_mixed_state_hash",
	"replay_qualification", "certificate_hash", "checksum",
]
const STALE_FIELDS: Array[String] = [
	"representation_kind", "error_code", "cause", "fallback", "reason", "stale_hash",
]
const SPLIT_FIELDS: Array[String] = [
	"component_id", "part_count", "descriptor_hash", "reconstruction_mapping_hash",
	"guard_field_hash", "physical_artifact_hash", "split_hash",
]
const SPLIT_STATE_FIELDS: Array[String] = [
	"component_id", "artifact_hash", "reduced_state_hash", "execution_gate_hash", "state_hash",
]

static func capture_invalidation(b: Dictionary) -> Dictionary:
	if not bool(b.get("success", false)):
		return U.failure("BRIDGE2_E_INVALIDATION_FIXTURE_FAILED")
	var trace: Dictionary = b.get("trace", {})
	var checked := Ordering.validate_invalidation(trace)
	if not bool(checked.get("success", false)):
		return checked
	var stale_records := _stale_records(b)
	if stale_records.is_empty():
		return U.failure("BRIDGE2_E_STALE_CAPTURE_FAILED")
	var split_records := _split_records(b.get("transaction", {}))
	if split_records.is_empty():
		return U.failure("BRIDGE2_E_SPLIT_CAPTURE_FAILED")
	var split_states := _split_state_records(b.get("topology_runtime", {}))
	if split_states.is_empty():
		return U.failure("BRIDGE2_E_SPLIT_STATE_CAPTURE_FAILED")
	var invalidation_hashes: Array = []
	for name in ["structural_invalidation", "contact_invalidation", "dynamic_invalidation"]:
		var inv = b.get(name, {})
		if typeof(inv) != TYPE_DICTIONARY or not U.is_lower_hex_64(inv.get("checksum")):
			return U.failure("BRIDGE2_E_INVALIDATION_HASH_CAPTURE_FAILED", {"name": name})
		invalidation_hashes.append(String(inv["checksum"]))
	var hybrid_package = b.get("hybrid_invalidated", {}).get("details", {}).get("package", {})
	if typeof(hybrid_package) != TYPE_DICTIONARY or not U.is_lower_hex_64(hybrid_package.get("checksum")):
		return U.failure("BRIDGE2_E_HYBRID_INVALIDATION_HASH_CAPTURE_FAILED")
	invalidation_hashes.append(String(hybrid_package["checksum"]))
	invalidation_hashes.sort()

	var runtime: Dictionary = b.get("topology_runtime", {})
	var event_commit: Dictionary = runtime.get("event_commit", {})
	var diagnostics: Dictionary = runtime.get("diagnostics", {})
	var value: Dictionary = {
		"schema": INVALIDATION_SCHEMA,
		"event_id": String(event_commit.get("event_id", "")),
		"event_sequence": int(event_commit.get("event_sequence", -1)),
		"event_hash": String(event_commit.get("event_hash", "")),
		"previous_source_frontier_hash": String(trace.get("previous_source_frontier_hash", "")),
		"current_source_frontier_hash": String(trace.get("current_source_frontier_hash", "")),
		"route_hash": String(trace.get("route_hash", "")),
		"commit_hash": String(trace.get("commit_hash", "")),
		"old_subject_hash": String(trace.get("old_subject_hash", "")),
		"old_ownership_contract_hash": String(trace.get("old_ownership_contract_hash", "")),
		"ordering_trace_hash": String(trace.get("trace_hash", "")),
		"stale_records": stale_records,
		"invalidation_hashes": invalidation_hashes,
		"transaction_checksum": String(b.get("transaction", {}).get("checksum", "")),
		"split_records": split_records,
		"split_state_records": split_states,
		"topology_event_commit_hash": U.canonical_hash(event_commit),
		"diagnostics_hash": U.canonical_hash(_deterministic_diagnostics(diagnostics)),
		"final_structural_state_hash": U.canonical_hash(split_states),
		"replay_qualification": QUALIFICATION,
		"capsule_hash": "",
		"checksum": "",
	}
	value["capsule_hash"] = U.canonical_hash(_without(value, ["capsule_hash", "checksum"]))
	value["checksum"] = U.compute_checksum(value)
	checked = validate_invalidation(value)
	if not bool(checked.get("success", false)):
		return checked
	return U.success({"capsule": value})

static func capture_recovery(b: Dictionary) -> Dictionary:
	if not bool(b.get("success", false)):
		return U.failure("BRIDGE2_E_RECOVERY_FIXTURE_FAILED")
	var trace: Dictionary = b.get("trace", {})
	var checked := Ordering.validate_recovery(trace)
	if not bool(checked.get("success", false)):
		return checked
	var structural_hashes: Array = []
	for component in b.get("transaction", {}).get("rebaked_components", []):
		var artifact = component.get("physical_bake_artifact", {})
		if typeof(artifact) != TYPE_DICTIONARY or not U.is_lower_hex_64(artifact.get("checksum")):
			return U.failure("BRIDGE2_E_RECOVERY_STRUCTURAL_HASH_CAPTURE_FAILED")
		structural_hashes.append(String(artifact["checksum"]))
	structural_hashes.sort()
	if structural_hashes.size() != 2:
		return U.failure("BRIDGE2_E_RECOVERY_STRUCTURAL_COVERAGE_MISMATCH")
	var rebound: Dictionary = b.get("rebound", {})
	var full_model: Dictionary = rebound.get("full_model", {})
	var dynamic_bundle: Dictionary = rebound.get("dynamic_bundle", {})
	var dynamic_session: Dictionary = rebound.get("dynamic_session", {})
	var hybrid_package: Dictionary = rebound.get("hybrid_package", {})
	var hybrid_session: Dictionary = rebound.get("hybrid_session", {})
	for pair in [
		["fresh_full_model_hash", full_model.get("model_hash")],
		["fresh_dynamic_artifact_hash", dynamic_bundle.get("physical_artifact", {}).get("checksum")],
		["fresh_dynamic_session_hash", dynamic_session.get("checksum")],
		["fresh_hybrid_package_hash", hybrid_package.get("package_hash")],
		["fresh_hybrid_session_hash", hybrid_session.get("checksum")],
	]:
		if not U.is_lower_hex_64(pair[1]):
			return U.failure("BRIDGE2_E_RECOVERY_IDENTITY_CAPTURE_FAILED", {"field": pair[0]})
	var recovery_records: Array = trace.get("recovery_records", []).duplicate(true)
	var execution_signature := {
		"dynamic_physical_artifact_id": String(rebound.get("dynamic_step", {}).get("details", {}).get("physical_artifact_id", "")),
		"dynamic_session_hash": String(dynamic_session["checksum"]),
		"hybrid_action": String(rebound.get("hybrid_resolution", {}).get("details", {}).get("action", "")),
		"hybrid_status": String(rebound.get("hybrid_step", {}).get("details", {}).get("status", "")),
		"hybrid_session_hash": String(hybrid_session["checksum"]),
		"structural_artifact_hashes": structural_hashes,
	}
	var value: Dictionary = {
		"schema": RECOVERY_SCHEMA,
		"event_id": String(trace.get("event_id", "")),
		"current_source_frontier_hash": String(trace.get("current_source_frontier_hash", "")),
		"old_ownership_contract_hash": String(trace.get("old_ownership_contract_hash", "")),
		"fresh_ownership_contract_hash": String(trace.get("fresh_ownership_contract_hash", "")),
		"ordering_trace_hash": String(trace.get("trace_hash", "")),
		"recovery_records": recovery_records,
		"fresh_full_model_hash": String(full_model["model_hash"]),
		"fresh_structural_artifact_hashes": structural_hashes,
		"fresh_dynamic_artifact_hash": String(dynamic_bundle["physical_artifact"]["checksum"]),
		"fresh_dynamic_session_hash": String(dynamic_session["checksum"]),
		"fresh_hybrid_package_hash": String(hybrid_package["package_hash"]),
		"fresh_hybrid_session_hash": String(hybrid_session["checksum"]),
		"fresh_execution_signature_hash": U.canonical_hash(execution_signature),
		"final_recovery_state_hash": U.canonical_hash({
			"ownership": trace["fresh_ownership_contract_hash"],
			"recovery_records": recovery_records,
			"fresh_execution_signature_hash": U.canonical_hash(execution_signature),
		}),
		"replay_qualification": QUALIFICATION,
		"capsule_hash": "",
		"checksum": "",
	}
	value["capsule_hash"] = U.canonical_hash(_without(value, ["capsule_hash", "checksum"]))
	value["checksum"] = U.compute_checksum(value)
	checked = validate_recovery(value)
	if not bool(checked.get("success", false)):
		return checked
	return U.success({"capsule": value})

static func compose(invalidation: Dictionary, recovery: Dictionary) -> Dictionary:
	var checked := validate_invalidation(invalidation)
	if not bool(checked.get("success", false)):
		return checked
	checked = validate_recovery(recovery)
	if not bool(checked.get("success", false)):
		return checked
	if String(invalidation["event_id"]) != String(recovery["event_id"]):
		return U.failure("BRIDGE2_E_EVENT_LINK_MISMATCH")
	if String(invalidation["current_source_frontier_hash"]) != String(recovery["current_source_frontier_hash"]):
		return U.failure("BRIDGE2_E_FRONTIER_LINK_MISMATCH")
	if String(invalidation["old_ownership_contract_hash"]) != String(recovery["old_ownership_contract_hash"]):
		return U.failure("BRIDGE2_E_OWNERSHIP_LINK_MISMATCH")
	var split_hashes: Array = []
	for record in invalidation["split_records"]:
		split_hashes.append(String(record["physical_artifact_hash"]))
	split_hashes.sort()
	if split_hashes != recovery["fresh_structural_artifact_hashes"]:
		return U.failure("BRIDGE2_E_STRUCTURAL_RECOVERY_LINK_MISMATCH")
	var value: Dictionary = {
		"schema": CERTIFICATE_SCHEMA,
		"event_id": String(invalidation["event_id"]),
		"event_sequence": int(invalidation["event_sequence"]),
		"event_hash": String(invalidation["event_hash"]),
		"previous_source_frontier_hash": String(invalidation["previous_source_frontier_hash"]),
		"current_source_frontier_hash": String(invalidation["current_source_frontier_hash"]),
		"route_hash": String(invalidation["route_hash"]),
		"commit_hash": String(invalidation["commit_hash"]),
		"old_subject_hash": String(invalidation["old_subject_hash"]),
		"old_ownership_contract_hash": String(invalidation["old_ownership_contract_hash"]),
		"fresh_ownership_contract_hash": String(recovery["fresh_ownership_contract_hash"]),
		"invalidation_capsule_hash": String(invalidation["capsule_hash"]),
		"recovery_capsule_hash": String(recovery["capsule_hash"]),
		"stale_set_hash": U.canonical_hash(invalidation["stale_records"]),
		"split_identity_hash": U.canonical_hash(invalidation["split_records"]),
		"post_split_structural_state_hash": String(invalidation["final_structural_state_hash"]),
		"fresh_execution_identity_hash": String(recovery["fresh_execution_signature_hash"]),
		"final_recovery_state_hash": String(recovery["final_recovery_state_hash"]),
		"final_mixed_state_hash": U.canonical_hash({
			"structural": invalidation["final_structural_state_hash"],
			"recovery": recovery["final_recovery_state_hash"],
		}),
		"replay_qualification": QUALIFICATION,
		"certificate_hash": "",
		"checksum": "",
	}
	value["certificate_hash"] = U.canonical_hash(_without(value, ["certificate_hash", "checksum"]))
	value["checksum"] = U.compute_checksum(value)
	checked = validate_certificate(value)
	if not bool(checked.get("success", false)):
		return checked
	return U.success({"certificate": value})

static func compare_replays(left: Dictionary, right: Dictionary) -> Dictionary:
	var checked := validate_certificate(left)
	if not bool(checked.get("success", false)):
		return checked
	checked = validate_certificate(right)
	if not bool(checked.get("success", false)):
		return checked
	for field in CERTIFICATE_FIELDS:
		if left.get(field) != right.get(field):
			return U.failure("BRIDGE2_E_REPLAY_MISMATCH", {"field": field, "left": left.get(field), "right": right.get(field)})
	return U.success({"certificate_hash": String(left["certificate_hash"])})

static func validate_invalidation(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, INVALIDATION_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != INVALIDATION_SCHEMA:
		return U.failure("UNSUPPORTED_BRIDGE2_E_INVALIDATION_SCHEMA")
	for field in [
		"event_hash", "previous_source_frontier_hash", "current_source_frontier_hash", "route_hash",
		"commit_hash", "old_subject_hash", "old_ownership_contract_hash", "ordering_trace_hash",
		"transaction_checksum", "topology_event_commit_hash", "diagnostics_hash",
		"final_structural_state_hash", "capsule_hash",
	]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("BRIDGE2_E_INVALID_HASH", {"field": field})
	if not U.is_canonical_id(value.get("event_id"), 2) or int(value.get("event_sequence", -1)) < 0:
		return U.failure("BRIDGE2_E_INVALID_EVENT_IDENTITY")
	if String(value["previous_source_frontier_hash"]) == String(value["current_source_frontier_hash"]):
		return U.failure("BRIDGE2_E_FRONTIER_MUST_ADVANCE")
	if String(value.get("replay_qualification", "")) != QUALIFICATION:
		return U.failure("BRIDGE2_E_REPLAY_NOT_QUALIFIED")
	checked = _validate_stale_records(value.get("stale_records"))
	if not bool(checked.get("success", false)):
		return checked
	checked = U.validate_sorted_unique_strings(value.get("invalidation_hashes"), false)
	if not bool(checked.get("success", false)):
		return U.failure("BRIDGE2_E_INVALID_INVALIDATION_HASH_SET")
	for h in value["invalidation_hashes"]:
		if not U.is_lower_hex_64(h): return U.failure("BRIDGE2_E_INVALID_INVALIDATION_HASH")
	checked = _validate_split_records(value.get("split_records"))
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_split_states(value.get("split_state_records"))
	if not bool(checked.get("success", false)):
		return checked
	if String(value["final_structural_state_hash"]) != U.canonical_hash(value["split_state_records"]):
		return U.failure("BRIDGE2_E_STRUCTURAL_STATE_HASH_MISMATCH")
	return _validate_capsule_hash(value)

static func validate_recovery(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, RECOVERY_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != RECOVERY_SCHEMA:
		return U.failure("UNSUPPORTED_BRIDGE2_E_RECOVERY_SCHEMA")
	for field in [
		"current_source_frontier_hash", "old_ownership_contract_hash", "fresh_ownership_contract_hash",
		"ordering_trace_hash", "fresh_full_model_hash", "fresh_dynamic_artifact_hash",
		"fresh_dynamic_session_hash", "fresh_hybrid_package_hash", "fresh_hybrid_session_hash",
		"fresh_execution_signature_hash", "final_recovery_state_hash", "capsule_hash",
	]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("BRIDGE2_E_INVALID_HASH", {"field": field})
	if not U.is_canonical_id(value.get("event_id"), 2):
		return U.failure("BRIDGE2_E_INVALID_EVENT_IDENTITY")
	if String(value["old_ownership_contract_hash"]) == String(value["fresh_ownership_contract_hash"]):
		return U.failure("BRIDGE2_E_OWNERSHIP_REBIND_REQUIRED")
	if String(value.get("replay_qualification", "")) != QUALIFICATION:
		return U.failure("BRIDGE2_E_REPLAY_NOT_QUALIFIED")
	# Reuse B2-D's recovery-record validator by recreating a legal trace with
	# deterministic placeholder phase proofs.
	var legal := Ordering.create_recovery(
		String(value["event_id"]), String(value["current_source_frontier_hash"]),
		String(value["old_ownership_contract_hash"]), String(value["fresh_ownership_contract_hash"]),
		[_placeholder_hash(), _placeholder_hash()], value["recovery_records"]
	)
	if legal.is_empty():
		return U.failure("BRIDGE2_E_INVALID_RECOVERY_RECORDS")
	checked = U.validate_sorted_unique_strings(value.get("fresh_structural_artifact_hashes"), false)
	if not bool(checked.get("success", false)) or value["fresh_structural_artifact_hashes"].size() != 2:
		return U.failure("BRIDGE2_E_INVALID_FRESH_STRUCTURAL_SET")
	for h in value["fresh_structural_artifact_hashes"]:
		if not U.is_lower_hex_64(h): return U.failure("BRIDGE2_E_INVALID_FRESH_STRUCTURAL_HASH")
	var expected_final := U.canonical_hash({
		"ownership": value["fresh_ownership_contract_hash"],
		"recovery_records": value["recovery_records"],
		"fresh_execution_signature_hash": value["fresh_execution_signature_hash"],
	})
	if String(value["final_recovery_state_hash"]) != expected_final:
		return U.failure("BRIDGE2_E_FINAL_RECOVERY_STATE_HASH_MISMATCH")
	return _validate_capsule_hash(value)

static func validate_certificate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, CERTIFICATE_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != CERTIFICATE_SCHEMA:
		return U.failure("UNSUPPORTED_BRIDGE2_E_CERTIFICATE_SCHEMA")
	if not U.is_canonical_id(value.get("event_id"), 2) or int(value.get("event_sequence", -1)) < 0:
		return U.failure("BRIDGE2_E_INVALID_EVENT_IDENTITY")
	for field in [
		"event_hash", "previous_source_frontier_hash", "current_source_frontier_hash", "route_hash",
		"commit_hash", "old_subject_hash", "old_ownership_contract_hash", "fresh_ownership_contract_hash",
		"invalidation_capsule_hash", "recovery_capsule_hash", "stale_set_hash", "split_identity_hash",
		"post_split_structural_state_hash", "fresh_execution_identity_hash", "final_recovery_state_hash", "final_mixed_state_hash", "certificate_hash",
	]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("BRIDGE2_E_INVALID_HASH", {"field": field})
	if String(value["previous_source_frontier_hash"]) == String(value["current_source_frontier_hash"]):
		return U.failure("BRIDGE2_E_FRONTIER_MUST_ADVANCE")
	if String(value["old_ownership_contract_hash"]) == String(value["fresh_ownership_contract_hash"]):
		return U.failure("BRIDGE2_E_OWNERSHIP_REBIND_REQUIRED")
	var expected_final_mixed := U.canonical_hash({
		"structural": value["post_split_structural_state_hash"],
		"recovery": value["final_recovery_state_hash"],
	})
	if String(value["final_mixed_state_hash"]) != expected_final_mixed:
		return U.failure("BRIDGE2_E_FINAL_MIXED_STATE_HASH_MISMATCH")
	if String(value.get("replay_qualification", "")) != QUALIFICATION:
		return U.failure("BRIDGE2_E_REPLAY_NOT_QUALIFIED")
	if String(value["certificate_hash"]) != U.canonical_hash(_without(value, ["certificate_hash", "checksum"])):
		return U.failure("BRIDGE2_E_CERTIFICATE_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _stale_records(b: Dictionary) -> Array:
	var records: Array = [
		_stale("STRUCTURAL_BAKE", String(b.get("structural_stale", {}).get("error_code", "")), "", "", ""),
		_stale("CONTACT_BAKE", String(b.get("contact_stale", {}).get("code", "")), String(b.get("contact_stale", {}).get("b0_3_gate", {}).get("error_code", "")), "", ""),
		_stale("DYNAMIC_ROM", String(b.get("dynamic_stale", {}).get("error_code", "")), String(b.get("dynamic_stale", {}).get("details", {}).get("cause", b.get("dynamic_stale", {}).get("cause", ""))), "", ""),
		_stale("HYBRID_BAKE", String(b.get("hybrid_stale", {}).get("error_code", "")), String(b.get("hybrid_stale", {}).get("details", {}).get("cause", b.get("hybrid_stale", {}).get("cause", ""))), "", ""),
		_stale("HYBRID_CACHE", "", "", String(b.get("stale_mode_resolution", {}).get("details", {}).get("fallback", "")), String(b.get("stale_mode_resolution", {}).get("details", {}).get("reason", ""))),
	]
	records.sort_custom(func(a, c): return String(a["representation_kind"]) < String(c["representation_kind"]))
	return records

static func _stale(kind: String, code: String, cause: String, fallback: String, reason: String) -> Dictionary:
	var record := {
		"representation_kind": kind, "error_code": code, "cause": cause,
		"fallback": fallback, "reason": reason, "stale_hash": "",
	}
	record["stale_hash"] = U.canonical_hash(_without(record, ["stale_hash"]))
	return record

static func _validate_stale_records(raw) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 5:
		return U.failure("BRIDGE2_E_STALE_COVERAGE_MISMATCH")
	var previous := ""
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			return U.failure("BRIDGE2_E_INVALID_STALE_RECORD")
		var checked := U.validate_exact_fields(item, STALE_FIELDS)
		if not bool(checked.get("success", false)): return checked
		var kind := String(item["representation_kind"])
		if not previous.is_empty() and kind <= previous:
			return U.failure("BRIDGE2_E_STALE_RECORDS_NOT_SORTED")
		previous = kind
		if not U.is_lower_hex_64(item.get("stale_hash")) or String(item["stale_hash"]) != U.canonical_hash(_without(item, ["stale_hash"])):
			return U.failure("BRIDGE2_E_STALE_HASH_MISMATCH", {"kind": kind})
	return U.success()

static func _split_records(transaction: Dictionary) -> Array:
	var records: Array = []
	for component in transaction.get("rebaked_components", []):
		var artifact = component.get("physical_bake_artifact", {})
		var record := {
			"component_id": String(component.get("component_id", "")),
			"part_count": component.get("part_ids", []).size(),
			"descriptor_hash": String(component.get("descriptor", {}).get("checksum", "")),
			"reconstruction_mapping_hash": String(component.get("reconstruction_mapping", {}).get("checksum", "")),
			"guard_field_hash": String(component.get("guard_field", {}).get("checksum", "")),
			"physical_artifact_hash": String(artifact.get("checksum", "")),
			"split_hash": "",
		}
		record["split_hash"] = U.canonical_hash(_without(record, ["split_hash"]))
		records.append(record)
	records.sort_custom(func(a, c): return String(a["component_id"]) < String(c["component_id"]))
	return records

static func _validate_split_records(raw) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
		return U.failure("BRIDGE2_E_SPLIT_COVERAGE_MISMATCH")
	var previous := ""
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY: return U.failure("BRIDGE2_E_INVALID_SPLIT_RECORD")
		var checked := U.validate_exact_fields(item, SPLIT_FIELDS)
		if not bool(checked.get("success", false)): return checked
		var component_id := String(item["component_id"])
		if not previous.is_empty() and component_id <= previous: return U.failure("BRIDGE2_E_SPLIT_RECORDS_NOT_SORTED")
		previous = component_id
		if int(item.get("part_count", 0)) <= 0: return U.failure("BRIDGE2_E_INVALID_SPLIT_PART_COUNT")
		for field in ["descriptor_hash", "reconstruction_mapping_hash", "guard_field_hash", "physical_artifact_hash", "split_hash"]:
			if not U.is_lower_hex_64(item.get(field)): return U.failure("BRIDGE2_E_INVALID_SPLIT_HASH", {"field": field})
		if String(item["split_hash"]) != U.canonical_hash(_without(item, ["split_hash"])):
			return U.failure("BRIDGE2_E_SPLIT_HASH_MISMATCH")
	return U.success()

static func _split_state_records(runtime: Dictionary) -> Array:
	var records: Array = []
	for state in runtime.get("rebaked_component_states", []):
		var record := {
			"component_id": String(state.get("component_id", "")),
			"artifact_hash": String(state.get("artifact_hash", "")),
			"reduced_state_hash": U.canonical_hash(state.get("reduced_state", {})),
			"execution_gate_hash": U.canonical_hash(state.get("execution_gate", {})),
			"state_hash": "",
		}
		record["state_hash"] = U.canonical_hash(_without(record, ["state_hash"]))
		records.append(record)
	records.sort_custom(func(a, c): return String(a["component_id"]) < String(c["component_id"]))
	return records

static func _validate_split_states(raw) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 2: return U.failure("BRIDGE2_E_SPLIT_STATE_COVERAGE_MISMATCH")
	var previous := ""
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY: return U.failure("BRIDGE2_E_INVALID_SPLIT_STATE")
		var checked := U.validate_exact_fields(item, SPLIT_STATE_FIELDS)
		if not bool(checked.get("success", false)): return checked
		var component_id := String(item["component_id"])
		if not previous.is_empty() and component_id <= previous: return U.failure("BRIDGE2_E_SPLIT_STATES_NOT_SORTED")
		previous = component_id
		for field in ["artifact_hash", "reduced_state_hash", "execution_gate_hash", "state_hash"]:
			if not U.is_lower_hex_64(item.get(field)): return U.failure("BRIDGE2_E_INVALID_SPLIT_STATE_HASH", {"field": field})
		if String(item["state_hash"]) != U.canonical_hash(_without(item, ["state_hash"])):
			return U.failure("BRIDGE2_E_SPLIT_STATE_HASH_MISMATCH")
	return U.success()

static func _deterministic_diagnostics(d: Dictionary) -> Dictionary:
	return {
		"split_component_count": int(d.get("split_component_count", -1)),
		"invalidated_reduced_piece_count": int(d.get("invalidated_reduced_piece_count", -1)),
		"executable_physical_bake_artifact_count": int(d.get("executable_physical_bake_artifact_count", -1)),
		"full_dof": int(d.get("full_dof", -1)),
		"mixed_before_event_dof": int(d.get("mixed_before_event_dof", -1)),
		"rebaked_dof": int(d.get("rebaked_dof", -1)),
		"post_split_reduction_ratio": float(d.get("post_split_reduction_ratio", -1.0)),
		"mass_error": float(d.get("mass_error", -1.0)),
		"linear_momentum_error": float(d.get("linear_momentum_error", -1.0)),
		"angular_momentum_error": float(d.get("angular_momentum_error", -1.0)),
		"max_state_handoff_error": float(d.get("max_state_handoff_error", -1.0)),
		"duplicate_event_count": int(d.get("duplicate_event_count", -1)),
		"physical_bake_artifact_emitted": bool(d.get("physical_bake_artifact_emitted", false)),
		"b0_2_complete": bool(d.get("b0_2_complete", false)),
	}

static func _validate_capsule_hash(value: Dictionary) -> Dictionary:
	if String(value["capsule_hash"]) != U.canonical_hash(_without(value, ["capsule_hash", "checksum"])):
		return U.failure("BRIDGE2_E_CAPSULE_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _without(value: Dictionary, fields: Array) -> Dictionary:
	var payload := value.duplicate(true)
	for field in fields: payload.erase(field)
	return payload

static func _placeholder_hash() -> String:
	return "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
