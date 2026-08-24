extends RefCounted

## SM1.2 one-writer authority transfer coordinator.
##
## This object owns only the transfer decision/epoch state. It does NOT own
## player, Item Graph, Construction, replay, persistence or Gateway truth.
## Write authorization is fail-closed and is intentionally unavailable during
## the transfer gap. Before the linearization point the source is canonical;
## after commit the source is permanently fenced and the target is still
## read-only until explicit activation.

const SCHEMA := "distributed_world_simulator.v0_sm1_authority_transfer.v1"

const STATE_UNCONFIGURED := "UNCONFIGURED"
const STATE_ACTIVE := "ACTIVE"
const STATE_SOURCE_FROZEN := "SOURCE_FROZEN"
const STATE_TARGET_WARM_VALIDATED := "TARGET_WARM_VALIDATED"
const STATE_OWNERSHIP_COMMITTED := "OWNERSHIP_COMMITTED"
const STATE_SOURCE_RETIRED := "SOURCE_RETIRED"

const RESULT_STARTED := "STARTED"
const RESULT_WARM_VALIDATED := "WARM_VALIDATED"
const RESULT_COMMITTED := "COMMITTED"
const RESULT_ALREADY_COMMITTED := "ALREADY_COMMITTED"
const RESULT_SOURCE_RETIRED := "SOURCE_RETIRED"
const RESULT_ALREADY_RETIRED := "ALREADY_RETIRED"
const RESULT_TARGET_ACTIVATED := "TARGET_ACTIVATED"
const RESULT_ALREADY_ACTIVE := "ALREADY_ACTIVE"
const RESULT_ABORTED := "ABORTED_BEFORE_COMMIT"

var _state: String = STATE_UNCONFIGURED
var _active_authority_id: String = ""
var _authority_epoch: int = 0
var _player_snapshot: Dictionary = {}
var _transfer: Dictionary = {}
var _completed_transfers: Dictionary = {}
var _counters := {
	"begins": 0,
	"warm_validations": 0,
	"commits": 0,
	"commit_replays": 0,
	"source_retires": 0,
	"activations": 0,
	"activation_replays": 0,
	"aborts_before_commit": 0,
	"write_authorizations": 0,
	"write_rejections": 0,
}


func configure(initial_authority_id: String, initial_epoch: int, player_snapshot: Dictionary) -> Dictionary:
	if _state != STATE_UNCONFIGURED:
		return _failure("SM1_ALREADY_CONFIGURED")
	if initial_authority_id.strip_edges().is_empty() or initial_epoch < 1:
		return _failure("SM1_INITIAL_AUTHORITY_INVALID")
	var player_check := _validate_player_snapshot(player_snapshot)
	if not bool(player_check.get("success", false)):
		return player_check
	_active_authority_id = initial_authority_id
	_authority_epoch = initial_epoch
	_player_snapshot = player_snapshot.duplicate(true)
	_player_snapshot["authority_epoch"] = initial_epoch
	_state = STATE_ACTIVE
	return _success({"result": "CONFIGURED", "snapshot": snapshot()})


func begin_transfer(transfer_id: String, source_authority_id: String, target_authority_id: String, expected_source_epoch: int) -> Dictionary:
	if transfer_id.strip_edges().is_empty():
		return _failure("SM1_TRANSFER_ID_REQUIRED")
	if _completed_transfers.has(transfer_id):
		return _failure("SM1_TRANSFER_ALREADY_COMPLETED", {"transfer_id": transfer_id})
	if _state != STATE_ACTIVE:
		return _failure("SM1_TRANSFER_IN_PROGRESS", {"state": _state})
	if source_authority_id != _active_authority_id:
		return _failure("SM1_SOURCE_NOT_ACTIVE", {"active_authority_id": _active_authority_id})
	if target_authority_id.strip_edges().is_empty() or target_authority_id == source_authority_id:
		return _failure("SM1_TARGET_AUTHORITY_INVALID")
	if expected_source_epoch != _authority_epoch:
		return _failure("SM1_SOURCE_EPOCH_MISMATCH", {"expected": _authority_epoch, "actual": expected_source_epoch})

	_transfer = {
		"transfer_id": transfer_id,
		"source_authority_id": source_authority_id,
		"target_authority_id": target_authority_id,
		"source_epoch": _authority_epoch,
		"target_epoch": _authority_epoch + 1,
		"player_snapshot": _player_snapshot.duplicate(true),
		"warm_checksum": "",
		"commit_token": "",
	}
	_state = STATE_SOURCE_FROZEN
	_counters["begins"] = int(_counters["begins"]) + 1
	return _success({
		"result": RESULT_STARTED,
		"transfer": _transfer.duplicate(true),
		"source_write_authorized": false,
		"target_write_authorized": false,
	})


