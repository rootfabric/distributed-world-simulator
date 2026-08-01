extends Node

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Level = preload("res://scripts/construction/streaming/construction_activity_level.gd")
const Policy = preload("res://scripts/construction/streaming/construction_streaming_policy.gd")
const Interest = preload("res://scripts/construction/streaming/construction_interest_sample.gd")
const Request = preload("res://scripts/construction/streaming/construction_streaming_request.gd")
const Summary = preload("res://scripts/construction/streaming/construction_construct_summary.gd")
const Record = preload("res://scripts/construction/streaming/construction_activity_record.gd")
const CatchUp = preload("res://scripts/construction/streaming/construction_catch_up_plan.gd")
const BudgetReport = preload("res://scripts/construction/streaming/construction_streaming_budget_report.gd")
const State = preload("res://scripts/construction/streaming/construction_streaming_state.gd")
const RuntimeCompiler = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_compiler.gd")
const Lod = preload("res://scripts/construction/streaming/construction_lod_profile.gd")
const LodAdapter = preload("res://scripts/construction/streaming/construction_lod_projection_adapter.gd")

var _policy: Dictionary = {}
var _runtime = null
var _simulation = null
var _requests: Dictionary = {}
var _records: Dictionary = {}
var _summaries: Dictionary = {}
var _operations: Dictionary = {}
var _tick := 0
var _generation := 0

func setup(policy: Dictionary, runtime_synchronizer = null, simulation_driver = null) -> Dictionary:
	var checked := Policy.validate(policy); if not bool(checked.get("success", false)): return checked
	if runtime_synchronizer != null and (not runtime_synchronizer.has_method("upsert") or not runtime_synchronizer.has_method("remove_construct")): return _failure("INVALID_CONSTRUCTION_STREAMING_RUNTIME_SYNCHRONIZER")
	if simulation_driver != null and not simulation_driver.has_method("catch_up"): return _failure("INVALID_CONSTRUCTION_STREAMING_SIMULATION_DRIVER")
	_policy = policy.duplicate(true); _runtime = runtime_synchronizer; _simulation = simulation_driver
	return _success({"policy_checksum": String(_policy["checksum"])})

func register_construct(request: Dictionary, tick: int = 0) -> Dictionary:
	if _policy.is_empty(): return _failure("CONSTRUCTION_STREAMING_CONTROLLER_NOT_CONFIGURED")
	var checked := Request.validate(request); if not bool(checked.get("success", false)): return checked
	if tick < 0: return _failure("INVALID_CONSTRUCTION_STREAMING_REGISTER_TICK")
	var id := String(request["construct_id"])
	if _requests.has(id):
		var current: Dictionary = _requests[id]
		if String(current["checksum"]) == String(request["checksum"]): return _success({"replay": true, "generation": _generation})
		if int(request["authority_epoch"]) < int(current["authority_epoch"]): return _failure("STALE_CONSTRUCTION_STREAMING_AUTHORITY_EPOCH")
		var current_snapshot: Dictionary = current["construct_snapshot"]; var next_snapshot: Dictionary = request["construct_snapshot"]
		if int(request["authority_epoch"]) == int(current["authority_epoch"]) and int(next_snapshot["state_revision"]) < int(current_snapshot["state_revision"]): return _failure("STALE_CONSTRUCTION_STREAMING_SOURCE_REVISION")
		if int(request["authority_epoch"]) == int(current["authority_epoch"]) and int(next_snapshot["state_revision"]) == int(current_snapshot["state_revision"]) and String(next_snapshot["checksum"]) != String(current_snapshot["checksum"]): return _failure("CONSTRUCTION_STREAMING_SOURCE_SAME_REVISION_MUTATION")
		_evict_runtime(id); _summaries.erase(id)
		var old_record: Dictionary = _records[id]
		var reset := Record.create(request, tick)
		reset["last_interest_tick"] = int(old_record["last_interest_tick"])
		reset["last_simulated_tick"] = int(old_record["last_simulated_tick"])
		reset["next_due_tick"] = int(old_record["next_due_tick"])
		reset["generation"] = int(old_record["generation"]) + 1
		reset["checksum"] = Record.compute_checksum(reset)
		_records[id] = reset
	elif _records.has(id):
		var persisted: Dictionary = _records[id]
		var snapshot: Dictionary = request["construct_snapshot"]
		if int(persisted["authority_epoch"]) != int(request["authority_epoch"]) or int(persisted["source_revision"]) != int(snapshot["state_revision"]) or String(persisted["source_checksum"]) != String(snapshot["checksum"]): return _failure("CONSTRUCTION_STREAMING_RESTORED_SOURCE_MISMATCH")
		_requests[id] = request.duplicate(true)
		return _success({"replay": true, "restored_source": true, "generation": _generation})
	else:
		_records[id] = Record.create(request, tick)
	_requests[id] = request.duplicate(true); _generation += 1
	return _success({"replay": false, "generation": _generation})

