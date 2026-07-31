extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c7_spatial_house_fixture.gd")
const CompilerScript = preload("res://scripts/construction/spatial/construction_spatial_compiler.gd")
const StoreScript = preload("res://scripts/construction/spatial/construction_spatial_profile_store.gd")
const PersistenceScript = preload("res://scripts/construction/spatial/construction_spatial_persistence.gd")
const CommandScript = preload("res://scripts/construction/spatial/construction_spatial_command.gd")
const AuthorizerScript = preload("res://scripts/construction/spatial/construction_spatial_command_authorizer.gd")

class MemoryStateStore:
	extends RefCounted
	var states: Dictionary = {}
	func save_state(key: String, state: Dictionary) -> Dictionary:
		states[key] = state.duplicate(true)
		return {"success": true}
	func load_state(key: String) -> Dictionary:
		if not states.has(key): return {"success": false, "error_code": "STATE_NOT_FOUND"}
		return {"success": true, "state": Dictionary(states[key]).duplicate(true)}

var assertions: int = 0
var failures: Array[String] = []

func _init() -> void:
	_test_intact_house_activation()
	_test_door_state_and_access_affordances()
	_test_enclosure_damage_fail_closed()
	_test_utility_degradation_isolated_from_enclosure()
	_test_partial_and_repair_lifecycle()
	_test_command_preconditions_and_actor_gates()
	_test_persistence_restart_and_rebuild()
	_test_multiple_houses_and_profile_removal()
	_finish()

func _test_intact_house_activation() -> void:
	var compiled := CompilerScript.compile(FixtureScript.house_snapshot("intact"))
	_assert_ok(compiled, "Intact house compile failed")
	var profile: Dictionary = compiled.profile
	_assert(String(profile.building_state) == "ACTIVE", "Intact house not active")
	_assert(String(profile.activation_level) == "FUNCTIONAL", "Intact house activation level mismatch")
	_assert(String(profile.space_states[0].status) == "HABITABLE", "Intact room not habitable")
	_assert(int(profile.space_states[0].properties.available_utility_count) == 2, "Intact room utility count mismatch")
	_assert(_section_by_id(profile, "spatial-section/floor").status == "ONLINE", "Floor not online")
	_assert(_opening_by_id(profile, "spatial-opening/main-door").status == "CLOSED", "Door not closed")
	_assert(_opening_by_id(profile, "spatial-opening/main-window").status == "SEALED", "Window not sealed")
	_assert(_utility_by_id(profile, "spatial-utility/power").status == "ONLINE", "Power not online")
	_assert(_utility_by_id(profile, "spatial-utility/data").status == "ONLINE", "Data not online")
	var capabilities := _capability_kinds(profile)
	for expected in ["ACCESS_CONTROL", "DATA_DISTRIBUTION", "ENCLOSED_SPACE", "POWER_DISTRIBUTION", "SHELTER"]:
		_assert(capabilities.has(expected), "Missing intact capability %s" % expected)
	var actions := _action_kinds(profile)
	for expected in ["INSPECT_SPACE", "OCCUPY_SPACE", "OPEN_DOOR", "TOGGLE_LIGHTING", "TRAVERSE_OPENING", "USE_UTILITY"]:
		_assert(actions.has(expected), "Missing intact action %s" % expected)
	_assert(int(profile.diagnostics.habitable_space_count) == 1, "Habitable diagnostic mismatch")
	_assert(int(profile.diagnostics.exposed_space_count) == 0, "Exposed diagnostic mismatch")

func _test_door_state_and_access_affordances() -> void:
	var profile: Dictionary = CompilerScript.compile(FixtureScript.door_open("door-open")).profile
	_assert(String(profile.building_state) == "DEGRADED", "Open exterior door did not degrade building")
	_assert(String(profile.activation_level) == "FUNCTIONAL", "Open-door house lost functional activation")
	_assert(String(profile.space_states[0].status) == "DEGRADED", "Open exterior door did not degrade room")
	_assert(Array(profile.space_states[0].open_exterior_opening_ids) == ["spatial-opening/main-door"], "Open door not recorded in room")
	_assert(String(_opening_by_id(profile, "spatial-opening/main-door").status) == "OPEN", "Open door state mismatch")
	var actions := _action_kinds(profile)
	_assert(actions.has("CLOSE_DOOR"), "Close-door action missing")
	_assert(not actions.has("OPEN_DOOR"), "Open-door action remained while open")
	_assert(actions.has("TRAVERSE_OPENING"), "Open door lost traversal")
	_assert(actions.has("OCCUPY_SPACE"), "Open door removed occupancy")
	var broken: Dictionary = CompilerScript.compile(FixtureScript.door_bond_broken("door-broken")).profile
	_assert(String(_opening_by_id(broken, "spatial-opening/main-door").status) == "BREACHED", "Broken door bond not breached")
	_assert(String(broken.space_states[0].status) == "EXPOSED", "Breached door did not expose room")
	_assert(String(broken.building_state) == "INACTIVE", "Breached-only building remained active")
	_assert(_action_kinds(broken).is_empty(), "Breached inactive building exposed actions")

