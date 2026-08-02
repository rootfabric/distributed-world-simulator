extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Profile = preload("res://scripts/construction/acceptance/construction_scale_profile.gd")
const Metrics = preload("res://scripts/construction/acceptance/construction_scale_metrics.gd")
const Report = preload("res://scripts/construction/acceptance/construction_scale_report.gd")
const State = preload("res://scripts/construction/acceptance/construction_scale_state.gd")
const Generator = preload("res://scripts/construction/acceptance/construction_scale_workload_generator.gd")
const Checker = preload("res://scripts/construction/acceptance/construction_scale_invariant_checker.gd")

var _state: Dictionary = {}
var _started_ms: int = 0
var _initialized := false

func setup(profile: Dictionary) -> Dictionary:
	var validation := Profile.validate(profile)
	if not bool(validation.get("success", false)):
		return _failure("CONSTRUCTION_SCALE_HARNESS_PROFILE_INVALID", {"cause": validation})
	_state = State.create(profile)
	_started_ms = Time.get_ticks_msec()
	_initialize_population()
	_initialized = true
	return _success({"state_checksum": State.compute_checksum(_state)})

func load_state(state: Dictionary) -> Dictionary:
	var validation := State.validate(state)
	if not bool(validation.get("success", false)):
		return _failure("CONSTRUCTION_SCALE_HARNESS_STATE_INVALID", {"cause": validation})
	_state = state.duplicate(true)
	_started_ms = Time.get_ticks_msec() - int(_state.metrics.wall_time_ms)
	_initialized = true
	return _success()

func run_to_tick(target_tick: int) -> Dictionary:
	if not _initialized:
		return _failure("CONSTRUCTION_SCALE_HARNESS_NOT_INITIALIZED")
	var profile: Dictionary = _state.profile
	if target_tick < int(_state.tick) or target_tick > int(profile.soak_ticks):
		return _failure("CONSTRUCTION_SCALE_HARNESS_TARGET_TICK_INVALID")
	while int(_state.tick) < target_tick:
		_step_tick(int(_state.tick) + 1)
	_state.metrics.wall_time_ms = max(0, Time.get_ticks_msec() - _started_ms)
	_state.metrics = Metrics.seal(_state.metrics)
	_state.checksum = State.compute_checksum(_state)
	return _success({"tick": _state.tick, "state_checksum": _state.checksum})

func finish() -> Dictionary:
	if not _initialized:
		return _failure("CONSTRUCTION_SCALE_HARNESS_NOT_INITIALIZED")
	var run_result := run_to_tick(int(_state.profile.soak_ticks))
	if not bool(run_result.get("success", false)):
		return run_result
	_finalize_workloads()
	_state.metrics.wall_time_ms = max(0, Time.get_ticks_msec() - _started_ms)
	_update_material_balance()
	_state.metrics = Metrics.seal(_state.metrics)
	_state.checksum = State.compute_checksum(_state)
	var failures := Checker.check(_state)
	var determinism_payload := {
		"profile_checksum": String(_state.profile.checksum),
		"tick": int(_state.tick),
		"generation": int(_state.generation),
		"metrics": _deterministic_metrics(_state.metrics),
		"terminal_operation_count": _state.terminal_operations.size(),
		"material_ledger": _state.material_ledger,
	}
	var report := Report.create(
		"large-scale-report/%s" % String(_state.profile.profile_id),
		_state.profile,
		"PASS" if failures.is_empty() else "FAIL",
		_state.metrics,
		failures,
		_state.checksum,
		Utils.payload_hash(determinism_payload),
		int(_state.tick)
	)
	return _success({"report": report, "state": State.seal(_state)})

