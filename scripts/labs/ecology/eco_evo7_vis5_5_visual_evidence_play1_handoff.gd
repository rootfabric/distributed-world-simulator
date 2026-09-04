extends Node3D

## ECO.EVO7 VIS5.5 — Visual Evidence / Integrated PLAY1 Handoff.
##
## Presentation-only operator lab over the accepted VIS5.3 mixed composition and
## VIS5.4 local LOD/streaming gate. It creates no ecology/terrain/network/
## persistence/PERF2 authority. Its job is to make the accepted truth boundary
## visible, produce a repeatable capture sequence, and export a PLAY1 handoff
## package that explicitly keeps final performance acceptance behind PERF2.CONV.

const Vis53LabScript = preload("res://scripts/labs/ecology/eco_evo7_vis5_3_mixed_strata_composition_lab.gd")
const Vis54GateScript = preload("res://scripts/labs/ecology/eco_evo7_vis5_4_composition_lod_streaming_gate.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis5_visual_evidence_play1_handoff.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS5.5.R1"

const PRESENTATION_ONLY := true
const ECOLOGY_AUTHORITY := false
const TERRAIN_AUTHORITY := false
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false
const PERF2_AUTHORITY := false
const PERF2_CONVERGENCE_REQUIRED := true
const PLAY1_PERFORMANCE_ACCEPTED := false
const VISUAL_LINE_STATUS := "READY_FOR_PLAY1_HANDOFF"

const VIEW_NEAR_OVERVIEW := "NEAR_OVERVIEW"
const VIEW_NEAR_DETAIL := "NEAR_DETAIL"
const VIEW_MID_CONTEXT := "MID_CONTEXT"
const VIEW_FAR_CONTEXT := "FAR_CONTEXT"
const VIEW_CULLED_CONTEXT := "CULLED_CONTEXT"
const VIEW_RETURN_AFTER_STREAMING := "RETURN_AFTER_STREAMING"
const VIEW_IDS := [
	VIEW_NEAR_OVERVIEW,
	VIEW_NEAR_DETAIL,
	VIEW_MID_CONTEXT,
	VIEW_FAR_CONTEXT,
	VIEW_CULLED_CONTEXT,
	VIEW_RETURN_AFTER_STREAMING,
]

const CAPTURE_FILENAMES := {
	VIEW_NEAR_OVERVIEW: "01_near_overview.png",
	VIEW_NEAR_DETAIL: "02_near_detail.png",
	VIEW_MID_CONTEXT: "03_mid_context.png",
	VIEW_FAR_CONTEXT: "04_far_context.png",
	VIEW_CULLED_CONTEXT: "05_culled_context.png",
	VIEW_RETURN_AFTER_STREAMING: "06_return_after_streaming.png",
}

@export var auto_initialize := true
@export var show_operator_hud := true

var lab = null
var gate = null
var camera: Camera3D = null
var initialized := false
var current_view_id := ""
var lifecycle_evidence_complete := false
var last_capture_bundle: Dictionary = {}
var last_handoff_package: Dictionary = {}

var hud_layer: CanvasLayer = null
var hud_panel: PanelContainer = null
var hud_title: Label = null
var hud_state: Label = null
var hud_truth: Label = null
var hud_controls: Label = null


func _ready() -> void:
	name = "EcoEvo7Vis55VisualEvidencePlay1Handoff"
	if auto_initialize:
		initialize_runtime()


func initialize_runtime(profile_override: Dictionary = {}) -> bool:
	if initialized:
		return true
	lab = Vis53LabScript.new()
	lab.auto_initialize = false
	lab.name = "Vis55MixedComposition"
	add_child(lab)
	if not lab.initialize_runtime(profile_override):
		return false
	gate = Vis54GateScript.new()
	if not gate.setup(lab):
		return false
	camera = lab.camera
	if camera == null:
		return false
	_configure_hud()
	initialized = true
	if not set_evidence_view(VIEW_NEAR_OVERVIEW):
		initialized = false
		return false
	_refresh_handoff_package()
	return validate_handoff_package(last_handoff_package)


func set_evidence_view(view_id: String) -> bool:
	if not initialized or view_id not in VIEW_IDS:
		return false
	var presentation = lab.get_presentation()
	var earth = lab.get_earth_world()
	if presentation == null or earth == null or camera == null:
		return false
	var center_direction: Vector3 = presentation.get_patch_center_direction().normalized()
	var center_world: Vector3 = earth.get_surface_point(center_direction)
	var basis: Basis = _up_basis(center_direction)
	var observer_world: Vector3 = center_world
	var target_world: Vector3 = center_world + center_direction * 8.0
	var fov: float = 67.0

	match view_id:
		VIEW_NEAR_OVERVIEW:
			observer_world = center_world + basis.x * 185.0 + basis.z * 120.0 + center_direction * 95.0
			fov = 66.0
		VIEW_NEAR_DETAIL:
			var plant_world: Vector3 = presentation.get_stem_world_position(0)
			var plant_up: Vector3 = plant_world.normalized()
			var plant_basis: Basis = _up_basis(plant_up)
			observer_world = plant_world + plant_basis.x * 18.0 + plant_basis.z * 14.0 + plant_up * 11.0
			target_world = plant_world + plant_up * 6.0
			fov = 58.0
		VIEW_MID_CONTEXT:
			observer_world = center_world + basis.x * 700.0 + center_direction * 90.0
			fov = 54.0
		VIEW_FAR_CONTEXT:
			observer_world = center_world + basis.x * 3000.0 + center_direction * 260.0
			fov = 44.0
		VIEW_CULLED_CONTEXT:
			observer_world = center_world + basis.x * 20000.0 + center_direction * 900.0
			fov = 30.0
		VIEW_RETURN_AFTER_STREAMING:
			observer_world = center_world + basis.x * 210.0 + basis.z * 55.0 + center_direction * 105.0
			fov = 64.0
		_:
			return false

	if not gate.update_observer(observer_world, 1.0 / 60.0, false):
		return false
	var render_origin: Vector3 = earth.get_render_origin()
	camera.position = observer_world - render_origin
	camera.fov = fov
	camera.look_at(target_world - render_origin, center_direction)
	camera.current = true
	current_view_id = view_id
	_refresh_operator_hud()
	_refresh_handoff_package()
	return true


func perform_handoff_lifecycle_evidence() -> Dictionary:
	if not initialized:
		return {}
	# Normalize to an accepted visible NEAR state before any scenery rebuild.
	# VIS5.3 snapshots macro visibility when rebuilding its composition summary;
	# starting from CULLED would otherwise leave a stale zero-visible diagnostic
	# even after PH5 later returns to NEAR. This changes presentation only.
	if not set_evidence_view(VIEW_NEAR_OVERVIEW):
		return {}
	var earth = lab.get_earth_world()
	var presentation = lab.get_presentation()
	var center_direction: Vector3 = presentation.get_patch_center_direction().normalized()
	var center_world: Vector3 = earth.get_surface_point(center_direction)
	var basis: Basis = _up_basis(center_direction)
	var source_before: Dictionary = _source_identity()
	var composition_hash_before := String(lab.get_summary().get("composition_hash", ""))
	var original_origin: Vector3 = earth.get_render_origin()
	var shifted_origin: Vector3 = original_origin + basis.x * 1500.0
	var recenter: Dictionary = gate.recenter_render_origin(shifted_origin)
	if recenter.is_empty() or not bool(recenter.get("identity_stable", false)):
		return {}
	var restore: Dictionary = gate.recenter_render_origin(original_origin)
	if restore.is_empty() or not bool(restore.get("identity_stable", false)):
		return {}
	if String(lab.get_summary().get("composition_hash", "")) != composition_hash_before:
		return {}

	var angular_offset: float = earth.local_recenter_distance_m * 1.6 / earth.get_planet_radius()
	var target_direction: Vector3 = center_direction.rotated(basis.x, angular_offset).normalized()
	var target_surface: Vector3 = earth.get_surface_point(target_direction)
	if target_surface.distance_to(earth.get_surface_anchor()) <= earth.local_recenter_distance_m:
		return {}
	var roundtrip: Dictionary = gate.roundtrip_region_rebuild(target_direction)
	if roundtrip.is_empty() or not bool(roundtrip.get("success", false)):
		return {}
	if not set_evidence_view(VIEW_RETURN_AFTER_STREAMING):
		return {}
	var source_after: Dictionary = _source_identity()
	var identity_stable: bool = _same_source_identity(source_before, source_after)
	lifecycle_evidence_complete = (
		identity_stable
		and String(lab.get_summary().get("composition_hash", "")) == composition_hash_before
		and int(roundtrip.get("rebuild_events", 0)) >= 2
		and bool(roundtrip.get("remote_placement_suppressed", false))
		and bool(roundtrip.get("return_placement_suppressed", false))
	)
	_refresh_handoff_package()
	return {
		"success": lifecycle_evidence_complete,
		"recenter": recenter.duplicate(true),
		"restore": restore.duplicate(true),
		"roundtrip": roundtrip.duplicate(true),
		"source_identity_stable": identity_stable,
		"composition_hash_restored": String(lab.get_summary().get("composition_hash", "")) == composition_hash_before,
		"center_world": center_world,
		"handoff_hash": String(last_handoff_package.get("handoff_hash", "")),
	}


func get_handoff_package() -> Dictionary:
	_refresh_handoff_package()
	return last_handoff_package.duplicate(true)


func get_capture_plan() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for view_id in VIEW_IDS:
		result.append({
			"view_id": view_id,
			"filename": String(CAPTURE_FILENAMES[view_id]),
			"expected_mode": _expected_mode_for_view(view_id),
			"truth_overlay_required": true,
		})
	return result


func capture_evidence_bundle(output_dir: String = "user://vis5_5_evidence") -> Dictionary:
	if not initialized:
		return {}
	if output_dir.is_empty():
		return {}
	var absolute_dir: String = ProjectSettings.globalize_path(output_dir)
	if output_dir.begins_with("/"):
		absolute_dir = output_dir
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return {}

	var shots: Array[Dictionary] = []
	for view_id in [VIEW_NEAR_OVERVIEW, VIEW_NEAR_DETAIL, VIEW_MID_CONTEXT, VIEW_FAR_CONTEXT, VIEW_CULLED_CONTEXT]:
		if not set_evidence_view(view_id):
			return {}
		await _settle_render_frames(3)
		var shot: Dictionary = _capture_current_view(absolute_dir, view_id)
		if shot.is_empty():
			return {}
		shots.append(shot)

	var lifecycle: Dictionary = perform_handoff_lifecycle_evidence()
	if lifecycle.is_empty() or not bool(lifecycle.get("success", false)):
		return {}
	await _settle_render_frames(3)
	var return_shot: Dictionary = _capture_current_view(absolute_dir, VIEW_RETURN_AFTER_STREAMING)
	if return_shot.is_empty():
		return {}
	shots.append(return_shot)

	_refresh_handoff_package()
	last_capture_bundle = {
		"schema": "distributed_world_simulator.ecology.evo7_vis5_visual_capture_bundle.v1",
		"version": VERSION,
		"revision": REVISION,
		"visual_line_status": VISUAL_LINE_STATUS,
		"capture_count": shots.size(),
		"shots": shots,
		"lifecycle_evidence_complete": lifecycle_evidence_complete,
		"handoff": last_handoff_package.duplicate(true),
		"output_directory": absolute_dir,
	}
	last_capture_bundle["capture_bundle_hash"] = _capture_bundle_hash(last_capture_bundle)
	var manifest_path: String = absolute_dir.path_join("vis5_5_evidence_manifest.json")
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return {}
	file.store_string(JSON.stringify(_json_safe(last_capture_bundle), "  "))
	file.close()
	last_capture_bundle["manifest_path"] = manifest_path
	last_capture_bundle["manifest_sha256"] = _sha256_file(manifest_path)
	return last_capture_bundle.duplicate(true)


static func validate_handoff_package(value: Dictionary) -> bool:
	if value.is_empty():
		return false
	if String(value.get("schema", "")) != SCHEMA:
		return false
	if String(value.get("version", "")) != VERSION or String(value.get("revision", "")) != REVISION:
		return false
	if not bool(value.get("presentation_only", false)):
		return false
	for authority_key in ["ecology_authority", "terrain_authority", "network_authority", "persistence_authority", "perf2_authority"]:
		if bool(value.get(authority_key, true)):
			return false
	if not bool(value.get("perf2_convergence_required", false)):
		return false
	if bool(value.get("play1_performance_accepted", true)):
		return false
	if String(value.get("visual_line_status", "")) != VISUAL_LINE_STATUS:
		return false
	if not bool(value.get("visual_composition_ready", false)):
		return false
	if not bool(value.get("play1_handoff_ready", false)):
		return false
	if String(value.get("terrain_source", "")) != "ProceduralEarthWorld":
		return false
	if String(value.get("macro_truth_status", "")) != "CANONICAL_ECO_VIS4_PH5":
		return false
	if String(value.get("ground_cover_truth_status", "")) != "NONCANONICAL_SCENERY":
		return false
	if String(value.get("rock_truth_status", "")) != "TERRAIN_SCENERY":
		return false
	if String(value.get("source_ecology_hash", "")).length() != 64:
		return false
	if String(value.get("macro_bridge_hash", "")).length() != 64:
		return false
	if String(value.get("descriptor_adapter_hash", "")).length() != 64:
		return false
	if String(value.get("composition_hash", "")).length() != 64:
		return false
	if int(value.get("macro_record_count", 0)) <= 0:
		return false
	if int(value.get("ground_cover_instances", 0)) <= 0:
		return false
	if int(value.get("rock_instances", 0)) <= 0:
		return false
	if not bool(value.get("procedural_tree_placement_suppressed", false)):
		return false
	var capture_plan = value.get("capture_plan", [])
	if not capture_plan is Array or capture_plan.size() != VIEW_IDS.size():
		return false
	var seen_modes: Dictionary = {}
	for item in capture_plan:
		if not item is Dictionary:
			return false
		var view_id: String = String(item.get("view_id", ""))
		if view_id not in VIEW_IDS:
			return false
		if not String(item.get("filename", "")).ends_with(".png"):
			return false
		if not bool(item.get("truth_overlay_required", false)):
			return false
		seen_modes[String(item.get("expected_mode", ""))] = true
	for required_mode in [Vis54GateScript.MODE_NEAR, Vis54GateScript.MODE_MID, Vis54GateScript.MODE_FAR, Vis54GateScript.MODE_CULLED]:
		if not seen_modes.has(required_mode):
			return false
	if not bool(value.get("workload_is_proxy", false)):
		return false
	if not bool(value.get("frame_diagnostics_observational_only", false)):
		return false
	if bool(value.get("ecology_identity_drift", true)):
		return false
	return String(value.get("handoff_hash", "")) == compute_handoff_hash(value)


static func compute_handoff_hash(value: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		String(value.get("visual_line_status", "")),
		String(value.get("terrain_source", "")),
		String(value.get("macro_truth_status", "")),
		String(value.get("ground_cover_truth_status", "")),
		String(value.get("rock_truth_status", "")),
		String(value.get("source_ecology_hash", "")),
		String(value.get("macro_bridge_hash", "")),
		String(value.get("descriptor_adapter_hash", "")),
		String(value.get("composition_hash", "")),
		str(int(value.get("macro_record_count", 0))),
		str(int(value.get("ground_cover_instances", 0))),
		str(int(value.get("rock_instances", 0))),
		str(int(value.get("composition_cost_proxy", 0))),
		str(int(value.get("composition_draw_call_proxy", 0))),
		str(bool(value.get("lifecycle_evidence_complete", false))),
		str(bool(value.get("perf2_convergence_required", false))),
		str(bool(value.get("play1_performance_accepted", true))),
		str(bool(value.get("procedural_tree_placement_suppressed", false))),
	])).sha256_text()