func unregister_construct(construct_id: String) -> Dictionary:
	if not _records.has(construct_id): return _success({"replay": true, "generation": _generation})
	_evict_runtime(construct_id); _requests.erase(construct_id); _records.erase(construct_id); _summaries.erase(construct_id); _generation += 1
	return _success({"replay": false, "generation": _generation})

func reconcile(samples: Array, tick: int) -> Dictionary:
	if _policy.is_empty(): return _failure("CONSTRUCTION_STREAMING_CONTROLLER_NOT_CONFIGURED")
	if tick < _tick: return _failure("CONSTRUCTION_STREAMING_TICK_ROLLBACK")
	var canonical_samples: Array = []
	for raw in samples:
		if typeof(raw) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_STREAMING_INTEREST_SAMPLE")
		var checked := Interest.validate(raw); if not bool(checked.get("success", false)): return checked
		if int(raw["tick"]) != tick: return _failure("CONSTRUCTION_STREAMING_INTEREST_TICK_MISMATCH")
		if not _requests.has(String(raw["construct_id"])): return _failure("CONSTRUCTION_STREAMING_UNKNOWN_CONSTRUCT")
		canonical_samples.append(Dictionary(raw).duplicate(true))
	canonical_samples.sort_custom(func(a,b):
		if String(a["construct_id"]) != String(b["construct_id"]): return String(a["construct_id"]) < String(b["construct_id"])
		return String(a["observer_id"]) < String(b["observer_id"]))
	var request_checksums: Array = []; var ids := _requests.keys(); ids.sort()
	for id in ids: request_checksums.append(String(_requests[id]["checksum"]))
	var input_checksum := Utils.payload_hash({"tick": tick, "samples": canonical_samples, "request_checksums": request_checksums, "policy_checksum": String(_policy["checksum"])})
	if _operations.has(tick):
		var terminal: Dictionary = _operations[tick]
		if String(terminal["input_checksum"]) != input_checksum: return _failure("CONSTRUCTION_STREAMING_RECONCILE_TICK_CONFLICT")
		var replay_report: Dictionary = terminal["report"].duplicate(true)
		return _success({"replay": true, "report": replay_report, "generation": _generation})

	var grouped := _group_samples(canonical_samples)
	var desired: Dictionary = {}; var scores: Dictionary = {}; var outside: Dictionary = {}; var reasons: Dictionary = {}
	for id in ids:
		var computed := _compute_interest(_records[id], Array(grouped.get(id, [])), tick)
		var level := Level.max_level(String(computed["level"]), String(_requests[id]["minimum_level"]))
		if String(_requests[id]["authority_mode"]) == Request.READ_ONLY and level == Level.SIMULATED: level = Level.SUMMARY
		desired[id] = level; scores[id] = int(computed["score"]); outside[id] = int(computed["outside_since"]); reasons[id] = []

	var effective := desired.duplicate(true)
	var allocation := _apply_budgets(effective, scores, reasons)
	if not bool(allocation.get("success", false)): return allocation
	effective = allocation["levels"]
	for id in ids:
		if String(effective[id]) == Level.PRESENTED:
			if Dictionary(_requests[id]["runtime_projection_request"]).is_empty(): return _failure("CONSTRUCTION_STREAMING_PRESENTATION_REQUEST_REQUIRED", {"construct_id": id})
			var compiled := RuntimeCompiler.compile(_requests[id]["runtime_projection_request"]); if not bool(compiled.get("success", false)): return compiled

	var changed := false
	for id in ids:
		var applied := _apply_level(String(id), String(desired[id]), String(effective[id]), int(scores[id]), int(outside[id]), Array(reasons[id]), tick, not Array(grouped.get(id, [])).is_empty())
		if not bool(applied.get("success", false)): return applied
		changed = changed or bool(applied.get("changed", false))
	if changed: _generation += 1
	_tick = tick
	var levels := {Level.DORMANT: [], Level.SUMMARY: [], Level.SIMULATED: [], Level.PRESENTED: []}
	var evicted: Array = []
	for id in ids:
		var record: Dictionary = _records[id]; levels[String(record["effective_level"])].append(id)
		if not Array(record["eviction_reasons"]).is_empty(): evicted.append(id)
	var budgets := {"summary_bytes": int(_policy["summary_budget_bytes"]), "simulation_units": int(_policy["simulation_budget_units"]), "presentation_bytes": int(_policy["presentation_budget_bytes"])}
	var report := BudgetReport.create(tick, budgets, allocation["used"], levels, evicted)
	_operations[tick] = {"tick": tick, "input_checksum": input_checksum, "report": report.duplicate(true)}
	return _success({"replay": false, "report": report, "generation": _generation})

