extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_utility_allocation.v1"
const FIELDS: Array[String] = ["schema", "demand_id", "network_id", "consumer_node_id", "requested_per_tick", "minimum_required_per_tick", "delivered_per_tick", "loss_per_tick", "status", "priority", "source_contributions", "path_contributions", "checksum"]
const STATUSES: Array[String] = ["FULL", "PARTIAL", "SHED"]
const SOURCE_FIELDS: Array[String] = ["node_id", "injected", "delivered", "source_kind"]
const PATH_FIELDS: Array[String] = ["source_node_id", "link_ids", "efficiency", "injected", "delivered"]

static func create(demand: Dictionary, delivered: float, loss: float, status: String, source_contributions: Array, path_contributions: Array) -> Dictionary:
	var sources := source_contributions.duplicate(true); sources.sort_custom(func(a,b): return String(a.get("node_id", "")) < String(b.get("node_id", "")))
	var paths := path_contributions.duplicate(true); paths.sort_custom(func(a,b):
		var ak := "%s|%s" % [String(a.get("source_node_id", "")), "|".join(Array(a.get("link_ids", [])))]
		var bk := "%s|%s" % [String(b.get("source_node_id", "")), "|".join(Array(b.get("link_ids", [])))]
		return ak < bk)
	var value := {"schema": SCHEMA, "demand_id": String(demand.get("demand_id", "")), "network_id": String(demand.get("network_id", "")), "consumer_node_id": String(demand.get("consumer_node_id", "")), "requested_per_tick": float(demand.get("requested_per_tick", 0.0)), "minimum_required_per_tick": float(demand.get("minimum_required_per_tick", 0.0)), "delivered_per_tick": delivered, "loss_per_tick": loss, "status": status, "priority": int(demand.get("priority", 0)), "source_contributions": sources, "path_contributions": paths, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ContractUtils.failure("UNSUPPORTED_CONSTRUCTION_UTILITY_ALLOCATION_SCHEMA")
	if not ContractUtils.is_path(String(value.get("demand_id", "")), "utility-demand/") or not ContractUtils.is_path(String(value.get("network_id", "")), "utility-network/") or not ContractUtils.is_path(String(value.get("consumer_node_id", "")), "utility-node/"): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_ALLOCATION_IDENTITY")
	for field in ["requested_per_tick", "minimum_required_per_tick", "delivered_per_tick", "loss_per_tick"]:
		if not ContractUtils.non_negative(value.get(field)): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_ALLOCATION_QUANTITY")
	if float(value["minimum_required_per_tick"]) > float(value["requested_per_tick"]) or float(value["delivered_per_tick"]) > float(value["requested_per_tick"]) + 0.000001: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_ALLOCATION_BOUNDS")
	if typeof(value.get("status")) != TYPE_STRING or not STATUSES.has(String(value["status"])): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_ALLOCATION_STATUS")
	if not UtilsScript.is_json_integer(value.get("priority")) or int(value["priority"]) < 0: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_ALLOCATION_PRIORITY")
	if typeof(value.get("source_contributions")) != TYPE_ARRAY or typeof(value.get("path_contributions")) != TYPE_ARRAY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_ALLOCATION_CONTRIBUTIONS")
	var delivered_sum := 0.0; var injected_sum := 0.0; var previous := ""
	for row in value["source_contributions"]:
		if typeof(row) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SOURCE_CONTRIBUTION")
		var row_exact := UtilsScript.validate_exact_fields(row, SOURCE_FIELDS); if not bool(row_exact.get("success", false)): return row_exact
		var node_id := String(row.get("node_id", ""))
		if not ContractUtils.is_path(node_id, "utility-node/") or (not previous.is_empty() and node_id < previous): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_UTILITY_SOURCE_CONTRIBUTIONS")
		if not ContractUtils.non_negative(row.get("injected")) or not ContractUtils.non_negative(row.get("delivered")) or float(row["delivered"]) > float(row["injected"]) + 0.000001: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SOURCE_CONTRIBUTION_QUANTITY")
		if typeof(row.get("source_kind")) != TYPE_STRING or not String(row["source_kind"]) in ["SOURCE", "STORAGE"]: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SOURCE_KIND")
		delivered_sum += float(row["delivered"]); injected_sum += float(row["injected"]); previous = node_id
	previous = ""; var path_delivered := 0.0; var path_injected := 0.0
	for row in value["path_contributions"]:
		if typeof(row) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_PATH_CONTRIBUTION")
		var row_exact := UtilsScript.validate_exact_fields(row, PATH_FIELDS); if not bool(row_exact.get("success", false)): return row_exact
		var key := "%s|%s" % [String(row.get("source_node_id", "")), "|".join(Array(row.get("link_ids", [])))]
		if not ContractUtils.is_path(String(row.get("source_node_id", "")), "utility-node/") or (not previous.is_empty() and key < previous): return ContractUtils.failure("NON_CANONICAL_CONSTRUCTION_UTILITY_PATH_CONTRIBUTIONS")
		if typeof(row.get("link_ids")) != TYPE_ARRAY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_PATH_LINKS")
		var seen_links := {}
		for raw_link_id in row["link_ids"]:
			var link_id := String(raw_link_id)
			if typeof(raw_link_id) != TYPE_STRING or not ContractUtils.is_path(link_id, "utility-link/") or seen_links.has(link_id): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_PATH_LINK")
			seen_links[link_id] = true
		if not ContractUtils.ratio(row.get("efficiency"), false) or not ContractUtils.non_negative(row.get("injected")) or not ContractUtils.non_negative(row.get("delivered")): return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_PATH_CONTRIBUTION_QUANTITY")
		if absf(float(row["delivered"]) - float(row["injected"]) * float(row["efficiency"])) > 0.000001: return ContractUtils.failure("CONSTRUCTION_UTILITY_PATH_CONTRIBUTION_MISMATCH")
		path_delivered += float(row["delivered"]); path_injected += float(row["injected"]); previous = key
	if absf(delivered_sum - float(value["delivered_per_tick"])) > 0.000001 or absf(path_delivered - delivered_sum) > 0.000001 or absf(path_injected - injected_sum) > 0.000001 or absf(float(value["loss_per_tick"]) - (injected_sum - delivered_sum)) > 0.000001: return ContractUtils.failure("CONSTRUCTION_UTILITY_ALLOCATION_SUMMARY_MISMATCH")
	var delivered := float(value["delivered_per_tick"]); var requested := float(value["requested_per_tick"]); var minimum := float(value["minimum_required_per_tick"]); var status := String(value["status"])
	if (status == "FULL" and absf(delivered - requested) > 0.000001) or (status == "PARTIAL" and not (delivered >= minimum and delivered < requested - 0.000001)) or (status == "SHED" and delivered > 0.000001): return ContractUtils.failure("CONSTRUCTION_UTILITY_ALLOCATION_STATUS_MISMATCH")
	if String(value.get("checksum", "")) != compute_checksum(value): return ContractUtils.failure("CONSTRUCTION_UTILITY_ALLOCATION_CHECKSUM_MISMATCH")
	return ContractUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
