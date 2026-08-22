extends SceneTree

## EG4 L0/L1 unit proof for the graph-driven view planner.
## Predicates exercised here (and re-proven end to end in the aggregation L1):
##   - WORLD_GRAPH_DRIVEN_VIEW_PLANNING_PASS: the planned ClientWorldView is a
##     pure function of the GatewayWorldGraphSnapshot + subscription demand —
##     NOT a hardcoded list (different homes/edges change the plan).
##   - EIGHT_WORLD_PLANNER_WALK_PASS: one deterministic walk over the >=100
##     world known-world fixture visits at least required_machine_walk_worlds=8
##     distinct worlds.
##   - Fail-closed stale graph revision: planning from a stale cache errors.

const Planner = preload("res://scripts/network/gateway/runtime/eg4_view_planner.gd")
const SnapshotScript = preload("res://scripts/network/gateway/gateway_world_graph_snapshot.gd")
const ViewScript = preload("res://scripts/network/gateway/client_world_view.gd")
const Generator = preload("res://tools/network/eg4_world_fixture_generator.gd")

const REQUIRED_MACHINE_WALK_WORLDS := 8
const FIXTURE_PATH := "res://tests/network/fixtures/eg4_world_graph_fixture.json"

var assertions := 0
var failures: Array[String] = []
var _started_ms: int = 0


## Watchdog: a script error would abort _init before quit() and hang the
## harness — fail loudly instead of hanging.
func _process(_delta: float) -> bool:
	if _started_ms > 0 and Time.get_ticks_msec() - _started_ms > 120000:
		print("[eg4-planner] WATCHDOG TIMEOUT")
		quit(1)
		return true
	return false


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg4-planner][FAIL] %s" % message)


func _demand(home_world_id: String, interest_revision: int, graph_revision: int) -> Dictionary:
	return {
		"gateway_session_id": "gateway-session/eg4/planner",
		"home_world_id": home_world_id,
		"reference_frame_id": "reference-frame/eg4/planner",
		"interest_revision": interest_revision,
		"expected_graph_revision": graph_revision,
	}