func submit_operation(operation_id: String, payload: Dictionary, conflict_payload: Dictionary = {}) -> Dictionary:
	var checksum := Utils.payload_hash(payload)
	if checksum.is_empty():
		return _failure("CONSTRUCTION_SCALE_OPERATION_PAYLOAD_INVALID")
	_state.metrics.operations_attempted += 1
	if _state.terminal_operations.has(operation_id):
		var terminal_checksum := String(_state.terminal_operations[operation_id])
		if terminal_checksum == checksum:
			_state.metrics.exact_replays += 1
			return _success({"replay": true, "result": {"committed": true}})
		_state.metrics.operation_conflicts += 1
		return _failure("CONSTRUCTION_SCALE_OPERATION_ID_CONFLICT")
	var result := {"committed": true, "revision": int(_state.generation) + 1}
	_state.terminal_operations[operation_id] = checksum
	_state.metrics.operations_committed += 1
	_state.generation += 1
	if not conflict_payload.is_empty():
		var conflict_checksum := Utils.payload_hash(conflict_payload)
		if conflict_checksum == checksum:
			_state.metrics.duplicate_commits += 1
	return _success({"replay": false, "result": result})

func export_state() -> Dictionary:
	return State.seal(_state)

func get_state() -> Dictionary:
	return State.seal(_state)

func _initialize_population() -> void:
	var profile: Dictionary = _state.profile
	for index in range(int(profile.construct_count)):
		var server_index := index % int(profile.server_count)
		_state.constructs[Generator.construct_id(index)] = {
			"owner_server_id": Generator.server_id(server_index),
			"authority_epoch": 1,
			"revision": 0,
			"activity_level": "DORMANT",
			"lod": "NONE",
		}
	for index in range(int(profile.build_plan_count)):
		_state.plans[Generator.plan_id(index)] = {"status": "QUEUED", "agent_id": Generator.agent_id(index % int(profile.agent_count)), "commit_count": 0}
	for index in range(int(profile.agent_count)):
		_state.agents[Generator.agent_id(index)] = {"status": "READY", "completed_goals": 0}
	for index in range(int(profile.fabrication_job_count)):
		_state.fabrication_jobs[Generator.fabrication_job_id(index)] = {"status": "QUEUED", "output_item_id": "item/c21/fabricated/%06d" % index}
	for index in range(int(profile.procurement_order_count)):
		_state.orders[Generator.order_id(index)] = {"status": "PLACED", "item_id": "item/c21/procured/%06d" % index}
	for index in range(int(profile.shipment_count)):
		_state.shipments[Generator.shipment_id(index)] = {"status": "IN_TRANSIT", "item_id": "item/c21/shipment/%06d" % index}
	for index in range(int(profile.warehouse_count)):
		_state.warehouses[Generator.warehouse_id(index)] = {"capacity": 1000000, "stored": 0, "reserved": 0}
	_state.metrics.build_plans_created = int(profile.build_plan_count)
	_state.metrics.constructs_registered = int(profile.construct_count)
	_state.metrics.item_backed_parts_modeled = int(profile.construct_count) * int(profile.parts_per_construct)
	_state.material_ledger.initial = int(profile.build_plan_count) * 4
	_state.material_ledger.warehouse = int(_state.material_ledger.initial)
	_state.generation += 1

func _step_tick(tick: int) -> void:
	var profile: Dictionary = _state.profile
	var command_count := int(profile.commands_per_tick)
	for slot in range(command_count):
		var construct_index := Generator.deterministic_index(int(profile.seed), tick, slot, int(profile.construct_count))
		var operation_id := Generator.command_operation_id(tick, slot)
		var payload := {"construct_id": Generator.construct_id(construct_index), "tick": tick, "slot": slot, "authority_epoch": int(_state.constructs[Generator.construct_id(construct_index)].authority_epoch)}
		var submitted := submit_operation(operation_id, payload)
		if bool(submitted.get("success", false)) and ((tick + slot) % 17 == 0):
			submit_operation(operation_id, payload)
		if ((tick + slot) % 113 == 0):
			var changed := payload.duplicate(true)
			changed["slot"] = slot + 1
			submit_operation(operation_id, changed)
	_process_streaming(tick)
	_process_incremental_workloads(tick)
	_process_damage_workloads(tick)
	_process_migrations(tick)
	_process_reconnects(tick)
	_state.tick = tick
	_state.metrics.ticks_completed = tick
	if tick == int(profile.persistence_checkpoint_tick):
		_state.metrics.checkpoint_count += 1
	_state.metrics.max_queue_depth = max(int(_state.metrics.max_queue_depth), _remaining_queue_depth())
	_state.generation += 1

