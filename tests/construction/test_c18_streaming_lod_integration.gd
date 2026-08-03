extends SceneTree

const F = preload("res://tests/construction/fixtures/c18_streaming_fixture.gd")
const Level = preload("res://scripts/construction/streaming/construction_activity_level.gd")
const Request = preload("res://scripts/construction/streaming/construction_streaming_request.gd")
const Controller = preload("res://scripts/construction/streaming/construction_streaming_controller.gd")
const Runtime = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_synchronizer.gd")
const Persistence = preload("res://scripts/construction/streaming/construction_streaming_persistence.gd")
const State = preload("res://scripts/construction/streaming/construction_streaming_state.gd")

var assertions := 0
var failures: Array[String] = []
var runtime: Node
var controller: Node
var simulation
var requests: Dictionary = {}

func _init() -> void:
	runtime = Runtime.new(); get_root().add_child(runtime)
	controller = Controller.new(); get_root().add_child(controller)
	simulation = F.FakeSimulationDriver.new()
	_ok(controller.setup(F.policy(), runtime, simulation), "controller setup")
	_register_initial()
	_test_budgeted_levels_and_replay()
	_test_demotion_and_dormancy()
	_test_lazy_rebuild_and_catch_up()
	_test_read_only_presentation()
	_test_persistence_and_authority_change()
	_test_pinned_budget_atomicity()
	_finish()

func _register_initial() -> void:
	requests["a"] = F.request("a", 1, F.SERVER_A, F.SERVER_A, Request.OWNER, Level.DORMANT, {}, [0.0, 0.0, 0.0])
	requests["b"] = F.request("b", 1, F.SERVER_A, F.SERVER_A, Request.OWNER, Level.DORMANT, {}, [10.0, 0.0, 0.0])
	requests["c"] = F.request("c", 1, F.SERVER_A, F.SERVER_A, Request.OWNER, Level.DORMANT, {}, [20.0, 0.0, 0.0])
	requests["d"] = F.request("d", 1, F.SERVER_A, F.SERVER_A, Request.OWNER, Level.DORMANT, {}, [30.0, 0.0, 0.0])
	for key in ["a", "b", "c", "d"]: _ok(controller.register_construct(requests[key], 0), "register %s" % key)
	_assert(controller.get_generation() == 4, "register generation")

func _test_budgeted_levels_and_replay() -> void:
	var samples := [
		F.sample_for(requests["a"], 0, 2.0, true, false, true, 100),
		F.sample_for(requests["b"], 0, 2.0, true, true, false, 50),
		F.sample_for(requests["c"], 0, 30.0, true),
		F.sample_for(requests["d"], 0, 80.0, false),
	]
	var result: Dictionary = controller.reconcile(samples, 0); _ok(result, "initial reconcile")
	_assert(controller.get_record(String(requests["a"]["construct_id"]))["effective_level"] == Level.PRESENTED, "A presented")
	_assert(controller.get_record(String(requests["b"]["construct_id"]))["effective_level"] == Level.SIMULATED, "B simulated")
	_assert(controller.get_record(String(requests["c"]["construct_id"]))["effective_level"] == Level.SUMMARY, "C summary")
	_assert(controller.get_record(String(requests["d"]["construct_id"]))["effective_level"] == Level.DORMANT, "D dormant by summary budget")
	_assert(runtime.get_construct_count() == 1, "one presented node")
	var a_node = runtime.get_construct_node(String(requests["a"]["construct_id"]))
	_assert(a_node != null, "A runtime node")
	_assert(String(a_node.get_meta("construction_lod_tier", "")) == "FULL", "A full LOD")
	_assert(String(controller.get_record(String(requests["a"]["construct_id"]))["lod_tier"]) == "FULL", "A LOD persisted in record")
	_assert(simulation.calls.size() == 2, "owner simulation activation count")
	_assert(not controller.get_summary(String(requests["a"]["construct_id"])).is_empty(), "A summary exists")
	_assert(not controller.get_summary(String(requests["b"]["construct_id"])).is_empty(), "B summary exists")
	_assert(not controller.get_summary(String(requests["c"]["construct_id"])).is_empty(), "C summary exists")
	_assert(controller.get_summary(String(requests["d"]["construct_id"])).is_empty(), "D summary evicted")
	_assert(controller.get_record(String(requests["d"]["construct_id"]))["pending_job_ids"] == requests["d"]["pending_job_ids"], "dormant jobs preserved")
	_assert(int(result["report"]["used"]["presentation_bytes"]) == 100, "presentation budget used")
	_assert(int(result["report"]["used"]["simulation_units"]) == 6, "simulation budget used")
	_assert(int(result["report"]["used"]["summary_bytes"]) == 360, "summary budget used")
	var calls_before: int = simulation.calls.size(); var presentation_before: int = runtime.get_presentation_generation(); var replay: Dictionary = controller.reconcile(samples, 0); _ok(replay, "reconcile replay")
	_assert(bool(replay["replay"]), "reconcile replay marker")
	_assert(simulation.calls.size() == calls_before and runtime.get_presentation_generation() == presentation_before, "replay no derived work")
	var conflict_samples := samples.duplicate(true); conflict_samples[0] = F.sample_for(requests["a"], 0, 3.0, true, false, true, 100)
	_err(controller.reconcile(conflict_samples, 0), "CONSTRUCTION_STREAMING_RECONCILE_TICK_CONFLICT", "same tick conflict")

