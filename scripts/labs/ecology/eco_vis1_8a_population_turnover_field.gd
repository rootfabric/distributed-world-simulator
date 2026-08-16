extends "res://scripts/labs/ecology/eco_vis1_7_temporal_evolution_field.gd"

const VIS18_TurnoverBridge = preload("res://scripts/labs/ecology/eco_vis1_8a_turnover_bridge.gd")
const VIS18_TimelineBridge = preload("res://scripts/labs/ecology/eco_vis1_7_temporal_evolution_bridge.gd")

const VIS1_8A_STAGE := "ECO.VIS1.8A"
const VIS18_TURNOVER_MODE := "LAB_DERIVED_FITNESS_TURNOVER_RECRUITMENT"

var _vis18_founders_by_population := {}
var _vis18_generation_cache := {}
var _vis18_max_cached_generation := 0
var _vis18_field_hash := ""
var _vis18_turnover_hash := ""
var _vis18_founder_count := 0
var _vis18_current_births := 0
var _vis18_current_deaths := 0
var _vis18_current_survivors := 0
var _vis18_cumulative_births := 0
var _vis18_cumulative_deaths := 0
var _vis18_current_visual_count := 0
var _vis18_unique_stable_ids := {}


func _ready() -> void:
	super._ready()
	_vis17_playing = false
	_vis17_generation = 0
	_apply_vis1_7_generation(0)
	_capture_vis18_founders()
	_apply_vis1_8a_generation(0)
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title != null:
		title.text = "ECO.VIS1.8A — Population Turnover Field — PAUSE G0"
	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset | Left/Right generation | Space play/pause | R generation 0 | F1-F5 diagnostics\nVIS1.8A: fitness-ranked survival + genetic recruitment changes representative count and placement; represented biomass stays equal to the read-only VIS1.2 source snapshot"
	_update_status()


func set_evolution_generation(generation: int) -> void:
	var clamped := clampi(generation, 0, VIS18_TimelineBridge.MAX_GENERATION)
	if clamped == _vis17_generation and _vis18_field_hash.length() == 64:
		_update_status()
		return
	_vis17_generation = clamped
	_vis17_play_accumulator = 0.0
	_apply_vis1_8a_generation(clamped)
	_update_status()


func get_evolution_state() -> Dictionary:
	var state := super.get_evolution_state()
	state["stage"] = VIS1_8A_STAGE
	state["mode"] = VIS18_TURNOVER_MODE
	state["generation"] = _vis17_generation
	state["field_hash"] = _vis18_field_hash
	state["turnover_hash"] = _vis18_turnover_hash
	state["founder_count"] = _vis18_founder_count
	state["visual_count"] = _vis18_current_visual_count
	state["birth_count"] = _vis18_current_births
	state["death_count"] = _vis18_current_deaths
	state["survivor_count"] = _vis18_current_survivors
	state["cumulative_births"] = _vis18_cumulative_births
	state["cumulative_deaths"] = _vis18_cumulative_deaths
	state["canonical_population_truth"] = false
	state["canonical_timeline_truth"] = false
	return state


func get_turnover_state() -> Dictionary:
	return get_evolution_state()


func get_population_field_hash() -> String:
	return _vis18_field_hash


func get_ph5_projection_hash() -> String:
	return _vis18_field_hash


func get_population_field_summary() -> Dictionary:
	var summary := super.get_population_field_summary()
	summary["stage"] = VIS1_8A_STAGE
	summary["turnover_mode"] = VIS18_TURNOVER_MODE
	summary["current_generation"] = _vis17_generation
	summary["founder_count"] = _vis18_founder_count
	summary["visual_instance_count"] = _vis18_current_visual_count
	summary["birth_count"] = _vis18_current_births
	summary["death_count"] = _vis18_current_deaths
	summary["survivor_count"] = _vis18_current_survivors
	summary["cumulative_births"] = _vis18_cumulative_births
	summary["cumulative_deaths"] = _vis18_cumulative_deaths
	summary["unique_stable_id_count"] = _vis18_unique_stable_ids.size()
	summary["turnover_hash"] = _vis18_turnover_hash
	summary["projection_hash"] = _vis18_field_hash
	summary["canonical_population_truth"] = false
	summary["canonical_timeline_truth"] = false
	return summary


