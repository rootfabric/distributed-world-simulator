extends "res://scripts/labs/ecology/eco_vis1_3_ph5_population_materialization.gd"

const VIS1_4_STAGE := "ECO.VIS1.4"
const REPRESENTED_KG_PER_VISUAL_INSTANCE := 0.22
const VIS14_MAX_VISUAL_INSTANCES_PER_POPULATION := 24
const PATCH_FIELD_RADIUS_M := 21.5
const CLUSTER_RADIUS_M := 5.5
const VIS14_PLANT_SCALE_MIN := 1.85
const VIS14_PLANT_SCALE_MAX := 2.80
const NEAR_LOD_END_M := 110.0
const MID_LOD_BEGIN_M := 75.0
const MID_LOD_END_M := 240.0
const FAR_LOD_BEGIN_M := 190.0

var _vis14_projection_hash := ""
var _vis14_instance_count := 0
var _vis14_represented_biomass_kg := 0.0
var _vis14_mid_proxy_count := 0
var _vis14_far_proxy_count := 0
var _vis14_population_summaries: Array[Dictionary] = []
var _patch_discs_visible := false
var _dispersal_links_visible := false
var _patch_labels_visible := false
var _plants_visible := true


func _ready() -> void:
	super._ready()
	_build_vis1_4_population_field()
	_set_default_world_view()
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title != null:
		title.text = "ECO.VIS1.4 — Readable Population Visual Field"
	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset | F1 diagnostics | F2 discs | F3 links | F4 labels | F5 plants\nRepresentative plants preserve source biomass through represented_biomass_kg; near PH5 + mid/far derived LOD proxies"
	_update_status()


func rebuild_spatial_projection() -> void:
	super.rebuild_spatial_projection()
	_build_vis1_4_population_field()
	_apply_visibility_state()
	_update_status()


func get_population_field_hash() -> String:
	return _vis14_projection_hash


func get_ph5_projection_hash() -> String:
	return _vis14_projection_hash


func get_ph5_materialization_summary() -> Dictionary:
	return get_population_field_summary()


func get_population_field_summary() -> Dictionary:
	return {
		"stage": VIS1_4_STAGE,
		"profile_id": String(_ph5_profile.get("profile_id", "")),
		"profile_hash": String(_ph5_profile.get("profile_hash", "")),
		"source_snapshot_hash": String(_spatial_snapshot.get("snapshot_hash", "")),
		"projection_hash": _vis14_projection_hash,
		"visual_instance_count": _vis14_instance_count,
		"branch_vertex_count": _ph5_branch_vertex_count,
		"foliage_instance_count": _ph5_foliage_instance_count,
		"represented_biomass_kg": _vis14_represented_biomass_kg,
		"source_biomass_kg": float(_spatial_snapshot.get("total_final_biomass_kg", 0.0)),
		"mid_proxy_count": _vis14_mid_proxy_count,
		"far_proxy_count": _vis14_far_proxy_count,
		"populations": _vis14_population_summaries.duplicate(true),
		"visibility": get_visual_visibility_state(),
	}


func get_visual_visibility_state() -> Dictionary:
	return {
		"patch_discs": _patch_discs_visible,
		"dispersal_links": _dispersal_links_visible,
		"patch_labels": _patch_labels_visible,
		"plants": _plants_visible,
	}


func set_diagnostics_visible(enabled: bool) -> void:
	_patch_discs_visible = enabled
	_dispersal_links_visible = enabled
	_patch_labels_visible = enabled
	_apply_visibility_state()
	_update_status()


func set_plants_visible(enabled: bool) -> void:
	_plants_visible = enabled
	_apply_visibility_state()
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_F1:
					set_diagnostics_visible(not (_patch_discs_visible or _dispersal_links_visible or _patch_labels_visible))
					get_viewport().set_input_as_handled()
					return
				KEY_F2:
					_patch_discs_visible = not _patch_discs_visible
					_apply_visibility_state()
					_update_status()
					get_viewport().set_input_as_handled()
					return
				KEY_F3:
					_dispersal_links_visible = not _dispersal_links_visible
					_apply_visibility_state()
					_update_status()
					get_viewport().set_input_as_handled()
					return
				KEY_F4:
					_patch_labels_visible = not _patch_labels_visible
					_apply_visibility_state()
					_update_status()
					get_viewport().set_input_as_handled()
					return
				KEY_F5:
					set_plants_visible(not _plants_visible)
					get_viewport().set_input_as_handled()
					return
	super._unhandled_input(event)


