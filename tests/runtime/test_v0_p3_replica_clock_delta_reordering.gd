extends SceneTree

const ReplicaStore = preload(
	"res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd"
)
const Snapshot = preload(
	"res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd"
)
const Delta = preload(
	"res://scripts/runtime/networked_gameplay/contracts/player_state_delta.gd"
)

const AUTHORITY_OWNER_ID := "authority/v0-p3/replica-clock"
const REGION_ID := "region/v0-p3/replica-clock"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_exact_same_revision_delta_replay()
	_test_stale_delta_after_clock_only_snapshot_is_safe()
	_test_newer_same_revision_delta_advances_only_clock()
	_test_true_same_revision_gameplay_mutation_still_rejects()
	_test_delta_base_mismatch_still_rejects()
	_test_snapshot_revision_rollback_still_rejects()
	_finish()


func _test_exact_same_revision_delta_replay() -> void:
	var replica = ReplicaStore.new()
	var player := _player(1.0, 2, 1)
	var target := _snapshot(2, 100, player)
	_assert(_ok(replica.accept_snapshot(target)), "baseline snapshot is accepted")
	var delta := _delta(1, 2, 100, player, String(target.get("checksum", "")))
	var accepted := replica.accept_delta(delta)
	_assert(_ok(accepted), "exact same-revision delta is accepted as replay")
	_assert(bool(accepted.get("details", {}).get("replay", false)), "exact delta reports replay")
	_assert(not bool(accepted.get("details", {}).get("clock_update", true)), "exact replay does not report clock update")
	_assert(not bool(accepted.get("details", {}).get("stale", true)), "exact replay is not stale")


func _test_stale_delta_after_clock_only_snapshot_is_safe() -> void:
	var replica = ReplicaStore.new()
	var player := _player(1.0, 2, 1)
	var mutation_target := _snapshot(2, 100, player)
	_assert(_ok(replica.accept_snapshot(mutation_target)), "stale-delta baseline is accepted")
	var later_clock := _snapshot(2, 105, player)
	var clock_accept := replica.accept_snapshot(later_clock)
	_assert(_ok(clock_accept), "same gameplay at a newer server tick is accepted")
	_assert(bool(clock_accept.get("details", {}).get("clock_update", false)), "newer snapshot reports clock-only update")
	var delayed_delta := _delta(
		1,
		2,
		100,
		player,
		String(mutation_target.get("checksum", ""))
	)
	var accepted := replica.accept_delta(delayed_delta)
	_assert(_ok(accepted), "delayed delta for identical gameplay state is accepted")
	_assert(bool(accepted.get("details", {}).get("replay", false)), "delayed delta reports replay")
	_assert(bool(accepted.get("details", {}).get("stale", false)), "delayed delta is classified as stale clock-only")
	_assert(not bool(accepted.get("details", {}).get("clock_update", true)), "stale delta does not move the clock backwards")
	var current := replica.get_snapshot()
	_assert(int(current.get("server_tick", -1)) == 105, "stale delta preserves newer replica tick")
	_assert(String(current.get("checksum", "")) == String(later_clock.get("checksum", "")), "stale delta preserves newer replica checksum")
	_assert(int(replica.get_report().get("stale_clock_only_deltas", 0)) == 1, "stale clock-only delta is reported")


func _test_newer_same_revision_delta_advances_only_clock() -> void:
	var replica = ReplicaStore.new()
	var player := _player(1.0, 2, 1)
	var current := _snapshot(2, 100, player)
	_assert(_ok(replica.accept_snapshot(current)), "newer-delta baseline is accepted")
	var later_target := _snapshot(2, 105, player)
	var later_delta := _delta(
		1,
		2,
		105,
		player,
		String(later_target.get("checksum", ""))
	)
	var accepted := replica.accept_delta(later_delta)
	_assert(_ok(accepted), "same-revision delta with identical gameplay and newer tick is accepted")
	_assert(bool(accepted.get("details", {}).get("clock_update", false)), "newer same-revision delta reports clock update")
	_assert(not bool(accepted.get("details", {}).get("stale", true)), "newer same-revision delta is not stale")
	var after := replica.get_snapshot()
	_assert(int(after.get("revision", -1)) == 2, "clock-only delta preserves gameplay revision")
	_assert(int(after.get("server_tick", -1)) == 105, "clock-only delta advances server tick")
	_assert(String(after.get("checksum", "")) == String(later_target.get("checksum", "")), "clock-only delta adopts reconstructed target checksum")
	_assert(_same_player_state(after, later_target), "clock-only delta does not mutate gameplay player state")
	_assert(int(replica.get_report().get("clock_only_delta_updates", 0)) == 1, "clock-only delta update is reported")


