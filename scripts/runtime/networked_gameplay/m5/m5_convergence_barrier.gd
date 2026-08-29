extends RefCounted

const CLIENT_WAIT := "WAIT"
const CLIENT_REVOKE := "REVOKE"
const CLIENT_CONSUME_RELEASE := "CONSUME_RELEASE"
const CLIENT_HOLD_RELEASE := "HOLD_RELEASE"
const CLIENT_COMPLETE_RELEASE := "COMPLETE_RELEASE"
const CLIENT_FAIL_RELEASE := "FAIL_RELEASE"

const COORDINATOR_WAIT := "WAIT"
const COORDINATOR_RELEASE := "RELEASE"
const COORDINATOR_COMPLETE := "COMPLETE"
const COORDINATOR_ABANDON := "ABANDON"
const COORDINATOR_FAILED := "FAILED"


static func generation_id(generation: int, player_checksum: String, item_checksum: String) -> String:
	return "m5-convergence/%d/%s/%s" % [generation, player_checksum.left(12), item_checksum.left(12)]


static func observations_identical(a: Dictionary, b: Dictionary) -> bool:
	for field in ["checksum", "revision", "server_tick", "authority_owner_id", "authority_epoch"]:
		if a.get(field) != b.get(field):
			return false
	return (
		not String(a.get("checksum", "")).is_empty()
		and int(a.get("revision", -1)) >= 0
		and int(a.get("server_tick", -1)) >= 0
		and not String(a.get("authority_owner_id", "")).is_empty()
		and int(a.get("authority_epoch", 0)) >= 1
	)


static func evaluate_observed_state_progress(
	prepared_observation: Dictionary,
	current_observation: Dictionary
) -> Dictionary:
	if (
		String(prepared_observation.get("checksum", "")).is_empty()
		or int(prepared_observation.get("revision", -1)) < 0
		or int(prepared_observation.get("server_tick", -1)) < 0
		or String(prepared_observation.get("authority_owner_id", "")).is_empty()
		or int(prepared_observation.get("authority_epoch", 0)) < 1
	):
		return {"success": false, "reason": "PREPARED_OBSERVED_STATE_IDENTITY_INCOMPLETE"}
	if (
		String(current_observation.get("checksum", "")).is_empty()
		or int(current_observation.get("revision", -1)) < 0
		or int(current_observation.get("server_tick", -1)) < 0
	):
		return {"success": false, "reason": "CURRENT_OBSERVED_STATE_IDENTITY_INCOMPLETE"}
	if String(current_observation.get("authority_owner_id", "")) != String(prepared_observation.get("authority_owner_id", "")):
		return {"success": false, "reason": "AUTHORITY_OWNER_CHANGED_AFTER_OBSERVATION"}
	if int(current_observation.get("authority_epoch", 0)) != int(prepared_observation.get("authority_epoch", 0)):
		return {"success": false, "reason": "AUTHORITY_EPOCH_CHANGED_AFTER_OBSERVATION"}
	if int(current_observation.get("revision", -1)) < int(prepared_observation.get("revision", -1)):
		return {"success": false, "reason": "PLAYER_REVISION_REGRESSED_AFTER_OBSERVATION"}
	if int(current_observation.get("server_tick", -1)) < int(prepared_observation.get("server_tick", -1)):
		return {"success": false, "reason": "PLAYER_SERVER_TICK_REGRESSED_AFTER_OBSERVATION"}
	return {"success": true, "reason": "OBSERVED_STATE_PROGRESS_MONOTONIC"}


static func evaluate_prepared_release(
	prepared_id: String,
	prepared_player_observation: Dictionary,
	prepared_item_checksum: String,
	control_prepare: Dictionary,
	release_id: String,
	current_player_observation: Dictionary,
	current_item_checksum: String
) -> Dictionary:
	var control_id := String(control_prepare.get("id", "")).strip_edges()
	var control_player_checksum := String(control_prepare.get("player_checksum", ""))
	var control_observation: Dictionary = Dictionary(control_prepare.get("player_observation", {}))
	var control_item_checksum := String(control_prepare.get("item_checksum", ""))
	var prepared_player_checksum := String(prepared_player_observation.get("checksum", ""))
	var current_player_checksum := String(current_player_observation.get("checksum", ""))
	if prepared_id.is_empty() or prepared_player_checksum.is_empty() or prepared_item_checksum.is_empty():
		return _client_decision(CLIENT_REVOKE, "PREPARED_TARGET_INCOMPLETE", current_player_checksum, current_item_checksum)
	if control_id != prepared_id:
		return _client_decision(CLIENT_REVOKE, "PREPARE_GENERATION_CHANGED", current_player_checksum, current_item_checksum)
	if (
		control_player_checksum != prepared_player_checksum
		or not observations_identical(control_observation, prepared_player_observation)
		or control_item_checksum != prepared_item_checksum
	):
		return _client_decision(CLIENT_REVOKE, "PREPARE_TARGET_CHANGED", current_player_checksum, current_item_checksum)
	if current_item_checksum.is_empty() or current_item_checksum != prepared_item_checksum:
		return _client_decision(CLIENT_REVOKE, "ITEM_GRAPH_ADVANCED_AFTER_PREPARE", current_player_checksum, current_item_checksum)
	var progress := evaluate_observed_state_progress(prepared_player_observation, current_player_observation)
	if not bool(progress.get("success", false)):
		return _client_decision(CLIENT_REVOKE, String(progress.get("reason", "OBSERVED_STATE_PROGRESS_INVALID")), current_player_checksum, current_item_checksum)
	if String(release_id).strip_edges() == prepared_id:
		return _client_decision(CLIENT_CONSUME_RELEASE, "PINNED_OBSERVED_STATE_IDENTITY_RELEASED", current_player_checksum, current_item_checksum)
	return _client_decision(CLIENT_WAIT, "WAITING_FOR_RELEASE", current_player_checksum, current_item_checksum)