func _test_enclosure_damage_fail_closed() -> void:
	var wall_profile: Dictionary = CompilerScript.compile(FixtureScript.wall_lost("wall-loss")).profile
	_assert(String(_section_by_id(wall_profile, "spatial-section/wall-east").status) == "OFFLINE", "Destroyed wall section not offline")
	_assert(String(wall_profile.space_states[0].status) == "EXPOSED", "Destroyed wall did not expose room")
	_assert(Array(wall_profile.space_states[0].boundary_failure_section_ids) == ["spatial-section/wall-east"], "Destroyed wall failure not recorded")
	_assert(String(wall_profile.building_state) == "INACTIVE", "Exposed single-room building not inactive")
	_assert(String(wall_profile.activation_level) == "SUMMARY", "Damaged inactive house activation mismatch")
	_assert(wall_profile.capabilities.is_empty(), "Exposed building retained capabilities")
	_assert(wall_profile.affordances.is_empty(), "Exposed building retained affordances")
	var window_profile: Dictionary = CompilerScript.compile(FixtureScript.window_lost("window-loss")).profile
	_assert(String(_opening_by_id(window_profile, "spatial-opening/main-window").status) == "BREACHED", "Destroyed window not breached")
	_assert(String(window_profile.space_states[0].status) == "EXPOSED", "Destroyed window did not expose room")
	_assert(String(window_profile.building_state) == "INACTIVE", "Window breach kept building active")
	var roof_profile: Dictionary = CompilerScript.compile(FixtureScript.roof_degraded("roof-degraded")).profile
	_assert(String(_section_by_id(roof_profile, "spatial-section/roof").status) == "DEGRADED", "Degraded roof section status mismatch")
	_assert(String(roof_profile.space_states[0].status) == "DEGRADED", "Degraded roof did not degrade room")
	_assert(String(roof_profile.building_state) == "DEGRADED", "Degraded roof did not degrade building")
	_assert(_capability_kinds(roof_profile).has("SHELTER"), "Degraded roof removed shelter prematurely")

func _test_utility_degradation_isolated_from_enclosure() -> void:
	var power_profile: Dictionary = CompilerScript.compile(FixtureScript.power_lost("power-loss")).profile
	_assert(String(_utility_by_id(power_profile, "spatial-utility/power").status) == "OFFLINE", "Destroyed power panel not offline")
	_assert(String(_utility_by_id(power_profile, "spatial-utility/data").status) == "OFFLINE", "Data dependency did not cascade from power")
	_assert(String(power_profile.space_states[0].status) == "DEGRADED", "Power loss should degrade, not expose, room")
	_assert(String(power_profile.building_state) == "DEGRADED", "Power loss did not degrade building")
	_assert(_capability_kinds(power_profile).has("ENCLOSED_SPACE"), "Power loss removed enclosure capability")
	_assert(_capability_kinds(power_profile).has("SHELTER"), "Power loss removed shelter")
	_assert(not _capability_kinds(power_profile).has("POWER_DISTRIBUTION"), "Power loss retained power capability")
	_assert(not _capability_kinds(power_profile).has("DATA_DISTRIBUTION"), "Power loss retained dependent data capability")
	_assert(not _action_kinds(power_profile).has("TOGGLE_LIGHTING"), "Power loss retained lighting action")
	_assert(_action_kinds(power_profile).has("OCCUPY_SPACE"), "Power loss removed occupancy")
	var data_profile: Dictionary = CompilerScript.compile(FixtureScript.data_lost("data-loss")).profile
	_assert(String(_utility_by_id(data_profile, "spatial-utility/power").status) == "ONLINE", "Data loss affected power")
	_assert(String(_utility_by_id(data_profile, "spatial-utility/data").status) == "OFFLINE", "Destroyed data router not offline")
	_assert(_capability_kinds(data_profile).has("POWER_DISTRIBUTION"), "Data loss removed power capability")
	_assert(not _capability_kinds(data_profile).has("DATA_DISTRIBUTION"), "Data loss retained data capability")
	_assert(_action_kinds(data_profile).has("TOGGLE_LIGHTING"), "Data loss removed independent lighting")

