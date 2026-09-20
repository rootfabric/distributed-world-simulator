# EcologyWorkbench (P3+P4+P5, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: REUSABLE presentation component (Layer 4). Owns NOTHING biological:
# no world, no player/camera, no Region, no Matter, no persistence, no
# biology truth in Node state (no health/resources/reproduction fields —
# only canonical_entity_id + presentation_descriptor + selection_state).
# The ExperimentController always comes from the outside (LAB host /
# WORLD-COMPAT host is the composition root); every UI action is a
# command routed to the controller, never a direct canonical mutation.
# Reads ONLY completed snapshots after a finished tick. Since P4 the
# organism views are built from the controller snapshot's read-only
# presentation views (debug_state is no longer a UI dependency).
# Morphology (P6): when the Morphology toggle is ON, organism bodies are
# projected read-only into MorphologyDescriptors (canonical development
# modules via controller debug_state) and realized by the generic universal
# realizer into primitive meshes. P3 sphere markers stay as the
# LOD-minimal fallback (visible when Morphology is OFF). Presentation never
# touches canonical state (A10.5 brief §14/§27 visual invariant).
# Time controls (P5): simulation time (controller ticks) is strictly
# separated from wall-clock (UI cadence); FAST only changes ticks per wall
# interval, never dt; MAX_TICKS_PER_FRAME bounds catch-up.
class_name EcologyWorkbench
extends Node

signal snapshot_updated(snapshot: Dictionary)
signal selection_changed(entity_id: String)

const DEFAULT_TICKS_PER_SECOND := 2.0
const FAST_TICKS_PER_SECOND := 20.0
# Wall-clock budget: no catch-up bursts, bounded ticks per frame.
const MAX_TICKS_PER_FRAME := 64

const PlacementPlan = preload("res://scripts/ecology/workbench/placement_plan_v1.gd")
const EnvironmentPatch = preload("res://scripts/ecology/workbench/environment_patch_v1.gd")
const MorphologyDescriptor = preload("res://scripts/ecology/workbench/morphology_descriptor_v1.gd")
const GenericRealizer = preload("res://scripts/ecology/workbench/generic_morphology_realizer_v1.gd")
const OrganismInspector = preload("res://scripts/ecology/workbench/organism_inspector_v1.gd")
const GenomeEditor = preload("res://scripts/ecology/workbench/genome_editor_v1.gd")
const ExperimentBranch = preload("res://scripts/ecology/workbench/experiment_branch_v1.gd")
const MutationProxy = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")

# Scene scale: millimetres -> metres (same convention as the P3 markers).
const MM_PER_SCENE_UNIT := 100.0
const MORPHOLOGY_BASE_OFFSET_Y := 0.5

var controller: Object = null
var founder_registry: Dictionary = {}
var ticks_per_second: float = DEFAULT_TICKS_PER_SECOND
var running := false
# Pending run target (P5): {"kind": "tick"|"generation"|"condition", ...} or {}.
var pending_target: Dictionary = {}
# Presentation state only: {canonical_entity_id, presentation_descriptor, selection_state}.
var organism_views: Array[Dictionary] = []
var zone_color_provider: Callable = Callable()

var _elapsed := 0.0
var _wall_elapsed := 0.0
var _markers_root: Node3D = null
var _marker_by_id: Dictionary = {}
var _status_bar: Label = null
var _run_button: Button = null
# Morphology presentation state (P6): presentation-only, no biology truth.
var morphology_enabled := true
var morphology_lod := "HIGH"
var _morphology_root: Node3D = null
var _morphology_by_id: Dictionary = {}
# Inspector / editor / branch state (P7+P8): presentation + orchestration
# commands only; no biology truth ever lives in the workbench.
var _selected_entity := ""
var _last_checkpoint: Dictionary = {}
var branch_manager: Object = null

