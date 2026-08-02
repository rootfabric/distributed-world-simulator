extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const JournalRecord = preload("res://scripts/simulation/matter/handoff/durable/matter_handoff_journal_record.gd")

var _applied_record_checksums: Dictionary = {}


func project(adapter, record: Dictionary) -> Dictionary:
	if adapter == null:
		return MatterUtils.failure("MATTER_HANDOFF_RUNTIME_ADAPTER_REQUIRED")
	var checked: Dictionary = JournalRecord.validate(record)
	if not bool(checked.get("success", false)):
		return checked
	var transfer_id: String = String(record["transfer_id"])
	var checksum: String = String(record["checksum"])
	if String(_applied_record_checksums.get(transfer_id, "")) == checksum:
		return MatterUtils.success({"replay": true, "phase": record["phase"]})
	var method_name: String = _method_for_phase(String(record["phase"]))
	if method_name.is_empty() or not adapter.has_method(method_name):
		return MatterUtils.failure("MATTER_HANDOFF_RUNTIME_ADAPTER_METHOD_MISSING", {
			"method": method_name,
			"phase": record["phase"],
		})
	var result = adapter.call(method_name, record.duplicate(true))
	if typeof(result) != TYPE_DICTIONARY:
		return MatterUtils.failure("MATTER_HANDOFF_RUNTIME_ADAPTER_INVALID_RESULT")
	var applied: Dictionary = result
	if not bool(applied.get("success", false)):
		return applied
	_applied_record_checksums[transfer_id] = checksum
	return MatterUtils.success({"replay": false, "phase": record["phase"], "adapter_result": applied})


func applied_checksum(transfer_id: String) -> String:
	return String(_applied_record_checksums.get(transfer_id.strip_edges().to_lower(), ""))


func _method_for_phase(phase: String) -> String:
	match phase:
		JournalRecord.PHASE_BEGIN:
			return "freeze_handoff"
		JournalRecord.PHASE_PACKAGE_DURABLE:
			return "persist_handoff_package"
		JournalRecord.PHASE_TARGET_PREPARED:
			return "prepare_handoff_target"
		JournalRecord.PHASE_COMMIT_DECIDED, JournalRecord.PHASE_COMMITTED:
			return "commit_handoff"
		JournalRecord.PHASE_ABORT_DECIDED, JournalRecord.PHASE_ABORTED:
			return "abort_handoff"
	return ""
