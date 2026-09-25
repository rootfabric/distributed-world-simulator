extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_live_player_transfer_port.gd"

# Opt-in composition of existing native owners. Legacy MVP3 stays unchanged.
# This port never reads/writes another owner's private inventory dictionaries.
const SCHEMA6 := "distributed_world_simulator.mvp6_live_player_export.v1"
const ITEM_POLICY6 := "MVP6_NATIVE_ITEM_CLOSURE"

func bind_player(actor: String, session: String, ownership_epoch: int, coordinator) -> Dictionary:
	if _items == null or not _items.get_live_item_report().get("enabled", false):
		return _failure("MVP6_NATIVE_ITEM_OWNER_REQUIRED")
	var bound: Dictionary = super.bind_player(actor, session, ownership_epoch, coordinator)
	if not bool(bound.get("success", false)): return bound
	return _items.bind_live_item_actor(actor, _gates[actor], self)

func attested_item_carry(actor: String, transfer: String, source: String) -> Dictionary:
	if not _peers.has(source) or _peers[source].get_ref() == null: return {}
	var packet: Dictionary = _peers[source].get_ref().get_prepared_export(actor, transfer)
	return Dictionary(packet.get("item_carry", {})).duplicate(true)

func attested_item_retirement(actor: String, transfer: String, source: String) -> Dictionary:
	if not _peers.has(source) or _peers[source].get_ref() == null: return {}
	return _peers[source].get_ref().get_retirement_receipt(actor, transfer)

func prepare_export(actor: String, transfer: String, manifest: Dictionary) -> Dictionary:
	if not _gates.has(actor): return _failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[actor]
	var phase: Dictionary = gate.check_transfer_phase(transfer, "SOURCE_EXPORT")
	if not bool(phase.get("success", false)): return phase
	var tuple: Dictionary = phase["details"]["transfer"]
	var captured: Dictionary = _registry.capture_live_player(actor, gate, transfer)
	var ownership: Dictionary = _ownership.capture_live_player(actor, gate, transfer)
	if not bool(captured.get("success", false)): return captured
	if not bool(ownership.get("success", false)): return ownership
	var player: Dictionary = captured["details"]["player"]
	var binding: Dictionary = ownership["details"]["player"]
	for row in [player, binding]:
		var identity: Dictionary = gate.validate_record_identity(row)
		if not bool(identity.get("success", false)): return identity
	# Legacy SharedItemService inventory is not the canonical M4 inventory.
	if not player.get("inventory", []).is_empty(): return _failure("MVP6_LEGACY_FIXTURE_CARRY_UNSUPPORTED")
	var replay: Dictionary = _owner_ref.get_ref().export_live_player_replay(actor)
	if replay.size() > MAX_REPLAY_RECORDS: return _failure("LIVE_PLAYER_REPLAY_BUDGET_EXCEEDED")
	var checked := _validate_carry_manifest(actor, player, tuple, manifest, replay)
	if not bool(checked.get("success", false)): return checked
	var items: Dictionary = _items.prepare_live_item_carry(actor, gate, transfer)
	if not bool(items.get("success", false)): return items
	var packet := {"schema": SCHEMA6, "transfer_id": transfer, "logical_player_id": actor, "source_authority_id": _authority, "target_authority_id": tuple["target_authority_id"], "source_epoch": tuple["source_epoch"], "target_epoch": tuple["target_epoch"], "backend_authority_epoch": _backend_epoch, "player": player, "ownership": binding, "replay": replay, "carrying_manifest": manifest.duplicate(true), "item_payload_policy": ITEM_POLICY6, "item_carry": items["details"]["packet"]}
	var stable := false
	for _attempt in range(4):
		var roundtrip: Dictionary = Utils.json_round_trip(packet)
		if not bool(roundtrip.get("success", false)) or not roundtrip.get("value") is Dictionary: return _failure("LIVE_PLAYER_EXPORT_CANONICALIZATION_FAILED")
		var candidate: Dictionary = roundtrip["value"]
		if Utils.payload_hash(candidate) == Utils.payload_hash(packet):
			stable = true
			break
		packet = candidate
	if not stable: return _failure("LIVE_PLAYER_EXPORT_CANONICALIZATION_UNSTABLE")
	if packet["item_carry"].get("checksum") != _checksum(packet["item_carry"]): return _failure("MVP6_ITEM_TRANSPORT_CANONICALIZATION_CHANGED")
	packet["checksum"] = Utils.payload_hash(packet)
	var previous: Dictionary = _prepared.get(actor, {})
	if previous.get("transfer_id") == transfer and previous.get("checksum") != packet["checksum"]: return _failure("LIVE_PLAYER_FROZEN_EXPORT_CHANGED")
	_prepared[actor] = packet.duplicate(true)
	return _success({"packet": packet})

