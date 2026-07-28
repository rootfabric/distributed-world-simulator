extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TicketScript = preload("res://scripts/network/contracts/network_resume_ticket.gd")
const ResumeScript = preload("res://scripts/network/contracts/network_session_resume_envelope.gd")
const ResumeResultScript = preload("res://scripts/network/contracts/network_session_resume_result.gd")
const CommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")

const SCHEMA: String = "planet_simulator.network_reconnect_replay_service.v1"
const PERSISTENCE_SCHEMA: String = "planet_simulator.network_reconnect_replay_state.v1"

var _max_tickets: int = 8
var _max_records: int = 32
var _ticket_ttl_ticks: int = 32
var _record_ttl_ticks: int = 128
var _max_resumes_per_ticket: int = 4
var _max_grants: int = 32
var _sequence: int = 0
var _tickets: Dictionary = {}
var _records: Dictionary = {}
var _grants: Dictionary = {}
var _ticket_evictions: int = 0
var _record_evictions: int = 0
var _grant_evictions: int = 0
var _resume_accepts: int = 0
var _resume_rejects: int = 0
var _replay_serves: int = 0


func configure(
	max_tickets: int = 8,
	max_records: int = 32,
	ticket_ttl_ticks: int = 32,
	record_ttl_ticks: int = 128,
	max_resumes_per_ticket: int = 4
) -> Dictionary:
	if (
		max_tickets <= 0 or max_tickets > 4096
		or max_records <= 0 or max_records > 65536
		or ticket_ttl_ticks <= 0 or ticket_ttl_ticks > 1000000000
		or record_ttl_ticks <= 0 or record_ttl_ticks > 1000000000
		or max_resumes_per_ticket <= 0 or max_resumes_per_ticket > 64
	):
		return _failure("INVALID_REPLAY_LIMITS")
	_max_tickets = max_tickets
	_max_records = max_records
	_ticket_ttl_ticks = ticket_ttl_ticks
	_record_ttl_ticks = record_ttl_ticks
	_max_resumes_per_ticket = max_resumes_per_ticket
	_max_grants = max_tickets * max_resumes_per_ticket
	_sequence = 0
	_tickets.clear()
	_records.clear()
	_grants.clear()
	_ticket_evictions = 0
	_record_evictions = 0
	_grant_evictions = 0
	_resume_accepts = 0
	_resume_rejects = 0
	_replay_serves = 0
	return _success()


func issue_ticket(logical_session_id: String, client_node_id: String, current_tick: int) -> Dictionary:
	if not _is_canonical_id(logical_session_id) or not _is_canonical_id(client_node_id) or current_tick < 0:
		return _failure("INVALID_TICKET_REQUEST")
	_purge(current_tick)
	_sequence += 1
	var ticket_id: String = "resume-ticket/%d/%d" % [OS.get_process_id(), _sequence]
	var token_seed: PackedByteArray = Crypto.new().generate_random_bytes(32)
	if token_seed.size() != 32:
		return _failure("RESUME_TOKEN_GENERATION_FAILED")
	var ticket: Dictionary = TicketScript.create(
		ticket_id,
		logical_session_id,
		client_node_id,
		current_tick,
		current_tick + _ticket_ttl_ticks,
		token_seed.hex_encode()
	)
	var validation: Dictionary = TicketScript.validate(ticket)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_ISSUED_TICKET")))
	_evict_oldest(_tickets, _max_tickets, true)
	_tickets[ticket_id] = {
		"sequence": _sequence,
		"ticket": ticket.duplicate(true),
		"resume_count": 0,
	}
	return _success({"ticket": ticket.duplicate(true)})


