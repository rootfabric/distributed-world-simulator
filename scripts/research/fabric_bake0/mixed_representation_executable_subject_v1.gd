extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const PhysicalArtifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const FullState = preload("res://scripts/research/fabric_bake0/dynamic_full_state_v1.gd")
const ContactBridge = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_bridge_v1.gd")
const DynamicBridge = preload("res://scripts/research/fabric_bake0/dynamic_rom_physical_bake_bridge_v1.gd")
const DynamicExecution = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_runtime_v1.gd")
const HybridRuntime = preload("res://scripts/research/fabric_bake0/hybrid_bake_executable_runtime_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_mixed_representation_executable_subject.v1"
const QUALIFICATION := "BRIDGE_2_B_EXECUTABLE_SUBJECT"
const WITNESS_KINDS := {
	"FULL": "FULL_REFERENCE_EXECUTION",
	"STRUCTURAL_BAKE": "BRIDGE1_STRUCTURAL_EXECUTION",
	"CONTACT_BAKE": "B0_3_CONTACT_EXECUTION",
	"DYNAMIC_ROM": "B0_4_DYNAMIC_ROM_SESSION",
	"HYBRID_BAKE": "B0_5_A_HYBRID_SESSION",
}
const FIELDS: Array[String] = [
	"schema", "ownership_contract_hash", "canonical_source_frontier_hash",
	"authority_epoch_binding", "execution_owner", "entries",
	"execution_qualification", "subject_hash", "checksum",
]
const ENTRY_FIELDS: Array[String] = [
	"representation_id", "representation_kind", "region_id", "ownership_role",
	"witness_kind", "source_frontier_hash", "authority_epoch_binding",
	"physical_artifact_checksum", "execution_identity_hash", "runtime_state_hash",
	"underlying_physical_artifact_checksum", "witness_hash",
]

static func compile(ownership_contract: Dictionary, witnesses: Array) -> Dictionary:
	var checked := Ownership.validate(ownership_contract)
	if not bool(checked.get("success", false)):
		return checked
	if witnesses.size() != ownership_contract["representations"].size():
		return Utils.failure("BRIDGE2_B_WITNESS_COVERAGE_MISMATCH", {
			"expected": ownership_contract["representations"].size(),
			"actual": witnesses.size(),
		})
	var entries: Array = []
	for raw in witnesses:
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("BRIDGE2_B_INVALID_WITNESS")
		var built := _build_entry(ownership_contract, raw)
		if not bool(built.get("success", false)):
			return built
		entries.append(built["details"]["entry"])
	entries.sort_custom(func(a, b): return String(a["representation_id"]) < String(b["representation_id"]))
	var value: Dictionary = {
		"schema": SCHEMA,
		"ownership_contract_hash": String(ownership_contract["contract_hash"]),
		"canonical_source_frontier_hash": String(ownership_contract["canonical_source_frontier"]["frontier_hash"]),
		"authority_epoch_binding": String(ownership_contract["authority_envelope"]["authority_epoch_binding"]),
		"execution_owner": String(ownership_contract["authority_envelope"]["execution_owner"]),
		"entries": entries,
		"execution_qualification": QUALIFICATION,
		"subject_hash": "",
		"checksum": "",
	}
	value["subject_hash"] = Utils.canonical_hash(_identity(value))
	value["checksum"] = Utils.compute_checksum(value)
	checked = validate(value, ownership_contract)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"subject": value})

