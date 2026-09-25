extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_fixed_tick_gameplay_service.gd"

# Same ONE Service and inherited canonical M4 object, not a nested backend.
const ItemPlayerPort6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_live_item_player_transfer_port.gd")

func setup(owner_id: String, epoch: int, server_tick: int = 0, config: Dictionary = {}) -> Dictionary:
	if _configured: return _failure("NETWORKED_GAMEPLAY_SERVICE_ALREADY_CONFIGURED")
	var fixture_owner = config.get("mvp6_fixture_owner", owner_id == "authority/a")
	var spatial = config.get("mvp6_spatial_validation", true)
	if typeof(fixture_owner) != TYPE_BOOL or typeof(spatial) != TYPE_BOOL or bool(config.get("playable_sandbox", false)):
		return _failure("MVP6_TRUSTED_NATIVE_POLICY_INVALID")
	var initialized: Dictionary = super.setup(owner_id, epoch, server_tick, config)
	if not bool(initialized.get("success", false)): return initialized
	var items: Dictionary = _canonical_multiplayer_items.configure_live_items(fixture_owner, spatial)
	if not bool(items.get("success", false)):
		shutdown()
		return items
	return _success({"snapshot": create_snapshot(), "profile": _profile, "native_item_policy": _canonical_multiplayer_items.get_live_item_report()})

func get_live_player_transfer_port():
	if not _configured or _profile != PROFILE_MULTIPLAYER_CORE: return null
	if _live_player_port == null:
		var port = ItemPlayerPort6.new()
		var configured: Dictionary = port.configure(self, _players, _ownership, _canonical_multiplayer_items, _authority_owner_id, _authority_epoch)
		if not bool(configured.get("success", false)): return null
		_live_player_port = port
	return _live_player_port

func handle_canonical_item_command(actor: String, session: String, ownership_epoch: int, operation: String, kind: String, payload: Dictionary) -> Dictionary:
	# A historical known operation is NOT a substitute for a live session.
	# Authenticate before inherited replay lookup as well as before mutation.
	if not _configured: return _failure("CANONICAL_ITEM_GRAPH_NOT_READY")
	var allowed := _validate_owner(actor, session, ownership_epoch)
	if not bool(allowed.get("success", false)): return allowed
	return super.handle_canonical_item_command(actor, session, ownership_epoch, operation, kind, payload)
