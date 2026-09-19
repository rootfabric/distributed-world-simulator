extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp5_material_output_authority.gd"

# MW5 persistence + MW6 current-state replication over the SAME MVP4/5 owners.
# This is one participant in a coordinated world cut, not a new save engine.
const MatterRepository7 = preload("res://scripts/simulation/matter/persistence/matter_state_repository.gd")
const MatterRecovery7 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_matter_recovery_coordinator.gd")
var _matter_sealed7 := false
var _matter_restored7 := false
var _matter_receipt7: Dictionary = {}

func _persistence_ports7(repository_root: String) -> Dictionary:
	if not _configured or repository_root.strip_edges().is_empty(): return fail("MVP7_MATTER_RECOVERY_NOT_CONFIGURED")
	var repository = MatterRepository7.new()
	var configured: Dictionary = repository.configure(repository_root)
	if not bool(configured.get("success", false)): return configured
	var coordinator = MatterRecovery7.new()
	var excavation = _bubble.excavation_service()
	configured = coordinator.configure(_bubble.body_definition(), _bubble.grid_profile(), _bubble.mutation_level(), excavation.snapshot_store(), excavation.material_receiver(), excavation.mutation_journal(), repository)
	if not bool(configured.get("success", false)): return configured
	return ok({"coordinator": coordinator, "repository": repository})

func seal_and_save_matter7(repository_root: String, server_tick: int) -> Dictionary:
	if not _matter_receipt7.is_empty(): return fail("MVP7_MATTER_CUT_ALREADY_SAVED")
	var ports := _persistence_ports7(repository_root)
	if not bool(ports.get("success", false)): return ports
	# Fail closed even if a filesystem operation fails. The outer world
	# coordinator must not acknowledge a cut unless EVERY participant succeeds.
	_matter_sealed7 = true
	var saved: Dictionary = ports["details"]["coordinator"].save_next(server_tick)
	if not bool(saved.get("success", false)): return saved
	var checkpoint: Dictionary = saved.get("details", {}).get("checkpoint", {})
	var receipt := {"checkpoint_checksum": String(checkpoint.get("checksum", "")), "generation": int(checkpoint.get("generation", 0)), "server_tick": int(checkpoint.get("server_tick", -1)), "store_hash": _bubble.snapshot_store().content_hash(), "receiver_hash": _bubble.excavation_service().material_receiver().content_hash(), "journal_hash": _bubble.excavation_service().mutation_journal().content_hash(), "stream_sequence": _matter.stream_sequence(), "state_hash": _matter.current_state_hash()}
	var checked: Dictionary = ports["details"]["coordinator"].preflight_exact7(receipt["checkpoint_checksum"])
	if not bool(checked.get("success", false)): return checked
	_matter_receipt7 = receipt
	return ok(receipt.duplicate(true))

func restore_matter7(repository_root: String, receipt: Dictionary) -> Dictionary:
	if _matter_sealed7 or _matter_restored7 or not _connected.is_empty(): return fail("MVP7_FRESH_MATTER_OWNER_REQUIRED")
	if not receipt.has_all(["checkpoint_checksum", "generation", "server_tick", "store_hash", "receiver_hash", "journal_hash", "stream_sequence", "state_hash"]): return fail("MVP7_MATTER_RECEIPT_INCOMPLETE")
	var ports := _persistence_ports7(repository_root)
	if not bool(ports.get("success", false)): return ports
	var checked: Dictionary = ports["details"]["coordinator"].preflight_exact7(String(receipt["checkpoint_checksum"]))
	if not bool(checked.get("success", false)): return checked
	var checkpoint: Dictionary = checked["details"]["checkpoint"]
	if int(checkpoint["generation"]) != int(receipt["generation"]) or int(checkpoint["server_tick"]) != int(receipt["server_tick"]): return fail("MVP7_MATTER_RECEIPT_CUT_MISMATCH")
	_matter_sealed7 = true
	var restored: Dictionary = ports["details"]["coordinator"].restore_exact7(String(receipt["checkpoint_checksum"]))
	if not bool(restored.get("success", false)): return restored
	var rebased: Dictionary = _matter.rebase_from_service_state()
	if not bool(rebased.get("success", false)): return rebased
	var actual := {"store_hash": _bubble.snapshot_store().content_hash(), "receiver_hash": _bubble.excavation_service().material_receiver().content_hash(), "journal_hash": _bubble.excavation_service().mutation_journal().content_hash(), "stream_sequence": _matter.stream_sequence(), "state_hash": _matter.current_state_hash()}
	for field in actual:
		if actual[field] != receipt[field]: return fail("MVP7_MATTER_RECOVERED_" + String(field).to_upper() + "_MISMATCH")
	_matter_restored7 = true
	_matter_sealed7 = false
	return ok(actual)

func authorize_committed_replay7(actor: String, session: String, request_transport: String) -> Dictionary:
	if _matter_sealed7: return fail("MVP7_MATTER_CUT_SEALED")
	var identity := _identity(actor, session)
	if not bool(identity.get("success", false)): return identity
	if request_transport.to_utf8_buffer().size() > MAX_REQUEST_BYTES: return fail("MVP4_DIG_REQUEST_BUDGET")
	var request: Dictionary = Codec.rehydrate_request(Codec.decode_persistence_json(request_transport))
	if request.is_empty() or not bool(Request.validate(request).get("success", false)): return fail("MVP4_INVALID_CANONICAL_REQUEST")
	if request.get("actor_id") != "player/" + actor or not String(request.get("operation_id", "")).begins_with("operation/mvp4/" + actor + "/"): return fail("MVP4_DIG_ACTOR_BINDING_INVALID")
	if not _bubble.excavation_service().mutation_journal().has_operation(String(request["operation_id"])): return fail("MVP7_DURABLE_DIG_OPERATION_REQUIRED")
	# Reissue only the transient attestation. Native MW4 still compares the full
	# original request fingerprint; same ID with changed content is NOT replay.
	return ok({"request_transport": request_transport, "plan_mac": _plan_mac(actor, session, request_transport), "aim_source": "DURABLE_COMMITTED_REQUEST"})

func prepare_dig(actor: String, session: String, operation_id: String, direction_value: Array) -> Dictionary:
	if _matter_sealed7: return fail("MVP7_MATTER_CUT_SEALED")
	return super.prepare_dig(actor, session, operation_id, direction_value)

func execute_prepared(actor: String, session: String, plan: Dictionary) -> Dictionary:
	if _matter_sealed7: return fail("MVP7_MATTER_CUT_SEALED")
	return super.execute_prepared(actor, session, plan)

func equip_tool(actor: String, session: String) -> Dictionary:
	if _matter_sealed7: return fail("MVP7_MATTER_CUT_SEALED")
	return super.equip_tool(actor, session)

func connect_replica(actor: String, session: String, sync_request: Dictionary) -> Dictionary:
	if _matter_sealed7: return fail("MVP7_MATTER_CUT_SEALED")
	return super.connect_replica(actor, session, sync_request)