func _set_default_world_view() -> void:
	_patch_discs_visible = false
	_dispersal_links_visible = false
	_patch_labels_visible = false
	_plants_visible = true
	_apply_visibility_state()


func _apply_visibility_state() -> void:
	var projection := get_node_or_null("SpatialEcologyProjection") as Node3D
	if projection == null:
		return
	var links := projection.get_node_or_null("DispersalLinks") as Node3D
	if links != null:
		links.visible = _dispersal_links_visible
	for patch_variant in Array(_spatial_snapshot.get("patches", [])):
		if typeof(patch_variant) != TYPE_DICTIONARY:
			continue
		var patch_id := String(Dictionary(patch_variant).get("id", ""))
		var patch_root := projection.get_node_or_null("Patch_%s" % patch_id) as Node3D
		if patch_root == null:
			continue
		var disc := patch_root.get_node_or_null("PatchDisc") as Node3D
		if disc != null:
			disc.visible = _patch_discs_visible
		var label := patch_root.get_node_or_null("PatchLabel") as Node3D
		if label != null:
			label.visible = _patch_labels_visible
	if is_instance_valid(_ph5_root):
		_ph5_root.visible = _plants_visible


func _build_vis1_4_population_field() -> void:
	if is_instance_valid(_ph5_root):
		_ph5_root.free()
	_vis14_projection_hash = ""
	_vis14_instance_count = 0
	_vis14_represented_biomass_kg = 0.0
	_vis14_mid_proxy_count = 0
	_vis14_far_proxy_count = 0
	_vis14_population_summaries.clear()
	_ph5_instance_count = 0
	_ph5_branch_vertex_count = 0
	_ph5_foliage_instance_count = 0
	_ph5_population_summaries.clear()

	var projection := get_node_or_null("SpatialEcologyProjection") as Node3D
	if projection == null or _spatial_snapshot.is_empty() or _ph5_probe_results.is_empty() or _ph5_profile.is_empty():
		return

	_ph5_root = Node3D.new()
	_ph5_root.name = "PH5PlantGeometry"
	projection.add_child(_ph5_root)

	var hash_tokens := PackedStringArray([
		VIS1_4_STAGE,
		String(_spatial_snapshot.get("snapshot_hash", "")),
		String(_ph5_profile.get("profile_hash", "")),
		"kg_per_visual=%.9f" % REPRESENTED_KG_PER_VISUAL_INSTANCE,
		"field_radius=%.9f" % PATCH_FIELD_RADIUS_M,
		"cluster_radius=%.9f" % CLUSTER_RADIUS_M,
	])

	for patch_variant in Array(_spatial_snapshot.get("patches", [])):
		if typeof(patch_variant) != TYPE_DICTIONARY:
			continue
		var patch: Dictionary = patch_variant
		var patch_id := String(patch.get("id", ""))
		var patch_root := projection.get_node_or_null("Patch_%s" % patch_id) as Node3D
		if patch_root == null:
			continue
		var ph5_patch_root := Node3D.new()
		ph5_patch_root.name = "Patch_%s" % patch_id
		ph5_patch_root.position = patch_root.position
		_ph5_root.add_child(ph5_patch_root)
		var population_index := 0
		for plant_variant in Array(patch.get("plants", [])):
			if typeof(plant_variant) != TYPE_DICTIONARY:
				continue
			var population: Dictionary = plant_variant
			var population_id := String(population.get("id", ""))
			var biomass_kg := maxf(0.0, float(population.get("final_biomass_kg", 0.0)))
			if population_id.is_empty() or biomass_kg <= 0.000001:
				continue
			var exemplar_id := String(EXEMPLAR_BY_POPULATION.get(population_id, "REFERENCE"))
			if not _ph5_probe_results.has(exemplar_id):
				exemplar_id = "REFERENCE"
			var probe: Dictionary = _ph5_probe_results.get(exemplar_id, {})
			var description: Dictionary = probe.get("render_description", {})
			var materialization := Materializer3D.build(description, _ph5_profile)
			if materialization.is_empty():
				continue
			var visual_count := clampi(
				int(ceil(biomass_kg / REPRESENTED_KG_PER_VISUAL_INSTANCE)),
				1,
				VIS14_MAX_VISUAL_INSTANCES_PER_POPULATION
			)
			var cluster_count := clampi(int(ceil(sqrt(float(visual_count)) / 1.7)), 1, 3)
			var cluster_anchors := _cluster_anchors(patch_id, population_id, population_index, cluster_count)
			var population_root := Node3D.new()
			population_root.name = "PH5Population_%s" % population_id
			ph5_patch_root.add_child(population_root)
			_add_far_population_proxies(population_root, patch_id, population_id, biomass_kg, cluster_anchors, ph5_patch_root.position)
			var represented_sum := 0.0
			var geometry_hash := String(materialization.get("geometry_hash", ""))
			for instance_index in range(visual_count):
				var represented_biomass := biomass_kg / float(visual_count)
				if instance_index == visual_count - 1:
					represented_biomass = biomass_kg - represented_sum
				represented_sum += represented_biomass
				var instance := _create_ph5_plant_instance(
					patch_id,
					population_id,
					population_index,
					instance_index,
					visual_count,
					biomass_kg,
					materialization,
					ph5_patch_root.position
				)
				_apply_clustered_transform(instance, patch_id, population_id, population_index, instance_index, represented_biomass, cluster_anchors, ph5_patch_root.position)
				instance.set_meta("visual_representation_only", true)
				instance.set_meta("patch_id", patch_id)
				instance.set_meta("population_id", population_id)
				instance.set_meta("represented_biomass_kg", represented_biomass)
				_configure_near_lod(instance)
				_add_mid_canopy_proxy(instance, population_id)
				population_root.add_child(instance)
				_vis14_instance_count += 1
				_vis14_represented_biomass_kg += represented_biomass
				_ph5_instance_count += 1
				_ph5_branch_vertex_count += int(materialization.get("branch_vertex_count", 0))
				_ph5_foliage_instance_count += int(materialization.get("foliage_instance_count", 0))
				hash_tokens.append("%s|represented=%.9f" % [_instance_hash_token(patch_id, population_id, instance_index, instance), represented_biomass])
			var population_summary := {
				"patch_id": patch_id,
				"population_id": population_id,
				"source_biomass_kg": biomass_kg,
				"represented_biomass_kg": represented_sum,
				"visual_count": visual_count,
				"cluster_count": cluster_count,
				"exemplar_id": exemplar_id,
				"geometry_hash": geometry_hash,
			}
			_vis14_population_summaries.append(population_summary)
			_ph5_population_summaries.append(population_summary.duplicate(true))
			hash_tokens.append("POP|%s|%s|%.9f|%.9f|%d|%d|%s|%s" % [
				patch_id,
				population_id,
				biomass_kg,
				represented_sum,
				visual_count,
				cluster_count,
				exemplar_id,
				geometry_hash,
			])
			population_index += 1

	_vis14_projection_hash = "\n".join(hash_tokens).sha256_text()
	_ph5_projection_hash = _vis14_projection_hash


