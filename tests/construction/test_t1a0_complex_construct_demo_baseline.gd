extends SceneTree

const FixtureBuilder = preload("res://scripts/labs/t1/t1_complex_construct_fixture_builder.gd")

const EXPECTED_BASE_COMMIT := "68085c9154a85a581226d08001f8e524b0992323"
const EXPECTED_C24_ACCEPTED_COMMIT := "c18b3afaf0f2f078899be20d0529fa94d53adf90"
const EXPECTED_D0_CHECKSUM := "9e20be039011f6b94582dc4c7cffd2098fea0d145f3c08a3b053902764514d58"
const EXPECTED_D1_CHECKSUM := "876cae0b17d8d508515ea2dafc577ad1b9389070d29d1102d3ad8565bd00b474"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_manifest_contract()
	_test_profile_contracts()
	_test_deterministic_rebuild()
	_test_checksum_detects_mutation()
	_test_demo_scene_boundary()
	_finish()

func _test_manifest_contract() -> void:
	var loaded: Dictionary = FixtureBuilder.load_manifest()
	_ok(loaded, "manifest loads")
	if not bool(loaded.get("success", false)):
		return
	var manifest: Dictionary = loaded["manifest"]
	_assert(String(manifest["checkpoint"]) == "T1A0_BASELINE_AND_FIXTURE_CONTRACTS", "checkpoint pinned")
	_assert(String(manifest["status"]) == "IMPLEMENTED_CANDIDATE", "manifest status")
	_assert(String(manifest["branch"]) == "feature/t1-complex-construct-demo-lab", "branch pinned")
	_assert(String(manifest["branch_base_commit"]) == EXPECTED_BASE_COMMIT, "branch base commit pinned")
	_assert(String(manifest["c24_accepted_commit"]) == EXPECTED_C24_ACCEPTED_COMMIT, "C24 acceptance commit pinned")
	_assert(String(manifest["fixture_seed"]) == "t1a0-lunar-engineering-outpost-v1", "fixture seed pinned")
	_assert(String(manifest["scene_path"]) == "res://scenes/labs/t1_complex_construct_demo.tscn", "demo scene path pinned")
	var policy: Dictionary = manifest["authority_policy"]
	_assert(not bool(policy["production_contract_changes_allowed"]), "production contract mutation forbidden")
	_assert(not bool(policy["fixture_is_authoritative_state"]), "fixture is not authoritative state")
	_assert(bool(policy["fixture_is_data_only"]), "fixture is data-only")
	_assert(String(policy["canonical_construct_checksum_stage"]) == "T1A.2", "canonical construct deferred to T1A.2")
	_assert(String(policy["visual_asset_catalog_stage"]) == "T1A.1", "visual catalog deferred to T1A.1")
	_assert(not bool(policy["network_transport_dependency_allowed"]), "fixture has no transport dependency")

func _test_profile_contracts() -> void:
	var d0_rooms := ["room/t1/d0/habitat"]
	var d0_utilities := ["utility/t1/d0/power", "utility/t1/d0/data"]
	var d0_items := [
		"item/t1/d0/door/main",
		"item/t1/d0/container/storage",
		"item/t1/d0/generator/main",
		"item/t1/d0/battery/main",
		"item/t1/d0/lamp/main",
		"item/t1/d0/console/main",
	]
	_check_profile("D0", 64, "construct/t1/lunar-outpost/d0", d0_rooms, d0_utilities, d0_items, EXPECTED_D0_CHECKSUM, "part/t1/d0/p0000", "part/t1/d0/p0063")

	var d1_rooms := [
		"room/t1/d1/habitat",
		"room/t1/d1/airlock",
		"room/t1/d1/workshop",
		"room/t1/d1/storage",
		"room/t1/d1/utility",
	]
	var d1_utilities := ["utility/t1/d1/power", "utility/t1/d1/data", "utility/t1/d1/air"]
	var d1_items := [
		"item/t1/d1/door/airlock-inner",
		"item/t1/d1/door/airlock-outer",
		"item/t1/d1/door/workshop",
		"item/t1/d1/door/storage",
		"item/t1/d1/container/habitat",
		"item/t1/d1/container/storage",
		"item/t1/d1/container/tools",
		"item/t1/d1/generator/main",
		"item/t1/d1/battery/main",
		"item/t1/d1/lamp/habitat",
		"item/t1/d1/lamp/airlock",
		"item/t1/d1/lamp/workshop",
		"item/t1/d1/console/main",
		"item/t1/d1/fabricator/main",
		"item/t1/d1/workbench/main",
	]
	_check_profile("D1", 384, "construct/t1/lunar-outpost/d1", d1_rooms, d1_utilities, d1_items, EXPECTED_D1_CHECKSUM, "part/t1/d1/p0000", "part/t1/d1/p0383")

	var unknown: Dictionary = FixtureBuilder.build_profile("D2")
	_assert(not bool(unknown.get("success", false)) and String(unknown.get("error_code", "")) == "T1A0_UNKNOWN_PROFILE", "unfrozen D2 profile rejected")

