extends "res://scripts/labs/ecology/eco_vis1_2_spatial_projection.gd"

const PH5Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")

const VIS1_3_STAGE := "ECO.VIS1.3"
const PH5_PROFILE_ID := "BRANCH_LEAF_INSTANCED"
const KG_PER_VISUAL_INSTANCE := 0.60
const MAX_VISUAL_INSTANCES_PER_POPULATION := 12
const PATCH_VISUAL_RADIUS_M := 17.0
const PLANT_SCALE_MIN := 1.25
const PLANT_SCALE_MAX := 2.10
const EXEMPLAR_BY_POPULATION := {
	"alpha": "SUN",
	"beta": "SHADE",
}

var _ph5_probe_results: Dictionary = {}
var _ph5_profile: Dictionary = {}
var _ph5_root: Node3D
var _ph5_projection_hash := ""
var _ph5_instance_count := 0
var _ph5_branch_vertex_count := 0
var _ph5_foliage_instance_count := 0
var _ph5_population_summaries: Array[Dictionary] = []


func _ready() -> void:
	_ph5_probe_results = PH5Probes.run_all()
	_ph5_profile = RendererProfile.create(PH5_PROFILE_ID)
	super._ready()
	$HUD/Margin/Panel/VBox/Title.text = "ECO.VIS1.3 — PH5 Population Materialization"
	_build_ph5_population_projection()
	_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset\nPH5 plant geometry is derived presentation; canonical ecology remains the VIS1.2 spatial snapshot"
	_update_status()


func rebuild_spatial_projection() -> void:
	super.rebuild_spatial_projection()
	_build_ph5_population_projection()
	_update_status()


func get_ph5_projection_hash() -> String:
	return _ph5_projection_hash


func get_ph5_materialization_summary() -> Dictionary:
	return {
		"stage": VIS1_3_STAGE,
		"profile_id": String(_ph5_profile.get("profile_id", "")),
		"profile_hash": String(_ph5_profile.get("profile_hash", "")),
		"source_snapshot_hash": String(_spatial_snapshot.get("snapshot_hash", "")),
		"projection_hash": _ph5_projection_hash,
		"visual_instance_count": _ph5_instance_count,
		"branch_vertex_count": _ph5_branch_vertex_count,
		"foliage_instance_count": _ph5_foliage_instance_count,
		"populations": _ph5_population_summaries.duplicate(true),
	}