func _refresh_handoff_package() -> void:
	if not initialized or lab == null or gate == null:
		last_handoff_package = {}
		return
	var composition: Dictionary = lab.get_summary()
	var evidence: Dictionary = gate.get_evidence()
	var valid_composition: bool = Vis53LabScript.validate_summary(composition)
	var valid_gate: bool = Vis54GateScript.validate_evidence(evidence)
	last_handoff_package = {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"presentation_only": PRESENTATION_ONLY,
		"ecology_authority": ECOLOGY_AUTHORITY,
		"terrain_authority": TERRAIN_AUTHORITY,
		"network_authority": NETWORK_AUTHORITY,
		"persistence_authority": PERSISTENCE_AUTHORITY,
		"perf2_authority": PERF2_AUTHORITY,
		"perf2_convergence_required": PERF2_CONVERGENCE_REQUIRED,
		"play1_performance_accepted": PLAY1_PERFORMANCE_ACCEPTED,
		"visual_line_status": VISUAL_LINE_STATUS,
		"visual_composition_ready": valid_composition and valid_gate,
		"play1_handoff_ready": valid_composition and valid_gate,
		"current_view_id": current_view_id,
		"current_mode": String(evidence.get("mode", "")),
		"terrain_source": String(composition.get("terrain_source", "")),
		"macro_truth_status": String(composition.get("macro_truth_status", "")),
		"ground_cover_truth_status": String(composition.get("ground_cover_truth_status", "")),
		"rock_truth_status": String(composition.get("rock_truth_status", "")),
		"source_ecology_hash": String(composition.get("source_ecology_hash", "")),
		"macro_bridge_hash": String(composition.get("macro_bridge_hash", "")),
		"descriptor_adapter_hash": String(evidence.get("descriptor_adapter_hash", "")),
		"composition_hash": String(composition.get("composition_hash", "")),
		"macro_record_count": int(composition.get("macro_record_count", 0)),
		"macro_visible_individual_count": int(evidence.get("ph5_visible_individual_count", 0)),
		"ground_cover_instances": int(composition.get("ground_cover_instances", 0)),
		"ground_cover_visible_instances": int(evidence.get("ground_cover_visible_instances", 0)),
		"rock_instances": int(composition.get("rock_instances", 0)),
		"rock_visible_instances": int(evidence.get("rock_visible_instances", 0)),
		"terrain_relief_range_m": float(composition.get("terrain_relief_range_m", 0.0)),
		"terrain_maximum_geometric_slope_deg": float(composition.get("terrain_maximum_geometric_slope_deg", 0.0)),
		"composition_cost_proxy": int(evidence.get("composition_cost_proxy", 0)),
		"composition_draw_call_proxy": int(evidence.get("composition_draw_call_proxy", 0)),
		"workload_is_proxy": bool(evidence.get("workload_is_proxy", false)),
		"frame_diagnostics_observational_only": bool(evidence.get("frame_diagnostics_observational_only", false)),
		"procedural_tree_placement_suppressed": bool(evidence.get("procedural_tree_placement_suppressed", false)),
		"ecology_identity_drift": bool(evidence.get("ecology_identity_drift", true)),
		"render_origin_recenter_count": int(evidence.get("render_origin_recenter_count", 0)),
		"local_surface_rebuild_count": int(evidence.get("local_surface_rebuild_count", 0)),
		"region_roundtrip_count": int(evidence.get("region_roundtrip_count", 0)),
		"same_seed_roundtrip_verified": bool(evidence.get("same_seed_roundtrip_verified", false)),
		"lifecycle_evidence_complete": lifecycle_evidence_complete,
		"capture_plan": get_capture_plan(),
		"final_join": "VIS5.5 GREEN + PERF2.CONV GREEN -> PLAY1 integrated acceptance",
	}
	last_handoff_package["handoff_hash"] = compute_handoff_hash(last_handoff_package)
	_refresh_operator_hud()


