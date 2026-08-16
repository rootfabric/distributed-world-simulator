extends RefCounted

const VIS16 = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_bridge.gd")
const STAGE := "ECO.VIS1.8A-R1"
const BIRTH_ANIMATION_SECONDS := 0.45
const DEATH_ANIMATION_SECONDS := 0.55

var preview_root: Node3D = null
var event_root: Node3D = null
var nodes_by_id := {}
var animations := {}
var preview_build_count := 0

var trunk_mesh: CylinderMesh
var canopy_mesh: SphereMesh
var marker_mesh: SphereMesh
var death_mesh: CylinderMesh
var trunk_material: StandardMaterial3D
var birth_material: StandardMaterial3D
var death_material: StandardMaterial3D


func _init() -> void:
	trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.42
	trunk_mesh.bottom_radius = 0.58
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	canopy_mesh = SphereMesh.new()
	canopy_mesh.radius = 1.0
	canopy_mesh.height = 2.0
	canopy_mesh.radial_segments = 8
	canopy_mesh.rings = 5
	marker_mesh = SphereMesh.new()
	marker_mesh.radius = 0.22
	marker_mesh.height = 0.44
	marker_mesh.radial_segments = 6
	marker_mesh.rings = 4
	death_mesh = CylinderMesh.new()
	death_mesh.top_radius = 0.38
	death_mesh.bottom_radius = 0.38
	death_mesh.height = 0.035
	death_mesh.radial_segments = 12
	death_mesh.rings = 1
	trunk_material = StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.22, 0.12, 0.055, 1.0)
	trunk_material.roughness = 0.92
	birth_material = StandardMaterial3D.new()
	birth_material.albedo_color = Color(1.0, 0.84, 0.12, 1.0)
	birth_material.emission_enabled = true
	birth_material.emission = Color(0.85, 0.48, 0.04, 1.0)
	birth_material.emission_energy_multiplier = 1.5
	death_material = StandardMaterial3D.new()
	death_material.albedo_color = Color(0.95, 0.12, 0.08, 0.9)
	death_material.emission_enabled = true
	death_material.emission = Color(0.6, 0.03, 0.02, 1.0)
	death_material.emission_energy_multiplier = 1.2


func clear_preview() -> void:
	animations.clear()
	nodes_by_id.clear()
	if is_instance_valid(preview_root):
		preview_root.visible = false
		preview_root.queue_free()
	preview_root = null
	event_root = null


func show_generation_zero(ph5_root: Node3D) -> void:
	if is_instance_valid(ph5_root):
		ph5_root.visible = true
	clear_preview()


func show_realtime_generation(field: Node, ph5_root: Node3D, generation: int, generation_map: Dictionary) -> Dictionary:
	if is_instance_valid(ph5_root):
		ph5_root.visible = false
	_ensure_preview_root(field)
	_clear_event_markers()
	var desired_records := {}
	var hash_tokens := PackedStringArray([STAGE, "REALTIME_TURNOVER_PROXY_PRESENTATION", "generation=%d" % generation])
	var turnover_tokens := PackedStringArray([STAGE, "generation=%d" % generation])
	var visual_count := 0
	var birth_count := 0
	var death_count := 0
	var survivor_count := 0
	var represented_biomass_kg := 0.0
	var keys := generation_map.keys()
	keys.sort()
	for key_variant in keys:
		var state: Dictionary = generation_map[key_variant]
		var transition: Dictionary = state.get("transition", {})
		for record_variant in Array(state.get("records", [])):
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_variant
			var stable_id := String(record.get("stable_id", ""))
			if stable_id.is_empty():
				continue
			desired_records[stable_id] = record.duplicate(true)
			represented_biomass_kg += float(record.get("represented_biomass_kg", 0.0))
			hash_tokens.append(_record_hash_token(record))
		birth_count += int(transition.get("birth_count", 0))
		death_count += int(transition.get("death_count", 0))
		survivor_count += int(transition.get("survivor_count", 0))
		turnover_tokens.append(String(transition.get("turnover_hash", "")))
		_add_death_markers(field, transition)

	for stable_id_variant in nodes_by_id.keys():
		var stable_id := String(stable_id_variant)
		if desired_records.has(stable_id):
			continue
		var node := nodes_by_id.get(stable_id) as Node3D
		if is_instance_valid(node):
			animations[stable_id] = {
				"node": node,
				"mode": "DEATH",
				"elapsed": 0.0,
				"duration": DEATH_ANIMATION_SECONDS,
				"start_scale": node.scale,
			}

	for stable_id_variant in desired_records.keys():
		var stable_id := String(stable_id_variant)
		var record: Dictionary = desired_records[stable_id_variant]
		var node := nodes_by_id.get(stable_id) as Node3D
		var is_new := not is_instance_valid(node)
		if is_new:
			node = _create_proxy(record)
			nodes_by_id[stable_id] = node
			preview_root.add_child(node)
		_update_proxy(field, node, record, generation)
		if is_new and int(record.get("birth_generation", -1)) == generation:
			var target_scale := node.scale
			node.scale = target_scale * 0.12
			animations[stable_id] = {
				"node": node,
				"mode": "BIRTH",
				"elapsed": 0.0,
				"duration": BIRTH_ANIMATION_SECONDS,
				"target_scale": target_scale,
			}
		visual_count += 1

	preview_build_count += 1
	return {
		"visual_count": visual_count,
		"birth_count": birth_count,
		"death_count": death_count,
		"survivor_count": survivor_count,
		"represented_biomass_kg": represented_biomass_kg,
		"field_hash": "\n".join(hash_tokens).sha256_text(),
		"turnover_hash": "\n".join(turnover_tokens).sha256_text(),
		"active_animations": animations.size(),
		"preview_build_count": preview_build_count,
	}