func _check_profile(profile_id: String, expected_count: int, construct_id: String, room_ids: Array, utility_ids: Array, item_ids: Array, expected_checksum: String, first_part_id: String, last_part_id: String) -> void:
	var result: Dictionary = FixtureBuilder.build_profile(profile_id)
	_ok(result, "%s fixture builds" % profile_id)
	if not bool(result.get("success", false)):
		return
	var fixture: Dictionary = result["fixture"]
	_ok(FixtureBuilder.validate_fixture(fixture), "%s fixture validates" % profile_id)
	_assert(String(fixture["profile_id"]) == profile_id, "%s profile id" % profile_id)
	_assert(String(fixture["construct_id"]) == construct_id, "%s construct id" % profile_id)
	_assert(int(fixture["part_count"]) == expected_count, "%s expected part count" % profile_id)
	_assert(Array(fixture["part_ids"]).size() == expected_count, "%s generated part id count" % profile_id)
	_assert(String(fixture["part_ids"][0]) == first_part_id, "%s first deterministic part id" % profile_id)
	_assert(String(fixture["part_ids"][expected_count - 1]) == last_part_id, "%s last deterministic part id" % profile_id)
	_assert(Array(fixture["room_ids"]) == room_ids, "%s room ids pinned" % profile_id)
	_assert(Array(fixture["utility_ids"]) == utility_ids, "%s utility ids pinned" % profile_id)
	_assert(Array(fixture["item_ids"]) == item_ids, "%s item ids pinned" % profile_id)
	_assert(String(fixture["fixture_checksum"]) == expected_checksum, "%s initial fixture checksum pinned" % profile_id)

func _test_deterministic_rebuild() -> void:
	for profile_id in ["D0", "D1"]:
		var first: Dictionary = FixtureBuilder.build_profile(profile_id)
		var second: Dictionary = FixtureBuilder.build_profile(profile_id)
		_ok(first, "%s first deterministic build" % profile_id)
		_ok(second, "%s second deterministic build" % profile_id)
		if bool(first.get("success", false)) and bool(second.get("success", false)):
			_assert(first["fixture"] == second["fixture"], "%s repeated build is byte-semantically identical" % profile_id)
			_assert(String(first["fixture"]["fixture_checksum"]) == String(second["fixture"]["fixture_checksum"]), "%s repeated checksum stable" % profile_id)

func _test_checksum_detects_mutation() -> void:
	var result: Dictionary = FixtureBuilder.build_profile("D0")
	_ok(result, "D0 mutation source builds")
	if not bool(result.get("success", false)):
		return
	var fixture: Dictionary = Dictionary(result["fixture"]).duplicate(true)
	fixture["part_ids"] = Array(fixture["part_ids"]).duplicate(true)
	fixture["part_ids"][0] = "part/t1/d0/corrupt"
	_assert(FixtureBuilder.compute_fixture_checksum(fixture) != EXPECTED_D0_CHECKSUM, "part identity mutation changes fixture checksum")
	_assert(not bool(FixtureBuilder.validate_fixture(fixture).get("success", false)), "mutated fixture fails validation until re-pinned")

func _test_demo_scene_boundary() -> void:
	var loaded: Dictionary = FixtureBuilder.load_manifest()
	_ok(loaded, "manifest reloads for scene test")
	if not bool(loaded.get("success", false)):
		return
	var scene_path := String(loaded["manifest"]["scene_path"])
	_assert(ResourceLoader.exists(scene_path), "demo scene exists")
	var packed = load(scene_path)
	_assert(packed is PackedScene, "demo scene loads as PackedScene")
	if not (packed is PackedScene):
		return
	var instance = packed.instantiate()
	_assert(instance is Node3D, "demo scene root is Node3D")
	_assert(instance.has_method("build_fixture_descriptor"), "demo scene exposes data-only fixture build method")
	var raw_result = instance.call("build_fixture_descriptor", "D0")
	_assert(typeof(raw_result) == TYPE_DICTIONARY, "demo scene returns fixture result dictionary")
	if typeof(raw_result) == TYPE_DICTIONARY:
		var result: Dictionary = raw_result
		_ok(result, "demo scene builds D0 descriptor without authority mutation")
		if bool(result.get("success", false)):
			_assert(String(result["fixture"]["fixture_checksum"]) == EXPECTED_D0_CHECKSUM, "demo scene uses pinned D0 baseline")
	instance.free()

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("T1A.0 complex construct demo baseline: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("T1A.0 complex construct demo baseline: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