func _configure_hud() -> void:
	if not show_operator_hud:
		return
	hud_layer = CanvasLayer.new()
	hud_layer.name = "Vis55OperatorHud"
	hud_layer.layer = 100
	add_child(hud_layer)
	hud_panel = PanelContainer.new()
	hud_panel.name = "TruthAndHandoffPanel"
	hud_panel.position = Vector2(18.0, 18.0)
	hud_panel.custom_minimum_size = Vector2(620.0, 0.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.05, 0.90)
	style.border_color = Color(0.36, 0.64, 0.82, 0.85)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	hud_panel.add_theme_stylebox_override("panel", style)
	hud_layer.add_child(hud_panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	hud_panel.add_child(box)
	hud_title = Label.new()
	hud_title.text = "ECO.EVO7 VIS5.5 — MIXED WORLD EVIDENCE"
	hud_title.add_theme_font_size_override("font_size", 21)
	box.add_child(hud_title)
	hud_state = Label.new()
	hud_state.add_theme_font_size_override("font_size", 16)
	box.add_child(hud_state)
	hud_truth = Label.new()
	hud_truth.add_theme_font_size_override("font_size", 15)
	hud_truth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hud_truth)
	hud_controls = Label.new()
	hud_controls.add_theme_font_size_override("font_size", 14)
	hud_controls.text = "Views: 1 Near  2 Detail  3 Mid  4 Far  5 Culled   |   H = lifecycle proof"
	box.add_child(hud_controls)


