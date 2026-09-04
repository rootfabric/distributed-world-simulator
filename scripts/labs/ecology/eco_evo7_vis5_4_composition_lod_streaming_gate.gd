extends RefCounted

## ECO.EVO7 VIS5.4 — local mixed-composition LOD / streaming gate.
##
## Read-only/presentation-only controller over the already accepted VIS5.3 lab.
## It owns no ecology, terrain, network, persistence, or PERF2 authority.
##
## Responsibilities:
##   * drive accepted PH5 projected-size LOD from observer world position;
##   * gate dense ground cover and terrain rocks by local composition distance;
##   * reproject/rebuild presentation scenery after render-origin recenter;
##   * certify a local-surface rebuild round trip without ecology identity drift;
##   * expose bounded-workload and frame observations as diagnostic evidence.

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis5_composition_lod_streaming_gate.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS5.4.R1"

const PRESENTATION_ONLY := true
const ECOLOGY_AUTHORITY := false
const TERRAIN_AUTHORITY := false
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false
const PERF2_AUTHORITY := false
const PERF2_CONVERGENCE_REQUIRED := true

const MODE_NEAR := "NEAR"
const MODE_MID := "MID"
const MODE_FAR := "FAR"
const MODE_CULLED := "CULLED"
const MODES := [MODE_NEAR, MODE_MID, MODE_FAR, MODE_CULLED]

const NEAR_MAX_DISTANCE_M := 350.0
const MID_MAX_DISTANCE_M := 1400.0
const FAR_MAX_DISTANCE_M := 7000.0
const RENDER_RECENTER_DISTANCE_M := 1200.0

var lab = null
var earth_world = null
var presentation = null
var ground_cover = null

var initialized := false
var observer_world_position := Vector3.ZERO
var current_mode := ""
var observer_update_count := 0
var mode_switch_count := 0
var render_origin_recenter_count := 0
var render_reprojection_count := 0
var local_surface_rebuild_count := 0
var scenery_rebuild_count := 0
var region_roundtrip_count := 0
var same_seed_roundtrip_verified := false
var last_recenter_identity_stable := true
var ecology_identity_drift := false
var last_region_roundtrip: Dictionary = {}
var last_recenter: Dictionary = {}

var _frame_sample_count := 0
var _frame_total_sec := 0.0
var _frame_min_sec := INF
var _frame_max_sec := 0.0
var _last_evidence: Dictionary = {}


func setup(lab_reference) -> bool:
	if initialized:
		return true
	lab = lab_reference
	if lab == null or not lab.has_method("is_mixed_ready") or not lab.is_mixed_ready():
		return false
	earth_world = lab.get_earth_world()
	presentation = lab.get_presentation()
	ground_cover = lab.get_ground_cover_bridge()
	if earth_world == null or presentation == null or ground_cover == null:
		return false
	if not earth_world.earth_rebuilt.is_connected(_on_earth_rebuilt):
		earth_world.earth_rebuilt.connect(_on_earth_rebuilt)
	var center := _patch_center_world()
	if center.length_squared() < 1.0:
		return false
	observer_world_position = center
	initialized = true
	if not update_observer(center, 0.0, false):
		initialized = false
		return false
	return validate_evidence(_last_evidence)


func update_observer(
	view_world_position: Vector3,
	delta: float = 0.0,
	auto_recenter: bool = false
) -> bool:
	if not initialized or not _finite_vec(view_world_position):
		return false
	if not is_finite(delta) or delta < 0.0:
		return false
	if auto_recenter:
		var origin: Vector3 = earth_world.get_render_origin()
		if origin.distance_to(view_world_position) > RENDER_RECENTER_DISTANCE_M:
			if recenter_render_origin(view_world_position).is_empty():
				return false
	observer_world_position = view_world_position
	observer_update_count += 1
	if delta > 0.0:
		_frame_sample_count += 1
		_frame_total_sec += delta
		_frame_min_sec = minf(_frame_min_sec, delta)
		_frame_max_sec = maxf(_frame_max_sec, delta)
	if not presentation.set_view_world_position(view_world_position):
		return false
	var next_mode := _mode_for_distance(_observer_distance_m())
	if next_mode != current_mode:
		current_mode = next_mode
		mode_switch_count += 1
	_apply_strata_visibility()
	_refresh_evidence()
	return validate_evidence(_last_evidence)