static func evaluate_consumed_release_integrity(
	consumed_id: String,
	prepared_player_observation: Dictionary,
	prepared_item_checksum: String,
	control_prepare: Dictionary,
	release_id: String,
	complete_id: String,
	current_player_observation: Dictionary,
	current_item_checksum: String
) -> Dictionary:
	var control_id := String(control_prepare.get("id", "")).strip_edges()
	var control_player_checksum := String(control_prepare.get("player_checksum", ""))
	var control_observation: Dictionary = Dictionary(control_prepare.get("player_observation", {}))
	var control_item_checksum := String(control_prepare.get("item_checksum", ""))
	var prepared_player_checksum := String(prepared_player_observation.get("checksum", ""))
	var current_player_checksum := String(current_player_observation.get("checksum", ""))
	if consumed_id.is_empty():
		return _client_decision(CLIENT_FAIL_RELEASE, "CONSUMED_GENERATION_EMPTY", current_player_checksum, current_item_checksum)
	if control_id != consumed_id:
		return _client_decision(CLIENT_FAIL_RELEASE, "CONTROL_GENERATION_REGRESSED_AFTER_RELEASE", current_player_checksum, current_item_checksum)
	if String(release_id).strip_edges() != consumed_id:
		return _client_decision(CLIENT_FAIL_RELEASE, "RELEASE_ID_REGRESSED_AFTER_CONSUMPTION", current_player_checksum, current_item_checksum)
	if (
		control_player_checksum != prepared_player_checksum
		or not observations_identical(control_observation, prepared_player_observation)
		or control_item_checksum != prepared_item_checksum
	):
		return _client_decision(CLIENT_FAIL_RELEASE, "PREPARED_TARGET_CHANGED_AFTER_RELEASE", current_player_checksum, current_item_checksum)
	if current_item_checksum.is_empty() or current_item_checksum != prepared_item_checksum:
		return _client_decision(CLIENT_FAIL_RELEASE, "ITEM_GRAPH_ADVANCED_AFTER_RELEASE", current_player_checksum, current_item_checksum)
	var progress := evaluate_observed_state_progress(prepared_player_observation, current_player_observation)
	if not bool(progress.get("success", false)):
		return _client_decision(CLIENT_FAIL_RELEASE, String(progress.get("reason", "OBSERVED_STATE_PROGRESS_INVALID")), current_player_checksum, current_item_checksum)
	# Exact COMPLETE seals the pinned observation checkpoint, while the live
	# player snapshot is allowed to be a monotonic descendant of that checkpoint.
	if String(complete_id).strip_edges() == consumed_id:
		return _client_decision(CLIENT_COMPLETE_RELEASE, "PINNED_OBSERVED_STATE_IDENTITY_COMPLETE", current_player_checksum, current_item_checksum)
	return _client_decision(CLIENT_HOLD_RELEASE, "WAITING_FOR_COORDINATOR_COMPLETE", current_player_checksum, current_item_checksum)


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
	var observation: Dictionary = Dictionary(report.get("player_observation", {}))
	var prepared_observation: Dictionary = Dictionary(report.get("prepared_player_observation", {}))
	return (
		String(report.get("state", "")) == "CONVERGENCE_PREPARED"
		and bool(report.get("convergence_prepared", false))
		and String(report.get("convergence_prepare_id", "")) == generation
		and not bool(report.get("convergence_release_consumed", false))
		and observations_identical(observation, prepared_observation)
		and String(prepared_observation.get("checksum", "")) == String(report.get("player_checksum", ""))
	)


static func _report_released_for(report: Dictionary, generation: String) -> bool:
	var observation: Dictionary = Dictionary(report.get("player_observation", {}))
	var prepared_observation: Dictionary = Dictionary(report.get("prepared_player_observation", {}))
	return (
		String(report.get("state", "")) == "CONVERGENCE_RELEASED"
		and bool(report.get("convergence_prepared", false))
		and bool(report.get("convergence_release_consumed", false))
		and String(report.get("convergence_prepare_id", "")) == generation
		and String(report.get("convergence_release_id", "")) == generation
		and observations_identical(observation, prepared_observation)
		and String(prepared_observation.get("checksum", "")) == String(report.get("player_checksum", ""))
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
