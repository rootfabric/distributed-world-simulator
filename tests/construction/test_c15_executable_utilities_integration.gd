extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Fixture = preload("res://tests/construction/fixtures/c15_executable_utilities_fixture.gd")
const C8Fixture = preload("res://tests/construction/fixtures/c8_fabrication_cell_fixture.gd")
const SimulatorScript = preload("res://scripts/construction/utilities/construction_utility_simulator.gd")
const ProfileScript = preload("res://scripts/construction/utilities/construction_utility_execution_profile.gd")
const NetworkScript = preload("res://scripts/construction/utilities/construction_utility_network_definition.gd")
const LinkScript = preload("res://scripts/construction/utilities/construction_utility_link_definition.gd")
const LeaseCompilerScript = preload("res://scripts/construction/utilities/construction_machine_utility_lease_compiler.gd")
const LeaseScript = preload("res://scripts/construction/utilities/construction_machine_utility_lease.gd")
const ExecutableRuntimeScript = preload("res://scripts/construction/utilities/construction_executable_fabrication_runtime.gd")
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const CatalogScript = preload("res://scripts/construction/fabrication/construction_fabrication_catalog.gd")
const QueueScript = preload("res://scripts/construction/fabrication/construction_fabrication_queue_store.gd")
const FabricationProcessScript = preload("res://scripts/construction/fabrication/construction_fabrication_process.gd")
const MachineCompilerScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_compiler.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_all_utility_kinds_execute()
	_test_priority_losses_storage_and_shedding()
	_test_storage_charge_discharge_and_link_failure()
	_test_c8_machine_requires_actual_allocation()
	_test_machine_lease_replay_and_recovery()
	_finish()

func _test_all_utility_kinds_execute() -> void:
	for kind in ["POWER", "WATER", "AIR", "HEAT", "DATA"]:
		var key := "execute-%s" % kind.to_lower()
		var result := SimulatorScript.step(Fixture.direct_network(kind, key, 20.0, 0.05), [Fixture.direct_demand(kind, key, 10.0, 8.0)], [], 1)
		_assert_ok(result, "%s execution failed" % kind)
		var profile: Dictionary = result.profile
		_assert_ok(ProfileScript.validate(profile), "%s execution profile rejected" % kind)
		_assert(String(profile.utility_kind) == kind, "%s profile kind mismatch" % kind)
		_assert(String(profile.status) == "BALANCED", "%s profile not balanced" % kind)
		_assert(profile.allocations.size() == 1, "%s allocation count mismatch" % kind)
		_assert(String(profile.allocations[0].status) == "FULL", "%s demand not fully allocated" % kind)
		_assert(absf(float(profile.allocations[0].delivered_per_tick) - 10.0) < 0.000001, "%s delivered amount mismatch" % kind)
		_assert(float(profile.total_loss) > 0.0, "%s link loss not recorded" % kind)

func _test_priority_losses_storage_and_shedding() -> void:
	var result := SimulatorScript.step(Fixture.power_network("priority"), [Fixture.lights_demand("priority"), Fixture.machine_demand("priority")], [Fixture.power_storage("priority", 20.0)], 1)
	_assert_ok(result, "Priority allocation failed")
	var profile: Dictionary = result.profile
	_assert(String(profile.status) == "DEGRADED", "Partial low-priority load not classified degraded")
	var machine := _allocation(profile, "utility-demand/power/priority/machine")
	var lights := _allocation(profile, "utility-demand/power/priority/lights")
	_assert(String(machine.status) == "FULL", "Critical machine was not allocated first")
	_assert(absf(float(machine.delivered_per_tick) - 70.0) < 0.000001, "Critical machine delivery mismatch")
	_assert(String(lights.status) == "PARTIAL", "Low-priority lights not partial")
	_assert(float(lights.delivered_per_tick) > 30.0 and float(lights.delivered_per_tick) < 40.0, "Low-priority allocation outside expected range")
	_assert(float(profile.total_loss) > 10.0, "Network loss summary too small")
	_assert(absf(float(profile.storage_states[0].stored_amount)) < 0.000001, "Battery was not discharged")
	_assert(float(_dispatch(profile, "utility-node/power/priority/battery").discharged) == 18.0, "Battery discharge output mismatch")
	_assert(float(_dispatch(profile, "utility-node/power/priority/generator").generated) == 100.0, "Generator dispatch mismatch")
	var insufficient := SimulatorScript.step(Fixture.power_network("shed", 30.0, true, 10.0), [Fixture.machine_demand("shed", 70.0, 60.0, 900), Fixture.lights_demand("shed", 20.0, 5.0, 100)], [Fixture.power_storage("shed", 0.0, 0, 0, 10.0)], 1)
	_assert_ok(insufficient, "Load-shedding simulation failed")
	_assert(String(insufficient.profile.status) == "SHEDDING", "Shed network status mismatch")
	_assert(String(_allocation(insufficient.profile, "utility-demand/power/shed/machine").status) == "SHED", "Critical demand below minimum was not shed atomically")
	_assert(float(_allocation(insufficient.profile, "utility-demand/power/shed/machine").delivered_per_tick) == 0.0, "Shed demand retained partial flow")
	_assert(String(_allocation(insufficient.profile, "utility-demand/power/shed/lights").status) == "FULL", "Released capacity did not serve lower-priority viable load")