func stage_export(actor: String, packet: Dictionary) -> Dictionary:
	if not _gates.has(actor): return _failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[actor]
	var transfer := String(packet.get("transfer_id", ""))
	var phase: Dictionary = gate.check_transfer_phase(transfer, "TARGET_STAGE")
	if not bool(phase.get("success", false)): return phase
	var tuple: Dictionary = phase["details"]["transfer"]
	if packet.get("schema") != SCHEMA6 or packet.get("logical_player_id") != actor or packet.get("target_authority_id") != _authority or packet.get("backend_authority_epoch") != _backend_epoch or packet.get("item_payload_policy") != ITEM_POLICY6:
		return _failure("LIVE_PLAYER_EXPORT_TUPLE_MISMATCH")
	for field in ["source_authority_id", "target_authority_id", "source_epoch", "target_epoch"]:
		if packet.get(field) != tuple.get(field): return _failure("LIVE_PLAYER_EXPORT_TUPLE_MISMATCH")
	var source := String(packet["source_authority_id"])
	if not _peers.has(source) or _peers[source].get_ref() == null: return _failure("LIVE_TRANSFER_TRUSTED_SOURCE_REQUIRED")
	var attested: Dictionary = _peers[source].get_ref().get_prepared_export(actor, transfer)
	if attested.is_empty(): return _failure("LIVE_PLAYER_SOURCE_ATTESTATION_ABSENT")
	if packet.get("checksum") != _checksum(packet): return _failure("LIVE_PLAYER_SOURCE_CHECKSUM_INVALID")
	if Utils.payload_hash(packet) != Utils.payload_hash(attested): return _failure("LIVE_PLAYER_SOURCE_PACKET_DIVERGED")
	for field in ["player", "ownership", "replay", "carrying_manifest", "item_carry"]:
		if not packet.get(field) is Dictionary: return _failure("LIVE_PLAYER_EXPORT_SECTION_INVALID")
	var player: Dictionary = packet["player"]
	var binding: Dictionary = packet["ownership"]
	for row in [player, binding]:
		var identity: Dictionary = gate.validate_record_identity(row)
		if not bool(identity.get("success", false)): return identity
	var checks: Array[Dictionary] = [_registry.validate_live_player_record(player), _ownership.validate_live_binding_record(binding), _owner_ref.get_ref().validate_live_player_replay(actor, packet["replay"])]
	for checked in checks:
		if not bool(checked.get("success", false)): return checked
	if _staged.has(actor) and _staged[actor]["packet"].get("checksum") != packet["checksum"]: return _failure("LIVE_PLAYER_STAGE_CONFLICT")
	var item_stage: Dictionary = _items.stage_live_item_carry(actor, gate, packet["item_carry"])
	if not bool(item_stage.get("success", false)): return item_stage
	player = Gate.normalize_live_record(player)
	binding = Gate.normalize_live_record(binding)
	var registry_stage: Dictionary = _registry.stage_live_player(actor, gate, transfer, player)
	if not bool(registry_stage.get("success", false)):
		_items.rollback_live_item_stage(actor, gate, transfer)
		return registry_stage
	var ownership_stage: Dictionary = _ownership.stage_live_player(actor, gate, transfer, binding)
	if not bool(ownership_stage.get("success", false)):
		_registry.discard_live_player_stage(actor, gate, transfer)
		_items.rollback_live_item_stage(actor, gate, transfer)
		return ownership_stage
	var projection = ProjectionScript.new()
	var projected: Dictionary = projection.configure_from_canonical_sources({"gameplay": {"live_actor_export_checksum": packet["checksum"], "player": player, "ownership": binding}, "item_graph": {"carry_checksum": packet["item_carry"]["checksum"], "slice": packet["item_carry"]["slice"]}, "construction": {}})
	var shadow = Shadow.new()
	var shadow_setup: Dictionary = shadow.configure(projection) if bool(projected.get("success", false)) else projected
	if not bool(shadow_setup.get("success", false)):
		_registry.discard_live_player_stage(actor, gate, transfer)
		_ownership.discard_live_player_stage(actor, gate, transfer)
		_items.rollback_live_item_stage(actor, gate, transfer)
		return shadow_setup
	var report: Dictionary = shadow.get_report()
	_staged[actor] = {"packet": packet.duplicate(true), "shadow_report": report}
	return _success({"stage_checksum": packet["checksum"], "item_carry_checksum": packet["item_carry"]["checksum"], "shadow_report": report.duplicate(true), "canonical_state_owned": false})