func _capture_vis18_founders() -> void:
	_vis18_founders_by_population.clear()
	_vis18_generation_cache.clear()
	_vis18_max_cached_generation = 0
	_vis18_founder_count = 0
	if not is_instance_valid(_ph5_root) or _spatial_snapshot.is_empty() or _ph5_profile.is_empty():
		return
	var snapshot_hash := String(_spatial_snapshot.get("snapshot_hash", ""))
	var generation_zero := {}
	for patch_variant in Array(_spatial_snapshot.get("patches", [])):
		if typeof(patch_variant) != TYPE_DICTIONARY:
			continue
		var patch: Dictionary = patch_variant
		var patch_id := String(patch.get("id", ""))
		var patch_root := _ph5_root.get_node_or_null("Patch_%s" % patch_id) as Node3D
		if patch_root == null:
			continue
		var patch_center := Vector2(patch_root.global_position.x, patch_root.global_position.z)
		for population_variant in Array(patch.get("plants", [])):
			if typeof(population_variant) != TYPE_DICTIONARY:
				continue
			var population: Dictionary = population_variant
			var population_id := String(population.get("id", ""))
			var source_biomass := maxf(0.0, float(population.get("final_biomass_kg", 0.0)))
			var population_root := patch_root.get_node_or_null("PH5Population_%s" % population_id) as Node3D
			if population_root == null or population_id.is_empty() or source_biomass <= 0.000001:
				continue
			var founders: Array[Dictionary] = []
			for child in population_root.get_children():
				if not child is Node3D or not String(child.name).begins_with("Plant_"):
					continue
				var plant := child as Node3D
				var founder_index := String(plant.name).trim_prefix("Plant_").to_int()
				var environment := sample_environment_at(plant.global_position.x, plant.global_position.z)
				var realized := VIS18_TimelineBridge.realize_at_generation(
					environment,
					_ph5_profile,
					snapshot_hash,
					patch_id,
					population_id,
					founder_index,
					0
				)
				if realized.is_empty():
					continue
				var stable_id := "vis18/%s/%s/founder/%03d" % [patch_id, population_id, founder_index]
				var founder := VIS18_TurnoverBridge.create_founder_record(
					stable_id,
					patch_id,
					population_id,
					founder_index,
					plant.global_position.x,
					plant.global_position.z,
					plant.rotation.y,
					Dictionary(realized.get("genome", {})),
					Dictionary(realized.get("lineage", {})),
					float(plant.get_meta("represented_biomass_kg", 0.0)),
					float(realized.get("final_fitness", 0.0))
				)
				if not founder.is_empty():
					founders.append(founder)
			var key := _vis18_population_key(patch_id, population_id)
			var transition := {
				"generation": 0,
				"patch_id": patch_id,
				"population_id": population_id,
				"base_count": founders.size(),
				"previous_count": founders.size(),
				"target_count": founders.size(),
				"survivor_count": founders.size(),
				"birth_count": 0,
				"death_count": 0,
				"mean_parent_fitness": _vis18_mean_record_fitness(founders),
				"selected_birth_mutation_count": 0,
				"source_biomass_kg": source_biomass,
				"represented_biomass_kg": source_biomass,
				"records": founders.duplicate(true),
				"births": [],
				"deaths": [],
				"turnover_hash": _vis18_founder_hash(snapshot_hash, patch_id, population_id, founders),
			}
			var state := {
				"patch_id": patch_id,
				"population_id": population_id,
				"base_count": founders.size(),
				"source_biomass_kg": source_biomass,
				"patch_center": patch_center,
				"records": founders.duplicate(true),
				"transition": transition,
			}
			_vis18_founders_by_population[key] = state.duplicate(true)
			generation_zero[key] = state.duplicate(true)
			_vis18_founder_count += founders.size()
	_vis18_generation_cache[0] = generation_zero


