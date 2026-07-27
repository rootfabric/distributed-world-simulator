extends SceneTree

const EntityRecordScript = preload("res://scripts/simulation/entities/entity_record.gd")
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const PartitionAddressScript = preload("res://scripts/simulation/partition/partition_address.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var record = EntityRecordScript.new()
	record.setup_with_spatial_ref(
		"entity/authority-probe",
		"diagnostic_probe",
		SpatialRefScript.create("body/moon/fixed", Vector3(1737400.0, 0.0, 0.0)),
		{},
		"sim-a",
		7
	)
	record.initialize_partition(PartitionAddressScript.create_cube_sphere(0, 0, 0, 0, 0))
	record.set_component("probe", {"value": 1})
	var revision_before: int = record.state_revision
	_assert(revision_before > 0, "Test entity has no revision before authority transfer")
	_assert(record.transfer_authority("sim-b", 8), "Valid authority transfer was rejected")
	_assert(record.authority_owner_id == "sim-b", "Authority owner was not changed")
	_assert(record.authority_epoch == 8, "Authority epoch was not changed")
	_assert(record.state_revision == revision_before + 1, "Authority transfer must increment state revision exactly once")
	_assert(record.revision == record.state_revision, "Revision aliases diverged after authority transfer")
	_assert(not record.transfer_authority("sim-c", 8), "Equal authority epoch was accepted")
	_assert(not record.transfer_authority("sim-c", 7), "Older authority epoch was accepted")
	_assert(record.state_revision == revision_before + 1, "Rejected transfer changed revision")

	var snapshot: Dictionary = record.to_snapshot()
	var restored = EntityRecordScript.new()
	_assert(restored.setup_from_snapshot(snapshot), "Authority snapshot round-trip failed")
	_assert(restored.authority_owner_id == "sim-b", "Snapshot lost authority owner")
	_assert(restored.authority_epoch == 8, "Snapshot lost authority epoch")
	_assert(restored.state_revision == record.state_revision, "Snapshot lost monotonic state revision")
	_assert(restored.transfer_authority("sim-c", 9), "Second authority transfer was rejected")
	_assert(restored.state_revision == record.state_revision + 1, "Second handoff did not preserve revision monotonicity")

	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Authority revision semantics: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Authority revision semantics: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