func recenter_render_origin(new_origin_world: Vector3) -> Dictionary:
	if not initialized or not _finite_vec(new_origin_world):
		return {}
	var old_origin: Vector3 = earth_world.get_render_origin()
	if old_origin.is_equal_approx(new_origin_world):
		_refresh_evidence()
		return {
			"changed": false,
			"identity_stable": true,
			"old_origin": old_origin,
			"new_origin": new_origin_world,
		}
	var before := _source_identity()
	var before_world: Vector3 = presentation.get_stem_world_position(0)
	var before_render: Vector3 = presentation.get_stem_render_position(0)
	earth_world.set_render_origin(new_origin_world)
	presentation.refresh_render_transform(true)
	render_origin_recenter_count += 1
	render_reprojection_count += 1
	var seed := int(lab.get_summary().get("presentation_seed", -1))
	if seed < 0 or not lab.rebuild_surface_scenery(seed):
		return {}
	scenery_rebuild_count += 1
	_apply_strata_visibility()
	var after := _source_identity()
	var after_world: Vector3 = presentation.get_stem_world_position(0)
	var after_render: Vector3 = presentation.get_stem_render_position(0)
	last_recenter_identity_stable = (
		_same_source_identity(before, after)
		and before_world.distance_to(after_world) < 0.001
	)
	ecology_identity_drift = ecology_identity_drift or not last_recenter_identity_stable
	last_recenter = {
		"changed": true,
		"identity_stable": last_recenter_identity_stable,
		"old_origin": old_origin,
		"new_origin": new_origin_world,
		"origin_delta_m": old_origin.distance_to(new_origin_world),
		"record_world_delta_m": before_world.distance_to(after_world),
		"record_render_delta_m": before_render.distance_to(after_render),
		"source_ecology_hash": String(after.get("source_ecology_hash", "")),
		"macro_bridge_hash": String(after.get("macro_bridge_hash", "")),
	}
	_refresh_evidence()
	return last_recenter.duplicate(true)


func roundtrip_region_rebuild(target_direction_value: Vector3) -> Dictionary:
	if (
		not initialized
		or not _finite_vec(target_direction_value)
		or target_direction_value.length_squared() < 0.5
	):
		return {}
	var target_direction := target_direction_value.normalized()
	var original_direction: Vector3 = presentation.get_patch_center_direction().normalized()
	var original_origin: Vector3 = earth_world.get_render_origin()
	var before_summary: Dictionary = lab.get_summary()
	var before_hash := String(before_summary.get("composition_hash", ""))
	var before_identity := _source_identity()
	var seed := int(before_summary.get("presentation_seed", -1))
	var events_before := local_surface_rebuild_count

	# During a remote terrain window the ecology patch scenery is deliberately
	# hidden. Canonical PH5 truth remains resident and is not rebound to terrain.
	_set_scenery_visible(false, false)
	earth_world.prepare_surface_region(target_direction, false)
	var remote_rebuild: Dictionary = earth_world.last_rebuild_summary.duplicate(true)
	var remote_placement_zero := _placement_is_suppressed(remote_rebuild)

	# Return the streamed Earth surface to the ecology patch before making the
	# mixed strata visible again.
	earth_world.prepare_surface_region(original_direction, false)
	var return_rebuild: Dictionary = earth_world.last_rebuild_summary.duplicate(true)
	earth_world.set_render_origin(original_origin)
	presentation.refresh_render_transform(true)
	render_reprojection_count += 1
	if seed < 0 or not lab.rebuild_surface_scenery(seed):
		return {}
	scenery_rebuild_count += 1
	_apply_strata_visibility()

	var after_summary: Dictionary = lab.get_summary()
	var after_identity := _source_identity()
	var restored_hash := String(after_summary.get("composition_hash", ""))
	var rebuild_events := local_surface_rebuild_count - events_before
	var return_placement_zero := _placement_is_suppressed(return_rebuild)
	var identity_stable := _same_source_identity(before_identity, after_identity)
	var restored_exact := restored_hash == before_hash
	same_seed_roundtrip_verified = (
		identity_stable
		and restored_exact
		and remote_placement_zero
		and return_placement_zero
		and rebuild_events >= 2
	)
	ecology_identity_drift = ecology_identity_drift or not identity_stable
	region_roundtrip_count += 1
	last_region_roundtrip = {
		"success": same_seed_roundtrip_verified,
		"target_direction": target_direction,
		"rebuild_events": rebuild_events,
		"remote_placement_suppressed": remote_placement_zero,
		"return_placement_suppressed": return_placement_zero,
		"source_identity_stable": identity_stable,
		"composition_hash_before": before_hash,
		"composition_hash_after": restored_hash,
		"composition_hash_restored": restored_exact,
		"remote_center_direction": remote_rebuild.get("center_direction", []),
		"return_center_direction": return_rebuild.get("center_direction", []),
	}
	_refresh_evidence()
	return last_region_roundtrip.duplicate(true)


