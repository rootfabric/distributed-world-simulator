extends SceneTree

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const F = preload("res://tests/construction/fixtures/c18_streaming_fixture.gd")
const Level = preload("res://scripts/construction/streaming/construction_activity_level.gd")
const Policy = preload("res://scripts/construction/streaming/construction_streaming_policy.gd")
const Interest = preload("res://scripts/construction/streaming/construction_interest_sample.gd")
const Request = preload("res://scripts/construction/streaming/construction_streaming_request.gd")
const Summary = preload("res://scripts/construction/streaming/construction_construct_summary.gd")
const Record = preload("res://scripts/construction/streaming/construction_activity_record.gd")
const CatchUp = preload("res://scripts/construction/streaming/construction_catch_up_plan.gd")
const Budget = preload("res://scripts/construction/streaming/construction_streaming_budget_report.gd")
const State = preload("res://scripts/construction/streaming/construction_streaming_state.gd")
const Lod = preload("res://scripts/construction/streaming/construction_lod_profile.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_levels_and_policy()
	_test_interest_and_request()
	_test_summary_and_record()
	_test_catch_up_and_budget()
	_test_lod_profile()
	_test_state()
	_finish()

func _test_levels_and_policy() -> void:
	_assert(Level.rank(Level.DORMANT) < Level.rank(Level.SUMMARY), "DORMANT rank")
	_assert(Level.rank(Level.SUMMARY) < Level.rank(Level.SIMULATED), "SUMMARY rank")
	_assert(Level.rank(Level.SIMULATED) < Level.rank(Level.PRESENTED), "SIMULATED rank")
	_assert(Level.max_level(Level.SUMMARY, Level.PRESENTED) == Level.PRESENTED, "max level")
	var policy := F.policy(); _ok(Policy.validate(policy), "policy")
	_assert(String(policy["checksum"]).length() == 64, "policy checksum")
	var extra := policy.duplicate(true); extra["unexpected"] = true; _err(Policy.validate(extra), "UNEXPECTED_FIELD", "policy extra")
	var non_monotonic := Policy.create(100.0, 50.0, 500.0); _err(Policy.validate(non_monotonic), "NON_MONOTONIC_CONSTRUCTION_STREAMING_DISTANCES", "policy distance order")
	var bad_interval := Policy.create(10.0, 20.0, 30.0, 1.0, 1, 1, 1, 1, 0, 1); _err(Policy.validate(bad_interval), "INVALID_CONSTRUCTION_STREAMING_CATCH_UP_POLICY", "policy interval")

func _test_interest_and_request() -> void:
	var request := F.request("contracts"); _ok(Request.validate(request), "request")
	_assert(request["capability_kinds"] == ["LOAD_BEARING_MEMBER", "POWERED"], "capability order")
	_assert(request["pending_job_ids"].size() == 1 and request["pending_operation_ids"].size() == 1, "pending identity")
	_assert(not Utils.canonical_json(request).is_empty(), "request json")
	var sample := F.sample_for(request, 5, 12.5, true, false, false, 10); _ok(Interest.validate(sample), "interest")
	var bad_tick := sample.duplicate(true); bad_tick["tick"] = -1; bad_tick["checksum"] = Interest.compute_checksum(bad_tick); _err(Interest.validate(bad_tick), "INVALID_CONSTRUCTION_INTEREST_TICK", "negative tick")
	var mismatch := request.duplicate(true); mismatch["construct_id"] = "construct/other"; mismatch["checksum"] = Request.compute_checksum(mismatch); _err(Request.validate(mismatch), "CONSTRUCTION_STREAMING_SNAPSHOT_ID_MISMATCH", "snapshot id")
	var noncanonical := request.duplicate(true); noncanonical["capability_kinds"] = ["POWERED", "LOAD_BEARING_MEMBER"]; noncanonical["checksum"] = Request.compute_checksum(noncanonical); _err(Request.validate(noncanonical), "NON_CANONICAL_CONSTRUCTION_STREAMING_STRING_LIST", "capabilities order")
	var owner_mismatch := F.request("owner-mismatch", 1, F.SERVER_A, F.SERVER_B, Request.OWNER); _err(Request.validate(owner_mismatch), "CONSTRUCTION_STREAMING_OWNER_MODE_SERVER_MISMATCH", "owner mode")
	var read_only := F.request("read-only", 2, F.SERVER_B, F.SERVER_A, Request.READ_ONLY); _ok(Request.validate(read_only), "read only request")

func _test_summary_and_record() -> void:
	var request := F.request("summary")
	var compiled := Summary.compile(request); _ok(compiled, "summary compile")
	var summary: Dictionary = compiled["summary"]; _ok(Summary.validate(summary), "summary validate")
	_assert(int(summary["pending_job_count"]) == 1 and int(summary["pending_operation_count"]) == 1, "summary pending counts")
	_assert(String(summary["structural_state"]) == "STABLE", "summary structural")
	_assert(summary["utility_statuses"].size() == 1 and String(summary["utility_statuses"][0]["status"]) == "BALANCED", "summary utility")
	var tamper: Dictionary = summary.duplicate(true); tamper["mass_kg"] = 999.0; _err(Summary.validate(tamper), "CONSTRUCTION_CONSTRUCT_SUMMARY_CHECKSUM_MISMATCH", "summary tamper")
	var record := Record.create(request, 3); _ok(Record.validate(record), "record")
	_assert(record["effective_level"] == Level.DORMANT, "record dormant")
	_assert(record["pending_job_ids"] == request["pending_job_ids"], "record jobs")
	var updated := Record.with_updates(record, {"effective_level": Level.SUMMARY, "requested_level": Level.SUMMARY, "summary_checksum": String(summary["checksum"]), "generation": 1}); _ok(Record.validate(updated), "record update")
	var bad_level := Record.with_updates(updated, {"effective_level": "INVALID"}); _err(Record.validate(bad_level), "INVALID_CONSTRUCTION_ACTIVITY_RECORD_LEVEL", "record level")

func _test_catch_up_and_budget() -> void:
	var plan_result := CatchUp.compile("construct/streaming/catch", 0, 20, 3, 4); _ok(plan_result, "catch up compile")
	var plan: Dictionary = plan_result["plan"]; _ok(CatchUp.validate(plan), "catch up validate")
	_assert(plan["steps"].size() == 4, "catch up bounded")
	_assert(int(plan["steps"][0]["tick"]) == 3 and int(plan["steps"][3]["tick"]) == 12, "catch up ticks")
	_assert(bool(plan["truncated"]), "catch up truncated")
	var tamper: Dictionary = plan.duplicate(true); tamper["steps"][0]["elapsed_ticks"] = 2; tamper["checksum"] = CatchUp.compute_checksum(tamper); _err(CatchUp.validate(tamper), "NON_CANONICAL_CONSTRUCTION_CATCH_UP_STEP", "catch up continuity")
	var budget := Budget.create(10, {"summary_bytes": 100, "simulation_units": 5, "presentation_bytes": 50}, {"summary_bytes": 80, "simulation_units": 3, "presentation_bytes": 50}, {Level.PRESENTED: ["construct/a"], Level.SIMULATED: ["construct/b"], Level.SUMMARY: [], Level.DORMANT: ["construct/c"]}, ["construct/c"])
	_ok(Budget.validate(budget), "budget")
	_assert(budget["presented_construct_ids"] == ["construct/a"], "budget presented")
	var bad := budget.duplicate(true); bad["evicted_construct_ids"] = ["construct/z", "construct/a"]; bad["checksum"] = Budget.compute_checksum(bad); _err(Budget.validate(bad), "NON_CANONICAL_CONSTRUCTION_STREAMING_BUDGET_IDS", "budget order")

func _test_lod_profile() -> void:
	var full: Dictionary = Lod.compile("construct/lod/full", Level.PRESENTED, 10000000)["profile"]
	_ok(Lod.validate(full), "full lod")
	_assert(full["lod_tier"] == Lod.FULL and bool(full["animation_enabled"]), "full lod flags")
	var simplified: Dictionary = Lod.compile("construct/lod/simple", Level.PRESENTED, 1000)["profile"]
	_ok(Lod.validate(simplified), "simplified lod")
	_assert(simplified["lod_tier"] == Lod.SIMPLIFIED and bool(simplified["collision_enabled"]), "simplified lod flags")
	var impostor: Dictionary = Lod.compile("construct/lod/summary", Level.SUMMARY, 0)["profile"]
	_assert(impostor["lod_tier"] == Lod.IMPOSTOR and not bool(impostor["collision_enabled"]), "impostor lod")
	var none: Dictionary = Lod.compile("construct/lod/dormant", Level.DORMANT, 0)["profile"]
	_assert(none["lod_tier"] == Lod.NONE and float(none["mesh_detail_ratio"]) == 0.0, "none lod")
	var tamper: Dictionary = simplified.duplicate(true); tamper["mesh_detail_ratio"] = 0.5; tamper["checksum"] = Lod.compute_checksum(tamper); _err(Lod.validate(tamper), "NON_CANONICAL_CONSTRUCTION_LOD_PROFILE", "lod tamper")

func _test_state() -> void:
	var request := F.request("state")
	var record := Record.create(request, 0)
	var summary: Dictionary = Summary.compile(request)["summary"]
	var budget := Budget.create(0, {"summary_bytes": 100, "simulation_units": 5, "presentation_bytes": 50}, {"summary_bytes": 0, "simulation_units": 0, "presentation_bytes": 0}, {Level.PRESENTED: [], Level.SIMULATED: [], Level.SUMMARY: [], Level.DORMANT: [String(request["construct_id"])]}, [])
	var state := State.create(0, 1, String(F.policy()["checksum"]), [record], [], [{"tick": 0, "input_checksum": Utils.payload_hash({"input": 0}), "report": budget}]); _ok(State.validate(state), "state")
	_assert(state["records"].size() == 1, "state records")
	var with_summary := State.create(1, 2, String(F.policy()["checksum"]), [Record.with_updates(record, {"requested_level": Level.SUMMARY, "effective_level": Level.SUMMARY, "summary_checksum": String(summary["checksum"]), "generation": 1})], [summary], []); _ok(State.validate(with_summary), "state summary")
	var orphan := State.create(1, 2, String(F.policy()["checksum"]), [], [summary], []); _err(State.validate(orphan), "CONSTRUCTION_STREAMING_SUMMARY_WITHOUT_RECORD", "orphan summary")
	var tamper: Dictionary = state.duplicate(true); tamper["generation"] = 2; _err(State.validate(tamper), "CONSTRUCTION_STREAMING_STATE_CHECKSUM_MISMATCH", "state tamper")

func _ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _err(result: Dictionary, code: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C18 streaming/LOD contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C18 streaming/LOD contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
