extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const SummaryManifest = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_persistence_manifest.gd")

const SCHEMA := "planet_simulator.matter_handoff_journal_record.v1"
const PHASE_BEGIN := "BEGIN"
const PHASE_PACKAGE_DURABLE := "PACKAGE_DURABLE"
const PHASE_TARGET_PREPARED := "TARGET_PREPARED"
const PHASE_COMMIT_DECIDED := "COMMIT_DECIDED"
const PHASE_COMMITTED := "COMMITTED"
const PHASE_ABORT_DECIDED := "ABORT_DECIDED"
const PHASE_ABORTED := "ABORTED"
const PHASES: Array[String] = [
	PHASE_BEGIN, PHASE_PACKAGE_DURABLE, PHASE_TARGET_PREPARED,
	PHASE_COMMIT_DECIDED, PHASE_COMMITTED, PHASE_ABORT_DECIDED, PHASE_ABORTED,
]
const DECISION_NONE := "NONE"
const DECISION_COMMIT := "COMMIT"
const DECISION_ABORT := "ABORT"
const DECISIONS: Array[String] = [DECISION_NONE, DECISION_COMMIT, DECISION_ABORT]
const FIELDS: Array[String] = [
	"schema", "transfer_id", "region_id", "source_owner_id", "target_owner_id",
	"source_authority_epoch", "target_authority_epoch", "frozen_lease_revision",
	"source_fencing_token_checksum", "phase", "decision", "record_sequence", "transition_id", "created_tick",
	"package_transport", "package_checksum", "package_transport_hash", "target_state_hash",
	"summary_manifest", "previous_record_checksum", "checksum",
]


static func create_begin(
	transfer_id: String,
	region_id: String,
	source_owner_id: String,
	target_owner_id: String,
	source_authority_epoch: int,
	frozen_lease_revision: int,
	source_fencing_token_checksum: String,
	transition_id: String,
	created_tick: int
) -> Dictionary:
	return _create({
		"transfer_id": transfer_id,
		"region_id": region_id,
		"source_owner_id": source_owner_id,
		"target_owner_id": target_owner_id,
		"source_authority_epoch": source_authority_epoch,
		"target_authority_epoch": source_authority_epoch + 1,
		"frozen_lease_revision": frozen_lease_revision,
		"source_fencing_token_checksum": source_fencing_token_checksum,
		"phase": PHASE_BEGIN,
		"decision": DECISION_NONE,
		"record_sequence": 1,
		"transition_id": transition_id,
		"created_tick": created_tick,
		"package_transport": "",
		"package_checksum": "",
		"package_transport_hash": "",
		"target_state_hash": "",
		"summary_manifest": {},
		"previous_record_checksum": "",
	})