func _test_storage_charge_discharge_and_link_failure() -> void:
	var charging := SimulatorScript.step(Fixture.power_network("charge", 100.0, true, 40.0), [Fixture.machine_demand("charge", 10.0, 10.0)], [Fixture.power_storage("charge", 0.0)], 1)
	_assert_ok(charging, "Storage charging tick failed")
	var charged_amount := float(charging.profile.storage_states[0].stored_amount)
	_assert(charged_amount > 15.0 and charged_amount <= 20.0, "Storage did not charge from surplus")
	_assert(float(_dispatch(charging.profile, "utility-node/power/charge/battery").charged) == charged_amount, "Storage charge dispatch mismatch")
	var offline_network := Fixture.power_network("backup", 100.0, false, 40.0)
	var backup := SimulatorScript.step(offline_network, [Fixture.machine_demand("backup", 10.0, 8.0)], [Fixture.power_storage("backup", 20.0)], 1)
	_assert_ok(backup, "Battery backup tick failed")
	_assert(String(backup.profile.status) == "BALANCED", "Battery backup did not keep critical demand online")
	_assert(String(backup.profile.allocations[0].status) == "FULL", "Battery backup allocation not full")
	_assert(float(backup.profile.storage_states[0].stored_amount) < 10.0, "Battery storage was not consumed")
	var empty := SimulatorScript.step(offline_network, [Fixture.machine_demand("backup", 10.0, 8.0)], [Fixture.power_storage("backup", 0.0)], 2)
	_assert_ok(empty, "Empty backup tick failed")
	_assert(String(empty.profile.status) == "OFFLINE", "No-source network not offline")
	_assert(String(empty.profile.allocations[0].status) == "SHED", "No-source demand not shed")
	var broken := Fixture.direct_network("DATA", "broken-link", 20.0)
	broken.links[0].enabled = false; broken.links[0].checksum = LinkScript.compute_checksum(broken.links[0]); broken.checksum = NetworkScript.compute_checksum(broken)
	var broken_result := SimulatorScript.step(broken, [Fixture.direct_demand("DATA", "broken-link", 5.0, 1.0)], [], 1)
	_assert_ok(broken_result, "Broken-link simulation failed")
	_assert(String(broken_result.profile.status) == "OFFLINE", "Disabled link did not isolate consumer")
	_assert(String(broken_result.profile.allocations[0].status) == "SHED", "Isolated data demand not shed")

