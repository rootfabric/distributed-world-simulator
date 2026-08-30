extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_physical_boundary_contract.v1"
const PORT_FIELDS: Array[String] = [
	"port_id", "physical_domain", "effort_quantity", "flow_quantity",
	"effort_dimension", "flow_dimension", "frame", "orientation",
	"conservation_group", "event_observables",
]
const FIELDS: Array[String] = ["schema", "ports", "contract_hash", "checksum"]
const ORIENTATIONS: Array[String] = ["INTO_SUBSYSTEM", "OUT_OF_SUBSYSTEM"]

static func create(ports: Array) -> Dictionary:
	var ordered := Utils.sorted_dicts(ports, "port_id")
	for index in range(ordered.size()):
		if typeof(ordered[index]) == TYPE_DICTIONARY:
			var port: Dictionary = ordered[index]
			if typeof(port.get("event_observables")) == TYPE_ARRAY:
				port["event_observables"] = Utils.sorted_strings(port["event_observables"])
	var value: Dictionary = {
		"schema": SCHEMA,
		"ports": ordered,
		"contract_hash": Utils.canonical_hash(ordered),
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_PHYSICAL_BOUNDARY_CONTRACT_SCHEMA")
	if typeof(value.get("ports")) != TYPE_ARRAY or value["ports"].is_empty():
		return Utils.failure("INVALID_PHYSICAL_BOUNDARY_PORTS")
	var previous := ""
	for index in range(value["ports"].size()):
		var raw = value["ports"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_PHYSICAL_BOUNDARY_PORT", {"index": index})
		var port: Dictionary = raw
		checked = Utils.validate_exact_fields(port, PORT_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(port.get("port_id"), 2):
			return Utils.failure("INVALID_PHYSICAL_BOUNDARY_PORT_ID", {"index": index})
		if not Utils.is_upper_kind(port.get("physical_domain")):
			return Utils.failure("INVALID_PHYSICAL_DOMAIN", {"index": index})
		if not Utils.is_canonical_id(port.get("effort_quantity"), 2) or not Utils.is_canonical_id(port.get("flow_quantity"), 2):
			return Utils.failure("INVALID_PHYSICAL_BOUNDARY_QUANTITY", {"index": index})
		checked = Utils.validate_dimension(port.get("effort_dimension"))
		if not bool(checked.get("success", false)):
			return checked
		checked = Utils.validate_dimension(port.get("flow_dimension"))
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(port.get("frame"), 2):
			return Utils.failure("INVALID_PHYSICAL_BOUNDARY_FRAME", {"index": index})
		if not ORIENTATIONS.has(String(port.get("orientation", ""))):
			return Utils.failure("INVALID_PHYSICAL_BOUNDARY_ORIENTATION", {"index": index})
		if not Utils.is_canonical_id(port.get("conservation_group"), 2):
			return Utils.failure("INVALID_PHYSICAL_CONSERVATION_GROUP", {"index": index})
		checked = Utils.validate_sorted_unique_strings(port.get("event_observables"), true, true)
		if not bool(checked.get("success", false)):
			return checked
		var current := String(port["port_id"])
		if index > 0 and current <= previous:
			return Utils.failure("PHYSICAL_BOUNDARY_PORTS_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	if not Utils.is_lower_hex_64(value.get("contract_hash")):
		return Utils.failure("INVALID_PHYSICAL_BOUNDARY_CONTRACT_HASH")
	if String(value["contract_hash"]) != Utils.canonical_hash(value["ports"]):
		return Utils.failure("PHYSICAL_BOUNDARY_CONTRACT_HASH_MISMATCH")
	return Utils.validate_checksum(value)
