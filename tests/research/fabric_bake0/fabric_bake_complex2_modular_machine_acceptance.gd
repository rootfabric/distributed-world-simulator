extends SceneTree

const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const Complex1A = preload("res://tests/research/fabric_bake0/fabric_bake_complex1a_fixture.gd")

var _checks := 0
var _failures: Array[String] = []
var _experiment_hash := ""

func _initialize() -> void:
	var subject := Fixture.build()
	_check(bool(subject.get("success", false)), "COMPLEX2 fixture builds")
	if not bool(subject.get("success", false)):
		_finish()
		return
	_test_composition(subject)
	_test_experiment()
	_finish()

func _test_composition(subject: Dictionary) -> void:
	_check(String(subject["schema"]) == Fixture.SCHEMA, "schema exact")
	_check(subject["parts"].size() == Fixture.PART_COUNT, "2000 canonical parts")
	_check(subject["modules"].size() == Fixture.MODULE_COUNT, "25 structural modules")
	_check(subject["moving_subsystems"].size() == Fixture.MOVING_SUBSYSTEM_COUNT, "6 moving subsystems")
	_check(subject["contact_zones"].size() == Fixture.CONTACT_ZONE_COUNT, "3 active contact zones")
	_check(subject["functional_subject"]["functional_links"].size() == Fixture.FUNCTIONAL_PATH_COUNT, "2 functional paths")

	var part_ids: Dictionary = {}
	var parts_by_module: Dictionary = {}
	for part in subject["parts"]:
		var part_id := String(part["part_id"])
		var module_id := String(part["module_id"])
		_check(not part_ids.has(part_id), "canonical part identity unique")
		part_ids[part_id] = true
		parts_by_module[module_id] = int(parts_by_module.get(module_id, 0)) + 1
	_check(part_ids.size() == Fixture.PART_COUNT, "part identity set covers 2000")
	_check(parts_by_module.size() == Fixture.MODULE_COUNT, "all modules own parts")
	for module in subject["modules"]:
		_check(int(parts_by_module.get(String(module["module_id"]), 0)) == Fixture.PARTS_PER_MODULE, "module owns exactly 80 parts")

	var registry: Dictionary = subject["registry"]
	_check(bool(Registry.validate(registry).get("success", false)), "closed BRIDGE-2 registry validates")
	_check(registry["regions"].size() == 5, "BRIDGE-2 R1 remains exactly five execution regions")
	var kinds: Array = []
	for region in registry["regions"]:
		kinds.append(String(region["representation_kind"]))
	kinds.sort()
	var expected := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
	expected.sort()
	_check(kinds == expected, "all five representation kinds present exactly once")

	var module_regions: Dictionary = {}
	for module in subject["modules"]:
		var region_id := String(module["region_id"])
		module_regions[region_id] = int(module_regions.get(region_id, 0)) + 1
	_check(module_regions.size() == 5, "25 logical modules span all five execution partitions")
	for region_id in module_regions.keys():
		_check(int(module_regions[region_id]) > 0, "execution partition owns non-empty logical module set")

	var support_ids: Dictionary = {}
	for support in subject["supports"]:
		var support_id := String(support["support_id"])
		_check(not support_ids.has(support_id), "support identity unique")
		support_ids[support_id] = true
	_check(support_ids.has(Fixture.DETACH_SUPPORT_ID), "detach support exists")
	_check(support_ids.has(Fixture.SECOND_SUPPORT_ID), "second functional support exists")

