extends SceneTree

const Builder = preload("res://scripts/labs/t1/ts0/ts0_large_structural_fixture_builder.gd")

const MATERIALIZED_PROFILES := [
	"CUBE_10K",
	"PYRAMID_10K",
]
const EXPECTED_COUNTS := {
	"CUBE_10K": 10648,
	"PYRAMID_10K": 10416,
	"CUBE_100K": 97336,
	"PYRAMID_100K": 102510,
	"CUBE_1M_RESEARCH": 1000000,
}
const EXPECTED_CHECKSUMS := {
	"CUBE_10K": "6afcb91d403e0e380f33ad202748f6f7524843188036d9e083e1cbe315672a4f",
	"PYRAMID_10K": "39babb3e29949f48fb2df1ddc89c24f6a16e46760939a5b009c29bfbbe5464bf",
	"CUBE_100K": "4aebed994f09f578ae241a9c8adb677eb5cf81d1581aea99491921c6f685e084",
	"PYRAMID_100K": "4a721061894d65b7bee1d9502a331e0879e4ce5a8047cfe53650460e07b636e6",
	"CUBE_1M_RESEARCH": "bfdefbbefc2cde42e713ff6eefbe63c88d35777a4ce9f7deb0d9d25318035543",
}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_config_alignment()
	_test_profile_contracts()
	_test_materialized_profiles()
	_test_deferred_scale_profiles()
	_test_research_profile_is_non_blocking()
	_finish()

func _test_config_alignment() -> void:
	var loaded := Builder.load_config()
	_ok(loaded, "TS0 config loads")
	if not bool(loaded.get("success", false)):
		return
	var config: Dictionary = loaded["config"]
	_assert(String(config["global_revision"]) == "GLOBAL-P0-2026-08-10-R2", "global revision pinned")
	_assert(String(config["status"]) == "TS0_0_IMPLEMENTED_CANDIDATE", "TS0.0 candidate status pinned")
	var grid: Dictionary = config["structural_grid"]
	_assert(float(grid["cell_size_m"]) == 1.0, "C22 unit grid cell size")
	_assert(float(grid["section_size_m"]) == 8.0, "TS0 local section size")
	_assert(String(grid["representation_fast_path"]) == "C22_UNIT_AXIS_GRID", "C22 fast path pinned")
	for profile_id in config["profiles"]:
		var profile: Dictionary = config["profiles"][profile_id]
		_assert(float(profile["block_size_m"]) == 1.0, "%s uses unit cells" % profile_id)

func _test_profile_contracts() -> void:
	for profile_id in EXPECTED_COUNTS:
		var described := Builder.describe_profile(profile_id)
		_ok(described, "%s descriptor" % profile_id)
		if not bool(described.get("success", false)):
			continue
		_assert(int(described["computed_part_count"]) == int(EXPECTED_COUNTS[profile_id]), "%s count formula" % profile_id)
		_assert(String(described["expected_canonical_checksum"]) == String(EXPECTED_CHECKSUMS[profile_id]), "%s checksum pin" % profile_id)

func _test_materialized_profiles() -> void:
	for profile_id in MATERIALIZED_PROFILES:
		var started := Time.get_ticks_msec()
		var forward := Builder.build_profile(profile_id, Builder.FORWARD)
		_ok(forward, "%s forward build" % profile_id)
		if not bool(forward.get("success", false)):
			continue
		var snapshot: Dictionary = forward["snapshot"]
		_assert(Array(snapshot["parts"]).size() == int(EXPECTED_COUNTS[profile_id]), "%s canonical part count" % profile_id)
		_assert(String(snapshot["checksum"]) == String(EXPECTED_CHECKSUMS[profile_id]), "%s canonical checksum" % profile_id)
		_assert(int(snapshot["state_revision"]) == 1, "%s canonical revision" % profile_id)
		_assert(Array(snapshot["bonds"]).is_empty(), "%s fixture has no synthetic bond graph" % profile_id)
		_assert(String(snapshot["build_state"]) == "OPERATIONAL", "%s build state" % profile_id)
		var parts: Array = snapshot["parts"]
		if not parts.is_empty():
			_assert(Builder.is_c22_unit_grid_compatible_part(parts[0]), "%s first part matches C22 unit grid" % profile_id)
			_assert(Builder.is_c22_unit_grid_compatible_part(parts[parts.size() / 2]), "%s middle part matches C22 unit grid" % profile_id)
			_assert(Builder.is_c22_unit_grid_compatible_part(parts[parts.size() - 1]), "%s last part matches C22 unit grid" % profile_id)
		var forward_checksum := String(snapshot["checksum"])
		var forward_parts := parts.size()
		forward.clear()
		snapshot.clear()
		parts.clear()

		var reverse := Builder.build_profile(profile_id, Builder.REVERSE)
		_ok(reverse, "%s reverse build" % profile_id)
		if bool(reverse.get("success", false)):
			_assert(int(reverse["canonical_part_count"]) == forward_parts, "%s reverse count stable" % profile_id)
			_assert(String(reverse["canonical_checksum"]) == forward_checksum, "%s traversal-order invariant checksum" % profile_id)
		reverse.clear()
		print("TS0.0 fixture metric: profile=%s parts=%d elapsed_ms=%d" % [
			profile_id,
			forward_parts,
			Time.get_ticks_msec() - started,
		])

func _test_deferred_scale_profiles() -> void:
	for profile_id in ["CUBE_100K", "PYRAMID_100K"]:
		var described := Builder.describe_profile(profile_id)
		_ok(described, "%s deferred scale descriptor" % profile_id)
		if not bool(described.get("success", false)):
			continue
		var profile: Dictionary = described["profile"]
		_assert(not bool(profile["materialize_in_ts0_0_acceptance"]), "%s stays out of TS0.0 materialization gate" % profile_id)
		_assert(int(described["computed_part_count"]) >= 90000, "%s remains a 100k-class scale profile" % profile_id)

func _test_research_profile_is_non_blocking() -> void:
	var described := Builder.describe_profile("CUBE_1M_RESEARCH")
	_ok(described, "1M research descriptor")
	if bool(described.get("success", false)):
		_assert(int(described["computed_part_count"]) == 1000000, "1M count formula pinned")
		_assert(String(described["expected_canonical_checksum"]) == String(EXPECTED_CHECKSUMS["CUBE_1M_RESEARCH"]), "1M checksum pre-pinned")
	var blocked := Builder.build_profile("CUBE_1M_RESEARCH")
	_assert(not bool(blocked.get("success", false)), "1M is not materialized by TS0.0 default acceptance")
	_assert(String(blocked.get("error_code", "")) == "TS0_RESEARCH_PROFILE_REQUIRES_EXPLICIT_OPT_IN", "1M explicit opt-in guard")

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("TS0.0 deterministic large structural fixtures: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("TS0.0 deterministic large structural fixtures: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
