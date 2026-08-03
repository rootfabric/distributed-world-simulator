extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const AllocationScript = preload("res://scripts/construction/utilities/construction_utility_allocation.gd")
const StorageScript = preload("res://scripts/construction/utilities/construction_utility_storage_state.gd")
const SCHEMA := "planet_simulator.construction_utility_execution_profile.v1"
const FIELDS: Array[String] = ["schema", "network_id", "utility_kind", "unit", "construct_id", "construct_revision", "construct_checksum", "network_checksum", "tick", "status", "allocations", "source_dispatch", "link_flows", "storage_states", "total_requested", "total_delivered", "total_loss", "total_unserved", "checksum"]
const STATUSES: Array[String] = ["BALANCED", "DEGRADED", "SHEDDING", "OFFLINE"]
const DISPATCH_FIELDS: Array[String] = ["node_id", "generated", "discharged", "charged"]
const FLOW_FIELDS: Array[String] = ["link_id", "flow", "loss"]

static func create(network: Dictionary, tick: int, status: String, allocations: Array, source_dispatch: Array, link_flows: Array, storage_states: Array) -> Dictionary:
	var sorted_allocations := allocations.duplicate(true); sorted_allocations.sort_custom(func(a,b): return String(a.get("demand_id", "")) < String(b.get("demand_id", "")))
	var sorted_dispatch := source_dispatch.duplicate(true); sorted_dispatch.sort_custom(func(a,b): return String(a.get("node_id", "")) < String(b.get("node_id", "")))
	var sorted_flows := link_flows.duplicate(true); sorted_flows.sort_custom(func(a,b): return String(a.get("link_id", "")) < String(b.get("link_id", "")))
	var sorted_storage := storage_states.duplicate(true); sorted_storage.sort_custom(func(a,b): return String(a.get("node_id", "")) < String(b.get("node_id", "")))
	var requested := 0.0; var delivered := 0.0; var loss := 0.0
	for row in sorted_allocations:
		requested += float(row.get("requested_per_tick", 0.0)); delivered += float(row.get("delivered_per_tick", 0.0)); loss += float(row.get("loss_per_tick", 0.0))
	var value := {"schema": SCHEMA, "network_id": String(network.get("network_id", "")), "utility_kind": String(network.get("utility_kind", "")), "unit": String(network.get("unit", "")), "construct_id": String(network.get("construct_id", "")), "construct_revision": int(network.get("construct_revision", -1)), "construct_checksum": String(network.get("construct_checksum", "")), "network_checksum": String(network.get("checksum", "")), "tick": tick, "status": status, "allocations": sorted_allocations, "source_dispatch": sorted_dispatch, "link_flows": sorted_flows, "storage_states": sorted_storage, "total_requested": requested, "total_delivered": delivered, "total_loss": loss, "total_unserved": maxf(0.0, requested - delivered), "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ContractUtils.failure("UNSUPPORTED_CONSTRUCTION_UTILITY_EXECUTION_PROFILE_SCHEMA")
	if not ContractUtils.is_path(String(value.get("network_id", "")), "utility-network/") or not ContractUtils.is_path(String(value.get("construct_id", "")), "construct/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_EXECUTION_PROFILE_IDENTITY")
	var kind := String(value.get("utility_kind", "")); if not ContractUtils.VALID_KINDS.has(kind) or String(value.get("unit", "")) != String(ContractUtils.VALID_UNITS.get(kind, "")): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_EXECUTION_PROFILE_KIND")
	if not UtilsScript.is_json_integer(value.get("construct_revision")) or int(value["construct_revision"]) < 0 or not UtilsScript.is_json_integer(value.get("tick")) or int(value["tick"]) < 0: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_EXECUTION_PROFILE_VERSION")
	for field in ["construct_checksum", "network_checksum"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).length() != 64: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_EXECUTION_PROFILE_CHECKSUM_REFERENCE")
	if typeof(value.get("status")) != TYPE_STRING or not STATUSES.has(String(value["status"])): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_EXECUTION_PROFILE_STATUS")
	for field in ["allocations", "source_dispatch", "link_flows", "storage_states"]:
		if typeof(value.get(field)) != TYPE_ARRAY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_EXECUTION_PROFILE_COLLECTION")
	var requested := 0.0; var delivered := 0.0; var loss := 0.0; var previous := ""; var has_partial := false; var has_shed := false
	for allocation in value["allocations"]:
		if typeof(allocation) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_EXECUTION_PROFILE_ALLOCATION")
		var checked := AllocationScript.validate(allocation); if not bool(checked.get("success", false)): return checked
		var demand_id := String(allocation["demand_id"]); if String(allocation["network_id"]) != String(value["network_id"]) or (not previous.is_empty() and demand_id < previous): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_UTILITY_EXECUTION_ALLOCATIONS")
		requested += float(allocation["requested_per_tick"]); delivered += float(allocation["delivered_per_tick"]); loss += float(allocation["loss_per_tick"]); previous = demand_id
		has_partial = has_partial or String(allocation["status"]) == "PARTIAL"; has_shed = has_shed or String(allocation["status"]) == "SHED"
	previous = ""
	for row in value["source_dispatch"]:
		if typeof(row) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SOURCE_DISPATCH")
		var checked := UtilsScript.validate_exact_fields(row, DISPATCH_FIELDS); if not bool(checked.get("success", false)): return checked
		var node_id := String(row.get("node_id", "")); if not ContractUtils.is_path(node_id, "utility-node/") or (not previous.is_empty() and node_id < previous): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_UTILITY_SOURCE_DISPATCH")
		for field in ["generated", "discharged", "charged"]:
			if not ContractUtils.non_negative(row.get(field)): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SOURCE_DISPATCH_QUANTITY")
		previous = node_id
	previous = ""
	for row in value["link_flows"]:
		if typeof(row) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_LINK_FLOW")
		var checked := UtilsScript.validate_exact_fields(row, FLOW_FIELDS); if not bool(checked.get("success", false)): return checked
		var link_id := String(row.get("link_id", "")); if not ContractUtils.is_path(link_id, "utility-link/") or (not previous.is_empty() and link_id < previous): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_UTILITY_LINK_FLOWS")
		if not ContractUtils.non_negative(row.get("flow")) or not ContractUtils.non_negative(row.get("loss")): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_LINK_FLOW_QUANTITY")
		previous = link_id
	previous = ""
	for storage in value["storage_states"]:
		if typeof(storage) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_STORAGE_PROFILE_STATE")
		var checked := StorageScript.validate(storage); if not bool(checked.get("success", false)): return checked
		var node_id := String(storage["node_id"]); if String(storage["network_id"]) != String(value["network_id"]) or (not previous.is_empty() and node_id < previous): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_UTILITY_STORAGE_PROFILE_STATES")
		previous = node_id
	for field in ["total_requested", "total_delivered", "total_loss", "total_unserved"]:
		if not ContractUtils.non_negative(value.get(field)): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_EXECUTION_PROFILE_TOTAL")
	if absf(float(value["total_requested"]) - requested) > 0.000001 or absf(float(value["total_delivered"]) - delivered) > 0.000001 or absf(float(value["total_loss"]) - loss) > 0.000001 or absf(float(value["total_unserved"]) - maxf(0.0, requested - delivered)) > 0.000001: return ContractUtils.failure("CONSTRUCTION_UTILITY_EXECUTION_PROFILE_TOTAL_MISMATCH")
	var status := String(value["status"])
	if (status == "BALANCED" and (has_partial or has_shed)) or (status == "DEGRADED" and (not has_partial or has_shed)) or (status == "SHEDDING" and not has_shed) or (status == "OFFLINE" and delivered > 0.000001): return ContractUtils.failure("CONSTRUCTION_UTILITY_EXECUTION_PROFILE_STATUS_MISMATCH")
	if String(value.get("checksum", "")) != compute_checksum(value): return ContractUtils.failure("CONSTRUCTION_UTILITY_EXECUTION_PROFILE_CHECKSUM_MISMATCH")
	return ContractUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