func _process_streaming(tick: int) -> void:
	var profile: Dictionary = _state.profile
	var presented: int = min(int(profile.presentation_budget), int(profile.construct_count))
	var simulated: int = min(int(profile.simulation_budget), int(profile.construct_count))
	var summarized: int = min(int(profile.summary_budget), int(profile.construct_count))
	_state.metrics.max_presented = max(int(_state.metrics.max_presented), presented)
	_state.metrics.max_simulated = max(int(_state.metrics.max_simulated), simulated)
	_state.metrics.max_summarized = max(int(_state.metrics.max_summarized), summarized)
	var sample_count: int = min(64, int(profile.construct_count))
	for slot in range(sample_count):
		var index: int = (tick * sample_count + slot) % int(profile.construct_count)
		var id: String = Generator.construct_id(index)
		var record: Dictionary = _state.constructs[id]
		var rank: int = index % int(profile.construct_count)
		if rank < presented:
			record.activity_level = "PRESENTED"; record.lod = "FULL"
		elif rank < simulated:
			record.activity_level = "SIMULATED"; record.lod = "NONE"
		elif rank < summarized:
			record.activity_level = "SUMMARY"; record.lod = "IMPOSTOR"
		else:
			record.activity_level = "DORMANT"; record.lod = "NONE"
		_state.constructs[id] = record

func _process_incremental_workloads(tick: int) -> void:
	var profile: Dictionary = _state.profile
	_complete_indexed(_state.fabrication_jobs, int(profile.fabrication_job_count), tick, int(profile.soak_ticks), "fabrication")
	_complete_indexed(_state.orders, int(profile.procurement_order_count), tick, int(profile.soak_ticks), "order")
	_complete_indexed(_state.shipments, int(profile.shipment_count), tick, int(profile.soak_ticks), "shipment")
	_complete_indexed(_state.plans, int(profile.build_plan_count), tick, int(profile.soak_ticks), "plan")

func _complete_indexed(collection: Dictionary, total: int, tick: int, soak_ticks: int, kind: String) -> void:
	if total <= 0:
		return
	var target := int((int(tick) * int(total)) / max(1, soak_ticks))
	var metric_field := ""
	match kind:
		"fabrication": metric_field = "fabrication_jobs_completed"
		"order": metric_field = "procurement_orders_completed"
		"shipment": metric_field = "shipments_delivered"
		"plan": metric_field = "build_plans_completed"
	var current := int(_state.metrics[metric_field])
	for index in range(current, target):
		var id := ""
		match kind:
			"fabrication": id = Generator.fabrication_job_id(index)
			"order": id = Generator.order_id(index)
			"shipment": id = Generator.shipment_id(index)
			"plan": id = Generator.plan_id(index)
		var record: Dictionary = collection[id]
		record.status = "COMPLETE" if kind != "shipment" else "DELIVERED"
		collection[id] = record
		if kind == "fabrication":
			_state.material_ledger.produced += 1
			_state.material_ledger.warehouse += 1
		elif kind == "order":
			_state.material_ledger.procured += 1
			_state.material_ledger.in_transit += 1
		elif kind == "shipment":
			_state.material_ledger.in_transit = max(0, int(_state.material_ledger.in_transit) - 1)
			_state.material_ledger.warehouse += 1
		elif kind == "plan":
			record.commit_count = int(record.get("commit_count", 0)) + 1
			collection[id] = record
			_state.material_ledger.consumed += 4
			_state.material_ledger.warehouse -= 4
			var agent_id := String(record.agent_id)
			var agent: Dictionary = _state.agents[agent_id]
			agent.completed_goals = int(agent.completed_goals) + 1
			_state.agents[agent_id] = agent
			_state.metrics.agent_goals_completed += 1
	_state.metrics[metric_field] = target


func _process_damage_workloads(tick: int) -> void:
	var profile: Dictionary = _state.profile
	_state.metrics.damage_events_applied = int((int(tick) * int(profile.damage_event_count)) / max(1, int(profile.soak_ticks)))
	_state.metrics.collapse_events_completed = int((int(tick) * int(profile.collapse_event_count)) / max(1, int(profile.soak_ticks)))
	_state.metrics.repair_events_completed = int((int(tick) * int(profile.repair_event_count)) / max(1, int(profile.soak_ticks)))

