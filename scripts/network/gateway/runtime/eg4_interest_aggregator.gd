extends RefCounted

## EG4 interest aggregator: folds per-client subscription demands into ONE
## AggregatedInterestPlan per upstream world, deduplicated across clients, and
## derives per-upstream-source stream sets plus subscribe/unsubscribe deltas.
##
## Ownership discipline: the aggregator produces DERIVED ROUTING DEMAND ONLY
## (read_only contracts, canonical=false ownership). It never mutates route
## truth and never interprets domain payloads. Identity namespaces stay
## separated: gateway-session/* subscribers, authority/* upstream sources,
## world/* demand targets.
##
## Staleness lifecycle: withdrawing the last demand of a world emits an
## unsubscribe delta and parks the world as a STALE upstream subscription; a
## bounded maintenance cycle retires up to retire_batch_per_cycle stale
## subscriptions per cycle, so after demand withdrawal and a bounded number of
## pump cycles the stale set is provably EMPTY.

const PlanScript = preload("res://scripts/network/gateway/aggregated_interest_plan.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.eg4_interest_aggregator.v1"
const DEFAULT_SOURCE_ROLE := "PROJECTION"
const REPRESENTATION_OR_LOD := "entity_states"
const DEFAULT_AGGREGATE_PRIORITY := 4
const DEFAULT_BYTES_PER_SECOND := 262144
## Bounded staleness drain: maximum stale subscriptions retired per cycle.
const DEFAULT_RETIRE_BATCH_PER_CYCLE := 2

var _retire_batch_per_cycle: int = DEFAULT_RETIRE_BATCH_PER_CYCLE
# gateway_session_id -> {"interest_revision", "graph_revision",
#                        "worlds": {world_id: source_authority_id}}
var _demands_by_session: Dictionary = {}
# world_id -> AggregatedInterestPlan contract dictionary (validated).
var _plans_by_world: Dictionary = {}
# world_id -> source_authority_id currently subscribed upstream.
var _source_by_world: Dictionary = {}
# world_id -> true once parked as a stale upstream subscription.
var _stale_worlds: Dictionary = {}
# source_authority_id -> highest interest_revision actually served upstream.
var _last_served_revision_by_source: Dictionary = {}
var _counters := {
	"demands_set": 0,
	"demands_withdrawn": 0,
	"subscribe_deltas_emitted": 0,
	"unsubscribe_deltas_emitted": 0,
	"deduplicated_demands": 0,
	"stale_retired": 0,
}


func configure(options: Dictionary) -> Dictionary:
	for key in options.keys():
		var value = options[key]
		match String(key):
			"retire_batch_per_cycle":
				if not GatewayUtilsScript.require_positive_integer(options, "retire_batch_per_cycle").get("success", false):
					return _failure("INVALID_OPTION", {"option": "retire_batch_per_cycle"})
				_retire_batch_per_cycle = int(value)
			_:
				return _failure("UNKNOWN_OPTION", {"option": String(key)})
	return _success({})


## Register/replace ONE client session's demand revision.
## demand: {gateway_session_id, interest_revision, graph_revision,
##          worlds: [{"world_id", "source_authority_id"}, ...]}
## Returns the subscribe/unsubscribe deltas this revision produced.
func set_client_demand(demand: Dictionary) -> Dictionary:
	var check: Dictionary = _validate_demand(demand)
	if not bool(check.get("success", false)):
		return check
	var gateway_session_id := String(demand["gateway_session_id"])
	var previous: Dictionary = _worlds_of(_demands_by_session.get(gateway_session_id, {}))
	var next_worlds: Dictionary = {}
	for raw_entry in Array(demand["worlds"]):
		var entry: Dictionary = Dictionary(raw_entry)
		next_worlds[String(entry["world_id"])] = String(entry["source_authority_id"])
	_demands_by_session[gateway_session_id] = {
		"gateway_session_id": gateway_session_id,
		"interest_revision": int(demand["interest_revision"]),
		"graph_revision": int(demand["graph_revision"]),
		"worlds": next_worlds.duplicate(true),
	}
	_counters["demands_set"] = int(_counters["demands_set"]) + 1
	var deltas: Array = _recompute(previous)
	return _success({
		"deltas": deltas,
		"interest_revision": int(demand["interest_revision"]),
	})


## Withdraw one client session entirely (detach / disconnect).
func withdraw_client_demand(gateway_session_id: String) -> Dictionary:
	if not _demands_by_session.has(gateway_session_id):
		return _failure("UNKNOWN_CLIENT_DEMAND", {"gateway_session_id": gateway_session_id})
	var previous: Dictionary = _worlds_of(_demands_by_session[gateway_session_id])
	_demands_by_session.erase(gateway_session_id)
	_counters["demands_withdrawn"] = int(_counters["demands_withdrawn"]) + 1
	var deltas: Array = _recompute(previous)
	return _success({"deltas": deltas})


## One bounded pump-cycle step: retire up to retire_batch_per_cycle stale
## upstream subscriptions. Deterministic retirement order (sorted world ids).
func run_maintenance_cycle() -> Dictionary:
	var remaining: Array[String] = []
	for world_id in _stale_worlds.keys():
		remaining.append(String(world_id))
	remaining.sort()
	var retired: Array[String] = []
	for index in range(mini(remaining.size(), _retire_batch_per_cycle)):
		var world_id: String = remaining[index]
		if _has_current_subscriber(world_id):
			# Demand returned before retirement ran: no longer stale.
			_stale_worlds.erase(world_id)
			continue
		_stale_worlds.erase(world_id)
		retired.append(world_id)
		_counters["stale_retired"] = int(_counters["stale_retired"]) + 1
	return _success({"retired": retired, "remaining_stale": _stale_worlds.keys()})


## Upstream acknowledged the withdrawal (source loss confirmation etc.).
func confirm_withdrawn(world_id: String) -> Dictionary:
	if not _stale_worlds.has(world_id):
		return _failure("NOT_STALE", {"world_id": world_id})
	_stale_worlds.erase(world_id)
	return _success({"world_id": world_id})


func mark_served(source_authority_id: String, interest_revision: int) -> Dictionary:
	var check: Dictionary = GatewayUtilsScript.require_id(
			{"source_authority_id": source_authority_id}, "source_authority_id", "authority")
	if not bool(check.get("success", false)):
		return check
	var revision_check: Dictionary = GatewayUtilsScript.require_positive_integer(
			{"interest_revision": interest_revision}, "interest_revision")
	if not bool(revision_check.get("success", false)):
		return revision_check
	var current := int(_last_served_revision_by_source.get(source_authority_id, 0))
	if interest_revision < current:
		return _failure("STALE_SERVED_REVISION", {"current": current})
	_last_served_revision_by_source[source_authority_id] = interest_revision
	return _success({"source_authority_id": source_authority_id})


## Per-upstream stream sets: source_authority_id -> sorted world ids it MUST
## stream right now (deduplicated across every client demand).
func upstream_stream_sets() -> Dictionary:
	var by_source: Dictionary = {}
	for world_id_value in _source_by_world.keys():
		var world_id := String(world_id_value)
		if _stale_worlds.has(world_id):
			continue
		var source := String(_source_by_world[world_id])
		if not by_source.has(source):
			by_source[source] = []
		(by_source[source] as Array).append(world_id)
	for source_value in by_source.keys():
		(by_source[source_value] as Array).sort()
	return by_source


func plan_for_world(world_id: String) -> Dictionary:
	if not _plans_by_world.has(world_id):
		return _failure("NO_PLAN_FOR_WORLD", {"world_id": world_id})
	return _success({"plan": _plans_by_world[world_id]})


func get_plans() -> Array:
	return _plans_by_world.values()


## Worlds still subscribed upstream although NO client demands them anymore.
func stale_subscription_worlds() -> Array[String]:
	var worlds: Array[String] = []
	for world_id in _stale_worlds.keys():
		worlds.append(String(world_id))
	worlds.sort()
	return worlds


func stale_subscription_count() -> int:
	return _stale_worlds.size()


func last_served_interest_revision(source_authority_id: String) -> int:
	return int(_last_served_revision_by_source.get(source_authority_id, 0))


func get_report() -> Dictionary:
	var plans: Array = []
	for world_id in _plans_by_world.keys().slice(0, mini(_plans_by_world.size(), 64)):
		plans.append(String(world_id))
	return {
		"schema": SCHEMA,
		"counters": _counters.duplicate(true),
		"client_demand_count": _demands_by_session.size(),
		"active_plan_count": _plans_by_world.size(),
		"stale_subscription_count": _stale_worlds.size(),
		"stale_subscription_worlds": stale_subscription_worlds(),
		"upstream_stream_sets": upstream_stream_sets(),
		"last_served_interest_revisions": _last_served_revision_by_source.duplicate(true),
	}


## ---- internals ---------------------------------------------------------------


## Recompute aggregated plans from current demands vs the PREVIOUS per-session
## snapshot; emit deduplicated subscribe/unsubscribe deltas.
func _recompute(previous: Dictionary) -> Array:
	var next_worlds: Dictionary = _aggregate_current()
	var deltas: Array = []

	for world_id_value in next_worlds.keys():
		var world_id := String(world_id_value)
		var entry: Dictionary = next_worlds[world_id]
		if not _plans_by_world.has(world_id):
			deltas.append({
				"action": "SUBSCRIBE",
				"world_id": world_id,
				"source_authority_id": String(entry["source_authority_id"]),
				"subscriber_sessions": entry["subscriber_sessions"],
			})
			_counters["subscribe_deltas_emitted"] = int(_counters["subscribe_deltas_emitted"]) + 1
			_stale_worlds.erase(world_id)
		else:
			# Same world already subscribed: DEDUP across clients — the delta
			# only records the merged subscriber surface.
			_counters["deduplicated_demands"] = int(_counters["deduplicated_demands"]) + 1
		_upsert_plan(world_id, entry)

	for world_id_value in previous.keys():
		var world_id := String(world_id_value)
		if next_worlds.has(world_id):
			continue
		if _plans_by_world.has(world_id):
			_plans_by_world.erase(world_id)
			_stale_worlds[world_id] = true
			deltas.append({
				"action": "UNSUBSCRIBE",
				"world_id": world_id,
				"source_authority_id": String(previous[world_id]),
				"subscriber_sessions": [],
			})
			_counters["unsubscribe_deltas_emitted"] = int(_counters["unsubscribe_deltas_emitted"]) + 1

	# Rebuild the flat world->source map for stream-set accounting.
	var source_map: Dictionary = {}
	for world_id_value in next_worlds.keys():
		source_map[String(world_id_value)] = String(next_worlds[String(world_id_value)]["source_authority_id"])
	_source_by_world = source_map
	return deltas


func _aggregate_current() -> Dictionary:
	var aggregated: Dictionary = {}
	for gateway_session_id in _demands_by_session.keys():
		var demand: Dictionary = _demands_by_session[gateway_session_id]
		for world_id_value in (demand["worlds"] as Dictionary).keys():
			var world_id := String(world_id_value)
			var source := String((demand["worlds"] as Dictionary)[world_id_value])
			if not aggregated.has(world_id):
				aggregated[world_id] = {
					"source_authority_id": source,
					"subscriber_sessions": [],
					"interest_revision": 0,
					"graph_revision": int(demand["graph_revision"]),
				}
			var entry: Dictionary = aggregated[world_id]
			var sessions: Array = entry["subscriber_sessions"]
			if not sessions.has(gateway_session_id):
				sessions.append(gateway_session_id)
			entry["interest_revision"] = maxi(int(entry["interest_revision"]), int(demand["interest_revision"]))
			entry["graph_revision"] = maxi(int(entry["graph_revision"]), int(demand["graph_revision"]))
	for entry_value in aggregated.values():
		(entry_value["subscriber_sessions"] as Array).sort()
	return aggregated


func _upsert_plan(world_id: String, entry: Dictionary) -> void:
	var plan := PlanScript.create(
			_plan_id(world_id),
			world_id,
			DEFAULT_SOURCE_ROLE,
			REPRESENTATION_OR_LOD,
			entry["subscriber_sessions"],
			DEFAULT_AGGREGATE_PRIORITY,
			{"bytes_per_second": DEFAULT_BYTES_PER_SECOND},
			int(entry["graph_revision"]),
			int(entry["interest_revision"]),
			true)
	if bool(PlanScript.validate(plan).get("success", false)):
		_plans_by_world[world_id] = plan


func _plan_id(world_id: String) -> String:
	return "interest-plan/eg4/%s" % String(world_id).replace("/", "-").substr(0, 120)


func _has_current_subscriber(world_id: String) -> bool:
	for gateway_session_id in _demands_by_session.keys():
		if (_worlds_of(_demands_by_session[gateway_session_id])).has(world_id):
			return true
	return false


static func _worlds_of(demand: Dictionary) -> Dictionary:
	if demand.is_empty():
		return {}
	var output: Dictionary = {}
	var worlds: Dictionary = demand.get("worlds", {})
	for world_id in worlds.keys():
		output[String(world_id)] = String(worlds[world_id])
	return output


func _validate_demand(demand: Dictionary) -> Dictionary:
	for field in ["gateway_session_id", "interest_revision", "graph_revision", "worlds"]:
		if not demand.has(field):
			return _failure("MISSING_DEMAND_FIELD", {"field": field})
	var session_check: Dictionary = GatewayUtilsScript.require_id(demand, "gateway_session_id", "gateway-session")
	if not bool(session_check.get("success", false)):
		return session_check
	for field in ["interest_revision", "graph_revision"]:
		var revision_check: Dictionary = GatewayUtilsScript.require_positive_integer(demand, field)
		if not bool(revision_check.get("success", false)):
			return revision_check
	if typeof(demand["worlds"]) != TYPE_ARRAY:
		return _failure("INVALID_DEMAND_WORLDS", {})
	var seen: Dictionary = {}
	for raw_entry in Array(demand["worlds"]):
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return _failure("INVALID_DEMAND_WORLD_ENTRY", {})
		var entry: Dictionary = Dictionary(raw_entry)
		var world_check: Dictionary = GatewayUtilsScript.require_id(entry, "world_id", "world")
		if not bool(world_check.get("success", false)):
			return world_check
		var source_check: Dictionary = GatewayUtilsScript.require_id(entry, "source_authority_id", "authority")
		if not bool(source_check.get("success", false)):
			return source_check
		var world_id := String(entry["world_id"])
		if seen.has(world_id):
			return _failure("DUPLICATE_DEMAND_WORLD", {"world_id": world_id})
		seen[world_id] = true
	return _success({})


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
