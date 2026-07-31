extends SceneTree

const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")

var failures: Array[String] = []
var assertions: int = 0

func _init() -> void:
	_test_table_lifecycle()
	_test_replay_and_revision_fences()
	_test_transactional_snapshot_load()
	_finish()

func _test_table_lifecycle() -> void:
	var aggregate = AggregateScript.new()
	_assert_ok(aggregate.setup("construct/table/demo", "item/construct/table-demo"), "Construct setup failed")
	var revision: int = 0
	for part in _parts():
		var result: Dictionary = aggregate.add_part("op/add/%s" % part["part_id"], revision, part)
		_assert_ok(result, "Part add failed")
		revision += 1
		_assert(int(result.get("state_revision", -1)) == revision, "Part add revision did not advance")
	for bond in _bonds():
		var result: Dictionary = aggregate.add_bond("op/add/%s" % bond["bond_id"], revision, bond)
		_assert_ok(result, "Bond add failed")
		revision += 1
	var operational: Dictionary = aggregate.set_build_state("op/state/operational", revision, "OPERATIONAL")
	_assert_ok(operational, "Stable table did not become operational")
	revision += 1
	_assert(String(operational.get("build_state", "")) == "OPERATIONAL", "Operational state not reported")
	var facets: Dictionary = aggregate.get_compiled_facets()
	_assert(bool(facets.get("stable", false)), "Operational table is not stable")
	_assert(facets.get("capabilities", []) == ["PLACE_ITEMS", "SUPPORT_SURFACE", "WORK_SURFACE"], "Operational table capabilities are wrong")
	var snapshot: Dictionary = aggregate.export_snapshot()
	_assert_ok(SnapshotScript.validate(snapshot), "Aggregate exported invalid snapshot")
	_assert(int(snapshot.get("state_revision", -1)) == revision, "Snapshot revision mismatch")
	var restored = AggregateScript.new()
	_assert_ok(restored.load_snapshot(snapshot), "Snapshot restoration failed")
	_assert(restored.export_snapshot() == snapshot, "Snapshot restoration was not deterministic")
	var broken: Dictionary = aggregate.break_bond("op/break/leg-a", revision, "bond/table/leg-a")
	_assert_ok(broken, "Bond break failed")
	revision += 1
	_assert(String(broken.get("build_state", "")) == "DAMAGED", "Bond break did not mark construct damaged")
	var damaged: Dictionary = aggregate.get_compiled_facets()
	_assert(int(damaged.get("rigid_island_count", 0)) == 2, "Broken leg did not split rigid islands")
	_assert(damaged.get("capabilities", []).is_empty(), "Damaged table retained operational capabilities")

func _test_replay_and_revision_fences() -> void:
	var aggregate = AggregateScript.new()
	_assert_ok(aggregate.setup("construct/table/replay", "item/construct/table-replay"), "Replay construct setup failed")
	var part: Dictionary = _parts()[0]
	var first: Dictionary = aggregate.add_part("op/replay/1", 0, part)
	_assert_ok(first, "First operation failed")
	var replay: Dictionary = aggregate.add_part("op/replay/1", 0, part)
	_assert_ok(replay, "Exact replay failed")
	_assert(bool(replay.get("replay", false)), "Exact replay not marked")
	_assert(int(replay.get("state_revision", -1)) == 1, "Replay changed revision")
	var changed_part: Dictionary = part.duplicate(true)
	changed_part["mass_kg"] = 13.0
	_assert_error(aggregate.add_part("op/replay/1", 1, changed_part), "OPERATION_REPLAY_CONFLICT", "Operation collision accepted")
	_assert_error(aggregate.add_part("op/stale/1", 0, _parts()[1]), "STALE_CONSTRUCT_REVISION", "Stale revision accepted")
	var invalid_part: Dictionary = _parts()[1]
	invalid_part["mass_kg"] = 0.0
	_assert_error(aggregate.add_part("op/invalid/1", 1, invalid_part), "INVALID_PART_MASS", "Invalid part accepted")
	var corrected_part: Dictionary = _parts()[1]
	_assert_ok(aggregate.add_part("op/invalid/1", 1, corrected_part), "Failed operation poisoned operation ID")

func _test_transactional_snapshot_load() -> void:
	var aggregate = AggregateScript.new()
	_assert_ok(aggregate.setup("construct/table/load", "item/construct/table-load"), "Load construct setup failed")
	_assert_ok(aggregate.add_part("op/load/1", 0, _parts()[0]), "Load fixture mutation failed")
	var before: Dictionary = aggregate.export_snapshot()
	var invalid: Dictionary = before.duplicate(true)
	invalid["checksum"] = "0".repeat(64)
	_assert_error(aggregate.load_snapshot(invalid), "CONSTRUCT_SNAPSHOT_CHECKSUM_MISMATCH", "Invalid snapshot loaded")
	_assert(aggregate.export_snapshot() == before, "Rejected snapshot mutated aggregate")

func _parts() -> Array:
	return [
		PartScript.create("part/table/top", "item/table/top", "PANEL", "surface", 12.0, [0.0, 0.75, 0.0]),
		PartScript.create("part/table/leg-a", "item/table/leg-a", "BEAM", "support", 2.0, [-0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-b", "item/table/leg-b", "BEAM", "support", 2.0, [0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-c", "item/table/leg-c", "BEAM", "support", 2.0, [0.5, 0.375, 0.3]),
		PartScript.create("part/table/leg-d", "item/table/leg-d", "BEAM", "support", 2.0, [-0.5, 0.375, 0.3]),
	]

func _bonds() -> Array:
	return [
		BondScript.create("bond/table/leg-a", "part/table/top", "part/table/leg-a", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-b", "part/table/top", "part/table/leg-b", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-c", "part/table/top", "part/table/leg-c", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-d", "part/table/top", "part/table/leg-d", "BOLT", 2500.0),
	]

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C1 construct aggregate: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C1 construct aggregate: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