func _test_demotion_and_dormancy() -> void:
	var far1: Array = []
	for key in ["a", "b", "c", "d"]: far1.append(F.sample_for(requests[key], 1, 200.0))
	_ok(controller.reconcile(far1, 1), "far tick 1")
	_assert(runtime.get_construct_count() == 0, "presentation evicted")
	_assert(controller.get_record(String(requests["a"]["construct_id"]))["effective_level"] == Level.SUMMARY, "A grace summary")
	_assert(int(controller.get_record(String(requests["a"]["construct_id"]))["outside_summary_since_tick"]) == 1, "outside tick recorded")
	var far4: Array = []
	for key in ["a", "b", "c", "d"]: far4.append(F.sample_for(requests[key], 4, 200.0))
	_ok(controller.reconcile(far4, 4), "far tick 4")
	for key in ["a", "b", "c", "d"]:
		_assert(controller.get_record(String(requests[key]["construct_id"]))["effective_level"] == Level.DORMANT, "%s dormant" % key)
		_assert(controller.get_summary(String(requests[key]["construct_id"])).is_empty(), "%s summary evicted" % key)
	_assert(runtime.get_construct_count() == 0, "dormant no runtime")

func _test_lazy_rebuild_and_catch_up() -> void:
	var samples := [F.sample_for(requests["c"], 20, 1.0, true, false, true, 200)]
	var result: Dictionary = controller.reconcile(samples, 20); _ok(result, "lazy present C")
	var c_id := String(requests["c"]["construct_id"])
	_assert(controller.get_record(c_id)["effective_level"] == Level.PRESENTED, "C promoted")
	_assert(runtime.get_construct_node(c_id) != null, "C runtime rebuilt")
	_assert(not controller.get_summary(c_id).is_empty(), "C summary rebuilt")
	var last_call: Dictionary = simulation.calls[-1]
	_assert(String(last_call["construct_id"]) == c_id, "C catch up call")
	_assert(last_call["plan"]["steps"].size() == 3, "bounded catch up steps")
	_assert(bool(last_call["plan"]["truncated"]), "catch up truncated")
	_assert(int(last_call["plan"]["steps"][-1]["tick"]) == 6, "catch up frontier")
	_assert(last_call["pending_job_ids"] == requests["c"]["pending_job_ids"] and last_call["pending_operation_ids"] == requests["c"]["pending_operation_ids"], "catch up pending state preserved")
	_assert(String(controller.get_record(c_id)["simulation_checksum"]).length() == 64, "simulation checksum")

