extends SceneTree

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const PlayerSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Coordinator = preload("res://scripts/persistence/authoritative_recovery_coordinator.gd")
const AuthorityAdapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const ReplayOutbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const GraphicalClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const GameplayReplica = preload("res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd")

const AUTHORITY_OWNER_ID := "simulation/m6/contracts"
const AUTHORITY_EPOCH := 1
const SESSION_A1 := "transport-session/m6/contracts/a/1"
const SESSION_B1 := "transport-session/m6/contracts/b/1"
const MOVE_OPERATION_ID := "operation/m6/contracts/a/move/1"
const FAILED_OPERATION_ID := "operation/m6/contracts/b/pickup-ore/already-claimed"
const HOTBAR_OPERATION_ID := "operation/m6/contracts/a/hotbar/1"
const HOTBAR_PAYLOAD := {"item_id": "item/shared/ore/1", "slot_index": 2}

var assertions := 0
var failures: Array[String] = []
var root_path := ""


func _init() -> void:
	_test_recovery_wire_snapshot_sessions()
	_test_recovery_client_snapshot_resync()
	root_path = ProjectSettings.globalize_path(
		"user://m6-dedicated-recovery-contracts-%d" % Time.get_ticks_usec()
	)
	_remove_tree(root_path)
	_test_dedicated_checkpoint_recovery()
	_test_successive_item_checkpoint_progression()
	_test_damaged_restore_is_transactional()
	_test_replay_outbox_validation()
	_remove_tree(root_path)
	_finish()



func _test_recovery_wire_snapshot_sessions() -> void:
	var disconnected := {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"transport_session_id": "",
		"ownership_epoch": 1,
		"connected": false,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
		"inventory": [],
		"last_input_sequence": 0,
		"state_revision": 1,
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}
	_assert_ok(PlayerSnapshot.validate_player_record(disconnected), "Recovered disconnected player may omit transient transport session")
	var connected_without_session := disconnected.duplicate(true)
	connected_without_session["connected"] = true
	_assert_error(PlayerSnapshot.validate_player_record(connected_without_session), "INVALID_MULTIPLAYER_TRANSPORT_SESSION", "Connected player still requires transport session")
	var disconnected_invalid_session := disconnected.duplicate(true)
	disconnected_invalid_session["transport_session_id"] = "stale-session"
	_assert_error(PlayerSnapshot.validate_player_record(disconnected_invalid_session), "INVALID_MULTIPLAYER_TRANSPORT_SESSION", "Disconnected player rejects malformed non-empty transport session")

func _test_recovery_client_snapshot_resync() -> void:
	var service = _new_service()
	if service == null:
		return
	var initial: Dictionary = service.create_snapshot()
	_assert_ok(service.join("a", "transport-session/m6/resync/a/1", "operation/m6/resync/a/join/1"), "M6 resync A join")
	var join_b: Dictionary = service.join("b", "transport-session/m6/resync/b/1", "operation/m6/resync/b/join/1")
	_assert_ok(join_b, "M6 resync B join")
	var runtime = GraphicalClientRuntime.new()
	runtime.set("_replica", GameplayReplica.new())
	runtime.call("_accept_snapshot", initial)
	runtime.call("_accept_delta", join_b.get("details", {}).get("delta", {}))
	var waiting: Dictionary = runtime.get_report()
	_assert(bool(waiting.get("pending_replica_resync", false)), "M6 client waits for authoritative snapshot after delta gap")
	_assert(String(waiting.get("last_error_code", "")) != "MULTIPLAYER_DELTA_BASE_MISMATCH", "M6 delta gap is transient rather than terminal")
	runtime.call("_accept_snapshot", join_b.get("details", {}).get("snapshot", {}))
	var repaired: Dictionary = runtime.get_report()
	_assert(not bool(repaired.get("pending_replica_resync", true)), "M6 authoritative snapshot completes resync")
	_assert(int(repaired.get("snapshot_resyncs", 0)) == 1, "M6 snapshot resync is counted")
	_assert(String(runtime.get_snapshot().get("checksum", "")) == String(join_b.get("details", {}).get("snapshot", {}).get("checksum", "")), "M6 resynced replica matches authority")
	service.shutdown()