func validate_warm_target(transfer_id: String, target_authority_id: String, warm_report: Dictionary) -> Dictionary:
	if not _matches_live_transfer(transfer_id):
		return _failure("SM1_TRANSFER_NOT_FOUND", {"transfer_id": transfer_id})
	if target_authority_id != String(_transfer.get("target_authority_id", "")):
		return _failure("SM1_WARM_TARGET_MISMATCH")

	var checksum := String(warm_report.get("checksum", ""))
	if _state == STATE_TARGET_WARM_VALIDATED:
		if checksum == String(_transfer.get("warm_checksum", "")) and not checksum.is_empty():
			return _success({"result": "WARM_ALREADY_VALIDATED", "transfer": _transfer.duplicate(true)})
		return _failure("SM1_WARM_REPLAY_CONFLICT")
	if _state != STATE_SOURCE_FROZEN:
		return _failure("SM1_WARM_VALIDATION_STATE_INVALID", {"state": _state})
	if String(warm_report.get("mode", "")) != "SHADOW":
		return _failure("SM1_WARM_TARGET_NOT_SHADOW")
	if checksum.is_empty():
		return _failure("SM1_WARM_CHECKSUM_REQUIRED")
	if bool(warm_report.get("private_canonical_truth", true)):
		return _failure("SM1_WARM_PRIVATE_TRUTH_FORBIDDEN")
	if String(warm_report.get("persistence_owner", "")) != "EXTERNAL":
		return _failure("SM1_WARM_PERSISTENCE_OWNER_INVALID")
	var counters_value: Variant = warm_report.get("counters", {})
	if counters_value is Dictionary:
		var counters := Dictionary(counters_value)
		var attempts := int(counters.get("write_attempts", 0))
		var rejections := int(counters.get("write_rejections", 0))
		if attempts != rejections:
			return _failure("SM1_WARM_WRITE_NOT_FAIL_CLOSED", {"attempts": attempts, "rejections": rejections})

	_transfer["warm_checksum"] = checksum
	_state = STATE_TARGET_WARM_VALIDATED
	_counters["warm_validations"] = int(_counters["warm_validations"]) + 1
	return _success({"result": RESULT_WARM_VALIDATED, "transfer": _transfer.duplicate(true)})


func commit_ownership(transfer_id: String, source_authority_id: String, target_authority_id: String, source_epoch: int, target_epoch: int) -> Dictionary:
	if _completed_transfers.has(transfer_id):
		_counters["commit_replays"] = int(_counters["commit_replays"]) + 1
		return _success({"result": RESULT_ALREADY_COMMITTED, "completed": Dictionary(_completed_transfers[transfer_id]).duplicate(true)})
	if not _matches_live_transfer(transfer_id):
		return _failure("SM1_TRANSFER_NOT_FOUND", {"transfer_id": transfer_id})
	if _state in [STATE_OWNERSHIP_COMMITTED, STATE_SOURCE_RETIRED]:
		if _tuple_matches(source_authority_id, target_authority_id, source_epoch, target_epoch):
			_counters["commit_replays"] = int(_counters["commit_replays"]) + 1
			return _success({
				"result": RESULT_ALREADY_COMMITTED,
				"commit_token": String(_transfer.get("commit_token", "")),
				"linearized_now": false,
				"transfer": _transfer.duplicate(true),
			})
		return _failure("SM1_COMMIT_REPLAY_CONFLICT")
	if _state != STATE_TARGET_WARM_VALIDATED:
		return _failure("SM1_COMMIT_BEFORE_WARM_VALIDATION", {"state": _state})
	if not _tuple_matches(source_authority_id, target_authority_id, source_epoch, target_epoch):
		return _failure("SM1_COMMIT_TUPLE_MISMATCH")

	var commit_payload := {
		"schema": SCHEMA,
		"transfer_id": transfer_id,
		"source_authority_id": source_authority_id,
		"target_authority_id": target_authority_id,
		"source_epoch": source_epoch,
		"target_epoch": target_epoch,
		"warm_checksum": String(_transfer.get("warm_checksum", "")),
		"logical_player_id": String(_player_snapshot.get("logical_player_id", "")),
		"player_entity_id": String(_player_snapshot.get("player_entity_id", "")),
	}
	var commit_token := JSON.stringify(commit_payload, "", false).sha256_text()
	_transfer["commit_token"] = commit_token
	_active_authority_id = target_authority_id
	_authority_epoch = target_epoch
	_player_snapshot["authority_epoch"] = target_epoch
	_state = STATE_OWNERSHIP_COMMITTED
	_counters["commits"] = int(_counters["commits"]) + 1
	return _success({
		"result": RESULT_COMMITTED,
		"commit_token": commit_token,
		"linearized_now": true,
		"source_write_authorized": false,
		"target_write_authorized": false,
		"transfer": _transfer.duplicate(true),
	})


