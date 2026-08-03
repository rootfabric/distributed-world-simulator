extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Record = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_record.gd")
const Reservation = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_reservation.gd")
const OperationResult = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_operation_result.gd")
const OutboxRecord = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_invalidation_outbox_record.gd")

const SCHEMA := "planet_simulator.matter_cross_region_transaction_checkpoint.v1"
const FIELDS: Array[String] = [
	"schema", "checkpoint_id", "generation", "server_tick", "previous_checkpoint_checksum",
	"transaction_records", "region_reservations", "operation_results", "invalidation_outbox", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var records: Array = Array(data.get("transaction_records", [])).duplicate(true)
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_id: String = String(a.get("transaction_id", ""))
		var b_id: String = String(b.get("transaction_id", ""))
		if a_id == b_id:
			return int(a.get("record_sequence", 0)) < int(b.get("record_sequence", 0))
		return a_id < b_id
	)
	var reservations: Array = Array(data.get("region_reservations", [])).duplicate(true)
	reservations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("region_id", "")) < String(b.get("region_id", ""))
	)
	var results: Array = Array(data.get("operation_results", [])).duplicate(true)
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("operation_id", "")) < String(b.get("operation_id", ""))
	)
	var outbox: Array = Array(data.get("invalidation_outbox", [])).duplicate(true)
	outbox.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("outbox_id", "")) < String(b.get("outbox_id", ""))
	)
	var value: Dictionary = {
		"schema": SCHEMA,
		"checkpoint_id": String(data.get("checkpoint_id", "")).strip_edges().to_lower(),
		"generation": int(data.get("generation", 0)),
		"server_tick": int(data.get("server_tick", 0)),
		"previous_checkpoint_checksum": String(data.get("previous_checkpoint_checksum", "")).strip_edges().to_lower(),
		"transaction_records": records,
		"region_reservations": reservations,
		"operation_results": results,
		"invalidation_outbox": outbox,
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_CROSS_REGION_TRANSACTION_CHECKPOINT_SCHEMA")
	if not MatterUtils.is_canonical_id(value.get("checkpoint_id"), 2):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_CHECKPOINT_ID")
	for field in ["generation", "server_tick"]:
		if not MatterUtils.is_json_integer(value.get(field)):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_CHECKPOINT_INTEGER", {"field": field})
	if int(value["generation"]) < 1 or int(value["server_tick"]) < 0:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_CHECKPOINT_FRONTIER")
	var previous_checksum: String = String(value.get("previous_checkpoint_checksum", ""))
	if int(value["generation"]) == 1:
		if not previous_checksum.is_empty():
			return MatterUtils.failure("FIRST_MATTER_CROSS_REGION_CHECKPOINT_HAS_PREVIOUS")
	elif not MatterUtils.is_lower_hex_64(previous_checksum):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PREVIOUS_CHECKPOINT_CHECKSUM")
	if typeof(value.get("transaction_records")) != TYPE_ARRAY \
		or typeof(value.get("region_reservations")) != TYPE_ARRAY \
		or typeof(value.get("operation_results")) != TYPE_ARRAY \
		or typeof(value.get("invalidation_outbox")) != TYPE_ARRAY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_CHECKPOINT_COLLECTION")
	var latest_by_transaction: Dictionary = {}
	var previous_by_transaction: Dictionary = {}
	var previous_record_key := ""
	for index in range(value["transaction_records"].size()):
		var raw_record = value["transaction_records"][index]
		if typeof(raw_record) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_CHECKPOINT_RECORD")
		checked = Record.validate(raw_record)
		if not bool(checked.get("success", false)):
			return checked
		var record: Dictionary = raw_record
		var key: String = "%s/%012d" % [String(record["transaction_id"]), int(record["record_sequence"])]
		if index > 0 and key <= previous_record_key:
			return MatterUtils.failure("MATTER_CROSS_REGION_RECORDS_NOT_SORTED_UNIQUE")
		previous_record_key = key
		var transaction_id: String = String(record["transaction_id"])
		if previous_by_transaction.has(transaction_id):
			checked = Record.validate_progression(record, previous_by_transaction[transaction_id])
			if not bool(checked.get("success", false)):
				return checked
		elif int(record["record_sequence"]) != 1:
			return MatterUtils.failure("MATTER_CROSS_REGION_RECORD_CHAIN_MISSING_BEGIN")
		previous_by_transaction[transaction_id] = record
		latest_by_transaction[transaction_id] = record
	var reservations_by_region: Dictionary = {}
	var reservations_by_transaction: Dictionary = {}
	var previous_region_id := ""
	for index in range(value["region_reservations"].size()):
		var raw_reservation = value["region_reservations"][index]
		if typeof(raw_reservation) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_CHECKPOINT_RESERVATION")
		checked = Reservation.validate(raw_reservation)
		if not bool(checked.get("success", false)):
			return checked
		var reservation: Dictionary = raw_reservation
		var region_id: String = String(reservation["region_id"])
		if index > 0 and region_id <= previous_region_id:
			return MatterUtils.failure("MATTER_CROSS_REGION_RESERVATIONS_NOT_SORTED_UNIQUE")
		previous_region_id = region_id
		reservations_by_region[region_id] = reservation
		var transaction_id: String = String(reservation["transaction_id"])
		if not reservations_by_transaction.has(transaction_id):
			reservations_by_transaction[transaction_id] = []
		reservations_by_transaction[transaction_id].append(region_id)
	var results_by_operation: Dictionary = {}
	var results_by_transaction: Dictionary = {}
	var previous_operation_id := ""
	for index in range(value["operation_results"].size()):
		var raw_result = value["operation_results"][index]
		if typeof(raw_result) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_CHECKPOINT_RESULT")
		checked = OperationResult.validate(raw_result)
		if not bool(checked.get("success", false)):
			return checked
		var result: Dictionary = raw_result
		var operation_id: String = String(result["operation_id"])
		if index > 0 and operation_id <= previous_operation_id:
			return MatterUtils.failure("MATTER_CROSS_REGION_RESULTS_NOT_SORTED_UNIQUE")
		previous_operation_id = operation_id
		if results_by_transaction.has(String(result["transaction_id"])):
			return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_HAS_MULTIPLE_RESULTS")
		results_by_operation[operation_id] = result
		results_by_transaction[String(result["transaction_id"])] = result
	var outbox_by_transaction: Dictionary = {}
	var previous_outbox_id := ""
	for index in range(value["invalidation_outbox"].size()):
		var raw_outbox = value["invalidation_outbox"][index]
		if typeof(raw_outbox) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_CHECKPOINT_OUTBOX")
		checked = OutboxRecord.validate(raw_outbox)
		if not bool(checked.get("success", false)):
			return checked
		var outbox: Dictionary = raw_outbox
		var outbox_id: String = String(outbox["outbox_id"])
		if index > 0 and outbox_id <= previous_outbox_id:
			return MatterUtils.failure("MATTER_CROSS_REGION_OUTBOX_NOT_SORTED_UNIQUE")
		previous_outbox_id = outbox_id
		var transaction_id: String = String(outbox["transaction_id"])
		if outbox_by_transaction.has(transaction_id):
			return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_HAS_MULTIPLE_OUTBOX_RECORDS")
		outbox_by_transaction[transaction_id] = outbox
	for transaction_id in latest_by_transaction:
		var latest: Dictionary = latest_by_transaction[transaction_id]
		var expected_regions: Array[String] = []
		for raw_participant in latest["plan"]["participants"]:
			expected_regions.append(String(raw_participant["region_id"]))
		var reserved_regions: Array = reservations_by_transaction.get(transaction_id, [])
		reserved_regions.sort()
		if Record.is_terminal(latest):
			if not reserved_regions.is_empty():
				return MatterUtils.failure("TERMINAL_MATTER_CROSS_REGION_TRANSACTION_REMAINS_RESERVED")
			if not results_by_transaction.has(transaction_id):
				return MatterUtils.failure("TERMINAL_MATTER_CROSS_REGION_TRANSACTION_RESULT_MISSING")
			var result: Dictionary = results_by_transaction[transaction_id]
			if String(result["terminal_record_checksum"]) != String(latest["checksum"]) \
				or String(result["plan_checksum"]) != String(latest["plan"]["checksum"]):
				return MatterUtils.failure("MATTER_CROSS_REGION_TERMINAL_RESULT_BINDING_MISMATCH")
			if String(latest["phase"]) == Record.PHASE_COMMITTED:
				if String(result["outcome"]) != OperationResult.OUTCOME_COMMITTED \
					or String(result["global_commit_hash"]) != String(latest["global_commit_hash"]) \
					or String(result["invalidation_batch_checksum"]) != String(latest["invalidation_batch"]["checksum"]):
					return MatterUtils.failure("MATTER_CROSS_REGION_COMMITTED_RESULT_MISMATCH")
				if not outbox_by_transaction.has(transaction_id):
					return MatterUtils.failure("MATTER_CROSS_REGION_COMMITTED_OUTBOX_MISSING")
				var outbox: Dictionary = outbox_by_transaction[transaction_id]
				if String(outbox["committed_record_checksum"]) != String(latest["checksum"]) \
					or outbox["invalidation_batch"] != latest["invalidation_batch"]:
					return MatterUtils.failure("MATTER_CROSS_REGION_COMMITTED_OUTBOX_MISMATCH")
			else:
				if String(result["outcome"]) != OperationResult.OUTCOME_ABORTED \
					or outbox_by_transaction.has(transaction_id):
					return MatterUtils.failure("MATTER_CROSS_REGION_ABORTED_RESULT_MISMATCH")
		else:
			if results_by_transaction.has(transaction_id) or outbox_by_transaction.has(transaction_id):
				return MatterUtils.failure("INCOMPLETE_MATTER_CROSS_REGION_TRANSACTION_HAS_TERMINAL_OUTPUT")
			if reserved_regions != expected_regions:
				return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_RESERVATION_SET_MISMATCH")
			for raw_participant in latest["plan"]["participants"]:
				var participant: Dictionary = raw_participant
				var reservation: Dictionary = reservations_by_region[String(participant["region_id"])]
				if String(reservation["participant_checksum"]) != String(participant["checksum"]):
					return MatterUtils.failure("MATTER_CROSS_REGION_RESERVATION_PARTICIPANT_MISMATCH")
	for operation_id in results_by_operation:
		var result: Dictionary = results_by_operation[operation_id]
		if not latest_by_transaction.has(String(result["transaction_id"])):
			return MatterUtils.failure("MATTER_CROSS_REGION_RESULT_TRANSACTION_MISSING")
	return MatterUtils.validate_checksum(value)


static func validate_progression(current: Dictionary, previous: Dictionary) -> Dictionary:
	var checked: Dictionary = validate(previous)
	if not bool(checked.get("success", false)):
		return checked
	checked = validate(current)
	if not bool(checked.get("success", false)):
		return checked
	if String(current["checkpoint_id"]) != String(previous["checkpoint_id"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_CHECKPOINT_ID_CHANGED")
	if int(current["generation"]) != int(previous["generation"]) + 1 \
		or String(current["previous_checkpoint_checksum"]) != String(previous["checksum"]) \
		or int(current["server_tick"]) < int(previous["server_tick"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_CHECKPOINT_CHAIN_MISMATCH")
	var previous_records: Dictionary = _records_by_key(previous["transaction_records"])
	var current_records: Dictionary = _records_by_key(current["transaction_records"])
	if current_records.size() < previous_records.size() or current_records.size() > previous_records.size() + 1:
		return MatterUtils.failure("MATTER_CROSS_REGION_CHECKPOINT_RECORD_COUNT_INVALID")
	for key in previous_records:
		if not current_records.has(key) or current_records[key] != previous_records[key]:
			return MatterUtils.failure("MATTER_CROSS_REGION_CHECKPOINT_RECORD_HISTORY_MUTATED")
	var new_record: Dictionary = {}
	for key in current_records:
		if not previous_records.has(key):
			new_record = current_records[key]
	if not new_record.is_empty():
		var transaction_id: String = String(new_record["transaction_id"])
		var previous_latest: Dictionary = _latest_record(previous["transaction_records"], transaction_id)
		if int(new_record["record_sequence"]) == 1:
			if not previous_latest.is_empty():
				return MatterUtils.failure("MATTER_CROSS_REGION_DUPLICATE_BEGIN")
		else:
			if previous_latest.is_empty():
				return MatterUtils.failure("MATTER_CROSS_REGION_NEW_RECORD_PREVIOUS_MISSING")
			checked = Record.validate_progression(new_record, previous_latest)
			if not bool(checked.get("success", false)):
				return checked
	checked = _validate_reservation_progression(current, previous, new_record)
	if not bool(checked.get("success", false)):
		return checked
	var previous_results: Dictionary = _items_by_id(previous["operation_results"], "operation_id")
	var current_results: Dictionary = _items_by_id(current["operation_results"], "operation_id")
	if current_results.size() < previous_results.size() or current_results.size() > previous_results.size() + 1:
		return MatterUtils.failure("MATTER_CROSS_REGION_CHECKPOINT_RESULT_COUNT_INVALID")
	for key in previous_results:
		if not current_results.has(key) or current_results[key] != previous_results[key]:
			return MatterUtils.failure("MATTER_CROSS_REGION_CHECKPOINT_RESULT_HISTORY_MUTATED")
	var added_results: Array[String] = _added_keys(current_results, previous_results)
	if new_record.is_empty() or not Record.is_terminal(new_record):
		if not added_results.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_RESULT_ADDED_WITHOUT_TERMINAL_RECORD")
	else:
		if added_results != [String(new_record["operation_id"])]:
			return MatterUtils.failure("MATTER_CROSS_REGION_TERMINAL_RESULT_ADDITION_MISMATCH")
	var previous_outbox: Dictionary = _items_by_id(previous["invalidation_outbox"], "outbox_id")
	var current_outbox: Dictionary = _items_by_id(current["invalidation_outbox"], "outbox_id")
	if current_outbox.size() < previous_outbox.size() or current_outbox.size() > previous_outbox.size() + 1:
		return MatterUtils.failure("MATTER_CROSS_REGION_CHECKPOINT_OUTBOX_COUNT_INVALID")
	var publish_changes := 0
	for key in previous_outbox:
		if not current_outbox.has(key):
			return MatterUtils.failure("MATTER_CROSS_REGION_CHECKPOINT_OUTBOX_REMOVED")
		var old_record: Dictionary = previous_outbox[key]
		var new_outbox_record: Dictionary = current_outbox[key]
		if new_outbox_record == old_record:
			continue
		if bool(old_record["published"]) or not bool(new_outbox_record["published"]) \
			or Dictionary(old_record["invalidation_batch"]) != Dictionary(new_outbox_record["invalidation_batch"]) \
			or String(old_record["committed_record_checksum"]) != String(new_outbox_record["committed_record_checksum"]):
			return MatterUtils.failure("MATTER_CROSS_REGION_OUTBOX_HISTORY_MUTATED")
		publish_changes += 1
	var added_outbox: Array[String] = _added_keys(current_outbox, previous_outbox)
	if not new_record.is_empty() and String(new_record["phase"]) == Record.PHASE_COMMITTED:
		if added_outbox.size() != 1:
			return MatterUtils.failure("MATTER_CROSS_REGION_COMMITTED_OUTBOX_ADDITION_MISMATCH")
	else:
		if not added_outbox.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_OUTBOX_ADDED_WITHOUT_COMMIT")
	if publish_changes > 1:
		return MatterUtils.failure("MATTER_CROSS_REGION_MULTIPLE_OUTBOX_PUBLISH_CHANGES")
	if not new_record.is_empty() and publish_changes != 0:
		return MatterUtils.failure("MATTER_CROSS_REGION_RECORD_AND_OUTBOX_PUBLISH_CHANGED_TOGETHER")
	if new_record.is_empty() and publish_changes != 1:
		return MatterUtils.failure("MATTER_CROSS_REGION_CHECKPOINT_NO_EFFECT")
	return MatterUtils.success()


static func _validate_reservation_progression(current: Dictionary, previous: Dictionary, new_record: Dictionary) -> Dictionary:
	var previous_reservations: Dictionary = _items_by_id(previous["region_reservations"], "region_id")
	var current_reservations: Dictionary = _items_by_id(current["region_reservations"], "region_id")
	for region_id in previous_reservations:
		if current_reservations.has(region_id) and current_reservations[region_id] != previous_reservations[region_id]:
			return MatterUtils.failure("MATTER_CROSS_REGION_RESERVATION_HISTORY_MUTATED", {"region_id": region_id})
	var added: Array[String] = _added_keys(current_reservations, previous_reservations)
	var removed: Array[String] = _added_keys(previous_reservations, current_reservations)
	if new_record.is_empty():
		if not added.is_empty() or not removed.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_RESERVATION_CHANGED_WITHOUT_RECORD")
		return MatterUtils.success()
	var expected_regions: Array[String] = []
	for raw_participant in new_record["plan"]["participants"]:
		expected_regions.append(String(raw_participant["region_id"]))
	if int(new_record["record_sequence"]) == 1:
		if added != expected_regions or not removed.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_BEGIN_RESERVATION_ADDITION_MISMATCH")
	elif Record.is_terminal(new_record):
		if removed != expected_regions or not added.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_TERMINAL_RESERVATION_REMOVAL_MISMATCH")
	elif not added.is_empty() or not removed.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_NONTERMINAL_RESERVATION_SET_CHANGED")
	return MatterUtils.success()


static func _added_keys(current: Dictionary, previous: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in current:
		if not previous.has(key):
			result.append(String(key))
	result.sort()
	return result


static func latest_records(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_record in records:
		var record: Dictionary = raw_record
		result[String(record["transaction_id"])] = record
	return result


static func _records_by_key(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_record in records:
		var record: Dictionary = raw_record
		result["%s/%012d" % [String(record["transaction_id"]), int(record["record_sequence"])]] = record
	return result


static func _items_by_id(items: Array, field: String) -> Dictionary:
	var result: Dictionary = {}
	for raw_item in items:
		var item: Dictionary = raw_item
		result[String(item[field])] = item
	return result


static func _latest_record(records: Array, transaction_id: String) -> Dictionary:
	var result: Dictionary = {}
	for raw_record in records:
		var record: Dictionary = raw_record
		if String(record["transaction_id"]) == transaction_id:
			result = record
	return result