func _test_dedicated_checkpoint_recovery() -> void:
	var service = _new_service()
	if service == null:
		return
	_assert_ok(service.join("a", SESSION_A1, "operation/m6/contracts/a/join/1"), "A initial join")
	_assert_ok(service.join("b", SESSION_B1, "operation/m6/contracts/b/join/1"), "B initial join")
	_assert_ok(
		service.move_player("a", SESSION_A1, 1, 1, 3.5, -1.25, MOVE_OPERATION_ID),
		"A authoritative movement"
	)
	_assert_ok(
		service.move_player("b", SESSION_B1, 1, 1, -2.0, 4.0, "operation/m6/contracts/b/move/1"),
		"B authoritative movement"
	)
	var revision_before_pickup := int(service.get_report().get("revision", -1))
	_assert_ok(
		service.handle_canonical_item_command(
			"a", SESSION_A1, 1, "operation/m6/contracts/a/pickup-ore/1",
			"item.pickup", {"item_id": "item/shared/ore/1"}
		),
		"A picked canonical ore"
	)
	_assert(
		int(service.get_report().get("revision", -1)) == revision_before_pickup + 1,
		"Successful canonical item mutation advances gameplay revision"
	)
	var revision_before_committed_failure := int(service.get_report().get("revision", -1))
	var committed_failure: Dictionary = service.handle_canonical_item_command(
		"b", SESSION_B1, 1, FAILED_OPERATION_ID,
		"item.pickup", {"item_id": "item/shared/ore/1"}
	)
	_assert_error(committed_failure, "ITEM_ALREADY_CLAIMED", "Committed item rejection recorded before checkpoint")
	_assert(service.has_durable_replay_operation(FAILED_OPERATION_ID), "Committed item rejection is replay-durable")
	_assert(
		int(service.get_report().get("revision", -1)) == revision_before_committed_failure,
		"Committed canonical rejection does not advance gameplay revision"
	)
	var revision_before_owner_failure := int(service.get_report().get("revision", -1))
	var uncommitted_owner_failure: Dictionary = service.handle_canonical_item_command(
		"b", "stale-transport-session", 1, "operation/m6/contracts/b/stale-owner/1",
		"item.pickup", {"item_id": "item/shared/crate/1"}
	)
	_assert_error(uncommitted_owner_failure, "STALE_PLAYER_SESSION", "Pre-execution ownership rejection remains uncommitted")
	_assert(not service.has_durable_replay_operation("operation/m6/contracts/b/stale-owner/1"), "Uncommitted rejection cannot enter durable outbox")
	_assert(
		int(service.get_report().get("revision", -1)) == revision_before_owner_failure,
		"Pre-execution ownership rejection does not advance gameplay revision"
	)
	var revision_before_hotbar := int(service.get_report().get("revision", -1))
	_assert_ok(
		service.handle_canonical_item_command(
			"a", SESSION_A1, 1, HOTBAR_OPERATION_ID,
			"inventory.assign_hotbar", HOTBAR_PAYLOAD
		),
		"A assigned ore to hotbar"
	)
	_assert(
		int(service.get_report().get("revision", -1)) == revision_before_hotbar + 1,
		"Second canonical mutation advances gameplay revision for checkpoint progression"
	)
	_assert_ok(
		service.handle_canonical_item_command(
			"b", SESSION_B1, 1, "operation/m6/contracts/b/pickup-beacon/1",
			"item.pickup", {"item_id": "item/shared/beacon/1"}
		),
		"B picked canonical beacon"
	)
	_assert_ok(
		service.handle_canonical_item_command(
			"b", SESSION_B1, 1, "operation/m6/contracts/b/open-container/1",
			"container.open", {"container_id": "container/shared/crate/1"}
		),
		"B opened shared container before checkpoint"
	)

	var durable_before: Dictionary = service.export_durable_state()
	var replay_before: Dictionary = service.export_replay_state()
	var live_item_before: Dictionary = service.create_canonical_item_graph_snapshot()
	var durable_item_before: Dictionary = durable_before.get("canonical_item_graph", {}).get("snapshot", {})
	var players_before: Dictionary = service.create_snapshot()
	_assert_ok(service.validate_durable_state(durable_before), "Live durable state validates")
	_assert_ok(service.validate_replay_state(replay_before), "Live replay state validates")
	_assert(Dictionary(durable_before.get("canonical_item_graph", {}).get("snapshot", {}).get("open_containers", {})).is_empty(), "Transient container access excluded from durable state")

	var repository = Repository.new()
	_assert_ok(repository.configure(root_path.path_join("checkpoint")), "M6 repository configured")
	var authority = AuthorityAdapter.new()
	_assert_ok(authority.setup(service, "session/m6/contracts"), "M6 authority adapter configured")
	var outbox = ReplayOutbox.new()
	_assert_ok(outbox.setup(service), "M6 replay outbox configured")
	var move_stage: Dictionary = outbox.stage_committed(MOVE_OPERATION_ID, "MOVE", {
		"logical_player_id": "a",
		"success": true,
		"player_snapshot_checksum": String(players_before.get("checksum", "")),
	})
	_assert_ok(move_stage, "Committed movement result staged in outbox")
	_assert_ok(
		outbox.mark_delivered(int(move_stage.get("details", {}).get("record", {}).get("sequence", 0))),
		"Delivered movement outbox state recorded"
	)
	_assert_ok(
		outbox.stage_committed(HOTBAR_OPERATION_ID, "inventory.assign_hotbar", {
			"logical_player_id": "a",
			"success": true,
			"item_graph_checksum": String(durable_item_before.get("checksum", "")),
		}),
		"Committed item result staged in outbox"
	)
	var outbox_before: Dictionary = outbox.to_dict()
	var coordinator = Coordinator.new()
	_assert_ok(coordinator.configure(repository, authority, outbox), "M6 coordinator configured")
	var persisted: Dictionary = coordinator.persist_checkpoint(
		"checkpoint/m6/contracts/1", 1, 0, HOTBAR_OPERATION_ID
	)
	_assert_ok(persisted, "M6 checkpoint persisted atomically")
	if not bool(persisted.get("success", false)):
		return
	var checkpoint: Dictionary = persisted.get("details", {}).get("checkpoint", {})
	_assert(int(checkpoint.get("generation", 0)) == 1, "Checkpoint generation starts at one")
	_assert(String(checkpoint.get("committed_operation_id", "")) == HOTBAR_OPERATION_ID, "Checkpoint records committed operation")

	var restored_service = _new_service()
	if restored_service == null:
		return
	var restored_authority = AuthorityAdapter.new()
	_assert_ok(restored_authority.setup(restored_service, "session/m6/contracts"), "Restored authority adapter configured")
	var restored_outbox = ReplayOutbox.new()
	_assert_ok(restored_outbox.setup(restored_service), "Restored replay outbox configured")
	var restored_coordinator = Coordinator.new()
	_assert_ok(restored_coordinator.configure(repository, restored_authority, restored_outbox), "Restored coordinator configured")
	var recovered: Dictionary = restored_coordinator.recover_latest()
	_assert_ok(recovered, "Dedicated state recovered from committed checkpoint")
	if not bool(recovered.get("success", false)):
		return
	_assert(String(recovered.get("details", {}).get("source", "")) == "ACTIVE", "Recovery used active checkpoint")
	_assert(String(restored_service.export_durable_state().get("checksum", "")) == String(durable_before.get("checksum", "")), "Durable gameplay checksum round-trips")
	_assert(String(restored_service.export_replay_state().get("checksum", "")) == String(replay_before.get("checksum", "")), "Replay ledger checksum round-trips")
	_assert(String(live_item_before.get("checksum", "")) != String(durable_item_before.get("checksum", "")), "Transient container access changes only live Item Graph checksum")
	_assert(String(restored_service.create_canonical_item_graph_snapshot().get("checksum", "")) == String(durable_item_before.get("checksum", "")), "Canonical durable Item Graph checksum round-trips")
	_assert(_player_position(restored_service.create_snapshot(), "a") == _player_position(players_before, "a"), "A position survived recovery")
	_assert(_player_position(restored_service.create_snapshot(), "b") == _player_position(players_before, "b"), "B position survived recovery")
	_assert(not bool(restored_service.get_player("a").get("connected", true)), "A transport session cleared on recovery")
	_assert(not bool(restored_service.get_player("b").get("connected", true)), "B transport session cleared on recovery")
	_assert(String(restored_service.get_player("a").get("transport_session_id", "")).is_empty(), "Recovered A has no stale transport identity")
	_assert(Dictionary(restored_service.create_canonical_item_graph_snapshot().get("open_containers", {})).is_empty(), "Container access session did not survive restart")
	_assert(_item_count(restored_service.create_canonical_item_graph_snapshot(), "item/shared/ore/1") == 1, "Ore identity was not duplicated")
	_assert(_item_count(restored_service.create_canonical_item_graph_snapshot(), "item/shared/beacon/1") == 1, "Beacon identity was not duplicated")
	_assert(_all_item_ids_unique(restored_service.create_canonical_item_graph_snapshot()), "All recovered Item Graph identities are unique")
	_assert(int(restored_service.get_report().get("authority_epoch", 0)) == AUTHORITY_EPOCH, "Authority epoch survived recovery")
	_assert(int(restored_service.get_report().get("revision", -1)) == int(durable_before.get("revision", -2)), "Gameplay revision survived recovery")
	_assert(int(restored_service.get_report().get("server_tick", -1)) == int(durable_before.get("server_tick", -2)), "Gameplay tick survived recovery")
	_assert(_inventory_contains(restored_service.create_canonical_item_graph_snapshot(), "a", "item/shared/ore/1"), "A canonical inventory survived recovery")
	_assert(_inventory_contains(restored_service.create_canonical_item_graph_snapshot(), "b", "item/shared/beacon/1"), "B canonical inventory survived recovery")
	_assert(_hotbar_item(restored_service.create_canonical_item_graph_snapshot(), "a", 2) == "item/shared/ore/1", "A hotbar assignment survived recovery")
	_assert(restored_outbox.get_records().size() == 2, "Committed outbox records recovered")
	_assert(restored_outbox.get_pending_records().size() == 1, "Undelivered committed outbox state recovered")
	_assert(bool(restored_outbox.get_record_for_operation(MOVE_OPERATION_ID).get("delivered", false)), "Delivered outbox state survived recovery")
	_assert(String(restored_outbox.to_dict().get("checksum", "")) == String(outbox_before.get("checksum", "")), "Outbox checksum round-trips")

	var player_checksum_before_service_replay := String(restored_service.create_snapshot().get("checksum", ""))
	var service_revision_before_service_replay := int(restored_service.get_report().get("revision", -1))
	var movement_replay: Dictionary = restored_service.move_player(
		"a", SESSION_A1, 1, 1, 3.5, -1.25, MOVE_OPERATION_ID
	)
	_assert_ok(movement_replay, "Committed movement replay succeeds after restart")
	_assert(bool(movement_replay.get("replay", false)), "Recovered movement operation is marked replay")
	_assert(String(restored_service.create_snapshot().get("checksum", "")) == player_checksum_before_service_replay, "Movement replay did not mutate player snapshot")
	_assert(int(restored_service.get_report().get("revision", -2)) == service_revision_before_service_replay, "Movement replay did not advance gameplay revision")
	var movement_conflict: Dictionary = restored_service.move_player(
		"a", SESSION_A1, 1, 1, 3.75, -1.25, MOVE_OPERATION_ID
	)
	_assert_error(movement_conflict, "OPERATION_REPLAY_CONFLICT", "Changed movement replay rejected")

	var failed_replay: Dictionary = restored_service.handle_canonical_item_command(
		"b", SESSION_B1, 1, FAILED_OPERATION_ID,
		"item.pickup", {"item_id": "item/shared/ore/1"}
	)
	_assert_error(failed_replay, "ITEM_ALREADY_CLAIMED", "Committed rejection replays after restart")
	_assert(bool(failed_replay.get("replay", false)), "Committed rejection is marked replay")
	_assert(bool(failed_replay.get("details", {}).get("replay", false)), "Committed rejection replay marker survives command routing")

	var item_revision_before_replay := int(restored_service.create_canonical_item_graph_snapshot().get("revision", -1))
	var item_checksum_before_replay := String(restored_service.create_canonical_item_graph_snapshot().get("checksum", ""))
	var service_revision_before_replay := int(restored_service.get_report().get("revision", -1))
	var replayed: Dictionary = restored_service.handle_canonical_item_command(
		"a", SESSION_A1, 1, HOTBAR_OPERATION_ID,
		"inventory.assign_hotbar", HOTBAR_PAYLOAD
	)
	_assert_ok(replayed, "Committed item operation replay succeeds after restart")
	_assert(bool(replayed.get("replay", false)), "Recovered committed operation is marked replay")
	_assert(bool(replayed.get("details", {}).get("replay", false)), "Committed replay marker survives targeted command routing")
	_assert(int(restored_service.create_canonical_item_graph_snapshot().get("revision", -2)) == item_revision_before_replay, "Committed replay did not advance Item Graph revision")
	_assert(String(restored_service.create_canonical_item_graph_snapshot().get("checksum", "")) == item_checksum_before_replay, "Committed replay did not mutate Item Graph")
	_assert(int(restored_service.get_report().get("revision", -2)) == service_revision_before_replay, "Committed replay did not advance gameplay revision")
	var conflict: Dictionary = restored_service.handle_canonical_item_command(
		"a", SESSION_A1, 1, HOTBAR_OPERATION_ID,
		"inventory.assign_hotbar", {"item_id": "item/shared/ore/1", "slot_index": 3}
	)
	_assert_error(conflict, "OPERATION_REPLAY_CONFLICT", "Changed replay payload rejected")
	_assert(String(restored_service.create_canonical_item_graph_snapshot().get("checksum", "")) == item_checksum_before_replay, "Replay conflict did not mutate Item Graph")

	var reconnect_a: Dictionary = restored_service.join(
		"a", "transport-session/m6/contracts/a/2", "operation/m6/contracts/a/join/2"
	)
	var reconnect_b: Dictionary = restored_service.join(
		"b", "transport-session/m6/contracts/b/2", "operation/m6/contracts/b/join/2"
	)
	_assert_ok(reconnect_a, "A reconnect succeeds")
	_assert_ok(reconnect_b, "B reconnect succeeds")
	_assert(int(reconnect_a.get("details", {}).get("player", {}).get("ownership_epoch", 0)) == 2, "A ownership epoch advanced 1 to 2")
	_assert(int(reconnect_b.get("details", {}).get("player", {}).get("ownership_epoch", 0)) == 2, "B ownership epoch advanced 1 to 2")
	_assert(String(restored_service.get_player("a").get("player_entity_id", "")) == "player/a", "A stable player entity preserved")
	_assert_ok(
		restored_service.move_player(
			"a", "transport-session/m6/contracts/a/2", 2, 2, 1.0, 0.5,
			"operation/m6/contracts/a/move/2"
		),
		"Recovered server accepts new authoritative command"
	)

	_assert_ok(restored_outbox.stage_committed("operation/m6/contracts/a/move/2", "MOVE", {"success": true}), "Post-recovery operation staged")
	var second_checkpoint: Dictionary = restored_coordinator.persist_checkpoint(
		"checkpoint/m6/contracts/2", 2, 1, "operation/m6/contracts/a/move/2"
	)
	_assert_ok(second_checkpoint, "Post-recovery checkpoint progression succeeds")
	_assert(int(second_checkpoint.get("details", {}).get("checkpoint", {}).get("previous_generation", -1)) == 1, "Checkpoint generation chain preserved")


