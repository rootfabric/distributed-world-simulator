extends RefCounted

const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const NetworkScript = preload("res://scripts/construction/utilities/construction_utility_network_definition.gd")
const DemandScript = preload("res://scripts/construction/utilities/construction_utility_demand.gd")
const StorageScript = preload("res://scripts/construction/utilities/construction_utility_storage_state.gd")
const AllocationScript = preload("res://scripts/construction/utilities/construction_utility_allocation.gd")
const ProfileScript = preload("res://scripts/construction/utilities/construction_utility_execution_profile.gd")

static func step(network: Dictionary, demands: Array, storage_states: Array, tick: int) -> Dictionary:
	var checked := NetworkScript.validate(network); if not bool(checked.get("success", false)): return checked
	if tick < 0: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SIMULATION_TICK")
	var nodes := {}; var links := {}; var adjacency := {}
	for node in network["nodes"]:
		nodes[String(node["node_id"])] = node; adjacency[String(node["node_id"])] = []
	for link in network["links"]:
		links[String(link["link_id"])] = link
		if bool(link["enabled"]):
			adjacency[String(link["node_a_id"])].append({"other": String(link["node_b_id"]), "link_id": String(link["link_id"])})
			adjacency[String(link["node_b_id"])].append({"other": String(link["node_a_id"]), "link_id": String(link["link_id"])})
	for node_id in adjacency: adjacency[node_id].sort_custom(func(a,b): return String(a["link_id"]) < String(b["link_id"]))
	var canonical_demands: Array = []; var demand_ids := {}
	for demand in demands:
		if typeof(demand) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SIMULATION_DEMAND")
		checked = DemandScript.validate(demand); if not bool(checked.get("success", false)): return checked
		var demand_id := String(demand["demand_id"]); var consumer_id := String(demand["consumer_node_id"])
		if String(demand["network_id"]) != String(network["network_id"]) or not nodes.has(consumer_id) or String(nodes[consumer_id]["node_kind"]) != "CONSUMER" or demand_ids.has(demand_id): return ContractUtils.failure("CONSTRUCTION_UTILITY_DEMAND_NETWORK_MISMATCH")
		demand_ids[demand_id] = true; canonical_demands.append(demand)
	canonical_demands.sort_custom(func(a,b):
		var ap := int(a["priority"]); var bp := int(b["priority"])
		return String(a["demand_id"]) < String(b["demand_id"]) if ap == bp else ap > bp)
	var storage_by_node := {}
	for state in storage_states:
		if typeof(state) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_UTILITY_SIMULATION_STORAGE")
		checked = StorageScript.validate(state); if not bool(checked.get("success", false)): return checked
		var node_id := String(state["node_id"])
		if String(state["network_id"]) != String(network["network_id"]) or not nodes.has(node_id) or String(nodes[node_id]["node_kind"]) != "STORAGE" or storage_by_node.has(node_id): return ContractUtils.failure("CONSTRUCTION_UTILITY_STORAGE_NETWORK_MISMATCH")
		if absf(float(state["capacity"]) - float(nodes[node_id]["properties"]["storage_capacity"])) > 0.000001: return ContractUtils.failure("CONSTRUCTION_UTILITY_STORAGE_CAPACITY_MISMATCH")
		storage_by_node[node_id] = state.duplicate(true)
	for node_id in nodes:
		if String(nodes[node_id]["node_kind"]) == "STORAGE" and not storage_by_node.has(node_id): return ContractUtils.failure("CONSTRUCTION_UTILITY_STORAGE_STATE_REQUIRED")
	var source_remaining := {}; var source_kind := {}; var dispatch := {}
	for node_id in nodes:
		var node: Dictionary = nodes[node_id]; var kind := String(node["node_kind"])
		if kind == "SOURCE":
			var online := bool(node["properties"].get("online", true))
			source_remaining[node_id] = float(node["capacity_per_tick"]) if online else 0.0; source_kind[node_id] = "SOURCE"
			dispatch[node_id] = {"node_id": node_id, "generated": 0.0, "discharged": 0.0, "charged": 0.0}
		elif kind == "STORAGE":
			var state: Dictionary = storage_by_node[node_id]; var properties: Dictionary = node["properties"]
			var available := minf(float(node["capacity_per_tick"]), minf(float(properties["max_discharge_per_tick"]), float(state["stored_amount"]) * float(properties["discharge_efficiency"])))
			source_remaining[node_id] = available; source_kind[node_id] = "STORAGE"
			dispatch[node_id] = {"node_id": node_id, "generated": 0.0, "discharged": 0.0, "charged": 0.0}
	var link_remaining := {}; var link_flows := {}
	for link_id in links:
		link_remaining[link_id] = float(links[link_id]["capacity_per_tick"])
		link_flows[link_id] = {"link_id": link_id, "flow": 0.0, "loss": 0.0}
	var allocations: Array = []
	for demand in canonical_demands:
		var trial_sources := source_remaining.duplicate(true); var trial_links := link_remaining.duplicate(true); var trial_storage := _deep_dictionary(storage_by_node); var trial_dispatch := _deep_dictionary(dispatch); var trial_flows := _deep_dictionary(link_flows)
		var contribution_result := _allocate_demand(demand, nodes, links, adjacency, trial_sources, source_kind, trial_links, trial_storage, trial_dispatch, trial_flows)
		var delivered := float(contribution_result["delivered"])
		if delivered + 0.000001 < float(demand["minimum_required_per_tick"]):
			allocations.append(AllocationScript.create(demand, 0.0, 0.0, "SHED", [], []))
			continue
		source_remaining = trial_sources; link_remaining = trial_links; storage_by_node = trial_storage; dispatch = trial_dispatch; link_flows = trial_flows
		var status := "FULL" if absf(delivered - float(demand["requested_per_tick"])) <= 0.000001 else "PARTIAL"
		allocations.append(AllocationScript.create(demand, _q(delivered), _q(float(contribution_result["injected"]) - delivered), status, contribution_result["sources"], contribution_result["paths"]))
	_charge_storage(nodes, links, adjacency, source_remaining, source_kind, link_remaining, storage_by_node, dispatch, link_flows)
	var next_storage: Array = []
	for node_id in storage_by_node:
		var old: Dictionary = storage_by_node[node_id]
		next_storage.append(StorageScript.create(String(network["network_id"]), node_id, tick, int(old["revision"]) + 1, _q(float(old["stored_amount"])), float(old["capacity"])))
	var dispatch_rows: Array = []; for row in dispatch.values():
		var copy: Dictionary = row.duplicate(true); copy["generated"] = _q(float(copy["generated"])); copy["discharged"] = _q(float(copy["discharged"])); copy["charged"] = _q(float(copy["charged"])); dispatch_rows.append(copy)
	var flow_rows: Array = []; for row in link_flows.values():
		var copy: Dictionary = row.duplicate(true); copy["flow"] = _q(float(copy["flow"])); copy["loss"] = _q(float(copy["loss"])); flow_rows.append(copy)
	var has_partial := false; var has_shed := false; var total_delivered := 0.0
	for allocation in allocations:
		has_partial = has_partial or String(allocation["status"]) == "PARTIAL"; has_shed = has_shed or String(allocation["status"]) == "SHED"; total_delivered += float(allocation["delivered_per_tick"])
	var status := "BALANCED"
	if total_delivered <= 0.000001 and has_shed: status = "OFFLINE"
	elif has_shed: status = "SHEDDING"
	elif has_partial: status = "DEGRADED"
	var profile := ProfileScript.create(network, tick, status, allocations, dispatch_rows, flow_rows, next_storage)
	checked = ProfileScript.validate(profile); return ContractUtils.success({"profile": profile}) if bool(checked.get("success", false)) else checked