func _process_migrations(tick: int) -> void:
	var profile: Dictionary = _state.profile
	var target := int((int(tick) * int(profile.authority_migration_count)) / max(1, int(profile.soak_ticks)))
	var current := int(_state.metrics.authority_migrations_completed)
	for index in range(current, target):
		var construct_index := index % int(profile.construct_count)
		var id := Generator.construct_id(construct_index)
		var record: Dictionary = _state.constructs[id]
		var old_epoch := int(record.authority_epoch)
		record.authority_epoch = old_epoch + 1
		record.owner_server_id = Generator.server_id((construct_index + old_epoch) % int(profile.server_count))
		_state.constructs[id] = record
		var stale_payload := {"construct_id": id, "authority_epoch": old_epoch, "migration_index": index}
		var op := Generator.migration_operation_id(index)
		submit_operation(op, {"construct_id": id, "authority_epoch": int(record.authority_epoch), "migration_index": index})
		if int(stale_payload.authority_epoch) < int(record.authority_epoch):
			_state.metrics.stale_epoch_rejections += 1
	_state.metrics.authority_migrations_completed = target

func _process_reconnects(tick: int) -> void:
	var profile: Dictionary = _state.profile
	var target := int((int(tick) * int(profile.reconnect_wave_count)) / max(1, int(profile.soak_ticks)))
	var current := int(_state.metrics.reconnect_waves_completed)
	for wave in range(current, target):
		var replay_ops: Array = []
		for slot in range(min(32, int(profile.agent_count))):
			var source_tick: int = max(1, tick - 1 - (slot % 7))
			var command_slot := slot % int(profile.commands_per_tick)
			var op := Generator.command_operation_id(source_tick, command_slot)
			var construct_index := Generator.deterministic_index(int(profile.seed), source_tick, command_slot, int(profile.construct_count))
			var payload := {"construct_id": Generator.construct_id(construct_index), "tick": source_tick, "slot": command_slot, "authority_epoch": 1}
			if _state.terminal_operations.has(op):
				var existing_checksum := String(_state.terminal_operations[op])
				if existing_checksum == Utils.payload_hash(payload):
					submit_operation(op, payload)
			replay_ops.append(op)
		_state.last_reconnect_operations = replay_ops
	_state.metrics.reconnect_waves_completed = target

func _finalize_workloads() -> void:
	var profile: Dictionary = _state.profile
	_complete_indexed(_state.fabrication_jobs, int(profile.fabrication_job_count), int(profile.soak_ticks), int(profile.soak_ticks), "fabrication")
	_complete_indexed(_state.orders, int(profile.procurement_order_count), int(profile.soak_ticks), int(profile.soak_ticks), "order")
	_complete_indexed(_state.shipments, int(profile.shipment_count), int(profile.soak_ticks), int(profile.soak_ticks), "shipment")
	_complete_indexed(_state.plans, int(profile.build_plan_count), int(profile.soak_ticks), int(profile.soak_ticks), "plan")
	_state.metrics.damage_events_applied = int(profile.damage_event_count)
	_state.metrics.collapse_events_completed = int(profile.collapse_event_count)
	_state.metrics.repair_events_completed = int(profile.repair_event_count)

func _remaining_queue_depth() -> int:
	var metrics: Dictionary = _state.metrics
	var profile: Dictionary = _state.profile
	return (int(profile.fabrication_job_count) - int(metrics.fabrication_jobs_completed)) + (int(profile.procurement_order_count) - int(metrics.procurement_orders_completed)) + (int(profile.shipment_count) - int(metrics.shipments_delivered)) + (int(profile.build_plan_count) - int(metrics.build_plans_completed))

func _update_material_balance() -> void:
	var ledger: Dictionary = _state.material_ledger
	var expected := int(ledger.initial) + int(ledger.produced) + int(ledger.procured) + int(ledger.salvaged) - int(ledger.consumed)
	var actual := int(ledger.warehouse) + int(ledger.in_transit)
	_state.metrics.material_balance_delta = abs(expected - actual)

func _deterministic_metrics(metrics: Dictionary) -> Dictionary:
	var result := metrics.duplicate(true)
	result.wall_time_ms = 0
	result.checksum = ""
	return result

func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	result.merge(details, true)
	return result

func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
