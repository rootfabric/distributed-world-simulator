extends SceneTree

## EG4 L0 unit proof for the interest aggregator.
## Predicate exercised here (re-proven end to end in the aggregation L1):
##   - INTEREST_AGGREGATION_PASS: per-client demands fold into ONE
##     AggregatedInterestPlan per upstream world, DEDUPLICATED across clients;
##     subscribe/unsubscribe deltas fire exactly on demand changes; per-source
##     last-served revisions are tracked; and after demand withdrawal a bounded
##     number of maintenance cycles drains stale upstream subscriptions to ZERO.

const AggregatorScript = preload("res://scripts/network/gateway/runtime/eg4_interest_aggregator.gd")
const PlanScript = preload("res://scripts/network/gateway/aggregated_interest_plan.gd")
const Generator = preload("res://tools/network/eg4_world_fixture_generator.gd")

var assertions := 0
var failures: Array[String] = []
var _started_ms: int = 0


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg4-aggregator][FAIL] %s" % message)


func _process(_delta: float) -> bool:
	if _started_ms > 0 and Time.get_ticks_msec() - _started_ms > 60000:
		print("[eg4-aggregator] WATCHDOG TIMEOUT")
		quit(1)
		return true
	return false


func _world_entry(index: int, authority: String) -> Dictionary:
	return {"world_id": Generator.world_id_at(index), "source_authority_id": authority}


func _demand(gateway_session_id: String, entries: Array, interest_revision: int) -> Dictionary:
	return {
		"gateway_session_id": gateway_session_id,
		"interest_revision": interest_revision,
		"graph_revision": 1,
		"worlds": entries,
	}


func _collect_actions(deltas: Array) -> Dictionary:
	var actions := {}
	for delta_value in deltas:
		var delta: Dictionary = delta_value
		var key := "%s:%s" % [String(delta["action"]), String(delta["world_id"])]
		actions[key] = true
	return actions