func retire_source(transfer_id: String, source_authority_id: String, commit_token: String) -> Dictionary:
	if _completed_transfers.has(transfer_id):
		return _success({"result": RESULT_ALREADY_RETIRED, "completed": Dictionary(_completed_transfers[transfer_id]).duplicate(true)})
	if not _matches_live_transfer(transfer_id):
		return _failure("SM1_TRANSFER_NOT_FOUND", {"transfer_id": transfer_id})
	if _state == STATE_SOURCE_RETIRED:
		if _source_and_token_match(source_authority_id, commit_token):
			return _success({"result": RESULT_ALREADY_RETIRED, "transfer": _transfer.duplicate(true)})
		return _failure("SM1_SOURCE_RETIRE_REPLAY_CONFLICT")
	if _state != STATE_OWNERSHIP_COMMITTED:
		return _failure("SM1_SOURCE_RETIRE_BEFORE_COMMIT", {"state": _state})
	if not _source_and_token_match(source_authority_id, commit_token):
		return _failure("SM1_SOURCE_RETIRE_PROOF_INVALID")
	_state = STATE_SOURCE_RETIRED
	_counters["source_retires"] = int(_counters["source_retires"]) + 1
	return _success({"result": RESULT_SOURCE_RETIRED, "transfer": _transfer.duplicate(true)})


func activate_target(transfer_id: String, target_authority_id: String, target_epoch: int, commit_token: String) -> Dictionary:
	if _completed_transfers.has(transfer_id):
		var completed := Dictionary(_completed_transfers[transfer_id])
		if target_authority_id == String(completed.get("target_authority_id", "")) \
				and target_epoch == int(completed.get("target_epoch", 0)) \
				and commit_token == String(completed.get("commit_token", "")):
			_counters["activation_replays"] = int(_counters["activation_replays"]) + 1
			return _success({"result": RESULT_ALREADY_ACTIVE, "completed": completed.duplicate(true)})
		return _failure("SM1_TARGET_ACTIVATION_REPLAY_CONFLICT")
	if not _matches_live_transfer(transfer_id):
		return _failure("SM1_TRANSFER_NOT_FOUND", {"transfer_id": transfer_id})
	if _state != STATE_SOURCE_RETIRED:
		return _failure("SM1_TARGET_ACTIVATION_BEFORE_SOURCE_RETIRED", {"state": _state})
	if target_authority_id != _active_authority_id or target_epoch != _authority_epoch:
		return _failure("SM1_TARGET_ACTIVATION_TUPLE_MISMATCH")
	if commit_token.is_empty() or commit_token != String(_transfer.get("commit_token", "")):
		return _failure("SM1_TARGET_ACTIVATION_PROOF_INVALID")

	_state = STATE_ACTIVE
	_counters["activations"] = int(_counters["activations"]) + 1
	var completed := _transfer.duplicate(true)
	completed["completed"] = true
	completed["final_state"] = STATE_ACTIVE
	_completed_transfers[transfer_id] = completed
	_transfer = {}
	return _success({
		"result": RESULT_TARGET_ACTIVATED,
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
		"player_snapshot": _player_snapshot.duplicate(true),
		"completed": completed.duplicate(true),
	})


