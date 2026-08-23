extends "res://tools/runtime/v0_p2_live_reconnect_client.gd"

const P5_MINING_TOOL_DEFINITION_ID := "item/tool/mining"
const P5_TOOL_SLOT_ID := "tool/main"


func _run_actor() -> void:
	var initial_item: Dictionary = client.get_item_graph_snapshot()
	var initial_construction: Dictionary = client.get_construction_bundle()
	_assert_runtime_healthy(client.get_report(), "actor initial")
	_assert(_item_location(initial_item, BEACON_ID) == "WORLD", "shared beacon starts in WORLD")
	var initial_fingerprint := _fingerprint()
	_assert(bool(initial_fingerprint.get("success", false)), "actor initial composite fingerprint builds")
	_write("ACTOR_READY", failures.is_empty(), {
		"item_graph_checksum": String(initial_item.get("checksum", "")),
		"construction_checksum": String(initial_construction.get("checksum", "")),
		"construction_generation": int(initial_construction.get("server_generation", -1)),
		"composite_checksum": _fingerprint_checksum(initial_fingerprint),
		"actor_player": client.get_local_player_record(),
		"runtime_report": client.get_report(),
	})
	if not failures.is_empty():
		_shutdown(1)
		return

	var mutate_requested := await _wait_control_phase("MUTATE", CONTROL_TIMEOUT_MS)
	_assert(mutate_requested, "actor receives MUTATE phase")
	if not mutate_requested:
		_fail("V0_P2_RECONNECT_MUTATE_PHASE_TIMEOUT")
		return
	var b_disconnected := await _wait_player_connected("b", false, 15000)
	_assert(b_disconnected, "actor replica observes B disconnected before mutation")
	if not b_disconnected:
		_fail("V0_P2_RECONNECT_B_DISCONNECT_NOT_OBSERVED")
		return

	var move_to_beacon: Dictionary = await _move_toward(TARGET_BEACON, 4)
	_assert(bool(move_to_beacon.get("success", false)), "actor moves to shared beacon while B absent")
	var pickup: Dictionary = client.execute_item_command_blocking("item.pickup", {"item_id": BEACON_ID})
	_assert(bool(pickup.get("success", false)), "actor picks up shared beacon while B absent")
	if not bool(pickup.get("success", false)):
		_fail(String(pickup.get("error_code", "V0_P2_RECONNECT_PICKUP_FAILED")), pickup)
		return
	var move_to_crate: Dictionary = await _move_toward(TARGET_CRATE, 4)
	_assert(bool(move_to_crate.get("success", false)), "actor moves to canonical crate while B absent")
	var opened: Dictionary = client.execute_item_command_blocking("container.open", {"container_id": CRATE_CONTAINER_ID})
	_assert(bool(opened.get("success", false)), "actor opens canonical crate while B absent")
	if not bool(opened.get("success", false)):
		_fail(String(opened.get("error_code", "V0_P2_RECONNECT_CONTAINER_OPEN_FAILED")), opened)
		return
	var transferred: Dictionary = client.execute_item_command_blocking("item.transfer", {
		"item_id": BEACON_ID,
		"quantity": -1,
		"target_container_id": CRATE_CONTAINER_ID,
		"target_slot_index": 0,
		"target_item_id": "",
	})
	_assert(bool(transferred.get("success", false)), "actor transfers beacon into canonical crate while B absent")
	if not bool(transferred.get("success", false)):
		_fail(String(transferred.get("error_code", "V0_P2_RECONNECT_CONTAINER_TRANSFER_FAILED")), transferred)
		return
	var item_mutation_visible := await _wait_item_state(
		func(snapshot: Dictionary) -> bool:
			return (
				_item_location(snapshot, BEACON_ID) == "CONTAINER"
				and _item_container_id(snapshot, BEACON_ID) == CRATE_CONTAINER_ID
				and _item_slot_index(snapshot, BEACON_ID) == 0
				and _container_has_item(snapshot, CRATE_CONTAINER_ID, BEACON_ID)
			),
		10000
	)
	_assert(item_mutation_visible, "actor confirms absent-peer Item Graph mutation")
	if not item_mutation_visible:
		_fail("V0_P2_RECONNECT_ITEM_MUTATION_NOT_CONFIRMED")
		return

	# Construction now consumes canonical P3-mined ore and P5 mining requires
	# the canonical mining tool to be equipped. Temporarily equip the seeded P5
	# tool through the live Item Graph command path, mine the exact foundation
	# cost, then restore the previous unequipped fixture state.
	var mining_tool_id := _owned_item_id_by_definition(
		client.get_item_graph_snapshot(),
		"a",
		P5_MINING_TOOL_DEFINITION_ID
	)
	_assert(not mining_tool_id.is_empty(), "actor resolves canonical P5 mining tool for P2/P5 compatibility")
	if mining_tool_id.is_empty():
		_fail("V0_P2_P5_MINING_TOOL_MISSING")
		return
	var equipped: Dictionary = client.execute_item_command_blocking(
		"item.equip",
		{"item_id": mining_tool_id, "slot_id": P5_TOOL_SLOT_ID}
	)
	_assert(bool(equipped.get("success", false)), "actor equips canonical P5 mining tool before ResourceMining")
	if not bool(equipped.get("success", false)):
		_fail(String(equipped.get("error_code", "V0_P2_P5_MINING_TOOL_EQUIP_FAILED")), equipped)
		return

	var resource_snapshot: Dictionary = client.get_resource_mining_snapshot()
	var target_result := _resource_target_position(resource_snapshot)
	_assert(bool(target_result.get("success", false)), "actor resolves canonical ore target for P2/P4 compatibility")
	if not bool(target_result.get("success", false)):
		_fail(String(target_result.get("error_code", "V0_P2_RESOURCE_TARGET_FAILED")), target_result)
		return
	var resource_target: Vector3 = target_result.get("details", {}).get("position", Vector3.ZERO)
	var move_to_resource: Dictionary = await _move_toward(resource_target, 24)
	_assert(bool(move_to_resource.get("success", false)), "actor approaches canonical ore node before Construction")
	if not bool(move_to_resource.get("success", false)):
		_fail(String(move_to_resource.get("error_code", "V0_P2_RESOURCE_APPROACH_FAILED")), move_to_resource)
		return
	var mine_operation := "operation/v0-p2/compat/mine-foundation/%d" % Time.get_ticks_msec()
	var mined: Dictionary = client.execute_resource_mine_blocking(P2_RESOURCE_NODE_ID, 2, mine_operation)
	_assert(bool(mined.get("success", false)), "actor mines exact canonical foundation ore cost")
	if not bool(mined.get("success", false)):
		_fail(String(mined.get("error_code", "V0_P2_RESOURCE_MINE_FAILED")), mined)
		return
	var ore_ready := await _wait_item_state(
		func(snapshot: Dictionary) -> bool:
			return _ore_quantity(snapshot, "a") == 2,
		10000
	)
	_assert(ore_ready, "actor receives two canonical ore before Construction")
	if not ore_ready:
		_fail("V0_P2_CANONICAL_ORE_NOT_VISIBLE")
		return
	var unequipped: Dictionary = client.execute_item_command_blocking(
		"item.unequip",
		{"item_id": mining_tool_id, "slot_id": P5_TOOL_SLOT_ID}
	)
	_assert(bool(unequipped.get("success", false)), "actor restores unequipped P2 fixture state after mining")
	if not bool(unequipped.get("success", false)):
		_fail(String(unequipped.get("error_code", "V0_P2_P5_MINING_TOOL_UNEQUIP_FAILED")), unequipped)
		return

	var construction_session: Dictionary = client.get_construction_session()
	_assert(not construction_session.is_empty(), "actor has canonical Construction session")
	if construction_session.is_empty():
		_fail("V0_P2_CONSTRUCTION_SESSION_MISSING")
		return
	var before_construction: Dictionary = client.get_construction_bundle()
	var construction_operation := "operation/v0-p2/outpost/foundation/%d" % Time.get_ticks_msec()
	var command := ConstructionCommand.create(
		"multiplayer-command/v0-p2/outpost/foundation/%d" % Time.get_ticks_msec(),
		String(construction_session.get("client_id", "")),
		String(construction_session.get("session_id", "")),
		int(construction_session.get("session_epoch", 0)),
		0,
		Grant.ACTION_BUILD,
		OutpostAuthority.CONSTRUCT_ID,
		"",
		int(before_construction.get("server_generation", 0)),
		int(construction_session.get("permission_epoch", 0)),
		{
			"build_plan_id": OutpostAuthority.BUILD_PLAN_ID,
			"stage_index": 0,
			"operation_id": construction_operation,
			"provided_capabilities": ["FASTEN"],
			"options": {},
		}
	)
	var built: Dictionary = client.execute_construction_command_blocking(command, construction_operation)
	_assert(bool(built.get("success", false)), "actor commits Earth outpost foundation while B absent")
	if not bool(built.get("success", false)):
		_fail(String(built.get("error_code", "V0_P2_CONSTRUCTION_BUILD_FAILED")), built)
		return
	var construction_mutation_visible := await _wait_construction_state(
		func(bundle: Dictionary) -> bool:
			return (
				int(bundle.get("server_generation", -1)) > int(before_construction.get("server_generation", -1))
				and String(bundle.get("checksum", "")) != String(before_construction.get("checksum", ""))
			),
		10000
	)
	_assert(construction_mutation_visible, "actor receives authoritative Construction mutation")
	if not construction_mutation_visible:
		_fail("V0_P2_CONSTRUCTION_MUTATION_NOT_CONFIRMED")
		return

	# Item/equipment and Construction mutate domains independently of the player
	# movement replica. Submit one stationary authoritative movement intent so the
	# compact gameplay stream publishes a fresh revision after those mutations;
	# this lets the client prove that any same-revision race is bounded rather
	# than carrying a stale health error into the reconnect phase.
	var player_position := _player_position(client.get_local_player_record())
	var replica_flush: Dictionary = await _move_toward(player_position, 1)
	_assert(bool(replica_flush.get("success", false)), "actor advances gameplay replica after cross-domain mutations")
	if not bool(replica_flush.get("success", false)):
		_fail(String(replica_flush.get("error_code", "V0_P2_REPLICA_FLUSH_FAILED")), replica_flush)
		return

	var mutated_item: Dictionary = client.get_item_graph_snapshot()
	var mutated_construction: Dictionary = client.get_construction_bundle()
	var runtime_stabilized := await _wait_runtime_error_clear(3000)
	_assert(runtime_stabilized, "actor post-mutation transient replica error clears within bounded time")
	_assert_runtime_healthy(client.get_report(), "actor post-mutation")
	_assert(String(mutated_item.get("checksum", "")) != String(initial_item.get("checksum", "")), "absent-peer Item Graph checksum changes")
	_assert(String(mutated_construction.get("checksum", "")) != String(initial_construction.get("checksum", "")), "absent-peer Construction checksum changes")
	var mutated_fingerprint := _fingerprint()
	_assert(bool(mutated_fingerprint.get("success", false)), "actor post-mutation composite fingerprint builds")
	_write("ACTOR_MUTATED", failures.is_empty(), {
		"item_graph_checksum": String(mutated_item.get("checksum", "")),
		"item_graph_revision": int(mutated_item.get("revision", -1)),
		"construction_checksum": String(mutated_construction.get("checksum", "")),
		"construction_generation": int(mutated_construction.get("server_generation", -1)),
		"composite_checksum": _fingerprint_checksum(mutated_fingerprint),
		"beacon_location": _item_location(mutated_item, BEACON_ID),
		"beacon_container_id": _item_container_id(mutated_item, BEACON_ID),
		"beacon_slot_index": _item_slot_index(mutated_item, BEACON_ID),
		"crate_contains_beacon": _container_has_item(mutated_item, CRATE_CONTAINER_ID, BEACON_ID),
		"actor_player": client.get_local_player_record(),
		"b_player": client.get_player("b"),
		"runtime_report": client.get_report(),
	})
	if not failures.is_empty():
		_shutdown(1)
		return

	var b_reconnected := await _wait_player_connected("b", true, CONTROL_TIMEOUT_MS)
	_assert(b_reconnected, "actor remains live and observes B reconnect")
	if not b_reconnected:
		_fail("V0_P2_RECONNECT_B_RETURN_NOT_OBSERVED")
		return
	await _wait_frames(5)
	var reconnect_item: Dictionary = client.get_item_graph_snapshot()
	var reconnect_construction: Dictionary = client.get_construction_bundle()
	_assert_runtime_healthy(client.get_report(), "actor reconnect-observed")
	_assert(String(reconnect_item.get("checksum", "")) == String(mutated_item.get("checksum", "")), "B reconnect does not mutate canonical Item Graph")
	_assert(String(reconnect_construction.get("checksum", "")) == String(mutated_construction.get("checksum", "")), "B reconnect does not mutate canonical Construction state")
	var final_fingerprint := _fingerprint()
	_assert(bool(final_fingerprint.get("success", false)), "actor final composite fingerprint builds")
	_write("ACTOR_RECONNECT_SEEN", failures.is_empty(), {
		"item_graph_checksum": String(reconnect_item.get("checksum", "")),
		"construction_checksum": String(reconnect_construction.get("checksum", "")),
		"construction_generation": int(reconnect_construction.get("server_generation", -1)),
		"composite_checksum": _fingerprint_checksum(final_fingerprint),
		"actor_player": client.get_local_player_record(),
		"b_player": client.get_player("b"),
		"runtime_report": client.get_report(),
	})

	var finish_requested := await _wait_control_phase("FINISH", CONTROL_TIMEOUT_MS)
	_assert(finish_requested, "actor receives FINISH phase")
	if not finish_requested:
		_fail("V0_P2_RECONNECT_FINISH_PHASE_TIMEOUT")
		return
	_complete("ACTOR_COMPLETE", {
		"composite_checksum": _fingerprint_checksum(_fingerprint()),
		"runtime_report": client.get_report(),
	})



func _owned_item_id_by_definition(snapshot: Dictionary, player_id: String, definition_id: String) -> String:
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var location: Dictionary = Dictionary(item.get("location", {}))
		if (
			String(item.get("definition_id", "")) == definition_id
			and String(location.get("kind", "")) == "INVENTORY"
			and String(location.get("player_id", "")) == player_id
		):
			return String(item.get("item_id", ""))
	return ""


func _wait_runtime_error_clear(timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		if String(client.get_report().get("last_error_code", "")).is_empty():
			return true
		await create_timer(0.02).timeout
	return String(client.get_report().get("last_error_code", "")).is_empty()