func _test_partial_and_repair_lifecycle() -> void:
	var partial: Dictionary = CompilerScript.compile(FixtureScript.partial("lifecycle")).profile
	_assert(String(partial.building_state) == "INACTIVE", "Partial building active")
	_assert(String(partial.activation_level) == "DORMANT", "Partial building not dormant")
	_assert(String(partial.space_states[0].status) == "INACTIVE", "Partial space not inactive")
	_assert(partial.capabilities.is_empty(), "Partial building exposed capabilities")
	_assert(partial.affordances.is_empty(), "Partial building exposed affordances")
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Lifecycle store setup failed")
	var damaged := store.compile_snapshot(FixtureScript.wall_lost("lifecycle", 1))
	_assert_ok(damaged, "Lifecycle damaged publish failed")
	_assert(String(damaged.profile.building_state) == "INACTIVE", "Lifecycle damaged state mismatch")
	var repaired := store.compile_snapshot(FixtureScript.repaired("lifecycle", 2))
	_assert_ok(repaired, "Lifecycle repair publish failed")
	_assert(String(repaired.profile.building_state) == "ACTIVE", "Repair did not restore active state")
	_assert(String(repaired.profile.space_states[0].status) == "HABITABLE", "Repair did not restore habitable room")
	_assert(_action_kinds(repaired.profile).has("OPEN_DOOR"), "Repair did not restore door action")
	_assert(int(store.get_generation()) == 2, "Lifecycle generation mismatch")

func _test_command_preconditions_and_actor_gates() -> void:
	var closed_profile: Dictionary = CompilerScript.compile(FixtureScript.house_snapshot("commands")).profile
	var open_command := CommandScript.create("spatial-command/c7/open", String(closed_profile.construct_id), "OPEN_DOOR", ["OPERATE_DOOR"], {}, String(closed_profile.checksum))
	var authorized := AuthorizerScript.authorize(open_command, closed_profile)
	_assert_ok(authorized, "Skilled actor could not open door")
	_assert(String(authorized.affordance.action_kind) == "OPEN_DOOR", "Open command resolved wrong affordance")
	_assert(String(authorized.affordance.target_part_id).ends_with("/door"), "Open command targeted wrong part")
	var unskilled := CommandScript.create("spatial-command/c7/unskilled", String(closed_profile.construct_id), "OPEN_DOOR", [], {}, String(closed_profile.checksum))
	_assert_error(AuthorizerScript.authorize(unskilled, closed_profile), "CONSTRUCTION_SPATIAL_COMMAND_NOT_AUTHORIZED", "Unskilled actor opened door")
	var lighting := CommandScript.create("spatial-command/c7/light", String(closed_profile.construct_id), "TOGGLE_LIGHTING", [], {"enabled": true}, String(closed_profile.checksum))
	var lighting_result := AuthorizerScript.authorize(lighting, closed_profile)
	_assert_ok(lighting_result, "Lighting command rejected")
	_assert(bool(lighting_result.resolved_parameters.enabled), "Lighting command override lost")
	var open_profile: Dictionary = CompilerScript.compile(FixtureScript.door_open("commands", 1)).profile
	_assert_error(AuthorizerScript.authorize(open_command, open_profile), "CONSTRUCTION_SPATIAL_COMMAND_PROFILE_PRECONDITION_MISMATCH", "Stale door command authorized")
	var close_command := CommandScript.create("spatial-command/c7/close", String(open_profile.construct_id), "CLOSE_DOOR", ["OPERATE_DOOR"], {}, String(open_profile.checksum))
	_assert_ok(AuthorizerScript.authorize(close_command, open_profile), "Fresh close command rejected")
	var wall_profile: Dictionary = CompilerScript.compile(FixtureScript.wall_lost("commands", 2)).profile
	var inspect_old := CommandScript.create("spatial-command/c7/inspect-old", String(closed_profile.construct_id), "INSPECT_SPACE", ["INSPECT_CONSTRUCT"], {}, String(closed_profile.checksum))
	_assert_error(AuthorizerScript.authorize(inspect_old, wall_profile), "CONSTRUCTION_SPATIAL_COMMAND_PROFILE_PRECONDITION_MISMATCH", "Old inspect command authorized after wall loss")

