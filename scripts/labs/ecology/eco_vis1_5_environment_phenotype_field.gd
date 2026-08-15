extends "res://scripts/labs/ecology/eco_vis1_4_population_visual_field.gd"

const VIS15_PhenotypeBridge = preload("res://scripts/labs/ecology/eco_vis1_5_environment_phenotype_bridge.gd")

const VIS1_5_STAGE := "ECO.VIS1.5"
const VIS15_PHENOTYPE_MODE := "LOCAL_ENVIRONMENT_COUPLED_DEVELOPMENT"

var _vis15_genome: Dictionary = {}
var _vis15_traits: Dictionary = {}
var _vis15_field_hash := ""
var _vis15_phenotype_count := 0
var _vis15_unique_phenotype_hashes := {}
var _vis15_unique_environment_hashes := {}
var _vis15_population_summaries: Array[Dictionary] = []


func _ready() -> void:
	_vis15_genome = VIS15_PhenotypeBridge.create_baseline_genome()
	_vis15_traits = VIS15_PhenotypeBridge.create_baseline_traits()
	super._ready()
	_build_vis1_5_environment_phenotype_field()
	_set_default_world_view()
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title != null:
		title.text = "ECO.VIS1.5 — Environment-Coupled Phenotype Field"
	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset | F1 diagnostics | F2 discs | F3 links | F4 labels | F5 plants\nVIS1.5: every representative plant realizes phenotype from the actual local EnvironmentSample; shared lab baseline genome is presentation context, not canonical alpha/beta genome truth"
	_update_status()


func rebuild_spatial_projection() -> void:
	super.rebuild_spatial_projection()
	_build_vis1_5_environment_phenotype_field()
	_apply_visibility_state()
	_update_status()


func get_population_field_hash() -> String:
	return _vis15_field_hash


func get_ph5_projection_hash() -> String:
	return _vis15_field_hash


func get_ph5_materialization_summary() -> Dictionary:
	return get_population_field_summary()


func get_population_field_summary() -> Dictionary:
	var summary := super.get_population_field_summary()
	summary["stage"] = VIS1_5_STAGE
	summary["phenotype_mode"] = VIS15_PHENOTYPE_MODE
	summary["canned_exemplar_mapping"] = false
	summary["baseline_genome_id"] = String(_vis15_genome.get("genome_id", ""))
	summary["baseline_genome_checksum"] = String(_vis15_genome.get("checksum", ""))
	summary["baseline_traits_checksum"] = String(_vis15_traits.get("checksum", ""))
	summary["phenotype_instance_count"] = _vis15_phenotype_count
	summary["unique_phenotype_count"] = _vis15_unique_phenotype_hashes.size()
	summary["unique_environment_sample_count"] = _vis15_unique_environment_hashes.size()
	summary["projection_hash"] = _vis15_field_hash
	summary["populations"] = _vis15_population_summaries.duplicate(true)
	return summary