func _refresh_operator_hud() -> void:
	if hud_layer == null or hud_state == null or hud_truth == null or lab == null or gate == null:
		return
	var composition: Dictionary = lab.get_summary()
	var evidence: Dictionary = gate.get_evidence()
	hud_state.text = "VIEW %s   MODE %s   |   PH5 visible %d/%d   grass %d/%d   rocks %d/%d" % [
		current_view_id,
		String(evidence.get("mode", "")),
		int(evidence.get("ph5_visible_individual_count", 0)),
		int(evidence.get("ph5_record_count", 0)),
		int(evidence.get("ground_cover_visible_instances", 0)),
		int(evidence.get("ground_cover_total_instances", 0)),
		int(evidence.get("rock_visible_instances", 0)),
		int(evidence.get("rock_total_instances", 0)),
	]
	hud_truth.text = (
		"TRUTH: macro plants = CANONICAL ECO/VIS4 PH5   |   ground cover = NONCANONICAL_SCENERY   |   rocks = TERRAIN_SCENERY\n"
		+ "TERRAIN: ProceduralEarthWorld, relief %.1fm, sampled max slope %.1fdeg   |   procedural trees SUPPRESSED\n" % [
			float(composition.get("terrain_relief_range_m", 0.0)),
			float(composition.get("terrain_maximum_geometric_slope_deg", 0.0)),
		]
		+ "WORKLOAD: cost=%d draw_proxy=%d (PROXIES ONLY)   |   recenter=%d earth_rebuild=%d roundtrip=%d\n" % [
			int(evidence.get("composition_cost_proxy", 0)),
			int(evidence.get("composition_draw_call_proxy", 0)),
			int(evidence.get("render_origin_recenter_count", 0)),
			int(evidence.get("local_surface_rebuild_count", 0)),
			int(evidence.get("region_roundtrip_count", 0)),
		]
		+ "HANDOFF: VIS5 visual line READY   |   PLAY1 PERFORMANCE NOT ACCEPTED   |   PERF2.CONV REQUIRED"
	)


