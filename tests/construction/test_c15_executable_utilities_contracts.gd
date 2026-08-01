extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Fixture = preload("res://tests/construction/fixtures/c15_executable_utilities_fixture.gd")
const NodeScript = preload("res://scripts/construction/utilities/construction_utility_node_definition.gd")
const LinkScript = preload("res://scripts/construction/utilities/construction_utility_link_definition.gd")
const NetworkScript = preload("res://scripts/construction/utilities/construction_utility_network_definition.gd")
const DemandScript = preload("res://scripts/construction/utilities/construction_utility_demand.gd")
const StorageScript = preload("res://scripts/construction/utilities/construction_utility_storage_state.gd")
const AllocationScript = preload("res://scripts/construction/utilities/construction_utility_allocation.gd")
const ProfileScript = preload("res://scripts/construction/utilities/construction_utility_execution_profile.gd")
const SimulatorScript = preload("res://scripts/construction/utilities/construction_utility_simulator.gd")
const StoreScript = preload("res://scripts/construction/utilities/construction_utility_profile_store.gd")
const PersistenceScript = preload("res://scripts/construction/utilities/construction_utility_persistence.gd")
const SummaryScript = preload("res://scripts/construction/utilities/construction_utility_summary.gd")
const LeaseScript = preload("res://scripts/construction/utilities/construction_machine_utility_lease.gd")
const RuntimeScript = preload("res://scripts/construction/utilities/construction_executable_fabrication_runtime.gd")

