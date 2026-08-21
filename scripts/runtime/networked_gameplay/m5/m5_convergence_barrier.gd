extends RefCounted

const CLIENT_WAIT := "WAIT"
const CLIENT_REVOKE := "REVOKE"
const CLIENT_CONSUME_RELEASE := "CONSUME_RELEASE"

const COORDINATOR_WAIT := "WAIT"
const COORDINATOR_RELEASE := "RELEASE"
const COORDINATOR_COMPLETE := "COMPLETE"
const COORDINATOR_ABANDON := "ABANDON"
const COORDINATOR_FAILED := "FAILED"


static func generation_id(generation: int, player_checksum: String, item_checksum: String) -> String:
	return "m5-convergence/%d/%s/%s" % [generation, player_checksum.left(12), item_checksum.left(12)]


static func evaluate_prepared_release(
	prepared_id: String,
	prepared_player_checksum: String,
	prepared_item_checksum: String,
	control_prepare: Dictionary,
	release_id: String,
	current_player_checksum: String,
	current_item_checksum: String
) -> Dictionary:
	var control_id := String(control_prepare.get("id", "")).strip_edges()
	var control_player_checksum := String(control_prepare.get("player_checksum", ""))
	var control_item_checksum := String(control_prepare.get("item_checksum", ""))
	if (
		prepared_id.is_empty()
		or prepared_player_checksum.is_empty()
		or prepared_item_checksum.is_empty()
	):
		return _client_decision(CLIENT_REVOKE, "PREPARED_TARGET_INCOMPLETE", current_player_checksum, current_item_checksum)
	if control_id != prepared_id:
		return _client_decision(CLIENT_REVOKE, "PREPARE_GENERATION_CHANGED", current_player_checksum, current_item_checksum)
	if control_player_checksum != prepared_player_checksum or control_item_checksum != prepared_item_checksum:
		return _client_decision(CLIENT_REVOKE, "PREPARE_TARGET_CHANGED", current_player_checksum, current_item_checksum)
	if current_player_checksum.is_empty() or current_item_checksum.is_empty():
		return _client_decision(CLIENT_REVOKE, "CURRENT_AUTHORITATIVE_CHECKSUM_EMPTY", current_player_checksum, current_item_checksum)
	if (
		current_player_checksum != prepared_player_checksum
		or current_item_checksum != prepared_item_checksum
	):
		return _client_decision(CLIENT_REVOKE, "CURRENT_AUTHORITATIVE_STATE_ADVANCED", current_player_checksum, current_item_checksum)
	if String(release_id).strip_edges() == prepared_id:
		return _client_decision(CLIENT_CONSUME_RELEASE, "EXACT_PREPARED_TARGET_STILL_CURRENT", current_player_checksum, current_item_checksum)
	return _client_decision(CLIENT_WAIT, "WAITING_FOR_RELEASE", current_player_checksum, current_item_checksum)


static func evaluate_coordinator_generation(
	generation: String,
	target_player_checksum: String,
	target_item_checksum: String,
	release_sent: bool,
	a_report: Dictionary,
	b_report: Dictionary
) -> Dictionary:
	if generation.is_empty() or target_player_checksum.is_empty() or target_item_checksum.is_empty():
		return _coordinator_decision(COORDINATOR_ABANDON, "TARGET_INCOMPLETE")
	for report_value in [a_report, b_report]:
		var report: Dictionary = report_value
		var state := String(report.get("state", ""))
		if state == "FAILED":
			return _coordinator_decision(COORDINATOR_FAILED, "CLIENT_FAILED")
		if (
			String(report.get("player_checksum", "")) != target_player_checksum
			or String(report.get("item_checksum", "")) != target_item_checksum
		):
			return _coordinator_decision(COORDINATOR_ABANDON, "CLIENT_TARGET_CHANGED")
		if state in ["CONVERGENCE_PREPARED", "CONVERGENCE_RELEASED"]:
			if String(report.get("convergence_prepare_id", "")) != generation:
				return _coordinator_decision(COORDINATOR_ABANDON, "CLIENT_GENERATION_CHANGED")
	if release_sent:
		var a_released := _report_released_for(a_report, generation)
		var b_released := _report_released_for(b_report, generation)
		if a_released and b_released:
			return _coordinator_decision(COORDINATOR_COMPLETE, "BOTH_RELEASES_CONSUMED")
		for report_value in [a_report, b_report]:
			var report: Dictionary = report_value
			var state := String(report.get("state", ""))
			if state in ["READY_TO_CONVERGE", "CONVERGENCE_LOCKED"]:
				return _coordinator_decision(COORDINATOR_ABANDON, "PREPARED_ACK_REVOKED_AFTER_RELEASE")
			if state == "CONVERGENCE_PREPARED" and not bool(report.get("convergence_prepared", false)):
				return _coordinator_decision(COORDINATOR_ABANDON, "PREPARED_FLAG_REVOKED_AFTER_RELEASE")
		return _coordinator_decision(COORDINATOR_WAIT, "WAITING_FOR_BOTH_RELEASES")
	var a_prepared := _report_prepared_for(a_report, generation)
	var b_prepared := _report_prepared_for(b_report, generation)
	if a_prepared and b_prepared:
		return _coordinator_decision(COORDINATOR_RELEASE, "BOTH_PREPARED")
	if String(a_report.get("state", "")) == "CONVERGENCE_RELEASED" or String(b_report.get("state", "")) == "CONVERGENCE_RELEASED":
		return _coordinator_decision(COORDINATOR_ABANDON, "RELEASED_BEFORE_COORDINATOR_RELEASE")
	return _coordinator_decision(COORDINATOR_WAIT, "WAITING_FOR_BOTH_PREPARED")


static func _report_prepared_for(report: Dictionary, generation: String) -> bool:
	return (
		String(report.get("state", "")) == "CONVERGENCE_PREPARED"
		and bool(report.get("convergence_prepared", false))
		and String(report.get("convergence_prepare_id", "")) == generation
		and not bool(report.get("convergence_release_consumed", false))
	)


static func _report_released_for(report: Dictionary, generation: String) -> bool:
	return (
		String(report.get("state", "")) == "CONVERGENCE_RELEASED"
		and bool(report.get("convergence_prepared", false))
		and bool(report.get("convergence_release_consumed", false))
		and String(report.get("convergence_prepare_id", "")) == generation
		and String(report.get("convergence_release_id", "")) == generation
	)


static func _client_decision(action: String, reason: String, player_checksum: String, item_checksum: String) -> Dictionary:
	return {
		"action": action,
		"reason": reason,
		"current_player_checksum": player_checksum,
		"current_item_checksum": item_checksum,
	}


static func _coordinator_decision(action: String, reason: String) -> Dictionary:
	return {"action": action, "reason": reason}