static func validate(value: Dictionary, ownership_contract: Dictionary) -> Dictionary:
	var checked := Ownership.validate(ownership_contract)
	if not bool(checked.get("success", false)):
		return checked
	checked = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BRIDGE2_B_SUBJECT_SCHEMA")
	if String(value.get("ownership_contract_hash", "")) != String(ownership_contract["contract_hash"]):
		return Utils.failure("BRIDGE2_B_OWNERSHIP_CONTRACT_MISMATCH")
	if String(value.get("canonical_source_frontier_hash", "")) != String(ownership_contract["canonical_source_frontier"]["frontier_hash"]):
		return Utils.failure("BRIDGE2_B_SUBJECT_FRONTIER_MISMATCH")
	if String(value.get("authority_epoch_binding", "")) != String(ownership_contract["authority_envelope"]["authority_epoch_binding"]):
		return Utils.failure("BRIDGE2_B_SUBJECT_AUTHORITY_MISMATCH")
	if String(value.get("execution_owner", "")) != String(ownership_contract["authority_envelope"]["execution_owner"]):
		return Utils.failure("BRIDGE2_B_SUBJECT_EXECUTION_OWNER_MISMATCH")
	if String(value.get("execution_qualification", "")) != QUALIFICATION:
		return Utils.failure("BRIDGE2_B_SUBJECT_NOT_EXECUTABLE")
	if typeof(value.get("entries")) != TYPE_ARRAY:
		return Utils.failure("BRIDGE2_B_INVALID_ENTRIES")
	if value["entries"].size() != ownership_contract["representations"].size():
		return Utils.failure("BRIDGE2_B_ENTRY_COVERAGE_MISMATCH")
	var representation_by_id := {}
	for representation in ownership_contract["representations"]:
		representation_by_id[String(representation["representation_id"])] = representation
	var seen := {}
	var previous := ""
	for index in range(value["entries"].size()):
		var raw = value["entries"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("BRIDGE2_B_INVALID_ENTRY", {"index": index})
		var entry: Dictionary = raw
		checked = Utils.validate_exact_fields(entry, ENTRY_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var representation_id := String(entry.get("representation_id", ""))
		if not previous.is_empty() and representation_id <= previous:
			return Utils.failure("BRIDGE2_B_ENTRIES_NOT_SORTED_UNIQUE", {"index": index})
		previous = representation_id
		if seen.has(representation_id):
			return Utils.failure("BRIDGE2_B_DUPLICATE_REPRESENTATION_ENTRY", {"representation_id": representation_id})
		seen[representation_id] = true
		if not representation_by_id.has(representation_id):
			return Utils.failure("BRIDGE2_B_UNKNOWN_REPRESENTATION_ENTRY", {"representation_id": representation_id})
		var representation: Dictionary = representation_by_id[representation_id]
		if String(entry["representation_kind"]) != String(representation["representation_kind"]):
			return Utils.failure("BRIDGE2_B_REPRESENTATION_KIND_MISMATCH", {"representation_id": representation_id})
		if String(entry["witness_kind"]) != String(WITNESS_KINDS.get(String(entry["representation_kind"]), "")):
			return Utils.failure("BRIDGE2_B_WITNESS_KIND_MISMATCH", {"representation_id": representation_id})
		if String(entry["source_frontier_hash"]) != String(value["canonical_source_frontier_hash"]):
			return Utils.failure("BRIDGE2_B_ENTRY_FRONTIER_MISMATCH", {"representation_id": representation_id})
		if String(entry["authority_epoch_binding"]) != String(value["authority_epoch_binding"]):
			return Utils.failure("BRIDGE2_B_ENTRY_AUTHORITY_MISMATCH", {"representation_id": representation_id})
		if Ownership.active_owner_for_region(ownership_contract, String(entry["region_id"])) == representation_id:
			if String(entry["ownership_role"]) != "ACTIVE_EXECUTION":
				return Utils.failure("BRIDGE2_B_ACTIVE_WITNESS_ROLE_MISMATCH", {"representation_id": representation_id})
		else:
			return Utils.failure("BRIDGE2_B_WITNESS_REGION_NOT_ACTIVE_OWNER", {"representation_id": representation_id})
		for hash_field in ["execution_identity_hash", "runtime_state_hash", "witness_hash"]:
			if not Utils.is_lower_hex_64(entry.get(hash_field)):
				return Utils.failure("BRIDGE2_B_INVALID_ENTRY_HASH", {"representation_id": representation_id, "field": hash_field})
		if String(entry["representation_kind"]) == "FULL":
			if String(entry["physical_artifact_checksum"]) != "" or String(entry["underlying_physical_artifact_checksum"]) != "":
				return Utils.failure("BRIDGE2_B_FULL_MUST_NOT_PRETEND_BAKE_ARTIFACT", {"representation_id": representation_id})
		else:
			if not Utils.is_lower_hex_64(entry.get("physical_artifact_checksum")):
				return Utils.failure("BRIDGE2_B_PHYSICAL_ARTIFACT_REQUIRED", {"representation_id": representation_id})
			if not Utils.is_lower_hex_64(entry.get("underlying_physical_artifact_checksum")):
				return Utils.failure("BRIDGE2_B_UNDERLYING_ARTIFACT_REQUIRED", {"representation_id": representation_id})
		if String(entry["witness_hash"]) != Utils.canonical_hash(_entry_identity(entry)):
			return Utils.failure("BRIDGE2_B_WITNESS_HASH_MISMATCH", {"representation_id": representation_id})
	for representation_id in representation_by_id.keys():
		if not seen.has(representation_id):
			return Utils.failure("BRIDGE2_B_REPRESENTATION_WITNESS_MISSING", {"representation_id": representation_id})
	if not Utils.is_lower_hex_64(value.get("subject_hash")) or String(value["subject_hash"]) != Utils.canonical_hash(_identity(value)):
		return Utils.failure("BRIDGE2_B_SUBJECT_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func _build_entry(ownership_contract: Dictionary, witness: Dictionary) -> Dictionary:
	for field in ["representation_id", "region_id", "representation_kind", "payload"]:
		if not witness.has(field):
			return Utils.failure("BRIDGE2_B_WITNESS_FIELD_MISSING", {"field": field})
	var representation_id := String(witness["representation_id"])
	var region_id := String(witness["region_id"])
	var representation_kind := String(witness["representation_kind"])
	var expected_kind := ""
	for representation in ownership_contract["representations"]:
		if String(representation["representation_id"]) == representation_id:
			expected_kind = String(representation["representation_kind"])
			break
	if expected_kind.is_empty():
		return Utils.failure("BRIDGE2_B_WITNESS_UNKNOWN_REPRESENTATION", {"representation_id": representation_id})
	if representation_kind != expected_kind:
		return Utils.failure("BRIDGE2_B_WITNESS_REPRESENTATION_KIND_MISMATCH", {"representation_id": representation_id})
	if Ownership.active_owner_for_region(ownership_contract, region_id) != representation_id:
		return Utils.failure("BRIDGE2_B_WITNESS_NOT_ACTIVE_OWNER", {"representation_id": representation_id, "region_id": region_id})
	var details: Dictionary
	match representation_kind:
		"FULL":
			details = _full_witness(witness["payload"])
		"STRUCTURAL_BAKE":
			details = _structural_witness(witness["payload"])
		"CONTACT_BAKE":
			details = _contact_witness(witness["payload"])
		"DYNAMIC_ROM":
			details = _dynamic_witness(witness["payload"])
		"HYBRID_BAKE":
			details = _hybrid_witness(witness["payload"])
		_:
			return Utils.failure("BRIDGE2_B_UNSUPPORTED_WITNESS_KIND")
	if not bool(details.get("success", false)):
		return details
	var frontier_hash := String(ownership_contract["canonical_source_frontier"]["frontier_hash"])
	var authority_binding := String(ownership_contract["authority_envelope"]["authority_epoch_binding"])
	if String(details["details"]["source_frontier_hash"]) != frontier_hash:
		return Utils.failure("BRIDGE2_B_WITNESS_FRONTIER_MISMATCH", {"representation_id": representation_id})
	if String(details["details"]["authority_epoch_binding"]) != authority_binding:
		return Utils.failure("BRIDGE2_B_WITNESS_AUTHORITY_MISMATCH", {"representation_id": representation_id})
	var entry: Dictionary = {
		"representation_id": representation_id,
		"representation_kind": representation_kind,
		"region_id": region_id,
		"ownership_role": "ACTIVE_EXECUTION",
		"witness_kind": WITNESS_KINDS[representation_kind],
		"source_frontier_hash": frontier_hash,
		"authority_epoch_binding": authority_binding,
		"physical_artifact_checksum": String(details["details"].get("physical_artifact_checksum", "")),
		"execution_identity_hash": String(details["details"]["execution_identity_hash"]),
		"runtime_state_hash": String(details["details"]["runtime_state_hash"]),
		"underlying_physical_artifact_checksum": String(details["details"].get("underlying_physical_artifact_checksum", details["details"].get("physical_artifact_checksum", ""))),
		"witness_hash": "",
	}
	entry["witness_hash"] = Utils.canonical_hash(_entry_identity(entry))
	return Utils.success({"entry": entry})

static func _full_witness(payload: Dictionary) -> Dictionary:
	if typeof(payload.get("full_model")) != TYPE_DICTIONARY or typeof(payload.get("execution")) != TYPE_DICTIONARY:
		return Utils.failure("BRIDGE2_B_FULL_WITNESS_INCOMPLETE")
	var model: Dictionary = payload["full_model"]
	var checked := FullModel.validate(model)
	if not bool(checked.get("success", false)):
		return checked
	var execution: Dictionary = payload["execution"]
	if not bool(execution.get("success", false)) or typeof(execution.get("state")) != TYPE_DICTIONARY:
		return Utils.failure("BRIDGE2_B_FULL_EXECUTION_NOT_SUCCESSFUL")
	checked = FullState.validate(execution["state"])
	if not bool(checked.get("success", false)):
		return checked
	if String(execution["state"]["model_hash"]) != String(model["model_hash"]):
		return Utils.failure("BRIDGE2_B_FULL_EXECUTION_MODEL_MISMATCH")
	return Utils.success({
		"source_frontier_hash": String(model["source_binding"]["frontier_hash"]),
		"authority_epoch_binding": String(model["source_binding"]["authority_envelope"]["authority_epoch_binding"]),
		"execution_identity_hash": String(model["model_hash"]),
		"runtime_state_hash": String(execution["state"]["checksum"]),
		"physical_artifact_checksum": "",
		"underlying_physical_artifact_checksum": "",
	})

static func _structural_witness(payload: Dictionary) -> Dictionary:
	if typeof(payload.get("bundle")) != TYPE_DICTIONARY or typeof(payload.get("execution")) != TYPE_DICTIONARY:
		return Utils.failure("BRIDGE2_B_STRUCTURAL_WITNESS_INCOMPLETE")
	var bundle: Dictionary = payload["bundle"]
	if String(bundle.get("kind", "")) != "BRIDGE1_PHYSICAL_SOURCE_LIFECYCLE_BUNDLE":
		return Utils.failure("BRIDGE2_B_STRUCTURAL_BUNDLE_KIND_MISMATCH")
	var checked := PhysicalArtifact.validate(bundle.get("artifact", {}))
	if not bool(checked.get("success", false)):
		return checked
	var execution: Dictionary = payload["execution"]
	if not bool(execution.get("success", false)) or String(execution.get("status", "")) != "BRIDGE1_EXECUTED":
		return Utils.failure("BRIDGE2_B_STRUCTURAL_EXECUTION_NOT_SUCCESSFUL")
	if String(execution.get("artifact_hash", "")) != String(bundle["artifact"]["checksum"]):
		return Utils.failure("BRIDGE2_B_STRUCTURAL_EXECUTION_ARTIFACT_MISMATCH")
	return Utils.success({
		"source_frontier_hash": String(bundle["artifact"]["source_binding"]["frontier_hash"]),
		"authority_epoch_binding": String(bundle["artifact"]["source_binding"]["authority_envelope"]["authority_epoch_binding"]),
		"execution_identity_hash": String(bundle["artifact"]["checksum"]),
		"runtime_state_hash": Utils.canonical_hash(execution),
		"physical_artifact_checksum": String(bundle["artifact"]["checksum"]),
	})

static func _contact_witness(payload: Dictionary) -> Dictionary:
	if typeof(payload.get("parent_bundle")) != TYPE_DICTIONARY or typeof(payload.get("bundle")) != TYPE_DICTIONARY or typeof(payload.get("execution")) != TYPE_DICTIONARY:
		return Utils.failure("BRIDGE2_B_CONTACT_WITNESS_INCOMPLETE")
	var parent: Dictionary = payload["parent_bundle"]
	var bundle: Dictionary = payload["bundle"]
	var checked := PhysicalArtifact.validate(bundle.get("artifact", {}))
	if not bool(checked.get("success", false)):
		return checked
	var gate := ContactBridge.can_execute(parent, bundle)
	if not bool(gate.get("ok", false)):
		return Utils.failure("BRIDGE2_B_CONTACT_GATE_FAILED", {"gate": gate})
	var execution: Dictionary = payload["execution"]
	if not bool(execution.get("ok", false)) or String(execution.get("artifact_id", "")) != String(bundle["artifact"]["artifact_id"]):
		return Utils.failure("BRIDGE2_B_CONTACT_EXECUTION_NOT_SUCCESSFUL")
	return Utils.success({
		"source_frontier_hash": String(bundle["artifact"]["source_binding"]["frontier_hash"]),
		"authority_epoch_binding": String(bundle["artifact"]["source_binding"]["authority_envelope"]["authority_epoch_binding"]),
		"execution_identity_hash": String(bundle["artifact"]["checksum"]),
		"runtime_state_hash": Utils.canonical_hash(execution),
		"physical_artifact_checksum": String(bundle["artifact"]["checksum"]),
	})

static func _dynamic_witness(payload: Dictionary) -> Dictionary:
	for field in ["full_model", "rom_descriptor", "reduction_binding", "certification", "bundle", "session"]:
		if typeof(payload.get(field)) != TYPE_DICTIONARY:
			return Utils.failure("BRIDGE2_B_DYNAMIC_WITNESS_INCOMPLETE", {"field": field})
	var bundle: Dictionary = payload["bundle"]
	var checked := DynamicBridge.validate(bundle, payload["full_model"], payload["rom_descriptor"], payload["reduction_binding"], payload["certification"])
	if not bool(checked.get("success", false)):
		return checked
	checked = DynamicExecution.validate(payload["session"], bundle["execution_artifact"])
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({
		"source_frontier_hash": String(bundle["physical_artifact"]["source_binding"]["frontier_hash"]),
		"authority_epoch_binding": String(bundle["physical_artifact"]["source_binding"]["authority_envelope"]["authority_epoch_binding"]),
		"execution_identity_hash": String(bundle["execution_artifact"]["artifact_hash"]),
		"runtime_state_hash": String(payload["session"]["checksum"]),
		"physical_artifact_checksum": String(bundle["physical_artifact"]["checksum"]),
	})

static func _hybrid_witness(payload: Dictionary) -> Dictionary:
	if typeof(payload.get("package")) != TYPE_DICTIONARY or typeof(payload.get("session")) != TYPE_DICTIONARY:
		return Utils.failure("BRIDGE2_B_HYBRID_WITNESS_INCOMPLETE")
	var package: Dictionary = payload["package"]
	var checked := HybridRuntime.validate_package(package)
	if not bool(checked.get("success", false)):
		return checked
	checked = HybridRuntime.validate_session(payload["session"], package)
	if not bool(checked.get("success", false)):
		return checked
	var physical: Dictionary = package["physical_bundle"]["physical_artifact"]
	return Utils.success({
		"source_frontier_hash": String(physical["source_binding"]["frontier_hash"]),
		"authority_epoch_binding": String(physical["source_binding"]["authority_envelope"]["authority_epoch_binding"]),
		"execution_identity_hash": String(package["package_hash"]),
		"runtime_state_hash": String(payload["session"]["checksum"]),
		"physical_artifact_checksum": String(physical["checksum"]),
		"underlying_physical_artifact_checksum": String(physical["checksum"]),
	})

static func _entry_identity(entry: Dictionary) -> Dictionary:
	var payload := entry.duplicate(true)
	payload.erase("witness_hash")
	return payload

static func _identity(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("subject_hash")
	payload.erase("checksum")
	return payload