func setup(deps: Dictionary) -> void:
	# deps: {controller, founder_registry, zone_color_provider?} — everything
	# external arrives explicitly; the workbench creates none of it.
	if deps.has("controller") and deps.controller != null:
		bind_controller(deps.controller)
	if deps.has("founder_registry") and deps.founder_registry is Dictionary:
		founder_registry = deps.founder_registry
		if branch_manager != null:
			branch_manager.set_founder_registry(founder_registry)
	if deps.has("zone_color_provider") and deps.zone_color_provider is Callable:
		zone_color_provider = deps.zone_color_provider

func bind_controller(new_controller: Object) -> void:
	controller = new_controller
	running = false
	pending_target = {}
	_elapsed = 0.0
	_wall_elapsed = 0.0
	_last_checkpoint = {}
	branch_manager = ExperimentBranch.new()
	var branch_setup: Dictionary = branch_manager.setup(new_controller, founder_registry)
	if not bool(branch_setup.get("success", false)):
		push_error("ECO_WORKBENCH branch setup failed: " + str(branch_setup))
	_refresh_from_controller(true)

# --- Commands (versioned UI actions -> controller, never direct mutation) ---

func command_run() -> void:
	if controller == null:
		return
	pending_target = {}
	running = true
	_elapsed = 0.0
	_wall_elapsed = 0.0
	_refresh_from_controller(false)

func command_pause() -> void:
	running = false
	pending_target = {}
	if controller != null:
		controller.pause()
	_refresh_from_controller(false)

func command_step() -> bool:
	# Single canonical tick through the controller, then publish.
	running = false
	pending_target = {}
	return _step_once()

func command_step_n(n_ticks: int) -> bool:
	# Exactly n canonical ticks in one controller batch (P5 STEP N).
	running = false
	pending_target = {}
	if controller == null or n_ticks < 1:
		return false
	var result: Dictionary = controller.run(n_ticks)
	var ok := bool(result.get("success", false))
	_refresh_from_controller(false)
	return ok

func command_reset() -> bool:
	running = false
	pending_target = {}
	_elapsed = 0.0
	_wall_elapsed = 0.0
	if controller == null:
		return false
	var result: Dictionary = controller.reset()
	var ok := bool(result.get("success", false))
	_refresh_from_controller(true)
	return ok

func command_fast() -> void:
	# FAST = higher tick cadence only; simulation dt never changes.
	ticks_per_second = FAST_TICKS_PER_SECOND
	command_run()

func set_ticks_per_second(value: float) -> void:
	if value > 0.0:
		ticks_per_second = value

func command_run_to_tick(target_tick: int) -> bool:
	running = true
	pending_target = {"kind": "tick", "value": int(target_tick)}
	_elapsed = 0.0
	_wall_elapsed = 0.0
	_refresh_from_controller(false)
	return controller != null

func command_run_to_generation(target_generation: int) -> bool:
	running = true
	pending_target = {"kind": "generation", "value": int(target_generation)}
	_elapsed = 0.0
	_wall_elapsed = 0.0
	_refresh_from_controller(false)
	return controller != null

func command_run_to_condition(value_kind: String, value: int) -> bool:
	running = true
	pending_target = {"kind": "condition", "value_kind": value_kind, "value": int(value)}
	_elapsed = 0.0
	_wall_elapsed = 0.0
	_refresh_from_controller(false)
	return controller != null

# --- Placement / environment commands (P4): new immutable manifest ------

## Generate placement entries from a preset and re-initialize the controller
## with the new immutable manifest (commands go through the controller).
func command_generate_placement(preset: String) -> bool:
	if controller == null:
		return false
	running = false
	pending_target = {}
	var manifest: Dictionary = controller.get_manifest()
	var generated: Dictionary = PlacementPlan.generate(manifest, preset)
	if not bool(generated.get("success", false)):
		push_error("ECO_WORKBENCH placement preset failed: " + str(generated.get("error", "?")))
		return false
	var next := manifest.duplicate(true)
	next.placement.entries = generated.entries
	var result: Dictionary = controller.initialize(next, founder_registry)
	var ok := bool(result.get("success", false))
	_refresh_from_controller(true)
	return ok

