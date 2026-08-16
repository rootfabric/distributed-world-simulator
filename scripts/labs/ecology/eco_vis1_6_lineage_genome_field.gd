extends "res://scripts/labs/ecology/eco_vis1_5_environment_phenotype_field.gd"

const VIS16_LineageBridge = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_bridge.gd")

const VIS1_6_STAGE := "ECO.VIS1.6"
const VIS16_LINEAGE_MODE := "LAB_DERIVED_LINEAGE_GENOME_LOCAL_ENVIRONMENT"

var _vis16_field_hash := ""
var _vis16_lineage_count := 0
var _vis16_unique_lineages := {}
var _vis16_unique_genomes := {}
var _vis16_alpha_genomes := {}
var _vis16_beta_genomes := {}
var _vis16_population_summaries: Array[Dictionary] = []
var _vis16_fitness_gain_sum := 0.0
var _vis16_selected_mutation_count := 0

func _ready() -> void:
	super._ready()
	var title := get_node_or_null("HUD/Margin/Panel/VBox/Title") as Label
	if title != null:
		title.text = "ECO.VIS1.6 — Lineage / Genome Field"
	if is_instance_valid(_controls_label):
		_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset | F1 diagnostics | F2 discs | F3 links | F4 labels | F5 plants\nVIS1.6: representative plants carry deterministic lab-derived lineages/genomes selected against local EnvironmentSample; canonical VIS1.2 population/genome truth remains untouched"
	_update_status()

func get_population_field_hash() -> String:
	return _vis16_field_hash

func get_ph5_projection_hash() -> String:
	return _vis16_field_hash

func get_population_field_summary() -> Dictionary:
	var summary := super.get_population_field_summary()
	summary["stage"] = VIS1_6_STAGE
	summary["lineage_mode"] = VIS16_LINEAGE_MODE
	summary["canonical_genome_truth"] = false
	summary["lab_lineage_field"] = true
	summary["lineage_instance_count"] = _vis16_lineage_count
	summary["unique_lineage_count"] = _vis16_unique_lineages.size()
	summary["unique_genome_count"] = _vis16_unique_genomes.size()
	summary["alpha_unique_genome_count"] = _vis16_alpha_genomes.size()
	summary["beta_unique_genome_count"] = _vis16_beta_genomes.size()
	summary["selected_mutation_count"] = _vis16_selected_mutation_count
	summary["mean_fitness_gain"] = _vis16_fitness_gain_sum / maxf(1.0, float(_vis16_lineage_count))
	summary["adaptation_generations"] = VIS16_LineageBridge.ADAPTATION_GENERATIONS
	summary["offspring_per_generation"] = VIS16_LineageBridge.OFFSPRING_PER_GENERATION
	summary["alpha_baseline_genome"] = VIS16_LineageBridge.create_population_baseline_genome("alpha")
	summary["beta_baseline_genome"] = VIS16_LineageBridge.create_population_baseline_genome("beta")
	summary["projection_hash"] = _vis16_field_hash
	summary["populations"] = _vis16_population_summaries.duplicate(true)
	return summary

