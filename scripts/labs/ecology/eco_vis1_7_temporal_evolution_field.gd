extends "res://scripts/labs/ecology/eco_vis1_6_lineage_genome_field.gd"

const VIS17_TimelineBridge = preload("res://scripts/labs/ecology/eco_vis1_7_temporal_evolution_bridge.gd")

const VIS1_7_STAGE := "ECO.VIS1.7"
const VIS17_TEMPORAL_MODE := "LAB_DERIVED_TEMPORAL_LINEAGE_SCRUBBER"
const PLAY_INTERVAL_SECONDS := 2.0

var _vis17_generation := VIS17_TimelineBridge.DEFAULT_GENERATION
var _vis17_playing := false
var _vis17_play_accumulator := 0.0
var _vis17_field_hash := ""
var _vis17_trajectory_hashes := {}
var _vis17_final_fitness_sum := 0.0

func _ready() -> void:
	super._ready()
	_apply_vis1_7_generation(_vis17_generation)
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title != null:
		title.text = "ECO.VIS1.7 — Temporal Evolution Scrubber"
	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset | Left/Right generation | Space play/pause | R generation 0 | F1-F5 diagnostics\nVIS1.7: positions/biomass stay fixed while deterministic lab-derived lineage/genome generations alter inherited phenotype and PH5 geometry; canonical ecology timeline truth remains untouched"
	_update_status()

