extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C13Fixture = preload("res://tests/construction/fixtures/c13_runtime_projection_fixture.gd")
const Request = preload("res://scripts/construction/streaming/construction_streaming_request.gd")
const Policy = preload("res://scripts/construction/streaming/construction_streaming_policy.gd")
const Interest = preload("res://scripts/construction/streaming/construction_interest_sample.gd")
const StructuralSummary = preload("res://scripts/construction/structural/construction_structural_summary.gd")
const UtilitySummary = preload("res://scripts/construction/utilities/construction_utility_summary.gd")
const Level = preload("res://scripts/construction/streaming/construction_activity_level.gd")

const SERVER_A := "server/streaming/alpha"
const SERVER_B := "server/streaming/beta"

static func policy(summary_budget: int = 360, simulation_budget: int = 6, presentation_budget: int = 100, maximum_steps: int = 3) -> Dictionary:
	return Policy.create(10.0, 40.0, 100.0, 5.0, 3, summary_budget, simulation_budget, presentation_budget, 2, maximum_steps)

static func request(key: String, authority_epoch: int = 1, owner_server_id: String = SERVER_A, local_server_id: String = SERVER_A, authority_mode: String = Request.OWNER, minimum_level: String = Level.DORMANT, costs: Dictionary = {}, origin: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	var runtime := C13Fixture.beam_request("streaming-%s" % key, 0, 4.0, origin)
	var snapshot: Dictionary = runtime["construct_snapshot"]
	var structural := {
		"schema": StructuralSummary.SCHEMA,
		"construct_id": String(snapshot["construct_id"]),
		"load_case_id": "load-case/streaming/%s/gravity" % key,
		"profile_checksum": Utils.payload_hash({"structural": key}),
		"structural_state": "STABLE",
		"maximum_utilization": 0.25,
		"part_count": snapshot["parts"].size(),
		"bond_count": snapshot["bonds"].size(),
		"load_path_count": 1,
		"critical_part_ids": [],
		"critical_bond_ids": [],
		"unsupported_part_count": 0,
		"checksum": "",
	}
	structural["checksum"] = StructuralSummary.compute_checksum(structural)
	var utility := {
		"schema": UtilitySummary.SCHEMA,
		"network_id": "utility-network/streaming/%s/power" % key,
		"utility_kind": "POWER",
		"tick": 0,
		"profile_checksum": Utils.payload_hash({"utility": key}),
		"status": "BALANCED",
		"demand_count": 1,
		"shed_demand_ids": [],
		"total_requested": 10.0,
		"total_delivered": 10.0,
		"storage_amount": 5.0,
		"checksum": "",
	}
	utility["checksum"] = UtilitySummary.compute_checksum(utility)
	var actual_costs := {"summary_bytes": 120, "simulation_units": 3, "presentation_bytes": 100}
	for cost_key in costs: actual_costs[cost_key] = costs[cost_key]
	return Request.create(snapshot, authority_epoch, owner_server_id, local_server_id, authority_mode, runtime, structural, [utility], ["LOAD_BEARING_MEMBER", "POWERED"], ["fabrication-job/streaming/%s" % key], ["operation/streaming/%s/pending" % key], [float(origin[0]), float(origin[1]), float(origin[2]), float(origin[0]) + 4.0, float(origin[1]) + 0.2, float(origin[2]) + 0.2], 200.0, actual_costs, minimum_level)

static func sample(key: String, tick: int, distance_m: float, visible: bool = false, selected: bool = false, interacting: bool = false, priority_boost: int = 0) -> Dictionary:
	return Interest.create("observer/player/main", String(request(key)["construct_id"]), tick, distance_m, visible, selected, interacting, priority_boost)

static func sample_for(request_value: Dictionary, tick: int, distance_m: float, visible: bool = false, selected: bool = false, interacting: bool = false, priority_boost: int = 0) -> Dictionary:
	return Interest.create("observer/player/main", String(request_value["construct_id"]), tick, distance_m, visible, selected, interacting, priority_boost)

class FakeSimulationDriver extends RefCounted:
	var calls: Array = []
	var elapsed_by_construct: Dictionary = {}
	func catch_up(request_value: Dictionary, plan: Dictionary) -> Dictionary:
		var id := String(request_value["construct_id"]); var elapsed := int(elapsed_by_construct.get(id, 0))
		for step in plan["steps"]: elapsed += int(step["elapsed_ticks"])
		elapsed_by_construct[id] = elapsed
		calls.append({"construct_id": id, "plan": plan.duplicate(true), "pending_job_ids": request_value["pending_job_ids"].duplicate(true), "pending_operation_ids": request_value["pending_operation_ids"].duplicate(true)})
		return {"success": true, "error_code": "", "message": "", "simulation_checksum": Utils.payload_hash({"construct_id": id, "elapsed": elapsed, "plan_checksum": plan["checksum"], "jobs": request_value["pending_job_ids"], "operations": request_value["pending_operation_ids"]})}

class MemoryStore extends RefCounted:
	var values: Dictionary = {}
	func save_state(key: String, state: Dictionary) -> Dictionary:
		values[key] = state.duplicate(true); return {"success": true, "error_code": "", "message": ""}
	func load_state(key: String) -> Dictionary:
		if not values.has(key): return {"success": false, "error_code": "NOT_FOUND", "message": "NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "state": values[key].duplicate(true)}
