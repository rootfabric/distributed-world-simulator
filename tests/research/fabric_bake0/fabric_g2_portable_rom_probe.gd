extends SceneTree

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

func _probe_transport(label: String, value) -> void:
	var normalized := NetworkUtils.canonicalize(value, "$probe.%s" % label)
	print("PROBE_TRANSPORT_", label, "_SUCCESS=", bool(normalized.get("success", false)))
	if not bool(normalized.get("success", false)):
		print("PROBE_TRANSPORT_", label, "_ERROR=", String(normalized.get("error", "")))

func _init() -> void:
	var fixture := Fixture.build("ZERO")
	var full := FullCompiler.compile(fixture["request"])
	print("PROBE_FULL_SUCCESS=", bool(full.get("success", false)))
	print("PROBE_FULL_ERROR=", String(full.get("error_code", "")))
	if not bool(full.get("success", false)):
		quit(2)
	var validated := FullModel.validate(full["model"])
	print("PROBE_FULL_VALIDATE_SUCCESS=", bool(validated.get("success", false)))
	print("PROBE_FULL_VALIDATE_ERROR=", String(validated.get("error_code", "")))

	var operators := ROMCompiler._full_operators(full["model"])
	print("PROBE_OPERATORS_SUCCESS=", bool(operators.get("success", false)))
	var basis_result := ROMCompiler._build_basis(full["model"], operators, ROMCompiler.LAPLACE_SHIFTS)
	print("PROBE_BASIS_SUCCESS=", bool(basis_result.get("success", false)))
	if not bool(basis_result.get("success", false)):
		print("PROBE_BASIS_ERROR=", String(basis_result.get("error_code", "")))
		quit(3)
	var basis_columns: Array = basis_result["basis_columns"]
	var basis_matrix := ROMCompiler._columns_to_rows(basis_columns, int(full["model"]["full_state_schema"]["state_count"]))
	var reduced_mass := ROMCompiler._reduced_mass(operators["storage"], basis_columns)
	var reduced_dissipation := ROMCompiler._reduced_dissipation(operators["shunts"], operators["edges"], basis_columns)
	var port_data := ROMCompiler._port_data(full["model"])
	var reduced_input := ROMCompiler._reduced_input(basis_columns, port_data["indices"], port_data["signs"])
	var reduced_output := ROMCompiler._reduced_output(basis_columns, port_data["indices"])
	var passivity := ROMCompiler._passivity_certificate(reduced_mass, reduced_dissipation)
	var interpolation := ROMCompiler._interpolation_certificate(
		operators, reduced_mass, reduced_dissipation, reduced_input, reduced_output,
		port_data["indices"], ROMCompiler.LAPLACE_SHIFTS
	)

	_probe_transport("basis", basis_matrix)
	_probe_transport("mass", reduced_mass)
	_probe_transport("dissipation", reduced_dissipation)
	_probe_transport("input", reduced_input)
	_probe_transport("output", reduced_output)
	_probe_transport("passivity", passivity)
	_probe_transport("interpolation", interpolation)

	var reduced := ROMCompiler.compile(full["model"])
	print("PROBE_ROM_SUCCESS=", bool(reduced.get("success", false)))
	print("PROBE_ROM_ERROR=", String(reduced.get("error_code", "")))
	print("PROBE_ROM_DETAILS=", JSON.stringify(reduced.get("details", {}), "", true, true))
	quit(0)
