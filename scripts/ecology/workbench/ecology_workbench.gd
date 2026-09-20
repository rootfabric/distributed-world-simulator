# EcologyWorkbench (P3, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: REUSABLE presentation component (Layer 4). Owns NOTHING biological:
# no world, no player/camera, no Region, no Matter, no persistence, no
# biology truth in Node state (no health/resources/reproduction fields —
# only canonical_entity_id + presentation_descriptor + selection_state).
# The ExperimentController always comes from the outside (LAB host /
# WORLD-COMPAT host is the composition root); every UI action is a
# command routed to the controller, never a direct canonical mutation.
# Reads ONLY completed snapshots after a finished tick.
class_name EcologyWorkbench
extends Node

signal snapshot_updated(snapshot: Dictionary)
signal selection_changed(entity_id: String)

const DEFAULT_TICKS_PER_SECOND := 2.0
const FAST_TICKS_PER_SECOND := 20.0
# Wall-clock budget: no catch-up bursts, bounded ticks per frame.
const MAX_TICKS_PER_FRAME := 64

var controller: Object = null
var founder_registry: Dictionary = {}
var ticks_per_second: float = DEFAULT_TICKS_PER_SECOND
var running := false
# Presentation state only: {canonical_entity_id, presentation_descriptor, selection_state}.
var organism_views: Array[Dictionary] = []
var zone_color_provider: Callable = Callable()

var _elapsed := 0.0
var _markers_root: Node3D = null
var _marker_by_id: Dictionary = {}
var _status_bar: Label = null
var _run_button: Button = null

func setup(deps: Dictionary) -> void:
	# deps: {controller, founder_registry, zone_color_provider?} — everything
	# external arrives explicitly; the workbench creates none of it.
	if deps.has("controller") and deps.controller != null:
		bind_controller(deps.controller)
	if deps.has("founder_registry") and deps.founder_registry is Dictionary:
		founder_registry = deps.founder_registry
	if deps.has("zone_color_provider") and deps.zone_color_provider is Callable:
		zone_color_provider = deps.zone_color_provider

func bind_controller(new_controller: Object) -> void:
	controller = new_controller
	running = false
	_elapsed = 0.0
	_refresh_from_controller(true)

# --- Commands (versioned UI actions -> controller, never direct mutation) ---

func command_run() -> void:
	if controller == null:
		return
	running = true
	_elapsed = 0.0
	_refresh_from_controller(false)

func command_pause() -> void:
	running = false
	if controller != null:
		controller.pause()
	_refresh_from_controller(false)

func command_step() -> bool:
	# Single canonical tick through the controller, then publish.
	running = false
	return _step_once()

func command_reset() -> bool:
	running = false
	_elapsed = 0.0
	if controller == null:
		return false
	var result: Dictionary = controller.reset()
	var ok := bool(result.get("success", false))
	_refresh_from_controller(true)
	return ok

func command_fast() -> void:
	ticks_per_second = FAST_TICKS_PER_SECOND
	command_run()

func set_ticks_per_second(value: float) -> void:
	if value > 0.0:
		ticks_per_second = value

func select_entity(entity_id: String) -> void:
	for view in organism_views:
		view.selection_state = "selected" if view.canonical_entity_id == entity_id else "none"
	selection_changed.emit(entity_id)
	_sync_markers()

# --- Tick-driven update with wall-clock budget ------------------------------

func _process(delta: float) -> void:
	if not running or controller == null:
		return
	_elapsed += delta
	var interval := 1.0 / ticks_per_second
	var executed := 0
	while _elapsed >= interval and executed < MAX_TICKS_PER_FRAME:
		_elapsed -= interval
		executed += 1
		if not _step_once():
			running = false
			return
	_refresh_from_controller(false)

func _step_once() -> bool:
	if controller == null:
		return false
	var result: Dictionary = controller.step()
	if not bool(result.get("success", false)):
		_refresh_from_controller(false)
		return false
	_refresh_from_controller(false)
	return true

# --- Presentation state (descriptor only; no biology truth stored) ----------

func _refresh_from_controller(rebuild_all: bool) -> void:
	if controller == null:
		return
	var snapshot: Dictionary = controller.get_snapshot()
	if not bool(snapshot.get("success", false)):
		_update_status_bar(snapshot)
		return
	organism_views = _build_views()
	_sync_markers()
	snapshot_updated.emit(snapshot)
	_update_status_bar(snapshot)