## Apply an environment patch (existing zone field, canonical bounds) as a
## NEW immutable manifest; the controller is re-initialized from it.
func command_apply_environment_patch(zone_id: String, field: String, value: int) -> bool:
	if controller == null:
		return false
	running = false
	pending_target = {}
	var manifest: Dictionary = controller.get_manifest()
	var applied: Dictionary = EnvironmentPatch.apply_patch(manifest, EnvironmentPatch.patch(zone_id, field, value))
	if not bool(applied.get("success", false)):
		push_error("ECO_WORKBENCH environment patch rejected: " + str(applied.get("error", "?")))
		return false
	var result: Dictionary = controller.initialize(applied.manifest, founder_registry)
	var ok := bool(result.get("success", false))
	_refresh_from_controller(true)
	return ok

func select_entity(entity_id: String) -> void:
	for view in organism_views:
		view.selection_state = "selected" if view.canonical_entity_id == entity_id else "none"
	_selected_entity = entity_id
	selection_changed.emit(entity_id)
	_sync_markers()

# --- Inspector / genome editor (P7) -------------------------------------------

## Read-only inspection chain for the currently selected organism, shown in
## the Inspector panel. Opens on every selection_changed.
func _on_selection_changed_inspector(entity_id: String) -> void:
	_render_inspector()

func _render_inspector() -> void:
	var selected := get_node_or_null("WorkbenchUI/InspectorControls/SelectedLabel") as Label
	var content := get_node_or_null("WorkbenchUI/InspectorPanel/InspectorContent") as Label
	if selected == null or content == null:
		return
	if controller == null or _selected_entity.is_empty():
		selected.text = "INSPECTOR: select an organism"
		content.text = ""
		return
	selected.text = "INSPECTOR: " + _selected_entity
	var inspection: Dictionary = OrganismInspector.compile(controller, _selected_entity)
	if not bool(inspection.get("success", false)):
		content.text = "inspector error: " + str(inspection.get("error", "?"))
		return
	content.text = OrganismInspector.render_text(inspection.view)

## CREATE VARIANT: propose a NEW validated genome variant for the selected
## organism through the canonical A3 editor; accepted variants are registered
## as session founders (never applied to the live population).
func command_create_variant() -> bool:
	if controller == null or _selected_entity.is_empty():
		return false
	var genome := OrganismInspector.genome_of(controller, _selected_entity)
	if genome.is_empty():
		_set_inspector_status("VARIANT: organism not found")
		return false
	var operator := "small"
	var operator_option := get_node_or_null("WorkbenchUI/InspectorControls/VariantOperator") as OptionButton
	if operator_option != null and operator_option.item_count > 0:
		operator = String(operator_option.get_item_text(maxi(0, operator_option.selected)))
	var seed := 7
	var seed_spin := get_node_or_null("WorkbenchUI/InspectorControls/VariantSeed") as SpinBox
	if seed_spin != null:
		seed = int(seed_spin.value)
	var proposed: Dictionary = GenomeEditor.propose_variant(genome, {"kind": "mutate", "operator": operator, "seed": seed})
	if not bool(proposed.get("success", false)):
		# Validation error is surfaced; nothing is applied.
		_set_inspector_status("VARIANT REJECTED: " + str(proposed.get("error", "?")))
		return false
	var hash := GenomeEditor.register_founder(founder_registry, proposed.genome)
	if branch_manager != null:
		branch_manager.set_founder_registry(founder_registry)
	_set_inspector_status("VARIANT OK founder hash " + hash.substr(0, 10))
	return true

func _set_inspector_status(text: String) -> void:
	var status := get_node_or_null("WorkbenchUI/InspectorControls/InspectorStatus") as Label
	if status != null:
		status.text = text

# --- Checkpoint / restore / fork (P8) ------------------------------------------