func advance_animations(delta: float) -> void:
	if animations.is_empty():
		return
	var finished: Array[String] = []
	for stable_id_variant in animations.keys():
		var stable_id := String(stable_id_variant)
		var animation: Dictionary = animations[stable_id_variant]
		var node := animation.get("node") as Node3D
		if not is_instance_valid(node):
			finished.append(stable_id)
			continue
		var elapsed := float(animation.get("elapsed", 0.0)) + delta
		var duration := maxf(0.001, float(animation.get("duration", 0.4)))
		var t := clampf(elapsed / duration, 0.0, 1.0)
		animation["elapsed"] = elapsed
		if String(animation.get("mode", "")) == "BIRTH":
			var target_scale: Vector3 = animation.get("target_scale", Vector3.ONE)
			var eased := 1.0 - pow(1.0 - t, 3.0)
			node.scale = target_scale * lerpf(0.12, 1.0, eased)
		else:
			var start_scale: Vector3 = animation.get("start_scale", Vector3.ONE)
			node.scale = start_scale * lerpf(1.0, 0.04, t * t)
		if t >= 1.0:
			if String(animation.get("mode", "")) == "DEATH":
				node.queue_free()
				nodes_by_id.erase(stable_id)
			else:
				node.scale = Vector3.ONE
			finished.append(stable_id)
		else:
			animations[stable_id] = animation
	for stable_id in finished:
		animations.erase(stable_id)


func _ensure_preview_root(field: Node) -> void:
	if is_instance_valid(preview_root):
		preview_root.visible = true
		return
	var projection := field.get_node_or_null("SpatialEcologyProjection") as Node3D
	if projection == null:
		return
	preview_root = Node3D.new()
	preview_root.name = "VIS18RealtimePreview"
	projection.add_child(preview_root)
	event_root = Node3D.new()
	event_root.name = "VIS18RealtimeEvents"
	preview_root.add_child(event_root)


func _clear_event_markers() -> void:
	if not is_instance_valid(event_root):
		return
	for child in event_root.get_children():
		child.queue_free()


