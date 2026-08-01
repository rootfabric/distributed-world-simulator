extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Fixture = preload("res://tests/construction/fixtures/c14_structural_integrity_fixture.gd")
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const StructuralProcessScript = preload("res://scripts/construction/structural/construction_structural_process.gd")
const DamageProcessScript = preload("res://scripts/construction/damage/construction_damage_process.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ProfileStoreScript = preload("res://scripts/construction/structural/construction_structural_profile_store.gd")
const SummaryScript = preload("res://scripts/construction/structural/construction_structural_summary.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_stable_evaluation_is_read_only()
	_test_progressive_collapse_split_and_repair()
	_test_retry_replay_and_atomicity()
	_test_multiple_construct_isolation_and_summary_cache()
	_finish()

func _runtime(instance_key: String) -> Dictionary:
	var snapshot := Fixture.snapshot(instance_key)
	var adapter = AdapterScript.new(); _assert_ok(adapter.setup(Fixture.items(instance_key, snapshot), [snapshot]), "Adapter setup failed")
	var process = StructuralProcessScript.new(); _assert_ok(process.setup(adapter), "Structural process setup failed")
	return {"snapshot": snapshot, "adapter": adapter, "process": process}

func _test_stable_evaluation_is_read_only() -> void:
	var rt := _runtime("stable-integration")
	var before: Dictionary = rt.adapter.export_state()
	var load_case := Fixture.load_case("stable-integration", rt.snapshot)
	var result: Dictionary = rt.process.evaluate(load_case); _assert_ok(result, "Stable process evaluation failed")
	_assert(String(result["profile"]["structural_state"]) == "STABLE", "Stable process returned non-stable profile")
	_assert(int(rt.adapter.get_generation()) == 0, "Read-only evaluation advanced authoritative generation")
	_assert(UtilsScript.canonical_json(rt.adapter.export_state()) == UtilsScript.canonical_json(before), "Read-only structural evaluation mutated authority")
	var applied: Dictionary = rt.process.apply_cascade("plan/c14/stable", "operation/c14/stable", "cascade/c14/stable", load_case); _assert_ok(applied, "Stable cascade process failed")
	_assert(bool(applied["stable"]), "Stable cascade process marked damage")
	_assert(int(rt.adapter.get_generation()) == 0, "Stable cascade advanced generation")
	_assert(rt.adapter.get_operation_result("operation/c14/stable").is_empty(), "Stable no-op wrote operation ledger")

func _test_progressive_collapse_split_and_repair() -> void:
	var rt := _runtime("collapse")
	var load_case := Fixture.load_case("collapse", rt.snapshot, true)
	var result: Dictionary = rt.process.apply_cascade("plan/c14/collapse", "operation/c14/collapse", "cascade/c14/collapse", load_case)
	_assert_ok(result, "Structural cascade application failed")
	_assert(not bool(result["stable"]), "Overloaded structure marked stable")
	_assert(int(rt.adapter.get_generation()) == 1, "Structural cascade did not commit exactly once")
	var plan: Dictionary = result["cascade_plan"]
	_assert(plan["failed_bond_ids"].size() == 2, "Structural cascade failure count mismatch")
	_assert(plan["step_profiles"].size() == 3, "Structural cascade step count mismatch")
	var damage: Dictionary = result["damage_result"]
	_assert(damage["split_construct_ids"] == ["construct/structural/collapse/structural-split-01"], "Structural cascade split ID mismatch")
	_assert(damage["salvage_item_ids"].is_empty(), "Two-part detached component was salvaged instead of split")
	var source: Dictionary = rt.adapter.get_construct_snapshot("construct/structural/collapse")
	var child: Dictionary = rt.adapter.get_construct_snapshot("construct/structural/collapse/structural-split-01")
	_assert(source["parts"].size() == 3, "Source construct retained wrong part count")
	_assert(child["parts"].size() == 2, "Split construct has wrong part count")
	_assert(String(source["build_state"]) == "DAMAGED" and String(child["build_state"]) == "DAMAGED", "Structural split build states mismatch")
	_assert(_part_ids(source) == ["part/structural/collapse/brace", "part/structural/collapse/column", "part/structural/collapse/foundation"], "Source retained component mismatch")
	_assert(_part_ids(child) == ["part/structural/collapse/payload", "part/structural/collapse/tool"], "Child detached component mismatch")
	_assert(_bond_ids(source) == ["bond/structural/collapse/column-brace", "bond/structural/collapse/foundation-column"], "Source live bonds mismatch")
	_assert(_bond_ids(child) == ["bond/structural/collapse/payload-tool"], "Child live bonds mismatch")
	var payload: Dictionary = rt.adapter.get_item_projection("item/structural/collapse/payload")
	var tool: Dictionary = rt.adapter.get_item_projection("item/structural/collapse/tool")
	_assert(String(payload["relation"]["assembly_id"]) == String(child["construct_id"]), "Payload was not rebound to structural child")
	_assert(String(tool["relation"]["assembly_id"]) == String(child["construct_id"]), "Tool was not rebound to structural child")
	_assert(String(payload["relation"]["parent_item_id"]) == String(child["root_item_instance_id"]), "Payload child root mismatch")
	var split_root: Dictionary = rt.adapter.get_item_projection(String(child["root_item_instance_id"]))
	_assert(not split_root.is_empty(), "Structural split root item missing")
	_assert(String(split_root["components"]["construction_root"]["construct_id"]) == String(child["construct_id"]), "Structural split root component mismatch")
	var terminal: Dictionary = rt.adapter.get_operation_result("operation/c14/collapse")
	_assert(String(terminal["status"]) == "SUCCEEDED", "Structural cascade terminal result missing")
	var repair_plan: Dictionary = damage["repair_plan"]
	var damage_process = DamageProcessScript.new(); _assert_ok(damage_process.setup(rt.adapter), "Repair process setup failed")
	var repaired: Dictionary = damage_process.apply_repair("plan/c14/collapse/repair", "operation/c14/collapse/repair", repair_plan)
	_assert_ok(repaired, "Structural repair failed")
	_assert(int(rt.adapter.get_generation()) == 2, "Structural repair did not commit exactly once")
	var restored: Dictionary = rt.adapter.get_construct_snapshot("construct/structural/collapse")
	_assert(restored["parts"].size() == 5 and restored["bonds"].size() == 5, "Structural repair did not restore topology")
	_assert(String(restored["build_state"]) == "OPERATIONAL", "Structural repair did not restore operational state")
	_assert(rt.adapter.get_construct_snapshot("construct/structural/collapse/structural-split-01").is_empty(), "Structural repair left child construct")
	_assert(rt.adapter.get_item_projection(String(child["root_item_instance_id"])).is_empty(), "Structural repair left child root item")
	for part in restored["parts"]:
		var item: Dictionary = rt.adapter.get_item_projection(String(part["item_instance_id"]))
		_assert(String(item["relation"]["assembly_id"]) == "construct/structural/collapse", "Repaired structural item not attached to source")
	_assert(UtilsScript.canonical_json(restored["parts"]) == UtilsScript.canonical_json(rt.snapshot["parts"]), "Structural repair changed original part identities")
	_assert(UtilsScript.canonical_json(restored["bonds"]) == UtilsScript.canonical_json(rt.snapshot["bonds"]), "Structural repair changed original bond definitions")

func _test_retry_replay_and_atomicity() -> void:
	var rt := _runtime("retry")
	var load_case := Fixture.load_case("retry", rt.snapshot, true)
	var before: Dictionary = rt.adapter.export_state()
	var failed: Dictionary = rt.process.apply_cascade("plan/c14/retry", "operation/c14/retry", "cascade/c14/retry", load_case, "BEFORE_COMMIT")
	_assert(not bool(failed.get("success", false)), "Injected structural failure unexpectedly succeeded")
	_assert(String(failed.get("status", "")) == "RETRYABLE", "Injected structural failure not retryable")
	_assert(int(rt.adapter.get_generation()) == 0, "Injected structural failure changed generation")
	_assert(UtilsScript.canonical_json(rt.adapter.export_state()) == UtilsScript.canonical_json(before), "Injected structural failure mutated authoritative state")
	var success: Dictionary = rt.process.apply_cascade("plan/c14/retry", "operation/c14/retry", "cascade/c14/retry", load_case)
	_assert_ok(success, "Structural retry failed")
	_assert(int(rt.adapter.get_generation()) == 1, "Structural retry generation mismatch")
	var state_after: Dictionary = rt.adapter.export_state()
	var replay: Dictionary = rt.process.apply_cascade("plan/c14/retry", "operation/c14/retry", "cascade/c14/retry", load_case)
	_assert_ok(replay, "Structural exact replay failed")
	_assert(bool(replay.get("replay", false)), "Structural replay not marked replay")
	_assert(int(rt.adapter.get_generation()) == 1, "Structural exact replay advanced generation")
	_assert(UtilsScript.canonical_json(rt.adapter.export_state()) == UtilsScript.canonical_json(state_after), "Structural replay changed authoritative state")
	var conflict_case: Dictionary = load_case.duplicate(true)
	conflict_case["external_part_loads_n"] = {"part/structural/retry/payload": 900.0}
	conflict_case["checksum"] = preload("res://scripts/construction/structural/construction_structural_load_case.gd").compute_checksum(conflict_case)
	var conflict: Dictionary = rt.process.apply_cascade("plan/c14/retry", "operation/c14/retry", "cascade/c14/retry", conflict_case)
	_assert(not bool(conflict.get("success", false)) and String(conflict.get("error_code", "")) == "CONSTRUCTION_STRUCTURAL_OPERATION_REPLAY_CONFLICT", "Structural process accepted conflicting replay payload")
	_assert(int(rt.adapter.get_generation()) == 1, "Conflicting structural replay advanced generation")
	var restored = AdapterScript.new(); _assert_ok(restored.setup(), "Restored adapter setup failed")
	_assert_ok(restored.load_state(state_after), "Structural authoritative state load failed")
	var restored_process = StructuralProcessScript.new(); _assert_ok(restored_process.setup(restored), "Restored structural process setup failed")
	var restart_replay: Dictionary = restored_process.apply_cascade("plan/c14/retry", "operation/c14/retry", "cascade/c14/retry", load_case)
	_assert_ok(restart_replay, "Structural replay after restart failed")
	_assert(bool(restart_replay.get("replay", false)), "Restart replay not marked replay")
	_assert(int(restored.get_generation()) == 1, "Restart replay advanced generation")

func _test_multiple_construct_isolation_and_summary_cache() -> void:
	var snapshot_a: Dictionary = Fixture.snapshot("isolation-a")
	var snapshot_b: Dictionary = Fixture.snapshot("isolation-b")
	var adapter = AdapterScript.new()
	var items: Array = Fixture.items("isolation-a", snapshot_a); items.append_array(Fixture.items("isolation-b", snapshot_b))
	_assert_ok(adapter.setup(items, [snapshot_a, snapshot_b]), "Multi-construct adapter setup failed")
	var process = StructuralProcessScript.new(); _assert_ok(process.setup(adapter), "Multi-construct process setup failed")
	var result: Dictionary = process.apply_cascade("plan/c14/isolation-a", "operation/c14/isolation-a", "cascade/c14/isolation-a", Fixture.load_case("isolation-a", snapshot_a, true))
	_assert_ok(result, "Isolation structural cascade failed")
	_assert(int(adapter.get_generation()) == 1, "Isolation cascade generation mismatch")
	_assert(adapter.get_construct_snapshot("construct/structural/isolation-b")["parts"].size() == 5, "Independent construct topology changed")
	_assert(String(adapter.get_item_projection("item/structural/isolation-b/payload")["relation"]["assembly_id"]) == "construct/structural/isolation-b", "Independent construct item moved")
	var profile_result: Dictionary = process.evaluate(Fixture.load_case("isolation-b", snapshot_b)); _assert_ok(profile_result, "Independent profile evaluation failed")
	var store = ProfileStoreScript.new(); _assert_ok(store.publish(profile_result["profile"]), "Summary cache profile publish failed")
	var summary_result: Dictionary = SummaryScript.compile(store.get_profile("construct/structural/isolation-b", "load-case/structural/isolation-b/gravity")); _assert_ok(summary_result, "Dormant structural summary compile failed")
	var summary: Dictionary = summary_result["summary"]
	_assert(String(summary["structural_state"]) == "STABLE", "Dormant summary state mismatch")
	_assert(int(summary["part_count"]) == 5 and int(summary["load_path_count"]) == 4, "Dormant summary lost structural counts")
	_assert(String(summary["checksum"]).length() == 64, "Dormant summary checksum missing")

func _part_ids(snapshot: Dictionary) -> Array:
	var output: Array = []
	for part in snapshot["parts"]:
		output.append(String(part["part_id"]))
	output.sort()
	return output
func _bond_ids(snapshot: Dictionary) -> Array:
	var output: Array = []
	for bond in snapshot["bonds"]:
		output.append(String(bond["bond_id"]))
	output.sort()
	return output
func _assert_ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C14 structural integrity integration: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C14 structural integrity integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