func _test_persistence_restart_and_rebuild() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Persistence store setup failed")
	var snapshot := FixtureScript.power_lost("persistence", 4)
	var published := store.compile_snapshot(snapshot)
	_assert_ok(published, "Persistence profile publish failed")
	var memory = MemoryStateStore.new()
	var persistence = PersistenceScript.new()
	_assert_ok(persistence.setup(store, memory, "spatial-c7"), "Persistence setup failed")
	var saved := persistence.save()
	_assert_ok(saved, "Persistence save failed")
	_assert(String(saved.checksum) == String(store.to_dict().checksum), "Persistence save checksum mismatch")
	var restarted = StoreScript.new()
	_assert_ok(restarted.setup(), "Restarted store setup failed")
	var restarted_persistence = PersistenceScript.new()
	_assert_ok(restarted_persistence.setup(restarted, memory, "spatial-c7"), "Restarted persistence setup failed")
	_assert_ok(restarted_persistence.load(), "Persistence load failed")
	_assert(int(restarted.get_generation()) == 1, "Restarted generation mismatch")
	_assert(UtilsScript.canonical_json(restarted.get_profile(String(snapshot.construct_id))) == UtilsScript.canonical_json(published.profile), "Restarted profile changed")
	var rebuilt = StoreScript.new()
	_assert_ok(rebuilt.setup(), "Rebuild store setup failed")
	var rebuilt_result := rebuilt.compile_snapshot(snapshot)
	_assert_ok(rebuilt_result, "Authoritative rebuild failed")
	_assert(UtilsScript.canonical_json(rebuilt_result.profile) == UtilsScript.canonical_json(published.profile), "Authoritative rebuild diverged")
	var tampered: Dictionary = memory.states["spatial-c7"].duplicate(true)
	tampered.profiles[0].building_state = "ACTIVE"
	memory.states["spatial-c7"] = tampered
	var rejected = StoreScript.new()
	_assert_ok(rejected.setup(), "Rejected store setup failed")
	var rejected_persistence = PersistenceScript.new()
	_assert_ok(rejected_persistence.setup(rejected, memory, "spatial-c7"), "Rejected persistence setup failed")
	_assert_error(rejected_persistence.load(), "CONSTRUCTION_SPATIAL_PROFILE_CHECKSUM_MISMATCH", "Persistence accepted tampered profile")
	_assert(rejected.list_profiles().is_empty(), "Rejected persistence mutated store")

func _test_multiple_houses_and_profile_removal() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Multi-house store setup failed")
	var alpha: Dictionary = store.compile_snapshot(FixtureScript.door_open("alpha", 1)).profile
	var beta: Dictionary = store.compile_snapshot(FixtureScript.house_snapshot("beta")).profile
	_assert(String(alpha.construct_id) != String(beta.construct_id), "House construct IDs collided")
	_assert(String(alpha.building_state) == "DEGRADED", "Alpha state mismatch")
	_assert(String(beta.building_state) == "ACTIVE", "Beta state mismatch")
	_assert(int(store.get_generation()) == 2, "Multi-house generation mismatch")
	var profiles := store.list_profiles()
	_assert(profiles.size() == 2, "Multi-house profile count mismatch")
	_assert(String(profiles[0].construct_id) < String(profiles[1].construct_id), "Multi-house profiles not sorted")
	_assert_error(store.remove_profile(String(beta.construct_id), "0".repeat(64)), "CONSTRUCTION_SPATIAL_PROFILE_REMOVE_PRECONDITION_MISMATCH", "Profile removed with wrong checksum")
	_assert(int(store.get_generation()) == 2, "Failed removal advanced generation")
	var removed := store.remove_profile(String(beta.construct_id), String(FixtureScript.house_snapshot("beta").checksum))
	_assert_ok(removed, "Profile removal failed")
	_assert(bool(removed.removed), "Profile removal not reported")
	_assert(int(store.get_generation()) == 3, "Removal generation mismatch")
	_assert(store.get_profile(String(beta.construct_id)).is_empty(), "Removed profile remained visible")
	var replay := store.remove_profile(String(beta.construct_id), String(FixtureScript.house_snapshot("beta").checksum))
	_assert_ok(replay, "Removal replay failed")
	_assert(bool(replay.replay), "Removal replay not detected")
	_assert(int(store.get_generation()) == 3, "Removal replay advanced generation")

func _section_by_id(profile: Dictionary, identifier: String) -> Dictionary:
	for state in profile.section_states:
		if String(state.section_id) == identifier: return state
	return {}
func _opening_by_id(profile: Dictionary, identifier: String) -> Dictionary:
	for state in profile.opening_states:
		if String(state.opening_id) == identifier: return state
	return {}
func _utility_by_id(profile: Dictionary, identifier: String) -> Dictionary:
	for state in profile.utility_states:
		if String(state.utility_id) == identifier: return state
	return {}
func _capability_kinds(profile: Dictionary) -> Array:
	var result: Array = []
	for capability in profile.capabilities: result.append(String(capability.capability_kind))
	result.sort(); return result
func _action_kinds(profile: Dictionary) -> Array:
	var result: Array = []
	for affordance in profile.affordances: result.append(String(affordance.action_kind))
	result.sort(); return result
func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty():
		print("C7 spatial construct integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures: push_error(failure)
	print("C7 spatial construct integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