func get_evidence() -> Dictionary:
	_refresh_evidence()
	return _last_evidence.duplicate(true)


func get_last_region_roundtrip() -> Dictionary:
	return last_region_roundtrip.duplicate(true)


func get_last_recenter() -> Dictionary:
	return last_recenter.duplicate(true)


static func validate_evidence(value: Dictionary) -> bool:
	if value.is_empty():
		return false
	if String(value.get("schema", "")) != SCHEMA:
		return false
	if String(value.get("version", "")) != VERSION:
		return false
	if String(value.get("revision", "")) != REVISION:
		return false
	if not bool(value.get("presentation_only", false)):
		return false
	for forbidden_authority in [
		"ecology_authority",
		"terrain_authority",
		"network_authority",
		"persistence_authority",
		"perf2_authority",
	]:
		if bool(value.get(forbidden_authority, true)):
			return false
	if not bool(value.get("perf2_convergence_required", false)):
		return false
	if String(value.get("mode", "")) not in MODES:
		return false
	if String(value.get("source_ecology_hash", "")).length() != 64:
		return false
	if String(value.get("macro_bridge_hash", "")).length() != 64:
		return false
	if String(value.get("descriptor_adapter_hash", "")).length() != 64:
		return false
	if bool(value.get("ecology_identity_drift", true)):
		return false
	if not bool(value.get("procedural_tree_placement_suppressed", false)):
		return false
	for key in [
		"ph5_record_count",
		"ph5_visible_individual_count",
		"ground_cover_total_instances",
		"ground_cover_visible_instances",
		"rock_total_instances",
		"rock_visible_instances",
		"composition_cost_proxy",
		"composition_draw_call_proxy",
		"observer_update_count",
		"mode_switch_count",
		"render_origin_recenter_count",
		"render_reprojection_count",
		"local_surface_rebuild_count",
		"scenery_rebuild_count",
		"region_roundtrip_count",
		"frame_sample_count",
	]:
		if int(value.get(key, -1)) < 0:
			return false
	if int(value.get("ph5_visible_individual_count", -1)) > int(value.get("ph5_record_count", -1)):
		return false
	if int(value.get("ground_cover_visible_instances", -1)) > int(value.get("ground_cover_total_instances", -1)):
		return false
	if int(value.get("rock_visible_instances", -1)) > int(value.get("rock_total_instances", -1)):
		return false
	var mode := String(value.get("mode", ""))
	if mode != MODE_NEAR and int(value.get("ground_cover_visible_instances", 0)) != 0:
		return false
	if mode in [MODE_FAR, MODE_CULLED] and int(value.get("rock_visible_instances", 0)) != 0:
		return false
	if int(value.get("render_origin_recenter_count", 0)) > 0 and not bool(value.get("last_recenter_identity_stable", false)):
		return false
	if int(value.get("region_roundtrip_count", 0)) > 0 and not bool(value.get("same_seed_roundtrip_verified", false)):
		return false
	for key in [
		"observer_distance_m",
		"average_frame_ms",
		"min_frame_ms",
		"max_frame_ms",
		"estimated_fps",
	]:
		var number := float(value.get(key, NAN))
		if not is_finite(number) or number < 0.0:
			return false
	if int(value.get("frame_sample_count", 0)) > 0:
		if float(value.get("average_frame_ms", 0.0)) <= 0.0:
			return false
		if float(value.get("max_frame_ms", 0.0)) < float(value.get("min_frame_ms", 0.0)):
			return false
		if float(value.get("estimated_fps", 0.0)) <= 0.0:
			return false
	var tier_counts_value = value.get("ph5_tier_counts", {})
	if not tier_counts_value is Dictionary:
		return false
	var tier_total := 0
	for tier in [
		"TIER_0_FULL",
		"TIER_1_REDUCED",
		"TIER_2_CANOPY",
		"TIER_3_IMPOSTOR",
		"TIER_4_POPULATION_ONLY",
	]:
		var count := int(tier_counts_value.get(tier, -1))
		if count < 0:
			return false
		tier_total += count
	if tier_total != int(value.get("ph5_record_count", -1)):
		return false
	return String(value.get("structural_evidence_hash", "")) == compute_structural_hash(value)