func _test_successive_item_checkpoint_progression() -> void:
	var service = _new_service()
	if service == null:
		return
	_assert_ok(service.join("a", SESSION_A1, "operation/m6/progression/a/join/1"), "Progression fixture join")
	var repository = Repository.new()
	_assert_ok(repository.configure(root_path.path_join("progression-checkpoint")), "Progression repository configured")
	var authority = AuthorityAdapter.new()
	_assert_ok(authority.setup(service, "session/m6/progression"), "Progression authority configured")
	var outbox = ReplayOutbox.new()
	_assert_ok(outbox.setup(service), "Progression outbox configured")
	var coordinator = Coordinator.new()
	_assert_ok(coordinator.configure(repository, authority, outbox), "Progression coordinator configured")
	_assert_ok(
		coordinator.persist_checkpoint("checkpoint/m6/progression/1", 1, 0, ""),
		"Progression seed checkpoint persisted"
	)

	var pickup_operation := "operation/m6/progression/a/pickup-ore/1"
	var revision_before_pickup := int(service.get_report().get("revision", -1))
	_assert_ok(
		service.handle_canonical_item_command(
			"a", SESSION_A1, 1, pickup_operation,
			"item.pickup", {"item_id": "item/shared/ore/1"}
		),
		"Progression pickup succeeds"
	)
	_assert(int(service.get_report().get("revision", -1)) == revision_before_pickup + 1, "Pickup advances checkpoint revision")
	_assert_ok(outbox.stage_committed(pickup_operation, "item.pickup", {"success": true}), "Pickup outbox record staged")
	_assert_ok(
		coordinator.persist_checkpoint("checkpoint/m6/progression/2", 2, 1, pickup_operation),
		"First canonical mutation checkpoint persisted"
	)

	var hotbar_operation := "operation/m6/progression/a/hotbar/1"
	var revision_before_hotbar := int(service.get_report().get("revision", -1))
	_assert_ok(
		service.handle_canonical_item_command(
			"a", SESSION_A1, 1, hotbar_operation,
			"inventory.assign_hotbar", HOTBAR_PAYLOAD
		),
		"Progression hotbar mutation succeeds"
	)
	_assert(int(service.get_report().get("revision", -1)) == revision_before_hotbar + 1, "Hotbar advances checkpoint revision")
	_assert_ok(outbox.stage_committed(hotbar_operation, "inventory.assign_hotbar", {"success": true}), "Hotbar outbox record staged")
	var second_item_checkpoint: Dictionary = coordinator.persist_checkpoint(
		"checkpoint/m6/progression/3", 3, 2, hotbar_operation
	)
	_assert_ok(second_item_checkpoint, "Second canonical mutation checkpoint persisted without same-revision conflict")
	_assert(
		String(second_item_checkpoint.get("error_code", "")) != "SAME_REVISION_AUTHORITATIVE_MUTATION",
		"Successive Item Graph checkpoints cannot collide at one gameplay revision"
	)


