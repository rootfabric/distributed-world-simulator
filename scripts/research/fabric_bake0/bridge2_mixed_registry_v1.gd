extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Entry = preload("res://scripts/research/fabric_bake0/bridge2_entry_contract_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Slice = preload("res://scripts/research/fabric_bake0/bridge2_source_slice_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")

const SCHEMA := "planet_simulator.fabric_bridge2_mixed_registry.v1"
const REGION_FIELDS: Array[String] = [
	"region_id", "representation_kind", "state_id", "adapter",
]
const INTERFACE_FIELDS: Array[String] = [
	"interface_id", "region_a", "region_b", "port_a", "port_b", "conductance",
]
const FIELDS: Array[String] = [
	"schema", "master_frontier", "master_authority", "regions", "interfaces",
	"registry_hash", "checksum",
]

static func create(
	master_frontier: Dictionary,
	master_authority: Dictionary,
	regions: Array,
	interfaces: Array
) -> Dictionary:
	var ordered_regions := Utils.sorted_dicts(regions, "region_id")
	var ordered_interfaces := Utils.sorted_dicts(interfaces, "interface_id")
	var value: Dictionary = {
		"schema": SCHEMA,
		"master_frontier": master_frontier.duplicate(true),
		"master_authority": master_authority.duplicate(true),
		"regions": ordered_regions,
		"interfaces": ordered_interfaces,
		"registry_hash": "",
		"checksum": "",
	}
	value["registry_hash"] = Utils.canonical_hash(_identity_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BRIDGE2_MIXED_REGISTRY_SCHEMA")
	checked = Frontier.validate(value["master_frontier"])
	if not bool(checked.get("success", false)):
		return checked
	checked = AuthorityEnvelope.validate_b0_safety(value["master_authority"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("regions")) != TYPE_ARRAY or value["regions"].size() != Entry.REPRESENTATIONS.size():
		return Utils.failure("BRIDGE2_R1_REQUIRES_EXACTLY_FIVE_REGIONS")
	var region_ids: Array = []
	var state_ids: Array = []
	var kinds: Array = []
	var by_id := {}
	var owned_source_keys := {}
	var previous := ""
	for index in range(value["regions"].size()):
		var raw = value["regions"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_BRIDGE2_REGION_RECORD", {"index": index})
		var region: Dictionary = raw
		checked = Utils.validate_exact_fields(region, REGION_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(region.get("region_id"), 2) or not Utils.is_canonical_id(region.get("state_id"), 2):
			return Utils.failure("INVALID_BRIDGE2_REGION_ID", {"index": index})
		var region_id := String(region["region_id"])
		if index > 0 and region_id <= previous:
			return Utils.failure("BRIDGE2_REGIONS_NOT_SORTED_UNIQUE")
		previous = region_id
		if state_ids.has(region["state_id"]):
			return Utils.failure("BRIDGE2_OVERLAPPING_STATE_OWNERSHIP", {"state_id": region["state_id"]})
		if kinds.has(region["representation_kind"]):
			return Utils.failure("BRIDGE2_R1_DUPLICATE_REPRESENTATION_KIND", {"kind": region["representation_kind"]})
		checked = Adapter.validate(region["adapter"])
		if not bool(checked.get("success", false)):
			return checked
		if String(region["adapter"]["region_id"]) != region_id or String(region["adapter"]["state_id"]) != String(region["state_id"]) or String(region["adapter"]["representation_kind"]) != String(region["representation_kind"]):
			return Utils.failure("BRIDGE2_REGION_ADAPTER_BINDING_MISMATCH")
		checked = Slice.validate_against_master(
			region["adapter"]["source_slice"],
			value["master_frontier"],
			value["master_authority"]
		)
		if not bool(checked.get("success", false)):
			return checked
		for source_key in region["adapter"]["source_slice"]["source_keys"]:
			if owned_source_keys.has(source_key):
				return Utils.failure("BRIDGE2_OVERLAPPING_SOURCE_OWNERSHIP", {"source_key": source_key})
			owned_source_keys[source_key] = region_id
		region_ids.append(region_id)
		state_ids.append(String(region["state_id"]))
		kinds.append(String(region["representation_kind"]))
		by_id[region_id] = region
	kinds.sort()
	var expected_kinds := Entry.REPRESENTATIONS.duplicate()
	expected_kinds.sort()
	if kinds != expected_kinds:
		return Utils.failure("BRIDGE2_R1_REPRESENTATION_SET_MISMATCH")

	if typeof(value.get("interfaces")) != TYPE_ARRAY or value["interfaces"].size() != value["regions"].size() - 1:
		return Utils.failure("BRIDGE2_R1_INTERFACE_COUNT_MISMATCH")
	previous = ""
	var pair_keys := {}
	for index in range(value["interfaces"].size()):
		var raw = value["interfaces"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_BRIDGE2_INTERFACE", {"index": index})
		var interface: Dictionary = raw
		checked = Utils.validate_exact_fields(interface, INTERFACE_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(interface.get("interface_id"), 2):
			return Utils.failure("INVALID_BRIDGE2_INTERFACE_ID")
		var interface_id := String(interface["interface_id"])
		if index > 0 and interface_id <= previous:
			return Utils.failure("BRIDGE2_INTERFACES_NOT_SORTED_UNIQUE")
		previous = interface_id
		var a := String(interface.get("region_a", ""))
		var b := String(interface.get("region_b", ""))
		if a == b or not by_id.has(a) or not by_id.has(b):
			return Utils.failure("BRIDGE2_INTERFACE_REGION_INVALID")
		var pair_key := min(a, b) + "|" + max(a, b)
		if pair_keys.has(pair_key):
			return Utils.failure("BRIDGE2_DUPLICATE_REGION_INTERFACE")
		pair_keys[pair_key] = true
		if not _has_port(by_id[a]["adapter"]["boundary_contract"], String(interface["port_a"])):
			return Utils.failure("BRIDGE2_INTERFACE_PORT_A_UNDECLARED")
		if not _has_port(by_id[b]["adapter"]["boundary_contract"], String(interface["port_b"])):
			return Utils.failure("BRIDGE2_INTERFACE_PORT_B_UNDECLARED")
		if not Utils.is_positive_number(interface.get("conductance")):
			return Utils.failure("INVALID_BRIDGE2_INTERFACE_CONDUCTANCE")
	if not Utils.is_lower_hex_64(value.get("registry_hash")):
		return Utils.failure("INVALID_BRIDGE2_MIXED_REGISTRY_HASH")
	if String(value["registry_hash"]) != Utils.canonical_hash(_identity_payload(value)):
		return Utils.failure("BRIDGE2_MIXED_REGISTRY_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func region_by_id(value: Dictionary, region_id: String) -> Dictionary:
	for region in value.get("regions", []):
		if String(region.get("region_id", "")) == region_id:
			return Dictionary(region).duplicate(true)
	return {}

static func replace_region(value: Dictionary, replacement: Dictionary) -> Dictionary:
	var regions: Array = []
	var found := false
	for region in value["regions"]:
		if String(region["region_id"]) == String(replacement.get("region_id", "")):
			regions.append(replacement.duplicate(true))
			found = true
		else:
			regions.append(Dictionary(region).duplicate(true))
	if not found:
		return {}
	return create(value["master_frontier"], value["master_authority"], regions, value["interfaces"])

static func with_master(value: Dictionary, master_frontier: Dictionary, master_authority: Dictionary) -> Dictionary:
	return create(master_frontier, master_authority, value["regions"], value["interfaces"])

static func _has_port(boundary: Dictionary, port_id: String) -> bool:
	for port in boundary.get("ports", []):
		if String(port.get("port_id", "")) == port_id:
			return true
	return false

static func _identity_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("registry_hash")
	payload.erase("checksum")
	return payload
