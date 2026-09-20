extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_logic_interface.v1"
const TICK_SEMANTICS := "SYNCHRONOUS_CURRENT_OUTPUT_THEN_REGISTER_COMMIT"
const FIELDS: Array[String] = [
	"schema", "input_signals", "output_signals", "state_signals",
	"tick_semantics", "interface_hash", "checksum",
]

static func create(input_signals: Array, output_signals: Array, state_signals: Array) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"input_signals": U.sorted_strings(input_signals),
		"output_signals": U.sorted_strings(output_signals),
		"state_signals": U.sorted_strings(state_signals),
		"tick_semantics": TICK_SEMANTICS,
		"interface_hash": "",
		"checksum": "",
	}
	value.interface_hash = U.canonical_hash({
		"input_signals": value.input_signals,
		"output_signals": value.output_signals,
		"state_signals": value.state_signals,
		"tick_semantics": value.tick_semantics,
	})
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_LOGIC_INTERFACE_SCHEMA")
	checked = U.validate_sorted_unique_strings(value.get("input_signals"), false)
	if not checked.success:
		return U.failure("INVALID_LOGIC_INTERFACE_INPUTS")
	checked = U.validate_sorted_unique_strings(value.get("output_signals"), false)
	if not checked.success:
		return U.failure("INVALID_LOGIC_INTERFACE_OUTPUTS")
	checked = U.validate_sorted_unique_strings(value.get("state_signals"), true)
	if not checked.success:
		return U.failure("INVALID_LOGIC_INTERFACE_STATE")
	if value.get("tick_semantics") != TICK_SEMANTICS:
		return U.failure("UNSUPPORTED_LOGIC_TICK_SEMANTICS")
	if not U.is_lower_hex_64(value.get("interface_hash")):
		return U.failure("INVALID_LOGIC_INTERFACE_HASH")
	var expected := U.canonical_hash({
		"input_signals": value.input_signals,
		"output_signals": value.output_signals,
		"state_signals": value.state_signals,
		"tick_semantics": value.tick_semantics,
	})
	if String(value.interface_hash) != expected:
		return U.failure("LOGIC_INTERFACE_HASH_MISMATCH")
	return U.validate_checksum(value)