class MemoryStorage:
	extends RefCounted
	var values := {}
	func put(key: String, value: Dictionary) -> Dictionary: values[key] = value.duplicate(true); return {"success": true, "error_code": "", "message": ""}
	func get_value(key: String) -> Dictionary:
		if not values.has(key): return {"success": false, "error_code": "NOT_FOUND", "message": "NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "value": Dictionary(values[key]).duplicate(true)}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_node_and_link_contracts()
	_test_network_demand_and_storage_contracts()
	_test_allocation_and_profile_contracts()
	_test_store_summary_and_persistence()
	_test_lease_and_runtime_state_contracts()
	_finish()

func _test_node_and_link_contracts() -> void:
	var network := Fixture.power_network("contracts")
	for node in network.nodes: _assert_ok(NodeScript.validate(node), "Valid utility node rejected")
	for link in network.links: _assert_ok(LinkScript.validate(link), "Valid utility link rejected")
	_assert(network.nodes.size() == 5, "Power fixture node count mismatch")
	_assert(network.links.size() == 4, "Power fixture link count mismatch")
	var source: Dictionary = network.nodes.filter(func(n): return String(n.node_kind) == "SOURCE")[0]
	_assert(String(source.utility_kind) == "POWER", "Source utility kind mismatch")
	_assert(float(source.capacity_per_tick) == 100.0, "Source capacity mismatch")
	_assert(String(source.checksum).length() == 64, "Source checksum missing")
	var unknown := source.duplicate(true); unknown["unexpected_field"] = true
	_assert_error(NodeScript.validate(unknown), "UNEXPECTED_FIELD", "Node accepted unknown field")
	var bad_kind := source.duplicate(true); bad_kind.utility_kind = "STEAM"; bad_kind.checksum = NodeScript.compute_checksum(bad_kind)
	_assert_error(NodeScript.validate(bad_kind), "INVALID_CONSTRUCTION_UTILITY_KIND", "Node accepted unknown utility kind")
	var bad_capacity := source.duplicate(true); bad_capacity.capacity_per_tick = 0.0; bad_capacity.checksum = NodeScript.compute_checksum(bad_capacity)
	_assert_error(NodeScript.validate(bad_capacity), "CONSTRUCTION_UTILITY_SUPPLY_CAPACITY_REQUIRED", "Source accepted zero capacity")
	var bad_priority := source.duplicate(true); bad_priority.dispatch_priority = 1001; bad_priority.checksum = NodeScript.compute_checksum(bad_priority)
	_assert_error(NodeScript.validate(bad_priority), "INVALID_CONSTRUCTION_UTILITY_DISPATCH_PRIORITY", "Node accepted invalid priority")
	var battery: Dictionary = network.nodes.filter(func(n): return String(n.node_kind) == "STORAGE")[0]
	var bad_storage := battery.duplicate(true); bad_storage.properties.erase("charge_efficiency"); bad_storage.checksum = NodeScript.compute_checksum(bad_storage)
	_assert_error(NodeScript.validate(bad_storage), "INVALID_CONSTRUCTION_UTILITY_STORAGE_EFFICIENCY", "Storage accepted missing efficiency")
	var link: Dictionary = network.links[0]
	_assert(String(link.node_a_id) < String(link.node_b_id), "Link endpoints not canonical")
	_assert(float(link.loss_fraction) >= 0.0, "Link loss invalid")
	var reverse: Dictionary = link.duplicate(true); var a: String = String(reverse.node_a_id); reverse.node_a_id = reverse.node_b_id; reverse.node_b_id = a; reverse.checksum = LinkScript.compute_checksum(reverse)
	_assert_error(LinkScript.validate(reverse), "NON_CANONICAL_CONSTRUCTION_UTILITY_LINK_ENDPOINTS", "Link accepted reversed endpoints")
	var total_loss := link.duplicate(true); total_loss.loss_fraction = 1.0; total_loss.checksum = LinkScript.compute_checksum(total_loss)
	_assert_error(LinkScript.validate(total_loss), "INVALID_CONSTRUCTION_UTILITY_LINK_LOSS", "Link accepted total loss")
	var disabled := LinkScript.create("utility-link/power/contracts/disabled", String(network.network_id), "POWER", "utility-node/power/contracts/bus", "utility-node/power/contracts/machine", 5.0, 0.0, false)
	_assert_ok(LinkScript.validate(disabled), "Disabled link rejected")

func _test_network_demand_and_storage_contracts() -> void:
	for kind in ["POWER", "WATER", "AIR", "HEAT", "DATA"]:
		var network := Fixture.direct_network(kind, "contract-%s" % kind.to_lower())
		_assert_ok(NetworkScript.validate(network), "Valid %s network rejected" % kind)
		_assert(String(network.unit).length() > 0, "%s unit missing" % kind)
		_assert(String(network.checksum).length() == 64, "%s network checksum missing" % kind)
		var demand := Fixture.direct_demand(kind, "contract-%s" % kind.to_lower())
		_assert_ok(DemandScript.validate(demand), "Valid %s demand rejected" % kind)
	var network := Fixture.power_network("network-contract")
	var no_source := network.duplicate(true); no_source.nodes = no_source.nodes.filter(func(n): return String(n.node_kind) != "SOURCE" and String(n.node_kind) != "STORAGE"); no_source.links = []; no_source.checksum = NetworkScript.compute_checksum(no_source)
	_assert_error(NetworkScript.validate(no_source), "CONSTRUCTION_UTILITY_NETWORK_SUPPLY_REQUIRED", "Network accepted no supply")
	var wrong_unit := network.duplicate(true); wrong_unit.unit = "MW"; wrong_unit.checksum = NetworkScript.compute_checksum(wrong_unit)
	_assert_error(NetworkScript.validate(wrong_unit), "INVALID_CONSTRUCTION_UTILITY_NETWORK_KIND_OR_UNIT", "Network accepted wrong unit")
	var demand := Fixture.machine_demand("network-contract")
	_assert_ok(DemandScript.validate(demand), "Valid machine demand rejected")
	_assert(int(demand.priority) == 900, "Demand priority mismatch")
	var invalid_min := demand.duplicate(true); invalid_min.minimum_required_per_tick = 100.0; invalid_min.checksum = DemandScript.compute_checksum(invalid_min)
	_assert_error(DemandScript.validate(invalid_min), "INVALID_CONSTRUCTION_UTILITY_DEMAND_QUANTITY", "Demand accepted minimum above request")
	var invalid_group := demand.duplicate(true); invalid_group.shed_group = ""; invalid_group.checksum = DemandScript.compute_checksum(invalid_group)
	_assert_error(DemandScript.validate(invalid_group), "INVALID_CONSTRUCTION_UTILITY_SHED_GROUP", "Demand accepted empty shed group")
	var storage := Fixture.power_storage("network-contract", 20.0)
	_assert_ok(StorageScript.validate(storage), "Valid storage state rejected")
	_assert(float(storage.stored_amount) == 20.0, "Storage amount mismatch")
	var overflow := storage.duplicate(true); overflow.stored_amount = 50.0; overflow.checksum = StorageScript.compute_checksum(overflow)
	_assert_error(StorageScript.validate(overflow), "INVALID_CONSTRUCTION_UTILITY_STORAGE_STATE_AMOUNT", "Storage accepted overflow")
	var negative_tick := storage.duplicate(true); negative_tick.tick = -1; negative_tick.checksum = StorageScript.compute_checksum(negative_tick)
	_assert_error(StorageScript.validate(negative_tick), "INVALID_CONSTRUCTION_UTILITY_STORAGE_STATE_VERSION", "Storage accepted negative tick")

func _test_allocation_and_profile_contracts() -> void:
	var network := Fixture.power_network("profile")
	var result := SimulatorScript.step(network, [Fixture.machine_demand("profile"), Fixture.lights_demand("profile")], [Fixture.power_storage("profile", 20.0)], 1)
	_assert_ok(result, "Utility simulation failed")
	var profile: Dictionary = result.profile
	_assert_ok(ProfileScript.validate(profile), "Execution profile rejected")
	_assert(profile.allocations.size() == 2, "Allocation count mismatch")
	_assert(String(profile.checksum).length() == 64, "Profile checksum missing")
	_assert(not UtilsScript.canonical_json(profile).is_empty(), "Profile is not JSON-safe")
	for allocation in profile.allocations: _assert_ok(AllocationScript.validate(allocation), "Allocation rejected")
	var machine := _allocation(profile, "utility-demand/power/profile/machine")
	_assert(String(machine.status) == "FULL", "Critical machine allocation not full")
	_assert(absf(float(machine.delivered_per_tick) - 70.0) < 0.000001, "Critical machine delivery mismatch")
	_assert(float(machine.loss_per_tick) > 0.0, "Network losses not recorded")
	var tampered := machine.duplicate(true); tampered.delivered_per_tick = float(tampered.delivered_per_tick) - 1.0; tampered.checksum = AllocationScript.compute_checksum(tampered)
	_assert_error(AllocationScript.validate(tampered), "CONSTRUCTION_UTILITY_ALLOCATION_SUMMARY_MISMATCH", "Allocation accepted tampered total")
	var bad_status := machine.duplicate(true); bad_status.status = "SHED"; bad_status.checksum = AllocationScript.compute_checksum(bad_status)
	_assert_error(AllocationScript.validate(bad_status), "CONSTRUCTION_UTILITY_ALLOCATION_STATUS_MISMATCH", "Allocation accepted wrong status")
	var profile_tampered := profile.duplicate(true); profile_tampered.total_delivered = float(profile_tampered.total_delivered) + 1.0; profile_tampered.checksum = ProfileScript.compute_checksum(profile_tampered)
	_assert_error(ProfileScript.validate(profile_tampered), "CONSTRUCTION_UTILITY_EXECUTION_PROFILE_TOTAL_MISMATCH", "Profile accepted tampered total")
	var wrong_status := profile.duplicate(true); wrong_status.status = "BALANCED"; wrong_status.checksum = ProfileScript.compute_checksum(wrong_status)
	_assert_error(ProfileScript.validate(wrong_status), "CONSTRUCTION_UTILITY_EXECUTION_PROFILE_STATUS_MISMATCH", "Profile accepted wrong aggregate status")

func _test_store_summary_and_persistence() -> void:
	var profile: Dictionary = SimulatorScript.step(Fixture.power_network("store"), [Fixture.machine_demand("store")], [Fixture.power_storage("store", 10.0)], 1).profile
	var store = StoreScript.new()
	var published := store.publish(profile); _assert_ok(published, "Profile publish failed")
	_assert(int(store.get_generation()) == 1, "Store generation mismatch")
	var replay := store.publish(profile); _assert_ok(replay, "Profile replay failed")
	_assert(bool(replay.replay) and int(store.get_generation()) == 1, "Profile replay changed generation")
	var older := profile.duplicate(true); older.tick = 0; older.checksum = ProfileScript.compute_checksum(older)
	_assert_error(store.publish(older), "STALE_CONSTRUCTION_UTILITY_EXECUTION_PROFILE", "Store accepted stale profile")
	var same_tick_result := SimulatorScript.step(Fixture.power_network("store"), [Fixture.machine_demand("store", 65.0, 60.0)], [Fixture.power_storage("store", 10.0)], 1)
	_assert_ok(same_tick_result, "Same-tick alternate profile compile failed")
	_assert_error(store.publish(same_tick_result.profile), "CONSTRUCTION_UTILITY_SAME_TICK_MUTATION", "Store accepted same-tick mutation")
	var summary_result := SummaryScript.compile(profile); _assert_ok(summary_result, "Summary compile failed")
	_assert_ok(SummaryScript.validate(summary_result.summary), "Summary rejected")
	_assert(int(summary_result.summary.demand_count) == 1, "Summary demand count mismatch")
	var memory = MemoryStorage.new(); _assert_ok(PersistenceScript.save(memory, store), "Utility persistence save failed")
	var restored = StoreScript.new(); _assert_ok(PersistenceScript.load(memory, restored), "Utility persistence load failed")
	_assert(UtilsScript.canonical_json(restored.export_state()) == UtilsScript.canonical_json(store.export_state()), "Utility persistence roundtrip changed state")
	var tampered: Dictionary = store.export_state(); tampered.profiles[0].total_delivered = 999.0; tampered.profiles[0].checksum = ProfileScript.compute_checksum(tampered.profiles[0]); tampered.checksum = StoreScript.compute_state_checksum(tampered)
	var clean = StoreScript.new(); _assert_error(clean.load_state(tampered), "CONSTRUCTION_UTILITY_EXECUTION_PROFILE_TOTAL_MISMATCH", "Store accepted inconsistent profile")
	_assert(clean.get_all().is_empty(), "Rejected store load mutated state")

func _test_lease_and_runtime_state_contracts() -> void:
	var requirement := Fixture.machine_requirement("lease", 5.0, 0.8)
	var lease := LeaseScript.create("utility-lease/lease/cell", "construct/fabrication/lease", "fabrication-job/lease", "a".repeat(64), "b".repeat(64), 1, "ONLINE", 4, [requirement], {"utility-network/power/lease": "c".repeat(64)}, {"utility-demand/power/lease/machine": "d".repeat(64)})
	_assert_ok(LeaseScript.validate(lease), "Valid machine utility lease rejected")
	_assert(int(lease.max_work_units) == 4, "Lease work capacity mismatch")
	var offline := lease.duplicate(true); offline.status = "OFFLINE"; offline.checksum = LeaseScript.compute_checksum(offline)
	_assert_error(LeaseScript.validate(offline), "OFFLINE_CONSTRUCTION_MACHINE_UTILITY_LEASE_HAS_WORK", "Offline lease accepted work capacity")
	var missing_pin := lease.duplicate(true); missing_pin.profile_checksums = {}; missing_pin.checksum = LeaseScript.compute_checksum(missing_pin)
	_assert_error(LeaseScript.validate(missing_pin), "CONSTRUCTION_MACHINE_UTILITY_LEASE_PIN_MISSING", "Lease accepted missing profile pin")
	var runtime_state := {"schema": RuntimeScript.STATE_SCHEMA, "generation": 1, "lease_usage": [{"lease_checksum": String(lease.checksum), "used_work_units": 2}], "terminal_operations": [{"operation_id": "operation/fabrication/lease/progress", "request_checksum": "e".repeat(64), "result": {"success": true, "job": {"status": "PROCESSING"}}}], "checksum": ""}
	runtime_state.checksum = RuntimeScript.compute_state_checksum(runtime_state)
	_assert_ok(RuntimeScript.validate_state(runtime_state), "Valid executable fabrication runtime state rejected")
	var runtime = RuntimeScript.new(); _assert_ok(runtime.load_state(runtime_state), "Runtime state load failed")
	_assert(int(runtime.get_generation()) == 1, "Runtime generation load mismatch")
	_assert(int(runtime.get_used_work_units(String(lease.checksum))) == 2, "Runtime lease usage load mismatch")
	var tampered := runtime_state.duplicate(true); tampered.lease_usage[0].used_work_units = -1; tampered.checksum = RuntimeScript.compute_state_checksum(tampered)
	_assert_error(RuntimeScript.validate_state(tampered), "NON_CANONICAL_CONSTRUCTION_EXECUTABLE_FABRICATION_LEASE_USAGE", "Runtime accepted negative lease usage")

func _allocation(profile: Dictionary, demand_id: String) -> Dictionary:
	for allocation in profile.allocations:
		if String(allocation.demand_id) == demand_id: return allocation
	return {}
func _assert_ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, code: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void: assertions += 1; if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C15 executable utilities contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C15 executable utilities contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
