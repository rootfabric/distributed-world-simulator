extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const SCHEMA := "planet_simulator.semantic_port_descriptor.v1"
const PROTOCOL_VERSION := 1
const PORT_KINDS: Array[String] = [
	"BULK_TRANSFER",
	"EVENT_STREAM",
	"JOB_QUEUE",
	"REPLICATION_TRANSPORT",
	"SERVICE_REQUEST_REPLY",
]
const FIELDS: Array[String] = ["schema", "protocol_version", "port_kind", "adapter_id", "capabilities"]


static func create(port_kind: String, adapter_id: String, capabilities: Array[String] = []) -> Dictionary:
	var normalized: Array[String] = capabilities.duplicate()
	normalized.sort()
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"port_kind": port_kind,
		"adapter_id": adapter_id,
		"capabilities": normalized,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "Semantic port descriptor schema/version mismatch")
	if typeof(value.get("port_kind")) != TYPE_STRING or not PORT_KINDS.has(String(value["port_kind"])):
		return NetworkUtilsScript.validation_failure("INVALID_PORT_KIND", "Unknown semantic port kind")
	if not BusUtilsScript.is_canonical_id(value.get("adapter_id"), "adapter"):
		return NetworkUtilsScript.validation_failure("INVALID_ADAPTER_ID", "adapter_id is not canonical")
	if typeof(value.get("capabilities")) != TYPE_ARRAY:
		return NetworkUtilsScript.validation_failure("INVALID_FIELD_TYPE", "capabilities must be an Array")
	var previous: String = ""
	for capability in value["capabilities"]:
		if not BusUtilsScript.is_semantic_name(capability):
			return NetworkUtilsScript.validation_failure("INVALID_CAPABILITY", "Capability is not canonical")
		var text: String = String(capability)
		if not previous.is_empty() and text <= previous:
			return NetworkUtilsScript.validation_failure("NON_CANONICAL_CAPABILITIES", "Capabilities must be sorted and unique")
		previous = text
	return NetworkUtilsScript.validation_success()
