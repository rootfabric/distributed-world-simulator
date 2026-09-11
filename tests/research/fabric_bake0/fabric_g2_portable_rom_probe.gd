extends SceneTree

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

const ORBIT_LIMIT := 65536

func _probe_transport(label: String, value) -> void:
	var normalized := NetworkUtils.canonicalize(value, "$probe.%s" % label)
	print("PROBE_TRANSPORT_", label, "_SUCCESS=", bool(normalized.get("success", false)))
	if not bool(normalized.get("success", false)):
		print("PROBE_TRANSPORT_", label, "_ERROR=", String(normalized.get("error", "")))

func _measure_orbit(label: String, start_value: float) -> void:
	var current := start_value
	var seen := {}
	var encoded_orbit: Array[String] = []
	for round_index in range(ORBIT_LIMIT):
		var encoded := JSON.stringify(current, "", true, true)
		if round_index < 6:
			print("PROBE_ORBIT_", label, "_ROUND_", round_index, "=", encoded)
		var parsed = JSON.parse_string(encoded)
		if parsed == null and encoded != "null":
			print("PROBE_ORBIT_", label, "_RESULT=PARSE_FAIL round=", round_index)
			return
		var next_value := float(parsed)
		if next_value == current:
			print("PROBE_ORBIT_", label, "_RESULT=FIXED rounds=", round_index + 1, " value=", encoded)
			return
		var next_encoded := JSON.stringify(next_value, "", true, true)
		if seen.has(next_encoded):
			var cycle_start := int(seen[next_encoded])
			var cycle_length := encoded_orbit.size() - cycle_start
			var representative := next_encoded
			for orbit_index in range(cycle_start, encoded_orbit.size()):
				if encoded_orbit[orbit_index] < representative:
					representative = encoded_orbit[orbit_index]
			print("PROBE_ORBIT_", label, "_RESULT=CYCLE rounds=", round_index + 1, " start=", cycle_start, " length=", cycle_length, " representative=", representative)
			return
		seen[encoded] = encoded_orbit.size()
		encoded_orbit.append(encoded)
		current = next_value
	print("PROBE_ORBIT_", label, "_RESULT=LIMIT rounds=", ORBIT_LIMIT, " last=", JSON.stringify(current, "", true, true))

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

	_probe_transport("basis", basis_matrix)
	_probe_transport("mass", reduced_mass)
	_probe_transport("dissipation", reduced_dissipation)

	_measure_orbit("basis_17_19", float(basis_matrix[17][19]))
	_measure_orbit("mass_1_19", float(reduced_mass[1][19]))
	_measure_orbit("dissipation_4_19", float(reduced_dissipation[4][19]))
	quit(0)
