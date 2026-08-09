extends SceneTree

const FixtureBuilderScript = preload("res://scripts/labs/t1/t1_complex_construct_fixture_builder.gd")
const BuilderScript = preload("res://scripts/labs/t1/t1_d0_authoritative_outpost_builder.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ConstructStoreScript = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const ConstructStoreStateScript = preload("res://scripts/construction/authoritative/construction_construct_store.gd")

const D0_FIXTURE_CHECKSUM := "9e20be039011f6b94582dc4c7cffd2098fea0d145f3c08a3b053902764514d58"
const D0_CONSTRUCT_ID := "construct/t1/lunar-outpost/d0"
const EXPECTED_PART_COUNT := 64
const EXPECTED_BOND_COUNT := 112
const EXPECTED_STATE_REVISION := 177

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	_test_deterministic_authoritative_snapshot()
	_test_authoritative_store_materialization()
	_test_p0_boundary_guards()
	_finish()


func _test_deterministic_authoritative_snapshot() -> void:
	var fixture_result: Dictionary = FixtureBuilderScript.build_profile("D0")
	_assert_ok(fixture_result, "D0 fixture failed to build")
	if not bool(fixture_result.get("success", false)):
		return
	var fixture: Dictionary = Dictionary(fixture_result["fixture"])
	var fixture_before := fixture.duplicate(true)

	var first: Dictionary = BuilderScript.build_from_fixture(fixture)
	_assert_ok(first, "T1A.2 D0 build failed")
	if not bool(first.get("success", false)):
		return
	var second: Dictionary = BuilderScript.build_d0()
	_assert_ok(second, "T1A.2 repeated D0 build failed")
	if not bool(second.get("success", false)):
		return

	_assert(fixture == fixture_before, "T1A.2 mutated the data-only fixture")
	_assert(String(first.get("fixture_checksum", "")) == D0_FIXTURE_CHECKSUM, "Fixture checksum changed")
	_assert(String(first.get("construct_id", "")) == D0_CONSTRUCT_ID, "Construct identity changed")
	_assert(String(first.get("root_item_instance_id", "")) == "item/t1/d0/construct-root", "Root item reference changed")
	_assert(int(first.get("part_count", -1)) == EXPECTED_PART_COUNT, "D0 part count mismatch")
	_assert(int(first.get("bond_count", -1)) == EXPECTED_BOND_COUNT, "D0 bond count mismatch")
	_assert(int(first.get("state_revision", -1)) == EXPECTED_STATE_REVISION, "D0 state revision mismatch")
	_assert(String(first.get("snapshot_checksum", "")).length() == 64, "Snapshot checksum is not SHA-256 shaped")
	_assert(first.get("snapshot", {}) == second.get("snapshot", {}), "Repeated D0 build is not deterministic")
	_assert(first.get("snapshot_checksum", "") == second.get("snapshot_checksum", ""), "Repeated snapshot checksum changed")

	var snapshot: Dictionary = Dictionary(first["snapshot"])
	_assert_ok(SnapshotScript.validate(snapshot), "Production ConstructSnapshot rejected D0")
	_assert(String(snapshot.get("schema", "")) == SnapshotScript.SCHEMA, "Wrong ConstructSnapshot schema")
	_assert(String(snapshot.get("build_state", "")) == "OPERATIONAL", "D0 did not become OPERATIONAL")
	_assert(Array(snapshot.get("parts", [])).size() == EXPECTED_PART_COUNT, "Snapshot part count mismatch")
	_assert(Array(snapshot.get("bonds", [])).size() == EXPECTED_BOND_COUNT, "Snapshot bond count mismatch")

	var expected_part_ids: Array = Array(fixture["part_ids"]).duplicate(true)
	expected_part_ids.sort()
	var actual_part_ids: Array = []
	var seen_items: Dictionary = {}
	var support_count := 0
	var surface_count := 0
	for part_value in snapshot["parts"]:
		var part: Dictionary = part_value
		actual_part_ids.append(String(part["part_id"]))
		var item_id := String(part["item_instance_id"])
		_assert(item_id.begins_with("item/t1/d0/structural/p"), "Part uses a non-reserved structural item reference")
		_assert(not seen_items.has(item_id), "Part item reference was reused")
		seen_items[item_id] = true
		match String(part["role"]):
			"support": support_count += 1
			"surface": surface_count += 1
			_: _assert(false, "Unexpected D0 part role")
	_assert(actual_part_ids == expected_part_ids, "Fixture part identity was not preserved")
	_assert(support_count == 4, "D0 must have four corner supports")
	_assert(surface_count == 60, "D0 must have sixty surface parts")

	var facets: Dictionary = Dictionary(snapshot.get("compiled_facets", {}))
	_assert(bool(facets.get("connected", false)), "D0 compiled graph is disconnected")
	_assert(bool(facets.get("stable", false)), "D0 compiled graph is unstable")
	_assert(int(facets.get("rigid_island_count", -1)) == 1, "D0 has more than one rigid island")
	_assert(Array(facets.get("capabilities", [])) == ["PLACE_ITEMS", "SUPPORT_SURFACE", "WORK_SURFACE"], "D0 capabilities differ from C1 semantics")

	_assert(Array(first.get("source_room_ids", [])) == Array(fixture["room_ids"]), "Room fixture references were lost")
	_assert(Array(first.get("source_utility_ids", [])) == Array(fixture["utility_ids"]), "Utility fixture references were lost")
	_assert(Array(first.get("deferred_item_graph_ids", [])) == Array(fixture["item_ids"]), "Deferred Item Graph references were lost")


func _test_authoritative_store_materialization() -> void:
	var built: Dictionary = BuilderScript.build_d0()
	_assert_ok(built, "D0 build for store materialization failed")
	if not bool(built.get("success", false)):
		return
	var store = ConstructStoreScript.new()
	_assert(store.size() == 0, "Fresh ConstructionConstructStore is not empty")
	var applied: Dictionary = BuilderScript.materialize_into_store(store, built)
	_assert_ok(applied, "D0 CREATE mutation failed")
	if not bool(applied.get("success", false)):
		return
	_assert(store.size() == 1, "Authoritative construct store did not gain D0")
	_assert(store.has_construct(D0_CONSTRUCT_ID), "Authoritative construct store lost D0 identity")
	_assert(store.get_snapshot(D0_CONSTRUCT_ID) == built["snapshot"], "Authoritative store snapshot differs from builder snapshot")
	var store_state: Dictionary = store.to_dict()
	_assert_ok(ConstructStoreStateScript.validate_state(store_state), "Authoritative construct store state is invalid")
	var repeated: Dictionary = BuilderScript.materialize_into_store(store, built)
	_assert_error(repeated, "T1A2_CONSTRUCT_ALREADY_MATERIALIZED", "Duplicate D0 materialization was accepted")


func _test_p0_boundary_guards() -> void:
	var d1_result: Dictionary = FixtureBuilderScript.build_profile("D1")
	_assert_ok(d1_result, "D1 fixture failed to build for negative guard")
	if bool(d1_result.get("success", false)):
		_assert_error(
			BuilderScript.build_from_fixture(Dictionary(d1_result["fixture"])),
			"T1A2_ONLY_D0_SUPPORTED",
			"T1A.2 silently expanded into D1"
		)

	var d0_result: Dictionary = FixtureBuilderScript.build_profile("D0")
	_assert_ok(d0_result, "D0 fixture failed to build for corruption guard")
	if bool(d0_result.get("success", false)):
		var corrupt: Dictionary = Dictionary(d0_result["fixture"]).duplicate(true)
		corrupt["fixture_checksum"] = "0".repeat(64)
		_assert_error(
			BuilderScript.build_from_fixture(corrupt),
			"T1A0_FIXTURE_CHECKSUM_INVALID",
			"Corrupted fixture crossed the authoritative boundary"
		)

	var built: Dictionary = BuilderScript.build_d0()
	_assert_ok(built, "D0 build failed for P0 boundary checks")
	if not bool(built.get("success", false)):
		return
	var snapshot: Dictionary = Dictionary(built["snapshot"])
	var snapshot_text := JSON.stringify(snapshot)
	for forbidden in [
		"visual_profile_id",
		"representation_class",
		"detail_mode",
		"compiled_proxy",
		"surface_cell",
		"authority_owner",
		"authority_route",
		"server_id",
		"material_definition_id",
	]:
		_assert(not snapshot_text.contains(forbidden), "Canonical D0 snapshot leaked P0/presentation field: %s" % forbidden)
	for deferred_item_id in built.get("deferred_item_graph_ids", []):
		_assert(not snapshot_text.contains(String(deferred_item_id)), "T1A.3 Item Graph fixture ID was materialized during T1A.2")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, code: String, message: String) -> void:
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
		print("T1A.2 D0 authoritative outpost builder: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("T1A.2 D0 authoritative outpost builder: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