func _test_damaged_restore_is_transactional() -> void:
	var service = _new_service()
	if service == null:
		return
	_assert_ok(service.join("a", SESSION_A1, "operation/m6/transaction/a/join/1"), "Transactional fixture join")
	var before: Dictionary = service.export_durable_state()
	var damaged: Dictionary = before.duplicate(true)
	var players_state: Dictionary = damaged.get("players", {})
	var players: Array = players_state.get("players", [])
	players[0]["ownership_epoch"] = 99
	players_state["players"] = players
	players_state["checksum"] = _checksum_without_field(players_state)
	damaged["players"] = players_state
	damaged["checksum"] = _checksum_without_field(damaged)
	var result: Dictionary = service.restore_durable_state(damaged)
	_assert_error(result, "RECOVERED_PLAYER_EPOCH_MISMATCH", "Cross-service ownership mismatch rejected")
	_assert(String(service.export_durable_state().get("checksum", "")) == String(before.get("checksum", "")), "Failed durable restore left live service unchanged")


func _test_replay_outbox_validation() -> void:
	var service = _new_service()
	if service == null:
		return
	_assert_ok(service.join("a", SESSION_A1, "operation/m6/outbox/a/join/1"), "Outbox fixture join")
	_assert_ok(
		service.move_player("a", SESSION_A1, 1, 1, 1.0, 0.0, "operation/m6/outbox/1"),
		"Outbox fixture replay-durable move"
	)
	var outbox = ReplayOutbox.new()
	_assert_ok(outbox.setup(service), "Outbox validation fixture setup")
	_assert_ok(outbox.stage_committed("operation/m6/outbox/1", "MOVE", {"value": 1}), "First outbox operation staged")
	_assert_error(outbox.stage_committed("operation/m6/outbox/1", "MOVE", {"value": 1}), "M6_OUTBOX_OPERATION_ALREADY_STAGED", "Duplicate outbox operation rejected")
	_assert_error(outbox.stage_committed("Operation/M6/Outbox/2", "MOVE", {"value": 2}), "INVALID_M6_OUTBOX_OPERATION", "Non-canonical operation cannot poison a checkpoint")
	var encoded: Dictionary = outbox.to_dict()
	_assert_ok(outbox.validate(encoded), "Valid outbox state accepted")
	var damaged: Dictionary = encoded.duplicate(true)
	damaged["committed_outbox"][0]["payload"]["value"] = 2
	damaged["checksum"] = _checksum_without_field(damaged)
	_assert_error(outbox.validate(damaged), "M6_OUTBOX_PAYLOAD_CHECKSUM_MISMATCH", "Outbox payload mutation detected independently")
	var impossible_delivery: Dictionary = encoded.duplicate(true)
	impossible_delivery["committed_outbox"][0]["state"] = "DELIVERED"
	impossible_delivery["committed_outbox"][0]["delivered"] = true
	impossible_delivery["committed_outbox"][0]["delivery_attempts"] = 0
	impossible_delivery["checksum"] = _checksum_without_field(impossible_delivery)
	_assert_error(outbox.validate(impossible_delivery), "M6_OUTBOX_DELIVERY_ATTEMPT_MISSING", "Delivered outbox record requires an attempt")
	var orphaned: Dictionary = encoded.duplicate(true)
	orphaned["committed_outbox"][0]["operation_id"] = "operation/m6/outbox/orphaned"
	orphaned["checksum"] = _checksum_without_field(orphaned)
	_assert_error(
		outbox.validate(orphaned),
		"M6_OUTBOX_OPERATION_NOT_REPLAY_DURABLE",
		"Outbox record without a durable replay identity is rejected"
	)


