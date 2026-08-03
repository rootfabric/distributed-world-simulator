extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Fixture = preload("res://tests/construction/fixtures/c14_structural_integrity_fixture.gd")
const LoadCaseScript = preload("res://scripts/construction/structural/construction_structural_load_case.gd")
const LoadPathScript = preload("res://scripts/construction/structural/construction_structural_load_path.gd")
const ProfileScript = preload("res://scripts/construction/structural/construction_structural_profile.gd")
const CompilerScript = preload("res://scripts/construction/structural/construction_structural_compiler.gd")
const CascadePlannerScript = preload("res://scripts/construction/structural/construction_structural_cascade_planner.gd")
const CascadePlanScript = preload("res://scripts/construction/structural/construction_structural_cascade_plan.gd")
const SummaryScript = preload("res://scripts/construction/structural/construction_structural_summary.gd")
const StoreScript = preload("res://scripts/construction/structural/construction_structural_profile_store.gd")
const PersistenceScript = preload("res://scripts/construction/structural/construction_structural_persistence.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")

class MemoryStorage:
	extends RefCounted
	var values := {}
	func put(key: String, value: Dictionary) -> Dictionary: values[key] = value.duplicate(true); return {"success": true, "error_code": "", "message": ""}
	func get_value(key: String) -> Dictionary:
		if not values.has(key): return {"success": false, "error_code": "NOT_FOUND", "message": "NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "value": Dictionary(values[key]).duplicate(true)}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_load_case_contract()
	_test_stable_load_paths()
	_test_overload_and_alternate_path()
	_test_part_capacity_and_buckling()
	_test_cascade_plan()
	_test_summary_store_and_persistence()
	_finish()

func _test_load_case_contract() -> void:
	var snapshot := Fixture.snapshot("contracts")
	var load_case := Fixture.load_case("contracts", snapshot)
	_assert_ok(LoadCaseScript.validate(load_case), "Valid structural load case rejected")
	_assert(String(load_case["checksum"]).length() == 64, "Load case checksum missing")
	_assert(load_case["support_part_ids"] == ["part/structural/contracts/foundation"], "Support IDs not canonical")
	_assert(load_case["external_part_loads_n"].is_empty(), "Stable load case unexpectedly has external load")
	var unknown := load_case.duplicate(true); unknown["unexpected_field"] = true
	_assert_error(LoadCaseScript.validate(unknown), "UNEXPECTED_FIELD", "Load case accepted unknown field")
	var bad_gravity := load_case.duplicate(true); bad_gravity["gravity_m_s2"] = 0.0; bad_gravity["checksum"] = LoadCaseScript.compute_checksum(bad_gravity)
	_assert_error(LoadCaseScript.validate(bad_gravity), "INVALID_CONSTRUCTION_STRUCTURAL_GRAVITY", "Load case accepted zero gravity")
	var bad_supports := load_case.duplicate(true); bad_supports["support_part_ids"] = []; bad_supports["checksum"] = LoadCaseScript.compute_checksum(bad_supports)
	_assert_error(LoadCaseScript.validate(bad_supports), "INVALID_CONSTRUCTION_STRUCTURAL_SUPPORT_PARTS", "Load case accepted no supports")
	var duplicate_support := load_case.duplicate(true); duplicate_support["support_part_ids"] = [load_case["support_part_ids"][0], load_case["support_part_ids"][0]]; duplicate_support["checksum"] = LoadCaseScript.compute_checksum(duplicate_support)
	_assert_error(LoadCaseScript.validate(duplicate_support), "INVALID_CONSTRUCTION_STRUCTURAL_SUPPORT_PART", "Load case accepted duplicate support")
	var bad_factor := load_case.duplicate(true); bad_factor["degraded_capacity_factor"] = 1.1; bad_factor["checksum"] = LoadCaseScript.compute_checksum(bad_factor)
	_assert_error(LoadCaseScript.validate(bad_factor), "INVALID_CONSTRUCTION_STRUCTURAL_DEGRADED_CAPACITY_FACTOR", "Load case accepted invalid degraded factor")
	var bad_steps := load_case.duplicate(true); bad_steps["maximum_cascade_steps"] = 0; bad_steps["checksum"] = LoadCaseScript.compute_checksum(bad_steps)
	_assert_error(LoadCaseScript.validate(bad_steps), "INVALID_CONSTRUCTION_STRUCTURAL_MAXIMUM_CASCADE_STEPS", "Load case accepted zero cascade steps")
	var missing_support := load_case.duplicate(true); missing_support["support_part_ids"] = ["part/structural/contracts/missing"]; missing_support["checksum"] = LoadCaseScript.compute_checksum(missing_support)
	_assert_error(CompilerScript.compile(snapshot, missing_support), "CONSTRUCTION_STRUCTURAL_SUPPORT_PART_NOT_FOUND", "Compiler accepted missing support")
	var stale := load_case.duplicate(true); stale["source_snapshot_checksum"] = "0".repeat(64); stale["checksum"] = LoadCaseScript.compute_checksum(stale)
	_assert_error(CompilerScript.compile(snapshot, stale), "CONSTRUCTION_STRUCTURAL_SOURCE_CHECKSUM_MISMATCH", "Compiler accepted stale snapshot checksum")

func _test_stable_load_paths() -> void:
	var snapshot := Fixture.snapshot("stable")
	var load_case := Fixture.load_case("stable", snapshot)
	var result := CompilerScript.compile(snapshot, load_case); _assert_ok(result, "Stable structural compile failed")
	var profile: Dictionary = result["profile"]
	_assert_ok(ProfileScript.validate(profile), "Stable structural profile rejected")
	_assert(String(profile["structural_state"]) == "STABLE", "Stable structure not classified stable")
	_assert(profile["part_states"].size() == 5, "Part state count mismatch")
	_assert(profile["bond_states"].size() == 5, "Bond state count mismatch")
	_assert(profile["load_paths"].size() == 4, "Load path count mismatch")
	_assert(profile["overloaded_part_ids"].is_empty(), "Stable profile has overloaded parts")
	_assert(profile["overloaded_bond_ids"].is_empty(), "Stable profile has overloaded bonds")
	_assert(profile["unsupported_part_ids"].is_empty(), "Stable profile has unsupported parts")
	var primary := _bond_state(profile, "bond/structural/stable/column-payload-primary")
	_assert(absf(float(primary["load_n"]) - 980.665) < 0.001, "Primary bond load mismatch")
	_assert(absf(float(primary["utilization"]) - 980.665 / 1500.0) < 0.000001, "Primary utilization mismatch")
	var foundation := _part_state(profile, "part/structural/stable/foundation")
	_assert(String(foundation["state"]) == "SUPPORT", "Foundation not classified support")
	_assert(absf(float(foundation["reaction_n"]) - 1274.8645) < 0.001, "Support reaction mismatch")
	var payload_path := _source_paths(profile, "part/structural/stable/payload")
	_assert(payload_path.size() == 1, "Payload did not get one shortest path")
	_assert(payload_path[0]["bond_ids"] == ["bond/structural/stable/column-payload-primary", "bond/structural/stable/foundation-column"], "Payload path is not deterministic shortest route")
	var repeated := CompilerScript.compile(snapshot, load_case); _assert_ok(repeated, "Repeated stable compile failed")
	_assert(String(repeated["profile"]["checksum"]) == String(profile["checksum"]), "Structural compile is not deterministic")
	_assert(not UtilsScript.canonical_json(profile).is_empty(), "Structural profile is not JSON-safe")
	var tampered := profile.duplicate(true); tampered["total_support_reaction_n"] = float(tampered["total_support_reaction_n"]) + 1.0
	_assert_error(ProfileScript.validate(tampered), "CONSTRUCTION_STRUCTURAL_PROFILE_NUMERIC_SUMMARY_MISMATCH", "Profile accepted tampered reaction")
	var bad_path: Dictionary = profile["load_paths"][0].duplicate(true); bad_path["part_ids"] = bad_path["part_ids"].duplicate(); bad_path["part_ids"].append(bad_path["part_ids"][-1]); bad_path["checksum"] = LoadPathScript.compute_checksum(bad_path)
	_assert_error(LoadPathScript.validate(bad_path), "INVALID_CONSTRUCTION_STRUCTURAL_LOAD_PATH_BONDS", "Load path accepted inconsistent member counts")

func _test_overload_and_alternate_path() -> void:
	var source := Fixture.snapshot("overload")
	var loaded := Fixture.load_case("overload", source, true)
	var first := CompilerScript.compile(source, loaded); _assert_ok(first, "Overloaded structural compile failed")
	var first_profile: Dictionary = first["profile"]
	_assert(String(first_profile["structural_state"]) == "OVERLOADED", "External load did not overload structure")
	_assert(first_profile["overloaded_bond_ids"] == ["bond/structural/overload/column-payload-primary"], "Wrong primary bond overloaded")
	_assert(float(_bond_state(first_profile, "bond/structural/overload/column-payload-primary")["utilization"]) > 1.0, "Primary bond utilization not above one")
	_assert(float(_bond_state(first_profile, "bond/structural/overload/brace-payload-secondary")["load_n"]) == 0.0, "Longer alternate path carried load before primary failure")
	var primary_broken := Fixture.snapshot("overload", 1, ["primary"])
	var second_case := Fixture.load_case("overload", primary_broken, true)
	var second := CompilerScript.compile(primary_broken, second_case); _assert_ok(second, "Alternate path compile failed")
	var second_profile: Dictionary = second["profile"]
	_assert(second_profile["overloaded_bond_ids"] == ["bond/structural/overload/brace-payload-secondary"], "Alternate bond did not overload after primary failure")
	_assert(float(_bond_state(second_profile, "bond/structural/overload/brace-payload-secondary")["load_n"]) > 1700.0, "Alternate bond did not receive transferred load")
	var both_broken := Fixture.snapshot("overload", 2, ["primary", "secondary"])
	var unsupported_case := Fixture.load_case("overload", both_broken, true)
	var final := CompilerScript.compile(both_broken, unsupported_case); _assert_ok(final, "Unsupported profile compile failed")
	_assert(String(final["profile"]["structural_state"]) == "UNSUPPORTED", "Disconnected component not classified unsupported")
	_assert(final["profile"]["unsupported_part_ids"] == ["part/structural/overload/payload", "part/structural/overload/tool"], "Unsupported part set mismatch")
	var safety_case := Fixture.load_case("safety", Fixture.snapshot("safety"), false, 16, 2.0)
	var safety := CompilerScript.compile(Fixture.snapshot("safety"), safety_case); _assert_ok(safety, "Safety-factor compile failed")
	_assert(safety["profile"]["overloaded_bond_ids"].has("bond/structural/safety/column-payload-primary"), "Safety factor did not reduce capacity")
	var degraded_snapshot := Fixture.snapshot("degraded")
	for bond in degraded_snapshot["bonds"]:
		if String(bond["bond_id"]) == "bond/structural/degraded/column-payload-primary": bond["state"] = "DEGRADED"
	degraded_snapshot["checksum"] = SnapshotScript.compute_checksum(degraded_snapshot)
	var degraded := CompilerScript.compile(degraded_snapshot, Fixture.load_case("degraded", degraded_snapshot)); _assert_ok(degraded, "Degraded bond compile failed")
	_assert(degraded["profile"]["overloaded_bond_ids"] == ["bond/structural/degraded/column-payload-primary"], "Degraded capacity factor not applied")

func _test_part_capacity_and_buckling() -> void:
	var weak := Fixture.snapshot("weak", 0, [], true)
	var result := CompilerScript.compile(weak, Fixture.load_case("weak", weak, true)); _assert_ok(result, "Weak part compile failed")
	var payload := _part_state(result["profile"], "part/structural/weak/payload")
	_assert(String(payload["state"]) == "OVERLOADED", "Weak payload not overloaded")
	_assert(float(payload["utilization"]) > 1.5, "Weak payload did not exceed collapse utilization")
	var cascade := CascadePlannerScript.build("cascade/weak", weak, Fixture.load_case("weak", weak, true)); _assert_ok(cascade, "Weak-part cascade planning failed")
	_assert(String(cascade["plan"]["part_conditions"]["part/structural/weak/payload"]) == "DESTROYED", "Collapse threshold did not destroy weak part")
	_assert(cascade["plan"]["failed_bond_ids"].has("bond/structural/weak/column-payload-primary"), "Destroyed part did not break adjacent primary bond")
	_assert(cascade["plan"]["failed_bond_ids"].has("bond/structural/weak/brace-payload-secondary"), "Destroyed part did not break adjacent secondary bond")
	var buckling := Fixture.snapshot("buckling", 0, [], false, true)
	var buckling_result := CompilerScript.compile(buckling, Fixture.load_case("buckling", buckling)); _assert_ok(buckling_result, "Buckling compile failed")
	var column := _part_state(buckling_result["profile"], "part/structural/buckling/column")
	_assert(absf(float(column["effective_capacity_n"]) - 1100.0) < 0.000001, "Buckling capacity did not cap part capacity")
	_assert(float(column["utilization"]) > 1.0, "Buckling-limited column not overloaded")

func _test_cascade_plan() -> void:
	var source := Fixture.snapshot("cascade")
	var load_case := Fixture.load_case("cascade", source, true)
	var result := CascadePlannerScript.build("cascade/structural/cascade", source, load_case); _assert_ok(result, "Progressive cascade planning failed")
	var plan: Dictionary = result["plan"]
	_assert_ok(CascadePlanScript.validate(plan), "Cascade plan rejected")
	_assert(not bool(plan["stable"]), "Overloaded cascade marked stable")
	_assert(plan["step_profiles"].size() == 3, "Cascade did not include primary, alternate, and unsupported steps")
	_assert(plan["failed_bond_ids"] == ["bond/structural/cascade/brace-payload-secondary", "bond/structural/cascade/column-payload-primary"], "Cascade failure sequence mismatch")
	_assert(String(plan["step_profiles"][0]["structural_state"]) == "OVERLOADED", "Cascade step 0 state mismatch")
	_assert(String(plan["step_profiles"][1]["structural_state"]) == "OVERLOADED", "Cascade step 1 state mismatch")
	_assert(String(plan["step_profiles"][2]["structural_state"]) == "UNSUPPORTED", "Cascade final state mismatch")
	_assert(plan["damage_request"]["broken_bond_ids"] == plan["failed_bond_ids"], "Damage request does not match cascade failures")
	_assert(plan["damage_request"]["split_targets"].size() == 1, "Cascade did not preassign split target")
	_assert(String(plan["damage_request"]["split_targets"][0]["construct_id"]) == "construct/structural/cascade/structural-split-01", "Cascade split construct ID mismatch")
	var repeated := CascadePlannerScript.build("cascade/structural/cascade", source, load_case); _assert_ok(repeated, "Repeated cascade planning failed")
	_assert(String(repeated["plan"]["checksum"]) == String(plan["checksum"]), "Cascade plan is not deterministic")
	var stable := CascadePlannerScript.build("cascade/structural/stable", Fixture.snapshot("cascade-stable"), Fixture.load_case("cascade-stable", Fixture.snapshot("cascade-stable"))); _assert_ok(stable, "Stable cascade planning failed")
	_assert(bool(stable["plan"]["stable"]), "Stable structure produced damage plan")
	_assert(stable["plan"]["damage_request"].is_empty(), "Stable cascade has damage request")
	var limited_case := Fixture.load_case("limited", Fixture.snapshot("limited"), true, 1)
	_assert_error(CascadePlannerScript.build("cascade/structural/limited", Fixture.snapshot("limited"), limited_case), "CONSTRUCTION_STRUCTURAL_CASCADE_LIMIT_EXCEEDED", "Cascade accepted insufficient maximum steps")

func _test_summary_store_and_persistence() -> void:
	var snapshot := Fixture.snapshot("store")
	var profile: Dictionary = CompilerScript.compile(snapshot, Fixture.load_case("store", snapshot))["profile"]
	var summary_result := SummaryScript.compile(profile); _assert_ok(summary_result, "Structural summary compile failed")
	var summary: Dictionary = summary_result["summary"]
	_assert_ok(SummaryScript.validate(summary), "Structural summary rejected")
	_assert(String(summary["structural_state"]) == "STABLE", "Summary state mismatch")
	_assert(int(summary["part_count"]) == 5 and int(summary["bond_count"]) == 5, "Summary counts mismatch")
	_assert(int(summary["load_path_count"]) == 4, "Summary path count mismatch")
	var store = StoreScript.new()
	var published := store.publish(profile); _assert_ok(published, "Structural profile publish failed")
	_assert(int(store.get_generation()) == 1, "Structural store generation mismatch")
	var replay := store.publish(profile); _assert_ok(replay, "Structural profile replay failed")
	_assert(bool(replay["replay"]) and int(store.get_generation()) == 1, "Structural profile replay changed generation")
	var stale_snapshot := Fixture.snapshot("store", 0, ["primary"])
	var stale_profile: Dictionary = CompilerScript.compile(stale_snapshot, Fixture.load_case("store", stale_snapshot))["profile"]
	_assert_error(store.publish(stale_profile), "CONSTRUCTION_STRUCTURAL_SAME_REVISION_MUTATION", "Store accepted same-revision mutation")
	var state := store.export_state()
	_assert(String(state["checksum"]).length() == 64, "Structural store state checksum missing")
	var storage = MemoryStorage.new(); _assert_ok(PersistenceScript.save(storage, store), "Structural persistence save failed")
	var restored = StoreScript.new(); _assert_ok(PersistenceScript.load(storage, restored), "Structural persistence load failed")
	_assert(UtilsScript.canonical_json(restored.export_state()) == UtilsScript.canonical_json(state), "Structural store persistence roundtrip changed state")
	var tampered := state.duplicate(true); tampered["profiles"][0]["maximum_utilization"] = 99.0; tampered["profiles"][0]["checksum"] = ProfileScript.compute_checksum(tampered["profiles"][0]); tampered["checksum"] = StoreScript.compute_state_checksum(tampered)
	var clean = StoreScript.new(); _assert_error(clean.load_state(tampered), "CONSTRUCTION_STRUCTURAL_PROFILE_NUMERIC_SUMMARY_MISMATCH", "Store accepted internally inconsistent profile")
	_assert(clean.get_all().is_empty(), "Rejected structural state mutated store")

func _bond_state(profile: Dictionary, bond_id: String) -> Dictionary:
	for state in profile["bond_states"]:
		if String(state["bond_id"]) == bond_id: return state
	return {}
func _part_state(profile: Dictionary, part_id: String) -> Dictionary:
	for state in profile["part_states"]:
		if String(state["part_id"]) == part_id: return state
	return {}
func _source_paths(profile: Dictionary, source_part_id: String) -> Array:
	var result: Array = []
	for path in profile["load_paths"]:
		if String(path["source_part_id"]) == source_part_id: result.append(path)
	return result
func _assert_ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, expected: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == expected, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C14 structural integrity contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C14 structural integrity contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