func _ensure_vis18_generation(generation: int) -> void:
	if generation <= _vis18_max_cached_generation:
		return
	var snapshot_hash := String(_spatial_snapshot.get("snapshot_hash", ""))
	for next_generation in range(_vis18_max_cached_generation + 1, generation + 1):
		var previous_map: Dictionary = _vis18_generation_cache.get(next_generation - 1, {})
		var next_map := {}
		var keys := previous_map.keys()
		keys.sort()
		for key_variant in keys:
			var key := String(key_variant)
			var previous_state: Dictionary = previous_map[key_variant]
			var evaluated_records := _vis18_evaluate_records(Array(previous_state.get("records", [])))
			var previous_patch_center: Vector2 = previous_state.get("patch_center", Vector2.ZERO)
			var advanced := VIS18_TurnoverBridge.advance_population(
				evaluated_records,
				int(previous_state.get("base_count", 0)),
				float(previous_state.get("source_biomass_kg", 0.0)),
				next_generation,
				snapshot_hash,
				String(previous_state.get("patch_id", "")),
				String(previous_state.get("population_id", "")),
				previous_patch_center
			)
			if advanced.is_empty():
				continue
			next_map[key] = {
				"patch_id": String(previous_state.get("patch_id", "")),
				"population_id": String(previous_state.get("population_id", "")),
				"base_count": int(previous_state.get("base_count", 0)),
				"source_biomass_kg": float(previous_state.get("source_biomass_kg", 0.0)),
				"patch_center": Vector2(previous_state.get("patch_center", Vector2.ZERO)),
				"records": Array(advanced.get("records", [])).duplicate(true),
				"transition": advanced.duplicate(true),
			}
		_vis18_generation_cache[next_generation] = next_map
		_vis18_max_cached_generation = next_generation


func _vis18_evaluate_records(records: Array) -> Array[Dictionary]:
	var evaluated: Array[Dictionary] = []
	for record_variant in records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = Dictionary(record_variant).duplicate(true)
		var environment := sample_environment_at(float(record.get("world_x", 0.0)), float(record.get("world_z", 0.0)))
		record["current_fitness"] = VIS18_TurnoverBridge.evaluate_fitness(Dictionary(record.get("genome", {})), environment)
		evaluated.append(record)
	return evaluated