func record_completed_operation(
	logical_session_id: String,
	client_node_id: String,
	command: Dictionary,
	result: Dictionary,
	delta: Dictionary,
	final_snapshot: Dictionary,
	completed_tick: int,
	base_snapshot: Dictionary
) -> Dictionary:
	var command_validation: Dictionary = CommandScript.validate(command)
	var result_validation: Dictionary = ResultScript.validate(result)
	var delta_validation: Dictionary = DeltaScript.validate(delta)
	var snapshot_validation: Dictionary = SnapshotScript.validate(final_snapshot)
	var base_snapshot_validation: Dictionary = SnapshotScript.validate(base_snapshot)
	if not (
		bool(command_validation.get("success", false))
		and bool(result_validation.get("success", false))
		and bool(delta_validation.get("success", false))
		and bool(snapshot_validation.get("success", false))
		and bool(base_snapshot_validation.get("success", false))
	):
		return _failure("INVALID_REPLAY_RECORD")
	if not _is_canonical_id(logical_session_id) or not _is_canonical_id(client_node_id) or completed_tick < 0:
		return _failure("INVALID_REPLAY_RECORD")
	if String(command["operation_id"]) != String(result["operation_id"]):
		return _failure("REPLAY_OPERATION_MISMATCH")
	if String(result["status"]) != "SUCCEEDED":
		return _failure("ONLY_SUCCESSFUL_OPERATION_CAN_REPLAY")
	if String(delta["entity_id"]) != String(command["entity_id"]):
		return _failure("REPLAY_ENTITY_MISMATCH")
	if String(command["entity_id"]) != String(base_snapshot["entity_id"]):
		return _failure("REPLAY_BASE_ENTITY_MISMATCH")
	if int(command["expected_revision"]) != int(base_snapshot["state_revision"]):
		return _failure("REPLAY_BASE_REVISION_MISMATCH")
	if int(command["authority_epoch"]) != int(base_snapshot["authority_epoch"]):
		return _failure("REPLAY_BASE_AUTHORITY_MISMATCH")
	if int(delta["base_revision"]) != int(base_snapshot["state_revision"]):
		return _failure("REPLAY_DELTA_BASE_MISMATCH")
	if int(delta["result_revision"]) != int(final_snapshot["state_revision"]):
		return _failure("REPLAY_DELTA_TARGET_MISMATCH")
	if int(result["result_revision"]) != int(final_snapshot["state_revision"]):
		return _failure("REPLAY_RESULT_REVISION_MISMATCH")
	if String(final_snapshot["checksum"]) != String(result.get("payload", {}).get("result_snapshot_checksum", "")):
		return _failure("REPLAY_SNAPSHOT_CHECKSUM_MISMATCH")
	var applied: Dictionary = DeltaScript.apply_to_snapshot(base_snapshot, delta)
	if not bool(applied.get("success", false)) or String(applied.get("snapshot", {}).get("checksum", "")) != String(final_snapshot["checksum"]):
		return _failure("REPLAY_DELTA_SNAPSHOT_MISMATCH")
	_purge(completed_tick)
	var operation_id: String = String(command["operation_id"])
	var fingerprint: String = CommandScript.command_fingerprint(command)
	if _records.has(operation_id):
		var existing: Dictionary = _records[operation_id]
		if String(existing["fingerprint"]) != fingerprint:
			return _failure("OPERATION_ID_CONFLICT")
		return _success({"replay": true})
	_sequence += 1
	_evict_oldest(_records, _max_records, false)
	_records[operation_id] = {
		"sequence": _sequence,
		"logical_session_id": logical_session_id,
		"client_node_id": client_node_id,
		"operation_id": operation_id,
		"fingerprint": fingerprint,
		"command": command.duplicate(true),
		"result": result.duplicate(true),
		"delta": delta.duplicate(true),
		"final_snapshot": final_snapshot.duplicate(true),
		"base_snapshot": base_snapshot.duplicate(true),
		"base_snapshot_checksum": String(base_snapshot["checksum"]),
		"completed_tick": completed_tick,
		"expires_tick": completed_tick + _record_ttl_ticks,
	}
	return _success({"replay": false, "fingerprint": fingerprint})


