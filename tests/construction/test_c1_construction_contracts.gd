extends SceneTree

const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const CompilerScript = preload("res://scripts/construction/compilation/construction_capability_compiler.gd")

var failures: Array[String] = []
var assertions: int = 0

func _init() -> void:
	_test_part_contract()
	_test_bond_contract()
	_test_capability_compiler()
	_test_snapshot_contract()
	_finish()

func _test_part_contract() -> void:
	var part: Dictionary = _part("part/table/top", "item/table/top", "PANEL", "surface", 12.0, [0.0, 0.75, 0.0])
	_assert_ok(PartScript.validate(part), "Valid part rejected")
	var extra: Dictionary = part.duplicate(true)
	extra["extra"] = true
	_assert_fail(PartScript.validate(extra), "Unexpected part field accepted")
	var runtime: Dictionary = part.duplicate(true)
	runtime["metadata"] = {"node": RefCounted.new()}
	_assert_fail(PartScript.validate(runtime), "Runtime object accepted in part metadata")
	var bad_mass: Dictionary = part.duplicate(true)
	bad_mass["mass_kg"] = 0.0
	_assert_fail(PartScript.validate(bad_mass), "Zero part mass accepted")
	var bad_position: Dictionary = part.duplicate(true)
	bad_position["local_position_m"] = [0.0, NAN, 0.0]
	_assert_fail(PartScript.validate(bad_position), "Non-finite part position accepted")

func _test_bond_contract() -> void:
	var bond: Dictionary = _bond("bond/table/leg-a", "part/table/top", "part/table/leg-a")
	_assert_ok(BondScript.validate(bond), "Valid bond rejected")
	var self_bond: Dictionary = bond.duplicate(true)
	self_bond["part_b_id"] = self_bond["part_a_id"]
	_assert_fail(BondScript.validate(self_bond), "Self bond accepted")
	var bad_state: Dictionary = bond.duplicate(true)
	bad_state["state"] = "CRACKED"
	_assert_fail(BondScript.validate(bad_state), "Unknown bond state accepted")
	var bad_strength: Dictionary = bond.duplicate(true)
	bad_strength["strength_n"] = -1.0
	_assert_fail(BondScript.validate(bad_strength), "Negative bond strength accepted")

func _test_capability_compiler() -> void:
	var fixture: Dictionary = _table_fixture()
	var result: Dictionary = CompilerScript.compile(fixture["parts"], fixture["bonds"])
	_assert_ok(result, "Table capability compilation failed")
	var compiled: Dictionary = result.get("compiled", {})
	_assert(bool(compiled.get("connected", false)), "Table must compile as connected")
	_assert(bool(compiled.get("stable", false)), "Table must compile as stable")
	_assert(int(compiled.get("rigid_island_count", 0)) == 1, "Table must have one rigid island")
	_assert(compiled.get("capabilities", []) == ["PLACE_ITEMS", "SUPPORT_SURFACE", "WORK_SURFACE"], "Table capabilities are wrong")
	_assert(is_equal_approx(float(compiled.get("total_mass_kg", 0.0)), 20.0), "Table mass is wrong")
	var damaged_bonds: Array = fixture["bonds"].duplicate(true)
	damaged_bonds[0]["state"] = "BROKEN"
	var damaged: Dictionary = CompilerScript.compile(fixture["parts"], damaged_bonds)
	_assert_ok(damaged, "Damaged table compilation failed")
	_assert(not bool(damaged["compiled"].get("connected", true)), "Broken leg bond must disconnect the part")
	_assert(int(damaged["compiled"].get("rigid_island_count", 0)) == 2, "Broken leg must create a second rigid island")
	_assert(damaged["compiled"].get("capabilities", []).is_empty(), "Damaged disconnected table retained surface capabilities")
	var unknown_bond: Array = fixture["bonds"].duplicate(true)
	unknown_bond[0]["part_b_id"] = "part/table/missing"
	_assert_error(CompilerScript.compile(fixture["parts"], unknown_bond), "BOND_REFERENCES_UNKNOWN_PART", "Unknown bond endpoint accepted")

func _test_snapshot_contract() -> void:
	var fixture: Dictionary = _table_fixture()
	var compiled_result: Dictionary = CompilerScript.compile(fixture["parts"], fixture["bonds"])
	var snapshot: Dictionary = SnapshotScript.create("construct/table/demo", "item/construct/table-demo", 9, "OPERATIONAL", fixture["parts"], fixture["bonds"], compiled_result["compiled"])
	_assert_ok(SnapshotScript.validate(snapshot), "Valid construct snapshot rejected")
	_assert(String(snapshot.get("checksum", "")).length() == 64, "Construct checksum is not SHA-256")
	var encoded: String = JSON.stringify(snapshot, "", true, true)
	var decoded = JSON.parse_string(encoded)
	_assert(decoded is Dictionary, "Construct snapshot did not survive JSON")
	_assert_ok(SnapshotScript.validate(decoded), "JSON-decoded snapshot rejected")
	var changed: Dictionary = snapshot.duplicate(true)
	changed["parts"][0]["mass_kg"] = 999.0
	_assert_error(SnapshotScript.validate(changed), "CONSTRUCT_SNAPSHOT_CHECKSUM_MISMATCH", "Mutated snapshot checksum accepted")
	var unsorted: Dictionary = snapshot.duplicate(true)
	unsorted["parts"].reverse()
	unsorted["checksum"] = SnapshotScript.compute_checksum(unsorted)
	_assert_error(SnapshotScript.validate(unsorted), "PARTS_NOT_CANONICALLY_SORTED", "Unsorted snapshot parts accepted")

func _table_fixture() -> Dictionary:
	var parts: Array = [
		_part("part/table/top", "item/table/top", "PANEL", "surface", 12.0, [0.0, 0.75, 0.0]),
		_part("part/table/leg-a", "item/table/leg-a", "BEAM", "support", 2.0, [-0.5, 0.375, -0.3]),
		_part("part/table/leg-b", "item/table/leg-b", "BEAM", "support", 2.0, [0.5, 0.375, -0.3]),
		_part("part/table/leg-c", "item/table/leg-c", "BEAM", "support", 2.0, [0.5, 0.375, 0.3]),
		_part("part/table/leg-d", "item/table/leg-d", "BEAM", "support", 2.0, [-0.5, 0.375, 0.3]),
	]
	var bonds: Array = [
		_bond("bond/table/leg-a", "part/table/top", "part/table/leg-a"),
		_bond("bond/table/leg-b", "part/table/top", "part/table/leg-b"),
		_bond("bond/table/leg-c", "part/table/top", "part/table/leg-c"),
		_bond("bond/table/leg-d", "part/table/top", "part/table/leg-d"),
	]
	return {"parts": parts, "bonds": bonds}

func _part(part_id: String, item_id: String, kind: String, role: String, mass: float, position: Array) -> Dictionary:
	return PartScript.create(part_id, item_id, kind, role, mass, position)

func _bond(bond_id: String, part_a: String, part_b: String) -> Dictionary:
	return BondScript.create(bond_id, part_a, part_b, "BOLT", 2500.0)

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)

func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C1 construction contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C1 construction contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