func retire_source(actor: String, transfer: String, token: String) -> Dictionary:
	if not _gates.has(actor): return _failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[actor]
	var phase: Dictionary = gate.check_transfer_phase(transfer, "SOURCE_RETIRE", token)
	if not bool(phase.get("success", false)): return phase
	var packet: Dictionary = _prepared.get(actor, {})
	if packet.get("transfer_id") != transfer: return _failure("LIVE_PLAYER_SOURCE_EXPORT_REQUIRED")
	var previous: Dictionary = _retired.get(actor, {})
	if previous.get("transfer_id") == transfer:
		return _success({"replay": true, "receipt": previous.duplicate(true)}) if previous.get("commit_token") == token and previous.get("packet_checksum") == packet["checksum"] else _failure("LIVE_PLAYER_RETIRE_REPLAY_CONFLICT")
	var item_check: Dictionary = _items.preflight_live_item_retire(actor, gate, transfer, token)
	if not bool(item_check.get("success", false)): return item_check
	# Synchronous native retire followed by the SAME player/item readiness gate.
	# No RPC, await or user callback occurs between these local steps.
	var item_retire: Dictionary = _items.retire_live_item_carry(actor, gate, transfer, token)
	if not bool(item_retire.get("success", false)): return item_retire
	var retired: Dictionary = gate.mark_retired(transfer, token)
	if not bool(retired.get("success", false)): return retired
	_retired[actor] = {"transfer_id": transfer, "packet_checksum": packet["checksum"], "commit_token": token, "source_authority_id": _authority, "source_locally_fenced": true, "item_carry_checksum": packet["item_carry"]["checksum"], "item_retired": true}
	_owner_ref.get_ref().note_live_player_install()
	return _success({"receipt": _retired[actor].duplicate(true)})