static func advance(
	previous: Dictionary,
	phase: String,
	transition_id: String,
	created_tick: int,
	updates: Dictionary = {}
) -> Dictionary:
	if not bool(validate(previous).get("success", false)):
		return {}
	var data: Dictionary = previous.duplicate(true)
	data["phase"] = phase.strip_edges().to_upper()
	data["record_sequence"] = int(previous["record_sequence"]) + 1
	data["transition_id"] = transition_id
	data["created_tick"] = created_tick
	data["previous_record_checksum"] = String(previous["checksum"])
	data.erase("schema")
	data.erase("checksum")
	for key in updates:
		data[key] = updates[key]
	var created: Dictionary = _create(data)
	if created.is_empty():
		return {}
	return created if bool(validate_progression(created, previous).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_HANDOFF_JOURNAL_RECORD_SCHEMA")
	for field in ["transfer_id", "region_id", "source_owner_id", "target_owner_id", "transition_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_HANDOFF_JOURNAL_ID", {"field": field})
	if String(value["source_owner_id"]) == String(value["target_owner_id"]):
		return MatterUtils.failure("MATTER_HANDOFF_JOURNAL_OWNER_COLLISION")
	for field in [
		"source_authority_epoch", "target_authority_epoch", "frozen_lease_revision",
		"record_sequence", "created_tick",
	]:
		if not MatterUtils.is_json_integer(value.get(field)):
			return MatterUtils.failure("INVALID_MATTER_HANDOFF_JOURNAL_INTEGER", {"field": field})
	if int(value["source_authority_epoch"]) < 1 \
		or int(value["target_authority_epoch"]) != int(value["source_authority_epoch"]) + 1 \
		or int(value["frozen_lease_revision"]) < 2 \
		or int(value["record_sequence"]) < 1 or int(value["created_tick"]) < 0:
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_JOURNAL_FRONTIER")
	if not MatterUtils.is_lower_hex_64(value.get("source_fencing_token_checksum")):
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_SOURCE_FENCING_TOKEN_CHECKSUM")
	var phase: String = String(value.get("phase", ""))
	var decision: String = String(value.get("decision", ""))
	if not phase in PHASES or not decision in DECISIONS:
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_JOURNAL_PHASE_OR_DECISION")
	var package_required: bool = phase in [
		PHASE_PACKAGE_DURABLE, PHASE_TARGET_PREPARED, PHASE_COMMIT_DECIDED, PHASE_COMMITTED,
	]
	var package_optional: bool = phase in [PHASE_ABORT_DECIDED, PHASE_ABORTED]
	var package_transport: String = String(value.get("package_transport", ""))
	var package_checksum: String = String(value.get("package_checksum", ""))
	var package_transport_hash: String = String(value.get("package_transport_hash", ""))
	var has_any_package_field: bool = not package_transport.is_empty() \
		or not package_checksum.is_empty() or not package_transport_hash.is_empty()
	var has_complete_package: bool = not package_transport.is_empty() \
		and MatterUtils.is_lower_hex_64(package_checksum) \
		and MatterUtils.is_lower_hex_64(package_transport_hash)
	if package_required and not has_complete_package:
		return MatterUtils.failure("MATTER_HANDOFF_DURABLE_PACKAGE_REQUIRED")
	if not package_required and not package_optional and has_any_package_field:
		return MatterUtils.failure("MATTER_HANDOFF_BEGIN_HAS_PACKAGE")
	if package_optional and has_any_package_field and not has_complete_package:
		return MatterUtils.failure("MATTER_HANDOFF_DURABLE_PACKAGE_PARTIAL")
	if has_complete_package:
		if package_transport_hash != MatterUtils.payload_hash(package_transport):
			return MatterUtils.failure("MATTER_HANDOFF_PACKAGE_TRANSPORT_HASH_MISMATCH")
		var decoded_package = JSON.parse_string(package_transport)
		if typeof(decoded_package) != TYPE_DICTIONARY:
			return MatterUtils.failure("MATTER_HANDOFF_PACKAGE_TRANSPORT_NOT_OBJECT")
		var package_value: Dictionary = decoded_package
		if MatterUtils.canonical_json(package_value) != package_transport:
			return MatterUtils.failure("MATTER_HANDOFF_PACKAGE_TRANSPORT_NOT_CANONICAL")
		if String(package_value.get("checksum", "")) != package_checksum \
			or MatterUtils.compute_checksum(package_value) != package_checksum:
			return MatterUtils.failure("MATTER_HANDOFF_PACKAGE_CHECKSUM_BINDING_MISMATCH")
	var target_hash_required: bool = phase in [
		PHASE_TARGET_PREPARED, PHASE_COMMIT_DECIDED, PHASE_COMMITTED,
	]
	var target_hash_optional: bool = phase in [PHASE_ABORT_DECIDED, PHASE_ABORTED]
	var target_state_hash: String = String(value.get("target_state_hash", ""))
	var has_target_hash: bool = not target_state_hash.is_empty()
	if target_hash_required and not MatterUtils.is_lower_hex_64(target_state_hash):
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_TARGET_STATE_HASH")
	if not target_hash_required and not target_hash_optional and has_target_hash:
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_TARGET_STATE_HASH")
	if target_hash_optional and has_target_hash and not MatterUtils.is_lower_hex_64(target_state_hash):
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_TARGET_STATE_HASH")
	if typeof(value.get("summary_manifest")) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_SUMMARY_MANIFEST")
	var summary_manifest: Dictionary = value["summary_manifest"]
	if not summary_manifest.is_empty():
		checked = SummaryManifest.validate(summary_manifest)
		if not bool(checked.get("success", false)):
			return checked
		if not has_complete_package:
			return MatterUtils.failure("MATTER_HANDOFF_SUMMARY_REQUIRES_DURABLE_PACKAGE")
	if int(value["record_sequence"]) == 1:
		if phase != PHASE_BEGIN or not String(value["previous_record_checksum"]).is_empty():
			return MatterUtils.failure("INVALID_MATTER_HANDOFF_INITIAL_RECORD")
	elif not MatterUtils.is_lower_hex_64(value.get("previous_record_checksum")):
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_PREVIOUS_RECORD_CHECKSUM")
	match phase:
		PHASE_BEGIN, PHASE_PACKAGE_DURABLE, PHASE_TARGET_PREPARED:
			if decision != DECISION_NONE:
				return MatterUtils.failure("MATTER_HANDOFF_PREDECISION_RECORD_HAS_DECISION")
		PHASE_COMMIT_DECIDED, PHASE_COMMITTED:
			if decision != DECISION_COMMIT:
				return MatterUtils.failure("MATTER_HANDOFF_COMMIT_RECORD_DECISION_MISMATCH")
		PHASE_ABORT_DECIDED, PHASE_ABORTED:
			if decision != DECISION_ABORT:
				return MatterUtils.failure("MATTER_HANDOFF_ABORT_RECORD_DECISION_MISMATCH")
	return MatterUtils.validate_checksum(value)


static func validate_progression(current: Dictionary, previous: Dictionary) -> Dictionary:
	var checked: Dictionary = validate(previous)
	if not bool(checked.get("success", false)):
		return checked
	checked = validate(current)
	if not bool(checked.get("success", false)):
		return checked
	for field in [
		"transfer_id", "region_id", "source_owner_id", "target_owner_id",
		"source_authority_epoch", "target_authority_epoch", "frozen_lease_revision",
		"source_fencing_token_checksum",
	]:
		if current[field] != previous[field]:
			return MatterUtils.failure("MATTER_HANDOFF_JOURNAL_IDENTITY_CHANGED", {"field": field})
	if int(current["record_sequence"]) != int(previous["record_sequence"]) + 1 \
		or String(current["previous_record_checksum"]) != String(previous["checksum"]) \
		or int(current["created_tick"]) < int(previous["created_tick"]):
		return MatterUtils.failure("MATTER_HANDOFF_JOURNAL_CHAIN_MISMATCH")
	var allowed: Dictionary = {
		PHASE_BEGIN: [PHASE_PACKAGE_DURABLE, PHASE_ABORT_DECIDED],
		PHASE_PACKAGE_DURABLE: [PHASE_TARGET_PREPARED, PHASE_ABORT_DECIDED],
		PHASE_TARGET_PREPARED: [PHASE_COMMIT_DECIDED, PHASE_ABORT_DECIDED],
		PHASE_COMMIT_DECIDED: [PHASE_COMMITTED],
		PHASE_ABORT_DECIDED: [PHASE_ABORTED],
		PHASE_COMMITTED: [],
		PHASE_ABORTED: [],
	}
	if not String(current["phase"]) in Array(allowed[String(previous["phase"])]):
		return MatterUtils.failure("INVALID_MATTER_HANDOFF_JOURNAL_TRANSITION")
	if String(previous["package_transport"]) != "" \
		and (String(current["package_transport"]) != String(previous["package_transport"]) \
		or String(current["package_checksum"]) != String(previous["package_checksum"]) \
		or Dictionary(current["summary_manifest"]) != Dictionary(previous["summary_manifest"])):
		return MatterUtils.failure("MATTER_HANDOFF_DURABLE_PACKAGE_MUTATED")
	if String(previous["target_state_hash"]) != "" \
		and String(current["target_state_hash"]) != String(previous["target_state_hash"]):
		return MatterUtils.failure("MATTER_HANDOFF_TARGET_STATE_HASH_MUTATED")
	return MatterUtils.success()


static func _create(data: Dictionary) -> Dictionary:
	var phase: String = String(data.get("phase", "")).strip_edges().to_upper()
	var package_transport: String = String(data.get("package_transport", ""))
	var value: Dictionary = {
		"schema": SCHEMA,
		"transfer_id": String(data.get("transfer_id", "")).strip_edges().to_lower(),
		"region_id": String(data.get("region_id", "")).strip_edges().to_lower(),
		"source_owner_id": String(data.get("source_owner_id", "")).strip_edges().to_lower(),
		"target_owner_id": String(data.get("target_owner_id", "")).strip_edges().to_lower(),
		"source_authority_epoch": int(data.get("source_authority_epoch", 0)),
		"target_authority_epoch": int(data.get("target_authority_epoch", 0)),
		"frozen_lease_revision": int(data.get("frozen_lease_revision", 0)),
		"source_fencing_token_checksum": String(data.get("source_fencing_token_checksum", "")).strip_edges().to_lower(),
		"phase": phase,
		"decision": String(data.get("decision", _decision_for_phase(phase))).strip_edges().to_upper(),
		"record_sequence": int(data.get("record_sequence", 0)),
		"transition_id": String(data.get("transition_id", "")).strip_edges().to_lower(),
		"created_tick": int(data.get("created_tick", 0)),
		"package_transport": package_transport,
		"package_checksum": String(data.get("package_checksum", "")).strip_edges().to_lower(),
		"package_transport_hash": MatterUtils.payload_hash(package_transport) if not package_transport.is_empty() else "",
		"target_state_hash": String(data.get("target_state_hash", "")).strip_edges().to_lower(),
		"summary_manifest": Dictionary(data.get("summary_manifest", {})).duplicate(true),
		"previous_record_checksum": String(data.get("previous_record_checksum", "")).strip_edges().to_lower(),
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func _decision_for_phase(phase: String) -> String:
	if phase in [PHASE_COMMIT_DECIDED, PHASE_COMMITTED]:
		return DECISION_COMMIT
	if phase in [PHASE_ABORT_DECIDED, PHASE_ABORTED]:
		return DECISION_ABORT
	return DECISION_NONE