func _unhandled_input(event: InputEvent) -> void:
	if not initialized or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			set_evidence_view(VIEW_NEAR_OVERVIEW)
		KEY_2:
			set_evidence_view(VIEW_NEAR_DETAIL)
		KEY_3:
			set_evidence_view(VIEW_MID_CONTEXT)
		KEY_4:
			set_evidence_view(VIEW_FAR_CONTEXT)
		KEY_5:
			set_evidence_view(VIEW_CULLED_CONTEXT)
		KEY_H:
			perform_handoff_lifecycle_evidence()


func _capture_current_view(absolute_dir: String, view_id: String) -> Dictionary:
	var expected_mode: String = _expected_mode_for_view(view_id)
	var evidence: Dictionary = gate.get_evidence()
	if String(evidence.get("mode", "")) != expected_mode:
		return {}
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return {}
	var filename: String = String(CAPTURE_FILENAMES[view_id])
	var path: String = absolute_dir.path_join(filename)
	if image.save_png(path) != OK:
		return {}
	var sha: String = _sha256_file(path)
	if sha.length() != 64:
		return {}
	return {
		"view_id": view_id,
		"mode": expected_mode,
		"filename": filename,
		"path": path,
		"width": image.get_width(),
		"height": image.get_height(),
		"sha256": sha,
		"source_ecology_hash": String(evidence.get("source_ecology_hash", "")),
		"composition_hash": String(lab.get_summary().get("composition_hash", "")),
		"truth_overlay_present": hud_layer != null and hud_layer.visible,
	}