func _init() -> void:
	_started_ms = Time.get_ticks_msec()
	var fixture: Dictionary = _read_fixture()
	_assert(not fixture.is_empty(), "known-world fixture missing")
	var snapshot: Dictionary = Dictionary(fixture.get("snapshot", {}))
	_assert(bool(SnapshotScript.validate(snapshot).get("success", false)), "fixture snapshot invalid")
	var graph_revision := int(snapshot.get("graph_revision", 0))

	# --- graph-driven planning on the big fixture -----------------------------
	var home := Generator.home_world_id(0)
	var planned: Dictionary = Planner.plan_view(snapshot, _demand(home, 7, graph_revision))
	_assert(bool(planned.get("success", false)), "plan_view failed on fixture: %s" % str(planned.get("error_code", planned)))
	var entries: Array = planned.get("details", {}).get("entries", [])
	_assert(not entries.is_empty(), "planner produced no entries")
	if not entries.is_empty():
		_assert(String(entries[0]["world_id"]) == home and String(entries[0]["source_role"]) == "ACTIVE",
				"home world must be the single ACTIVE anchor")
		var non_active_ok := true
		for index in range(1, entries.size()):
			if String(entries[index]["source_role"]) != "PROJECTION":
				non_active_ok = false
		_assert(non_active_ok, "non-home entries must be PROJECTION sources")
		_assert(int(entries[0]["interest_revision"]) == 7, "entries lost the demand interest_revision")

	# --- EIGHT_WORLD_PLANNER_WALK_PASS ----------------------------------------
	var walk: Dictionary = Planner.walk_worlds(snapshot, home)
	_assert(bool(walk.get("success", false)), "walk failed on fixture")
	var visited: Array = walk.get("details", {}).get("visited", [])
	var distinct := {}
	for value in visited:
		distinct[String(value)] = true
	_assert(distinct.size() >= REQUIRED_MACHINE_WALK_WORLDS,
			"single deterministic walk visited only %d distinct worlds (need >= %d)" % [distinct.size(), REQUIRED_MACHINE_WALK_WORLDS])
	_assert(visited.size() == distinct.size(), "walk revisited worlds inside one pass")

	# --- determinism -----------------------------------------------------------
	var replanned: Dictionary = Planner.plan_view(snapshot, _demand(home, 7, graph_revision))
	_assert(JSON.stringify(replanned.get("details", {})) == JSON.stringify(planned.get("details", {})),
			"planning is not deterministic for identical snapshot + demand")

	# --- driven by the GRAPH, not hardcoded lists ------------------------------
	# 1. A different home world changes the plan.
	var other_home := Generator.world_id_at(50)
	var other_plan: Dictionary = Planner.plan_view(snapshot, _demand(other_home, 7, graph_revision))
	_assert(bool(other_plan.get("success", false)), "second home failed to plan")
	_assert(String(other_plan["details"]["entries"][0]["world_id"]) == other_home,
			"plan ignored the requested home world")
	_assert(JSON.stringify(other_plan["details"]["entries"]) != JSON.stringify(entries),
			"different home produced an identical plan: list looks hardcoded")
	# 2. A handcrafted graph with known topology yields exactly the BFS order.
	var tiny := _tiny_snapshot()
	var tiny_graph_revision := int(tiny["graph_revision"])
	var tiny_plan: Dictionary = Planner.plan_view(tiny, _demand("world/eg4/tiny-a", 1, tiny_graph_revision))
	_assert(bool(tiny_plan.get("success", false)), "tiny graph plan failed")
	var tiny_order: Array[String] = []
	for entry_value in tiny_plan["details"]["entries"]:
		tiny_order.append(String(entry_value["world_id"]))
	# adjacency sorted canonically: b before c; depth budget respected.
	_assert(tiny_order == ["world/eg4/tiny-a", "world/eg4/tiny-b", "world/eg4/tiny-c"],
			"handcrafted BFS order broken: %s" % str(tiny_order))
	# 3. Cutting the only edge removes downstream worlds from the plan.
	var cut := _tiny_snapshot_cut_bc()
	var cut_plan: Dictionary = Planner.plan_view(cut, _demand("world/eg4/tiny-a", 1, int(cut["graph_revision"])))
	_assert(bool(cut_plan.get("success", false)), "cut graph plan failed")
	var cut_order: Array[String] = []
	for entry_value in cut_plan["details"]["entries"]:
		cut_order.append(String(entry_value["world_id"]))
	_assert(cut_order == ["world/eg4/tiny-a"], "plan did not follow relation edges: %s" % str(cut_order))

	# --- fail-closed behaviors --------------------------------------------------
	var stale: Dictionary = Planner.plan_view(snapshot, _demand(home, 7, graph_revision + 1))
	_assert(bool(stale.get("success", false)) == false and String(stale.get("error_code", "")) == "STALE_GRAPH_REVISION",
			"stale graph revision must fail closed")
	var behind: Dictionary = Planner.plan_view(snapshot, _demand(home, 7, graph_revision + 12345))
	_assert(String(behind.get("error_code", "")) == "STALE_GRAPH_REVISION",
			"a demand bound to any other graph revision must fail closed")
	var unknown: Dictionary = Planner.walk_worlds(snapshot, "world/eg4/does-not-exist")
	_assert(String(unknown.get("error_code", "")) == "UNKNOWN_HOME_WORLD", "unknown home world must fail explicitly")
	var bad_snapshot: Dictionary = Planner.plan_view({"schema": "nope"}, _demand(home, 7, 1))
	_assert(String(bad_snapshot.get("error_code", "")) == "INVALID_GRAPH_SNAPSHOT", "invalid snapshot must fail closed")

	# --- full ClientWorldView DTO ------------------------------------------------
	var built: Dictionary = Planner.build_client_world_view(
			snapshot, _demand(home, 9, graph_revision), 3, "world-view/eg4/planner")
	_assert(bool(built.get("success", false)), "build_client_world_view failed: %s" % str(built.get("error_code", built)))
	var view: Dictionary = built.get("details", {}).get("view", {})
	_assert(bool(ViewScript.validate(view).get("success", false)), "built view failed contract validation")
	if not view.is_empty():
		_assert(int(view["graph_revision"]) == graph_revision and int(view["interest_revision"]) == 9,
				"view lost its revisions")
		_assert((view["warm_worlds"] as Array).size() > 0 and (view["projection_streams"] as Array).size() >= (view["warm_worlds"] as Array).size(),
				"warm/projection partition implausible")
		var newer_check: Dictionary = ViewScript.validate_newer(
				ViewScript.create(String(view["view_id"]), String(view["gateway_session_id"]),
						String(view["anchor_world_id"]), String(view["reference_frame_id"]),
						String(view["active_authority_world"]), view["warm_worlds"], view["projection_streams"],
						view["macro_sources"], int(view["graph_revision"]), int(view["view_revision"]) + 1,
						int(view["interest_revision"]) + 1),
				view)
		_assert(bool(newer_check.get("success", false)), "advancing view revisions rejected: %s" % String(newer_check.get("error_code", "")))

	_finish()