static func compute_structural_hash(value: Dictionary) -> String:
	var tiers: Dictionary = value.get("ph5_tier_counts", {})
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		String(value.get("mode", "")),
		String(value.get("source_ecology_hash", "")),
		String(value.get("macro_bridge_hash", "")),
		String(value.get("descriptor_adapter_hash", "")),
		str(int(value.get("ph5_record_count", 0))),
		str(int(value.get("ph5_visible_individual_count", 0))),
		str(int(tiers.get("TIER_0_FULL", 0))),
		str(int(tiers.get("TIER_1_REDUCED", 0))),
		str(int(tiers.get("TIER_2_CANOPY", 0))),
		str(int(tiers.get("TIER_3_IMPOSTOR", 0))),
		str(int(tiers.get("TIER_4_POPULATION_ONLY", 0))),
		str(int(value.get("ground_cover_total_instances", 0))),
		str(int(value.get("ground_cover_visible_instances", 0))),
		str(int(value.get("rock_total_instances", 0))),
		str(int(value.get("rock_visible_instances", 0))),
		str(int(value.get("composition_cost_proxy", 0))),
		str(int(value.get("composition_draw_call_proxy", 0))),
		str(int(value.get("render_origin_recenter_count", 0))),
		str(int(value.get("local_surface_rebuild_count", 0))),
		str(int(value.get("scenery_rebuild_count", 0))),
		str(int(value.get("region_roundtrip_count", 0))),
		str(bool(value.get("same_seed_roundtrip_verified", false))),
		str(bool(value.get("last_recenter_identity_stable", false))),
		str(bool(value.get("procedural_tree_placement_suppressed", false))),
	])).sha256_text()


func _refresh_evidence() -> void:
	if not initialized:
		_last_evidence = {}
		return
	var composition: Dictionary = lab.get_summary()
	var contract: Dictionary = presentation.get_contract()
	var ph5: Dictionary = contract.get("ph5", {})
	var perf: Dictionary = presentation.get_ph5_performance_counters()
	var ground_total := int(composition.get("ground_cover_instances", 0))
	var rock_total := int(composition.get("rock_instances", 0))
	var ground_visible := ground_total if current_mode == MODE_NEAR else 0
	var rock_visible := rock_total if current_mode in [MODE_NEAR, MODE_MID] else 0
	var ground_groups: int = ground_cover.get_grass_instances().size()
	var rock_groups: int = lab.get_rock_instances().size()
	var visible_ground_groups: int = ground_groups if ground_visible > 0 else 0
	var visible_rock_groups: int = rock_groups if rock_visible > 0 else 0
	var ph5_cost := int(perf.get("cost_units", 0))
	var ph5_draw_proxy := int(perf.get("draw_call_proxy", 0))
	var average_sec := _frame_total_sec / float(_frame_sample_count) if _frame_sample_count > 0 else 0.0
	var identity := _source_identity()
	_last_evidence = {
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
		"mode": current_mode,
		"observer_distance_m": _observer_distance_m(),
		"source_ecology_hash": String(identity.get("source_ecology_hash", "")),
		"macro_bridge_hash": String(identity.get("macro_bridge_hash", "")),
		"descriptor_adapter_hash": String(identity.get("descriptor_adapter_hash", "")),
		"ecology_identity_drift": ecology_identity_drift,
		"ph5_record_count": int(ph5.get("record_count", 0)),
		"ph5_visible_individual_count": int(ph5.get("visible_individual_count", 0)),
		"ph5_tier_counts": Dictionary(ph5.get("tier_counts", {})).duplicate(true),
		"ph5_cost_units": ph5_cost,
		"ph5_draw_call_proxy": ph5_draw_proxy,
		"ground_cover_total_instances": ground_total,
		"ground_cover_visible_instances": ground_visible,
		"ground_cover_group_count": ground_groups,
		"rock_total_instances": rock_total,
		"rock_visible_instances": rock_visible,
		"rock_group_count": rock_groups,
		"composition_cost_proxy": ph5_cost + ground_visible + rock_visible * 2,
		"composition_draw_call_proxy": ph5_draw_proxy + visible_ground_groups + visible_rock_groups,
		"workload_is_proxy": true,
		"observer_update_count": observer_update_count,
		"mode_switch_count": mode_switch_count,
		"render_origin_recenter_count": render_origin_recenter_count,
		"render_reprojection_count": render_reprojection_count,
		"local_surface_rebuild_count": local_surface_rebuild_count,
		"scenery_rebuild_count": scenery_rebuild_count,
		"region_roundtrip_count": region_roundtrip_count,
		"same_seed_roundtrip_verified": same_seed_roundtrip_verified,
		"last_recenter_identity_stable": last_recenter_identity_stable,
		"procedural_tree_placement_suppressed": _current_placement_suppressed(),
		"frame_sample_count": _frame_sample_count,
		"average_frame_ms": average_sec * 1000.0,
		"min_frame_ms": _frame_min_sec * 1000.0 if _frame_sample_count > 0 else 0.0,
		"max_frame_ms": _frame_max_sec * 1000.0,
		"estimated_fps": 1.0 / average_sec if average_sec > 0.0 else 0.0,
		"frame_diagnostics_observational_only": true,
	}
	_last_evidence["structural_evidence_hash"] = compute_structural_hash(_last_evidence)