func _test_c8_machine_requires_actual_allocation() -> void:
	var rt: Dictionary = _new_fabrication_runtime("machine")
	_assert_ok(_enqueue(rt, "machine"), "Machine job enqueue failed")
	var utility_result := SimulatorScript.step(Fixture.power_network("machine", 50.0, true, 20.0), [Fixture.machine_demand("machine", 10.0, 10.0)], [Fixture.power_storage("machine", 0.0, 0, 0, 20.0)], 1)
	_assert_ok(utility_result, "Machine power allocation failed")
	var lease_result := LeaseCompilerScript.compile("utility-lease/machine/tick-1", rt.profile, "fabrication-job/machine", rt.recipe, [Fixture.machine_requirement("machine", 1.0, 1.0)], [utility_result.profile], 1)
	_assert_ok(lease_result, "Machine utility lease compile failed")
	var lease: Dictionary = lease_result.lease
	_assert_ok(LeaseScript.validate(lease), "Machine utility lease rejected")
	_assert(String(lease.status) == "ONLINE" and int(lease.max_work_units) == 10, "Machine lease capacity mismatch")
	var executable = ExecutableRuntimeScript.new(); _assert_ok(executable.setup(rt.process), "Executable fabrication runtime setup failed")
	_assert_ok(executable.reserve_job("fabrication-job/machine", rt.profile, lease), "Allocated machine could not reserve job")
	var first := executable.advance_job("fabrication-job/machine", rt.profile, 6, "operation/machine/utility-progress-1", lease)
	_assert_ok(first, "Allocated machine first progress failed")
	_assert(int(rt.queue.get_job("fabrication-job/machine").work_completed) == 6, "First allocated progress mismatch")
	var exceeded := executable.advance_job("fabrication-job/machine", rt.profile, 5, "operation/machine/utility-progress-over", lease)
	_assert_error(exceeded, "CONSTRUCTION_FABRICATION_UTILITY_LEASE_CAPACITY_EXCEEDED", "Machine exceeded utility lease")
	_assert(int(rt.queue.get_job("fabrication-job/machine").work_completed) == 6, "Rejected over-capacity progress changed job")
	var second_utility := SimulatorScript.step(Fixture.power_network("machine", 50.0, true, 20.0), [Fixture.machine_demand("machine", 10.0, 10.0)], utility_result.profile.storage_states, 2)
	_assert_ok(second_utility, "Second utility tick failed")
	var second_lease_result := LeaseCompilerScript.compile("utility-lease/machine/tick-2", rt.profile, "fabrication-job/machine", rt.recipe, [Fixture.machine_requirement("machine", 1.0, 1.0)], [second_utility.profile], 2)
	_assert_ok(second_lease_result, "Second machine lease compile failed")
	_assert_ok(executable.advance_job("fabrication-job/machine", rt.profile, 4, "operation/machine/utility-progress-2", second_lease_result.lease), "Second allocated progress failed")
	_assert(int(rt.queue.get_job("fabrication-job/machine").work_completed) == 10, "Allocated work did not complete recipe")
	_assert_ok(executable.complete_job("fabrication-job/machine", rt.profile, second_lease_result.lease), "Allocated machine completion failed")
	_assert(String(rt.queue.get_job("fabrication-job/machine").status) == "COMPLETED", "Allocated machine job not completed")
	_assert(not rt.adapter.get_item_projection("item/fabricated/machine/beam").is_empty(), "Allocated machine did not produce output")
	var blocked_rt: Dictionary = _new_fabrication_runtime("blocked")
	_assert_ok(_enqueue(blocked_rt, "blocked"), "Blocked job enqueue failed")
	var no_power := SimulatorScript.step(Fixture.power_network("blocked", 50.0, false, 20.0), [Fixture.machine_demand("blocked", 10.0, 10.0)], [Fixture.power_storage("blocked", 0.0, 0, 0, 20.0)], 1)
	_assert_ok(no_power, "No-power profile compile failed")
	var offline_lease_result := LeaseCompilerScript.compile("utility-lease/blocked/tick-1", blocked_rt.profile, "fabrication-job/blocked", blocked_rt.recipe, [Fixture.machine_requirement("blocked", 1.0, 1.0)], [no_power.profile], 1)
	_assert_ok(offline_lease_result, "Offline lease compile failed")
	_assert(String(offline_lease_result.lease.status) == "OFFLINE", "Shed allocation produced online lease")
	var blocked_exec = ExecutableRuntimeScript.new(); blocked_exec.setup(blocked_rt.process)
	_assert_error(blocked_exec.reserve_job("fabrication-job/blocked", blocked_rt.profile, offline_lease_result.lease), "CONSTRUCTION_FABRICATION_UTILITY_LEASE_OFFLINE", "Unpowered machine reserved materials")
	_assert(String(blocked_rt.queue.get_job("fabrication-job/blocked").status) == "QUEUED", "Utility-gated rejection changed job")