func _compute_interest(record: Dictionary, samples: Array, tick: int) -> Dictionary:
	var distance := INF; var visible := false; var selected := false; var interacting := false; var boost := 0
	for sample in samples:
		distance = minf(distance, float(sample["distance_m"])); visible = visible or bool(sample["visible"]); selected = selected or bool(sample["selected"]); interacting = interacting or bool(sample["interacting"]); boost = maxi(boost, int(sample["priority_boost"]))
	var score := boost + (100000000 if interacting else 0) + (10000000 if selected else 0) + (1000000 if visible else 0)
	if distance < INF: score += maxi(0, 500000 - int(round(distance * 100.0)))
	score = maxi(score, 0)
	var level := Level.DORMANT; var h := float(_policy["hysteresis_m"]); var current := String(record["effective_level"])
	if interacting or selected or distance <= float(_policy["presented_distance_m"]): level = Level.PRESENTED
	elif current == Level.PRESENTED and distance <= float(_policy["presented_distance_m"]) + h: level = Level.PRESENTED
	elif distance <= float(_policy["simulated_distance_m"]): level = Level.SIMULATED
	elif current == Level.SIMULATED and distance <= float(_policy["simulated_distance_m"]) + h: level = Level.SIMULATED
	elif distance <= float(_policy["summary_distance_m"]): level = Level.SUMMARY
	elif current == Level.SUMMARY and distance <= float(_policy["summary_distance_m"]) + h: level = Level.SUMMARY
	var outside_since := int(record["outside_summary_since_tick"])
	if level == Level.DORMANT:
		if outside_since < 0: outside_since = tick
		if tick - outside_since < int(_policy["dormant_after_ticks"]): level = Level.SUMMARY
	else: outside_since = -1
	return {"level": level, "score": score, "outside_since": outside_since}

func _apply_budgets(levels: Dictionary, scores: Dictionary, reasons: Dictionary) -> Dictionary:
	var used_presentation := 0; var used_simulation := 0; var used_summary := 0
	var candidates := _sorted_candidates(levels, scores, Level.PRESENTED, false)
	for id in candidates:
		var request: Dictionary = _requests[id]; var cost := int(request["estimated_costs"]["presentation_bytes"])
		if used_presentation + cost <= int(_policy["presentation_budget_bytes"]): used_presentation += cost
		elif Level.rank(String(request["minimum_level"])) >= Level.rank(Level.PRESENTED): return _failure("CONSTRUCTION_STREAMING_PINNED_PRESENTATION_BUDGET_EXCEEDED", {"construct_id": id})
		else:
			levels[id] = Level.SUMMARY if String(request["authority_mode"]) == Request.READ_ONLY else Level.SIMULATED; reasons[id].append("PRESENTATION_BUDGET")
	candidates = _sorted_candidates(levels, scores, Level.SIMULATED, true)
	for id in candidates:
		var request: Dictionary = _requests[id]; var cost := int(request["estimated_costs"]["simulation_units"])
		if used_simulation + cost <= int(_policy["simulation_budget_units"]): used_simulation += cost
		elif Level.rank(String(request["minimum_level"])) >= Level.rank(Level.SIMULATED): return _failure("CONSTRUCTION_STREAMING_PINNED_SIMULATION_BUDGET_EXCEEDED", {"construct_id": id})
		else: levels[id] = Level.SUMMARY; reasons[id].append("SIMULATION_BUDGET")
	candidates = _sorted_candidates(levels, scores, Level.SUMMARY, false)
	for id in candidates:
		var request: Dictionary = _requests[id]; var cost := int(request["estimated_costs"]["summary_bytes"])
		if used_summary + cost <= int(_policy["summary_budget_bytes"]): used_summary += cost
		elif Level.rank(String(request["minimum_level"])) >= Level.rank(Level.SUMMARY): return _failure("CONSTRUCTION_STREAMING_PINNED_SUMMARY_BUDGET_EXCEEDED", {"construct_id": id})
		else: levels[id] = Level.DORMANT; reasons[id].append("SUMMARY_BUDGET")
	used_summary = 0
	used_simulation = 0
	used_presentation = 0
	for final_id in levels:
		var final_level := String(levels[final_id])
		var final_request: Dictionary = _requests[final_id]
		if Level.rank(final_level) >= Level.rank(Level.SUMMARY): used_summary += int(final_request["estimated_costs"]["summary_bytes"])
		if String(final_request["authority_mode"]) == Request.OWNER and Level.rank(final_level) >= Level.rank(Level.SIMULATED): used_simulation += int(final_request["estimated_costs"]["simulation_units"])
		if final_level == Level.PRESENTED: used_presentation += int(final_request["estimated_costs"]["presentation_bytes"])
	return _success({"levels": levels, "used": {"summary_bytes": used_summary, "simulation_units": used_simulation, "presentation_bytes": used_presentation}})