func _build_vis1_5_environment_phenotype_field() -> void:
	if is_instance_valid(_ph5_root):
		_ph5_root.free()
	_vis15_field_hash = ""
	_vis15_phenotype_count = 0
	_vis15_unique_phenotype_hashes.clear()
	_vis15_unique_environment_hashes.clear()
	_vis15_population_summaries.clear()
	_vis14_projection_hash = ""
	_vis14_instance_count = 0
	_vis14_represented_biomass_kg = 0.0
	_vis14_mid_proxy_count = 0
	_vis14_far_proxy_count = 0
	_vis14_population_summaries.clear()
	_ph5_projection_hash = ""
	_ph5_instance_count = 0
	_ph5_branch_vertex_count = 0
	_ph5_foliage_instance_count = 0
	_ph5_population_summaries.clear()

	var projection := get_node_or_null("SpatialEcologyProjection") as Node3D
	if projection == null or _spatial_snapshot.is_empty() or _ph5_profile.is_empty() or _vis15_genome.is_empty() or _vis15_traits.is_empty():
		return

	_ph5_root = Node3D.new()
	_ph5_root.name = "PH5PlantGeometry"
	projection.add_child(_ph5_root)
	var snapshot_hash := String(_spatial_snapshot.get("snapshot_hash", ""))
	var hash_tokens := PackedStringArray([
		VIS1_5_STAGE,
		snapshot_hash,
		String(_ph5_profile.get("profile_hash", "")),
		String(_vis15_genome.get("checksum", "")),
		String(_vis15_traits.get("checksum", "")),
		VIS15_PHENOTYPE_MODE,
		"kg_per_visual=%.9f" % REPRESENTED_KG_PER_VISUAL_INSTANCE,
	])

	for patch_variant in Array(_spatial_snapshot.get("patches", [])):
		if typeof(patch_variant) != TYPE_DICTIONARY:
			continue
		var patch: Dictionary = patch_variant
		var patch_id := String(patch.get("id", ""))
		var diagnostic_patch := projection.get_node_or_null("Patch_%s" % patch_id) as Node3D
		if diagnostic_patch == null:
			continue
		var ph5_patch_root := Node3D.new()
		ph5_patch_root.name = "Patch_%s" % patch_id
		ph5_patch_root.position = diagnostic_patch.position
		_ph5_root.add_child(ph5_patch_root)

		var population_index := 0
		for population_variant in Array(patch.get("plants", [])):
			if typeof(population_variant) != TYPE_DICTIONARY:
				continue
			var population: Dictionary = population_variant
			var population_id := String(population.get("id", ""))
			var biomass_kg := maxf(0.0, float(population.get("final_biomass_kg", 0.0)))
			if population_id.is_empty() or biomass_kg <= 0.000001:
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
			var phenotype_hashes := {}
			var environment_hashes := {}
			var height_sum := 0.0
			var crown_sum := 0.0
			var branch_probability_sum := 0.0
			for instance_index in range(visual_count):
				var represented_biomass := biomass_kg / float(visual_count)
				if instance_index == visual_count - 1:
					represented_biomass = biomass_kg - represented_sum
				represented_sum += represented_biomass

				var placement := _vis15_placement(
					patch_id,
					population_id,
					population_index,
					instance_index,
					represented_biomass,
					cluster_anchors,
					ph5_patch_root.position
				)
				var environment := sample_environment_at(float(placement["world_x"]), float(placement["world_z"]))
				var realized := VIS15_PhenotypeBridge.realize(
					_vis15_genome,
					_vis15_traits,
					environment,
					_ph5_profile,
					snapshot_hash,
					patch_id,
					population_id,
					instance_index
				)
				if realized.is_empty():
					continue
				var materialization: Dictionary = realized.get("materialization", {})
				var description: Dictionary = realized.get("render_description", {})
				var traits: Dictionary = realized.get("realized_traits", {})
				var response: Dictionary = realized.get("response", {})
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
				instance.position = Vector3(placement["local_position"])
				instance.rotation.y = float(placement["rotation_y"])
				instance.scale = Vector3.ONE * float(placement["scale_factor"])
				instance.set_meta("visual_representation_only", true)
				instance.set_meta("phenotype_environment_coupled", true)
				instance.set_meta("patch_id", patch_id)
				instance.set_meta("population_id", population_id)
				instance.set_meta("represented_biomass_kg", represented_biomass)
				instance.set_meta("genome_checksum", String(realized.get("genome_checksum", "")))
				instance.set_meta("environment_checksum", String(realized.get("environment_checksum", "")))
				instance.set_meta("phenotype_hash", String(realized.get("phenotype_hash", "")))
				instance.set_meta("bridge_hash", String(realized.get("bridge_hash", "")))
				instance.set_meta("soil_moisture", float(environment.get("soil_moisture", 0.0)))
				instance.set_meta("sunlight", float(environment.get("sunlight", 0.0)))
				instance.set_meta("nutrients", float(environment.get("nutrients", 0.0)))
				instance.set_meta("flood_frequency", float(environment.get("flood_frequency", 0.0)))
				instance.set_meta("realized_max_height_m", float(traits.get("max_height_m", 0.0)))
				instance.set_meta("realized_crown_spread_m", float(traits.get("crown_spread_m", 0.0)))
				instance.set_meta("realized_branch_probability", float(traits.get("branch_probability", 0.0)))
				instance.set_meta("drought_stress", float(response.get("drought_stress", 0.0)))
				instance.set_meta("flood_stress", float(response.get("flood_stress", 0.0)))
				_configure_near_lod(instance)
				_add_vis15_mid_canopy_proxy(instance, population_id, description, String(realized.get("phenotype_hash", "")))
				population_root.add_child(instance)

				var phenotype_hash := String(realized.get("phenotype_hash", ""))
				var environment_hash := String(realized.get("environment_checksum", ""))
				phenotype_hashes[phenotype_hash] = true
				environment_hashes[environment_hash] = true
				_vis15_unique_phenotype_hashes[phenotype_hash] = true
				_vis15_unique_environment_hashes[environment_hash] = true
				_vis15_phenotype_count += 1
				_vis14_instance_count += 1
				_vis14_represented_biomass_kg += represented_biomass
				_ph5_instance_count += 1
				_ph5_branch_vertex_count += int(materialization.get("branch_vertex_count", 0))
				_ph5_foliage_instance_count += int(materialization.get("foliage_instance_count", 0))
				height_sum += float(traits.get("max_height_m", 0.0))
				crown_sum += float(traits.get("crown_spread_m", 0.0))
				branch_probability_sum += float(traits.get("branch_probability", 0.0))
				hash_tokens.append("I|%s|represented=%.9f|bridge=%s" % [
					_instance_hash_token(patch_id, population_id, instance_index, instance),
					represented_biomass,
					String(realized.get("bridge_hash", "")),
				])

			var realized_count := phenotype_hashes.size()
			var divisor := maxf(1.0, float(visual_count))
			var population_summary := {
				"patch_id": patch_id,
				"population_id": population_id,
				"source_biomass_kg": biomass_kg,
				"represented_biomass_kg": represented_sum,
				"visual_count": visual_count,
				"phenotype_count": realized_count,
				"environment_sample_count": environment_hashes.size(),
				"cluster_count": cluster_count,
				"phenotype_source": VIS15_PHENOTYPE_MODE,
				"baseline_genome_id": String(_vis15_genome.get("genome_id", "")),
				"mean_max_height_m": height_sum / divisor,
				"mean_crown_spread_m": crown_sum / divisor,
				"mean_branch_probability": branch_probability_sum / divisor,
			}
			_vis15_population_summaries.append(population_summary)
			_vis14_population_summaries.append(population_summary.duplicate(true))
			_ph5_population_summaries.append(population_summary.duplicate(true))
			hash_tokens.append("POP|%s|%s|%.9f|%.9f|%d|%d|%d" % [
				patch_id,
				population_id,
				biomass_kg,
				represented_sum,
				visual_count,
				realized_count,
				environment_hashes.size(),
			])
			population_index += 1

	_vis15_field_hash = "\n".join(hash_tokens).sha256_text()
	_vis14_projection_hash = _vis15_field_hash
	_ph5_projection_hash = _vis15_field_hash