func _test_read_only_presentation() -> void:
	requests["e"] = F.request("e", 1, F.SERVER_B, F.SERVER_A, Request.READ_ONLY, Level.DORMANT, {}, [40.0, 0.0, 0.0])
	_ok(controller.register_construct(requests["e"], 20), "register read only")
	var call_count: int = simulation.calls.size()
	var samples := [F.sample_for(requests["c"], 21, 200.0), F.sample_for(requests["e"], 21, 1.0, true, false, true, 1000)]
	_ok(controller.reconcile(samples, 21), "read only present")
	var e_id := String(requests["e"]["construct_id"])
	_assert(controller.get_record(e_id)["effective_level"] == Level.PRESENTED, "read only presented")
	var e_node = runtime.get_construct_node(e_id)
	_assert(e_node != null, "read only runtime")
	_assert(String(e_node.get_meta("construction_lod_tier", "")) == "FULL", "read only LOD applied")
	_assert(simulation.calls.size() == call_count, "read only no authoritative simulation")
	_assert(String(controller.get_record(e_id)["authority_mode"]) == Request.READ_ONLY, "read only record")

func _test_persistence_and_authority_change() -> void:
	var storage := F.MemoryStore.new(); _ok(Persistence.save(storage, controller), "save streaming")
	var exported: Dictionary = controller.export_state(); _ok(State.validate(exported), "exported state")
	var restored_runtime := Runtime.new(); get_root().add_child(restored_runtime)
	var restored_driver := F.FakeSimulationDriver.new()
	var restored := Controller.new(); get_root().add_child(restored); _ok(restored.setup(F.policy(), restored_runtime, restored_driver), "restored setup")
	_ok(Persistence.load(storage, restored), "load streaming")
	_assert(restored.get_tick() == 21 and restored.get_generation() == controller.get_generation(), "restored cursor")
	for key in ["a", "b", "c", "d", "e"]: _ok(restored.register_construct(requests[key], 21), "reattach %s" % key)
	_assert(restored_runtime.get_construct_count() == 0, "runtime not persisted")
	var rebuild := restored.reconcile([F.sample_for(requests["a"], 22, 1.0, true, false, true, 500)], 22); _ok(rebuild, "restore lazy rebuild")
	var a_id := String(requests["a"]["construct_id"])
	_assert(restored_runtime.get_construct_node(a_id) != null, "restored runtime rebuilt")
	_assert(restored.get_record(a_id)["pending_operation_ids"] == requests["a"]["pending_operation_ids"], "restored pending operations")
	var migrated := F.request("a", 2, F.SERVER_B, F.SERVER_A, Request.READ_ONLY, Level.DORMANT, {}, [0.0, 0.0, 0.0])
	_ok(restored.register_construct(migrated, 22), "authority migration source")
	_err(restored.register_construct(requests["a"], 22), "STALE_CONSTRUCTION_STREAMING_AUTHORITY_EPOCH", "stale authority source")
	var calls_before: int = restored_driver.calls.size(); _ok(restored.reconcile([F.sample_for(migrated, 23, 1.0, true, false, true, 500)], 23), "migrated read only present")
	_assert(restored.get_record(a_id)["authority_epoch"] == 2 and restored.get_record(a_id)["authority_mode"] == Request.READ_ONLY, "authority record updated")
	_assert(restored_driver.calls.size() == calls_before, "new read only owner not simulated locally")
	controller = restored; runtime = restored_runtime; simulation = restored_driver; requests["a"] = migrated

func _test_pinned_budget_atomicity() -> void:
	var pinned := F.request("pinned", 1, F.SERVER_A, F.SERVER_A, Request.OWNER, Level.PRESENTED, {"presentation_bytes": 200}, [60.0, 0.0, 0.0])
	_ok(controller.register_construct(pinned, 23), "register pinned")
	var tick_before: int = controller.get_tick(); var runtime_count: int = runtime.get_construct_count(); var generation_before: int = controller.get_generation()
	var result: Dictionary = controller.reconcile([F.sample_for(pinned, 24, 1.0, true, false, true, 10000)], 24)
	_err(result, "CONSTRUCTION_STREAMING_PINNED_PRESENTATION_BUDGET_EXCEEDED", "pinned budget")
	_assert(controller.get_tick() == tick_before, "pinned failure tick atomic")
	_assert(runtime.get_construct_count() == runtime_count, "pinned failure presentation atomic")
	_assert(controller.get_generation() == generation_before, "pinned failure generation atomic")
	_ok(controller.unregister_construct(String(pinned["construct_id"])), "remove pinned")

func _ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _err(result: Dictionary, code: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C18 streaming/LOD integration: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C18 streaming/LOD integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
