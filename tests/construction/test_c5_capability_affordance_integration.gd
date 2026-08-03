extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C4FixtureScript = preload("res://tests/construction/fixtures/c4_reusable_table_fixture.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c5_affordance_fixture.gd")
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const BuildPlanStoreScript = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const BuildProcessScript = preload("res://scripts/construction/build/construction_build_process.gd")
const BehaviorStoreScript = preload("res://scripts/construction/behavior/construction_behavior_profile_store.gd")
const AgentScript = preload("res://scripts/construction/behavior/construction_affordance_agent.gd")
const ResolverScript = preload("res://scripts/construction/behavior/construction_affordance_resolver.gd")
const QueryScript = preload("res://scripts/construction/behavior/construction_affordance_query.gd")
const ProfileScript = preload("res://scripts/construction/behavior/construction_behavior_profile.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_c4_stage_execution_compiles_behaviors()
	_test_agent_uses_unknown_construct_semantically()
	_test_actor_capability_gates()
	_test_damage_invalidation_and_rebuild()
	_test_deterministic_resolution()
	_finish()


func _test_c4_stage_execution_compiles_behaviors() -> void:
	var compiled: Dictionary = FixtureScript.compiled_table("stage-execution", {
		"parameter/finish": "painted",
		"parameter/load-rating-kg": 150.0,
	})
	var build_plan: Dictionary = compiled.build_plan
	var adapter = AdapterScript.new()
	_assert_ok(adapter.setup(C4FixtureScript.source_projections("stage-execution")), "C5 authoritative adapter setup failed")
	var build_store = BuildPlanStoreScript.new()
	_assert_ok(build_store.setup(), "C5 BuildPlan store setup failed")
	var process = BuildProcessScript.new()
	_assert_ok(process.setup(adapter, build_store), "C5 BuildProcess setup failed")
	_assert_ok(process.register_plan(build_plan), "C5 BuildPlan registration failed")
	var behavior_store = BehaviorStoreScript.new()
	_assert_ok(behavior_store.setup(), "C5 behavior store setup failed")

	_assert_ok(process.advance_stage(String(build_plan.build_plan_id), 0, "operation/c5/stages/foundation", ["FASTEN"]), "C5 foundation failed")
	var foundation: Dictionary = adapter.get_construct_snapshot(String(build_plan.construct_id))
	var foundation_behavior: Dictionary = behavior_store.compile_snapshot(foundation)
	_assert_ok(foundation_behavior, "Foundation behavior compilation failed")
	_assert(not bool(foundation_behavior.profile.operational), "Foundation profile became operational")
	_assert(foundation_behavior.profile.capabilities.is_empty(), "Foundation profile exposed capability")
	_assert(foundation_behavior.profile.affordances.is_empty(), "Foundation profile exposed affordance")
	_assert(int(foundation_behavior.profile.construct_revision) == 0, "Foundation profile revision mismatch")

	_assert_ok(process.advance_stage(String(build_plan.build_plan_id), 1, "operation/c5/stages/frame", ["FASTEN"]), "C5 frame failed")
	var frame: Dictionary = adapter.get_construct_snapshot(String(build_plan.construct_id))
	var frame_behavior: Dictionary = behavior_store.compile_snapshot(frame)
	_assert_ok(frame_behavior, "Frame behavior compilation failed")
	_assert(frame_behavior.profile.capabilities.is_empty(), "Frame profile exposed capability before commissioning")
	_assert(frame_behavior.profile.affordances.is_empty(), "Frame profile exposed affordance before commissioning")
	_assert(int(frame_behavior.profile.construct_revision) == 1, "Frame profile revision mismatch")

	_assert_ok(process.advance_stage(String(build_plan.build_plan_id), 2, "operation/c5/stages/commission", ["INSPECT"]), "C5 commissioning failed")
	var completed: Dictionary = adapter.get_construct_snapshot(String(build_plan.construct_id))
	var completed_behavior: Dictionary = behavior_store.compile_snapshot(completed)
	_assert_ok(completed_behavior, "Completed behavior compilation failed")
	_assert(bool(completed_behavior.profile.operational), "Completed behavior profile not operational")
	_assert(completed_behavior.profile.capabilities.size() == 4, "Completed stage capability count mismatch")
	_assert(completed_behavior.profile.affordances.size() == 3, "Completed stage affordance count mismatch")
	_assert(int(completed_behavior.profile.construct_revision) == 2, "Completed profile revision mismatch")
	_assert(behavior_store.get_generation() == 3, "Stage-by-stage behavior generation mismatch")
	var replay: Dictionary = behavior_store.compile_snapshot(completed)
	_assert_ok(replay, "Completed profile replay failed")
	_assert(bool(replay.replay), "Completed profile replay not detected")
	_assert(behavior_store.get_generation() == 3, "Completed profile replay advanced generation")

	var agent = AgentScript.new()
	_assert_ok(agent.setup(behavior_store, "actor/c5-stage-user", ["MANIPULATE_ITEM"]), "Stage agent setup failed")
	var action: Dictionary = agent.choose_action(
		"affordance-query/c5/stage/place",
		"PLACE_ITEM",
		{"minimum_properties": {"load_rating_kg": 140.0}, "require_port_target": true}
	)
	_assert_ok(action, "Agent did not discover completed staged table")
	_assert(String(action.selected.construct_id) == String(build_plan.construct_id), "Agent selected wrong staged construct")
	_assert(String(action.selected.affordance.target_port_id) == "port/work-surface", "Agent selected nonsemantic target")
	_assert(float(action.selected.affordance.parameters.load_rating_kg) == 150.0, "Agent lost C4 parameter in C5 action")


func _test_agent_uses_unknown_construct_semantically() -> void:
	var store = BehaviorStoreScript.new()
	_assert_ok(store.setup(), "Unknown-object behavior store setup failed")
	var first: Dictionary = FixtureScript.table_snapshot("unknown-a", {
		"parameter/finish": "natural",
		"parameter/load-rating-kg": 100.0,
	})
	var second: Dictionary = FixtureScript.table_snapshot("unknown-b", {
		"parameter/finish": "painted",
		"parameter/load-rating-kg": 125.0,
	})
	_assert_ok(store.compile_snapshot(second), "Second unknown table profile failed")
	_assert_ok(store.compile_snapshot(first), "First unknown table profile failed")
	var agent = AgentScript.new()
	_assert_ok(agent.setup(store, "actor/c5-generic-agent", ["INSTALL_COMPONENT", "MANIPULATE_ITEM"]), "Generic affordance agent setup failed")
	var selected: Dictionary = agent.choose_action(
		"affordance-query/c5/unknown/high-load-painted",
		"PLACE_ITEM",
		{
			"minimum_properties": {"load_rating_kg": 120.0},
			"exact_properties": {"finish": "painted"},
			"require_port_target": true,
		}
	)
	_assert_ok(selected, "Generic agent did not find suitable unknown table")
	_assert(String(selected.selected.construct_id) == String(second.construct_id), "Generic agent ignored semantic property constraints")
	_assert(not selected.selected.has("prefab_name"), "Affordance result leaked prefab dependency")
	_assert(not selected.selected.has("display_name"), "Affordance result depended on display name")
	_assert(String(selected.selected.capability.capability_kind) == "PLACE_ITEMS", "Generic agent selected wrong capability")
	_assert(String(selected.selected.affordance.action_kind) == "PLACE_ITEM", "Generic agent selected wrong action")
	_assert(String(selected.selected.affordance.target_part_id).begins_with("part/"), "Generic agent action lacks concrete provider part")
	_assert(String(selected.selected.profile_checksum).length() == 64, "Generic agent result lacks profile provenance")

	var mount: Dictionary = agent.choose_action("affordance-query/c5/unknown/mount", "MOUNT_ITEM")
	_assert_ok(mount, "Generic agent did not discover mount point")
	_assert(String(mount.selected.affordance.target_port_id) == "port/service-anchor", "Generic agent selected wrong mount port")
	_assert(String(mount.selected.capability.capability_kind) == "MOUNTING_SURFACE", "Generic mount capability mismatch")


func _test_actor_capability_gates() -> void:
	var store = BehaviorStoreScript.new()
	_assert_ok(store.setup(), "Actor-gate behavior store setup failed")
	_assert_ok(store.compile_snapshot(FixtureScript.all_affordance_snapshot("actor-gates")), "All-affordance profile publish failed")
	var unskilled = AgentScript.new()
	_assert_ok(unskilled.setup(store, "actor/c5-unskilled", []), "Unskilled agent setup failed")
	for pair in [
		["PLACE_ITEM", "affordance-query/c5/gate/place"],
		["MOUNT_ITEM", "affordance-query/c5/gate/mount"],
		["OPEN_CONTAINER", "affordance-query/c5/gate/open"],
		["SIT", "affordance-query/c5/gate/sit"],
		["CLIMB", "affordance-query/c5/gate/climb"],
		["USE_WORKSTATION", "affordance-query/c5/gate/workstation"],
	]:
		_assert_error(unskilled.choose_action(String(pair[1]), String(pair[0])), "CONSTRUCTION_AFFORDANCE_NOT_FOUND", "Unskilled agent received %s" % String(pair[0]))

	var skilled = AgentScript.new()
	_assert_ok(skilled.setup(store, "actor/c5-skilled", [
		"INSTALL_COMPONENT",
		"INTERACT",
		"LOCOMOTION",
		"LOCOMOTION_CLIMB",
		"MANIPULATE_ITEM",
		"OPERATE_WORKSTATION",
	]), "Skilled agent setup failed")
	for pair in [
		["PLACE_ITEM", "port/work-surface"],
		["MOUNT_ITEM", "port/service-anchor"],
		["OPEN_CONTAINER", "port/container-access"],
		["STORE_ITEM", "port/container-access"],
		["TAKE_ITEM", "port/container-access"],
		["SIT", "port/seat"],
		["CLIMB", "port/climb-rung"],
		["USE_WORKSTATION", "port/workstation"],
		["USE_WORK_SURFACE", "port/work-surface"],
	]:
		var action: Dictionary = skilled.choose_action(
			"affordance-query/c5/skilled/%s" % String(pair[0]).to_lower().replace("_", "-"),
			String(pair[0])
		)
		_assert_ok(action, "Skilled agent did not receive %s" % String(pair[0]))
		_assert(String(action.selected.affordance.target_port_id) == String(pair[1]), "%s target mismatch" % String(pair[0]))


func _test_damage_invalidation_and_rebuild() -> void:
	var store = BehaviorStoreScript.new()
	_assert_ok(store.setup(), "Damage behavior store setup failed")
	var operational: Dictionary = FixtureScript.table_snapshot("damage-flow")
	var published: Dictionary = store.compile_snapshot(operational)
	_assert_ok(published, "Operational damage-flow profile failed")
	var agent = AgentScript.new()
	_assert_ok(agent.setup(store, "actor/c5-damage-user", ["MANIPULATE_ITEM"]), "Damage agent setup failed")
	_assert_ok(agent.choose_action("affordance-query/c5/damage/before", "PLACE_ITEM"), "Agent could not use intact table")
	var damaged: Dictionary = FixtureScript.damaged_table_snapshot("damage-flow")
	_assert_ok(store.compile_snapshot(damaged), "Damaged profile update failed")
	_assert(store.get_generation() == 2, "Damage profile update generation mismatch")
	_assert_error(agent.choose_action("affordance-query/c5/damage/after", "PLACE_ITEM"), "CONSTRUCTION_AFFORDANCE_NOT_FOUND", "Agent retained affordance after structural damage")
	var damaged_profile: Dictionary = store.get_profile(String(damaged.construct_id))
	_assert(String(damaged_profile.build_state) == "DAMAGED", "Damage profile build state mismatch")
	_assert(damaged_profile.capabilities.is_empty() and damaged_profile.affordances.is_empty(), "Damage profile retained behavior")
	_assert_error(store.compile_snapshot(operational), "STALE_CONSTRUCTION_BEHAVIOR_PROFILE", "Behavior store accepted pre-damage snapshot")

	var restarted = BehaviorStoreScript.new()
	_assert_ok(restarted.setup(), "Rebuild behavior store setup failed")
	var rebuilt: Dictionary = restarted.compile_snapshot(damaged)
	_assert_ok(rebuilt, "Behavior rebuild from authoritative damage snapshot failed")
	_assert(UtilsScript.canonical_json(rebuilt.profile) == UtilsScript.canonical_json(damaged_profile), "Rebuilt behavior profile diverged from persisted projection")
	_assert(int(restarted.get_generation()) == 1, "Rebuild store generation mismatch")


func _test_deterministic_resolution() -> void:
	var store = BehaviorStoreScript.new()
	_assert_ok(store.setup(), "Deterministic store setup failed")
	var z_snapshot: Dictionary = FixtureScript.table_snapshot("z-table", {"parameter/load-rating-kg": 100.0})
	var a_snapshot: Dictionary = FixtureScript.table_snapshot("a-table", {"parameter/load-rating-kg": 100.0})
	_assert_ok(store.compile_snapshot(z_snapshot), "Z table profile failed")
	_assert_ok(store.compile_snapshot(a_snapshot), "A table profile failed")
	var query: Dictionary = QueryScript.create(
		"affordance-query/c5/deterministic",
		["PLACE_ITEM"],
		["MANIPULATE_ITEM"],
		[],
		{"load_rating_kg": 100.0},
		{},
		true,
		10
	)
	var forward: Dictionary = ResolverScript.resolve(query, store.list_profiles())
	_assert_ok(forward, "Forward deterministic resolution failed")
	var reversed_profiles: Array = store.list_profiles()
	reversed_profiles.reverse()
	var reverse: Dictionary = ResolverScript.resolve(query, reversed_profiles)
	_assert_ok(reverse, "Reverse deterministic resolution failed")
	_assert(UtilsScript.canonical_json(forward.candidates) == UtilsScript.canonical_json(reverse.candidates), "Affordance resolution depended on input profile order")
	_assert(int(forward.candidate_count) == 2, "Deterministic query candidate count mismatch")
	_assert(String(forward.candidates[0].construct_id) < String(forward.candidates[1].construct_id), "Equal-priority candidates not ordered by construct ID")
	var limited: Dictionary = query.duplicate(true)
	limited.limit = 1
	limited.checksum = QueryScript.compute_checksum(limited)
	var limited_result: Dictionary = ResolverScript.resolve(limited, reversed_profiles)
	_assert_ok(limited_result, "Limited affordance resolution failed")
	_assert(int(limited_result.candidate_count) == 1, "Affordance query limit not enforced")
	_assert(String(limited_result.candidates[0].construct_id) == String(forward.candidates[0].construct_id), "Limited query selected nondeterministic candidate")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("C5 capability/affordance integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C5 capability/affordance integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
