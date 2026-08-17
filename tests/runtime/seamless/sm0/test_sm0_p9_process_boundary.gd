extends SceneTree

const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p9_foreign_item_boundary_contract.gd")

var _ports := {Contract.AUTHORITY_A: 26820, Contract.AUTHORITY_C: 26822, Contract.SHIP_AUTHORITY: 26823}
var _socket: PacketPeerUDP
var _request_counter := 0
var _assertions := 0
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_socket = PacketPeerUDP.new()
	var bind_result := _socket.bind(26830, "127.0.0.1")
	_check(bind_result == OK, "scenario reply socket bind")
	if _failed:
		return _finish()

	var foreign := Contract.create_item_envelope("item/p9/process/foreign-01", Contract.AUTHORITY_A, Contract.SCOPE_WORLD, 1, 1, 0)
	var native := Contract.create_item_envelope("item/p9/process/native-01", Contract.SHIP_AUTHORITY, Contract.SCOPE_SHIP, 1, 1, 0)
	_check_success(await _command(Contract.AUTHORITY_A, "SEED", {"item":foreign}), "seed A foreign")
	_check_success(await _command(Contract.SHIP_AUTHORITY, "SEED", {"item":native}), "seed ship native")

	var direct_request := Contract.create_interaction_request("operation/p9/process/direct/1", Contract.SHIP_AUTHORITY, foreign, Contract.INTERACTION_INSPECT)
	var direct := await _command(Contract.SHIP_AUTHORITY, "INTERACT", {"request":direct_request})
	_check(not bool(direct.get("success", true)), "process direct foreign interaction rejected")
	_check(String(direct.get("error_code", "")) == "SM0_P9_FOREIGN_DIRECT_MUTATION_FORBIDDEN", "process direct foreign exact error")

	var routed := await _command(Contract.AUTHORITY_A, "INTERACT", {"request":direct_request})
	_check_success(routed, "process foreign interaction executes at A")
	var interacted := Dictionary(Dictionary(routed.get("details", {})).get("item", {}))
	_check(int(interacted.get("item_revision", 0)) == 2, "process routed interaction revision")
	_check(int(interacted.get("interaction_sequence", 0)) == 1, "process routed interaction sequence")

	var import_request := Contract.create_transfer_request("operation/p9/process/import/1", interacted, Contract.SHIP_AUTHORITY, Contract.SCOPE_SHIP)
	_check_success(await _command(Contract.AUTHORITY_A, "PREPARE_SEND", {"request":import_request}), "process import source prepare")
	var target_prepare := await _command(Contract.SHIP_AUTHORITY, "PREPARE_RECEIVE", {"request":import_request})
	_check_success(target_prepare, "process import target shadow prepare")
	var a_before_commit := await _status(Contract.AUTHORITY_A)
	var ship_before_commit := await _status(Contract.SHIP_AUTHORITY)
	_check(_status_has_item(a_before_commit, "item/p9/process/foreign-01"), "source remains active before process commit")
	_check(not _status_has_item(ship_before_commit, "item/p9/process/foreign-01"), "target shadow not active before process commit")
	var frozen_process_interaction := Contract.create_interaction_request("operation/p9/process/frozen/1", Contract.SHIP_AUTHORITY, interacted, Contract.INTERACTION_USE)
	var frozen_process_result := await _command(Contract.AUTHORITY_A, "INTERACT", {"request":frozen_process_interaction})
	_check(not bool(frozen_process_result.get("success", true)), "process source interaction frozen during prepare")
	_check(String(frozen_process_result.get("error_code", "")) == "SM0_P9_ITEM_TRANSFER_FROZEN", "process frozen interaction exact error")
	var source_commit := await _command(Contract.AUTHORITY_A, "COMMIT_SEND", {"request":import_request})
	_check_success(source_commit, "process import source retire")
	var retirement := Dictionary(Dictionary(source_commit.get("details", {})).get("retirement_proof", {}))
	var receive_commit := await _command(Contract.SHIP_AUTHORITY, "COMMIT_RECEIVE", {"request":import_request, "retirement_proof":retirement})
	_check_success(receive_commit, "process import target activate")
	var imported := Dictionary(Dictionary(receive_commit.get("details", {})).get("item", {}))
	_check(String(imported.get("item_id", "")) == "item/p9/process/foreign-01", "process import stable item id")
	_check(String(imported.get("owner_authority_id", "")) == Contract.SHIP_AUTHORITY, "process import owner ship")
	_check(int(imported.get("ownership_epoch", 0)) == 2, "process import ownership epoch 2")
	_check(int(imported.get("item_revision", 0)) == 3, "process import revision 3")
	var a_after_import := await _status(Contract.AUTHORITY_A)
	var ship_after_import := await _status(Contract.SHIP_AUTHORITY)
	_check(not _status_has_item(a_after_import, "item/p9/process/foreign-01"), "process A retired foreign item")
	_check(_status_has_item(ship_after_import, "item/p9/process/foreign-01"), "process ship owns imported item")

	var send_replay := await _command(Contract.AUTHORITY_A, "COMMIT_SEND", {"request":import_request})
	_check_success(send_replay, "process source commit replay accepted")
	_check(bool(Dictionary(send_replay.get("details", {})).get("replay", false)), "process source commit replay identified")
	var receive_replay := await _command(Contract.SHIP_AUTHORITY, "COMMIT_RECEIVE", {"request":import_request, "retirement_proof":retirement})
	_check_success(receive_replay, "process target commit replay accepted")
	_check(bool(Dictionary(receive_replay.get("details", {})).get("replay", false)), "process target commit replay identified")
	var imported_after_replay := _status_item(await _status(Contract.SHIP_AUTHORITY), "item/p9/process/foreign-01")
	_check(int(imported_after_replay.get("ownership_epoch", 0)) == 2, "process replay ownership mutation-free")
	_check(int(imported_after_replay.get("item_revision", 0)) == 3, "process replay revision mutation-free")

	var local_use := Contract.create_interaction_request("operation/p9/process/use/1", Contract.SHIP_AUTHORITY, imported_after_replay, Contract.INTERACTION_USE)
	var local_use_result := await _command(Contract.SHIP_AUTHORITY, "INTERACT", {"request":local_use})
	_check_success(local_use_result, "process imported item local use")
	var used := Dictionary(Dictionary(local_use_result.get("details", {})).get("item", {}))
	_check(int(used.get("item_revision", 0)) == 4, "process local use revision 4")
	_check(int(used.get("interaction_sequence", 0)) == 2, "process local use sequence 2")

	var export_request := Contract.create_transfer_request("operation/p9/process/export/1", used, Contract.AUTHORITY_C, Contract.SCOPE_WORLD)
	_check_success(await _command(Contract.SHIP_AUTHORITY, "PREPARE_SEND", {"request":export_request}), "process export source prepare")
	_check_success(await _command(Contract.AUTHORITY_C, "PREPARE_RECEIVE", {"request":export_request}), "process export target prepare")
	var export_source_commit := await _command(Contract.SHIP_AUTHORITY, "COMMIT_SEND", {"request":export_request})
	_check_success(export_source_commit, "process export source retire")
	var export_proof := Dictionary(Dictionary(export_source_commit.get("details", {})).get("retirement_proof", {}))
	var export_target_commit := await _command(Contract.AUTHORITY_C, "COMMIT_RECEIVE", {"request":export_request, "retirement_proof":export_proof})
	_check_success(export_target_commit, "process export target activate C")
	var exported := Dictionary(Dictionary(export_target_commit.get("details", {})).get("item", {}))
	_check(String(exported.get("owner_authority_id", "")) == Contract.AUTHORITY_C, "process export current world owner C")
	_check(String(exported.get("authority_scope", "")) == Contract.SCOPE_WORLD, "process export world scope")
	_check(int(exported.get("ownership_epoch", 0)) == 3, "process export ownership epoch 3")
	_check(int(exported.get("item_revision", 0)) == 5, "process export revision 5")
	_check(_status_has_item(await _status(Contract.AUTHORITY_C), "item/p9/process/foreign-01"), "process C owns exported item")
	_check(not _status_has_item(await _status(Contract.SHIP_AUTHORITY), "item/p9/process/foreign-01"), "process ship retires exported item")
	_check(_status_has_item(await _status(Contract.SHIP_AUTHORITY), "item/p9/process/native-01"), "process ship-native item survives")

	var rollback_item := Contract.create_item_envelope("item/p9/process/rollback-01", Contract.AUTHORITY_C, Contract.SCOPE_WORLD, 1, 1, 0)
	_check_success(await _command(Contract.AUTHORITY_C, "SEED", {"item":rollback_item}), "process seed rollback item")
	var rollback_request := Contract.create_transfer_request("operation/p9/process/rollback/1", rollback_item, Contract.SHIP_AUTHORITY, Contract.SCOPE_SHIP)
	_check_success(await _command(Contract.AUTHORITY_C, "PREPARE_SEND", {"request":rollback_request}), "process rollback source prepare")
	_check_success(await _command(Contract.SHIP_AUTHORITY, "PREPARE_RECEIVE", {"request":rollback_request}), "process rollback target prepare")
	_check_success(await _command(Contract.SHIP_AUTHORITY, "FAIL_NEXT_RECEIVE_COMMIT", {}), "arm process target failure")
	var rollback_source_commit := await _command(Contract.AUTHORITY_C, "COMMIT_SEND", {"request":rollback_request})
	_check_success(rollback_source_commit, "process rollback source retires")
	var rollback_proof := Dictionary(Dictionary(rollback_source_commit.get("details", {})).get("retirement_proof", {}))
	var failed_target := await _command(Contract.SHIP_AUTHORITY, "COMMIT_RECEIVE", {"request":rollback_request, "retirement_proof":rollback_proof})
	_check(not bool(failed_target.get("success", true)), "process injected target failure returned")
	_check(String(failed_target.get("error_code", "")) == "SM0_P9_INJECTED_TARGET_COMMIT_FAILURE", "process target failure exact error")
	_check_success(await _command(Contract.AUTHORITY_C, "ROLLBACK_SEND", {"request":rollback_request}), "process source rollback")
	_check_success(await _command(Contract.SHIP_AUTHORITY, "ABORT_RECEIVE", {"request":rollback_request}), "process target abort shadow")
	var c_after_rollback := await _status(Contract.AUTHORITY_C)
	var ship_after_rollback := await _status(Contract.SHIP_AUTHORITY)
	var rollback_restored := _status_item(c_after_rollback, "item/p9/process/rollback-01")
	_check(not rollback_restored.is_empty(), "process rollback source item restored")
	_check(int(rollback_restored.get("ownership_epoch", 0)) == 1, "process rollback epoch restored")
	_check(int(rollback_restored.get("item_revision", 0)) == 1, "process rollback revision restored")
	_check(not _status_has_item(ship_after_rollback, "item/p9/process/rollback-01"), "process rollback target not active")

	for authority_id in [Contract.AUTHORITY_A, Contract.AUTHORITY_C, Contract.SHIP_AUTHORITY]:
		await _command(String(authority_id), "SHUTDOWN", {})
	_finish()

