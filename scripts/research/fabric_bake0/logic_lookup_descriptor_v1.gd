extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/logic_interface_contract_v1.gd")

const SCHEMA := "planet_simulator.fabric_logic_lookup_descriptor.v1"
const FIELDS: Array[String] = [
	"schema", "graph_hash", "interface_contract", "address_bits", "entry_count",
	"input_bit_count", "output_bit_count", "state_bit_count", "packed_result_bits",
	"initial_state_word", "source_operation_count", "compiled_operation_count",
	"table", "table_hash", "descriptor_hash", "checksum",
]

static func create(
	graph_hash: String,
	interface_contract: Dictionary,
	initial_state_word: int,
	source_operation_count: int,
	compiled_operation_count: int,
	table: Array
) -> Dictionary:
	var input_bits := interface_contract.input_signals.size()
	var output_bits := interface_contract.output_signals.size()
	var state_bits := interface_contract.state_signals.size()
	var address_bits := input_bits + state_bits
	var packed_bits := output_bits + state_bits
	var value := {
		"schema": SCHEMA,
		"graph_hash": graph_hash,
		"interface_contract": interface_contract.duplicate(true),
		"address_bits": address_bits,
		"entry_count": table.size(),
		"input_bit_count": input_bits,
		"output_bit_count": output_bits,
		"state_bit_count": state_bits,
		"packed_result_bits": packed_bits,
		"initial_state_word": initial_state_word,
		"source_operation_count": source_operation_count,
		"compiled_operation_count": compiled_operation_count,
		"table": table.duplicate(),
		"table_hash": U.canonical_hash(table),
		"descriptor_hash": "",
		"checksum": "",
	}
	value.descriptor_hash = U.canonical_hash(_identity_payload(value))
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_LOGIC_LOOKUP_DESCRIPTOR_SCHEMA")
	if not U.is_lower_hex_64(value.get("graph_hash")):
		return U.failure("INVALID_LOGIC_LOOKUP_GRAPH_HASH")
	if typeof(value.get("interface_contract")) != TYPE_DICTIONARY:
		return U.failure("INVALID_LOGIC_LOOKUP_INTERFACE")
	checked = Interface.validate(value.interface_contract)
	if not checked.success:
		return checked
	for field in [
		"address_bits", "entry_count", "input_bit_count", "output_bit_count",
		"state_bit_count", "packed_result_bits", "initial_state_word",
		"source_operation_count", "compiled_operation_count"
	]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return U.failure("INVALID_LOGIC_LOOKUP_INTEGER", {"field": field})
	if int(value.address_bits) != int(value.input_bit_count) + int(value.state_bit_count):
		return U.failure("LOGIC_LOOKUP_ADDRESS_WIDTH_MISMATCH")
	if int(value.packed_result_bits) != int(value.output_bit_count) + int(value.state_bit_count):
		return U.failure("LOGIC_LOOKUP_RESULT_WIDTH_MISMATCH")
	if int(value.entry_count) != (1 << int(value.address_bits)):
		return U.failure("LOGIC_LOOKUP_ENTRY_COUNT_MISMATCH")
	if typeof(value.get("table")) != TYPE_ARRAY or value.table.size() != int(value.entry_count):
		return U.failure("INVALID_LOGIC_LOOKUP_TABLE")
	var packed_limit := 1 << int(value.packed_result_bits)
	for entry in value.table:
		if not U.is_json_integer(entry) or int(entry) < 0 or int(entry) >= packed_limit:
			return U.failure("INVALID_LOGIC_LOOKUP_ENTRY")
	if int(value.state_bit_count) == 0:
		if int(value.initial_state_word) != 0:
			return U.failure("LOGIC_LOOKUP_INITIAL_STATE_WITHOUT_STATE")
	elif int(value.initial_state_word) >= (1 << int(value.state_bit_count)):
		return U.failure("LOGIC_LOOKUP_INITIAL_STATE_OUT_OF_RANGE")
	if int(value.compiled_operation_count) < 1 or int(value.source_operation_count) <= int(value.compiled_operation_count):
		return U.failure("INSUFFICIENT_LOGIC_LOOKUP_REDUCTION")
	if not U.is_lower_hex_64(value.get("table_hash")) or String(value.table_hash) != U.canonical_hash(value.table):
		return U.failure("LOGIC_LOOKUP_TABLE_HASH_MISMATCH")
	if not U.is_lower_hex_64(value.get("descriptor_hash")) or String(value.descriptor_hash) != U.canonical_hash(_identity_payload(value)):
		return U.failure("LOGIC_LOOKUP_DESCRIPTOR_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("descriptor_hash")
	payload.erase("checksum")
	return payload