func _test_true_same_revision_gameplay_mutation_still_rejects() -> void:
	var replica = ReplicaStore.new()
	var current_player := _player(1.0, 2, 1)
	var current := _snapshot(2, 105, current_player)
	_assert(_ok(replica.accept_snapshot(current)), "mutation-fence baseline is accepted")
	var divergent_player := _player(2.0, 3, 2)
	var divergent_target := _snapshot(2, 105, divergent_player)
	var divergent_delta := _delta(
		1,
		2,
		105,
		divergent_player,
		String(divergent_target.get("checksum", ""))
	)
	var rejected := replica.accept_delta(divergent_delta)
	_assert(not _ok(rejected), "same revision with changed gameplay state is rejected")
	_assert(String(rejected.get("error_code", "")) == "MULTIPLAYER_SAME_REVISION_MUTATION", "real same-revision mutation keeps exact fence")
	var after := replica.get_snapshot()
	_assert(String(after.get("checksum", "")) == String(current.get("checksum", "")), "rejected same-revision mutation leaves replica unchanged")


func _test_delta_base_mismatch_still_rejects() -> void:
	var replica = ReplicaStore.new()
	var current_player := _player(1.0, 2, 1)
	var current := _snapshot(2, 100, current_player)
	_assert(_ok(replica.accept_snapshot(current)), "base-mismatch baseline is accepted")
	var future_player := _player(4.0, 4, 3)
	var future_target := _snapshot(4, 110, future_player)
	var future_delta := _delta(
		3,
		4,
		110,
		future_player,
		String(future_target.get("checksum", ""))
	)
	var rejected := replica.accept_delta(future_delta)
	_assert(not _ok(rejected), "delta with missing base revision is rejected")
	_assert(String(rejected.get("error_code", "")) == "MULTIPLAYER_DELTA_BASE_MISMATCH", "delta-base mismatch fence remains unchanged")


func _test_snapshot_revision_rollback_still_rejects() -> void:
	var replica = ReplicaStore.new()
	var current_player := _player(1.0, 2, 1)
	_assert(_ok(replica.accept_snapshot(_snapshot(2, 100, current_player))), "rollback baseline is accepted")
	var old_player := _player(0.0, 1, 0)
	var rejected := replica.accept_snapshot(_snapshot(1, 90, old_player))
	_assert(not _ok(rejected), "older gameplay revision is rejected")
	_assert(String(rejected.get("error_code", "")) == "MULTIPLAYER_REVISION_ROLLBACK", "snapshot rollback fence remains unchanged")


func _player(x: float, state_revision: int, input_sequence: int) -> Dictionary:
	return {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"transport_session_id": "transport-session/v0-p3/replica-clock/a",
		"ownership_epoch": 1,
		"connected": true,
		"position": {"x": x, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
		"inventory": [],
		"last_input_sequence": input_sequence,
		"state_revision": state_revision,
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}


func _shared_item() -> Dictionary:
	return {
		"item_id": "item/shared/beacon/1",
		"available": true,
		"owner_player_entity_id": "",
		"revision": 0,
	}


func _snapshot(revision: int, server_tick: int, player: Dictionary) -> Dictionary:
	return Snapshot.create(
		AUTHORITY_OWNER_ID,
		1,
		revision,
		server_tick,
		REGION_ID,
		[player.duplicate(true)],
		_shared_item()
	)


func _delta(
	base_revision: int,
	target_revision: int,
	server_tick: int,
	player: Dictionary,
	target_checksum: String
) -> Dictionary:
	return Delta.create(
		AUTHORITY_OWNER_ID,
		1,
		base_revision,
		target_revision,
		server_tick,
		"PLAYER_MOVED",
		player.duplicate(true),
		{},
		target_checksum
	)


func _same_player_state(left: Dictionary, right: Dictionary) -> bool:
	return left.get("players", []) == right.get("players", [])


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _assert(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("V0-P3 replica clock/delta reordering: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"V0-P3 replica clock/delta reordering: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)
