extends "res://scripts/labs/ecology/eco_evo7_vis1_spatial_world_viewer.gd"

const PhenotypeRenderAdapter = preload("res://scripts/labs/ecology/eco_evo7_vis2_phenotype_render_adapter.gd")
const PlantOverlay = preload("res://scripts/labs/ecology/eco_evo7_vis2_plant_overlay.gd")

## ECO.EVO7 VIS2 — procedural plant renderer over accepted VIS1 + LS3.6 public data.
## The viewer never realizes phenotype itself: it renders only LS3.4 phenotype evidence
## already present in the Workbench ecology snapshot.

const VIS2_CELL_COUNT := 1024
const VIS2_VIEWER_TITLE := "ECO EVO7 — VIS2 Procedural Plant Viewer"
const VIS2_RUNTIME_REVISION := "ECO.EVO7-VIS2.R2.1"

var phenotype_adapter = PhenotypeRenderAdapter.new()
var phenotype_render_snapshot: Dictionary = {}
var plant_overlay = null
var roots_toggle: CheckButton
var phenotype_status: Label

func _ready() -> void:
    ensure_ui_built()
    _apply_vis2_identity()
    _ensure_vis2_ui()
    print("ECO.EVO7 VIS2 READY scene=%s revision=%s" % [name, VIS2_RUNTIME_REVISION])
    if auto_initialize:
        initialize_runtime()

func _process(delta: float) -> void:
    super._process(delta)
    if workbench == null or plant_overlay == null:
        return
    var ecology_hash := String(workbench.get_workbench_snapshot().get("ecology_state_hash", ""))
    if String(phenotype_render_snapshot.get("source_ecology_state_hash", "")) != ecology_hash:
        _refresh_plants()
        _refresh_selection()

func initialize_runtime(source = null) -> bool:
    # Explicit initialization must be complete even in SceneTree --script tests
    # that quit from _init() before the first main-loop frame. Do not rely on
    # _ready() ordering for runtime identity or VIS2 UI composition.
    ensure_ui_built()
    _apply_vis2_identity()
    _ensure_vis2_ui()
    var ok := super.initialize_runtime(source)
    if ok:
        _refresh_plants()
        _refresh_selection()
    return ok

func manual_step(count: int) -> bool:
    var ok := super.manual_step(count)
    if ok:
        _refresh_plants()
        _refresh_selection()
    return ok

func reset_same_seeds() -> bool:
    var ok := super.reset_same_seeds()
    if ok:
        _refresh_plants()
        _refresh_selection()
    return ok

func apply_physical_controls(world_seed: int, environment_seed: int, recipe: String) -> bool:
    var ok := super.apply_physical_controls(world_seed, environment_seed, recipe)
    if ok:
        _refresh_plants()
        _refresh_selection()
    return ok

func get_runtime_identity() -> Dictionary:
    return {
        "scene_name": String(name),
        "viewer_title": VIS2_VIEWER_TITLE,
        "revision": VIS2_RUNTIME_REVISION,
    }

func get_ui_contract() -> Dictionary:
    var contract: Dictionary = super.get_ui_contract()
    contract["procedural_plants"] = plant_overlay != null
    contract["phenotype_driven"] = plant_overlay != null
    contract["root_debug"] = roots_toggle != null
    contract["founder_markers"] = plant_overlay != null
    return contract

func get_phenotype_render_snapshot() -> Dictionary:
    return phenotype_render_snapshot.duplicate(true)

func get_plant_render_descriptors() -> Array[Dictionary]:
    return Array(phenotype_render_snapshot.get("descriptors", [])).duplicate(true)

func set_show_roots(value: bool) -> bool:
    if plant_overlay == null:
        return false
    plant_overlay.set_show_roots(value)
    if roots_toggle != null:
        roots_toggle.set_pressed_no_signal(value)
    return true

func select_cell(index: int) -> bool:
    var ok := super.select_cell(index)
    if ok and plant_overlay != null:
        plant_overlay.set_selected_cell(index)
    return ok

func _refresh_world() -> void:
    if workbench == null or world_canvas == null:
        return
    var projection: Array[Dictionary] = workbench.get_overlay_projection(active_overlay_group)
    if projection.size() != VIS2_CELL_COUNT:
        var empty_projection: Array[Dictionary] = []
        for index in VIS2_CELL_COUNT:
            empty_projection.append({"index": index, "x": index % 32, "y": index / 32, "label": "", "value": 0.0})
        projection = empty_projection
    var no_dot_markers: Array[int] = []
    no_dot_markers.resize(VIS2_CELL_COUNT)
    no_dot_markers.fill(0)
    world_canvas.set_projection(active_overlay_group, projection, no_dot_markers)
    _refresh_plants()

