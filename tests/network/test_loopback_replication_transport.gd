extends SceneTree

const Snapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const Delta = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const Transport = preload("res://scripts/network/loopback/loopback_replication_transport.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var transport = Transport.new()
	var spatial: Dictionary = SpatialRef.create("body/moon/fixed", Vector3(1, 2, 3))
	var snapshot: Dictionary = Snapshot.create(
		"snapshot/replication/1", "entity/item/replication", "world_item",
		7, "sim-a", 4, 100, spatial, {}, {"sleeping": false},
		{"item": {"definition_id": "survey_beacon"}}
	)
	_assert_ok(Snapshot.validate(snapshot), "Baseline snapshot invalid")
	var send: Dictionary = transport.send_snapshot(snapshot)
	_assert_ok(send, "Snapshot send failed")
	_assert(not bool(send["replay"]), "First snapshot send reported replay")
	_assert(transport.get_snapshot_count() == 1, "Snapshot count incorrect")
	_assert(String(send["snapshot"]["checksum"]) == Snapshot.snapshot_hash(snapshot), "Snapshot hash changed over transport")
	var replay: Dictionary = transport.send_snapshot(snapshot)
	_assert_ok(replay, "Snapshot replay failed")
	_assert(bool(replay["replay"]), "Exact snapshot replay was not detected")

	var conflicting: Dictionary = snapshot.duplicate(true)
	conflicting["physics_state"] = {"sleeping": true}
	conflicting["checksum"] = Snapshot.compute_checksum(conflicting)
	_assert_code(transport.send_snapshot(conflicting), "SNAPSHOT_REVISION_CONFLICT", "Same-revision conflicting snapshot accepted")
	var stale: Dictionary = snapshot.duplicate(true)
	stale["state_revision"] = 6
	stale["checksum"] = Snapshot.compute_checksum(stale)
	_assert_code(transport.send_snapshot(stale), "STALE_SNAPSHOT_REVISION", "Stale snapshot accepted")
	var stale_epoch: Dictionary = snapshot.duplicate(true)
	stale_epoch["authority_epoch"] = 3
	stale_epoch["state_revision"] = 8
	stale_epoch["checksum"] = Snapshot.compute_checksum(stale_epoch)
	_assert_code(transport.send_snapshot(stale_epoch), "STALE_AUTHORITY_EPOCH", "Stale snapshot authority accepted")

	var delta: Dictionary = Delta.create(
		"delta/replication/1", "entity/item/replication", "world_item",
		7, 8, "sim-a", 4, 101,
		{"physics_state": {"sleeping": true, "linear_velocity_mps": [1.0, 0.0, 0.0]}},
		[]
	)
	_assert_ok(Delta.validate(delta), "Baseline delta invalid")
	var delta_send: Dictionary = transport.send_delta(delta)
	_assert_ok(delta_send, "Delta send failed")
	_assert(not bool(delta_send["replay"]), "First delta send reported replay")
	var updated: Dictionary = delta_send["snapshot"]
	_assert_ok(Snapshot.validate(updated), "Delta produced invalid snapshot")
	_assert(int(updated["state_revision"]) == 8, "Delta result revision incorrect")
	_assert(int(updated["server_tick"]) == 101, "Delta server tick lost")
	_assert(bool(updated["physics_state"]["sleeping"]), "Delta payload was not applied")
	_assert(String(updated["checksum"]) == Snapshot.compute_checksum(updated), "Delta result checksum incorrect")
	var delta_replay: Dictionary = transport.send_delta(delta)
	_assert_ok(delta_replay, "Delta replay failed")
	_assert(bool(delta_replay["replay"]), "Exact delta replay was not detected")
	_assert(delta_replay["snapshot"] == updated, "Delta replay result changed")
	var conflicting_delta: Dictionary = delta.duplicate(true)
	conflicting_delta["changed_fields"] = {"physics_state": {"sleeping": false}}
	conflicting_delta["checksum"] = Delta.compute_checksum(conflicting_delta)
	_assert_code(transport.send_delta(conflicting_delta), "DELTA_ID_CONFLICT", "Conflicting delta ID accepted")

	var wrong_type_delta: Dictionary = Delta.create(
		"delta/replication/type", "entity/item/replication", "player",
		8, 9, "sim-a", 4, 102, {"physics_state": {}}, []
	)
	_assert_code(transport.send_delta(wrong_type_delta), "ENTITY_TYPE_MISMATCH", "Wrong entity type delta accepted")
	var wrong_epoch_delta: Dictionary = Delta.create(
		"delta/replication/epoch", "entity/item/replication", "world_item",
		8, 9, "sim-a", 3, 102, {"physics_state": {}}, []
	)
	_assert_code(transport.send_delta(wrong_epoch_delta), "STALE_AUTHORITY_EPOCH", "Stale delta authority accepted")
	var wrong_revision_delta: Dictionary = Delta.create(
		"delta/replication/revision", "entity/item/replication", "world_item",
		7, 9, "sim-a", 4, 102, {"physics_state": {}}, []
	)
	_assert_code(transport.send_delta(wrong_revision_delta), "BASE_REVISION_MISMATCH", "Wrong delta base revision accepted")
	var missing_entity_delta: Dictionary = Delta.create(
		"delta/replication/missing", "entity/missing", "world_item",
		0, 1, "sim-a", 4, 102, {"physics_state": {}}, []
	)
	_assert_code(transport.send_delta(missing_entity_delta), "SNAPSHOT_REQUIRED", "Delta without base snapshot accepted")

	var invalid_snapshot: Dictionary = snapshot.duplicate(true)
	invalid_snapshot["checksum"] = "0".repeat(64)
	_assert_code(transport.send_snapshot(invalid_snapshot), "CHECKSUM_MISMATCH", "Invalid snapshot checksum accepted")
	var invalid_delta: Dictionary = delta.duplicate(true)
	invalid_delta["checksum"] = "0".repeat(64)
	_assert_code(transport.send_delta(invalid_delta), "CHECKSUM_MISMATCH", "Invalid delta checksum accepted")
	_assert(transport.get_snapshot_count() == 1, "Rejected replication changed snapshot count")

	_finish()


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_code(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N0 loopback replication transport: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N0 loopback replication transport: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
