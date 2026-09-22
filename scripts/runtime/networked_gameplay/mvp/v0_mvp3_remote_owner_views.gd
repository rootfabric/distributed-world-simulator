extends RefCounted

# These are authenticated read models, NOT new decision/identity/replay owners.
const Protocol = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

class DecisionView:
	extends RefCounted
	var actor := ""
	var _view: Dictionary = {}
	var _completed: Dictionary = {}

	func ingest(player: String, view: Dictionary, completed: Dictionary) -> Dictionary:
		if not actor.is_empty() and actor != player:
			return {"success": false, "error_code": "MVP3_DECISION_ACTOR_CHANGED"}
		var row: Dictionary = view.get("player_snapshot", {})
		var epoch = view.get("authority_epoch")
		if row.get("logical_player_id") != "player/mvp3/" + player or row.get("player_entity_id") != "entity/mvp3/" + player or typeof(epoch) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(epoch)) or float(epoch) != floorf(float(epoch)) or int(epoch) < 1:
			return {"success": false, "error_code": "MVP3_DECISION_IDENTITY_INVALID"}
		if not _view.is_empty() and int(epoch) < int(_view["authority_epoch"]):
			return {"success": false, "error_code": "MVP3_DECISION_ROLLBACK_REJECTED"}
		if _view.is_empty() and (int(epoch) != 1 or view.get("state") != "ACTIVE" or view.get("active_authority_id") != "authority/a"):
			return {"success": false, "error_code": "MVP3_DECISION_BOOTSTRAP_INVALID"}
		if not completed.is_empty():
			if completed.get("completed") != true or completed.get("transfer_id", "").is_empty() or completed.get("target_epoch") != epoch:
				return {"success": false, "error_code": "MVP3_COMPLETED_DECISION_INVALID"}
			_completed[String(completed["transfer_id"])] = completed.duplicate(true)
			if _completed.size() > 8:
				return {"success": false, "error_code": "MVP3_BOUNDED_TRANSFER_BUDGET_EXCEEDED"}
		actor = player
		_view = view.duplicate(true)
		return {"success": true}

	func snapshot() -> Dictionary:
		return _view.duplicate(true)

	func get_completed_transfer(transfer_id: String) -> Dictionary:
		return Dictionary(_completed.get(transfer_id, {})).duplicate(true)

	func authorize_write(authority: String, epoch: int) -> Dictionary:
		var permitted: bool = _view.get("state") == "ACTIVE" and _view.get("active_authority_id") == authority and _view.get("authority_epoch") == epoch
		return {"success": permitted, "error_code": "" if permitted else "SM1_AUTHORITY_TRANSFER_WRITE_FENCED", "details": {"read_model_only": true}}

class SourceReceiptView:
	extends RefCounted
	const Auth = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
	var config: Dictionary = {}
	var source_authority := ""
	var source_key := ""
	var _last_sequence := 0
	var _prepared: Dictionary = {}
	var _retired: Dictionary = {}

	func ingest(signed_source_reply: Dictionary) -> Dictionary:
		if not Auth.verify(config, signed_source_reply, source_authority, "gateway", source_key):
			return Auth.failure("MVP3_SOURCE_RECEIPT_AUTH_INVALID")
		var sequence := int(signed_source_reply["sequence"])
		if sequence < _last_sequence:
			return Auth.failure("MVP3_SOURCE_RECEIPT_ROLLBACK")
		var body: Dictionary = signed_source_reply["body"]
		if body.get("success") != true or not body.get("details") is Dictionary:
			return Auth.failure("MVP3_SOURCE_RECEIPT_NOT_SUCCESSFUL")
		var result: Dictionary = body["details"].get("result", {})
		if result.get("success") != true:
			return Auth.failure("MVP3_NATIVE_SOURCE_RECEIPT_REJECTED")
		var details: Dictionary = result.get("details", {})
		if details.get("packet") is Dictionary:
			var packet: Dictionary = details["packet"]
			if packet.get("source_authority_id") != source_authority or packet.get("logical_player_id") not in ["a", "b"]:
				return Auth.failure("MVP3_SOURCE_RECEIPT_IDENTITY_INVALID")
			_prepared[packet["logical_player_id"]] = packet.duplicate(true)
		elif details.get("receipt") is Dictionary:
			var receipt: Dictionary = details["receipt"]
			var actor := String(body["details"].get("actor", ""))
			if actor not in ["a", "b"] or receipt.get("source_authority_id") != source_authority or receipt.get("source_locally_fenced") != true:
				return Auth.failure("MVP3_RETIRE_RECEIPT_IDENTITY_INVALID")
			_retired[actor] = receipt.duplicate(true)
		else:
			return Auth.failure("MVP3_SOURCE_RECEIPT_KIND_INVALID")
		_last_sequence = sequence
		return Auth.success()

	func get_prepared_export(actor: String, transfer_id: String) -> Dictionary:
		var packet: Dictionary = _prepared.get(actor, {})
		return packet.duplicate(true) if packet.get("transfer_id") == transfer_id else {}

	func get_retirement_receipt(actor: String, transfer_id: String) -> Dictionary:
		var receipt: Dictionary = _retired.get(actor, {})
		return receipt.duplicate(true) if receipt.get("transfer_id") == transfer_id else {}
