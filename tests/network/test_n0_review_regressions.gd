extends SceneTree

const Snapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const Delta = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const Transport = preload("res://scripts/network/loopback/loopback_replication_transport.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var spatial: Dictionary = SpatialRef.create("body/moon/fixed", Vector3(1, 2, 3))
	var snapshot: Dictionary = Snapshot.create(
		"snapshot/review/1",
		"entity/review/item",
		"world_item",
		7,
		"sim-a",
		4,
		100,
		spatial,
		{"space_id": "moon", "chunk_id": "chunk/0"},
		{"sleeping": false, "linear_velocity_mps": [0.0, 0.0, 0.0]},
		{"inventory": {"quantity": 2}}
	)
	_assert_ok(Snapshot.validate(snapshot), "Review baseline snapshot invalid")
	_test_delta_paths(snapshot)
	_test_delta_fencing(snapshot)
	_test_snapshot_fencing(snapshot)
	_finish()


func _test_delta_paths(snapshot: Dictionary) -> void:
	var valid_paths: Array[String] = [
		"spatial_ref",
		"spatial_ref.position_m",
		"partition_address.chunk_id",
		"physics_state",
		"physics_state.sleeping",
		"domain_components.inventory.quantity",
	]
	for index in range(valid_paths.size()):
		var path: String = valid_paths[index]
		var delta: Dictionary = Delta.create(
			"delta/review/valid-path/%d" % index,
			String(snapshot["entity_id"]),
			String(snapshot["entity_type"]),
			int(snapshot["state_revision"]),
			int(snapshot["state_revision"]) + 1,
			String(snapshot["authority_owner_id"]),
			int(snapshot["authority_epoch"]),
			int(snapshot["server_tick"]),
			{path: true},
			[]
		)
		_assert_ok(Delta.validate(delta), "Canonical delta path rejected: %s" % path)

	var invalid_paths: Array[String] = [
		"",
		".physics_state.sleeping",
		"physics_state.",
		"physics_state..sleeping",
		"physics_state...sleeping",
		"physics_state. sleeping",
		"physics_state.sleeping ",
		" physics_state.sleeping",
		"unknown.value",
	]
	for index in range(invalid_paths.size()):
		var path: String = invalid_paths[index]
		var delta: Dictionary = Delta.create(
			"delta/review/invalid-path/%d" % index,
			String(snapshot["entity_id"]),
			String(snapshot["entity_type"]),
			int(snapshot["state_revision"]),
			int(snapshot["state_revision"]) + 1,
			String(snapshot["authority_owner_id"]),
			int(snapshot["authority_epoch"]),
			int(snapshot["server_tick"]),
			{path: true},
			[]
		)
		_assert(not bool(Delta.validate(delta).get("success", false)), "Non-canonical delta path accepted: %s" % path)

	var double_separator: Dictionary = Delta.create(
		"delta/review/double-separator",
		String(snapshot["entity_id"]),
		String(snapshot["entity_type"]),
		7,
		8,
		"sim-a",
		4,
		101,
		{"physics_state..sleeping": true},
		[]
	)
	_assert_code(Delta.validate(double_separator), "INVALID_DELTA_FIELD", "Double path separator accepted")
	var invalid_removal: Dictionary = Delta.create(
		"delta/review/removal-separator",
		String(snapshot["entity_id"]),
		String(snapshot["entity_type"]),
		7,
		8,
		"sim-a",
		4,
		101,
		{},
		["domain_components..inventory"]
	)
	_assert_code(Delta.validate(invalid_removal), "INVALID_DELTA_FIELD", "Double separator in removal path accepted")


func _test_delta_fencing(snapshot: Dictionary) -> void:
	var valid_delta: Dictionary = Delta.create(
		"delta/review/valid",
		String(snapshot["entity_id"]),
		String(snapshot["entity_type"]),
		7,
		8,
		"sim-a",
		4,
		100,
		{"physics_state.sleeping": true},
		[]
	)
	var applied: Dictionary = Delta.apply_to_snapshot(snapshot, valid_delta)
	_assert_ok(applied, "Non-decreasing delta rejected")
	_assert(int(applied["snapshot"]["state_revision"]) == 8, "Valid delta revision incorrect")
	_assert(int(applied["snapshot"]["server_tick"]) == 100, "Equal server tick was not preserved")
	_assert(String(applied["snapshot"]["authority_owner_id"]) == "sim-a", "Valid delta changed owner")

	var owner_change: Dictionary = Delta.create(
		"delta/review/owner-change",
		String(snapshot["entity_id"]),
		String(snapshot["entity_type"]),
		7,
		8,
		"sim-b",
		4,
		101,
		{"physics_state.sleeping": true},
		[]
	)
	_assert_rejected_delta(snapshot, owner_change, "AUTHORITY_OWNER_MISMATCH", "Same-epoch delta owner change")

	var tick_rollback: Dictionary = Delta.create(
		"delta/review/tick-rollback",
		String(snapshot["entity_id"]),
		String(snapshot["entity_type"]),
		7,
		8,
		"sim-a",
		4,
		99,
		{"physics_state.sleeping": true},
		[]
	)
	_assert_rejected_delta(snapshot, tick_rollback, "STALE_SERVER_TICK", "Delta server tick rollback")

	var future_epoch: Dictionary = Delta.create(
		"delta/review/future-epoch",
		String(snapshot["entity_id"]),
		String(snapshot["entity_type"]),
		7,
		8,
		"sim-b",
		5,
		101,
		{"physics_state.sleeping": true},
		[]
	)
	_assert_rejected_delta(snapshot, future_epoch, "STALE_AUTHORITY_EPOCH", "Delta authority transfer bypass")


func _test_snapshot_fencing(snapshot: Dictionary) -> void:
	_assert_snapshot_rejected_without_mutation(
		snapshot,
		_snapshot_variant(snapshot, {
			"authority_owner_id": "sim-b",
			"state_revision": 8,
			"server_tick": 101,
		}),
		"AUTHORITY_OWNER_EPOCH_CONFLICT",
		"Same-epoch snapshot owner change"
	)
	_assert_snapshot_rejected_without_mutation(
		snapshot,
		_snapshot_variant(snapshot, {
			"authority_owner_id": "sim-b",
			"authority_epoch": 5,
			"state_revision": 1,
			"server_tick": 101,
		}),
		"STALE_SNAPSHOT_REVISION",
		"Higher-epoch snapshot revision rollback"
	)
	_assert_snapshot_rejected_without_mutation(
		snapshot,
		_snapshot_variant(snapshot, {
			"state_revision": 8,
			"server_tick": 99,
		}),
		"STALE_SERVER_TICK",
		"Same-epoch snapshot tick rollback"
	)
	_assert_snapshot_rejected_without_mutation(
		snapshot,
		_snapshot_variant(snapshot, {
			"authority_owner_id": "sim-b",
			"authority_epoch": 5,
			"state_revision": 7,
			"server_tick": 99,
		}),
		"STALE_SERVER_TICK",
		"Higher-epoch snapshot tick rollback"
	)
	_assert_snapshot_rejected_without_mutation(
		snapshot,
		_snapshot_variant(snapshot, {
			"entity_type": "player",
			"state_revision": 8,
			"server_tick": 101,
		}),
		"ENTITY_TYPE_MISMATCH",
		"Snapshot entity type mutation"
	)

	var same_revision_state_mutation: Dictionary = _snapshot_variant(snapshot, {
		"authority_owner_id": "sim-b",
		"authority_epoch": 5,
		"state_revision": 7,
		"server_tick": 101,
		"physics_state": {"sleeping": true, "linear_velocity_mps": [1.0, 0.0, 0.0]},
	})
	_assert_snapshot_rejected_without_mutation(
		snapshot,
		same_revision_state_mutation,
		"SNAPSHOT_REVISION_CONFLICT",
		"Higher-epoch same-revision state mutation"
	)

	var same_revision_new_epoch: Dictionary = _snapshot_variant(snapshot, {
		"authority_owner_id": "sim-b",
		"authority_epoch": 5,
		"state_revision": 7,
		"server_tick": 100,
	})
	var transport_equal_revision = Transport.new()
	_assert_ok(transport_equal_revision.send_snapshot(snapshot), "Equal-revision epoch baseline rejected")
	_assert_ok(transport_equal_revision.send_snapshot(same_revision_new_epoch), "Non-decreasing revision across epoch rejected")
	var stored_equal_revision: Dictionary = transport_equal_revision.get_snapshot(String(snapshot["entity_id"]))
	_assert_ok(stored_equal_revision, "Equal-revision epoch snapshot missing")
	_assert(String(stored_equal_revision["snapshot"]["authority_owner_id"]) == "sim-b", "Higher epoch owner was not stored")
	_assert(int(stored_equal_revision["snapshot"]["state_revision"]) == 7, "Equal monotonic revision changed")

	var advanced: Dictionary = _snapshot_variant(snapshot, {
		"authority_owner_id": "sim-b",
		"authority_epoch": 5,
		"state_revision": 8,
		"server_tick": 101,
	})
	var transport_advanced = Transport.new()
	_assert_ok(transport_advanced.send_snapshot(snapshot), "Advanced epoch baseline rejected")
	_assert_ok(transport_advanced.send_snapshot(advanced), "Valid advanced epoch snapshot rejected")
	var advanced_stored: Dictionary = transport_advanced.get_snapshot(String(snapshot["entity_id"]))
	_assert_ok(advanced_stored, "Advanced epoch snapshot missing")
	_assert(advanced_stored["snapshot"] == Snapshot.normalize(advanced), "Advanced epoch snapshot changed in storage")


func _assert_rejected_delta(snapshot: Dictionary, delta: Dictionary, expected_code: String, label: String) -> void:
	var snapshot_before: Dictionary = snapshot.duplicate(true)
	var direct_result: Dictionary = Delta.apply_to_snapshot(snapshot, delta)
	_assert_code(direct_result, expected_code, "%s accepted by direct apply" % label)
	_assert(snapshot == snapshot_before, "%s mutated the base snapshot" % label)
	var transport = Transport.new()
	_assert_ok(transport.send_snapshot(snapshot), "%s baseline send failed" % label)
	_assert_code(transport.send_delta(delta), expected_code, "%s accepted by transport" % label)
	var stored: Dictionary = transport.get_snapshot(String(snapshot["entity_id"]))
	_assert_ok(stored, "%s removed the stored snapshot" % label)
	_assert(stored["snapshot"] == Snapshot.normalize(snapshot), "%s mutated the stored snapshot" % label)


func _assert_snapshot_rejected_without_mutation(
	base_snapshot: Dictionary,
	candidate: Dictionary,
	expected_code: String,
	label: String
) -> void:
	var transport = Transport.new()
	_assert_ok(transport.send_snapshot(base_snapshot), "%s baseline send failed" % label)
	_assert_code(transport.send_snapshot(candidate), expected_code, "%s was accepted" % label)
	var stored: Dictionary = transport.get_snapshot(String(base_snapshot["entity_id"]))
	_assert_ok(stored, "%s removed the stored snapshot" % label)
	_assert(stored["snapshot"] == Snapshot.normalize(base_snapshot), "%s mutated the stored snapshot" % label)


func _snapshot_variant(snapshot: Dictionary, changes: Dictionary) -> Dictionary:
	var output: Dictionary = snapshot.duplicate(true)
	for key in changes.keys():
		output[key] = changes[key]
	output["checksum"] = Snapshot.compute_checksum(output)
	return output


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_code(result: Dictionary, code: String, message: String) -> void:
	_assert(
		not bool(result.get("success", false)) and String(result.get("error_code", "")) == code,
		"%s: %s" % [message, result]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N0 review regressions: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N0 review regressions: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
