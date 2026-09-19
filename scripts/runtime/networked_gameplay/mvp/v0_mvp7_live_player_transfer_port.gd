extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_live_item_player_transfer_port.gd"

# Read-only reconciliation of the EXISTING native player/item owners. This port
# does not choose an authority, detach gates, or make retired rows writable.
func checkpoint_binding_view7() -> Dictionary:
	if _owner_ref == null or _owner_ref.get_ref() == null or _gates.is_empty():
		return _failure("MVP7_LIVE_BINDINGS_REQUIRED")
	if not _staged.is_empty() or not _installing.is_empty():
		return _failure("MVP7_IN_FLIGHT_PLAYER_TRANSFER")
	if int(_registry.get_report().get("read_only_live_stage_count", -1)) != 0:
		return _failure("MVP7_IN_FLIGHT_REGISTRY_STAGE")
	var items: Dictionary = _items.get_live_item_report()
	if items.get("enabled") != true or int(items.get("stage_count", -1)) != 0:
		return _failure("MVP7_IN_FLIGHT_ITEM_TRANSFER")
	var bindings: Dictionary = {}
	var local_players: Array = []
	var actors: Array = _gates.keys()
	actors.sort()
	for actor_value in actors:
		var actor := String(actor_value)
		var gate = _gates[actor]
		var report: Dictionary = gate.get_report()
		var decision: Dictionary = report.get("decision", {})
		if decision.get("state") != "ACTIVE" or int(decision.get("authority_epoch", 0)) < 1:
			return _failure("MVP7_HANDOFF_NOT_QUIESCENT")
		var local := String(decision.get("active_authority_id", "")) == _authority
		if String(decision.get("active_authority_id", "")).is_empty() or gate.is_locally_ready() != local:
			return _failure("MVP7_DECISION_AND_NATIVE_READINESS_DIVERGED")
		var player: Dictionary = _registry.get_player(actor)
		var ownership: Dictionary = _ownership.get_player(actor)
		if player.is_empty() == local or ownership.is_empty() == local:
			return _failure("MVP7_DECISION_AND_NATIVE_ROWS_DIVERGED")
		if local:
			for row in [player, ownership]:
				var valid: Dictionary = gate.validate_record_identity(row)
				if not bool(valid.get("success", false)): return valid
			local_players.append(actor)
		bindings[actor] = report.duplicate(true)
	return _success({"bindings": bindings, "local_player_ids": local_players, "authority_id": _authority, "backend_epoch": _backend_epoch, "decision_owner": "EXISTING_SM1_COORDINATOR", "canonical_state_owned": false})