func command_checkpoint() -> bool:
	if branch_manager == null:
		return false
	var result: Dictionary = branch_manager.create_checkpoint("", {"source": "workbench"}, {})
	if not bool(result.get("success", false)):
		_set_branch_status("CHECKPOINT FAILED: " + str(result.get("error", "?")))
		return false
	_last_checkpoint = result.checkpoint
	_set_branch_status("CHECKPOINT @" + str(int(_last_checkpoint.tick)) + " id " + String(_last_checkpoint.checkpoint_id).substr(0, 8))
	return true

func command_restore() -> bool:
	if branch_manager == null or _last_checkpoint.is_empty():
		_set_branch_status("RESTORE: no checkpoint")
		return false
	running = false
	pending_target = {}
	var result: Dictionary = branch_manager.restore(_last_checkpoint)
	if not bool(result.get("success", false)):
		_set_branch_status("RESTORE FAILED: " + str(result.get("error", "?")))
		return false
	_set_branch_status("RESTORED to tick " + str(int(result.tick)))
	_refresh_from_controller(true)
	return true

## FORK: new branch from the last checkpoint; when an env-zone field is
## selected, the optional environment patch is applied to the new branch.
func command_fork() -> bool:
	if branch_manager == null or _last_checkpoint.is_empty():
		_set_branch_status("FORK: no checkpoint")
		return false
	running = false
	pending_target = {}
	var patch := _selected_env_patch()
	var result: Dictionary = branch_manager.fork(_last_checkpoint, patch, "fork/ui")
	if not bool(result.get("success", false)):
		_set_branch_status("FORK FAILED: " + str(result.get("error", "?")))
		return false
	bind_controller(result.controller)
	_set_branch_status("FORKED branch " + String(result.branch_id).substr(0, 8))
	return true

func command_show_branches() -> void:
	if branch_manager == null:
		return
	_set_branch_status(" | ".join(PackedStringArray(branch_manager.branch_tree_text().split("\n"))))

func _selected_env_patch() -> Dictionary:
	var zone_option := get_node_or_null("WorkbenchUI/PlacementControls/EnvZone") as OptionButton
	var field_option := get_node_or_null("WorkbenchUI/PlacementControls/EnvField") as OptionButton
	var spin := get_node_or_null("WorkbenchUI/PlacementControls/EnvValue") as SpinBox
	if zone_option == null or field_option == null or spin == null:
		return {}
	if zone_option.item_count == 0 or field_option.item_count == 0:
		return {}
	return EnvironmentPatch.patch(
		String(zone_option.get_item_text(maxi(0, zone_option.selected))),
		String(field_option.get_item_text(maxi(0, field_option.selected))),
		int(spin.value)
	)

func _set_branch_status(text: String) -> void:
	var status := get_node_or_null("WorkbenchUI/BranchControls/BranchStatus") as Label
	if status != null:
		status.text = text

# --- Tick-driven update with wall-clock budget ------------------------------

func _process(delta: float) -> void:
	if not running or controller == null:
		return
	_wall_elapsed += delta
	_elapsed += delta
	var interval := 1.0 / ticks_per_second
	if String(pending_target.get("kind", "")) == "tick":
		_process_run_to_tick(interval)
		return
	var executed := 0
	while _elapsed >= interval and executed < MAX_TICKS_PER_FRAME:
		_elapsed -= interval
		executed += 1
		if not _advance_one_tick():
			running = false
			return
	_refresh_from_controller(false)

## RUN TO TICK executes whole batches through controller.run (still bounded
## by the wall-clock cadence and MAX_TICKS_PER_FRAME per frame).
func _process_run_to_tick(interval: float) -> void:
	var due := mini(int(_elapsed / interval), MAX_TICKS_PER_FRAME)
	if due <= 0:
		return
	_consume_due(due * interval)
	var snapshot: Dictionary = controller.get_snapshot()
	var remaining := int(pending_target.value) - int(snapshot.get("tick", 0))
	if remaining <= 0:
		running = false
		_refresh_from_controller(false)
		return
	var result: Dictionary = controller.run(mini(due, remaining))
	if not bool(result.get("success", false)):
		running = false
	_refresh_from_controller(false)