func _create_proxy(record: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Turnover_%s" % String(record.get("stable_id", "")).sha256_text().substr(0, 10)
	root.set_meta("stable_id", String(record.get("stable_id", "")))
	root.set_meta("realtime_turnover_proxy", true)
	root.set_meta("canonical_population_truth", false)
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	trunk.mesh = trunk_mesh
	trunk.material_override = trunk_material
	root.add_child(trunk)
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = canopy_mesh
	root.add_child(canopy)
	var birth_marker := MeshInstance3D.new()
	birth_marker.name = "BirthMarker"
	birth_marker.mesh = marker_mesh
	birth_marker.material_override = birth_material
	birth_marker.position = Vector3(0.0, 0.24, 0.0)
	root.add_child(birth_marker)
	return root


func _update_proxy(field: Node, node: Node3D, record: Dictionary, generation: int) -> void:
	var world_x := float(record.get("world_x", 0.0))
	var world_z := float(record.get("world_z", 0.0))
	var ground := float(field.call("sample_terrain_height", world_x, world_z))
	node.position = Vector3(world_x, ground + 0.03, world_z)
	node.rotation.y = float(record.get("rotation_y", 0.0))
	for key in ["stable_id", "parent_stable_id", "birth_generation", "age_generations", "population_id", "current_fitness"]:
		node.set_meta(key, record.get(key))
	var genome: Dictionary = record.get("genome", {})
	var population_id := String(record.get("population_id", ""))
	var environment: Dictionary = field.call("sample_environment_at", world_x, world_z)
	var traits := VIS16.development_traits_from_genome(genome, population_id)
	var sunlight := clampf(float(environment.get("sunlight", 0.5)), 0.0, 1.0)
	var moisture := clampf(float(environment.get("soil_moisture", 0.5)), 0.0, 1.0)
	var flood := clampf(float(environment.get("flood_frequency", 0.0)), 0.0, 1.0)
	var max_height := maxf(0.8, float(traits.get("max_height_m", 3.0)))
	var crown_spread := maxf(0.35, float(traits.get("crown_spread_m", 1.0)))
	var height := clampf(max_height * (0.58 + 0.42 * sunlight) * (0.68 + 0.32 * moisture) * (1.0 - 0.18 * flood), 0.8, 8.0)
	var crown := clampf(crown_spread * (0.72 + 0.28 * moisture), 0.32, 2.6)
	var represented := maxf(0.001, float(record.get("represented_biomass_kg", 0.001)))
	var biomass_scale := clampf(0.72 + sqrt(represented) * 0.32, 0.72, 1.35)
	height *= biomass_scale
	crown *= biomass_scale
	var trunk_radius := clampf(0.055 + height * 0.018, 0.07, 0.22)
	var trunk := node.get_node_or_null("Trunk") as MeshInstance3D
	if trunk != null:
		trunk.position = Vector3(0.0, height * 0.5, 0.0)
		trunk.scale = Vector3(trunk_radius, height, trunk_radius)
	var canopy := node.get_node_or_null("Canopy") as MeshInstance3D
	if canopy != null:
		canopy.position = Vector3(0.0, height * 0.78, 0.0)
		canopy.scale = Vector3(crown, maxf(0.28, crown * 0.72), crown)
		canopy.material_override = field.call("_lod_proxy_material", population_id, 0.94) as Material
	var birth_marker := node.get_node_or_null("BirthMarker") as MeshInstance3D
	if birth_marker != null:
		birth_marker.visible = int(record.get("birth_generation", -1)) == generation and generation > 0
	node.scale = Vector3.ONE


func _add_death_markers(field: Node, transition: Dictionary) -> void:
	if not is_instance_valid(event_root):
		return
	for death_variant in Array(transition.get("deaths", [])):
		if typeof(death_variant) != TYPE_DICTIONARY:
			continue
		var death: Dictionary = death_variant
		var world_x := float(death.get("world_x", 0.0))
		var world_z := float(death.get("world_z", 0.0))
		var marker := MeshInstance3D.new()
		marker.name = "Death_%s" % String(death.get("stable_id", "")).sha256_text().substr(0, 8)
		marker.mesh = death_mesh
		marker.material_override = death_material
		marker.position = Vector3(world_x, float(field.call("sample_terrain_height", world_x, world_z)) + 0.05, world_z)
		marker.set_meta("death_marker", true)
		event_root.add_child(marker)


static func _record_hash_token(record: Dictionary) -> String:
	return "%s|%s|%.9f|%.9f|g=%d|age=%d" % [
		String(record.get("stable_id", "")),
		String(record.get("parent_stable_id", "")),
		float(record.get("world_x", 0.0)),
		float(record.get("world_z", 0.0)),
		int(record.get("birth_generation", 0)),
		int(record.get("age_generations", 0)),
	]
