extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Lease = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_authority_lease.gd")
const JournalRecord = preload("res://scripts/simulation/matter/handoff/durable/matter_handoff_journal_record.gd")

const SCHEMA := "planet_simulator.matter_durable_handoff_checkpoint.v1"
const FIELDS: Array[String] = [
	"schema", "checkpoint_id", "generation", "server_tick", "directory_revision",
	"previous_checkpoint_checksum", "leases", "handoff_records", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var leases: Array = Array(data.get("leases", [])).duplicate(true)
	leases.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("region_id", "")) < String(b.get("region_id", ""))
	)
	var records: Array = Array(data.get("handoff_records", [])).duplicate(true)
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_transfer: String = String(a.get("transfer_id", ""))
		var b_transfer: String = String(b.get("transfer_id", ""))
		if a_transfer == b_transfer:
			return int(a.get("record_sequence", 0)) < int(b.get("record_sequence", 0))
		return a_transfer < b_transfer
	)
	var value: Dictionary = {
		"schema": SCHEMA,
		"checkpoint_id": String(data.get("checkpoint_id", "")).strip_edges().to_lower(),
		"generation": int(data.get("generation", 0)),
		"server_tick": int(data.get("server_tick", 0)),
		"directory_revision": int(data.get("directory_revision", 0)),
		"previous_checkpoint_checksum": String(data.get("previous_checkpoint_checksum", "")).strip_edges().to_lower(),
		"leases": leases,
		"handoff_records": records,
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_DURABLE_HANDOFF_CHECKPOINT_SCHEMA")
	if not MatterUtils.is_canonical_id(value.get("checkpoint_id"), 2):
		return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_CHECKPOINT_ID")
	for field in ["generation", "server_tick", "directory_revision"]:
		if not MatterUtils.is_json_integer(value.get(field)):
			return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_CHECKPOINT_INTEGER", {"field": field})
	if int(value["generation"]) < 1 or int(value["server_tick"]) < 0 or int(value["directory_revision"]) < 1:
		return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_CHECKPOINT_FRONTIER")
	var previous_checksum: String = String(value.get("previous_checkpoint_checksum", ""))
	if int(value["generation"]) == 1:
		if not previous_checksum.is_empty():
			return MatterUtils.failure("FIRST_MATTER_DURABLE_HANDOFF_CHECKPOINT_HAS_PREVIOUS")
	elif not MatterUtils.is_lower_hex_64(previous_checksum):
		return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_PREVIOUS_CHECKSUM")
	if typeof(value.get("leases")) != TYPE_ARRAY or value["leases"].is_empty():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LEASES_REQUIRED")
	var leases_by_region: Dictionary = {}
	var active_transfer_to_region: Dictionary = {}
	var previous_region_id: String = ""
	for index in range(value["leases"].size()):
		var raw_lease = value["leases"][index]
		if typeof(raw_lease) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_LEASE", {"index": index})
		var lease: Dictionary = raw_lease
		checked = Lease.validate(lease)
		if not bool(checked.get("success", false)):
			return checked
		var region_id: String = String(lease["region_id"])
		if index > 0 and region_id <= previous_region_id:
			return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LEASES_NOT_SORTED_UNIQUE")
		previous_region_id = region_id
		leases_by_region[region_id] = lease
		if String(lease["status"]) == Lease.STATUS_PREPARING:
			var transfer_id: String = String(lease["active_transfer_id"])
			if active_transfer_to_region.has(transfer_id):
				return MatterUtils.failure("MATTER_DURABLE_HANDOFF_TRANSFER_USED_BY_MULTIPLE_REGIONS")
			active_transfer_to_region[transfer_id] = region_id
	if typeof(value.get("handoff_records")) != TYPE_ARRAY:
		return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_RECORDS")
	var latest_by_transfer: Dictionary = {}
	var previous_by_transfer: Dictionary = {}
	var previous_sort_key: String = ""
	for index in range(value["handoff_records"].size()):
		var raw_record = value["handoff_records"][index]
		if typeof(raw_record) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_RECORD", {"index": index})
		var record: Dictionary = raw_record
		checked = JournalRecord.validate(record)
		if not bool(checked.get("success", false)):
			return checked
		var sort_key: String = "%s/%012d" % [String(record["transfer_id"]), int(record["record_sequence"])]
		if index > 0 and sort_key <= previous_sort_key:
			return MatterUtils.failure("MATTER_DURABLE_HANDOFF_RECORDS_NOT_SORTED_UNIQUE")
		previous_sort_key = sort_key
		var transfer_id: String = String(record["transfer_id"])
		if previous_by_transfer.has(transfer_id):
			checked = JournalRecord.validate_progression(record, previous_by_transfer[transfer_id])
			if not bool(checked.get("success", false)):
				return checked
		elif int(record["record_sequence"]) != 1:
			return MatterUtils.failure("MATTER_DURABLE_HANDOFF_RECORD_CHAIN_MISSING_BEGIN")
		previous_by_transfer[transfer_id] = record
		latest_by_transfer[transfer_id] = record
		if not leases_by_region.has(String(record["region_id"])):
			return MatterUtils.failure("MATTER_DURABLE_HANDOFF_RECORD_REGION_MISSING")
	for transfer_id in latest_by_transfer:
		var record: Dictionary = latest_by_transfer[transfer_id]
		var terminal: bool = String(record["phase"]) in [JournalRecord.PHASE_COMMITTED, JournalRecord.PHASE_ABORTED]
		if terminal:
			if active_transfer_to_region.has(transfer_id):
				return MatterUtils.failure("TERMINAL_MATTER_HANDOFF_REMAINS_ACTIVE")
		else:
			if not active_transfer_to_region.has(transfer_id) \
				or String(active_transfer_to_region[transfer_id]) != String(record["region_id"]):
				return MatterUtils.failure("INCOMPLETE_MATTER_HANDOFF_HAS_NO_PREPARING_LEASE")
			var preparing_lease: Dictionary = leases_by_region[String(record["region_id"])]
			if String(preparing_lease["source_owner_id"]) != String(record["source_owner_id"]) \
				or String(preparing_lease["target_owner_id"]) != String(record["target_owner_id"]) \
				or int(preparing_lease["authority_epoch"]) != int(record["source_authority_epoch"]) \
				or int(preparing_lease["lease_revision"]) != int(record["frozen_lease_revision"]):
				return MatterUtils.failure("MATTER_DURABLE_HANDOFF_LEASE_RECORD_BINDING_MISMATCH")
	for transfer_id in active_transfer_to_region:
		if not latest_by_transfer.has(transfer_id):
			return MatterUtils.failure("PREPARING_MATTER_DURABLE_LEASE_HAS_NO_JOURNAL")
	return MatterUtils.validate_checksum(value)


static func validate_progression(current: Dictionary, previous: Dictionary) -> Dictionary:
	var checked: Dictionary = validate(previous)
	if not bool(checked.get("success", false)):
		return checked
	checked = validate(current)
	if not bool(checked.get("success", false)):
		return checked
	if String(current["checkpoint_id"]) != String(previous["checkpoint_id"]):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_ID_CHANGED")
	if int(current["generation"]) != int(previous["generation"]) + 1 \
		or String(current["previous_checkpoint_checksum"]) != String(previous["checksum"]):
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_CHAIN_MISMATCH")
	if int(current["server_tick"]) < int(previous["server_tick"]) \
		or int(current["directory_revision"]) != int(previous["directory_revision"]) + 1:
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_CHECKPOINT_FRONTIER_ROLLBACK")
	var previous_leases: Dictionary = _leases_by_region(previous["leases"])
	var current_leases: Dictionary = _leases_by_region(current["leases"])
	if current_leases.size() != previous_leases.size():
		return MatterUtils.failure("MATTER_DURABLE_AUTHORITY_REGION_SET_CHANGED")
	var latest_records: Dictionary = _latest_records(current["handoff_records"])
	for region_id in previous_leases:
		if not current_leases.has(region_id):
			return MatterUtils.failure("MATTER_DURABLE_AUTHORITY_REGION_REMOVED")
		var old_lease: Dictionary = previous_leases[region_id]
		var new_lease: Dictionary = current_leases[region_id]
		if new_lease == old_lease:
			continue
		if int(new_lease["lease_revision"]) != int(old_lease["lease_revision"]) + 1:
			return MatterUtils.failure("MATTER_DURABLE_AUTHORITY_LEASE_REVISION_NOT_CONTIGUOUS")
		var old_status: String = String(old_lease["status"])
		var new_status: String = String(new_lease["status"])
		if old_status == Lease.STATUS_ACTIVE:
			if new_status == Lease.STATUS_PREPARING:
				if int(current["server_tick"]) >= int(old_lease["expires_at_tick"]) \
					or String(new_lease["owner_id"]) != String(old_lease["owner_id"]) \
					or int(new_lease["authority_epoch"]) != int(old_lease["authority_epoch"]):
					return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_FREEZE_TRANSITION")
				var transfer_id: String = String(new_lease["active_transfer_id"])
				if not latest_records.has(transfer_id):
					return MatterUtils.failure("MATTER_DURABLE_HANDOFF_FREEZE_RECORD_MISSING")
				var begin_record: Dictionary = latest_records[transfer_id]
				if String(begin_record["phase"]) != JournalRecord.PHASE_BEGIN \
					or int(begin_record["frozen_lease_revision"]) != int(new_lease["lease_revision"]) \
					or String(begin_record["source_fencing_token_checksum"]) != String(old_lease["fencing_token"]["checksum"]):
					return MatterUtils.failure("MATTER_DURABLE_HANDOFF_FREEZE_RECORD_MISMATCH")
			elif new_status == Lease.STATUS_ACTIVE:
				var same_epoch_renewal: bool = int(new_lease["authority_epoch"]) == int(old_lease["authority_epoch"]) \
					and String(new_lease["owner_id"]) == String(old_lease["owner_id"])
				if same_epoch_renewal:
					if int(current["server_tick"]) < int(old_lease["renew_after_tick"]) \
						or int(current["server_tick"]) >= int(old_lease["expires_at_tick"]):
						return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_RENEWAL_TIME")
				else:
					if int(new_lease["authority_epoch"]) != int(old_lease["authority_epoch"]) + 1 \
						or int(current["server_tick"]) < int(old_lease["expires_at_tick"]):
						return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_EXPIRED_CLAIM")
			else:
				return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_ACTIVE_TRANSITION")
		elif old_status == Lease.STATUS_PREPARING:
			if new_status != Lease.STATUS_ACTIVE:
				return MatterUtils.failure("INVALID_MATTER_DURABLE_HANDOFF_TERMINAL_TRANSITION")
			var transfer_id: String = String(old_lease["active_transfer_id"])
			if not latest_records.has(transfer_id):
				return MatterUtils.failure("MATTER_DURABLE_HANDOFF_TERMINAL_RECORD_MISSING")
			var terminal: Dictionary = latest_records[transfer_id]
			if String(terminal["phase"]) == JournalRecord.PHASE_COMMITTED:
				if String(new_lease["owner_id"]) != String(old_lease["target_owner_id"]) \
					or int(new_lease["authority_epoch"]) != int(old_lease["authority_epoch"]) + 1:
					return MatterUtils.failure("MATTER_DURABLE_HANDOFF_COMMIT_LEASE_MISMATCH")
			elif String(terminal["phase"]) == JournalRecord.PHASE_ABORTED:
				if String(new_lease["owner_id"]) != String(old_lease["source_owner_id"]) \
					or int(new_lease["authority_epoch"]) != int(old_lease["authority_epoch"]):
					return MatterUtils.failure("MATTER_DURABLE_HANDOFF_ABORT_LEASE_MISMATCH")
			else:
				return MatterUtils.failure("MATTER_DURABLE_HANDOFF_TERMINAL_DECISION_MISSING")
		else:
			return MatterUtils.failure("INVALID_MATTER_DURABLE_AUTHORITY_STATUS_TRANSITION")
	var old_records: Array = previous["handoff_records"]
	var new_records: Array = current["handoff_records"]
	if new_records.size() < old_records.size():
		return MatterUtils.failure("MATTER_DURABLE_HANDOFF_JOURNAL_TRUNCATED")
	for index in range(old_records.size()):
		if old_records[index] != new_records[index]:
			return MatterUtils.failure("MATTER_DURABLE_HANDOFF_JOURNAL_HISTORY_MUTATED")
	return MatterUtils.success()


static func _latest_records(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_record in records:
		var record: Dictionary = raw_record
		result[String(record["transfer_id"])] = record
	return result


static func _leases_by_region(leases: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_lease in leases:
		var lease: Dictionary = raw_lease
		result[String(lease["region_id"])] = lease
	return result