func _sorted_candidates(levels: Dictionary, scores: Dictionary, minimum: String, owner_only: bool) -> Array:
	var result: Array = []
	for id in levels:
		if Level.rank(String(levels[id])) < Level.rank(minimum): continue
		if owner_only and String(_requests[id]["authority_mode"]) != Request.OWNER: continue
		result.append(id)
	result.sort_custom(func(a,b):
		if int(scores[a]) != int(scores[b]): return int(scores[a]) > int(scores[b])
		return String(a) < String(b))
	return result

func _apply_level(id: String, requested_level: String, effective_level: String, score: int, outside_since: int, eviction_reasons: Array, tick: int, has_interest: bool) -> Dictionary:
	var request: Dictionary = _requests[id]; var before: Dictionary = _records[id]; var summary_checksum := String(before["summary_checksum"]); var runtime_checksum := String(before["runtime_descriptor_checksum"]); var simulation_checksum := String(before["simulation_checksum"]); var last_simulated := int(before["last_simulated_tick"]); var next_due := int(before["next_due_tick"])
	if Level.rank(effective_level) >= Level.rank(Level.SUMMARY):
		var compiled_summary := Summary.compile(request); if not bool(compiled_summary.get("success", false)): return compiled_summary
		_summaries[id] = compiled_summary["summary"].duplicate(true); summary_checksum = String(compiled_summary["summary"]["checksum"])
	else:
		_summaries.erase(id); summary_checksum = ""
	var owner_simulation := String(request["authority_mode"]) == Request.OWNER and Level.rank(effective_level) >= Level.rank(Level.SIMULATED)
	if owner_simulation and (Level.rank(String(before["effective_level"])) < Level.rank(Level.SIMULATED) or tick >= next_due):
		var plan_result := CatchUp.compile(id, last_simulated, tick, int(_policy["catch_up_interval_ticks"]), int(_policy["maximum_catch_up_steps"])); if not bool(plan_result.get("success", false)): return plan_result
		var plan: Dictionary = plan_result["plan"]; var simulated := _simulate(request, plan); if not bool(simulated.get("success", false)): return simulated
		simulation_checksum = String(simulated.get("simulation_checksum", Utils.payload_hash({"request_checksum": request["checksum"], "plan_checksum": plan["checksum"]})))
		if not plan["steps"].is_empty(): last_simulated = int(plan["steps"][-1]["tick"])
		else: last_simulated = tick
		next_due = last_simulated + int(_policy["catch_up_interval_ticks"])
	var lod_result := Lod.compile(id, effective_level, score)
	if not bool(lod_result.get("success", false)): return lod_result
	var lod_profile: Dictionary = lod_result["profile"]
	if effective_level == Level.PRESENTED:
		var presented: Dictionary
		if _runtime != null:
			presented = _runtime.upsert(request["runtime_projection_request"])
		else:
			var compiled_runtime: Dictionary = RuntimeCompiler.compile(request["runtime_projection_request"])
			presented = _success({"descriptor": compiled_runtime["descriptor"]})
		if not bool(presented.get("success", false)): return presented
		var descriptor: Dictionary = presented.get("descriptor", {}); runtime_checksum = String(descriptor.get("checksum", ""))
		if _runtime != null and _runtime.has_method("get_construct_node"):
			var runtime_node = _runtime.get_construct_node(id)
			var lod_applied := LodAdapter.apply(runtime_node, lod_profile); if not bool(lod_applied.get("success", false)): return lod_applied
	else:
		if String(before["effective_level"]) == Level.PRESENTED or not runtime_checksum.is_empty(): _evict_runtime(id)
		runtime_checksum = ""
	var updates := {"authority_epoch": int(request["authority_epoch"]), "source_revision": int(request["construct_snapshot"]["state_revision"]), "source_checksum": String(request["construct_snapshot"]["checksum"]), "requested_level": requested_level, "effective_level": effective_level, "minimum_level": String(request["minimum_level"]), "authority_mode": String(request["authority_mode"]), "lod_tier": String(lod_profile["lod_tier"]), "last_transition_tick": tick if effective_level != String(before["effective_level"]) else int(before["last_transition_tick"]), "last_interest_tick": tick if has_interest else int(before["last_interest_tick"]), "outside_summary_since_tick": outside_since, "last_simulated_tick": last_simulated, "next_due_tick": next_due, "interest_score": score, "estimated_costs": request["estimated_costs"].duplicate(true), "summary_checksum": summary_checksum, "runtime_descriptor_checksum": runtime_checksum, "simulation_checksum": simulation_checksum, "pending_job_ids": request["pending_job_ids"].duplicate(true), "pending_operation_ids": request["pending_operation_ids"].duplicate(true), "eviction_reasons": _sorted(eviction_reasons), "generation": int(before["generation"]) + 1}
	var after := Record.with_updates(before, updates)
	var changed := String(after["checksum"]) != String(before["checksum"])
	if not changed: after = before.duplicate(true)
	_records[id] = after
	return _success({"changed": changed})