func activate_target(actor: String, transfer: String, token: String) -> Dictionary:
	if not _gates.has(actor): return _failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[actor]
	var phase: Dictionary = gate.check_transfer_phase(transfer, "TARGET_INSTALL", token)
	if not bool(phase.get("success", false)): return phase
	var completed: Dictionary = phase["details"]["transfer"]
	var item_check: Dictionary = _items.preflight_live_item_install(actor, gate, transfer, token)
	if not bool(item_check.get("success", false)): return item_check
	if not _staged.has(actor):
		return _success({"replay": true}) if item_check.get("details", {}).get("replay") == true and gate.is_locally_ready() else _failure("LIVE_PLAYER_STAGE_REQUIRED")
	var stage: Dictionary = _staged[actor]
	var packet: Dictionary = stage["packet"]
	if packet.get("transfer_id") != transfer: return _failure("LIVE_PLAYER_STAGE_CONFLICT")
	var retired: Dictionary = attested_item_retirement(actor, transfer, String(packet["source_authority_id"]))
	if retired.get("commit_token") != token or retired.get("packet_checksum") != packet["checksum"] or retired.get("source_locally_fenced") != true: return _failure("LIVE_PLAYER_SOURCE_RETIREMENT_REQUIRED")
	var warm: Dictionary = completed.get("warm_report", {})
	var manifest_checksum := String(packet["carrying_manifest"].get("manifest_checksum", ""))
	var shadow_checksum := String(stage["shadow_report"].get("checksum", ""))
	var composite := Utils.payload_hash({"schema": Carry.WARM_SCHEMA, "transfer_id": transfer, "p6_shadow_checksum": shadow_checksum, "carrying_manifest_checksum": manifest_checksum})
	if warm.get("p6_shadow_checksum") != shadow_checksum or warm.get("carrying_manifest_checksum") != manifest_checksum or warm.get("checksum") != composite or completed.get("warm_checksum") != composite: return _failure("LIVE_PLAYER_WARM_STAGE_BINDING_MISMATCH")
	var checks: Array[Dictionary] = [_registry.preflight_live_player_install(actor, gate, transfer, token), _ownership.preflight_live_player_install(actor, gate, transfer, token), _owner_ref.get_ref().validate_live_player_replay(actor, packet["replay"])]
	for checked in checks:
		if not bool(checked.get("success", false)): return checked
	_installing = {"logical_id": actor, "gate": gate, "replay_checksum": Utils.payload_hash(packet["replay"])}
	var replay_result: Dictionary = _owner_ref.get_ref().install_live_player_replay(actor, packet["replay"], gate)
	_installing = {}
	if not bool(replay_result.get("success", false)): return replay_result
	var installed_registry: Dictionary = _registry.install_live_player(actor, gate, transfer, token)
	if not bool(installed_registry.get("success", false)): return installed_registry
	var installed_ownership: Dictionary = _ownership.install_live_player(actor, gate, transfer, token)
	if not bool(installed_ownership.get("success", false)): return installed_ownership
	var installed_items: Dictionary = _items.install_live_item_carry(actor, gate, transfer, token)
	if not bool(installed_items.get("success", false)): return installed_items
	# The local player, equipment, inventory and native ledgers become writable
	# together; the gateway cannot expose an early item-only or player-only owner.
	var ready: Dictionary = gate.mark_installed(transfer, token)
	if not bool(ready.get("success", false)): return ready
	_staged.erase(actor)
	_owner_ref.get_ref().note_live_player_install()
	return _success({"player": _registry.get_player(actor), "ownership": _ownership.get_player(actor), "authority_epoch": completed["target_epoch"], "backend_authority_epoch": _backend_epoch, "item_carry_checksum": packet["item_carry"]["checksum"], "item_count": installed_items.get("details", {}).get("item_count", 0)})

func discard_aborted_stage(actor: String, transfer: String) -> Dictionary:
	if not _gates.has(actor): return _failure("LIVE_PLAYER_GATE_REQUIRED")
	var result: Dictionary = super.discard_aborted_stage(actor, transfer)
	if not bool(result.get("success", false)): return result
	return _items.discard_live_item_stage(actor, _gates[actor], transfer)

func get_report() -> Dictionary:
	var result: Dictionary = super.get_report()
	result["item_carry_scope"] = ITEM_POLICY6
	result["native_items"] = _items.get_live_item_report() if _items != null else {}
	return result