func _process(delta: float) -> void:
	super._process(delta)
	if not _vis17_playing:
		return
	_vis17_play_accumulator += delta
	if _vis17_play_accumulator < PLAY_INTERVAL_SECONDS:
		return
	_vis17_play_accumulator = 0.0
	if _vis17_generation >= VIS17_TimelineBridge.MAX_GENERATION:
		_vis17_playing = false
		_update_status()
		return
	set_evolution_generation(_vis17_generation + 1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_LEFT:
					_vis17_playing = false
					set_evolution_generation(_vis17_generation - 1)
					get_viewport().set_input_as_handled()
					return
				KEY_RIGHT:
					_vis17_playing = false
					set_evolution_generation(_vis17_generation + 1)
					get_viewport().set_input_as_handled()
					return
				KEY_SPACE:
					_vis17_playing = not _vis17_playing
					_vis17_play_accumulator = 0.0
					_update_status()
					get_viewport().set_input_as_handled()
					return
				KEY_R:
					_vis17_playing = false
					set_evolution_generation(0)
					get_viewport().set_input_as_handled()
					return
	super._unhandled_input(event)

func set_evolution_generation(generation: int) -> void:
	var clamped := clampi(generation, 0, VIS17_TimelineBridge.MAX_GENERATION)
	if clamped == _vis17_generation and _vis17_field_hash.length() == 64:
		_update_status()
		return
	_vis17_generation = clamped
	_vis17_play_accumulator = 0.0
	_apply_vis1_7_generation(_vis17_generation)
	_update_status()

func get_evolution_generation() -> int:
	return _vis17_generation

func get_evolution_state() -> Dictionary:
	return {
		"stage": VIS1_7_STAGE,
		"mode": VIS17_TEMPORAL_MODE,
		"generation": _vis17_generation,
		"max_generation": VIS17_TimelineBridge.MAX_GENERATION,
		"playing": _vis17_playing,
		"play_interval_seconds": PLAY_INTERVAL_SECONDS,
		"field_hash": _vis17_field_hash,
		"lineage_count": _vis16_lineage_count,
		"unique_genome_count": _vis16_unique_genomes.size(),
		"trajectory_count": _vis17_trajectory_hashes.size(),
		"selected_mutation_count": _vis16_selected_mutation_count,
		"mean_final_fitness": _vis17_final_fitness_sum / maxf(1.0, float(_vis16_lineage_count)),
		"canonical_timeline_truth": false,
	}

func get_population_field_hash() -> String:
	return _vis17_field_hash

func get_ph5_projection_hash() -> String:
	return _vis17_field_hash

func get_population_field_summary() -> Dictionary:
	var summary := super.get_population_field_summary()
	summary["stage"] = VIS1_7_STAGE
	summary["temporal_mode"] = VIS17_TEMPORAL_MODE
	summary["current_generation"] = _vis17_generation
	summary["max_generation"] = VIS17_TimelineBridge.MAX_GENERATION
	summary["playback_active"] = _vis17_playing
	summary["play_interval_seconds"] = PLAY_INTERVAL_SECONDS
	summary["trajectory_count"] = _vis17_trajectory_hashes.size()
	summary["mean_final_fitness"] = _vis17_final_fitness_sum / maxf(1.0, float(_vis16_lineage_count))
	summary["canonical_timeline_truth"] = false
	summary["adaptation_generations"] = _vis17_generation
	summary["projection_hash"] = _vis17_field_hash
	return summary

func _apply_vis1_7_generation(generation: int) -> void:
	if not is_instance_valid(_ph5_root) or _spatial_snapshot.is_empty() or _ph5_profile.is_empty():
		return
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
	_vis14_population_summaries.clear()
	_ph5_instance_count = 0
	_ph5_branch_vertex_count = 0
	_ph5_foliage_instance_count = 0
	_ph5_population_summaries.clear()

	var snapshot_hash := String(_spatial_snapshot.get("snapshot_hash", ""))
	var hash_tokens := PackedStringArray([
		VIS1_7_STAGE,
		snapshot_hash,
		String(_ph5_profile.get("profile_hash", "")),
		VIS17_TEMPORAL_MODE,
		"generation=%d" % generation,
		"max_generation=%d" % VIS17_TimelineBridge.MAX_GENERATION,
	])

	for patch_variant in Array(_spatial_snapshot.get("patches", [])):
		if typeof(patch_variant) != TYPE_DICTIONARY:
			continue
		var patch: Dictionary = patch_variant
		var patch_id := String(patch.get("id", ""))
		var ph5_patch_root := _ph5_root.get_node_or_null("Patch_%s" % patch_id) as Node3D
		if ph5_patch_root == null:
			continue
		for population_variant in Array(patch.get("plants", [])):
			if typeof(population_variant) != TYPE_DICTIONARY:
				continue
			var population: Dictionary = population_variant
			var population_id := String(population.get("id", ""))
			var biomass_kg := maxf(0.0, float(population.get("final_biomass_kg", 0.0)))
			var population_root := ph5_patch_root.get_node_or_null("PH5Population_%s" % population_id) as Node3D
			if population_root == null or population_id.is_empty() or biomass_kg <= 0.000001:
				continue
			var genome_hashes := {}
			var lineage_hashes := {}
			var phenotype_hashes := {}
			var environment_hashes := {}
			var represented_sum := 0.0
			var height_sum := 0.0
			var crown_sum := 0.0
			var branch_sum := 0.0
			var fitness_gain_sum := 0.0
			var mutation_count_sum := 0
			var visual_count := 0
			for child in population_root.get_children():
				if not child is Node3D or not String(child.name).begins_with("Plant_"):
					continue
				var plant := child as Node3D
				var instance_index := String(plant.name).trim_prefix("Plant_").to_int()
				var environment := sample_environment_at(plant.global_position.x, plant.global_position.z)
				var realized := VIS17_TimelineBridge.realize_at_generation(
					environment,
					_ph5_profile,
					snapshot_hash,
					patch_id,
					population_id,
					instance_index,
					generation
				)
				if realized.is_empty():
					continue
				_update_vis17_plant_geometry(plant, population_id, realized)
				var represented := float(plant.get_meta("represented_biomass_kg", 0.0))
				represented_sum += represented
				visual_count += 1
				var genome: Dictionary = realized.get("genome", {})
				var traits: Dictionary = realized.get("realized_traits", {})
				var genome_hash := String(realized.get("genome_checksum", ""))
				var lineage_hash := String(realized.get("lineage_checksum", ""))
				var phenotype_hash := String(realized.get("phenotype_hash", ""))
				var environment_hash := String(realized.get("environment_checksum", ""))
				var trajectory_hash := String(realized.get("trajectory_hash", ""))
				plant.set_meta("lineage_generation", generation)
				plant.set_meta("genome_id", String(realized.get("genome_id", "")))
				plant.set_meta("genome_checksum", genome_hash)
				plant.set_meta("lineage_id", String(realized.get("lineage_id", "")))
				plant.set_meta("individual_id", String(realized.get("individual_id", "")))
				plant.set_meta("lineage_checksum", lineage_hash)
				plant.set_meta("initial_fitness", float(realized.get("initial_fitness", 0.0)))
				plant.set_meta("final_fitness", float(realized.get("final_fitness", 0.0)))
				plant.set_meta("selected_mutation_count", int(realized.get("selected_mutation_count", 0)))
				plant.set_meta("trajectory_hash", trajectory_hash)
				plant.set_meta("timeline_generation", generation)
				plant.set_meta("canonical_timeline_truth", false)
				plant.set_meta("water_preference", float(genome.get("water_preference", 0.0)))
				plant.set_meta("root_depth_m", float(genome.get("root_depth_m", 0.0)))
				plant.set_meta("growth_rate", float(genome.get("growth_rate", 0.0)))
				plant.set_meta("shade_tolerance", float(genome.get("shade_tolerance", 0.0)))
				plant.set_meta("seed_dispersal_distance_m", float(genome.get("seed_dispersal_distance_m", 0.0)))
				plant.set_meta("environment_checksum", environment_hash)
				plant.set_meta("phenotype_hash", phenotype_hash)
				plant.set_meta("bridge_hash", String(realized.get("bridge_hash", "")))
				plant.set_meta("inherited_traits_checksum", String(realized.get("inherited_traits_checksum", "")))
				plant.set_meta("realized_max_height_m", float(traits.get("max_height_m", 0.0)))
				plant.set_meta("realized_crown_spread_m", float(traits.get("crown_spread_m", 0.0)))
				plant.set_meta("realized_branch_probability", float(traits.get("branch_probability", 0.0)))

				genome_hashes[genome_hash] = true
				lineage_hashes[lineage_hash] = true
				phenotype_hashes[phenotype_hash] = true
				environment_hashes[environment_hash] = true
				_vis16_unique_genomes[genome_hash] = true
				_vis16_unique_lineages[lineage_hash] = true
				_vis15_unique_phenotype_hashes[phenotype_hash] = true
				_vis15_unique_environment_hashes[environment_hash] = true
				_vis17_trajectory_hashes[trajectory_hash] = true
				if population_id == "alpha":
					_vis16_alpha_genomes[genome_hash] = true
				elif population_id == "beta":
					_vis16_beta_genomes[genome_hash] = true
				var fitness_gain := float(realized.get("final_fitness", 0.0)) - float(realized.get("initial_fitness", 0.0))
				fitness_gain_sum += fitness_gain
				_vis16_fitness_gain_sum += fitness_gain
				_vis17_final_fitness_sum += float(realized.get("final_fitness", 0.0))
				var selected_mutations := int(realized.get("selected_mutation_count", 0))
				mutation_count_sum += selected_mutations
				_vis16_selected_mutation_count += selected_mutations
				height_sum += float(traits.get("max_height_m", 0.0))
				crown_sum += float(traits.get("crown_spread_m", 0.0))
				branch_sum += float(traits.get("branch_probability", 0.0))
				_vis16_lineage_count += 1
				_vis15_phenotype_count += 1
				_vis14_instance_count += 1
				_vis14_represented_biomass_kg += represented
				_ph5_instance_count += 1
				var materialization: Dictionary = realized.get("materialization", {})
				_ph5_branch_vertex_count += int(materialization.get("branch_vertex_count", 0))
				_ph5_foliage_instance_count += int(materialization.get("foliage_instance_count", 0))
				hash_tokens.append("I|%s|%s|%d|g=%d|traj=%s|genome=%s|phenotype=%s" % [
					patch_id,
					population_id,
					instance_index,
					generation,
					trajectory_hash,
					genome_hash,
					phenotype_hash,
				])

			var divisor := maxf(1.0, float(visual_count))
			var population_summary := {
				"patch_id": patch_id,
				"population_id": population_id,
				"source_biomass_kg": biomass_kg,
				"represented_biomass_kg": represented_sum,
				"visual_count": visual_count,
				"phenotype_count": phenotype_hashes.size(),
				"environment_sample_count": environment_hashes.size(),
				"unique_genome_count": genome_hashes.size(),
				"unique_lineage_count": lineage_hashes.size(),
				"generation": generation,
				"mean_max_height_m": height_sum / divisor,
				"mean_crown_spread_m": crown_sum / divisor,
				"mean_branch_probability": branch_sum / divisor,
				"mean_fitness_gain": fitness_gain_sum / divisor,
				"selected_mutation_count": mutation_count_sum,
				"temporal_mode": VIS17_TEMPORAL_MODE,
			}
			_vis16_population_summaries.append(population_summary)
			_vis15_population_summaries.append(population_summary.duplicate(true))
			_vis14_population_summaries.append(population_summary.duplicate(true))
			_ph5_population_summaries.append(population_summary.duplicate(true))
			hash_tokens.append("POP|%s|%s|g=%d|%.9f|%.9f|%d|%d|%.12f|%d" % [
				patch_id,
				population_id,
				generation,
				biomass_kg,
				represented_sum,
				visual_count,
				genome_hashes.size(),
				fitness_gain_sum / divisor,
				mutation_count_sum,
			])

	_vis17_field_hash = "\n".join(hash_tokens).sha256_text()
	_vis16_field_hash = _vis17_field_hash
	_vis15_field_hash = _vis17_field_hash
	_vis14_projection_hash = _vis17_field_hash
	_ph5_projection_hash = _vis17_field_hash

func _update_vis17_plant_geometry(plant: Node3D, population_id: String, realized: Dictionary) -> void:
	var materialization: Dictionary = realized.get("materialization", {})
	var description: Dictionary = realized.get("render_description", {})
	var branches := plant.get_node_or_null("Branches") as MeshInstance3D
	if branches != null:
		branches.mesh = materialization.get("branch_mesh") as ArrayMesh
	var foliage := plant.get_node_or_null("Foliage") as MultiMeshInstance3D
	if foliage != null:
		foliage.multimesh = materialization.get("foliage_multimesh") as MultiMesh
	var mid := plant.get_node_or_null("MidCanopy") as MeshInstance3D
	if mid != null:
		var canopy: Dictionary = description.get("canopy", {})
		var center_values: Array = canopy.get("center", [0.0, 2.0, 0.0])
		var radius := maxf(0.25, float(canopy.get("radius_xz_m", 1.0)))
		var canopy_height := maxf(0.25, float(canopy.get("height_m", 1.5)))
		mid.position = Vector3(float(center_values[0]), float(center_values[1]), float(center_values[2]))
		mid.scale = Vector3(radius, canopy_height * 0.5, radius)
		mid.set_meta("phenotype_hash", String(realized.get("phenotype_hash", "")))
	plant.set_meta("timeline_generation", _vis17_generation)
	plant.set_meta("temporal_evolution_derived", true)
	plant.set_meta("canonical_timeline_truth", false)

func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	status.text = status.text.replace("VIS1.6=ACTIVE", "VIS1.6_LINEAGE=ACTIVE")
	var hash_preview := _vis17_field_hash.substr(0, 12) if _vis17_field_hash.length() == 64 else "pending"
	var play_label := "PLAY" if _vis17_playing else "PAUSE"
	status.text += "\nVIS1.7=ACTIVE generation=%d/%d %s | trajectories=%d unique_genomes=%d mutations=%d mean_fitness=%.3f | field=%s | canonical_timeline_truth=OFF" % [
		_vis17_generation,
		VIS17_TimelineBridge.MAX_GENERATION,
		play_label,
		_vis17_trajectory_hashes.size(),
		_vis16_unique_genomes.size(),
		_vis16_selected_mutation_count,
		_vis17_final_fitness_sum / maxf(1.0, float(_vis16_lineage_count)),
		hash_preview,
	]
