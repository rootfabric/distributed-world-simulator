extends SceneTree

const Authority = preload("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")
const Replica = preload("res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	_test_authority_and_contention()
	_test_replica_projection()
	_finish()


func _test_authority_and_contention() -> void:
	var authority = Authority.new()
	_assert(_ok(authority.setup("simulation/h3/test", 4, 300)), "authority setup")
	var join_a := authority.join("a", "transport-session/h3/a/1", "operation/h3/a/join/1")
	var join_b := authority.join("b", "transport-session/h3/b/1", "operation/h3/b/join/1")
	_assert(_ok(join_a), "player A join")
	_assert(_ok(join_b), "player B join")
	_assert(String(join_a.details.player.player_entity_id) == "player/a", "stable player A identity")
	_assert(String(join_b.details.player.player_entity_id) == "player/b", "stable player B identity")
	_assert(int(authority.get_report().player_count) == 2, "two player entities")
	var parallel_a := authority.join("a", "transport-session/h3/a/spoof", "operation/h3/a/join/spoof")
	_assert(_error(parallel_a) == "PLAYER_ALREADY_CONNECTED", "parallel player A ownership rejected")
	var stale_epoch := authority.move_player("a", "transport-session/h3/a/1", 2, 1, 1.0, 0.0, "operation/h3/a/move/stale-epoch")
	_assert(_error(stale_epoch) == "STALE_PLAYER_OWNERSHIP_EPOCH", "stale ownership epoch rejected")
	var spoofed_player := authority.move_player("b", "transport-session/h3/a/1", 1, 1, 1.0, 0.0, "operation/h3/b/move/spoof")
	_assert(_error(spoofed_player) == "STALE_PLAYER_SESSION", "spoofed player identity rejected")
	var move_a := authority.move_player("a", "transport-session/h3/a/1", 1, 1, 1.0, 0.5, "operation/h3/a/move/1")
	var move_b := authority.move_player("b", "transport-session/h3/b/1", 1, 1, -1.0, -0.5, "operation/h3/b/move/1")
	_assert(_ok(move_a), "player A movement")
	_assert(_ok(move_b), "player B movement")
	var replay_move := authority.move_player("a", "transport-session/h3/a/1", 1, 1, 1.0, 0.5, "operation/h3/a/move/1")
	_assert(_ok(replay_move) and bool(replay_move.details.replay), "exact movement replay")
	var duplicate_sequence := authority.move_player("a", "transport-session/h3/a/1", 1, 1, 0.5, 0.0, "operation/h3/a/move/duplicate-sequence")
	_assert(_error(duplicate_sequence) == "STALE_OR_DUPLICATE_INPUT_SEQUENCE", "duplicate input sequence rejected")
	var cross_inventory := authority.request_inventory_write("a", "b", "transport-session/h3/a/1", 1, "operation/h3/a/inventory/b")
	_assert(_error(cross_inventory) == "PLAYER_PERMISSION_DENIED", "cross-player inventory write rejected")
	var pickup_a := authority.pickup_shared_item("a", "transport-session/h3/a/1", 1, Authority.SHARED_ITEM_ID, "operation/h3/a/pickup/1")
	var pickup_b := authority.pickup_shared_item("b", "transport-session/h3/b/1", 1, Authority.SHARED_ITEM_ID, "operation/h3/b/pickup/1")
	_assert(_ok(pickup_a), "first pickup succeeds")
	_assert(_error(pickup_b) == "ITEM_ALREADY_CLAIMED", "second pickup deterministically rejected")
	var pickup_replay := authority.pickup_shared_item("a", "transport-session/h3/a/1", 1, Authority.SHARED_ITEM_ID, "operation/h3/a/pickup/1")
	_assert(_ok(pickup_replay) and bool(pickup_replay.details.replay), "pickup replay does not duplicate item")
	var player_a := authority.get_player("a")
	var player_b := authority.get_player("b")
	var item_count := Array(player_a.inventory).count(Authority.SHARED_ITEM_ID) + Array(player_b.inventory).count(Authority.SHARED_ITEM_ID)
	_assert(item_count == 1, "shared item exists in exactly one inventory")
	_assert(not bool(authority.create_snapshot().shared_item.available), "shared item removed from world")
	var leave_a := authority.leave("a", "transport-session/h3/a/1", "operation/h3/a/leave/1")
	_assert(_ok(leave_a), "player A leave")
	var b_continues := authority.move_player("b", "transport-session/h3/b/1", 1, 2, 0.0, 1.5, "operation/h3/b/move/2")
	_assert(_ok(b_continues), "player B continues after A leaves")
	var rejoin_a := authority.join("a", "transport-session/h3/a/2", "operation/h3/a/join/2")
	_assert(_ok(rejoin_a), "player A reconnect")
	_assert(String(rejoin_a.details.player.player_entity_id) == String(join_a.details.player.player_entity_id), "reconnect preserves player entity")
	_assert(int(rejoin_a.details.player.ownership_epoch) == 2, "reconnect increments ownership epoch")
	_assert(int(authority.get_report().player_count) == 2, "reconnect creates no duplicate player")
	var stale_session_after_rejoin := authority.move_player("a", "transport-session/h3/a/1", 1, 2, 1.0, 0.0, "operation/h3/a/move/stale-session")
	_assert(_error(stale_session_after_rejoin) == "STALE_PLAYER_SESSION", "old transport session fenced after reconnect")
	var operation_conflict := authority.move_player("b", "transport-session/h3/b/1", 1, 3, 1.0, 0.0, "operation/h3/a/move/1")
	_assert(_error(operation_conflict) == "OPERATION_REPLAY_CONFLICT", "operation payload mutation rejected")
	var stale_pickup_session := authority.pickup_shared_item("a", "transport-session/h3/a/1", 1, Authority.SHARED_ITEM_ID, "operation/h3/a/pickup/stale-session")
	_assert(_error(stale_pickup_session) == "STALE_PLAYER_SESSION", "old session cannot replay pickup after reconnect")
	var snapshot := authority.create_snapshot()
	_assert(_ok(authority.validate_snapshot(snapshot)), "final snapshot validates")
	var tampered := snapshot.duplicate(true)
	tampered.players[0].position.x = 999.0
	_assert(_error(authority.validate_snapshot(tampered)) == "MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH", "tampered snapshot rejected")
	var extra_player_field := snapshot.duplicate(true)
	extra_player_field.players[0]["authority_object"] = "forbidden"
	extra_player_field.erase("checksum")
	extra_player_field["checksum"] = Utils.payload_hash(extra_player_field)
	_assert(_error(authority.validate_snapshot(extra_player_field)) == "INVALID_MULTIPLAYER_PLAYER_FIELDS", "unexpected player field rejected")
	var duplicate_identity := snapshot.duplicate(true)
	duplicate_identity.players[1]["logical_player_id"] = duplicate_identity.players[0]["logical_player_id"]
	duplicate_identity.players[1]["player_entity_id"] = duplicate_identity.players[0]["player_entity_id"]
	duplicate_identity.erase("checksum")
	duplicate_identity["checksum"] = Utils.payload_hash(duplicate_identity)
	_assert(_error(authority.validate_snapshot(duplicate_identity)) == "DUPLICATE_MULTIPLAYER_PLAYER_IDENTITY", "duplicate player identity rejected")
	var invalid_available_item := snapshot.duplicate(true)
	invalid_available_item.shared_item.available = true
	invalid_available_item.erase("checksum")
	invalid_available_item["checksum"] = Utils.payload_hash(invalid_available_item)
	_assert(_error(authority.validate_snapshot(invalid_available_item)) == "AVAILABLE_ITEM_HAS_OWNER", "available item with owner rejected")


func _test_replica_projection() -> void:
	var authority = Authority.new()
	_assert(_ok(authority.setup("simulation/h3/replica", 5, 500)), "replica authority setup")
	var replica = Replica.new()
	var initial := authority.create_snapshot()
	_assert(_ok(replica.accept_snapshot(initial)), "replica initial snapshot")
	var join_a := authority.join("a", "transport-session/h3/replica/a/1", "operation/h3/replica/a/join/1")
	_assert(_ok(replica.accept_delta(join_a.details.delta)), "replica applies player A join delta")
	var join_b := authority.join("b", "transport-session/h3/replica/b/1", "operation/h3/replica/b/join/1")
	_assert(_ok(replica.accept_delta(join_b.details.delta)), "replica applies player B join delta")
	var move_a := authority.move_player("a", "transport-session/h3/replica/a/1", 1, 1, 1.0, 0.5, "operation/h3/replica/a/move/1")
	_assert(_ok(replica.accept_delta(move_a.details.delta)), "replica applies movement delta")
	var pickup := authority.pickup_shared_item("b", "transport-session/h3/replica/b/1", 1, Authority.SHARED_ITEM_ID, "operation/h3/replica/b/pickup/1")
	_assert(_ok(replica.accept_delta(pickup.details.delta)), "replica applies pickup delta")
	_assert(String(replica.get_shared_item().owner_player_entity_id) == "player/b", "replica sees item owner")
	_assert(Array(replica.get_player("b").inventory).count(Authority.SHARED_ITEM_ID) == 1, "replica sees winner inventory")
	_assert(String(replica.get_snapshot().checksum) == String(authority.create_snapshot().checksum), "replica checksum matches authority")
	var delta_replay := replica.accept_delta(pickup.details.delta)
	_assert(_ok(delta_replay) and bool(delta_replay.details.replay), "replica fences exact delta replay")
	var bad_delta: Dictionary = move_a.details.delta.duplicate(true)
	bad_delta.player.position.x = 777.0
	_assert(_error(replica.accept_delta(bad_delta)) == "MULTIPLAYER_DELTA_CHECKSUM_MISMATCH", "tampered delta rejected")
	var invalid_event_delta: Dictionary = pickup.details.delta.duplicate(true)
	invalid_event_delta["event_type"] = "AUTHORITY_OBJECT_EXPOSED"
	invalid_event_delta.erase("checksum")
	invalid_event_delta["checksum"] = Utils.payload_hash(invalid_event_delta)
	_assert(_error(replica.accept_delta(invalid_event_delta)) == "INVALID_MULTIPLAYER_DELTA_EVENT", "unknown delta event rejected")
	var bad_target_checksum: Dictionary = pickup.details.delta.duplicate(true)
	bad_target_checksum["target_checksum"] = "short"
	bad_target_checksum.erase("checksum")
	bad_target_checksum["checksum"] = Utils.payload_hash(bad_target_checksum)
	_assert(_error(replica.accept_delta(bad_target_checksum)) == "INVALID_MULTIPLAYER_DELTA_TARGET_CHECKSUM", "invalid target checksum rejected")
	var authority_mismatch := authority.create_snapshot().duplicate(true)
	authority_mismatch["authority_epoch"] = 6
	authority_mismatch.erase("checksum")
	authority_mismatch["checksum"] = Utils.payload_hash(authority_mismatch)
	_assert(_error(replica.accept_snapshot(authority_mismatch)) == "MULTIPLAYER_AUTHORITY_MISMATCH", "replica rejects authority epoch change")
	var same_revision_mutation := replica.get_snapshot()
	same_revision_mutation.players[0].position.z = 123.0
	same_revision_mutation.erase("checksum")
	same_revision_mutation["checksum"] = Utils.payload_hash(same_revision_mutation)
	_assert(_error(replica.accept_snapshot(same_revision_mutation)) == "MULTIPLAYER_SAME_REVISION_MUTATION", "replica rejects semantic same-revision mutation")

	var clock_forward := replica.get_snapshot()
	clock_forward["server_tick"] = int(clock_forward.get("server_tick", 0)) + 10
	clock_forward.erase("checksum")
	clock_forward["checksum"] = Utils.payload_hash(clock_forward)
	var clock_forward_result := replica.accept_snapshot(clock_forward)
	_assert(_ok(clock_forward_result) and bool(clock_forward_result.details.replay) and bool(clock_forward_result.details.clock_update), "replica accepts same-revision forward clock-only snapshot")
	_assert(int(replica.get_snapshot().get("server_tick", -1)) == int(clock_forward.get("server_tick", -2)), "forward clock-only snapshot advances replica clock")

	var clock_stale := replica.get_snapshot()
	clock_stale["server_tick"] = int(clock_stale.get("server_tick", 0)) - 5
	clock_stale.erase("checksum")
	clock_stale["checksum"] = Utils.payload_hash(clock_stale)
	var clock_stale_result := replica.accept_snapshot(clock_stale)
	_assert(_ok(clock_stale_result) and bool(clock_stale_result.details.replay) and bool(clock_stale_result.details.stale), "replica ignores same-revision stale clock-only snapshot")
	_assert(int(replica.get_snapshot().get("server_tick", -1)) == int(clock_forward.get("server_tick", -2)), "stale clock-only snapshot cannot roll replica clock back")
	_assert(int(replica.get_report().get("clock_only_snapshot_updates", 0)) == 1, "forward clock-only snapshot is observable")
	_assert(int(replica.get_report().get("stale_clock_only_snapshots", 0)) == 1, "stale clock-only snapshot is observable")

	var rollback := authority.create_snapshot().duplicate(true)
	rollback.revision = 0
	rollback.erase("checksum")
	rollback["checksum"] = Utils.payload_hash(rollback)
	var rollback_result: Dictionary = replica.accept_snapshot(rollback)
	_assert(_error(rollback_result) == "MULTIPLAYER_REVISION_ROLLBACK", "replica rejects snapshot rollback")
	_assert(int(replica.get_report().direct_authority_references) == 0, "replica holds no authority references")

	var race_authority = Authority.new()
	_assert(_ok(race_authority.setup("simulation/h3/replica-race", 6, 700)), "replica race authority setup")
	var race_initial := race_authority.create_snapshot()
	var race_join_a := race_authority.join("a", "transport-session/h3/race/a/1", "operation/h3/race/a/join/1")
	var race_join_b := race_authority.join("b", "transport-session/h3/race/b/1", "operation/h3/race/b/join/1")
	_assert(_ok(race_join_a) and _ok(race_join_b), "replica race joins")
	var race_replica = Replica.new()
	_assert(_ok(race_replica.accept_snapshot(race_join_b.details.snapshot)), "newer authoritative snapshot accepted before delayed delta")
	var race_checksum := String(race_replica.get_snapshot().get("checksum", ""))
	var superseded := race_replica.accept_delta(race_join_a.details.delta)
	_assert(_ok(superseded) and bool(superseded.details.replay) and bool(superseded.details.superseded), "delta fully covered by newer snapshot is fenced as superseded")
	_assert(String(race_replica.get_snapshot().get("checksum", "")) == race_checksum, "superseded delta does not mutate newer replica state")
	_assert(int(race_replica.get_report().get("superseded_deltas", 0)) == 1, "superseded delta is observable")
	var gap_replica = Replica.new()
	_assert(_ok(gap_replica.accept_snapshot(race_initial)), "gap replica initial snapshot")
	_assert(_error(gap_replica.accept_delta(race_join_b.details.delta)) == "MULTIPLAYER_DELTA_BASE_MISMATCH", "future delta gap still requires snapshot resync")


func _ok(value: Dictionary) -> bool:
	return bool(value.get("success", false))


func _error(value: Dictionary) -> String:
	return String(value.get("error_code", ""))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("H3 multiplayer gameplay contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("H3 multiplayer gameplay contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