func _apply_vis1_8a_generation(generation: int) -> void:
	_ensure_vis18_generation(generation)
	var generation_map: Dictionary = _vis18_generation_cache.get(generation, {})
	if generation_map.is_empty():
		return
	var projection := get_node_or_null("SpatialEcologyProjection") as Node3D
	if projection == null:
		return
	if is_instance_valid(_ph5_root):
		_ph5_root.free()
	var old_events := projection.get_node_or_null("VIS18TurnoverEvents")
	if old_events != null:
		old_events.free()

	_ph5_root = Node3D.new()
	_ph5_root.name = "PH5PlantGeometry"
	projection.add_child(_ph5_root)

	_vis18_field_hash = ""
	_vis18_turnover_hash = ""
	_vis18_current_births = 0
	_vis18_current_deaths = 0
	_vis18_current_survivors = 0
	_vis18_cumulative_births = 0
	_vis18_cumulative_deaths = 0
	_vis18_current_visual_count = 0
	_vis18_unique_stable_ids.clear()
	_vis17_field_hash = ""
	_vis17_trajectory_hashes.clear()
	_vis17_final_fitness_sum = 0.0
	_vis16_lineage_count = 0
	_vis16_unique_lineages.clear()
	_vis16_unique_genomes.clear()
	_vis16_alpha_genomes.clear()
	_vis16_beta_genomes.clear()
	_vis16_population_summaries.clear()
	_vis16_fitness_gain_sum = 0.0
	_vis16_selected_mutation_count = 0
	_vis15_phenotype_count = 0
	_vis15_unique_phenotype_hashes.clear()
	_vis15_unique_environment_hashes.clear()
	_vis15_population_summaries.clear()
	_vis14_instance_count = 0
	_vis14_represented_biomass_kg = 0.0
	_vis14_mid_proxy_count = 0
	_vis14_far_proxy_count = 0
	_vis14_population_summaries.clear()
	_ph5_instance_count = 0
	_ph5_branch_vertex_count = 0
	_ph5_foliage_instance_count = 0
	_ph5_population_summaries.clear()

	var snapshot_hash := String(_spatial_snapshot.get("snapshot_hash", ""))
	var hash_tokens := PackedStringArray([
		VIS1_8A_STAGE,
		VIS18_TURNOVER_MODE,
		snapshot_hash,
		String(_ph5_profile.get("profile_hash", "")),
		"generation=%d" % generation,
	])
	var turnover_tokens := PackedStringArray([VIS1_8A_STAGE, snapshot_hash, "generation=%d" % generation])
	var event_root := Node3D.new()
	event_root.name = "VIS18TurnoverEvents"
	projection.add_child(event_root)

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
			var key := _vis18_population_key(patch_id, population_id)
			if not generation_map.has(key):
				population_index += 1
				continue
			var state: Dictionary = generation_map[key]
			var records: Array = state.get("records", [])
			var transition: Dictionary = state.get("transition", {})
			var source_biomass := float(state.get("source_biomass_kg", 0.0))
			var population_root := Node3D.new()
			population_root.name = "PH5Population_%s" % population_id
			ph5_patch_root.add_child(population_root)

			var represented_sum := 0.0
			var genome_hashes := {}
			var lineage_hashes := {}
			var phenotype_hashes := {}
			var environment_hashes := {}
			var final_fitness_sum := 0.0
			var realized_count := 0
			for record_index in range(records.size()):
				if typeof(records[record_index]) != TYPE_DICTIONARY:
					continue
				var record: Dictionary = Dictionary(records[record_index]).duplicate(true)
				var world_x := float(record.get("world_x", ph5_patch_root.global_position.x))
				var world_z := float(record.get("world_z", ph5_patch_root.global_position.z))
				var environment := sample_environment_at(world_x, world_z)
				var realized := VIS18_TurnoverBridge.realize_individual(record, environment, _ph5_profile, snapshot_hash, generation)
				if realized.is_empty():
					continue
				var materialization: Dictionary = realized.get("materialization", {})
				var description: Dictionary = realized.get("render_description", {})
				var traits: Dictionary = realized.get("realized_traits", {})
				var represented := float(record.get("represented_biomass_kg", 0.0))
				var instance := _create_ph5_plant_instance(
					patch_id,
					population_id,
					population_index,
					record_index,
					records.size(),
					source_biomass,
					materialization,
					ph5_patch_root.position
				)
				var local_ground := sample_terrain_height(world_x, world_z) - ph5_patch_root.global_position.y
				instance.position = Vector3(world_x - ph5_patch_root.global_position.x, local_ground + 0.32, world_z - ph5_patch_root.global_position.z)
				instance.rotation.y = float(record.get("rotation_y", 0.0))
				instance.scale = Vector3.ONE * _vis18_scale_for_record(record)
				instance.set_meta("visual_representation_only", true)
				instance.set_meta("population_turnover_derived", true)
				instance.set_meta("canonical_population_truth", false)
				instance.set_meta("canonical_timeline_truth", false)
				instance.set_meta("patch_id", patch_id)
				instance.set_meta("population_id", population_id)
				instance.set_meta("stable_id", String(record.get("stable_id", "")))
				instance.set_meta("parent_stable_id", String(record.get("parent_stable_id", "")))
				instance.set_meta("birth_generation", int(record.get("birth_generation", 0)))
				instance.set_meta("age_generations", int(record.get("age_generations", 0)))
				instance.set_meta("turnover_event", String(record.get("last_event", "")))
				instance.set_meta("represented_biomass_kg", represented)
				instance.set_meta("genome_checksum", String(realized.get("genome_checksum", "")))
				instance.set_meta("lineage_checksum", String(realized.get("lineage_checksum", "")))
				instance.set_meta("lineage_generation", int(realized.get("lineage_generation", 0)))
				instance.set_meta("environment_checksum", String(realized.get("environment_checksum", "")))
				instance.set_meta("phenotype_hash", String(realized.get("phenotype_hash", "")))
				instance.set_meta("current_fitness", float(realized.get("current_fitness", 0.0)))
				instance.set_meta("realized_max_height_m", float(traits.get("max_height_m", 0.0)))
				instance.set_meta("realized_crown_spread_m", float(traits.get("crown_spread_m", 0.0)))
				instance.set_meta("realized_branch_probability", float(traits.get("branch_probability", 0.0)))
				_configure_near_lod(instance)
				_add_vis15_mid_canopy_proxy(instance, population_id, description, String(realized.get("phenotype_hash", "")))
				if generation > 0 and int(record.get("birth_generation", -1)) == generation:
					_vis18_highlight_newborn(instance, population_id)
				population_root.add_child(instance)

				var stable_id := String(record.get("stable_id", ""))
				var genome_hash := String(realized.get("genome_checksum", ""))
				var lineage_hash := String(realized.get("lineage_checksum", ""))
				var phenotype_hash := String(realized.get("phenotype_hash", ""))
				var environment_hash := String(realized.get("environment_checksum", ""))
				_vis18_unique_stable_ids[stable_id] = true
				_vis16_unique_genomes[genome_hash] = true
				_vis16_unique_lineages[lineage_hash] = true
				_vis15_unique_phenotype_hashes[phenotype_hash] = true
				_vis15_unique_environment_hashes[environment_hash] = true
				if population_id == "alpha":
					_vis16_alpha_genomes[genome_hash] = true
				elif population_id == "beta":
					_vis16_beta_genomes[genome_hash] = true
				genome_hashes[genome_hash] = true
				lineage_hashes[lineage_hash] = true
				phenotype_hashes[phenotype_hash] = true
				environment_hashes[environment_hash] = true
				represented_sum += represented
				var current_fitness := float(realized.get("current_fitness", 0.0))
				final_fitness_sum += current_fitness
				_vis17_final_fitness_sum += current_fitness
				realized_count += 1
				_vis18_current_visual_count += 1
				_vis16_lineage_count += 1
				_vis15_phenotype_count += 1
				_vis14_instance_count += 1
				_vis14_represented_biomass_kg += represented
				_ph5_instance_count += 1
				_ph5_branch_vertex_count += int(materialization.get("branch_vertex_count", 0))
				_ph5_foliage_instance_count += int(materialization.get("foliage_instance_count", 0))
				hash_tokens.append("I|%s|%s|%s|g=%d|%.9f|%.9f|genome=%s|phenotype=%s" % [
					patch_id,
					population_id,
					stable_id,
					generation,
					world_x,
					world_z,
					genome_hash,
					phenotype_hash,
				])

			_add_vis18_far_proxy(population_root, population_id, records, ph5_patch_root.global_position)
			_vis18_current_births += int(transition.get("birth_count", 0))
			_vis16_selected_mutation_count += int(transition.get("selected_birth_mutation_count", 0))
			_vis18_current_deaths += int(transition.get("death_count", 0))
			_vis18_current_survivors += int(transition.get("survivor_count", records.size()))
			turnover_tokens.append(String(transition.get("turnover_hash", "")))
			_vis18_add_death_markers(event_root, transition)

			var divisor := maxf(1.0, float(realized_count))
			var population_summary := {
				"patch_id": patch_id,
				"population_id": population_id,
				"source_biomass_kg": source_biomass,
				"represented_biomass_kg": represented_sum,
				"visual_count": realized_count,
				"founder_count": int(state.get("base_count", 0)),
				"birth_count": int(transition.get("birth_count", 0)),
				"death_count": int(transition.get("death_count", 0)),
				"survivor_count": int(transition.get("survivor_count", 0)),
				"unique_genome_count": genome_hashes.size(),
				"unique_lineage_count": lineage_hashes.size(),
				"phenotype_count": phenotype_hashes.size(),
				"environment_sample_count": environment_hashes.size(),
				"mean_final_fitness": final_fitness_sum / divisor,
				"generation": generation,
				"turnover_hash": String(transition.get("turnover_hash", "")),
			}
			_vis16_population_summaries.append(population_summary)
			_vis15_population_summaries.append(population_summary.duplicate(true))
			_vis14_population_summaries.append(population_summary.duplicate(true))
			_ph5_population_summaries.append(population_summary.duplicate(true))
			hash_tokens.append("POP|%s|%s|g=%d|count=%d|births=%d|deaths=%d|represented=%.9f|fitness=%.12f" % [
				patch_id,
				population_id,
				generation,
				realized_count,
				int(transition.get("birth_count", 0)),
				int(transition.get("death_count", 0)),
				represented_sum,
				final_fitness_sum / divisor,
			])
			population_index += 1

	_vis18_cumulative_births = _vis18_cumulative_event_count(generation, "birth_count")
	_vis18_cumulative_deaths = _vis18_cumulative_event_count(generation, "death_count")
	_vis18_turnover_hash = "\n".join(turnover_tokens).sha256_text()
	_vis18_field_hash = "\n".join(hash_tokens).sha256_text()
	_vis17_field_hash = _vis18_field_hash
	_vis16_field_hash = _vis18_field_hash
	_vis15_field_hash = _vis18_field_hash
	_vis14_projection_hash = _vis18_field_hash
	_ph5_projection_hash = _vis18_field_hash
	_apply_visibility_state()


