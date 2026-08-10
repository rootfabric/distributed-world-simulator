extends SceneTree

const PlannerScript = preload("res://scripts/labs/t1/t1a7/construction_runtime_selective_replication_planner.gd")
const StoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const SubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const SnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/construction_runtime_snapshot.gd")
const ReplicaStoreScript = preload("res://scripts/runtime/host_client/construction_runtime_replica_store.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.t1a7_4_scale_soak_acceptance.v1"
const AUTHORITY_EPOCH: int = 1
const SUBJECTS_PER_CONSTRUCT: int = 10
const REPLAY_HISTORY_BOUND: int = 0
const RESULT_PATH: String = "res://artifacts/test-results/t1a7-4-scale-soak-summary.json"

var assertions: int = 0
var failures: Array[String] = []
var case_reports: Array = []


func _init() -> void:
	_run_case("scale-100x10", 100, 16, 20, 2, 128, 256)
	_run_case("scale-1000x10", 1000, 32, 25, 4, 256, 512)
	_write_summary()
	_finish()


func _run_case(
	case_id: String,
	construct_count: int,
	client_count: int,
	selection_size: int,
	relevant_target_clients: int,
	mutation_iterations: int,
	interest_move_iterations: int
) -> void:
	var started_usec: int = Time.get_ticks_usec()
	var memory_before_bytes: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var fixture_result: Dictionary = _build_fixture(construct_count)
	_assert_ok(fixture_result, "%s fixture build" % case_id)
	if not bool(fixture_result.get("success", false)):
		return
	var fixture: Dictionary = Dictionary(fixture_result.get("details", {}))
	var snapshots_by_construct: Dictionary = Dictionary(fixture.get("snapshots_by_construct", {}))
	var bytes_by_construct: Dictionary = Dictionary(fixture.get("bytes_by_construct", {}))
	var full_world_baseline_bytes: int = int(fixture.get("full_world_baseline_bytes", 0))
	var canonical_subject_count: int = int(fixture.get("canonical_subject_count", 0))
	_assert(canonical_subject_count == construct_count * SUBJECTS_PER_CONSTRUCT, "%s canonical subject count mismatch" % case_id)
	_assert(snapshots_by_construct.size() == construct_count, "%s construct snapshot count mismatch" % case_id)

	var planner = PlannerScript.new()
	_assert_ok(planner.configure(AUTHORITY_EPOCH), "%s planner configure" % case_id)
	var active_routes: Dictionary = {}
	var selections_by_client: Dictionary = {}
	var selection_edge_count: int = 0
	var projected_baseline_bytes: int = 0
	var selection_started_usec: int = Time.get_ticks_usec()
	for client_index in range(client_count):
		var client_id: String = _client_id(client_index)
		var selection: Array = _selection_for_client(
			client_index,
			construct_count,
			selection_size,
			relevant_target_clients,
			0
		)
		selections_by_client[client_id] = selection.duplicate()
		selection_edge_count += selection.size()
		for construct_id_value in selection:
			projected_baseline_bytes += int(bytes_by_construct.get(String(construct_id_value), 0))
		_assert_ok(planner.update_selection(client_id, selection), "%s selection %s" % [case_id, client_id])
		active_routes[client_id] = {
			"client_id": client_id,
			"peer_id": "peer/t1a7-4/%03d" % client_index,
			"session_id": "session/t1a7-4/%03d" % client_index,
		}
	var selection_build_usec: int = Time.get_ticks_usec() - selection_started_usec

	var target_construct_id: String = _construct_id(0)
	_assert(planner.selected_clients(target_construct_id).size() == relevant_target_clients, "%s target reverse interest count mismatch" % case_id)
	var broadcast_baseline_messages: int = construct_count * client_count
	var projected_baseline_messages: int = selection_edge_count
	var broadcast_baseline_bytes: int = full_world_baseline_bytes * client_count
	_assert(projected_baseline_messages < broadcast_baseline_messages, "%s projected message count did not beat broadcast" % case_id)
	_assert(projected_baseline_bytes < broadcast_baseline_bytes, "%s projected baseline bytes did not beat broadcast" % case_id)

	var previous_snapshot: Dictionary = Dictionary(snapshots_by_construct.get(target_construct_id, {})).duplicate(true)
	var mutation_started_usec: int = Time.get_ticks_usec()
	for mutation_index in range(1, mutation_iterations + 1):
		var current_snapshot: Dictionary = _make_snapshot(
			target_construct_id,
			SUBJECTS_PER_CONSTRUCT,
			mutation_index,
			100000 + mutation_index
		)
		var plan: Dictionary = planner.plan_mutation(previous_snapshot, current_snapshot, active_routes, client_count)
		_assert_ok(plan, "%s mutation plan %d" % [case_id, mutation_index])
		if not bool(plan.get("success", false)):
			break
		var details: Dictionary = Dictionary(plan.get("details", {}))
		_assert(Array(details.get("dirty_runtime_ids", [])).size() == 1, "%s mutation %d dirty set was not one subject" % [case_id, mutation_index])
		_assert(int(details.get("target_count", -1)) == relevant_target_clients, "%s mutation %d target count mismatch" % [case_id, mutation_index])
		_assert(int(details.get("avoided_peer_deliveries", -1)) == client_count - relevant_target_clients, "%s mutation %d avoided delivery count mismatch" % [case_id, mutation_index])
		previous_snapshot = current_snapshot
	var mutation_plan_usec: int = Time.get_ticks_usec() - mutation_started_usec

	var memory_before_interest_moves_bytes: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var move_started_usec: int = Time.get_ticks_usec()
	for move_index in range(interest_move_iterations):
		var client_index: int = move_index % client_count
		var client_id: String = _client_id(client_index)
		var next_selection: Array = _selection_for_client(
			client_index,
			construct_count,
			selection_size,
			relevant_target_clients,
			move_index + 1
		)
		selections_by_client[client_id] = next_selection.duplicate()
		_assert_ok(planner.update_selection(client_id, next_selection), "%s interest move %d" % [case_id, move_index])
	var interest_move_usec: int = Time.get_ticks_usec() - move_started_usec
	var memory_after_interest_moves_bytes: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var planner_report: Dictionary = planner.report()
	_assert(int(planner_report.get("client_selection_count", -1)) == client_count, "%s client selection cardinality leaked" % case_id)
	_assert(int(planner_report.get("indexed_construct_count", -1)) <= construct_count, "%s indexed construct cardinality exceeded world" % case_id)
	_assert(planner.selected_clients(target_construct_id).size() == relevant_target_clients, "%s target reverse interest changed after soak" % case_id)
	_assert(int(planner_report.get("plans", 0)) == mutation_iterations, "%s mutation plan count mismatch" % case_id)
	_assert(int(planner_report.get("dirty_runtime_ids_total", 0)) == mutation_iterations, "%s dirty runtime total mismatch" % case_id)
	_assert(int(planner_report.get("targeted_deliveries", 0)) == mutation_iterations * relevant_target_clients, "%s targeted delivery total mismatch" % case_id)
	_assert(int(planner_report.get("avoided_peer_deliveries", 0)) == mutation_iterations * (client_count - relevant_target_clients), "%s avoided delivery total mismatch" % case_id)
	_assert(int(planner_report.get("plan_failures", 0)) == 0, "%s planner failures during soak" % case_id)

	var probe_client_id: String = _client_id(0)
	var probe_selection: Array = Array(selections_by_client.get(probe_client_id, [])).duplicate()
	var apply_result: Dictionary = _apply_projection_baseline(probe_selection, snapshots_by_construct)
	_assert_ok(apply_result, "%s replica projected baseline apply" % case_id)
	var apply_details: Dictionary = Dictionary(apply_result.get("details", {}))
	_assert(int(apply_details.get("replica_count", -1)) == selection_size, "%s projected replica count mismatch" % case_id)
	_assert(int(apply_details.get("accepted_count", -1)) == selection_size, "%s projected replica apply count mismatch" % case_id)

	var reconnect_result: Dictionary = _apply_projection_baseline(probe_selection, snapshots_by_construct)
	_assert_ok(reconnect_result, "%s reconnect full baseline apply" % case_id)
	var reconnect_details: Dictionary = Dictionary(reconnect_result.get("details", {}))
	_assert(int(reconnect_details.get("accepted_count", -1)) == selection_size, "%s reconnect baseline apply mismatch" % case_id)
	_assert(REPLAY_HISTORY_BOUND == 0, "%s replay history bound changed" % case_id)

	var memory_after_bytes: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	var selected_subject_count_per_probe_client: int = selection_size * SUBJECTS_PER_CONSTRUCT
	var report: Dictionary = {
		"case_id": case_id,
		"construct_count": construct_count,
		"subjects_per_construct": SUBJECTS_PER_CONSTRUCT,
		"canonical_subject_count": canonical_subject_count,
		"client_count": client_count,
		"selection_size_constructs": selection_size,
		"selected_subject_count_per_probe_client": selected_subject_count_per_probe_client,
		"selection_edge_count": selection_edge_count,
		"target_relevant_clients": relevant_target_clients,
		"mutation_iterations": mutation_iterations,
		"interest_move_iterations": interest_move_iterations,
		"mutation_scope_subjects_per_snapshot": SUBJECTS_PER_CONSTRUCT,
		"replay_history_bound": REPLAY_HISTORY_BOUND,
		"reconnect_strategy": "FULL_AUTHORITATIVE_BASELINE",
		"broadcast_baseline_messages": broadcast_baseline_messages,
		"projected_baseline_messages": projected_baseline_messages,
		"avoided_baseline_messages": broadcast_baseline_messages - projected_baseline_messages,
		"broadcast_baseline_bytes": broadcast_baseline_bytes,
		"projected_baseline_bytes": projected_baseline_bytes,
		"avoided_baseline_bytes": broadcast_baseline_bytes - projected_baseline_bytes,
		"full_world_baseline_bytes": full_world_baseline_bytes,
		"probe_connect_baseline_messages": selection_size,
		"probe_reconnect_baseline_messages": selection_size,
		"planner": planner_report,
		"timing_usec": {
			"selection_build": selection_build_usec,
			"mutation_plans": mutation_plan_usec,
			"interest_moves": interest_move_usec,
			"probe_replica_apply": int(apply_details.get("apply_usec", 0)),
			"probe_reconnect_apply": int(reconnect_details.get("apply_usec", 0)),
			"total_case": elapsed_usec,
		},
		"memory_static_bytes": {
			"case_start": memory_before_bytes,
			"before_interest_moves": memory_before_interest_moves_bytes,
			"after_interest_moves": memory_after_interest_moves_bytes,
			"case_end": memory_after_bytes,
			"interest_move_delta": memory_after_interest_moves_bytes - memory_before_interest_moves_bytes,
		},
		"structural_bounds": {
			"retained_client_selection_count": int(planner_report.get("client_selection_count", 0)),
			"retained_indexed_construct_count": int(planner_report.get("indexed_construct_count", 0)),
			"max_indexed_construct_count": construct_count,
			"node3d_per_subject_required": false,
		},
	}
	case_reports.append(report)
	print("T1A.7.4 scale case %s: %s" % [case_id, JSON.stringify(report)])


func _build_fixture(construct_count: int) -> Dictionary:
	var snapshots_by_construct: Dictionary = {}
	var bytes_by_construct: Dictionary = {}
	var full_world_baseline_bytes: int = 0
	for construct_index in range(construct_count):
		var construct_id: String = _construct_id(construct_index)
		var snapshot: Dictionary = _make_snapshot(construct_id, SUBJECTS_PER_CONSTRUCT, 0, construct_index)
		var validation: Dictionary = SnapshotScript.validate(snapshot)
		if not bool(validation.get("success", false)):
			return _failure("T1A7_4_SCALE_FIXTURE_SNAPSHOT_INVALID", {
				"construct_id": construct_id,
				"cause": validation,
			})
		var encoded: String = UtilsScript.canonical_json(snapshot)
		if encoded.is_empty():
			return _failure("T1A7_4_SCALE_FIXTURE_ENCODING_FAILED", {"construct_id": construct_id})
		var byte_count: int = encoded.to_utf8_buffer().size()
		snapshots_by_construct[construct_id] = snapshot
		bytes_by_construct[construct_id] = byte_count
		full_world_baseline_bytes += byte_count
	return _success({
		"snapshots_by_construct": snapshots_by_construct,
		"bytes_by_construct": bytes_by_construct,
		"full_world_baseline_bytes": full_world_baseline_bytes,
		"canonical_subject_count": construct_count * SUBJECTS_PER_CONSTRUCT,
	})


func _make_snapshot(
	construct_id: String,
	subjects_per_construct: int,
	mutation_revision: int,
	server_tick: int
) -> Dictionary:
	var subjects: Array = []
	for subject_index in range(subjects_per_construct):
		var subject_revision: int = mutation_revision if subject_index == 0 else 0
		var active: bool = mutation_revision % 2 == 1 if subject_index == 0 else false
		subjects.append(SubjectScript.create(
			_runtime_id(construct_id, subject_index),
			construct_id,
			_item_id(construct_id, subject_index),
			_capability_id(construct_id, subject_index),
			subject_revision,
			{
				"kind": "SCALE_SUBJECT",
				"slot": subject_index,
				"active": active,
			}
		))
	var state: Dictionary = {
		"schema": StoreScript.SCHEMA,
		"generation": subjects_per_construct + mutation_revision,
		"subjects": subjects,
		"checksum": "",
	}
	state["checksum"] = StoreScript.compute_checksum(state)
	return SnapshotScript.create(construct_id, AUTHORITY_EPOCH, server_tick, state)


func _selection_for_client(
	client_index: int,
	construct_count: int,
	selection_size: int,
	relevant_target_clients: int,
	offset: int
) -> Array:
	var selection: Array = []
	var target: String = _construct_id(0)
	var include_target: bool = client_index < relevant_target_clients
	if include_target:
		selection.append(target)
	var cursor: int = (client_index * 37 + offset * 17 + 1) % construct_count
	while selection.size() < selection_size:
		var candidate_index: int = cursor % construct_count
		cursor += 1
		if candidate_index == 0 and not include_target:
			continue
		var candidate: String = _construct_id(candidate_index)
		if not selection.has(candidate):
			selection.append(candidate)
	selection.sort()
	return selection


func _apply_projection_baseline(selection: Array, snapshots_by_construct: Dictionary) -> Dictionary:
	var replicas: Array = []
	var accepted_count: int = 0
	var started_usec: int = Time.get_ticks_usec()
	for construct_id_value in selection:
		var construct_id: String = String(construct_id_value)
		var snapshot: Dictionary = Dictionary(snapshots_by_construct.get(construct_id, {}))
		if snapshot.is_empty():
			return _failure("T1A7_4_SCALE_PROJECTION_SNAPSHOT_MISSING", {"construct_id": construct_id})
		var replica = ReplicaStoreScript.new()
		var accepted: Dictionary = replica.accept_snapshot(snapshot)
		if not bool(accepted.get("success", false)):
			return _failure("T1A7_4_SCALE_REPLICA_APPLY_FAILED", {
				"construct_id": construct_id,
				"cause": accepted,
			})
		if bool(Dictionary(accepted.get("details", {})).get("accepted", false)):
			accepted_count += 1
		replicas.append(replica)
	return _success({
		"replica_count": replicas.size(),
		"accepted_count": accepted_count,
		"apply_usec": Time.get_ticks_usec() - started_usec,
	})


func _construct_id(index: int) -> String:
	return "construct/t1a7-4/scale/c%04d" % index


func _runtime_id(construct_id: String, subject_index: int) -> String:
	return "runtime/t1a7-4/scale/%s/s%02d" % [construct_id.get_file(), subject_index]


func _item_id(construct_id: String, subject_index: int) -> String:
	return "item/t1a7-4/scale/%s/s%02d" % [construct_id.get_file(), subject_index]


func _capability_id(construct_id: String, subject_index: int) -> String:
	return "capability/t1a7-4/scale/%s/s%02d" % [construct_id.get_file(), subject_index]


func _client_id(index: int) -> String:
	return "client/%03d" % index


func _write_summary() -> void:
	var summary: Dictionary = {
		"schema": SCHEMA,
		"passed": failures.is_empty(),
		"assertions": assertions,
		"failure_count": failures.size(),
		"failures": failures.duplicate(),
		"cases": case_reports.duplicate(true),
	}
	var absolute_path: String = ProjectSettings.globalize_path(RESULT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  "))
		file.close()


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	if failures.is_empty():
		print("T1A.7.4 scale/soak lab: PASS (%d assertions, %d cases)" % [assertions, case_reports.size()])
		print("Report: %s" % ProjectSettings.globalize_path(RESULT_PATH))
		quit(0)
		return
	print("T1A.7.4 scale/soak lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