func _consume_due(seconds: float) -> void:
	_elapsed = maxf(0.0, _elapsed - seconds)

## One cadence tick: plain run, or a pending generation/condition check.
func _advance_one_tick() -> bool:
	var kind := String(pending_target.get("kind", ""))
	if kind == "generation" or kind == "condition":
		var snapshot: Dictionary = controller.get_snapshot()
		if _pending_reached(kind, snapshot):
			running = false
			return false
	return _step_once()

func _pending_reached(kind: String, snapshot: Dictionary) -> bool:
	if kind == "generation":
		return _generation_now(snapshot) >= int(pending_target.value)
	if String(pending_target.get("value_kind", "")) == "tick_horizon":
		return int(snapshot.get("tick", 0)) >= _manifest_horizon()
	return snapshot.get("presentation", []).size() >= int(pending_target.value)

func _generation_now(snapshot: Dictionary) -> int:
	var generation := 0
	for view in snapshot.get("presentation", []):
		generation = maxi(generation, int(view.get("lineage_depth", 0)))
	return generation

func _manifest_horizon() -> int:
	if controller == null:
		return 0
	var manifest: Dictionary = controller.get_manifest()
	return int(manifest.get("horizon_ticks", 0))

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
	organism_views = _build_views(snapshot)
	_sync_markers()
	snapshot_updated.emit(snapshot)
	_update_status_bar(snapshot)
	if rebuild_all:
		_sync_placement_panel(snapshot)