func _test_experiment() -> void:
	var result := Fixture.run_experiment()
	_check(bool(result.get("success", false)), "COMPLEX2 executable sequence completes")
	if not bool(result.get("success", false)):
		_failures.append("experiment details=%s" % str(result))
		return

	_check(int(result["part_count"]) == 2000, "experiment retains 2000 parts")
	_check(int(result["module_count"]) == 25, "experiment retains 25 modules")
	_check(int(result["moving_subsystem_count"]) == 6, "experiment has 6 movers")
	_check(int(result["contact_zone_count"]) == 3, "experiment has 3 contact zones")
	_check(int(result["functional_path_count"]) == 2, "experiment has 2 functional paths")
	_check(int(result["module_revision"]) == 102, "two canonical module events advance revision twice")
	var machine_events: Array = Array(result["applied_event_ids"]).duplicate()
	var expected_machine_events := [Fixture.EVENT_DETACH, Fixture.EVENT_SECOND]
	expected_machine_events.sort()
	_check(machine_events == expected_machine_events, "two module events committed exactly once")

	_check(Array(result["detached_component"]) == [Fixture.DETACH_MODULE_ID], "first event detaches exactly one end module")
	_check(Array(result["module_components_after_detach"]).size() == 2, "detach produces two module components")
	_check(Array(result["detach_affected_regions"]) == [Fixture.REGION_HYBRID], "detach invalidates only HYBRID region")
	_check(String(result["detach_stale_error"]) == "BRIDGE2_MIXED_STEP_BLOCKED", "detach stale region blocks mixed execution")
	_check(float(result["detach_rebuild_handoff_error"]) == 0.0, "detach rebuild state handoff exact")

	_check(Array(result["second_affected_regions"]) == [Fixture.REGION_DYNAMIC], "second event invalidates only DYNAMIC region")
	_check(String(result["second_stale_error"]) == "BRIDGE2_MIXED_STEP_BLOCKED", "second stale region blocks mixed execution")
	_check(float(result["second_rebuild_handoff_error"]) == 0.0, "second rebuild state handoff exact")

	_check(float(result["representation_swap_handoff_error"]) == 0.0, "FULL/HYBRID swap handoff exact")
	_check(int(result["representation_event_ledger_size"]) == 1, "representation event ledger exactly once")
	var kinds: Array = Array(result["representation_kinds_after_swap"]).duplicate()
	kinds.sort()
	var expected := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
	expected.sort()
	_check(kinds == expected, "swap preserves exact five-kind set")

	_check(Array(result["contact_external_flow_keys"]) == [Fixture.REGION_CONTACT], "local contact enters only CONTACT region")
	_check(float(result["contact_state_delta"]) > 1.0e-9, "contact produces measurable state change")
	_check(float(result["mixed_full_max_state_delta"]) <= 1.0e-12, "whole mixed sequence equals FULL reference")

	var before: Dictionary = result["power_before"]
	var after_detach: Dictionary = result["power_after_detach"]
	var after_second: Dictionary = result["power_after_second"]
	_check(bool(before["load_a"]["on"]) and bool(before["load_b"]["on"]), "both functional loads start ON")
	_check(not bool(after_detach["load_a"]["on"]) and bool(after_detach["load_b"]["on"]), "detach turns only dependent load A OFF")
	_check(not bool(after_second["load_a"]["on"]) and not bool(after_second["load_b"]["on"]), "second event turns remaining load B OFF")
	_check(Array(after_detach["active_functional_bond_ids"]) == ["wire/branch-b"], "only branch B remains after detach")
	_check(Array(after_second["active_functional_bond_ids"]).is_empty(), "no functional branch remains after second event")

	_check(Array(result["detach_functional_mutations"]).size() == 1, "detach causes one functional mutation")
	_check(String(result["detach_functional_mutations"][0]["reason"]) == "SUPPORT_TOPOLOGY_LOST", "detach consequence derives from support loss")
	_check(String(result["detach_functional_mutations"][0]["support_bond_id"]) == Fixture.DETACH_SUPPORT_ID, "detach consequence binds exact support")
	_check(Array(result["second_functional_mutations"]).size() == 1, "second event causes one functional mutation")
	_check(String(result["second_functional_mutations"][0]["support_bond_id"]) == Fixture.SECOND_SUPPORT_ID, "second consequence binds exact support")

	for power_state in [before, after_detach, after_second]:
		_check(float(power_state["max_balance_residual"]) <= Complex1A.EPSILON, "functional balance residual bounded")
		_check(float(power_state["max_power_residual"]) <= Complex1A.EPSILON, "functional power residual bounded")

	_experiment_hash = String(result["experiment_hash"])
	_check(not String(result["machine_hash"]).is_empty(), "machine hash present")
	_check(not String(result["final_state_hash"]).is_empty(), "final state hash present")
	_check(not _experiment_hash.is_empty(), "experiment hash present")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("COMPLEX2_EXPERIMENT_HASH=%s" % _experiment_hash)
		print("FABRIC COMPLEX2 Modular Machine Acceptance: PASS (%d assertions) parts=2000 modules=25 movers=6 contacts=3 paths=2 second_event=accepted mixed=FULL_REFERENCE" % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr("COMPLEX2 FAILURE: %s" % failure)
	print("FABRIC COMPLEX2 Modular Machine Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)