func _refresh_selection() -> void:
    super._refresh_selection()
    if selected_details == null or phenotype_render_snapshot.is_empty():
        return
    var plants: Array[Dictionary] = []
    for value in Array(phenotype_render_snapshot.get("descriptors", [])):
        if value is Dictionary and int(Dictionary(value).get("cell_index", -1)) == selected_cell:
            plants.append(Dictionary(value))
    if plants.is_empty():
        selected_details.text += "\n\n[b]VIS2 plants[/b]\nNo living plant descriptors in this cell."
        return
    plants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["record_id"]) < String(b["record_id"])
    )
    var first: Dictionary = plants[0]
    var evidence := String(first.get("evidence_level", ""))
    if evidence == PhenotypeRenderAdapter.FOUNDER_EVIDENCE:
        selected_details.text += "\n\n[b]VIS2 plants[/b]\n%d founder marker(s). Phenotype evidence appears after first competition generation." % plants.size()
        return
    selected_details.text += "\n\n[b]VIS2 plant sample[/b]\nPlants: %d\nHeight: %.3f m\nLAI: %.3f\nRoot depth: %.3f m\nRoot spread: %.3f m\nRoot/shoot: %.3f\nWater satisfaction: %.3f\nResource balance: %.3f\nEvidence: %s" % [
        plants.size(), float(first["realized_height_m"]), float(first["leaf_area_index_proxy"]),
        float(first["realized_root_depth_m"]), float(first["realized_root_spread_m"]), float(first["root_shoot_ratio"]),
        float(first["water_satisfaction"]), float(first["realized_resource_balance"]), evidence,
    ]

func _on_camera_changed(zoom_value: float, pan_value: Vector2) -> void:
    super._on_camera_changed(zoom_value, pan_value)
    if plant_overlay != null:
        plant_overlay.set_camera_state(zoom_value, pan_value)

func _apply_vis2_identity() -> void:
    DisplayServer.window_set_title(VIS2_VIEWER_TITLE)
    var top := get_node_or_null("VIS1UI/Root/Top") as HBoxContainer
    if top != null and top.get_child_count() > 0 and top.get_child(0) is Label:
        (top.get_child(0) as Label).text = VIS2_VIEWER_TITLE

func _ensure_vis2_ui() -> void:
    if plant_overlay != null:
        return
    var controls := get_node_or_null("VIS1UI/Root/Body/ControlPanel/Controls") as VBoxContainer
    if controls != null:
        var divider := HSeparator.new(); controls.add_child(divider)
        var vis2_title := Label.new(); vis2_title.text = "VIS2 Procedural Plants"; controls.add_child(vis2_title)
        var visual_help := Label.new(); visual_help.name = "VIS2VisualHelp"; visual_help.text = "Gen 0 = founder sprouts only. Press +1 for phenotype plants. Zoom 2x–4x to inspect morphology."; visual_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(visual_help)
        roots_toggle = CheckButton.new(); roots_toggle.name = "ShowRoots"; roots_toggle.text = "Show root debug"; roots_toggle.toggled.connect(_on_roots_toggled); controls.add_child(roots_toggle)
        phenotype_status = Label.new(); phenotype_status.name = "PhenotypeStatus"; phenotype_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(phenotype_status)
    if world_canvas != null:
        plant_overlay = PlantOverlay.new()
        plant_overlay.name = "PlantOverlay"
        plant_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        world_canvas.add_child(plant_overlay)
        plant_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        plant_overlay.set_selected_cell(selected_cell)
        var camera: Dictionary = world_canvas.get_camera_state()
        plant_overlay.set_camera_state(float(camera.get("zoom", 1.0)), Vector2(float(camera.get("pan_x", 0.0)), float(camera.get("pan_y", 0.0))))

func _refresh_plants() -> void:
    if workbench == null or plant_overlay == null:
        return
    var ecology: Dictionary = workbench.get_ecology_snapshot()
    phenotype_render_snapshot = phenotype_adapter.build(ecology)
    if phenotype_render_snapshot.is_empty():
        plant_overlay.set_descriptors([])
        if phenotype_status != null:
            phenotype_status.text = "VIS2 evidence unavailable"
        return
    var source_hash := String(phenotype_render_snapshot.get("source_ecology_state_hash", ""))
    var workbench_snapshot: Dictionary = workbench.get_workbench_snapshot()
    if source_hash != String(workbench_snapshot.get("ecology_state_hash", "")):
        phenotype_render_snapshot = {}
        plant_overlay.set_descriptors([])
        if phenotype_status != null:
            phenotype_status.text = "VIS2 source binding failed"
        return
    plant_overlay.set_descriptors(Array(phenotype_render_snapshot["descriptors"]))
    plant_overlay.set_selected_cell(selected_cell)
    if phenotype_status != null:
        var generation := int(phenotype_render_snapshot["generation"])
        var phenotype_count := int(phenotype_render_snapshot["phenotype_evidence_count"])
        var founder_count := int(phenotype_render_snapshot["founder_marker_count"])
        if generation == 0:
            phenotype_status.text = "Generation 0 — founder sprouts only\nPress +1 for phenotype-driven plants\nFounder markers: %d\nPhenotype evidence: 0" % founder_count
        else:
            phenotype_status.text = "Generation: %d\nPhenotype evidence: %d\nFounder markers: %d" % [generation, phenotype_count, founder_count]

func _on_roots_toggled(value: bool) -> void:
    set_show_roots(value)