func _vis15_placement(
	patch_id: String,
	population_id: String,
	population_index: int,
	instance_index: int,
	represented_biomass_kg: float,
	cluster_anchors: Array[Vector2],
	patch_center: Vector3
) -> Dictionary:
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
	var base_scale := VIS14_PLANT_SCALE_MIN + sqrt(maxf(represented_biomass_kg, 0.001)) * 1.05
	var variation := lerpf(0.86, 1.16, _unit(key + "/scale"))
	var scale_factor := clampf(base_scale * variation, VIS14_PLANT_SCALE_MIN, VIS14_PLANT_SCALE_MAX)
	return {
		"local_position": Vector3(local_xz.x, local_ground + 0.24, local_xz.y),
		"world_x": world_x,
		"world_z": world_z,
		"rotation_y": TAU * _unit(key + "/yaw"),
		"scale_factor": scale_factor,
	}


func _add_vis15_mid_canopy_proxy(instance: Node3D, population_id: String, description: Dictionary, phenotype_hash: String) -> void:
	var canopy: Dictionary = description.get("canopy", {})
	var center_values: Array = canopy.get("center", [0.0, 2.0, 0.0])
	var radius := maxf(0.25, float(canopy.get("radius_xz_m", 1.0)))
	var canopy_height := maxf(0.25, float(canopy.get("height_m", 1.5)))
	var proxy := MeshInstance3D.new()
	proxy.name = "MidCanopy"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 5
	proxy.mesh = sphere
	proxy.position = Vector3(float(center_values[0]), float(center_values[1]), float(center_values[2]))
	proxy.scale = Vector3(radius, canopy_height * 0.5, radius)
	proxy.material_override = _lod_proxy_material(population_id, 0.82)
	proxy.visibility_range_begin = MID_LOD_BEGIN_M
	proxy.visibility_range_begin_margin = 15.0
	proxy.visibility_range_end = MID_LOD_END_M
	proxy.visibility_range_end_margin = 25.0
	proxy.set_meta("derived_lod_proxy", "MID_CANOPY_PHENOTYPE")
	proxy.set_meta("phenotype_hash", phenotype_hash)
	instance.add_child(proxy)
	_vis14_mid_proxy_count += 1