func _vis18_cumulative_event_count(generation: int, field_name: String) -> int:
	var total := 0
	for generation_index in range(1, generation + 1):
		var state_map: Dictionary = _vis18_generation_cache.get(generation_index, {})
		for state_variant in state_map.values():
			if typeof(state_variant) != TYPE_DICTIONARY:
				continue
			var transition: Dictionary = Dictionary(state_variant).get("transition", {})
			total += int(transition.get(field_name, 0))
	return total


func _vis18_scale_for_record(record: Dictionary) -> float:
	var represented := maxf(0.001, float(record.get("represented_biomass_kg", 0.001)))
	var base_scale := VIS14_PLANT_SCALE_MIN + sqrt(represented) * 1.05
	var variation := lerpf(0.88, 1.14, _vis18_unit("scale|%s" % String(record.get("stable_id", ""))))
	return clampf(base_scale * variation, VIS14_PLANT_SCALE_MIN, VIS14_PLANT_SCALE_MAX)


func _add_vis18_far_proxy(population_root: Node3D, population_id: String, records: Array, patch_center: Vector3) -> void:
	if records.is_empty():
		return
	var centroid := Vector2.ZERO
	for record_variant in records:
		var record: Dictionary = record_variant
		centroid += Vector2(float(record.get("world_x", patch_center.x)), float(record.get("world_z", patch_center.z)))
	centroid /= float(records.size())
	var proxy := MeshInstance3D.new()
	proxy.name = "FarTurnoverCanopy"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 5
	proxy.mesh = sphere
	proxy.position = Vector3(centroid.x - patch_center.x, 4.2, centroid.y - patch_center.z)
	var radius := 2.0 + sqrt(float(records.size())) * 0.72
	proxy.scale = Vector3(radius, maxf(1.2, radius * 0.48), radius)
	proxy.material_override = _lod_proxy_material(population_id, 0.74)
	proxy.visibility_range_begin = FAR_LOD_BEGIN_M
	proxy.visibility_range_begin_margin = 30.0
	proxy.set_meta("derived_lod_proxy", "VIS18A_TURNOVER_POPULATION")
	proxy.set_meta("representative_count", records.size())
	population_root.add_child(proxy)
	_vis14_far_proxy_count += 1