func _build_vis1_5_environment_phenotype_field() -> void:
	if is_instance_valid(_ph5_root):
		_ph5_root.free()
	_vis16_field_hash = ""
	_vis16_lineage_count = 0
	_vis16_unique_lineages.clear()
	_vis16_unique_genomes.clear()
	_vis16_alpha_genomes.clear()
	_vis16_beta_genomes.clear()
	_vis16_population_summaries.clear()
	_vis16_fitness_gain_sum = 0.0
	_vis16_selected_mutation_count = 0
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
	if projection == null or _spatial_snapshot.is_empty() or _ph5_profile.is_empty():
		return

	_ph5_root = Node3D.new()
	_ph5_root.name = "PH5PlantGeometry"
	projection.add_child(_ph5_root)
	var snapshot_hash := String(_spatial_snapshot.get("snapshot_hash", ""))
	var alpha_baseline := VIS16_LineageBridge.create_population_baseline_genome("alpha")
	var beta_baseline := VIS16_LineageBridge.create_population_baseline_genome("beta")
	var hash_tokens := PackedStringArray([
		VIS1_6_STAGE,
		snapshot_hash,
		String(_ph5_profile.get("profile_hash", "")),
		String(alpha_baseline.get("checksum", "")),
		String(beta_baseline.get("checksum", "")),
		VIS16_LINEAGE_MODE,
		"generations=%d" % VIS16_LineageBridge.ADAPTATION_GENERATIONS,
		"offspring=%d" % VIS16_LineageBridge.OFFSPRING_PER_GENERATION,
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
			var visual_count := clampi(int(ceil(biomass_kg / REPRESENTED_KG_PER_VISUAL_INSTANCE)), 1, VIS14_MAX_VISUAL_INSTANCES_PER_POPULATION)
			var cluster_count := clampi(int(ceil(sqrt(float(visual_count)) / 1.7)), 1, 3)
			var cluster_anchors := _cluster_anchors(patch_id, population_id, population_index, cluster_count)
			var population_root := Node3D.new()
			population_root.name = "PH5Population_%s" % population_id
			ph5_patch_root.add_child(population_root)
			_add_far_population_proxies(population_root, patch_id, population_id, biomass_kg, cluster_anchors, ph5_patch_root.position)

			var represented_sum := 0.0
			var phenotype_hashes := {}
			var environment_hashes := {}
			var genome_hashes := {}
			var lineage_hashes := {}
			var height_sum := 0.0
			var crown_sum := 0.0
			var branch_probability_sum := 0.0
			var fitness_gain_sum := 0.0
			var mutation_count_sum := 0
			for instance_index in range(visual_count):
				var represented_biomass := biomass_kg / float(visual_count)
				if instance_index == visual_count - 1:
					represented_biomass = biomass_kg - represented_sum
				represented_sum += represented_biomass
				var placement := _vis15_placement(patch_id, population_id, population_index, instance_index, represented_biomass, cluster_anchors, ph5_patch_root.position)
				var environment := sample_environment_at(float(placement["world_x"]), float(placement["world_z"]))
				var realized := VIS16_LineageBridge.realize(environment, _ph5_profile, snapshot_hash, patch_id, population_id, instance_index)
				if realized.is_empty():
					continue
				var materialization: Dictionary = realized.get("materialization", {})
				var description: Dictionary = realized.get("render_description", {})
				var traits: Dictionary = realized.get("realized_traits", {})
				var response: Dictionary = realized.get("response", {})
				var genome: Dictionary = realized.get("genome", {})
				var instance := _create_ph5_plant_instance(patch_id, population_id, population_index, instance_index, visual_count, biomass_kg, materialization, ph5_patch_root.position)
				instance.position = Vector3(placement["local_position"])
				instance.rotation.y = float(placement["rotation_y"])
				instance.scale = Vector3.ONE * float(placement["scale_factor"])
				instance.set_meta("visual_representation_only", true)
				instance.set_meta("phenotype_environment_coupled", true)
				instance.set_meta("lineage_genome_derived", true)
				instance.set_meta("canonical_genome_truth", false)
				instance.set_meta("patch_id", patch_id)
				instance.set_meta("population_id", population_id)
				instance.set_meta("represented_biomass_kg", represented_biomass)
				instance.set_meta("baseline_genome_id", String(realized.get("baseline_genome_id", "")))
				instance.set_meta("genome_id", String(realized.get("genome_id", "")))
				instance.set_meta("genome_checksum", String(realized.get("genome_checksum", "")))
				instance.set_meta("lineage_id", String(realized.get("lineage_id", "")))
				instance.set_meta("individual_id", String(realized.get("individual_id", "")))
				instance.set_meta("lineage_checksum", String(realized.get("lineage_checksum", "")))
				instance.set_meta("lineage_generation", int(realized.get("generation", -1)))
				instance.set_meta("initial_fitness", float(realized.get("initial_fitness", 0.0)))
				instance.set_meta("final_fitness", float(realized.get("final_fitness", 0.0)))
				instance.set_meta("selected_mutation_count", int(realized.get("selected_mutation_count", 0)))
				instance.set_meta("water_preference", float(genome.get("water_preference", 0.0)))
				instance.set_meta("root_depth_m", float(genome.get("root_depth_m", 0.0)))
				instance.set_meta("growth_rate", float(genome.get("growth_rate", 0.0)))
				instance.set_meta("shade_tolerance", float(genome.get("shade_tolerance", 0.0)))
				instance.set_meta("seed_dispersal_distance_m", float(genome.get("seed_dispersal_distance_m", 0.0)))
				instance.set_meta("environment_checksum", String(realized.get("environment_checksum", "")))
				instance.set_meta("phenotype_hash", String(realized.get("phenotype_hash", "")))
				instance.set_meta("bridge_hash", String(realized.get("bridge_hash", "")))
				instance.set_meta("inherited_traits_checksum", String(realized.get("inherited_traits_checksum", "")))
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
				var genome_hash := String(realized.get("genome_checksum", ""))
				var lineage_hash := String(realized.get("lineage_checksum", ""))
				phenotype_hashes[phenotype_hash] = true
				environment_hashes[environment_hash] = true
				genome_hashes[genome_hash] = true
				lineage_hashes[lineage_hash] = true
				_vis15_unique_phenotype_hashes[phenotype_hash] = true
				_vis15_unique_environment_hashes[environment_hash] = true
				_vis16_unique_genomes[genome_hash] = true
				_vis16_unique_lineages[lineage_hash] = true
				if population_id == "alpha": _vis16_alpha_genomes[genome_hash] = true
				elif population_id == "beta": _vis16_beta_genomes[genome_hash] = true
				_vis15_phenotype_count += 1
				_vis16_lineage_count += 1
				_vis14_instance_count += 1
				_vis14_represented_biomass_kg += represented_biomass
				_ph5_instance_count += 1
				_ph5_branch_vertex_count += int(materialization.get("branch_vertex_count", 0))
				_ph5_foliage_instance_count += int(materialization.get("foliage_instance_count", 0))
				height_sum += float(traits.get("max_height_m", 0.0))
				crown_sum += float(traits.get("crown_spread_m", 0.0))
				branch_probability_sum += float(traits.get("branch_probability", 0.0))
				var fitness_gain := float(realized.get("final_fitness", 0.0)) - float(realized.get("initial_fitness", 0.0))
				fitness_gain_sum += fitness_gain
				_vis16_fitness_gain_sum += fitness_gain
				var selected_mutations := int(realized.get("selected_mutation_count", 0))
				mutation_count_sum += selected_mutations
				_vis16_selected_mutation_count += selected_mutations
				hash_tokens.append("I|%s|represented=%.9f|lineage=%s|genome=%s|phenotype=%s|bridge=%s" % [_instance_hash_token(patch_id, population_id, instance_index, instance), represented_biomass, lineage_hash, genome_hash, phenotype_hash, String(realized.get("bridge_hash", ""))])

			var divisor := maxf(1.0, float(visual_count))
			var population_summary := {
				"patch_id": patch_id, "population_id": population_id, "source_biomass_kg": biomass_kg, "represented_biomass_kg": represented_sum,
				"visual_count": visual_count, "phenotype_count": phenotype_hashes.size(), "environment_sample_count": environment_hashes.size(),
				"unique_genome_count": genome_hashes.size(), "unique_lineage_count": lineage_hashes.size(), "cluster_count": cluster_count,
				"phenotype_source": VIS16_LINEAGE_MODE,
				"baseline_genome_id": String(VIS16_LineageBridge.create_population_baseline_genome(population_id).get("genome_id", "")),
				"mean_max_height_m": height_sum / divisor, "mean_crown_spread_m": crown_sum / divisor, "mean_branch_probability": branch_probability_sum / divisor,
				"mean_fitness_gain": fitness_gain_sum / divisor, "selected_mutation_count": mutation_count_sum, "generation": VIS16_LineageBridge.ADAPTATION_GENERATIONS,
			}
			_vis16_population_summaries.append(population_summary)
			_vis15_population_summaries.append(population_summary.duplicate(true))
			_vis14_population_summaries.append(population_summary.duplicate(true))
			_ph5_population_summaries.append(population_summary.duplicate(true))
			hash_tokens.append("POP|%s|%s|%.9f|%.9f|%d|%d|%d|%d|%.12f|%d" % [patch_id, population_id, biomass_kg, represented_sum, visual_count, phenotype_hashes.size(), environment_hashes.size(), genome_hashes.size(), fitness_gain_sum / divisor, mutation_count_sum])
			population_index += 1

	_vis16_field_hash = "\n".join(hash_tokens).sha256_text()
	_vis15_field_hash = _vis16_field_hash
	_vis14_projection_hash = _vis16_field_hash
	_ph5_projection_hash = _vis16_field_hash

func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	var filtered := PackedStringArray()
	for line in status.text.split("\n"):
		var text_line := String(line)
		if text_line.begins_with("VIS1.5=ACTIVE") or text_line.begins_with("Nearest phenotype:"):
			continue
		filtered.append(text_line)
	status.text = "\n".join(filtered)
	var hash_preview := _vis16_field_hash.substr(0, 12) if _vis16_field_hash.length() == 64 else "pending"
	status.text += "\nVIS1.5_ENV=ACTIVE env_coupled=%d/%d | VIS1.6=ACTIVE lineages=%d unique_genomes=%d [alpha=%d beta=%d] mutations=%d | field=%s | canonical_genome_truth=OFF" % [_vis15_phenotype_count, _vis14_instance_count, _vis16_lineage_count, _vis16_unique_genomes.size(), _vis16_alpha_genomes.size(), _vis16_beta_genomes.size(), _vis16_selected_mutation_count, hash_preview]
	var nearest := _nearest_vis16_plant()
	if not nearest.is_empty():
		status.text += "\nNearest lineage: %s/%s gen=%d d=%.1fm | genome=%s lineage=%s | water=%.3f root=%.2fm growth=%.3f shade=%.3f disperse=%.1fm | fitness %.3f->%.3f | phenotype=%s" % [String(nearest.get("patch_id", "?")), String(nearest.get("population_id", "?")), int(nearest.get("generation", -1)), float(nearest.get("distance_m", 0.0)), String(nearest.get("genome_checksum", "")).substr(0, 12), String(nearest.get("lineage_checksum", "")).substr(0, 12), float(nearest.get("water_preference", 0.0)), float(nearest.get("root_depth_m", 0.0)), float(nearest.get("growth_rate", 0.0)), float(nearest.get("shade_tolerance", 0.0)), float(nearest.get("seed_dispersal_distance_m", 0.0)), float(nearest.get("initial_fitness", 0.0)), float(nearest.get("final_fitness", 0.0)), String(nearest.get("phenotype_hash", "")).substr(0, 12)]

func _nearest_vis16_plant() -> Dictionary:
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
				if not bool(plant.get_meta("lineage_genome_derived", false)):
					continue
				var distance := _camera.global_position.distance_to(plant.global_position)
				if distance >= best_distance:
					continue
				best_distance = distance
				best = {
					"distance_m": distance, "patch_id": plant.get_meta("patch_id", ""), "population_id": plant.get_meta("population_id", ""),
					"generation": plant.get_meta("lineage_generation", -1), "genome_checksum": plant.get_meta("genome_checksum", ""), "lineage_checksum": plant.get_meta("lineage_checksum", ""),
					"water_preference": plant.get_meta("water_preference", 0.0), "root_depth_m": plant.get_meta("root_depth_m", 0.0), "growth_rate": plant.get_meta("growth_rate", 0.0),
					"shade_tolerance": plant.get_meta("shade_tolerance", 0.0), "seed_dispersal_distance_m": plant.get_meta("seed_dispersal_distance_m", 0.0),
					"initial_fitness": plant.get_meta("initial_fitness", 0.0), "final_fitness": plant.get_meta("final_fitness", 0.0), "phenotype_hash": plant.get_meta("phenotype_hash", ""),
				}
	return best