func _tiny_snapshot() -> Dictionary:
	return SnapshotScript.create(
			"world-graph/eg4-tiny",
			1,
			5,
			[
				_world_descriptor("world/eg4/tiny-a"),
				_world_descriptor("world/eg4/tiny-b"),
				_world_descriptor("world/eg4/tiny-c"),
			],
			[
				_relation("world-relation/eg4/tiny-ab", "world/eg4/tiny-a", "world/eg4/tiny-b", "NEIGHBOR"),
				_relation("world-relation/eg4/tiny-ac", "world/eg4/tiny-a", "world/eg4/tiny-c", "NEIGHBOR"),
				_relation("world-relation/eg4/tiny-bc", "world/eg4/tiny-b", "world/eg4/tiny-c", "OVERLAP"),
			])


func _tiny_snapshot_cut_bc() -> Dictionary:
	# Same worlds, ZERO relations: nothing but the anchor may be reachable.
	return SnapshotScript.create(
			"world-graph/eg4-tiny-cut",
			1,
			6,
			[
				_world_descriptor("world/eg4/tiny-a"),
				_world_descriptor("world/eg4/tiny-b"),
				_world_descriptor("world/eg4/tiny-c"),
			],
			[])


func _world_descriptor(world_id: String) -> Dictionary:
	const WorldDescriptorScript = preload("res://scripts/network/gateway/world_descriptor.gd")
	return WorldDescriptorScript.create(
			world_id, "planetary_region_test", "reference-frame/eg4/test",
			{"kind": "grid_partition", "partition": 0},
			{"kind": "sphere", "radius": 10.0},
			"authority-subject/eg4/test",
			[], {"read_only": true, "allows_mutation": false},
			[], {"neighbor_depth": 1}, {"max_projection_neighbors": 2}, 1)


func _relation(relation_id: String, world_a: String, world_b: String, kind_value: String) -> Dictionary:
	const WorldRelationScript = preload("res://scripts/network/gateway/world_relation.gd")
	return WorldRelationScript.create(
			relation_id, world_a, world_b, kind_value,
			{"id": "eg4-test-transition-region", "kind": "transition_region"},
			{"kind": "shared_reference_frame"},
			{"read_only": true, "allows_mutation": false}, 1)


func _read_fixture() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	return parsed if parsed is Dictionary else {}


func _finish() -> void:
	var ok := failures.is_empty()
	var summary := {
		"test": "eg4_view_planner_l0",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicate": "WORLD_GRAPH_DRIVEN_VIEW_PLANNING_PASS+EIGHT_WORLD_PLANNER_WALK_PASS" if ok else "PREDICATE_NOT_DEMONSTRATED",
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg4-planner] PLANNER PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg4-planner] PLANNER FAIL")
		quit(1)
