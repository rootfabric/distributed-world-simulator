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
	var long_orbit_value := float("1.2345678901234567e-169")
	var long_orbit := _orbit_rounds(long_orbit_value)
	print("PROBE_LONG_ORBIT_ROUNDS=", long_orbit["rounds"])
	var normalized_long := NetworkUtils.canonicalize(long_orbit_value, "$probe.long_orbit")
	print("PROBE_LONG_ORBIT_CANONICAL_SUCCESS=", bool(normalized_long.get("success", false)))
	var reduced := ROMCompiler.compile(full["model"])
	print("PROBE_ROM_SUCCESS=", bool(reduced.get("success", false)))
	print("PROBE_ROM_ERROR=", String(reduced.get("error_code", "")))
	if not bool(normalized_long.get("success", false)) or not bool(reduced.get("success", false)):
		quit(4)
	quit(0)