func _settle_render_frames(count: int) -> void:
	for _i in range(maxi(count, 1)):
		await get_tree().process_frame


func _expected_mode_for_view(view_id: String) -> String:
	match view_id:
		VIEW_NEAR_OVERVIEW, VIEW_NEAR_DETAIL, VIEW_RETURN_AFTER_STREAMING:
			return Vis54GateScript.MODE_NEAR
		VIEW_MID_CONTEXT:
			return Vis54GateScript.MODE_MID
		VIEW_FAR_CONTEXT:
			return Vis54GateScript.MODE_FAR
		VIEW_CULLED_CONTEXT:
			return Vis54GateScript.MODE_CULLED
	return ""


func _source_identity() -> Dictionary:
	var composition: Dictionary = lab.get_summary()
	var evidence: Dictionary = gate.get_evidence()
	return {
		"source_ecology_hash": String(composition.get("source_ecology_hash", "")),
		"macro_bridge_hash": String(composition.get("macro_bridge_hash", "")),
		"descriptor_adapter_hash": String(evidence.get("descriptor_adapter_hash", "")),
	}


static func _same_source_identity(a: Dictionary, b: Dictionary) -> bool:
	return (
		String(a.get("source_ecology_hash", "")) == String(b.get("source_ecology_hash", ""))
		and String(a.get("macro_bridge_hash", "")) == String(b.get("macro_bridge_hash", ""))
		and String(a.get("descriptor_adapter_hash", "")) == String(b.get("descriptor_adapter_hash", ""))
	)


