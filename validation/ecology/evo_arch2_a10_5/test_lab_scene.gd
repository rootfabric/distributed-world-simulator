extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P3 Minimal LAB scene tests.
# Runner: Godot headless --script; prints checks/failed counts and PASS/FAIL.
# Instantiates the LAB host scene (composition root) headless and checks:
#   1. lab created controller + workbench (bound);
#   2. workbench owns no camera (camera belongs to the lab host);
#   3. after 8 simulated ticks (UI command path) organism views match the
#      snapshot population (count / ids / alive);
#   4. UI button commands (STEP / RESET) change controller state;
#   5. nodes carry no biology truth fields (health/energy/reserves...);
#   6. state hash after RESET + 8 ticks == hash of the first 8 ticks
#      (determinism through the UI path).

const LabScene = preload("res://scenes/labs/ecology/eco_arch2_polygon_lab.tscn")
const WorkbenchScript = preload("res://scripts/ecology/workbench/ecology_workbench.gd")

const BIOLOGY_TRUTH_FIELDS := [
	"health", "energy", "reserves", "resource_ledger", "metabolic_reserves",
	"starvation_ticks", "reproduction_count", "propagules", "population_state",
]

var checks := 0
var failures: Array[String] = []
var lab: Node = null
var workbench: Node = null  # EcologyWorkbench instance (dynamic calls)
var controller: Object = null

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P3_FAIL " + message)

func _button(path: String) -> Button:
	return workbench.get_node_or_null(path) as Button

func _run() -> void:
	# --- instantiate the LAB scene (headless; no window needed) ---------------
	lab = LabScene.instantiate()
	root.add_child(lab)  # triggers _ready() -> full composition
	controller = lab.get("controller")
	workbench = lab.get_node_or_null("EcologyWorkbench")
	_check(controller != null, "lab host created the ExperimentController")
	_check(workbench != null, "lab host instantiated the EcologyWorkbench")
	if controller == null or workbench == null:
		_finish()
		return

	# --- ownership: camera belongs to the LAB host, not the workbench ---------
	var lab_cameras := lab.find_children("*", "Camera3D", true, false)
	_check(not lab_cameras.is_empty(), "lab host owns a camera")
	var workbench_cameras: Array = workbench.find_children("*", "Camera3D", true, false)
	_check(workbench_cameras.is_empty(), "workbench owns no camera")
	for camera in lab_cameras:
		_check(camera.get_parent() != workbench, "lab camera is not parented under the workbench")
	_check(workbench.get("controller") == controller, "workbench is bound to the lab controller")
	_check(bool(workbench.get("ticks_per_second") == 2.0), "workbench default cadence is 2 ticks/sec")

	# --- UI button commands change controller state ---------------------------
	var step_button := _button("WorkbenchUI/ExperimentControls/Step")
	var reset_button := _button("WorkbenchUI/ExperimentControls/Reset")
	_check(step_button != null and reset_button != null, "UI step/reset buttons exist")
	var tick_before := int(controller.get_snapshot().tick)
	if step_button != null:
		step_button.pressed.emit()
	var tick_after_step := int(controller.get_snapshot().tick)
	_check(tick_after_step == tick_before + 1, "UI STEP advances the controller by one tick (%d -> %d)" % [tick_before, tick_after_step])
	if reset_button != null:
		reset_button.pressed.emit()
	_check(int(controller.get_snapshot().tick) == 0, "UI RESET returns the controller to tick 0")

	# --- 8 simulated ticks via the workbench UI path ---------------------------
	var collected: Array = []
	var watcher := func(snapshot: Dictionary) -> void:
		collected.append(snapshot)
	workbench.snapshot_updated.connect(watcher)
	for i in 8:
		var ok: bool = workbench.command_step()
		_check(ok, "UI-path tick %d succeeds" % (i + 1))
		if not ok:
			break
	_check(collected.size() == 8, "each completed tick publishes one snapshot (got %d)" % collected.size())

	# --- organism views match snapshot population -----------------------------
	var snapshot: Dictionary = controller.get_snapshot()
	var population: Array = snapshot.population
	var views: Array = workbench.organism_views
	_check(views.size() == population.size(), "view count == snapshot population count (%d vs %d)" % [views.size(), population.size()])
	var snapshot_ids := {}
	for entry in population:
		snapshot_ids[entry.individual_id] = true
	var view_ids := {}
	for view in views:
		view_ids[view.canonical_entity_id] = true
	_check(snapshot_ids == view_ids, "view ids == snapshot population ids")
	# Alive flags in the views must equal the controller's life-state truth.
	var alive_truth := {}
	for pop_entry in controller.debug_state().population:
		alive_truth[pop_entry.state.individual_id] = bool(pop_entry.state.alive)
	var alive_match := true
	for view in views:
		if bool(view.presentation_descriptor.alive) != bool(alive_truth.get(view.canonical_entity_id, false)):
			alive_match = false
	_check(alive_match, "view alive flags match controller life state")
	# Descriptor carries position + development summary (no biology truth).
	var first_view: Dictionary = views[0]
	_check(first_view.presentation_descriptor.has("position_mm") and first_view.presentation_descriptor.has("development_summary"), "descriptor has position + development summary")
	_check(first_view.has("selection_state"), "view carries selection state")
	# Selection signal round-trip (re-look-up the view: views are rebuilt
	# after each tick).
	var first_id := String(first_view.canonical_entity_id)
	var selection_events: Array = []
	var selection_watcher := func(entity_id: String) -> void: selection_events.append(entity_id)
	workbench.selection_changed.connect(selection_watcher)
	workbench.select_entity(first_id)
	_check(selection_events.size() == 1 and selection_events[0] == first_id, "selection_changed fires with the entity id")
	var selected_view: Dictionary = {}
	for view in workbench.organism_views:
		if view.canonical_entity_id == first_id:
			selected_view = view
	_check(selected_view.selection_state == "selected", "selected view marked as selected")

	# --- nodes carry no biology truth fields ------------------------------------
	_check(_no_biology_truth(workbench), "workbench node exposes no biology truth fields")
	for node in workbench.find_children("*", "", true, false):
		_check(_no_biology_truth(node), "workbench child %s exposes no biology truth fields" % node.name)
	_check(_no_biology_truth(lab), "lab host node exposes no biology truth fields")

	# --- determinism: RESET + 8 ticks (UI path) == first 8 ticks ---------------
	var hash_first_8 := String(snapshot.canonical_state_hash)
	var reset_ok: bool = workbench.command_reset()
	_check(reset_ok, "command_reset succeeds before determinism check")
	var determinism_ok := true
	for i in 8:
		if not workbench.command_step():
			determinism_ok = false
			break
	_check(determinism_ok, "8 ticks after reset succeed")
	_check(String(controller.get_snapshot().canonical_state_hash) == hash_first_8, "RESET + 8 UI ticks reproduce the first-8-ticks hash (determinism)")

	_finish()

func _no_biology_truth(node: Node) -> bool:
	for property in node.get_property_list():
		if property.name in BIOLOGY_TRUTH_FIELDS:
			return false
	return true

func _finish() -> void:
	print("EVO_ARCH2_A10_5_LAB_P3 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_LAB_P3 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P3_FAILURE " + failure)
		quit(1)
