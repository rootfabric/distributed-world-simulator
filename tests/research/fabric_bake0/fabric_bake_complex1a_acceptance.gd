extends SceneTree

const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_complex1a_fixture.gd")

var _checks := 0

func _initialize() -> void:
	_test_single_path_causality()
	_test_unrelated_break_is_not_a_shortcut()
	_test_redundant_path()
	_test_two_load_locality()
	_test_deterministic_link_order()
	_test_fail_closed_event_semantics()
	print("FABRIC-BAKE COMPLEX1A Acceptance: PASS (%d assertions) causal_chain=mechanical_support->functional_connectivity->effort_flow->load_power" % _checks)
	quit(0)

func _test_single_path_causality() -> void:
	var subject := Fixture.single_path()
	var before := Fixture.solve(subject)
	_check_solution(before)
	_check(_on(before, "load/lamp-a"))
	_check(absf(_voltage(before, "load/lamp-a") - Fixture.SOURCE_VOLTAGE) <= Fixture.EPSILON)
	_check(absf(_power(before, "load/lamp-a")) > Fixture.POWER_ON_THRESHOLD)

	var broken := Fixture.apply_structural_break(subject, "support/critical-a", "event/critical-a")
	_check(bool(broken.get("success", false)))
	_check(broken["functional_topology_mutations"].size() == 1)
	_check(String(broken["functional_topology_mutations"][0]["bond_id"]) == "wire/path-a")
	var after := Fixture.solve(broken["subject"])
	_check_solution(after)
	_check(not _on(after, "load/lamp-a"))
	_check(absf(_voltage(after, "load/lamp-a")) <= Fixture.EPSILON)
	_check(absf(_current(after, "load/lamp-a")) <= Fixture.EPSILON)
	_check(absf(_power(after, "load/lamp-a")) <= Fixture.EPSILON)
	_check(after["active_functional_bond_ids"].is_empty())

func _test_unrelated_break_is_not_a_shortcut() -> void:
	var subject := Fixture.single_path()
	var before := Fixture.solve(subject)
	_check_solution(before)
	var broken := Fixture.apply_structural_break(subject, "support/unrelated", "event/unrelated")
	_check(bool(broken.get("success", false)))
	_check(broken["functional_topology_mutations"].is_empty())
	var after := Fixture.solve(broken["subject"])
	_check_solution(after)
	_check(_on(after, "load/lamp-a"))
	_check(absf(_voltage(after, "load/lamp-a") - _voltage(before, "load/lamp-a")) <= Fixture.EPSILON)
	_check(absf(_power(after, "load/lamp-a") - _power(before, "load/lamp-a")) <= Fixture.EPSILON)
	_check(after["active_functional_bond_ids"] == ["wire/path-a"])

func _test_redundant_path() -> void:
	var subject := Fixture.redundant_path()
	var intact := Fixture.solve(subject)
	_check_solution(intact)
	_check(_on(intact, "load/lamp-a"))
	_check(intact["active_functional_bond_ids"] == ["wire/path-a", "wire/path-b"])

	var first_break := Fixture.apply_structural_break(subject, "support/path-a", "event/path-a")
	_check(bool(first_break.get("success", false)))
	_check(first_break["functional_topology_mutations"].size() == 1)
	var one_path := Fixture.solve(first_break["subject"])
	_check_solution(one_path)
	_check(_on(one_path, "load/lamp-a"))
	_check(one_path["active_functional_bond_ids"] == ["wire/path-b"])
	_check(absf(_voltage(one_path, "load/lamp-a") - Fixture.SOURCE_VOLTAGE) <= Fixture.EPSILON)

	var second_break := Fixture.apply_structural_break(first_break["subject"], "support/path-b", "event/path-b")
	_check(bool(second_break.get("success", false)))
	_check(second_break["functional_topology_mutations"].size() == 1)
	var no_path := Fixture.solve(second_break["subject"])
	_check_solution(no_path)
	_check(not _on(no_path, "load/lamp-a"))
	_check(no_path["active_functional_bond_ids"].is_empty())

func _test_two_load_locality() -> void:
	var subject := Fixture.two_loads()
	var before := Fixture.solve(subject)
	_check_solution(before)
	_check(_on(before, "load/lamp-a"))
	_check(_on(before, "load/lamp-b"))
	var lamp_b_power := _power(before, "load/lamp-b")

	var broken := Fixture.apply_structural_break(subject, "support/branch-a", "event/branch-a")
	_check(bool(broken.get("success", false)))
	_check(broken["functional_topology_mutations"].size() == 1)
	_check(String(broken["functional_topology_mutations"][0]["bond_id"]) == "wire/branch-a")
	var after := Fixture.solve(broken["subject"])
	_check_solution(after)
	_check(not _on(after, "load/lamp-a"))
	_check(_on(after, "load/lamp-b"))
	_check(absf(_power(after, "load/lamp-b") - lamp_b_power) <= Fixture.EPSILON)
	_check(after["active_functional_bond_ids"] == ["wire/branch-b"])

func _test_deterministic_link_order() -> void:
	for factory_name in ["single", "redundant", "two_loads"]:
		var forward: Dictionary
		var reverse: Dictionary
		match factory_name:
			"single":
				forward = Fixture.single_path(false)
				reverse = Fixture.single_path(true)
			"redundant":
				forward = Fixture.redundant_path(false)
				reverse = Fixture.redundant_path(true)
			_:
				forward = Fixture.two_loads(false)
				reverse = Fixture.two_loads(true)
		var a := Fixture.solve(forward)
		var b := Fixture.solve(reverse)
		_check_solution(a)
		_check_solution(b)
		_check(String(a["network_hash"]) == String(b["network_hash"]))
		_check(a["loads"] == b["loads"])

func _test_fail_closed_event_semantics() -> void:
	var subject := Fixture.single_path()
	var first := Fixture.apply_structural_break(subject, "support/critical-a", "event/exactly-once")
	_check(bool(first.get("success", false)))
	var duplicate := Fixture.apply_structural_break(first["subject"], "support/unrelated", "event/exactly-once")
	_check(not bool(duplicate.get("success", false)))
	_check(String(duplicate.get("error_code", "")) == "COMPLEX1A_STRUCTURAL_EVENT_ALREADY_APPLIED")
	var missing := Fixture.apply_structural_break(subject, "support/not-present", "event/missing")
	_check(not bool(missing.get("success", false)))
	_check(String(missing.get("error_code", "")) == "COMPLEX1A_STRUCTURAL_BOND_NOT_FOUND")

func _check_solution(result: Dictionary) -> void:
	_check(bool(result.get("success", false)))
	_check(float(result["max_balance_residual"]) <= Fixture.EPSILON)
	_check(float(result["max_power_residual"]) <= Fixture.EPSILON)

func _on(result: Dictionary, load_id: String) -> bool:
	return bool(result["loads"][load_id]["on"])

func _voltage(result: Dictionary, load_id: String) -> float:
	return float(result["loads"][load_id]["voltage"])

func _current(result: Dictionary, load_id: String) -> float:
	return float(result["loads"][load_id]["current"])

func _power(result: Dictionary, load_id: String) -> float:
	return float(result["loads"][load_id]["absorbed_power"])

func _check(condition: bool) -> void:
	assert(condition)
	_checks += 1
