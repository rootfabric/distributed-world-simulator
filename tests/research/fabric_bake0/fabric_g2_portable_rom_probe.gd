extends SceneTree

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

const ORBIT_LIMIT := 65536

func _orbit_rounds(start_value: float) -> Dictionary:
	var current := start_value
	var seen := {}
	for round_index in range(ORBIT_LIMIT):
		var encoded := JSON.stringify(current, "", true, true)
		var parsed = JSON.parse_string(encoded)
		if parsed == null and encoded != "null":
			return {"kind": "PARSE_FAIL", "rounds": round_index + 1, "value": encoded}
		var next_value := float(parsed)
		if next_value == current:
			return {"kind": "FIXED", "rounds": round_index + 1, "value": encoded}
		var next_encoded := JSON.stringify(next_value, "", true, true)
		if seen.has(next_encoded):
			return {"kind": "CYCLE", "rounds": round_index + 1, "value": next_encoded}
		seen[encoded] = true
		current = next_value
	return {"kind": "LIMIT", "rounds": ORBIT_LIMIT, "value": JSON.stringify(current, "", true, true)}

func _report_orbit(label: String, value: float) -> void:
	var result := _orbit_rounds(value)
	print("PROBE_ORBIT_", label, "_KIND=", result["kind"], " rounds=", result["rounds"], " start=", JSON.stringify(value, "", true, true), " final=", result["value"])

func _init() -> void:
	var fixture := Fixture.build("ZERO")
	var full := FullCompiler.compile(fixture["request"])
	print("PROBE_FULL_SUCCESS=", bool(full.get("success", false)))
	if not bool(full.get("success", false)):
		quit(2)
	var validated := FullModel.validate(full["model"])
	print("PROBE_FULL_VALIDATE_SUCCESS=", bool(validated.get("success", false)))
	var operators := ROMCompiler._full_operators(full["model"])
	var basis_result := ROMCompiler._build_basis(full["model"], operators, ROMCompiler.LAPLACE_SHIFTS)
	print("PROBE_BASIS_SUCCESS=", bool(basis_result.get("success", false)))
	if not bool(basis_result.get("success", false)):
		quit(3)
	var basis_columns: Array = basis_result["basis_columns"]
	var basis_matrix := ROMCompiler._columns_to_rows(basis_columns, int(full["model"]["full_state_schema"]["state_count"]))
	var reduced_mass := ROMCompiler._reduced_mass(operators["storage"], basis_columns)
	var reduced_dissipation := ROMCompiler._reduced_dissipation(operators["shunts"], operators["edges"], basis_columns)

	_report_orbit("basis_17_19", float(basis_matrix[17][19]))
	_report_orbit("mass_1_19", float(reduced_mass[1][19]))
	_report_orbit("dissipation_4_19", float(reduced_dissipation[4][19]))
	for exponent in [-300, -260, -220, -180, -169, -160, -140, -120, -100, -80, -60, -40, -20, 0, 20, 60, 100, 160, 220, 280, 300]:
		var positive := float("1.2345678901234567e%d" % exponent)
		var negative := -float("9.876543210987654e%d" % exponent)
		_report_orbit("synthetic_pos_e%d" % exponent, positive)
		_report_orbit("synthetic_neg_e%d" % exponent, negative)
	quit(0)