func evaluate_resume(resume: Dictionary, current_tick: int) -> Dictionary:
	var validation: Dictionary = ResumeScript.validate(resume)
	if not bool(validation.get("success", false)):
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, String(validation.get("error_code", "INVALID_RESUME")))
	_purge(current_tick)
	var ticket: Dictionary = resume["ticket"]
	var ticket_id: String = String(ticket["ticket_id"])
	var operation_id: String = String(resume["operation_id"])
	var transport_session_id: String = String(resume["transport_session_id"])
	if not _tickets.has(ticket_id):
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "RESUME_TICKET_NOT_FOUND")
	var stored_ticket: Dictionary = _tickets[ticket_id]
	var authoritative_ticket: Dictionary = stored_ticket["ticket"]
	if UtilsScript.canonical_json(authoritative_ticket) != UtilsScript.canonical_json(ticket):
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "RESUME_TICKET_CONFLICT")
	if int(ticket["expires_tick"]) < current_tick:
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "RESUME_TICKET_EXPIRED")
	if int(stored_ticket["resume_count"]) >= _max_resumes_per_ticket:
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "RESUME_LIMIT_EXCEEDED")
	if transport_session_id == String(ticket["logical_session_id"]):
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "TRANSPORT_SESSION_NOT_ROTATED")
	if not _records.has(operation_id):
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "REPLAY_RECORD_NOT_FOUND")
	var record: Dictionary = _records[operation_id]
	if int(record["expires_tick"]) < current_tick:
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "REPLAY_RECORD_EXPIRED")
	if String(record["logical_session_id"]) != String(ticket["logical_session_id"]):
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "LOGICAL_SESSION_MISMATCH")
	if String(record["client_node_id"]) != String(ticket["client_node_id"]):
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "CLIENT_ID_MISMATCH")
	if String(record["fingerprint"]) != String(resume["command_fingerprint"]):
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "COMMAND_FINGERPRINT_MISMATCH")
	var last_checksum: String = String(resume["last_snapshot_checksum"])
	if last_checksum not in [String(record["base_snapshot_checksum"]), String(record["final_snapshot"]["checksum"])]:
		_resume_rejects += 1
		return _resume_decision(resume, false, current_tick, "LAST_SNAPSHOT_CHECKSUM_MISMATCH")
	stored_ticket["resume_count"] = int(stored_ticket["resume_count"]) + 1
	_tickets[ticket_id] = stored_ticket
	_sequence += 1
	_evict_oldest_grant()
	_grants[transport_session_id] = {
		"sequence": _sequence,
		"operation_id": operation_id,
		"fingerprint": String(record["fingerprint"]),
		"logical_session_id": String(record["logical_session_id"]),
		"client_node_id": String(record["client_node_id"]),
		"expires_tick": mini(int(ticket["expires_tick"]), int(record["expires_tick"])),
	}
	_resume_accepts += 1
	return _resume_decision(resume, true, current_tick, "")


func serve_replay(transport_session_id: String, command: Dictionary, current_tick: int) -> Dictionary:
	var validation: Dictionary = CommandScript.validate(command)
	if not bool(validation.get("success", false)):
		return _failure(String(validation.get("error_code", "INVALID_COMMAND")))
	_purge(current_tick)
	if not _grants.has(transport_session_id):
		return _failure("REPLAY_GRANT_NOT_FOUND")
	var grant: Dictionary = _grants[transport_session_id]
	if int(grant["expires_tick"]) < current_tick:
		_grants.erase(transport_session_id)
		return _failure("REPLAY_GRANT_EXPIRED")
	var operation_id: String = String(command["operation_id"])
	var fingerprint: String = CommandScript.command_fingerprint(command)
	if operation_id != String(grant["operation_id"]) or fingerprint != String(grant["fingerprint"]):
		return _failure("REPLAY_COMMAND_CONFLICT")
	if not _records.has(operation_id):
		return _failure("REPLAY_RECORD_NOT_FOUND")
	var record: Dictionary = _records[operation_id]
	_grants.erase(transport_session_id)
	_replay_serves += 1
	var result: Dictionary = record["result"].duplicate(true)
	result["message_id"] = String(command["message_id"])
	return _success({
		"result": result,
		"delta": record["delta"].duplicate(true),
		"final_snapshot": record["final_snapshot"].duplicate(true),
		"logical_session_id": String(record["logical_session_id"]),
	})


func to_dict() -> Dictionary:
	var ticket_rows: Array = []
	var ticket_ids: Array = _tickets.keys()
	ticket_ids.sort()
	for ticket_id_value in ticket_ids:
		var ticket_id: String = String(ticket_id_value)
		var stored: Dictionary = _tickets[ticket_id]
		ticket_rows.append({
			"sequence": int(stored.get("sequence", 0)),
			"ticket": Dictionary(stored.get("ticket", {})).duplicate(true),
			"resume_count": int(stored.get("resume_count", 0)),
		})
	var record_rows: Array = []
	var operation_ids: Array = _records.keys()
	operation_ids.sort()
	for operation_id_value in operation_ids:
		record_rows.append(Dictionary(_records[operation_id_value]).duplicate(true))
	return {
		"schema": PERSISTENCE_SCHEMA,
		"max_tickets": _max_tickets,
		"max_records": _max_records,
		"ticket_ttl_ticks": _ticket_ttl_ticks,
		"record_ttl_ticks": _record_ttl_ticks,
		"max_resumes_per_ticket": _max_resumes_per_ticket,
		"sequence": _sequence,
		"ticket_evictions": _ticket_evictions,
		"record_evictions": _record_evictions,
		"resume_accepts": _resume_accepts,
		"resume_rejects": _resume_rejects,
		"replay_serves": _replay_serves,
		"tickets": ticket_rows,
		"records": record_rows,
	}