func abort_before_commit(transfer_id: String, source_authority_id: String) -> Dictionary:
	if not _matches_live_transfer(transfer_id):
		return _failure("SM1_TRANSFER_NOT_FOUND", {"transfer_id": transfer_id})
	if _state not in [STATE_SOURCE_FROZEN, STATE_TARGET_WARM_VALIDATED]:
		return _failure("SM1_ABORT_AFTER_COMMIT_FORBIDDEN", {"state": _state})
	if source_authority_id != String(_transfer.get("source_authority_id", "")):
		return _failure("SM1_ABORT_SOURCE_MISMATCH")
	_active_authority_id = source_authority_id
	_authority_epoch = int(_transfer.get("source_epoch", _authority_epoch))
	_player_snapshot["authority_epoch"] = _authority_epoch
	_transfer = {}
	_state = STATE_ACTIVE
	_counters["aborts_before_commit"] = int(_counters["aborts_before_commit"]) + 1
	return _success({"result": RESULT_ABORTED, "snapshot": snapshot()})


func authorize_write(authority_id: String, authority_epoch: int) -> Dictionary:
	if _state != STATE_ACTIVE:
		_counters["write_rejections"] = int(_counters["write_rejections"]) + 1
		return _failure("SM1_AUTHORITY_TRANSFER_WRITE_FENCED", {"state": _state, "active_authority_id": _active_authority_id, "authority_epoch": _authority_epoch})
	if authority_epoch < _authority_epoch:
		_counters["write_rejections"] = int(_counters["write_rejections"]) + 1
		return _failure("SM1_STALE_AUTHORITY_EPOCH", {"current_epoch": _authority_epoch, "provided_epoch": authority_epoch})
	if authority_id != _active_authority_id:
		_counters["write_rejections"] = int(_counters["write_rejections"]) + 1
		return _failure("SM1_NOT_ACTIVE_AUTHORITY", {"active_authority_id": _active_authority_id})
	if authority_epoch != _authority_epoch:
		_counters["write_rejections"] = int(_counters["write_rejections"]) + 1
		return _failure("SM1_AUTHORITY_EPOCH_MISMATCH", {"current_epoch": _authority_epoch, "provided_epoch": authority_epoch})
	_counters["write_authorizations"] = int(_counters["write_authorizations"]) + 1
	return _success({"result": "WRITE_AUTHORIZED", "authority_id": authority_id, "authority_epoch": authority_epoch})


func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"state": _state,
		"active_authority_id": _active_authority_id,
		"authority_epoch": _authority_epoch,
		"player_snapshot": _player_snapshot.duplicate(true),
		"transfer": _transfer.duplicate(true),
		"completed_transfer_count": _completed_transfers.size(),
		"private_item_graph": false,
		"private_construction_truth": false,
		"private_persistence_owner": false,
		"private_replay_owner": false,
	}


func get_report() -> Dictionary:
	var report := snapshot()
	report["counters"] = _counters.duplicate(true)
	report["one_writer_policy"] = "ACTIVE_TUPLE_ONLY_ZERO_WRITER_TRANSFER_GAP"
	return report


func get_completed_transfer(transfer_id: String) -> Dictionary:
	if not _completed_transfers.has(transfer_id):
		return {}
	return Dictionary(_completed_transfers[transfer_id]).duplicate(true)


func _matches_live_transfer(transfer_id: String) -> bool:
	return not _transfer.is_empty() and transfer_id == String(_transfer.get("transfer_id", ""))


func _tuple_matches(source_authority_id: String, target_authority_id: String, source_epoch: int, target_epoch: int) -> bool:
	return source_authority_id == String(_transfer.get("source_authority_id", "")) \
		and target_authority_id == String(_transfer.get("target_authority_id", "")) \
		and source_epoch == int(_transfer.get("source_epoch", 0)) \
		and target_epoch == int(_transfer.get("target_epoch", 0))


func _source_and_token_match(source_authority_id: String, commit_token: String) -> bool:
	return source_authority_id == String(_transfer.get("source_authority_id", "")) \
		and not commit_token.is_empty() \
		and commit_token == String(_transfer.get("commit_token", ""))


func _validate_player_snapshot(player_snapshot: Dictionary) -> Dictionary:
	var logical_player_id := String(player_snapshot.get("logical_player_id", "")).strip_edges()
	var player_entity_id := String(player_snapshot.get("player_entity_id", "")).strip_edges()
	if logical_player_id.is_empty() or player_entity_id.is_empty():
		return _failure("SM1_PLAYER_IDENTITY_REQUIRED")
	if int(player_snapshot.get("last_input_sequence", -1)) < 0:
		return _failure("SM1_INPUT_SEQUENCE_INVALID")
	if not player_snapshot.has("last_operation_id") or typeof(player_snapshot.get("last_operation_id")) != TYPE_STRING:
		return _failure("SM1_OPERATION_WATERMARK_INVALID")
	return _success({})


static func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