func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	status.text = status.text.replace("presentation exemplars alpha=SUN beta=SHADE", "phenotype_source=LOCAL_ENVIRONMENT")
	status.text = status.text.replace("VIS1.4=ACTIVE", "VIS1.4_LOD=ACTIVE")
	var hash_preview := _vis15_field_hash.substr(0, 12) if _vis15_field_hash.length() == 64 else "pending"
	status.text += "\nVIS1.5=ACTIVE env_coupled=%d/%d | unique_phenotypes=%d env_samples=%d | field=%s | lab_genome=%s | canned_exemplars=OFF" % [
		_vis15_phenotype_count,
		_vis14_instance_count,
		_vis15_unique_phenotype_hashes.size(),
		_vis15_unique_environment_hashes.size(),
		hash_preview,
		String(_vis15_genome.get("genome_id", "pending")),
	]
	var nearest := _nearest_vis15_plant()
	if not nearest.is_empty():
		status.text += "\nNearest phenotype: %s/%s d=%.1fm | moisture=%.3f light=%.3f nutrients=%.3f flood=%.3f | height=%.2fm crown=%.2fm branch=%.3f | phenotype=%s" % [
			String(nearest.get("patch_id", "?")),
			String(nearest.get("population_id", "?")),
			float(nearest.get("distance_m", 0.0)),
			float(nearest.get("soil_moisture", 0.0)),
			float(nearest.get("sunlight", 0.0)),
			float(nearest.get("nutrients", 0.0)),
			float(nearest.get("flood_frequency", 0.0)),
			float(nearest.get("realized_max_height_m", 0.0)),
			float(nearest.get("realized_crown_spread_m", 0.0)),
			float(nearest.get("realized_branch_probability", 0.0)),
			String(nearest.get("phenotype_hash", "")).substr(0, 12),
		]


func _nearest_vis15_plant() -> Dictionary:
	if not is_instance_valid(_camera) or not is_instance_valid(_ph5_root):
		return {}
	var best := {}
	var best_distance := INF
	for patch_root in _ph5_root.get_children():
		for population_root in patch_root.get_children():
			for child in population_root.get_children():
				if not child is Node3D or not String(child.name).begins_with("Plant_"):
					continue
				var plant := child as Node3D
				if not bool(plant.get_meta("phenotype_environment_coupled", false)):
					continue
				var distance := _camera.global_position.distance_to(plant.global_position)
				if distance >= best_distance:
					continue
				best_distance = distance
				best = {
					"distance_m": distance,
					"patch_id": plant.get_meta("patch_id", ""),
					"population_id": plant.get_meta("population_id", ""),
					"soil_moisture": plant.get_meta("soil_moisture", 0.0),
					"sunlight": plant.get_meta("sunlight", 0.0),
					"nutrients": plant.get_meta("nutrients", 0.0),
					"flood_frequency": plant.get_meta("flood_frequency", 0.0),
					"realized_max_height_m": plant.get_meta("realized_max_height_m", 0.0),
					"realized_crown_spread_m": plant.get_meta("realized_crown_spread_m", 0.0),
					"realized_branch_probability": plant.get_meta("realized_branch_probability", 0.0),
					"phenotype_hash": plant.get_meta("phenotype_hash", ""),
				}
	return best
