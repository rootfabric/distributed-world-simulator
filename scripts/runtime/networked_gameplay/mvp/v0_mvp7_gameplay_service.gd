extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_gameplay_service.gd"

# One native M3/M4 owner, not a copied gameplay service. The inherited generic
# live-export prohibition remains in force until the caller stops admission and
# seals a reconciled ACTIVE-only cut. Historical inactive rows stay excluded by
# the native owners' public readers; no gate or private foreign table is reset.
const TransferPort7 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_live_player_transfer_port.gd")
var _recovery_cut_sealed7 := false
var _recovery_binding7: Dictionary = {}

func get_live_player_transfer_port():
	if not _configured or _profile != PROFILE_MULTIPLAYER_CORE: return null
	if _live_player_port == null:
		var port = TransferPort7.new()
		var configured: Dictionary = port.configure(self, _players, _ownership, _canonical_multiplayer_items, _authority_owner_id, _authority_epoch)
		if not bool(configured.get("success", false)): return null
		_live_player_port = port
	return _live_player_port

func seal_recovery_cut7() -> Dictionary:
	if not _configured or _live_player_port == null:
		return _failure("MVP7_NATIVE_LIVE_OWNER_REQUIRED")
	var checked: Dictionary = _live_player_port.checkpoint_binding_view7()
	if not bool(checked.get("success", false)): return checked
	var view: Dictionary = checked.get("details", {})
	if _recovery_cut_sealed7:
		return _success({"replay": true}) if Utils.payload_hash(view) == Utils.payload_hash(_recovery_binding7) else _failure("MVP7_SEALED_DECISION_CHANGED")
	_recovery_binding7 = view.duplicate(true)
	_recovery_cut_sealed7 = true
	return _success({"sealed": true, "binding_checksum": Utils.payload_hash(view), "local_player_ids": view["local_player_ids"]})

func recovery_binding7() -> Dictionary:
	return _recovery_binding7.duplicate(true)

func export_durable_state() -> Dictionary:
	if not _configured: return {}
	if _live_player_port == null or not _live_player_port.has_bindings():
		return super.export_durable_state()
	if not _recovery_cut_sealed7: return {}
	var checked: Dictionary = _live_player_port.checkpoint_binding_view7()
	if not bool(checked.get("success", false)) or Utils.payload_hash(checked.get("details", {})) != Utils.payload_hash(_recovery_binding7): return {}
	# Serialize the accepted native DTOs from public, owner-filtered snapshots.
	# Their validators and M6 restore methods remain authoritative. Disconnected
	# durable records intentionally contain no reusable transport session.
	var players: Array = _players.get_players()
	for row in players:
		row["connected"] = false
		row["transport_session_id"] = ""
	var registry_state := Utils.finalize_json_checksum({"schema": PlayerRegistry.DURABLE_SCHEMA, "players": players})
	var ownership_snapshot: Dictionary = _ownership.create_snapshot()
	var ownership_players: Array = ownership_snapshot.get("players", []).duplicate(true)
	for row in ownership_players:
		row["connected"] = false
		row["transport_session_id"] = ""
	var ownership_state := Utils.finalize_json_checksum({"schema": OwnershipService.DURABLE_SCHEMA, "authority_owner_id": ownership_snapshot["authority_owner_id"], "authority_epoch": ownership_snapshot["authority_epoch"], "revision": ownership_snapshot["revision"], "server_tick": ownership_snapshot["server_tick"], "players": ownership_players})
	var state := Utils.finalize_json_checksum({"schema": DURABLE_SCHEMA, "authority_owner_id": _authority_owner_id, "authority_epoch": _authority_epoch, "revision": _revision, "server_tick": _tick, "region_id": _region_id, "topology_adapter": _topology_adapter, "profile": _profile, "players": registry_state, "ownership": ownership_state, "shared_item": _shared_items.export_durable_state(), "canonical_item_graph": _canonical_multiplayer_items.export_durable_state(), RESOURCE_DURABLE_FIELD: _resource_mining.export_durable_state()})
	return state if bool(validate_durable_state(state).get("success", false)) else {}

func _validate_owner(actor: String, session: String, ownership_epoch: int) -> Dictionary:
	if _recovery_cut_sealed7: return _failure("MVP7_RECOVERY_CUT_SEALED")
	return super._validate_owner(actor, session, ownership_epoch)

func handle_join_command(command: Dictionary) -> Dictionary:
	if _recovery_cut_sealed7: return _failure("MVP7_RECOVERY_CUT_SEALED")
	return super.handle_join_command(command)

func handle_leave_command(command: Dictionary) -> Dictionary:
	if _recovery_cut_sealed7: return _failure("MVP7_RECOVERY_CUT_SEALED")
	return super.handle_leave_command(command)

func advance_fixed_server_tick(server_tick: int) -> Dictionary:
	if _recovery_cut_sealed7: return _failure("MVP7_RECOVERY_CUT_SEALED")
	return super.advance_fixed_server_tick(server_tick)

func apply_canonical_server_output(operation_id: String, actor: String, definition_id: String, quantity: int, source_id: String = "") -> Dictionary:
	if _recovery_cut_sealed7: return _failure("MVP7_RECOVERY_CUT_SEALED")
	return super.apply_canonical_server_output(operation_id, actor, definition_id, quantity, source_id)

func handle_live_player_input(command: Dictionary) -> Dictionary:
	var allowed := _validate_owner(String(command.get("logical_player_id", "")), String(command.get("transport_session_id", "")), int(command.get("ownership_epoch", 0)))
	if not bool(allowed.get("success", false)): return allowed
	return super.handle_live_player_input(command)

func handle_live_fixed_player_input(command: Dictionary, delta_seconds: float) -> Dictionary:
	var allowed := _validate_owner(String(command.get("logical_player_id", "")), String(command.get("transport_session_id", "")), int(command.get("ownership_epoch", 0)))
	if not bool(allowed.get("success", false)): return allowed
	return super.handle_live_fixed_player_input(command, delta_seconds)