func _apply_strata_visibility() -> void:
	var ground_visible := current_mode == MODE_NEAR
	var rocks_visible := current_mode in [MODE_NEAR, MODE_MID]
	_set_scenery_visible(ground_visible, rocks_visible)


func _set_scenery_visible(ground_visible: bool, rocks_visible: bool) -> void:
	ground_cover.apply_lod_flags({"ground_cover": ground_visible})
	for rock in lab.get_rock_instances():
		if rock != null and is_instance_valid(rock):
			rock.visible = rocks_visible


func _mode_for_distance(distance_m: float) -> String:
	if distance_m <= NEAR_MAX_DISTANCE_M:
		return MODE_NEAR
	if distance_m <= MID_MAX_DISTANCE_M:
		return MODE_MID
	if distance_m <= FAR_MAX_DISTANCE_M:
		return MODE_FAR
	return MODE_CULLED


func _observer_distance_m() -> float:
	return observer_world_position.distance_to(_patch_center_world())


func _patch_center_world() -> Vector3:
	if earth_world == null or presentation == null:
		return Vector3.ZERO
	return earth_world.get_surface_point(presentation.get_patch_center_direction())


func _source_identity() -> Dictionary:
	var composition: Dictionary = lab.get_summary()
	var morphology: Dictionary = lab.get_published_morphology_descriptors()
	return {
		"source_ecology_hash": String(composition.get("source_ecology_hash", "")),
		"macro_bridge_hash": String(composition.get("macro_bridge_hash", "")),
		"descriptor_adapter_hash": String(morphology.get("adapter_hash", "")),
	}


static func _same_source_identity(a: Dictionary, b: Dictionary) -> bool:
	return (
		String(a.get("source_ecology_hash", "")) == String(b.get("source_ecology_hash", ""))
		and String(a.get("macro_bridge_hash", "")) == String(b.get("macro_bridge_hash", ""))
		and String(a.get("descriptor_adapter_hash", "")) == String(b.get("descriptor_adapter_hash", ""))
	)


func _on_earth_rebuilt(_summary: Dictionary) -> void:
	local_surface_rebuild_count += 1


func _current_placement_suppressed() -> bool:
	if earth_world == null or earth_world.placement_system == null:
		return false
	var config: Dictionary = earth_world.placement_system.config
	return (
		not earth_world.placement_system.visible
		and int(config.get("max_near_trees", -1)) == 0
		and int(config.get("max_billboard_trees", -1)) == 0
		and int(config.get("max_grass_instances", -1)) == 0
		and int(config.get("max_rocks", -1)) == 0
	)


static func _placement_is_suppressed(rebuild_summary: Dictionary) -> bool:
	var placement_value = rebuild_summary.get("placement", {})
	if not placement_value is Dictionary:
		return false
	var placement: Dictionary = placement_value
	return (
		int(placement.get("near_trees", -1)) == 0
		and int(placement.get("billboard_trees", -1)) == 0
		and int(placement.get("grass", -1)) == 0
		and int(placement.get("rocks", -1)) == 0
	)


static func _finite_vec(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