func _build_views() -> Array[Dictionary]:
	var views: Array[Dictionary] = []
	if controller == null:
		return views
	# Position/alive/development summary are read from the controller's
	# completed state purely to BUILD the descriptor, then discarded — the
	# Node keeps only id + descriptor + selection.
	var state: Dictionary = controller.debug_state()
	var previous := {}
	for view in organism_views:
		previous[view.canonical_entity_id] = view.selection_state
	for entry in state.population:
		var individual_id := String(entry.state.individual_id)
		var position: Array = entry.state.position_mm
		var summary := {
			"module_count": int(entry.state.development.modules.size()),
			"age_ticks": int(entry.state.age_ticks),
		}
		views.append({
			"canonical_entity_id": individual_id,
			"presentation_descriptor": {
				"position_mm": [int(position[0]), int(position[1]), int(position[2])],
				"alive": bool(entry.state.alive),
				"development_summary": summary,
			},
			"selection_state": String(previous.get(individual_id, "none")),
		})
	return views

func _update_status_bar(snapshot: Dictionary) -> void:
	if _status_bar == null:
		return
	if not bool(snapshot.get("success", false)):
		_status_bar.text = "CONTROLLER ERROR: " + str(snapshot.get("error", "unknown"))
		return
	var hash_short := String(snapshot.get("canonical_state_hash", "")).substr(0, 8)
	_status_bar.text = "tick %d | organisms %d | state %s | hash %s" % [
		int(snapshot.get("tick", 0)), organism_views.size(),
		String(snapshot.get("status", "?")), hash_short,
	]

# --- P3-minimal organism markers (morphology is P6, NOT here) ---------------

func _sync_markers() -> void:
	if _markers_root == null:
		return
	var seen := {}
	for view in organism_views:
		var entity_id: String = view.canonical_entity_id
		seen[entity_id] = true
		var descriptor: Dictionary = view.presentation_descriptor
		var marker: MeshInstance3D = _marker_by_id.get(entity_id)
		if marker == null:
			marker = MeshInstance3D.new()
			marker.name = "OrganismMarker"
			var mesh := SphereMesh.new()
			mesh.radius = 0.25
			mesh.height = 0.5
			marker.mesh = mesh
			var material := StandardMaterial3D.new()
			marker.material_override = material
			_markers_root.add_child(marker)
			_marker_by_id[entity_id] = marker
		# Scene scale: millimetres -> metres (mm / 100).
		var position_mm: Array = descriptor.position_mm
		marker.position = Vector3(
			float(position_mm[0]) / 100.0,
			0.5 + float(position_mm[1]) / 100.0,
			float(position_mm[2]) / 100.0
		)
		var material2: StandardMaterial3D = marker.material_override
		material2.albedo_color = _marker_color(descriptor, view.selection_state == "selected")
	for entity_id in _marker_by_id.keys():
		if not seen.has(entity_id):
			var stale: Node = _marker_by_id[entity_id]
			_marker_by_id.erase(entity_id)
			stale.queue_free()

func _marker_color(descriptor: Dictionary, selected: bool) -> Color:
	var color := Color(0.8, 0.8, 0.8)
	if zone_color_provider.is_valid():
		var provided: Variant = zone_color_provider.call(descriptor.position_mm)
		if provided is Color:
			color = provided
	if not descriptor.alive:
		color = Color(0.35, 0.35, 0.35)
	if selected:
		color = Color(1.0, 0.9, 0.2)
	return color

# --- UI wiring (buttons live in the workbench scene) -------------------------

func _ready() -> void:
	_markers_root = get_node_or_null("OrganismMarkers")
	_status_bar = get_node_or_null("WorkbenchUI/StatusBar")
	_run_button = get_node_or_null("WorkbenchUI/ExperimentControls/Run") as Button
	_connect_button("WorkbenchUI/ExperimentControls/Run", command_run)
	_connect_button("WorkbenchUI/ExperimentControls/Pause", command_pause)
	_connect_button("WorkbenchUI/ExperimentControls/Step", command_step)
	_connect_button("WorkbenchUI/ExperimentControls/Reset", command_reset)
	_connect_button("WorkbenchUI/ExperimentControls/Fast", command_fast)

func _connect_button(path: String, action: Callable) -> void:
	var button := get_node_or_null(path) as Button
	if button != null:
		button.pressed.connect(action)
