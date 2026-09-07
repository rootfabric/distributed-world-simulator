extends SceneTree
const Scene = preload("res://scenes/research/fabric_composition_r3_observatory.tscn")
var failures: Array = []
func _initialize() -> void:
	_run.call_deferred()
func _check(value: bool, text: String) -> void:
	if not value: failures.append(text)
func _run() -> void:
	var lab = Scene.instantiate()
	root.add_child(lab)
	lab.set_process(false)
	_check(lab.last_result.success, "observer initializes")
	_check(lab.paused, "initial paused")
	lab.single_step()
	_check(lab.observed_snapshot() == lab.bridge.inspect(), "same snapshot after step")
	_check(lab.observed_snapshot().time_s == 0.005, "single step advances physical time")
	lab.toggle_fidelity()
	_check(lab.observed_snapshot().fidelity == "BAKE", "UI fidelity routes to runtime")
	lab.set_input("source_voltage_v", 10.0)
	_check(lab.observed_snapshot().mechanical_revision == 2, "input goes through ConstructionStore")
	lab.set_load(4.0)
	_check(lab.observed_snapshot().electrical_revision == 2, "load has canonical revision")
	lab.toggle_pause()
	_check(not lab.paused, "play works")
	lab.toggle_pause()
	for i in range(100):
		if not lab.bridge.inspect().pending_proposal.is_empty(): break
		lab.single_step()
	_check(not lab.bridge.inspect().pending_proposal.is_empty(), "solver proposal visible")
	lab.single_step()
	_check(lab.bridge.inspect().mechanical_revision == 3 and lab.bridge.inspect().pending_proposal.is_empty(), "UI commits solver event without hardcoded bond")
	_check(lab.observed_snapshot() == lab.bridge.inspect(), "render input equals physical snapshot after fracture")
	lab.queue_free()
	await process_frame
	print("R3_OBSERVER_FAILURES=", failures)
	print("FABRIC-COMPOSITION-R3-OBSERVER: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