static func _up_basis(up_value: Vector3) -> Basis:
	var up: Vector3 = up_value.normalized()
	var helper: Vector3 = Vector3.UP if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis: Vector3 = helper.cross(up).normalized()
	var z_axis: Vector3 = x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)


static func _sha256_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(mini(1024 * 1024, file.get_length() - file.get_position())))
	file.close()
	return context.finish().hex_encode()


static func _capture_bundle_hash(value: Dictionary) -> String:
	var tokens: PackedStringArray = PackedStringArray([
		String(value.get("schema", "")),
		String(value.get("version", "")),
		String(value.get("revision", "")),
		str(int(value.get("capture_count", 0))),
		str(bool(value.get("lifecycle_evidence_complete", false))),
		String(value.get("handoff", {}).get("handoff_hash", "")),
	])
	var shots = value.get("shots", [])
	if shots is Array:
		for shot in shots:
			if shot is Dictionary:
				tokens.append(String(shot.get("view_id", "")))
				tokens.append(String(shot.get("mode", "")))
				tokens.append(String(shot.get("sha256", "")))
	return "|".join(tokens).sha256_text()


static func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key in value.keys():
				out[String(key)] = _json_safe(value[key])
			return out
		TYPE_ARRAY:
			var out_array: Array = []
			for item in value:
				out_array.append(_json_safe(item))
			return out_array
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_BASIS:
			return [
				[value.x.x, value.x.y, value.x.z],
				[value.y.x, value.y.y, value.y.z],
				[value.z.x, value.z.y, value.z.z],
			]
		TYPE_TRANSFORM3D:
			return {
				"basis": _json_safe(value.basis),
				"origin": _json_safe(value.origin),
			}
		_:
			return value