static func _allocate_demand(demand: Dictionary, nodes: Dictionary, links: Dictionary, adjacency: Dictionary, source_remaining: Dictionary, source_kind: Dictionary, link_remaining: Dictionary, storage_by_node: Dictionary, dispatch: Dictionary, link_flows: Dictionary) -> Dictionary:
	var target := String(demand["consumer_node_id"]); var remaining := float(demand["requested_per_tick"]); var paths: Array = []; var source_rows := {}
	var candidates: Array = []
	for source_id in source_remaining:
		if float(source_remaining[source_id]) <= 0.000001: continue
		var route := _best_route(source_id, target, nodes, links, adjacency, link_remaining)
		if not route.is_empty(): candidates.append({"source_id": source_id, "route": route, "source_kind": String(source_kind[source_id]), "priority": int(nodes[source_id]["dispatch_priority"])})
	candidates.sort_custom(func(a,b):
		var ak := 0 if String(a["source_kind"]) == "SOURCE" else 1; var bk := 0 if String(b["source_kind"]) == "SOURCE" else 1
		if ak != bk: return ak < bk
		if int(a["priority"]) != int(b["priority"]): return int(a["priority"]) > int(b["priority"])
		if absf(float(a["route"]["efficiency"]) - float(b["route"]["efficiency"])) > 0.000000001: return float(a["route"]["efficiency"]) > float(b["route"]["efficiency"])
		return String(a["source_id"]) < String(b["source_id"]))
	for candidate in candidates:
		if remaining <= 0.000001: break
		var source_id := String(candidate["source_id"]); var route: Dictionary = candidate["route"]; var efficiency := float(route["efficiency"])
		var path_limit := _path_source_injection_limit(route["link_ids"], links, link_remaining)
		var desired_injection := remaining / efficiency; var injected := minf(float(source_remaining[source_id]), minf(path_limit, desired_injection))
		if injected <= 0.000001: continue
		var delivered := _consume_path(injected, route["link_ids"], links, link_remaining, link_flows)
		source_remaining[source_id] = float(source_remaining[source_id]) - injected
		if String(candidate["source_kind"]) == "SOURCE": dispatch[source_id]["generated"] = float(dispatch[source_id]["generated"]) + injected
		else:
			var node: Dictionary = nodes[source_id]; var efficiency_out := float(node["properties"]["discharge_efficiency"]); var state: Dictionary = storage_by_node[source_id]
			state["stored_amount"] = maxf(0.0, float(state["stored_amount"]) - injected / efficiency_out); storage_by_node[source_id] = state
			dispatch[source_id]["discharged"] = float(dispatch[source_id]["discharged"]) + injected
		if not source_rows.has(source_id): source_rows[source_id] = {"node_id": source_id, "injected": 0.0, "delivered": 0.0, "source_kind": String(candidate["source_kind"])}
		source_rows[source_id]["injected"] = float(source_rows[source_id]["injected"]) + injected; source_rows[source_id]["delivered"] = float(source_rows[source_id]["delivered"]) + delivered
		paths.append({"source_node_id": source_id, "link_ids": Array(route["link_ids"]).duplicate(), "efficiency": _q(efficiency), "injected": _q(injected), "delivered": _q(delivered)})
		remaining -= delivered
	var sources: Array = []
	for row in source_rows.values():
		var copy: Dictionary = row.duplicate(true); copy["injected"] = _q(float(copy["injected"])); copy["delivered"] = _q(float(copy["delivered"])); sources.append(copy)
	return {"delivered": maxf(0.0, float(demand["requested_per_tick"]) - remaining), "injected": _sum_source_injected(sources), "sources": sources, "paths": paths}