func _cluster_anchors(patch_id: String, population_id: String, population_index: int, cluster_count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for cluster_index in range(cluster_count):
		var key := "%s/%s/%d/cluster/%d" % [patch_id, population_id, population_index, cluster_index]
		var angle := TAU * _unit(key + "/angle") + float(population_index) * 1.35
		var radius := lerpf(4.0, 12.5 + float(population_index) * 1.5, sqrt(_unit(key + "/radius")))
		result.append(Vector2(cos(angle), sin(angle)) * radius)
	return result


func _apply_clustered_transform(
	instance: Node3D,
	patch_id: String,
	population_id: String,
	population_index: int,
	instance_index: int,
	represented_biomass_kg: float,
	cluster_anchors: Array[Vector2],
	patch_center: Vector3
) -> void:
	var cluster_index := instance_index % cluster_anchors.size()
	var anchor := cluster_anchors[cluster_index]
	var key := "%s/%s/%d/%d/field" % [patch_id, population_id, population_index, instance_index]
	var jitter_angle := TAU * _unit(key + "/angle")
	var jitter_radius := lerpf(0.7, CLUSTER_RADIUS_M, sqrt(_unit(key + "/radius")))
	var local_xz := anchor + Vector2(cos(jitter_angle), sin(jitter_angle)) * jitter_radius
	if local_xz.length() > PATCH_FIELD_RADIUS_M:
		local_xz = local_xz.normalized() * PATCH_FIELD_RADIUS_M
	var world_x := patch_center.x + local_xz.x
	var world_z := patch_center.z + local_xz.y
	var local_ground := sample_terrain_height(world_x, world_z) - patch_center.y
	instance.position = Vector3(local_xz.x, local_ground + 0.24, local_xz.y)
	instance.rotation.y = TAU * _unit(key + "/yaw")
	var base_scale := VIS14_PLANT_SCALE_MIN + sqrt(maxf(represented_biomass_kg, 0.001)) * 1.05
	var variation := lerpf(0.86, 1.16, _unit(key + "/scale"))
	var scale_factor := clampf(base_scale * variation, VIS14_PLANT_SCALE_MIN, VIS14_PLANT_SCALE_MAX)
	instance.scale = Vector3.ONE * scale_factor


func _configure_near_lod(instance: Node3D) -> void:
	for child_name in ["Branches", "Foliage"]:
		var geometry := instance.get_node_or_null(child_name) as GeometryInstance3D
		if geometry == null:
			continue
		geometry.visibility_range_end = NEAR_LOD_END_M
		geometry.visibility_range_end_margin = 18.0


func _add_mid_canopy_proxy(instance: Node3D, population_id: String) -> void:
	var proxy := MeshInstance3D.new()
	proxy.name = "MidCanopy"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.4
	sphere.radial_segments = 8
	sphere.rings = 5
	proxy.mesh = sphere
	proxy.position = Vector3(0.0, 2.25, 0.0)
	proxy.scale = Vector3(1.25, 0.92, 1.25)
	proxy.material_override = _lod_proxy_material(population_id, 0.82)
	proxy.visibility_range_begin = MID_LOD_BEGIN_M
	proxy.visibility_range_begin_margin = 15.0
	proxy.visibility_range_end = MID_LOD_END_M
	proxy.visibility_range_end_margin = 25.0
	proxy.set_meta("derived_lod_proxy", "MID_CANOPY")
	instance.add_child(proxy)
	_vis14_mid_proxy_count += 1


func _add_far_population_proxies(
	population_root: Node3D,
	patch_id: String,
	population_id: String,
	biomass_kg: float,
	cluster_anchors: Array[Vector2],
	patch_center: Vector3
) -> void:
	for cluster_index in range(cluster_anchors.size()):
		var anchor := cluster_anchors[cluster_index]
		var world_x := patch_center.x + anchor.x
		var world_z := patch_center.z + anchor.y
		var local_ground := sample_terrain_height(world_x, world_z) - patch_center.y
		var cluster_biomass := biomass_kg / float(cluster_anchors.size())
		var radius := clampf(2.8 + sqrt(cluster_biomass) * 1.45, 3.0, 6.2)
		var proxy := MeshInstance3D.new()
		proxy.name = "FarCanopy_%02d" % cluster_index
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		proxy.mesh = sphere
		proxy.position = Vector3(anchor.x, local_ground + radius * 0.72, anchor.y)
		proxy.scale = Vector3(1.25, 0.62, 1.25)
		proxy.material_override = _lod_proxy_material(population_id, 0.58)
		proxy.visibility_range_begin = FAR_LOD_BEGIN_M
		proxy.visibility_range_begin_margin = 30.0
		proxy.set_meta("derived_lod_proxy", "FAR_POPULATION_CANOPY")
		proxy.set_meta("patch_id", patch_id)
		proxy.set_meta("population_id", population_id)
		proxy.set_meta("represented_biomass_kg", cluster_biomass)
		population_root.add_child(proxy)
		_vis14_far_proxy_count += 1


func _lod_proxy_material(population_id: String, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.72, 0.30, alpha) if population_id == "alpha" else Color(0.14, 0.50, 0.27, alpha)
	material.roughness = 0.94
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	var source_biomass := float(_spatial_snapshot.get("total_final_biomass_kg", 0.0))
	var conservation := "MATCH" if absf(_vis14_represented_biomass_kg - source_biomass) <= 0.000000001 else "MISMATCH"
	var hash_preview := _vis14_projection_hash.substr(0, 12) if _vis14_projection_hash.length() == 64 else "pending"
	status.text += "\nVIS1.4=ACTIVE representative_plants=%d | represented=%.3fkg source=%.3fkg %s | mid=%d far=%d | field=%s | view plants=%s discs=%s links=%s labels=%s" % [
		_vis14_instance_count,
		_vis14_represented_biomass_kg,
		source_biomass,
		conservation,
		_vis14_mid_proxy_count,
		_vis14_far_proxy_count,
		hash_preview,
		"ON" if _plants_visible else "OFF",
		"ON" if _patch_discs_visible else "OFF",
		"ON" if _dispersal_links_visible else "OFF",
		"ON" if _patch_labels_visible else "OFF",
	]
