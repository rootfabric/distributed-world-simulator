extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const FunctionalPlane = preload("res://scripts/research/fabric_bake0/complex4_real_world_machine_projection_v1.gd")
const Fixture = preload("res://tests/research/fabric1/complex4_real_world_machine_fixture_v1.gd")

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	_run()
	_finish()

func _run() -> void:
	var initial := Fixture.initial_snapshot()
	_assert_ok(Snapshot.validate(initial), "initial machine snapshot invalid")
	_assert(initial.parts.size() == Fixture.PART_COUNT, "machine part count wrong")
	_assert(initial.bonds.size() == Fixture.PART_COUNT + 3, "machine bond count wrong")
	var first := FunctionalPlane.solve(initial)
	_assert_ok(first, "initial functional projection failed")
	_assert(first.details.machine_state == "ON", "machine did not start ON")
	_assert(first.details.active_power_link_ids == [Fixture.POWER_A, Fixture.POWER_B], "initial redundant paths wrong")
	_assert(first.details.disabled_power_link_ids.is_empty(), "initial path unexpectedly disabled")
	_assert(absf(float(first.details.load_absorbed_power)) >= 1.0, "initial load has no power")
	_assert(float(first.details.max_balance_residual) <= 1.0e-9, "initial balance residual too large")
	_assert(float(first.details.max_power_residual) <= 1.0e-9, "initial power residual too large")
	var repeat := FunctionalPlane.solve(initial)
	_assert_ok(repeat, "repeat projection failed")
	_assert(String(first.details.projection_hash) == String(repeat.details.projection_hash), "projection not deterministic")

	var after_a := Fixture.successor_with_broken_support(initial, Fixture.SUPPORT_A)
	_assert_ok(Snapshot.validate(after_a), "primary support successor invalid")
	var projected_a := FunctionalPlane.solve(after_a)
	_assert_ok(projected_a, "primary support projection failed")
	_assert(projected_a.details.machine_state == "ON", "backup path did not preserve machine function")
	_assert(projected_a.details.active_power_link_ids == [Fixture.POWER_B], "primary path did not deactivate")
	_assert(projected_a.details.disabled_power_link_ids == [Fixture.POWER_A], "primary disabled set wrong")
	_assert(String(Fixture.bond(after_a, Fixture.POWER_A).state) == "INTACT", "derived functional failure mutated canonical power bond")

	var after_b := Fixture.successor_with_broken_support(after_a, Fixture.SUPPORT_B)
	_assert_ok(Snapshot.validate(after_b), "backup support successor invalid")
	var projected_b := FunctionalPlane.solve(after_b)
	_assert_ok(projected_b, "backup support projection failed")
	_assert(projected_b.details.machine_state == "OFF", "machine did not switch OFF after both supports failed")
	_assert(projected_b.details.active_power_link_ids.is_empty(), "power path remained active after both support failures")
	_assert(projected_b.details.disabled_power_link_ids == [Fixture.POWER_A, Fixture.POWER_B], "disabled path set wrong")
	_assert(absf(float(projected_b.details.load_absorbed_power)) < 1.0, "OFF machine still consumes powered load")
	_assert(String(Fixture.bond(after_b, Fixture.POWER_A).state) == "INTACT" and String(Fixture.bond(after_b, Fixture.POWER_B).state) == "INTACT", "functional projection wrote canonical power topology")

	var invalid := initial.duplicate(true)
	var bonds: Array = invalid.bonds.duplicate(true)
	for index in range(bonds.size()):
		if String(bonds[index].bond_id) == Fixture.POWER_A:
			var changed: Dictionary = bonds[index].duplicate(true)
			changed.metadata = {"support_bond_ids": ["bond/complex4/missing-support"], "path": "primary"}
			bonds[index] = changed
	invalid = Snapshot.create(initial.construct_id, initial.root_item_instance_id, initial.state_revision, initial.build_state, initial.parts, bonds, initial.compiled_facets)
	_assert_ok(Snapshot.validate(invalid), "adversarial canonical snapshot invalid before projection")
	_assert_error(FunctionalPlane.solve(invalid), "COMPLEX4_FUNCTIONAL_SUPPORT_UNKNOWN", "unknown functional support did not fail closed")

	var hash := Utils.canonical_hash({
		"initial": first.details.projection_hash,
		"after_primary": projected_a.details.projection_hash,
		"after_backup": projected_b.details.projection_hash,
		"states": [first.details.machine_state, projected_a.details.machine_state, projected_b.details.machine_state],
		"links": [first.details.active_power_link_ids, projected_a.details.active_power_link_ids, projected_b.details.active_power_link_ids],
	})
	print("COMPLEX4_A_INITIAL_POWER=" + str(first.details.load_absorbed_power))
	print("COMPLEX4_A_AFTER_PRIMARY_POWER=" + str(projected_a.details.load_absorbed_power))
	print("COMPLEX4_A_AFTER_BACKUP_POWER=" + str(projected_b.details.load_absorbed_power))
	print("COMPLEX4_A_HASH=%s" % hash)

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
		print("FABRIC COMPLEX4-A Canonical Machine: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FABRIC COMPLEX4-A Canonical Machine: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