func load_dict(value: Dictionary, current_tick: int = -1) -> Dictionary:
	var fields: Array[String] = [
		"schema", "max_tickets", "max_records", "ticket_ttl_ticks", "record_ttl_ticks",
		"max_resumes_per_ticket", "sequence", "ticket_evictions", "record_evictions",
		"resume_accepts", "resume_rejects", "replay_serves", "tickets", "records",
	]
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, fields)
	if not bool(exact.get("success", false)):
		return _failure("INVALID_REPLAY_STATE_FIELDS")
	if typeof(value["schema"]) != TYPE_STRING or String(value["schema"]) != PERSISTENCE_SCHEMA:
		return _failure("UNSUPPORTED_REPLAY_STATE_SCHEMA")
	for field in [
		"max_tickets", "max_records", "ticket_ttl_ticks", "record_ttl_ticks",
		"max_resumes_per_ticket", "sequence", "ticket_evictions", "record_evictions",
		"resume_accepts", "resume_rejects", "replay_serves",
	]:
		if not UtilsScript.is_json_integer(value[field]) or int(value[field]) < 0:
			return _failure("INVALID_REPLAY_STATE_INTEGER", {"field": field})
	var staged = get_script().new()
	var configured: Dictionary = staged.configure(
		int(value["max_tickets"]),
		int(value["max_records"]),
		int(value["ticket_ttl_ticks"]),
		int(value["record_ttl_ticks"]),
		int(value["max_resumes_per_ticket"])
	)
	if not bool(configured.get("success", false)):
		return configured
	if typeof(value["tickets"]) != TYPE_ARRAY or typeof(value["records"]) != TYPE_ARRAY:
		return _failure("INVALID_REPLAY_STATE_ROWS")
	if value["tickets"].size() > staged._max_tickets or value["records"].size() > staged._max_records:
		return _failure("REPLAY_STATE_LIMIT_EXCEEDED")
	var maximum_sequence: int = 0
	for row_value in value["tickets"]:
		if not row_value is Dictionary:
			return _failure("INVALID_REPLAY_TICKET_ROW")
		var row: Dictionary = row_value
		var row_exact: Dictionary = UtilsScript.validate_exact_fields(row, ["sequence", "ticket", "resume_count"])
		if not bool(row_exact.get("success", false)):
			return _failure("INVALID_REPLAY_TICKET_ROW")
		if not UtilsScript.is_json_integer(row["sequence"]) or int(row["sequence"]) < 1:
			return _failure("INVALID_REPLAY_TICKET_SEQUENCE")
		if not UtilsScript.is_json_integer(row["resume_count"]) or int(row["resume_count"]) < 0 or int(row["resume_count"]) > staged._max_resumes_per_ticket:
			return _failure("INVALID_REPLAY_TICKET_COUNT")
		if typeof(row["ticket"]) != TYPE_DICTIONARY:
			return _failure("INVALID_REPLAY_TICKET")
		var ticket: Dictionary = row["ticket"]
		var ticket_validation: Dictionary = TicketScript.validate(ticket)
		if not bool(ticket_validation.get("success", false)):
			return _failure("INVALID_REPLAY_TICKET")
		var ticket_id: String = String(ticket["ticket_id"])
		if staged._tickets.has(ticket_id):
			return _failure("DUPLICATE_REPLAY_TICKET")
		staged._tickets[ticket_id] = {
			"sequence": int(row["sequence"]),
			"ticket": ticket.duplicate(true),
			"resume_count": int(row["resume_count"]),
		}
		maximum_sequence = maxi(maximum_sequence, int(row["sequence"]))
	for record_value in value["records"]:
		if not record_value is Dictionary:
			return _failure("INVALID_REPLAY_RECORD")
		var record: Dictionary = record_value
		var record_validation: Dictionary = _validate_persisted_record(record)
		if not bool(record_validation.get("success", false)):
			return record_validation
		var operation_id: String = String(record["operation_id"])
		if staged._records.has(operation_id):
			return _failure("DUPLICATE_REPLAY_OPERATION")
		staged._records[operation_id] = record.duplicate(true)
		maximum_sequence = maxi(maximum_sequence, int(record["sequence"]))
	if int(value["sequence"]) < maximum_sequence:
		return _failure("INVALID_REPLAY_SEQUENCE")
	staged._sequence = int(value["sequence"])
	staged._ticket_evictions = int(value["ticket_evictions"])
	staged._record_evictions = int(value["record_evictions"])
	staged._resume_accepts = int(value["resume_accepts"])
	staged._resume_rejects = int(value["resume_rejects"])
	staged._replay_serves = int(value["replay_serves"])
	staged._grants.clear()
	if current_tick >= 0:
		staged._purge(current_tick)
	_max_tickets = staged._max_tickets
	_max_records = staged._max_records
	_ticket_ttl_ticks = staged._ticket_ttl_ticks
	_record_ttl_ticks = staged._record_ttl_ticks
	_max_resumes_per_ticket = staged._max_resumes_per_ticket
	_max_grants = staged._max_grants
	_sequence = staged._sequence
	_tickets = staged._tickets
	_records = staged._records
	_grants = {}
	_ticket_evictions = staged._ticket_evictions
	_record_evictions = staged._record_evictions
	_grant_evictions = 0
	_resume_accepts = staged._resume_accepts
	_resume_rejects = staged._resume_rejects
	_replay_serves = staged._replay_serves
	return _success({"ticket_count": _tickets.size(), "record_count": _records.size()})