func _vis18_highlight_newborn(instance: Node3D, population_id: String) -> void:
	var foliage := instance.get_node_or_null("Foliage") as MultiMeshInstance3D
	if foliage != null:
		var material := _foliage_material(population_id)
		material.albedo_color = material.albedo_color.lightened(0.24)
		foliage.material_override = material
	var marker := MeshInstance3D.new()
	marker.name = "NewbornMarker"
	var sphere := SphereMesh.new()
	sphere.radius = 0.20
	sphere.height = 0.40
	sphere.radial_segments = 8
	sphere.rings = 4
	marker.mesh = sphere
	marker.position = Vector3(0.0, 0.22, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.86, 0.22, 1.0)
	material.roughness = 0.72
	marker.material_override = material
	marker.visibility_range_end = 100.0
	marker.visibility_range_end_margin = 15.0
	instance.add_child(marker)


func _vis18_add_death_markers(event_root: Node3D, transition: Dictionary) -> void:
	for death_variant in Array(transition.get("deaths", [])):
		if typeof(death_variant) != TYPE_DICTIONARY:
			continue
		var death: Dictionary = death_variant
		var world_x := float(death.get("world_x", 0.0))
		var world_z := float(death.get("world_z", 0.0))
		var marker := MeshInstance3D.new()
		marker.name = "Death_%s" % String(death.get("stable_id", "")).sha256_text().substr(0, 8)
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.32
		cylinder.bottom_radius = 0.32
		cylinder.height = 0.08
		marker.mesh = cylinder
		marker.position = Vector3(world_x, sample_terrain_height(world_x, world_z) + 0.08, world_z)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.82, 0.20, 0.15, 0.88)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.82
		marker.material_override = material
		marker.visibility_range_end = 120.0
		marker.visibility_range_end_margin = 20.0
		event_root.add_child(marker)