static func _charge_storage(nodes: Dictionary, links: Dictionary, adjacency: Dictionary, source_remaining: Dictionary, source_kind: Dictionary, link_remaining: Dictionary, storage_by_node: Dictionary, dispatch: Dictionary, link_flows: Dictionary) -> void:
	var storage_ids: Array = storage_by_node.keys(); storage_ids.sort()
	var source_ids: Array = []
	for source_id in source_remaining:
		if String(source_kind[source_id]) == "SOURCE" and float(source_remaining[source_id]) > 0.000001: source_ids.append(source_id)
	source_ids.sort_custom(func(a,b):
		return String(a) < String(b) if int(nodes[a]["dispatch_priority"]) == int(nodes[b]["dispatch_priority"]) else int(nodes[a]["dispatch_priority"]) > int(nodes[b]["dispatch_priority"]))
	for storage_id in storage_ids:
		var state: Dictionary = storage_by_node[storage_id]; var node: Dictionary = nodes[storage_id]; var props: Dictionary = node["properties"]
		var desired_store := minf(float(props["max_charge_per_tick"]), float(state["capacity"]) - float(state["stored_amount"]))
		if desired_store <= 0.000001: continue
		for source_id in source_ids:
			if desired_store <= 0.000001: break
			var route := _best_route(source_id, storage_id, nodes, links, adjacency, link_remaining); if route.is_empty(): continue
			var efficiency := float(route["efficiency"]); var charge_eff := float(props["charge_efficiency"])
			var injected := minf(float(source_remaining[source_id]), minf(_path_source_injection_limit(route["link_ids"], links, link_remaining), desired_store / (efficiency * charge_eff)))
			if injected <= 0.000001: continue
			var arrived := _consume_path(injected, route["link_ids"], links, link_remaining, link_flows); var stored := arrived * charge_eff
			source_remaining[source_id] = float(source_remaining[source_id]) - injected; dispatch[source_id]["generated"] = float(dispatch[source_id]["generated"]) + injected; dispatch[storage_id]["charged"] = float(dispatch[storage_id]["charged"]) + stored
			state["stored_amount"] = minf(float(state["capacity"]), float(state["stored_amount"]) + stored); desired_store -= stored
		storage_by_node[storage_id] = state