func _validate_persisted_record(record: Dictionary) -> Dictionary:
	var fields: Array[String] = [
		"sequence", "logical_session_id", "client_node_id", "operation_id", "fingerprint",
		"command", "result", "delta", "final_snapshot", "base_snapshot", "base_snapshot_checksum",
		"completed_tick", "expires_tick",
	]
	var exact: Dictionary = UtilsScript.validate_exact_fields(record, fields)
	if not bool(exact.get("success", false)):
		return _failure("INVALID_REPLAY_RECORD_FIELDS")
	for field in ["sequence", "completed_tick", "expires_tick"]:
		if not UtilsScript.is_json_integer(record[field]) or int(record[field]) < 0:
			return _failure("INVALID_REPLAY_RECORD_INTEGER", {"field": field})
	if int(record["sequence"]) < 1 or int(record["expires_tick"]) <= int(record["completed_tick"]):
		return _failure("INVALID_REPLAY_RECORD_WINDOW")
	if not _is_canonical_id(String(record["logical_session_id"])) or not _is_canonical_id(String(record["client_node_id"])):
		return _failure("INVALID_REPLAY_RECORD_ID")
	for field in ["command", "result", "delta", "final_snapshot", "base_snapshot"]:
		if typeof(record[field]) != TYPE_DICTIONARY:
			return _failure("INVALID_REPLAY_RECORD_SECTION", {"field": field})
	var command: Dictionary = record["command"]
	var result: Dictionary = record["result"]
	var delta: Dictionary = record["delta"]
	var final_snapshot: Dictionary = record["final_snapshot"]
	var base_snapshot: Dictionary = record["base_snapshot"]
	if not bool(CommandScript.validate(command).get("success", false)):
		return _failure("INVALID_REPLAY_RECORD_COMMAND")
	if not bool(ResultScript.validate(result).get("success", false)):
		return _failure("INVALID_REPLAY_RECORD_RESULT")
	if not bool(DeltaScript.validate(delta).get("success", false)):
		return _failure("INVALID_REPLAY_RECORD_DELTA")
	if not bool(SnapshotScript.validate(final_snapshot).get("success", false)) or not bool(SnapshotScript.validate(base_snapshot).get("success", false)):
		return _failure("INVALID_REPLAY_RECORD_SNAPSHOT")
	var operation_id: String = String(record["operation_id"])
	if operation_id != String(command["operation_id"]) or operation_id != String(result["operation_id"]):
		return _failure("REPLAY_OPERATION_MISMATCH")
	if String(record["fingerprint"]) != CommandScript.command_fingerprint(command):
		return _failure("REPLAY_FINGERPRINT_MISMATCH")
	if String(record["base_snapshot_checksum"]) != String(base_snapshot["checksum"]):
		return _failure("REPLAY_BASE_CHECKSUM_MISMATCH")
	if String(result["status"]) != "SUCCEEDED":
		return _failure("ONLY_SUCCESSFUL_OPERATION_CAN_REPLAY")
	var applied: Dictionary = DeltaScript.apply_to_snapshot(base_snapshot, delta)
	if not bool(applied.get("success", false)) or String(applied.get("snapshot", {}).get("checksum", "")) != String(final_snapshot["checksum"]):
		return _failure("REPLAY_DELTA_SNAPSHOT_MISMATCH")
	if int(result["result_revision"]) != int(final_snapshot["state_revision"]):
		return _failure("REPLAY_RESULT_REVISION_MISMATCH")
	return _success()