func _build_ph5_population_projection() -> void:
	if is_instance_valid(_ph5_root):
		_ph5_root.free()
	_ph5_projection_hash = ""
	_ph5_instance_count = 0
	_ph5_branch_vertex_count = 0
	_ph5_foliage_instance_count = 0
	_ph5_population_summaries.clear()

	var projection := get_node_or_null("SpatialEcologyProjection") as Node3D
	if projection == null or _spatial_snapshot.is_empty() or _ph5_probe_results.is_empty() or _ph5_profile.is_empty():
		return

	_remove_vis1_2_population_glyphs(projection)
	_ph5_root = Node3D.new()
	_ph5_root.name = "PH5PlantGeometry"
	projection.add_child(_ph5_root)

	var hash_tokens := PackedStringArray([
		VIS1_3_STAGE,
		String(_spatial_snapshot.get("snapshot_hash", "")),
		String(_ph5_profile.get("profile_hash", "")),
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
				int(ceil(biomass_kg / KG_PER_VISUAL_INSTANCE)),
				1,
				MAX_VISUAL_INSTANCES_PER_POPULATION
			)
			var population_root := Node3D.new()
			population_root.name = "PH5Population_%s" % population_id
			ph5_patch_root.add_child(population_root)
			var geometry_hash := String(materialization.get("geometry_hash", ""))
			for instance_index in range(visual_count):
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
				population_root.add_child(instance)
				_ph5_instance_count += 1
				_ph5_branch_vertex_count += int(materialization.get("branch_vertex_count", 0))
				_ph5_foliage_instance_count += int(materialization.get("foliage_instance_count", 0))
				hash_tokens.append(_instance_hash_token(patch_id, population_id, instance_index, instance))
			_ph5_population_summaries.append({
				"patch_id": patch_id,
				"population_id": population_id,
				"biomass_kg": biomass_kg,
				"visual_count": visual_count,
				"exemplar_id": exemplar_id,
				"source_graph_hash": String(description.get("source_graph_hash", "")),
				"render_description_hash": String(description.get("render_description_hash", "")),
				"geometry_hash": geometry_hash,
			})
			hash_tokens.append("POP|%s|%s|%.9f|%d|%s|%s" % [
				patch_id,
				population_id,
				biomass_kg,
				visual_count,
				exemplar_id,
				geometry_hash,
			])
			population_index += 1

	_ph5_projection_hash = "\n".join(hash_tokens).sha256_text()


func _remove_vis1_2_population_glyphs(projection: Node3D) -> void:
	for patch_variant in Array(_spatial_snapshot.get("patches", [])):
		if typeof(patch_variant) != TYPE_DICTIONARY:
			continue
		var patch_id := String(Dictionary(patch_variant).get("id", ""))
		var patch_root := projection.get_node_or_null("Patch_%s" % patch_id) as Node3D
		if patch_root == null:
			continue
		for child in patch_root.get_children():
			if String(child.name).begins_with("Population_"):
				child.free()


func _create_ph5_plant_instance(
	patch_id: String,
	population_id: String,
	population_index: int,
	instance_index: int,
	visual_count: int,
	biomass_kg: float,
	materialization: Dictionary,
	patch_center: Vector3
) -> Node3D:
	var instance := Node3D.new()
	instance.name = "Plant_%02d" % instance_index
	var key := "%s/%s/%d/%d" % [patch_id, population_id, population_index, instance_index]
	var angle := TAU * _unit(key + "/angle")
	var radial_min := 3.5 + 2.5 * float(population_index)
	var radial_max := maxf(radial_min + 0.5, PATCH_VISUAL_RADIUS_M - 1.5 * float(population_index))
	var radius := lerpf(radial_min, radial_max, sqrt(_unit(key + "/radius")))
	var local_x := cos(angle) * radius
	var local_z := sin(angle) * radius
	var world_x := patch_center.x + local_x
	var world_z := patch_center.z + local_z
	var local_ground := sample_terrain_height(world_x, world_z) - patch_center.y
	instance.position = Vector3(local_x, local_ground + 0.32, local_z)
	instance.rotation.y = TAU * _unit(key + "/yaw")
	var biomass_per_visual := biomass_kg / maxf(1.0, float(visual_count))
	var scale_factor := clampf(PLANT_SCALE_MIN + sqrt(biomass_per_visual) * 0.55, PLANT_SCALE_MIN, PLANT_SCALE_MAX)
	instance.scale = Vector3.ONE * scale_factor

	var branch_mesh: ArrayMesh = materialization.get("branch_mesh") as ArrayMesh
	if branch_mesh != null:
		var branches := MeshInstance3D.new()
		branches.name = "Branches"
		branches.mesh = branch_mesh
		branches.material_override = _branch_material(population_id)
		instance.add_child(branches)

	var foliage_multimesh: MultiMesh = materialization.get("foliage_multimesh") as MultiMesh
	if foliage_multimesh != null:
		var foliage := MultiMeshInstance3D.new()
		foliage.name = "Foliage"
		foliage.multimesh = foliage_multimesh
		foliage.material_override = _foliage_material(population_id)
		instance.add_child(foliage)
	return instance


func _branch_material(population_id: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.22, 0.11) if population_id == "alpha" else Color(0.26, 0.18, 0.10)
	material.roughness = 0.88
	return material


func _foliage_material(population_id: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.74, 0.28) if population_id == "alpha" else Color(0.16, 0.55, 0.30)
	material.roughness = 0.82
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _instance_hash_token(patch_id: String, population_id: String, instance_index: int, instance: Node3D) -> String:
	return "I|%s|%s|%d|%.9f,%.9f,%.9f|%.9f|%.9f" % [
		patch_id,
		population_id,
		instance_index,
		instance.position.x,
		instance.position.y,
		instance.position.z,
		instance.rotation.y,
		instance.scale.x,
	]


func _unit(key: String) -> float:
	var digest := (String(_spatial_snapshot.get("snapshot_hash", "")) + "|" + key).sha256_text()
	return float(digest.substr(0, 12).hex_to_int()) / 281474976710655.0


func _update_status() -> void:
	super._update_status()
	var status := get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	if status == null:
		return
	var hash_preview := _ph5_projection_hash.substr(0, 12) if _ph5_projection_hash.length() == 64 else "pending"
	status.text += "\nPH5=ACTIVE profile=%s | visual_plants=%d | branch_vertices=%d | foliage=%d | projection=%s | presentation exemplars alpha=SUN beta=SHADE" % [
		PH5_PROFILE_ID,
		_ph5_instance_count,
		_ph5_branch_vertex_count,
		_ph5_foliage_instance_count,
		hash_preview,
	]
