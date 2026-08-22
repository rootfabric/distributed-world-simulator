extends RefCounted

## EG4 view planner: plans a ClientWorldView for ONE gateway session from a
## GatewayWorldGraphSnapshot cache line plus that session's subscription
## demand.
##
## Ownership discipline: the snapshot is READ_ONLY_DERIVED_RECONSTRUCTIBLE
## cache input (canonical=false, WORLD_DIRECTORY provenance) — planning never
## writes it and never becomes ownership truth. The walk crosses EVERY relation
## kind (NEIGHBOR, OVERLAP, CONTAINS, REFERENCE_FRAME_PARENT,
## REFERENCE_FRAME_CHILD, PORTAL_OR_TRANSITION, VISUALLY_RELEVANT) with a
## bounded depth/breadth budget PER plan revision.
##
## Determinism: adjacency is canonically ordered, the frontier is FIFO, and
## the same snapshot + demand always yields the same ordered view entries.
##
## Fail-closed: a demand bound to a stale graph revision, an invalid snapshot,
## or an unknown home world NEVER produces a view — the caller gets an
## explicit error result instead of a guessed plan.

const SnapshotScript = preload("res://scripts/network/gateway/gateway_world_graph_snapshot.gd")
const ViewScript = preload("res://scripts/network/gateway/client_world_view.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.eg4_view_planner.v1"
const SOURCE_ROLE_ACTIVE := "ACTIVE"
const SOURCE_ROLE_PROJECTION := "PROJECTION"
const DEFAULT_MAX_DEPTH := 3
const DEFAULT_MAX_BREADTH := 4
const WARM_DEPTH := 1
const MACRO_RELATION_KIND := "VISUALLY_RELEVANT"

const DEMAND_FIELDS: Array[String] = [
	"gateway_session_id",
	"home_world_id",
	"reference_frame_id",
	"interest_revision",
	"expected_graph_revision",
]


## Ordered deterministic walk over the relation graph from home_world_id.
## Result details:
##   visited: [world_id, ...] — home first, then canonical BFS discovery order
##   depth_by_world / reason_by_world: BFS depth and discovery-edge kind.
static func walk_worlds(snapshot: Dictionary, home_world_id: String, max_depth: int = DEFAULT_MAX_DEPTH, max_breadth: int = DEFAULT_MAX_BREADTH) -> Dictionary:
	var graph_check: Dictionary = _validated_adjacency(snapshot)
	if not bool(graph_check.get("success", false)):
		return graph_check
	var adjacency: Dictionary = graph_check["details"]["adjacency"]
	if not adjacency.has(home_world_id):
		return _failure("UNKNOWN_HOME_WORLD", {"home_world_id": home_world_id})
	var visited: Array[String] = [home_world_id]
	var seen: Dictionary = {home_world_id: true}
	var depth_by_world: Dictionary = {home_world_id: 0}
	var reason_by_world: Dictionary = {home_world_id: "home_anchor"}
	var frontier: Array[String] = [home_world_id]
	var depth := 0
	while not frontier.is_empty() and depth < maxi(max_depth, 0):
		depth += 1
		var next_frontier: Array[String] = []
		for current in frontier:
			var neighbor_slots: Array = adjacency[current]
			var budget := maxi(max_breadth, 0)
			for slot_index in range(mini(neighbor_slots.size(), budget)):
				var neighbor: Dictionary = neighbor_slots[slot_index]
				var neighbor_id := String(neighbor["world_id"])
				if seen.has(neighbor_id):
					continue
				seen[neighbor_id] = true
				visited.append(neighbor_id)
				depth_by_world[neighbor_id] = depth
				reason_by_world[neighbor_id] = String(neighbor["relation_kind"])
				next_frontier.append(neighbor_id)
		frontier = next_frontier
	return _success({
		"visited": visited,
		"depth_by_world": depth_by_world,
		"reason_by_world": reason_by_world,
	})


## Plan the ordered view entries {world_id, source_role, interest_revision}
## for one demand revision. Deterministic given snapshot + demands.
static func plan_view(snapshot: Dictionary, demand: Dictionary) -> Dictionary:
	var resolved: Dictionary = _resolve_demand(snapshot, demand)
	if not bool(resolved.get("success", false)):
		return resolved
	var resolution: Dictionary = resolved["details"]
	var walk_details: Dictionary = resolution["walk"]
	var entries: Array = []
	var visited: Array = walk_details["visited"]
	for index in range(visited.size()):
		var world_id := String(visited[index])
		entries.append({
			"world_id": world_id,
			"source_role": SOURCE_ROLE_ACTIVE if index == 0 else SOURCE_ROLE_PROJECTION,
			"interest_revision": int(resolution["interest_revision"]),
			"depth": int(walk_details["depth_by_world"].get(world_id, 0)),
			"visibility_reason": String(walk_details["reason_by_world"].get(world_id, "")),
		})
	return _success({
		"entries": entries,
		"graph_revision": int(resolution["graph_revision"]),
		"home_world_id": String(demand["home_world_id"]),
	})


## Build a full ClientWorldView contract DTO from the plan. view_revision must
## strictly advance per session (ClientWorldView.validate_newer contract).
static func build_client_world_view(snapshot: Dictionary, demand: Dictionary, view_revision: int, view_id: String) -> Dictionary:
	var planned: Dictionary = plan_view(snapshot, demand)
	if not bool(planned.get("success", false)):
		return planned
	if not NetworkUtilsScript.is_json_integer(view_revision) or int(view_revision) < 1:
		return _failure("INVALID_VIEW_REVISION", {"view_revision": view_revision})
	var id_check: Dictionary = GatewayUtilsScript.require_id({"view_id": view_id}, "view_id", "world-view")
	if not bool(id_check.get("success", false)):
		return _failure("INVALID_VIEW_ID", {"view_id": view_id})

	var interest_revision := int(planned["details"]["entries"][0]["interest_revision"]) \
			if not (planned["details"]["entries"] as Array).is_empty() else 1
	var graph_revision := int(planned["details"]["graph_revision"])
	var warm_worlds: Array[String] = []
	var projection_streams: Array = []
	var macro_sources: Array = []
	var entries: Array = planned["details"]["entries"]
	for index in range(entries.size()):
		if index == 0:
			continue # the ACTIVE anchor never appears as a derived stream
		var entry: Dictionary = entries[index]
		var world_id := String(entry["world_id"])
		var depth := int(entry["depth"])
		if depth <= WARM_DEPTH:
			warm_worlds.append(world_id)
		var stream_entry: Dictionary = _projection_entry(view_id, entry, graph_revision)
		if depth > WARM_DEPTH:
			projection_streams.append(stream_entry)
		if String(entry["visibility_reason"]) == MACRO_RELATION_KIND and depth > WARM_DEPTH:
			macro_sources.append(stream_entry)
	warm_worlds.sort()
	var view: Dictionary = ViewScript.create(
			view_id,
			String(demand["gateway_session_id"]),
			String(demand["home_world_id"]),
			String(demand["reference_frame_id"]),
			String(demand["home_world_id"]),
			warm_worlds,
			projection_streams,
			macro_sources,
			graph_revision,
			int(view_revision),
			interest_revision,
			true)
	var view_check: Dictionary = ViewScript.validate(view)
	if not bool(view_check.get("success", false)):
		return _failure("INVALID_CLIENT_WORLD_VIEW", {"error_code": String(view_check.get("error_code", ""))})
	return _success({"view": view, "entries": entries})


## ---- internals ---------------------------------------------------------------


static func _projection_entry(view_id: String, entry: Dictionary, _graph_revision: int) -> Dictionary:
	var world_slug := String(entry["world_id"]).replace("/", "-").replace("_", "-")
	var view_slug := view_id.replace("/", "-")
	var depth := int(entry["depth"])
	var max_depth := maxi(depth, 3)
	return {
		"source_world_id": String(entry["world_id"]),
		"projection_stream_id": "projection-stream/eg4/%s/%s" % [view_slug, world_slug],
		"lod_class": "lod_near" if depth <= 2 else "lod_far",
		"priority": maxi(max_depth - depth, 0),
		"visibility_reason": String(entry["visibility_reason"]).to_lower(),
		"interest_revision": int(entry["interest_revision"]),
		"projection_grant": "projection-grant/eg4/%s/%s" % [view_slug, world_slug],
	}


## Canonical undirected adjacency: world_id -> sorted [{world_id, relation_kind}].
static func _validated_adjacency(snapshot: Dictionary) -> Dictionary:
	var snapshot_check: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(snapshot_check.get("success", false)):
		return _failure("INVALID_GRAPH_SNAPSHOT", {"error_code": String(snapshot_check.get("error_code", ""))})
	var adjacency: Dictionary = {}
	for raw_world in Array(snapshot.get("worlds", [])):
		adjacency[String(Dictionary(raw_world).get("world_id", ""))] = []
	for raw_relation in Array(snapshot.get("relations", [])):
		var relation: Dictionary = Dictionary(raw_relation)
		var world_a := String(relation.get("world_a", ""))
		var world_b := String(relation.get("world_b", ""))
		var kind_value := String(relation.get("relation_kind", ""))
		if not adjacency.has(world_a) or not adjacency.has(world_b):
			return _failure("UNKNOWN_RELATION_WORLD", {"world_a": world_a, "world_b": world_b})
		(adjacency[world_a] as Array).append({"world_id": world_b, "relation_kind": kind_value})
		(adjacency[world_b] as Array).append({"world_id": world_a, "relation_kind": kind_value})
	for world_id in adjacency.keys():
		var neighbors: Array = adjacency[world_id]
		neighbors.sort_custom(func(a, b) -> bool:
			return String(a["world_id"]) < String(b["world_id"]))
	return _success({"adjacency": adjacency})


static func _resolve_demand(snapshot: Dictionary, demand: Dictionary) -> Dictionary:
	if typeof(demand) != TYPE_DICTIONARY:
		return _failure("INVALID_DEMAND", {})
	for field in DEMAND_FIELDS:
		if not demand.has(field):
			return _failure("MISSING_DEMAND_FIELD", {"field": field})
	var session_check: Dictionary = GatewayUtilsScript.require_id(demand, "gateway_session_id", "gateway-session")
	if not bool(session_check.get("success", false)):
		return session_check
	var world_check: Dictionary = GatewayUtilsScript.require_id(demand, "home_world_id", "world")
	if not bool(world_check.get("success", false)):
		return world_check
	var frame_check: Dictionary = GatewayUtilsScript.require_id(demand, "reference_frame_id", "reference-frame")
	if not bool(frame_check.get("success", false)):
		return frame_check
	var snapshot_check: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(snapshot_check.get("success", false)):
		return _failure("INVALID_GRAPH_SNAPSHOT", {"error_code": String(snapshot_check.get("error_code", ""))})
	var expected_revision := int(demand["expected_graph_revision"])
	var graph_revision := int(snapshot["graph_revision"])
	if expected_revision != graph_revision:
		# Fail closed on a stale graph revision: never plan from a stale cache.
		return _failure("STALE_GRAPH_REVISION", {
			"expected_graph_revision": expected_revision,
			"graph_revision": graph_revision,
		})
	var max_depth := int(demand.get("max_depth", DEFAULT_MAX_DEPTH))
	var max_breadth := int(demand.get("max_breadth", DEFAULT_MAX_BREADTH))
	var walk: Dictionary = walk_worlds(snapshot, String(demand["home_world_id"]), max_depth, max_breadth)
	if not bool(walk.get("success", false)):
		return walk
	return _success({
		"walk": walk["details"],
		"graph_revision": graph_revision,
		"interest_revision": int(demand["interest_revision"]),
		"max_depth": max_depth,
		"max_breadth": max_breadth,
	})


static func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


static func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