func _simulate(request: Dictionary, plan: Dictionary) -> Dictionary:
	if _simulation == null: return _success({"simulation_checksum": Utils.payload_hash({"request_checksum": request["checksum"], "plan_checksum": plan["checksum"]})})
	var result: Dictionary = _simulation.catch_up(request.duplicate(true), plan.duplicate(true))
	if not bool(result.get("success", false)): return result
	var checksum := String(result.get("simulation_checksum", "")); if checksum.length() != 64: return _failure("INVALID_CONSTRUCTION_STREAMING_SIMULATION_RESULT")
	return result

func _evict_runtime(id: String) -> void:
	if _runtime != null: _runtime.remove_construct(id)

func _group_samples(samples: Array) -> Dictionary:
	var grouped := {}
	for sample in samples:
		var id := String(sample["construct_id"]); if not grouped.has(id): grouped[id] = []
		grouped[id].append(sample)
	return grouped

func export_state() -> Dictionary:
	var records: Array = []
	var summaries: Array = []
	var operations: Array = []
	var ids := _records.keys()
	ids.sort()
	for id in ids:
		records.append(_records[id].duplicate(true))
	ids = _summaries.keys()
	ids.sort()
	for id in ids:
		summaries.append(_summaries[id].duplicate(true))
	var ticks := _operations.keys()
	ticks.sort()
	for operation_tick in ticks:
		operations.append(_operations[operation_tick].duplicate(true))
	return State.create(_tick, _generation, String(_policy.get("checksum", "")), records, summaries, operations)

func load_state(state: Dictionary) -> Dictionary:
	var checked := State.validate(state); if not bool(checked.get("success", false)): return checked
	if _policy.is_empty() or String(state["policy_checksum"]) != String(_policy["checksum"]): return _failure("CONSTRUCTION_STREAMING_POLICY_PRECONDITION_MISMATCH")
	var records := {}; var summaries := {}; var operations := {}
	for row in state["records"]: records[String(row["construct_id"])] = row.duplicate(true)
	for row in state["summaries"]: summaries[String(row["construct_id"])] = row.duplicate(true)
	for row in state["reconcile_operations"]: operations[int(row["tick"])] = row.duplicate(true)
	_records = records; _summaries = summaries; _operations = operations; _requests.clear(); _tick = int(state["tick"]); _generation = int(state["generation"])
	return _success({"record_count": _records.size(), "generation": _generation})

func get_record(construct_id: String) -> Dictionary: return Dictionary(_records.get(construct_id, {})).duplicate(true)
func get_summary(construct_id: String) -> Dictionary: return Dictionary(_summaries.get(construct_id, {})).duplicate(true)
func get_request(construct_id: String) -> Dictionary: return Dictionary(_requests.get(construct_id, {})).duplicate(true)
func list_records() -> Array: var values: Array = _records.values(); values.sort_custom(func(a,b): return String(a["construct_id"]) < String(b["construct_id"])); return values.duplicate(true)
func get_tick() -> int: return _tick
func get_generation() -> int: return _generation
func get_policy() -> Dictionary: return _policy.duplicate(true)
func get_lod_profile(construct_id: String) -> Dictionary:
	if not _records.has(construct_id): return {}
	var record: Dictionary = _records[construct_id]
	var result := Lod.compile(construct_id, String(record["effective_level"]), int(record["interest_score"]))
	return Dictionary(result.get("profile", {})).duplicate(true)
func _sorted(values: Array) -> Array: var result := values.duplicate(true); result.sort(); return result
func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
	for key in details: result[key] = details[key]
	return result
func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