func _command(authority_id: String, command: String, payload: Dictionary) -> Dictionary:
	_request_counter += 1
	var request_id := "p9-process-%d" % _request_counter
	var message := {"request_id":request_id, "command":command, "payload":payload.duplicate(true)}
	var port := int(_ports.get(authority_id, 0))
	if port < 1 or _socket.set_dest_address("127.0.0.1", port) != OK:
		return {"success":false, "error_code":"SM0_P9_SCENARIO_DESTINATION_INVALID", "details":{}}
	_socket.put_packet(JSON.stringify(message, "", false, true).to_utf8_buffer())
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		while _socket.get_available_packet_count() > 0:
			var decoded = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
			if decoded is Dictionary and String(Dictionary(decoded).get("request_id", "")) == request_id:
				return Dictionary(decoded)
		await process_frame
	return {"success":false, "error_code":"SM0_P9_SCENARIO_TIMEOUT", "details":{"authority_id":authority_id, "command":command}}

func _status(authority_id: String) -> Dictionary:
	var result := await _command(authority_id, "STATUS", {})
	if not bool(result.get("success", false)):
		return {}
	return Dictionary(Dictionary(result.get("details", {})).get("status", {}))

static func _status_has_item(status: Dictionary, item_id: String) -> bool:
	return Dictionary(status.get("active_items", {})).has(item_id)

static func _status_item(status: Dictionary, item_id: String) -> Dictionary:
	return Dictionary(Dictionary(status.get("active_items", {})).get(item_id, {})).duplicate(true)

func _check_success(result: Dictionary, label: String) -> void:
	_check(bool(result.get("success", false)), "%s: %s" % [label, String(result.get("error_code", ""))])

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	_failed = true
	push_error("P9 process assertion failed: %s" % label)

func _finish() -> void:
	if _socket != null:
		_socket.close()
	print("SM0 P9 process-isolated boundary: %s (%d assertions)" % ["FAIL" if _failed else "PASS", _assertions])
	quit(1 if _failed else 0)