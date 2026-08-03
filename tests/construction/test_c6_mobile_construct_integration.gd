extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const DefinitionScript = preload("res://scripts/construction/mobile/construction_mobile_subsystem_definition.gd")
const CompilerScript = preload("res://scripts/construction/mobile/construction_mobile_compiler.gd")
const ProfileScript = preload("res://scripts/construction/mobile/construction_mobile_profile.gd")
const StoreScript = preload("res://scripts/construction/mobile/construction_mobile_profile_store.gd")
const PersistenceScript = preload("res://scripts/construction/mobile/construction_mobile_persistence.gd")
const CommandScript = preload("res://scripts/construction/mobile/construction_mobile_command.gd")
const AuthorizerScript = preload("res://scripts/construction/mobile/construction_mobile_command_authorizer.gd")
const AgentScript = preload("res://scripts/construction/mobile/construction_mobile_agent.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c6_mobile_rover_fixture.gd")


class MemoryStateStore:
	extends RefCounted
	var states: Dictionary = {}

	func save_state(key: String, state: Dictionary) -> Dictionary:
		states[key] = state.duplicate(true)
		return {"success": true, "error_code": "", "message": ""}

	func load_state(key: String) -> Dictionary:
		if not states.has(key):
			return {"success": false, "error_code": "STATE_NOT_FOUND", "message": "STATE_NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "state": Dictionary(states[key]).duplicate(true)}


var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_damage_degradation_and_repair_flow()
	_test_sensor_failure_isolated_from_mobility()
	_test_power_and_control_dependency_cascade()
	_test_bond_health_and_quorum()
	_test_command_preconditions_and_actor_gates()
	_test_persistence_restart_and_rebuild()
	_test_multiple_mobile_constructs_are_isolated()
	_test_profile_removal_and_republication()
	_finish()


func _test_damage_degradation_and_repair_flow() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Damage-flow mobile store setup failed")
	var intact_snapshot: Dictionary = FixtureScript.rover_snapshot("damage-flow")
	var intact_publish: Dictionary = store.compile_snapshot(intact_snapshot)
	_assert_ok(intact_publish, "Intact rover publish failed")
	_assert(int(store.get_generation()) == 1, "Intact rover generation mismatch")
	var intact_profile: Dictionary = intact_publish.profile
	_assert(String(intact_profile.mobility_state) == "MOBILE", "Intact rover not mobile")
	_assert(intact_profile.affordances.size() == 4, "Intact rover affordance count mismatch")
	var agent = AgentScript.new()
	_assert_ok(agent.setup(store, "actor/c6/operator", ["OPERATE_MOBILE_CONSTRUCT", "OPERATE_SENSOR"]), "Mobile operator setup failed")
	var drive: Dictionary = agent.issue_command(
		"mobile-command/c6/damage-flow/drive-intact",
		String(intact_profile.construct_id),
		"DRIVE_TO",
		{"target_position_m": [20.0, 0.0, 5.0]}
	)
	_assert_ok(drive, "Intact rover drive command failed")
	_assert(String(drive.mobility_state) == "MOBILE", "Intact drive authorization lost mobility state")
	_assert(float(drive.resolved_parameters.effective_max_speed_mps) == 8.0, "Intact drive command speed mismatch")
	_assert(drive.resolved_parameters.target_position_m == [20.0, 0.0, 5.0], "Drive command parameters not merged")
	_assert_ok(agent.issue_command("mobile-command/c6/damage-flow/scan-intact", String(intact_profile.construct_id), "SCAN_ENVIRONMENT"), "Intact rover scan command failed")

	var degraded_snapshot: Dictionary = FixtureScript.one_wheel_lost("damage-flow", 1)
	var degraded_publish: Dictionary = store.compile_snapshot(degraded_snapshot)
	_assert_ok(degraded_publish, "Degraded rover publish failed")
	_assert(int(store.get_generation()) == 2, "Degraded rover generation mismatch")
	var degraded_profile: Dictionary = degraded_publish.profile
	_assert(String(degraded_profile.mobility_state) == "DEGRADED", "Wheel loss did not degrade mobility")
	_assert(String(_subsystem_by_kind(degraded_profile, "DRIVE").status) == "DEGRADED", "Wheel loss did not degrade drive subsystem")
	_assert(_subsystem_by_kind(degraded_profile, "DRIVE").offline_provider_part_ids.size() == 1, "Wheel loss provider accounting mismatch")
	var degraded_drive: Dictionary = agent.issue_command(
		"mobile-command/c6/damage-flow/drive-degraded",
		String(degraded_profile.construct_id),
		"DRIVE_TO"
	)
	_assert_ok(degraded_drive, "Degraded rover lost drive command")
	_assert(float(degraded_drive.resolved_parameters.effective_max_speed_mps) == 6.0, "Degraded rover speed was not reduced")
	_assert_ok(agent.issue_command("mobile-command/c6/damage-flow/scan-degraded", String(degraded_profile.construct_id), "SCAN_ENVIRONMENT"), "Wheel damage removed sensor command")
	var replay: Dictionary = store.compile_snapshot(degraded_snapshot)
	_assert_ok(replay, "Degraded rover exact replay failed")
	_assert(bool(replay.replay), "Degraded rover replay not detected")
	_assert(int(store.get_generation()) == 2, "Degraded rover replay advanced generation")
	var conflict_snapshot: Dictionary = FixtureScript.sensor_lost("damage-flow", 1)
	_assert_error(store.compile_snapshot(conflict_snapshot), "CONSTRUCTION_MOBILE_PROFILE_SAME_REVISION_CONFLICT", "Store accepted same-revision mobile mutation")
	_assert_error(store.compile_snapshot(intact_snapshot), "STALE_CONSTRUCTION_MOBILE_PROFILE", "Store accepted stale intact rover")

	var immobile_snapshot: Dictionary = FixtureScript.three_wheels_lost("damage-flow", 2)
	var immobile_publish: Dictionary = store.compile_snapshot(immobile_snapshot)
	_assert_ok(immobile_publish, "Immobile rover publish failed")
	_assert(int(store.get_generation()) == 3, "Immobile rover generation mismatch")
	var immobile_profile: Dictionary = immobile_publish.profile
	_assert(String(immobile_profile.mobility_state) == "IMMOBILE", "Three-wheel loss did not immobilize rover")
	_assert(not _action_kinds(immobile_profile).has("DRIVE_TO"), "Immobile rover retained drive action")
	_assert_error(agent.issue_command("mobile-command/c6/damage-flow/drive-immobile", String(immobile_profile.construct_id), "DRIVE_TO"), "CONSTRUCTION_MOBILE_COMMAND_NOT_AUTHORIZED", "Immobile rover accepted drive command")
	_assert_ok(agent.issue_command("mobile-command/c6/damage-flow/scan-immobile", String(immobile_profile.construct_id), "SCAN_ENVIRONMENT"), "Immobile rover lost independent sensor command")

	var repaired_snapshot: Dictionary = FixtureScript.repaired("damage-flow", 3)
	var repaired_publish: Dictionary = store.compile_snapshot(repaired_snapshot)
	_assert_ok(repaired_publish, "Repaired rover publish failed")
	_assert(int(store.get_generation()) == 4, "Repaired rover generation mismatch")
	var repaired_profile: Dictionary = repaired_publish.profile
	_assert(String(repaired_profile.mobility_state) == "MOBILE", "Repair did not restore mobility")
	_assert(_action_kinds(repaired_profile).has("DRIVE_TO"), "Repair did not restore drive action")
	var repaired_drive: Dictionary = agent.issue_command("mobile-command/c6/damage-flow/drive-repaired", String(repaired_profile.construct_id), "DRIVE_TO")
	_assert_ok(repaired_drive, "Repaired rover drive command failed")
	_assert(float(repaired_drive.resolved_parameters.effective_max_speed_mps) == 8.0, "Repair did not restore full speed")


func _test_sensor_failure_isolated_from_mobility() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Sensor-flow store setup failed")
	var sensor_snapshot: Dictionary = FixtureScript.sensor_lost("sensor-flow", 1)
	var published: Dictionary = store.compile_snapshot(sensor_snapshot)
	_assert_ok(published, "Sensor-loss profile publish failed")
	var profile: Dictionary = published.profile
	_assert(String(profile.mobility_state) == "MOBILE", "Sensor loss reduced mobility")
	_assert(String(_subsystem_by_kind(profile, "SENSOR").status) == "OFFLINE", "Sensor subsystem remained online")
	_assert(String(_subsystem_by_kind(profile, "DRIVE").status) == "ONLINE", "Sensor loss degraded drive")
	_assert(_action_kinds(profile).has("DRIVE_TO"), "Sensor loss removed drive action")
	_assert(not _action_kinds(profile).has("SCAN_ENVIRONMENT"), "Sensor loss retained scan action")
	var agent = AgentScript.new()
	_assert_ok(agent.setup(store, "actor/c6/sensor-flow", ["OPERATE_MOBILE_CONSTRUCT", "OPERATE_SENSOR"]), "Sensor-flow agent setup failed")
	_assert_ok(agent.issue_command("mobile-command/c6/sensor-flow/drive", String(profile.construct_id), "DRIVE_TO"), "Sensor-damaged rover could not drive")
	_assert_error(agent.issue_command("mobile-command/c6/sensor-flow/scan", String(profile.construct_id), "SCAN_ENVIRONMENT"), "CONSTRUCTION_MOBILE_COMMAND_NOT_AUTHORIZED", "Sensor-damaged rover accepted scan")
	var repaired: Dictionary = store.compile_snapshot(FixtureScript.repaired("sensor-flow", 2))
	_assert_ok(repaired, "Sensor repair publish failed")
	_assert(_action_kinds(repaired.profile).has("SCAN_ENVIRONMENT"), "Sensor repair did not restore scan")


func _test_power_and_control_dependency_cascade() -> void:
	var control_profile: Dictionary = CompilerScript.compile(FixtureScript.controller_lost("cascade-control", 1)).profile
	_assert(String(_subsystem_by_kind(control_profile, "POWER").status) == "ONLINE", "Controller loss changed power state")
	_assert(String(_subsystem_by_kind(control_profile, "CONTROL").status) == "OFFLINE", "Controller loss did not disable control")
	_assert(String(_subsystem_by_kind(control_profile, "DRIVE").status) == "OFFLINE", "Drive ignored control loss")
	_assert(String(_subsystem_by_kind(control_profile, "SENSOR").status) == "OFFLINE", "Sensor ignored control loss")
	_assert(String(control_profile.mobility_state) == "IMMOBILE", "Controller loss did not immobilize rover")
	_assert(_action_kinds(control_profile).is_empty(), "Controller loss retained dependent actions")
	var power_profile: Dictionary = CompilerScript.compile(FixtureScript.power_lost("cascade-power", 1)).profile
	_assert(String(_subsystem_by_kind(power_profile, "POWER").status) == "OFFLINE", "Battery loss did not disable power")
	_assert(String(_subsystem_by_kind(power_profile, "CONTROL").status) == "OFFLINE", "Control ignored power loss")
	_assert(String(_subsystem_by_kind(power_profile, "DRIVE").status) == "OFFLINE", "Drive ignored power loss")
	_assert(String(_subsystem_by_kind(power_profile, "SENSOR").status) == "OFFLINE", "Sensor ignored power loss")
	_assert(power_profile.capabilities.is_empty(), "Power loss retained capabilities")
	_assert(power_profile.affordances.is_empty(), "Power loss retained affordances")


func _test_bond_health_and_quorum() -> void:
	var degraded_bond_snapshot: Dictionary = FixtureScript.rover_snapshot(
		"bond-degraded",
		{},
		{"controller": "DEGRADED"},
		1,
		"DAMAGED"
	)
	var degraded_profile: Dictionary = CompilerScript.compile(degraded_bond_snapshot).profile
	_assert(String(_subsystem_by_kind(degraded_profile, "CONTROL").status) == "DEGRADED", "Degraded control bond did not degrade subsystem")
	_assert(String(_subsystem_by_kind(degraded_profile, "DRIVE").status) == "DEGRADED", "Drive did not inherit degraded control dependency")
	_assert(String(_subsystem_by_kind(degraded_profile, "SENSOR").status) == "DEGRADED", "Sensor did not inherit degraded control dependency")
	_assert(String(degraded_profile.mobility_state) == "DEGRADED", "Degraded control bond did not degrade mobility")
	_assert(_action_kinds(degraded_profile).has("DRIVE_TO"), "Degraded dependency removed drive action")
	var broken_power_bond: Dictionary = FixtureScript.rover_snapshot(
		"bond-broken",
		{},
		{"battery": "BROKEN"},
		1,
		"DAMAGED"
	)
	var broken_profile: Dictionary = CompilerScript.compile(broken_power_bond).profile
	_assert(String(_subsystem_by_kind(broken_profile, "POWER").status) == "OFFLINE", "Broken battery bond did not disable power")
	_assert(String(broken_profile.mobility_state) == "IMMOBILE", "Broken battery bond did not immobilize rover")
	_assert(broken_profile.affordances.is_empty(), "Broken battery bond retained actions")
	var two_wheel_snapshot: Dictionary = FixtureScript.rover_snapshot(
		"quorum-two",
		{"wheel-fl": "DESTROYED", "wheel-fr": "DESTROYED"},
		{},
		1,
		"DAMAGED"
	)
	var two_wheel_profile: Dictionary = CompilerScript.compile(two_wheel_snapshot).profile
	_assert(String(_subsystem_by_kind(two_wheel_profile, "DRIVE").status) == "DEGRADED", "Drive quorum rejected exactly two wheels")
	_assert(String(two_wheel_profile.mobility_state) == "DEGRADED", "Two-wheel quorum did not retain degraded mobility")
	_assert(float(_affordance_by_action(two_wheel_profile, "DRIVE_TO").parameters.effective_max_speed_mps) == 4.0, "Two-wheel speed scaling mismatch")


func _test_command_preconditions_and_actor_gates() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Command-gate store setup failed")
	var intact: Dictionary = store.compile_snapshot(FixtureScript.rover_snapshot("command-gates")).profile
	var drive_only = AgentScript.new()
	_assert_ok(drive_only.setup(store, "actor/c6/driver", ["OPERATE_MOBILE_CONSTRUCT"]), "Driver setup failed")
	_assert_ok(drive_only.issue_command("mobile-command/c6/gates/drive", String(intact.construct_id), "DRIVE_TO"), "Driver could not drive")
	_assert_error(drive_only.issue_command("mobile-command/c6/gates/scan", String(intact.construct_id), "SCAN_ENVIRONMENT"), "CONSTRUCTION_MOBILE_COMMAND_NOT_AUTHORIZED", "Driver received sensor action without skill")
	var sensor_only = AgentScript.new()
	_assert_ok(sensor_only.setup(store, "actor/c6/sensor", ["OPERATE_SENSOR"]), "Sensor operator setup failed")
	_assert_ok(sensor_only.issue_command("mobile-command/c6/gates/scan-skilled", String(intact.construct_id), "SCAN_ENVIRONMENT"), "Sensor operator could not scan")
	_assert_error(sensor_only.issue_command("mobile-command/c6/gates/drive-unskilled", String(intact.construct_id), "DRIVE_TO"), "CONSTRUCTION_MOBILE_COMMAND_NOT_AUTHORIZED", "Sensor operator received drive action")
	var old_command: Dictionary = CommandScript.create(
		"mobile-command/c6/gates/stale",
		String(intact.construct_id),
		"DRIVE_TO",
		["OPERATE_MOBILE_CONSTRUCT"],
		{},
		String(intact.checksum)
	)
	var degraded: Dictionary = store.compile_snapshot(FixtureScript.one_wheel_lost("command-gates", 1)).profile
	_assert_error(AuthorizerScript.authorize(old_command, degraded), "CONSTRUCTION_MOBILE_COMMAND_PROFILE_PRECONDITION_MISMATCH", "Old command authorized against changed profile")
	var fresh: Dictionary = CommandScript.create(
		"mobile-command/c6/gates/fresh",
		String(degraded.construct_id),
		"DRIVE_TO",
		["OPERATE_MOBILE_CONSTRUCT"],
		{"requested_speed_mps": 5.0},
		String(degraded.checksum)
	)
	var authorized: Dictionary = AuthorizerScript.authorize(fresh, degraded)
	_assert_ok(authorized, "Fresh degraded command not authorized")
	_assert(float(authorized.resolved_parameters.requested_speed_mps) == 5.0, "Fresh command parameter lost")
	_assert(float(authorized.resolved_parameters.effective_max_speed_mps) == 6.0, "Fresh command lost profile speed limit")


func _test_persistence_restart_and_rebuild() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Persistence store setup failed")
	var degraded_snapshot: Dictionary = FixtureScript.one_wheel_lost("persistence", 4)
	var published: Dictionary = store.compile_snapshot(degraded_snapshot)
	_assert_ok(published, "Persistence profile publish failed")
	var memory = MemoryStateStore.new()
	var persistence = PersistenceScript.new()
	_assert_ok(persistence.setup(store, memory, "mobile-c6"), "Persistence setup failed")
	var saved: Dictionary = persistence.save()
	_assert_ok(saved, "Persistence save failed")
	_assert(String(saved.checksum) == String(store.to_dict().checksum), "Persistence save checksum mismatch")
	var restarted = StoreScript.new()
	_assert_ok(restarted.setup(), "Restarted store setup failed")
	var restarted_persistence = PersistenceScript.new()
	_assert_ok(restarted_persistence.setup(restarted, memory, "mobile-c6"), "Restarted persistence setup failed")
	_assert_ok(restarted_persistence.load(), "Persistence load failed")
	_assert(int(restarted.get_generation()) == 1, "Restarted generation mismatch")
	_assert(UtilsScript.canonical_json(restarted.get_profile(String(degraded_snapshot.construct_id))) == UtilsScript.canonical_json(published.profile), "Restarted profile changed")
	var rebuilt = StoreScript.new()
	_assert_ok(rebuilt.setup(), "Rebuild store setup failed")
	var rebuilt_result: Dictionary = rebuilt.compile_snapshot(degraded_snapshot)
	_assert_ok(rebuilt_result, "Authoritative rebuild failed")
	_assert(UtilsScript.canonical_json(rebuilt_result.profile) == UtilsScript.canonical_json(published.profile), "Authoritative rebuild diverged from persisted profile")
	_assert(int(rebuilt.get_generation()) == 1, "Authoritative rebuild generation mismatch")
	var tampered: Dictionary = memory.states["mobile-c6"].duplicate(true)
	tampered.profiles[0].mobility_state = "MOBILE"
	memory.states["mobile-c6"] = tampered
	var rejected_store = StoreScript.new()
	_assert_ok(rejected_store.setup(), "Rejected store setup failed")
	var rejected_persistence = PersistenceScript.new()
	_assert_ok(rejected_persistence.setup(rejected_store, memory, "mobile-c6"), "Rejected persistence setup failed")
	_assert_error(rejected_persistence.load(), "CONSTRUCTION_MOBILE_PROFILE_CHECKSUM_MISMATCH", "Persistence accepted tampered profile")
	_assert(rejected_store.list_profiles().is_empty(), "Rejected persistence mutated target store")


func _test_multiple_mobile_constructs_are_isolated() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Multi-rover store setup failed")
	var alpha: Dictionary = store.compile_snapshot(FixtureScript.one_wheel_lost("alpha", 1)).profile
	var beta: Dictionary = store.compile_snapshot(FixtureScript.rover_snapshot("beta")).profile
	_assert(int(store.get_generation()) == 2, "Multi-rover generation mismatch")
	_assert(String(alpha.construct_id) != String(beta.construct_id), "Mobile construct IDs collided")
	_assert(String(alpha.mobility_state) == "DEGRADED", "Alpha mobility state mismatch")
	_assert(String(beta.mobility_state) == "MOBILE", "Beta mobility state mismatch")
	_assert(float(_affordance_by_action(alpha, "DRIVE_TO").parameters.effective_max_speed_mps) == 6.0, "Alpha speed mismatch")
	_assert(float(_affordance_by_action(beta, "DRIVE_TO").parameters.effective_max_speed_mps) == 8.0, "Beta speed mismatch")
	var profiles: Array = store.list_profiles()
	_assert(profiles.size() == 2, "Multi-rover profile count mismatch")
	_assert(String(profiles[0].construct_id) < String(profiles[1].construct_id), "Multi-rover profiles not sorted")
	var beta_agent = AgentScript.new()
	_assert_ok(beta_agent.setup(store, "actor/c6/beta", ["OPERATE_MOBILE_CONSTRUCT"]), "Beta agent setup failed")
	var beta_drive: Dictionary = beta_agent.issue_command("mobile-command/c6/beta/drive", String(beta.construct_id), "DRIVE_TO")
	_assert_ok(beta_drive, "Beta drive failed")
	_assert(String(beta_drive.command.construct_id) == String(beta.construct_id), "Beta command targeted alpha")


func _test_profile_removal_and_republication() -> void:
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Removal store setup failed")
	var snapshot: Dictionary = FixtureScript.rover_snapshot("removal")
	var published: Dictionary = store.compile_snapshot(snapshot)
	_assert_ok(published, "Removal profile publish failed")
	_assert_error(store.remove_profile(String(snapshot.construct_id), "0".repeat(64)), "CONSTRUCTION_MOBILE_PROFILE_REMOVE_PRECONDITION_MISMATCH", "Profile removed with wrong checksum")
	_assert(int(store.get_generation()) == 1, "Failed removal advanced generation")
	var removed: Dictionary = store.remove_profile(String(snapshot.construct_id), String(snapshot.checksum))
	_assert_ok(removed, "Profile removal failed")
	_assert(bool(removed.removed), "Profile removal not reported")
	_assert(int(store.get_generation()) == 2, "Profile removal generation mismatch")
	_assert(store.get_profile(String(snapshot.construct_id)).is_empty(), "Removed profile remained visible")
	var removal_replay: Dictionary = store.remove_profile(String(snapshot.construct_id), String(snapshot.checksum))
	_assert_ok(removal_replay, "Profile removal replay failed")
	_assert(bool(removal_replay.replay), "Profile removal replay not detected")
	_assert(int(store.get_generation()) == 2, "Removal replay advanced generation")
	var republished: Dictionary = store.compile_snapshot(snapshot)
	_assert_ok(republished, "Profile republication failed")
	_assert(not bool(republished.replay), "Profile republication marked replay")
	_assert(int(store.get_generation()) == 3, "Profile republication generation mismatch")


func _subsystem_by_kind(profile: Dictionary, kind: String) -> Dictionary:
	for state in profile.subsystem_states:
		if String(state.subsystem_kind) == kind:
			return state
	return {}


func _affordance_by_action(profile: Dictionary, action_kind: String) -> Dictionary:
	for affordance in profile.affordances:
		if String(affordance.action_kind) == action_kind:
			return affordance
	return {}


func _action_kinds(profile: Dictionary) -> Array:
	var result: Array = []
	for affordance in profile.affordances:
		result.append(String(affordance.action_kind))
	result.sort()
	return result


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
		print("C6 mobile construct integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C6 mobile construct integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