func get_snapshot() -> Dictionary:
	var ticket_resume_counts: Dictionary = {}
	for ticket_id in _tickets.keys():
		ticket_resume_counts[ticket_id] = int(_tickets[ticket_id]["resume_count"])
	return {
		"schema": SCHEMA,
		"max_tickets": _max_tickets,
		"max_records": _max_records,
		"ticket_ttl_ticks": _ticket_ttl_ticks,
		"record_ttl_ticks": _record_ttl_ticks,
		"max_resumes_per_ticket": _max_resumes_per_ticket,
		"max_grants": _max_grants,
		"ticket_count": _tickets.size(),
		"record_count": _records.size(),
		"grant_count": _grants.size(),
		"ticket_evictions": _ticket_evictions,
		"record_evictions": _record_evictions,
		"grant_evictions": _grant_evictions,
		"resume_accepts": _resume_accepts,
		"resume_rejects": _resume_rejects,
		"replay_serves": _replay_serves,
		"ticket_resume_counts": ticket_resume_counts,
	}


func _resume_decision(resume: Dictionary, accepted: bool, current_tick: int, error_code: String) -> Dictionary:
	var ticket: Dictionary = resume.get("ticket", {}) if resume.get("ticket") is Dictionary else {}
	var operation_id: String = String(resume.get("operation_id", "operation/invalid"))
	var result_revision: int = -1
	if _records.has(operation_id):
		result_revision = int(_records[operation_id]["result"].get("result_revision", -1))
	var result: Dictionary = ResumeResultScript.create(
		String(resume.get("resume_id", "resume/invalid")),
		accepted,
		String(ticket.get("logical_session_id", "session/invalid")),
		String(resume.get("transport_session_id", "session/invalid")),
		operation_id,
		result_revision,
		current_tick,
		error_code
	)
	return _success({"result": result})


func _purge(current_tick: int) -> void:
	for ticket_id in _tickets.keys().duplicate():
		if int(_tickets[ticket_id]["ticket"]["expires_tick"]) < current_tick:
			_tickets.erase(ticket_id)
	for operation_id in _records.keys().duplicate():
		if int(_records[operation_id]["expires_tick"]) < current_tick:
			_records.erase(operation_id)
			_remove_grants_for_operation(String(operation_id))
	for session_id in _grants.keys().duplicate():
		if int(_grants[session_id]["expires_tick"]) < current_tick:
			_grants.erase(session_id)


func _evict_oldest(store: Dictionary, maximum: int, ticket_store: bool) -> void:
	while store.size() >= maximum:
		var oldest_key = null
		var oldest_sequence: int = 9223372036854775807
		for key in store.keys():
			var sequence: int = int(store[key].get("sequence", oldest_sequence))
			if sequence < oldest_sequence:
				oldest_sequence = sequence
				oldest_key = key
		if oldest_key == null:
			break
		store.erase(oldest_key)
		if not ticket_store:
			_remove_grants_for_operation(String(oldest_key))
		if ticket_store:
			_ticket_evictions += 1
		else:
			_record_evictions += 1


func _evict_oldest_grant() -> void:
	while _grants.size() >= _max_grants:
		var oldest_key = null
		var oldest_sequence: int = 9223372036854775807
		for key in _grants.keys():
			var sequence: int = int(_grants[key].get("sequence", oldest_sequence))
			if sequence < oldest_sequence:
				oldest_sequence = sequence
				oldest_key = key
		if oldest_key == null:
			break
		_grants.erase(oldest_key)
		_grant_evictions += 1


func _remove_grants_for_operation(operation_id: String) -> void:
	for session_id in _grants.keys().duplicate():
		if String(_grants[session_id].get("operation_id", "")) == operation_id:
			_grants.erase(session_id)


func _is_canonical_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_lower():
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["/", "_", ".", "-"]):
			return false
	return true


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