## Views are built ONLY from the snapshot's read-only presentation views
## (P4 extension) — no debug_state dependency in the UI layer.
func _build_views(snapshot: Dictionary) -> Array[Dictionary]:
	var views: Array[Dictionary] = []
	var previous := {}
	for view in organism_views:
		previous[view.canonical_entity_id] = view.selection_state
	for entry in snapshot.get("presentation", []):
		var individual_id := String(entry.individual_id)
		var position: Array = entry.position_mm
		views.append({
			"canonical_entity_id": individual_id,
			"presentation_descriptor": {
				"position_mm": [int(position[0]), int(position[1]), int(position[2])],
				"alive": bool(entry.alive),
				"zone_id": String(entry.zone_id),
				"development_summary": entry.development_summary,
				"parent_id": String(entry.parent_id),
				"origin_kind": String(entry.origin_kind),
				"lineage_depth": int(entry.lineage_depth),
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
	# Simulation tick and wall-clock elapsed are shown SEPARATELY (P5).
	_status_bar.text = "sim tick %d | wall %.1fs | organisms %d | state %s | hash %s" % [
		int(snapshot.get("tick", 0)), _wall_elapsed, organism_views.size(),
		String(snapshot.get("status", "?")), hash_short,
	]

# --- P3 organism markers + P6 generic morphology meshes -----------------------

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
		# LOD-minimal fallback: markers stay hidden while morphology meshes
		# are enabled (P6), and remain the visible representation when OFF.
		marker.visible = not morphology_enabled
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
	_sync_morphology()

## Toggle generic morphology meshes (P6). ON by default; OFF restores the
## P3 sphere markers as the LOD-minimal fallback representation.
func set_morphology_enabled(value: bool) -> void:
	morphology_enabled = value
	for entity_id in _marker_by_id:
		var marker: MeshInstance3D = _marker_by_id[entity_id]
		marker.visible = not value
	if not value and _morphology_root != null:
		for entity_id in _morphology_by_id.keys():
			_morphology_by_id[entity_id].queue_free()
		_morphology_by_id.clear()
	_sync_markers()

func set_morphology_lod(lod: String) -> void:
	if GenericRealizer.LOD_DETAIL.has(String(lod).to_upper()):
		morphology_lod = String(lod).to_upper()
		_sync_markers()

## Read-only morphology projection: canonical development modules are read
## (never written) from the controller's completed state via debug_state;
## descriptors + realization run entirely in presentation space.
func _sync_morphology() -> void:
	if _morphology_root == null or controller == null or not morphology_enabled:
		return
	var bodies := {}
	if controller.has_method("debug_state"):
		for entry in controller.debug_state().population:
			bodies[String(entry.state.individual_id)] = {
				"modules": entry.state.development.modules,
				"position_mm": entry.state.position_mm,
				"alive": bool(entry.state.alive),
			}
	var seen := {}
	for view in organism_views:
		var entity_id: String = view.canonical_entity_id
		if not bodies.has(entity_id):
			continue
		var body: Dictionary = bodies[entity_id]
		seen[entity_id] = true
		var holder: Node3D = _morphology_by_id.get(entity_id)
		if holder == null:
			holder = Node3D.new()
			holder.name = "Morphology_" + entity_id.replace("/", "_")
			_morphology_root.add_child(holder)
			_morphology_by_id[entity_id] = holder
		for child in holder.get_children():
			child.queue_free()
		var descriptor: Dictionary = MorphologyDescriptor.compile(body.modules, entity_id, body.position_mm)
		if descriptor.is_empty():
			continue
		# Stable per-entity palette seed (presentation only).
		var manifest: Dictionary = GenericRealizer.realize(descriptor, {"lod": morphology_lod, "palette_seed": entity_id.hash()})
		var primitives: Array = manifest.get("primitives", [])
		for primitive in primitives:
			var color: Array = primitive.color
			if not body.alive:
				color = [color[0] * 0.35, color[1] * 0.35, color[2] * 0.35, 1.0]
			if view.selection_state == "selected":
				color = [1.0, 0.9, 0.2, 1.0]
			primitive.color = color
		build_meshes(primitives, holder)
	for entity_id in _morphology_by_id.keys():
		if not seen.has(entity_id):
			_morphology_by_id[entity_id].queue_free()
			_morphology_by_id.erase(entity_id)

## Thin Godot adapter (P6): universal primitive manifest -> MeshInstance3D
## children under parent_node. Scale: mm / 100 (P3 visual convention).
func build_meshes(primitives: Array, parent_node: Node3D) -> void:
	for primitive in primitives:
		var kind := String(primitive.kind)
		var color: Array = primitive.color
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(float(color[0]), float(color[1]), float(color[2]))
		if float(color[3]) < 0.999:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var inst := MeshInstance3D.new()
		inst.name = "Primitive_" + String(primitive.module_id) + "_" + kind
		match kind:
			"capsule":
				var mesh_c := CapsuleMesh.new()
				var from := _scene_point(primitive.from_mm)
				var to := _scene_point(primitive.to_mm)
				var radius := float(primitive.radius_mm) / MM_PER_SCENE_UNIT
				var axis := to - from
				var length: float = maxf(axis.length(), 0.01)
				mesh_c.radius = radius
				mesh_c.height = length + 2.0 * radius
				mesh_c.radial_segments = int(primitive.radial_segments)
				mesh_c.rings = int(primitive.rings)
				inst.mesh = mesh_c
				inst.material_override = material
				inst.transform = Transform3D(_axis_basis(axis), (from + to) * 0.5)
			"sphere":
				var mesh_s := SphereMesh.new()
				mesh_s.radius = maxf(float(primitive.radius_mm) / MM_PER_SCENE_UNIT, 0.01)
				mesh_s.height = 2.0 * mesh_s.radius
				mesh_s.radial_segments = int(primitive.radial_segments)
				mesh_s.rings = int(primitive.rings)
				inst.mesh = mesh_s
				inst.material_override = material
				inst.position = _scene_point(primitive.center_mm)
			"junction_plane":
				var mesh_p := PlaneMesh.new()
				var side_x := float(primitive.size_mm[0]) / MM_PER_SCENE_UNIT
				var side_z := float(primitive.size_mm[1]) / MM_PER_SCENE_UNIT
				mesh_p.size = Vector2(maxf(side_x, 0.02), maxf(side_z, 0.02))
				mesh_p.orientation = PlaneMesh.FACE_Y
				inst.mesh = mesh_p
				inst.material_override = material
				inst.position = _scene_point(primitive.center_mm)
			_:
				# Universal adapter fallback: any unknown kind still renders
				# as a bounding box (never zero primitives).
				var mesh_b := BoxMesh.new()
				var size: Array = primitive.size_mm
				mesh_b.size = Vector3(
					maxf(float(size[0]) / MM_PER_SCENE_UNIT, 0.02),
					maxf(float(size[1]) / MM_PER_SCENE_UNIT, 0.02),
					maxf(float(size[2]) / MM_PER_SCENE_UNIT, 0.02),
				)
				inst.mesh = mesh_b
				inst.material_override = material
				inst.position = _scene_point(primitive.center_mm)
		parent_node.add_child(inst)

func _scene_point(mm: Array) -> Vector3:
	return Vector3(
		float(mm[0]) / MM_PER_SCENE_UNIT,
		MORPHOLOGY_BASE_OFFSET_Y + float(mm[1]) / MM_PER_SCENE_UNIT,
		float(mm[2]) / MM_PER_SCENE_UNIT
	)

## Basis whose local +Y aligns with the capsule axis direction.
func _axis_basis(direction: Vector3) -> Basis:
	var y := direction.normalized() if direction.length() > 0.0001 else Vector3.UP
	var helper := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

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
	_morphology_root = Node3D.new()
	_morphology_root.name = "OrganismMorphology"
	add_child(_morphology_root)
	_status_bar = get_node_or_null("WorkbenchUI/StatusBar")
	_run_button = get_node_or_null("WorkbenchUI/ExperimentControls/Run") as Button
	_connect_button("WorkbenchUI/ExperimentControls/Run", command_run)
	_connect_button("WorkbenchUI/ExperimentControls/Pause", command_pause)
	_connect_button("WorkbenchUI/ExperimentControls/Step", command_step)
	_connect_button("WorkbenchUI/ExperimentControls/Reset", command_reset)
	_connect_button("WorkbenchUI/ExperimentControls/Fast", command_fast)
	_connect_button("WorkbenchUI/ExperimentControls/StepN", Callable(self, "command_step_n_button"))
	_connect_button("WorkbenchUI/ExperimentControls/RunToTick", Callable(self, "command_run_to_tick_button"))
	_connect_button("WorkbenchUI/ExperimentControls/RunToGen", Callable(self, "command_run_to_generation_button"))
	_connect_button("WorkbenchUI/ExperimentControls/RunToCondition", Callable(self, "command_run_to_condition_button"))
	_connect_button("WorkbenchUI/PlacementControls/GeneratePlacement", Callable(self, "command_generate_placement_button"))
	_connect_button("WorkbenchUI/PlacementControls/ApplyEnvPatch", Callable(self, "command_apply_env_patch_button"))
	var presets := get_node_or_null("WorkbenchUI/PlacementControls/PlacementPreset") as OptionButton
	if presets != null:
		for preset in PlacementPlan.PRESETS:
			presets.add_item(preset)
	var fields := get_node_or_null("WorkbenchUI/PlacementControls/EnvField") as OptionButton
	if fields != null:
		for field in EnvironmentPatch.EDITABLE_FIELDS:
			fields.add_item(field)
	# Morphology toggle (P6): ON by default; OFF shows the P3 marker fallback.
	var morphology_toggle := get_node_or_null("WorkbenchUI/ExperimentControls/Morphology") as CheckBox
	if morphology_toggle != null:
		morphology_toggle.button_pressed = morphology_enabled
		morphology_toggle.toggled.connect(set_morphology_enabled)
	# Inspector panel (P7): opens on selection_changed.
	selection_changed.connect(_on_selection_changed_inspector)
	# Genome editor (P7): mutate operators from the canonical OPERATORS list.
	var operators := get_node_or_null("WorkbenchUI/InspectorControls/VariantOperator") as OptionButton
	if operators != null:
		for operator in MutationProxy.OPERATORS:
			operators.add_item(operator)
	_connect_button("WorkbenchUI/InspectorControls/CreateVariant", command_create_variant)
	# Checkpoint / restore / fork / branch tree (P8).
	_connect_button("WorkbenchUI/BranchControls/Checkpoint", command_checkpoint)
	_connect_button("WorkbenchUI/BranchControls/Restore", command_restore)
	_connect_button("WorkbenchUI/BranchControls/Fork", command_fork)
	_connect_button("WorkbenchUI/BranchControls/ShowBranches", Callable(self, "command_show_branches"))

# --- Button handlers (read spinner/option values, then command) -------------

func command_step_n_button() -> void:
	var spin := get_node_or_null("WorkbenchUI/ExperimentControls/StepNSpin") as SpinBox
	command_step_n(int(spin.value) if spin != null else 1)

func command_run_to_tick_button() -> void:
	var spin := get_node_or_null("WorkbenchUI/ExperimentControls/TickTarget") as SpinBox
	command_run_to_tick(int(spin.value) if spin != null else 0)

func command_run_to_generation_button() -> void:
	var spin := get_node_or_null("WorkbenchUI/ExperimentControls/GenTarget") as SpinBox
	command_run_to_generation(int(spin.value) if spin != null else 1)

func command_run_to_condition_button() -> void:
	var kind_option := get_node_or_null("WorkbenchUI/ExperimentControls/ConditionKind") as OptionButton
	var spin := get_node_or_null("WorkbenchUI/ExperimentControls/ConditionValue") as SpinBox
	var value := int(spin.value) if spin != null else 1
	var value_kind := "population_at_least"
	if kind_option != null and kind_option.selected == 1:
		value_kind = "tick_horizon"
	command_run_to_condition(value_kind, value)

func command_generate_placement_button() -> void:
	var option := get_node_or_null("WorkbenchUI/PlacementControls/PlacementPreset") as OptionButton
	if option == null:
		return
	command_generate_placement(String(option.get_item_text(option.selected)))

func command_apply_env_patch_button() -> void:
	var zone_option := get_node_or_null("WorkbenchUI/PlacementControls/EnvZone") as OptionButton
	var field_option := get_node_or_null("WorkbenchUI/PlacementControls/EnvField") as OptionButton
	var spin := get_node_or_null("WorkbenchUI/PlacementControls/EnvValue") as SpinBox
	if zone_option == null or field_option == null or spin == null:
		return
	if zone_option.item_count == 0 or field_option.item_count == 0:
		return
	command_apply_environment_patch(
		String(zone_option.get_item_text(maxi(0, zone_option.selected))),
		String(field_option.get_item_text(maxi(0, field_option.selected))),
		int(spin.value)
	)

## Keep the env-zone option list in sync with the current manifest zones.
func _sync_placement_panel(snapshot: Dictionary) -> void:
	var zone_option := get_node_or_null("WorkbenchUI/PlacementControls/EnvZone") as OptionButton
	if zone_option == null or controller == null:
		return
	var manifest: Dictionary = controller.get_manifest()
	var previous := ""
	if zone_option.item_count > 0:
		previous = String(zone_option.get_item_text(maxi(0, zone_option.selected)))
	zone_option.clear()
	for zone in manifest.environment.zones:
		zone_option.add_item(String(zone.id))
		if String(zone.id) == previous:
			zone_option.selected = zone_option.item_count - 1

func _connect_button(path: String, action: Callable) -> void:
	var button := get_node_or_null(path) as Button
	if button != null:
		button.pressed.connect(action)