func _test_machine_lease_replay_and_recovery() -> void:
	var rt: Dictionary = _new_fabrication_runtime("replay")
	_assert_ok(_enqueue(rt, "replay"), "Replay job enqueue failed")
	var utility: Dictionary = SimulatorScript.step(Fixture.power_network("replay", 50.0, true, 20.0), [Fixture.machine_demand("replay", 10.0, 10.0)], [Fixture.power_storage("replay", 0.0, 0, 0, 20.0)], 1)
	var lease: Dictionary = LeaseCompilerScript.compile("utility-lease/replay/tick-1", rt.profile, "fabrication-job/replay", rt.recipe, [Fixture.machine_requirement("replay", 1.0, 1.0)], [utility.profile], 1).lease
	var executable = ExecutableRuntimeScript.new(); executable.setup(rt.process)
	_assert_ok(executable.reserve_job("fabrication-job/replay", rt.profile, lease), "Replay reservation failed")
	var first := executable.advance_job("fabrication-job/replay", rt.profile, 4, "operation/replay/utility-progress", lease)
	_assert_ok(first, "Replay first progress failed")
	var generation := int(executable.get_generation())
	var replay := executable.advance_job("fabrication-job/replay", rt.profile, 4, "operation/replay/utility-progress", lease)
	_assert_ok(replay, "Executable runtime replay failed")
	_assert(bool(replay.utility_runtime_replay), "Executable runtime replay not identified")
	_assert(int(executable.get_generation()) == generation, "Executable runtime replay changed generation")
	_assert(int(rt.queue.get_job("fabrication-job/replay").work_completed) == 4, "Executable runtime replay duplicated work")
	var conflict := executable.advance_job("fabrication-job/replay", rt.profile, 3, "operation/replay/utility-progress", lease)
	_assert_error(conflict, "CONSTRUCTION_EXECUTABLE_FABRICATION_OPERATION_ID_CONFLICT", "Executable runtime accepted operation conflict")
	var state := executable.export_state()
	var restarted = ExecutableRuntimeScript.new(); restarted.setup(rt.process); _assert_ok(restarted.load_state(state), "Executable runtime recovery failed")
	var recovered := restarted.advance_job("fabrication-job/replay", rt.profile, 4, "operation/replay/utility-progress", lease)
	_assert_ok(recovered, "Recovered executable runtime replay failed")
	_assert(bool(recovered.utility_runtime_replay), "Recovered runtime did not replay terminal operation")
	_assert(int(rt.queue.get_job("fabrication-job/replay").work_completed) == 4, "Recovered replay duplicated work")
	_assert(int(restarted.get_used_work_units(String(lease.checksum))) == 4, "Recovered lease usage mismatch")

func _new_fabrication_runtime(key: String) -> Dictionary:
	var graph := C8Fixture.machine_item_graph(key)
	var adapter = AdapterScript.new(); _assert_ok(adapter.setup(graph.items, [graph.snapshot]), "Adapter setup failed")
	var catalog = CatalogScript.new(); _assert_ok(catalog.setup(), "Catalog setup failed")
	var recipe := C8Fixture.recipe(); _assert_ok(catalog.publish(recipe), "Recipe publish failed")
	var queue = QueueScript.new(); _assert_ok(queue.setup(), "Queue setup failed")
	var process = FabricationProcessScript.new(); _assert_ok(process.setup(adapter, catalog, queue), "Fabrication process setup failed")
	var profile_result := MachineCompilerScript.compile(graph.snapshot, C8Fixture.machine_definition(key), C8Fixture.behavior_profile(key, graph.snapshot), C8Fixture.powered_spatial_profile("power-%s" % key))
	_assert_ok(profile_result, "Machine profile compile failed")
	return {"adapter": adapter, "catalog": catalog, "queue": queue, "process": process, "profile": profile_result.profile, "recipe": recipe, "snapshot": graph.snapshot}
func _enqueue(runtime: Dictionary, key: String) -> Dictionary:
	return runtime.process.enqueue_job("fabrication-job/%s" % key, "fabrication-recipe/structural-beam", 1, runtime.profile, C8Fixture.material_projections(key), {"beam": "item/fabricated/%s/beam" % key}, 500)
func _allocation(profile: Dictionary, demand_id: String) -> Dictionary:
	for allocation in profile.allocations:
		if String(allocation.demand_id) == demand_id: return allocation
	return {}
func _dispatch(profile: Dictionary, node_id: String) -> Dictionary:
	for row in profile.source_dispatch:
		if String(row.node_id) == node_id: return row
	return {}
func _assert_ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, code: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void: assertions += 1; if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C15 executable utilities integration: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C15 executable utilities integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