func _init() -> void:
	_started_ms = Time.get_ticks_msec()
	var aggregator = AggregatorScript.new()
	var configured: Dictionary = aggregator.configure({})
	_assert(bool(configured.get("success", false)), "aggregator configure failed")

	var source_a := "authority/eg4-sim-a"
	var source_b := "authority/eg4-sim-b"
	var world_0 := Generator.world_id_at(0)
	var world_1 := Generator.world_id_at(1)
	var world_2 := Generator.world_id_at(2)

	# --- first client demand: SUBSCRIBE deltas for every world -----------------
	var first: Dictionary = aggregator.set_client_demand(_demand("gateway-session/eg4/agg-one", [
		_world_entry(0, source_a), _world_entry(1, source_b),
	], 3))
	_assert(bool(first.get("success", false)), "first demand rejected: %s" % str(first.get("error_code", first)))
	var first_actions := _collect_actions(first["details"]["deltas"])
	_assert(bool(first_actions.get("SUBSCRIBE:%s" % world_0, false)) and bool(first_actions.get("SUBSCRIBE:%s" % world_1, false)),
			"first demand did not subscribe both worlds")

	# --- second client shares ONE world: deduplicated, no duplicate subscribe --
	var second: Dictionary = aggregator.set_client_demand(_demand("gateway-session/eg4/agg-two", [
		_world_entry(0, source_a), _world_entry(2, source_b),
	], 5))
	_assert(bool(second.get("success", false)), "second demand rejected")
	var second_actions := _collect_actions(second["details"]["deltas"])
	_assert(not second_actions.has("SUBSCRIBE:%s" % world_0),
			"shared world produced a DUPLICATE subscribe delta instead of deduping")
	_assert(bool(second_actions.has("SUBSCRIBE:%s" % world_2)), "new world was not subscribed")

	var shared_plan: Dictionary = aggregator.plan_for_world(world_0)
	_assert(bool(shared_plan.get("success", false)), "no aggregated plan for the shared world")
	var plan: Dictionary = shared_plan["details"]["plan"]
	_assert(bool(PlanScript.validate(plan).get("success", false)), "aggregated plan failed contract validation")
	if not plan.is_empty():
		var subscribers: Array = plan["subscriber_sessions"]
		_assert(subscribers.size() == 2, "shared plan did not merge BOTH subscriber sessions: %s" % str(subscribers))
		_assert(int(plan["interest_revision"]) == 5, "plan did not advance to the max demand revision")
		_assert(String(plan["source_role"]) == "PROJECTION" and bool(plan["read_only"]),
				"aggregated plan must stay read-only PROJECTION demand")

	# --- stream sets group by upstream source -----------------------------------
	var stream_sets: Dictionary = aggregator.upstream_stream_sets()
	var worlds_for_a: Array = stream_sets.get(source_a, [])
	var worlds_for_b: Array = stream_sets.get(source_b, [])
	_assert((worlds_for_a as Array).size() == 1 and String(worlds_for_a[0]) == world_0,
			"source A stream set wrong: %s" % str(worlds_for_a))
	_assert((worlds_for_b as Array).size() == 2, "source B stream set wrong: %s" % str(worlds_for_b))

	# --- one of two subscribers withdraws: shared world keeps its subscription --
	var partial: Dictionary = aggregator.withdraw_client_demand("gateway-session/eg4/agg-two")
	_assert(bool(partial.get("success", false)), "partial withdraw failed")
	var partially_unsubscribed: Array[String] = []
	for delta_value in partial["details"]["deltas"]:
		var delta: Dictionary = delta_value
		if String(delta["action"]) == "UNSUBSCRIBE":
			partially_unsubscribed.append(String(delta["world_id"]))
	_assert(not partially_unsubscribed.has(world_0),
			"withdrawing ONE of TWO subscribers dropped the SHARED world upstream")
	_assert(partially_unsubscribed.has(world_2),
			"the exclusive world of the withdrawn client was not released")
	var shared_still_planned: Dictionary = aggregator.plan_for_world(world_0)
	_assert(bool(shared_still_planned.get("success", false)), "shared plan vanished while one subscriber remains")

	# --- last subscriber withdraws: unsubscribe + STALE, bounded drain to zero ---
	var final_withdraw: Dictionary = aggregator.withdraw_client_demand("gateway-session/eg4/agg-one")
	_assert(bool(final_withdraw.get("success", false)), "final withdraw failed")
	var unsubscribed_worlds: Array[String] = []
	for delta_value in final_withdraw["details"]["deltas"]:
		var delta: Dictionary = delta_value
		if String(delta["action"]) == "UNSUBSCRIBE":
			unsubscribed_worlds.append(String(delta["world_id"]))
	_assert(unsubscribed_worlds.size() >= 2, "last withdrawal lost unsubscribe deltas: %s" % str(unsubscribed_worlds))
	_assert(aggregator.stale_subscription_count() >= 2,
			"withdrawn worlds are not tracked as stale upstream subscriptions")
	var stale_worlds: Array = aggregator.stale_subscription_worlds()
	_assert(stale_worlds.has(world_0),
			"the last withdrawal did not park the shared world as a stale subscription")

	# Bounded pump cycles: retire batch of 2 per cycle -> eventually zero.
	var cycles := 0
	while aggregator.stale_subscription_count() > 0 and cycles < 100:
		cycles += 1
		aggregator.run_maintenance_cycle()
	_assert(aggregator.stale_subscription_count() == 0,
			"stale subscriptions did not reach ZERO within bounded cycles")
	_assert(cycles <= 3, "stale drain took too many cycles: %d" % cycles)

	# --- per-source last-served revisions ----------------------------------------
	var served: Dictionary = aggregator.mark_served(source_a, 9)
	_assert(bool(served.get("success", false)), "mark_served rejected")
	_assert(aggregator.last_served_interest_revision(source_a) == 9, "last-served revision not tracked")
	var regress: Dictionary = aggregator.mark_served(source_a, 8)
	_assert(String(regress.get("error_code", "")) == "STALE_SERVED_REVISION",
			"served revision regression accepted")

	_finish()


func _finish() -> void:
	var ok := failures.is_empty()
	var summary := {
		"test": "eg4_interest_aggregator_l0",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicate": "INTEREST_AGGREGATION_PASS" if ok else "PREDICATE_NOT_DEMONSTRATED",
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg4-aggregator] AGGREGATOR PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg4-aggregator] AGGREGATOR FAIL")
		quit(1)