func _new_service():
	var service = Service.new()
	var setup: Dictionary = service.setup(AUTHORITY_OWNER_ID, AUTHORITY_EPOCH, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/m6/contracts",
	})
	_assert_ok(setup, "Networked gameplay service setup")
	return service if bool(setup.get("success", false)) else null


func _player_position(snapshot: Dictionary, logical_player_id: String) -> Dictionary:
	for player_value in snapshot.get("players", []):
		if player_value is Dictionary and String(player_value.get("logical_player_id", "")) == logical_player_id:
			return Dictionary(player_value.get("position", {})).duplicate(true)
	return {}


func _inventory_contains(snapshot: Dictionary, logical_player_id: String, item_id: String) -> bool:
	var inventory: Dictionary = Dictionary(snapshot.get("inventories", {})).get(logical_player_id, {})
	return item_id in Array(inventory.get("inventory", []))


func _hotbar_item(snapshot: Dictionary, logical_player_id: String, slot_index: int) -> String:
	var inventory: Dictionary = Dictionary(snapshot.get("inventories", {})).get(logical_player_id, {})
	var hotbar: Array = inventory.get("hotbar", [])
	return String(hotbar[slot_index]) if slot_index >= 0 and slot_index < hotbar.size() else ""


func _item_count(snapshot: Dictionary, item_id: String) -> int:
	var count := 0
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			count += 1
	return count


func _all_item_ids_unique(snapshot: Dictionary) -> bool:
	var seen: Dictionary = {}
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			return false
		var item_id := String(item_value.get("item_id", ""))
		if item_id.is_empty() or seen.has(item_id):
			return false
		seen[item_id] = true
	return true


func _checksum_without_field(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(
		not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code,
		"%s: %s" % [message, result]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	print("M6 dedicated recovery contracts: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