func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	var filtered := PackedStringArray()
	for line in status.text.split("\n"):
		var text_line := String(line)
		if text_line.begins_with("VIS1.7=ACTIVE"):
			continue
		filtered.append(text_line)
	status.text = "\n".join(filtered)
	var play_label := "PLAY" if _vis17_playing else "PAUSE"
	var hash_preview := _vis18_field_hash.substr(0, 12) if _vis18_field_hash.length() == 64 else "pending"
	var turnover_preview := _vis18_turnover_hash.substr(0, 12) if _vis18_turnover_hash.length() == 64 else "pending"
	status.text += "\nVIS1.8A=ACTIVE generation=%d/%d %s | reps=%d founders=%d | births=%d deaths=%d survivors=%d | cumulative births=%d deaths=%d | represented=%.3fkg source=%.3fkg | turnover=%s field=%s | canonical_population_truth=OFF" % [
		_vis17_generation,
		VIS18_TimelineBridge.MAX_GENERATION,
		play_label,
		_vis18_current_visual_count,
		_vis18_founder_count,
		_vis18_current_births,
		_vis18_current_deaths,
		_vis18_current_survivors,
		_vis18_cumulative_births,
		_vis18_cumulative_deaths,
		_vis14_represented_biomass_kg,
		float(_spatial_snapshot.get("total_final_biomass_kg", 0.0)),
		turnover_preview,
		hash_preview,
	]
	var nearest := _vis18_nearest_plant()
	if not nearest.is_empty():
		status.text += "\nNearest turnover: %s/%s stable=%s born=g%d age=%d event=%s d=%.1fm | parent=%s | fitness=%.3f genome=%s" % [
			String(nearest.get("patch_id", "?")),
			String(nearest.get("population_id", "?")),
			String(nearest.get("stable_id", "")).sha256_text().substr(0, 8),
			int(nearest.get("birth_generation", 0)),
			int(nearest.get("age_generations", 0)),
			String(nearest.get("turnover_event", "?")),
			float(nearest.get("distance_m", 0.0)),
			String(nearest.get("parent_stable_id", "")).sha256_text().substr(0, 8) if not String(nearest.get("parent_stable_id", "")).is_empty() else "founder",
			float(nearest.get("current_fitness", 0.0)),
			String(nearest.get("genome_checksum", "")).substr(0, 12),
		]
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title != null:
		title.text = "ECO.VIS1.8A — Population Turnover Field — %s G%d | reps=%d | +%d/-%d" % [play_label, _vis17_generation, _vis18_current_visual_count, _vis18_current_births, _vis18_current_deaths]


func _vis18_nearest_plant() -> Dictionary:
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
				if not bool(plant.get_meta("population_turnover_derived", false)):
					continue
				var distance := _camera.global_position.distance_to(plant.global_position)
				if distance >= best_distance:
					continue
				best_distance = distance
				best = {
					"distance_m": distance,
					"patch_id": plant.get_meta("patch_id", ""),
					"population_id": plant.get_meta("population_id", ""),
					"stable_id": plant.get_meta("stable_id", ""),
					"parent_stable_id": plant.get_meta("parent_stable_id", ""),
					"birth_generation": plant.get_meta("birth_generation", 0),
					"age_generations": plant.get_meta("age_generations", 0),
					"turnover_event": plant.get_meta("turnover_event", ""),
					"current_fitness": plant.get_meta("current_fitness", 0.0),
					"genome_checksum": plant.get_meta("genome_checksum", ""),
				}
	return best


func _vis18_population_key(patch_id: String, population_id: String) -> String:
	return "%s|%s" % [patch_id, population_id]


func _vis18_mean_record_fitness(records: Array) -> float:
	if records.is_empty():
		return 0.0
	var total := 0.0
	for record_variant in records:
		if typeof(record_variant) == TYPE_DICTIONARY:
			total += float(Dictionary(record_variant).get("current_fitness", 0.0))
	return total / float(records.size())


func _vis18_founder_hash(snapshot_hash: String, patch_id: String, population_id: String, records: Array) -> String:
	var tokens := PackedStringArray([VIS1_8A_STAGE, "FOUNDERS", snapshot_hash, patch_id, population_id])
	for record_variant in records:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		tokens.append("%s|%.9f|%.9f|%.9f" % [String(record.get("stable_id", "")), float(record.get("world_x", 0.0)), float(record.get("world_z", 0.0)), float(record.get("represented_biomass_kg", 0.0))])
	return "\n".join(tokens).sha256_text()


func _vis18_unit(payload: String) -> float:
	return float(payload.sha256_text().substr(0, 12).hex_to_int()) / 281474976710655.0