static func _best_route(source_id: String, target_id: String, nodes: Dictionary, links: Dictionary, adjacency: Dictionary, link_remaining: Dictionary) -> Dictionary:
	if source_id == target_id: return {"link_ids": [], "efficiency": 1.0, "key": ""}
	var results: Array = []; _walk_routes(source_id, target_id, adjacency, links, link_remaining, {source_id: true}, [], 1.0, results, nodes.size())
	if results.is_empty(): return {}
	results.sort_custom(func(a,b):
		if absf(float(a["efficiency"]) - float(b["efficiency"])) > 0.000000001: return float(a["efficiency"]) > float(b["efficiency"])
		if Array(a["link_ids"]).size() != Array(b["link_ids"]).size(): return Array(a["link_ids"]).size() < Array(b["link_ids"]).size()
		return String(a["key"]) < String(b["key"]))
	return results[0]

static func _walk_routes(current: String, target: String, adjacency: Dictionary, links: Dictionary, link_remaining: Dictionary, visited: Dictionary, path: Array, efficiency: float, results: Array, maximum_nodes: int) -> void:
	if path.size() >= maximum_nodes: return
	for edge in adjacency.get(current, []):
		var other := String(edge["other"]); var link_id := String(edge["link_id"])
		if visited.has(other) or float(link_remaining[link_id]) <= 0.000001: continue
		var next_path := path.duplicate(); next_path.append(link_id); var next_efficiency := efficiency * (1.0 - float(links[link_id]["loss_fraction"]))
		if other == target:
			results.append({"link_ids": next_path, "efficiency": next_efficiency, "key": "|".join(next_path)})
		else:
			var next_visited := visited.duplicate(); next_visited[other] = true; _walk_routes(other, target, adjacency, links, link_remaining, next_visited, next_path, next_efficiency, results, maximum_nodes)

static func _path_source_injection_limit(path: Array, links: Dictionary, link_remaining: Dictionary) -> float:
	var limit := INF; var efficiency_before := 1.0
	for link_id in path:
		limit = minf(limit, float(link_remaining[String(link_id)]) / efficiency_before)
		efficiency_before *= 1.0 - float(links[String(link_id)]["loss_fraction"])
	return 0.0 if is_inf(limit) else limit

static func _consume_path(source_injection: float, path: Array, links: Dictionary, link_remaining: Dictionary, link_flows: Dictionary) -> float:
	var current := source_injection
	for raw_link_id in path:
		var link_id := String(raw_link_id); var loss := current * float(links[link_id]["loss_fraction"])
		link_remaining[link_id] = maxf(0.0, float(link_remaining[link_id]) - current)
		link_flows[link_id]["flow"] = float(link_flows[link_id]["flow"]) + current; link_flows[link_id]["loss"] = float(link_flows[link_id]["loss"]) + loss
		current -= loss
	return current

static func _sum_source_injected(rows: Array) -> float:
	var result := 0.0; for row in rows: result += float(row["injected"])
	return result
static func _deep_dictionary(source: Dictionary) -> Dictionary:
	var result := {}; for key in source: result[key] = Dictionary(source[key]).duplicate(true)
	return result
static func _q(value: float) -> float: return round(value * 1000000000.0) / 1000000000.0
