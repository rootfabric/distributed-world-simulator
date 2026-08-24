extends Node3D

## ECO.EVO7 FFF6 - Closed Community Evolution / Succession Lab (spec sections
## 14, 15, 17 Experiment A, 19 FFF6; design doc
## docs/plans/ECO_EVO7_FFF6_SUCCESSION_LAB_DESIGN_RU.md).
##
## Six controlled zones (FLOODED / RIPARIAN / MESIC_LOAM / DRY_SAND /
## UNDER_CANOPY / CANOPY_GAP) run the SAME succession simulation
## (evo7_succession_simulation_v1) - this node is a READ-ONLY observer: it never
## writes genomes, phenotypes or environment authority, adds no second mutation
## path, and every ecological hash comes from the shared non-node module.
##
## Visual truth boundary (G15): evolving plants are materialized through the real
## PH5 pipeline CoupledDevelopment.realize -> growth_graph ->
## PlantRenderDescription.build -> MultiScaleRepresentation.build ->
## MultiscaleMaterializer.build using Simulation.realize_entry - the SAME
## realization that fed the fields. Presentation state (C-mode neutral material,
## overlays 1-5, tier choice, X canopy toggle) changes NO hash: the hash panel is
## untouched by any of these keys. Lab encoders (root rod, shadow disc,
## transpiration marker) are presentation geometry proportional to realized
## phenotype values (EVO6 house pattern); the static canopy ring renders from the
## same frozen constants its light records use.
##
## Controls (spec section 15.1 + design-doc debug key):
##   SPACE initial/final | F feedback ON/OFF | C neutral material |
##   1 light / 2 soil moisture / 3 shade / 4 transpiration / 5 fitness overlays |
##   R deterministic reset | X manual canopy removal (CANOPY_GAP counterfactual)
##
## Headless acceptance: EVO7_FFF6_LAB_AUTOCAP=1 runs the simulation + stability +
## replay checks and prints a machine-checkable verdict, then quit(0/1).

const Simulation = preload("res://scripts/research/ecology/evo7_succession_simulation_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const MultiscaleMaterializer = preload("res://scripts/research/ecology/plant_multiscale_materializer_v1.gd")
const LightField = preload("res://scripts/research/ecology/understory_light_field_v1.gd")

const SEED := 20260823
const PLOT_SPACING := 17.0
const ZONE_ROW_SPACING := 19.0
const CAMERA_SPEED := 14.0
const MOUSE_SENSITIVITY := 0.003

## Presentation-only magnification of the microcosm grid (ecological spacing
## stays 0.35 m inside the module; visuals are scaled so crown structure reads
## at zone distance). Never enters any hash.
const DISPLAY_SCALE := 3.0

var _cam: Camera3D
var _yaw := 0.0
var _pitch := -0.42
var _context: Dictionary = {}
var _result: Dictionary = {}
var _simulating := true
var _sim_step := 0
var _view_final := true
var _feedback_on := true
var _neutral_materials := false
var _active_overlay := 0
var _manual_canopy_removed := false
var _last_full_panel := ""
var _replay_match := true

var _zone_roots: Dictionary = {}
var _canopy_rings: Dictionary = {}
var _overlay_grids: Dictionary = {}
var _plant_root: Node3D
var _plant_cache: Array[Dictionary] = []
var _rendered_plants := 0
var _neutral_material: StandardMaterial3D

var _stats_label: Label
var _geometry_label: Label
var _hash_label: Label
var _help_label: Label


func _ready() -> void:
	_build_static_world()
	_setup_camera()
	_setup_hud()
	_start_simulation()


func _start_simulation() -> void:
	_context = Simulation.create_context(SEED)
	_result = {}
	_simulating = true
	_sim_step = 0
	_clear_plants()
	_run_simulation_steps()


func _run_simulation_steps() -> void:
	while true:
		_update_phase_hud()
		await get_tree().process_frame
		if Simulation.context_step(_context):
			break
		_sim_step += 1
	_result = Simulation.context_finish(_context)
	if _result.is_empty():
		push_error("ECO.EVO7-FFF6-VIS: succession simulation returned empty result")
		get_tree().quit(1)
		return
	_simulating = false
	_rebuild_all()
	print("ECO.EVO7-FFF6-VIS: READY zones=%d plants=%d result_hash=%s" % [
		Simulation.ZONE_ORDER.size(), _rendered_plants, String(_result.get("result_hash", ""))])
	if OS.get_environment("EVO7_FFF6_LAB_AUTOCAP") == "1":
		await get_tree().process_frame
		_autocap()


## ------------------------------------------------------------------ world --

func _build_static_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun.light_energy = 1.25
	add_child(sun)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.50, 0.57, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.82)
	env.ambient_light_energy = 0.85
	world_env.environment = env
	add_child(world_env)

	for index in range(Simulation.ZONE_ORDER.size()):
		_build_zone(String(Simulation.ZONE_ORDER[index]), index)

	_plant_root = Node3D.new()
	_plant_root.name = "Plants"
	add_child(_plant_root)


func _build_zone(zone_name: String, index: int) -> void:
	var origin := _zone_origin(index)
	var zone_root := Node3D.new()
	zone_root.name = "Zone_%s" % zone_name
	add_child(zone_root)
	_zone_roots[zone_name] = zone_root

	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(14.0, 0.35, 8.0)
	ground.mesh = ground_mesh
	ground.position = origin + Vector3(0.0, 1.8, 0.0)
	ground.material_override = _flat_material(_zone_color(zone_name))
	zone_root.add_child(ground)

	var parameters := Simulation.zone_parameters(zone_name)
	if String(parameters["texture"]) == "clay" or float(parameters["flood_frequency"]) >= 0.30:
		var water := MeshInstance3D.new()
		var water_mesh := BoxMesh.new()
		water_mesh.size = Vector3(14.2, 0.16, 8.2)
		water.mesh = water_mesh
		water.position = origin + Vector3(0.0, 2.08, 0.0)
		water.material_override = _flat_material(Color(0.18, 0.48, 0.72, 0.75), true)
		zone_root.add_child(water)
	elif String(parameters["texture"]) == "sand":
		var channel := MeshInstance3D.new()
		var channel_mesh := BoxMesh.new()
		channel_mesh.size = Vector3(2.4, 0.12, 8.2)
		channel.mesh = channel_mesh
		channel.position = origin + Vector3(-5.5, 2.02, 0.0)
		channel.material_override = _flat_material(Color(0.72, 0.62, 0.40))
		zone_root.add_child(channel)

	var title := Label3D.new()
	title.text = zone_name
	title.font_size = 44
	title.outline_size = 8
	title.position = origin + Vector3(0.0, 9.6, -3.7)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	zone_root.add_child(title)

	_overlay_grids[zone_name] = _build_overlay_grid(zone_name, origin)

	if bool(parameters["canopy"]):
		_canopy_rings[zone_name] = _build_canopy_ring(zone_name, origin)


func _build_overlay_grid(zone_name: String, origin: Vector3) -> Dictionary:
	var grid := Node3D.new()
	grid.name = "OverlayGrid"
	grid.visible = false
	_zone_roots[zone_name].add_child(grid)
	var quads := {}
	var labels := {}
	for ix in range(-1, 1):
		for iz in range(-1, 1):
			var cell_id := "%d|%d" % [ix, iz]
			var center := Vector3((float(ix) + 0.5) * DISPLAY_SCALE, 0.0, (float(iz) + 0.5) * DISPLAY_SCALE)
			var quad := MeshInstance3D.new()
			var quad_mesh := PlaneMesh.new()
			quad_mesh.size = Vector2(DISPLAY_SCALE * 0.96, DISPLAY_SCALE * 0.96)
			quad.mesh = quad_mesh
			quad.position = origin + center + Vector3(0.0, 2.02, 0.0)
			var quad_material := StandardMaterial3D.new()
			quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			quad_material.albedo_color = Color(0.2, 0.2, 0.2, 0.45)
			quad.material_override = quad_material
			grid.add_child(quad)
			quads[cell_id] = quad_material
			var label := Label3D.new()
			label.font_size = 26
			label.outline_size = 6
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.position = origin + center + Vector3(0.0, 2.85, 0.0)
			grid.add_child(label)
			labels[cell_id] = label
	return {"node": grid, "quads": quads, "labels": labels}


## Static canopy ring rendered from the SAME frozen constants its light records
## use (Simulation.canopy_records): one trunk + two crown discs per record.
func _build_canopy_ring(zone_name: String, origin: Vector3) -> Node3D:
	var ring := Node3D.new()
	ring.name = "CanopyRing"
	ring.visible = not (_manual_canopy_removed and zone_name == "CANOPY_GAP")
	_zone_roots[zone_name].add_child(ring)
	_canopy_rings[zone_name] = ring
	for record in Simulation.canopy_records():
		var base_y := 2.15
		var height := float(record["realized_height_m"])
		var holder := Node3D.new()
		holder.name = String(record["identity"])
		holder.position = origin + Vector3(
			float(record["world_x_m"]) * DISPLAY_SCALE, base_y, float(record["world_z_m"]) * DISPLAY_SCALE)
		ring.add_child(holder)
		var trunk := MeshInstance3D.new()
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.10
		trunk_mesh.bottom_radius = 0.22
		trunk_mesh.height = height * DISPLAY_SCALE
		trunk.mesh = trunk_mesh
		trunk.position.y = trunk_mesh.height * 0.5
		var trunk_material := StandardMaterial3D.new()
		trunk_material.albedo_color = Color(0.30, 0.20, 0.11)
		trunk.material_override = trunk_material
		holder.add_child(trunk)
		for crown_index in range(2):
			var crown := MeshInstance3D.new()
			var crown_mesh := SphereMesh.new()
			crown_mesh.radius = float(record["realized_crown_radius_m"]) * DISPLAY_SCALE * (0.55 if crown_index == 0 else 0.38)
			crown_mesh.height = crown_mesh.radius * 1.1
			crown.mesh = crown_mesh
			crown.position.y = height * DISPLAY_SCALE * (0.86 if crown_index == 0 else 1.02)
			var crown_material := StandardMaterial3D.new()
			crown_material.albedo_color = Color(0.14, 0.36, 0.16)
			crown.material_override = crown_material
			holder.add_child(crown)
	return ring


## ------------------------------------------------------------- rendering --

func _rebuild_all() -> void:
	_render_populations()
	_refresh_overlays()
	_update_hud()


func _clear_plants() -> void:
	if _plant_root != null:
		for child in _plant_root.get_children():
			child.free()
	_rendered_plants = 0
	_plant_cache.clear()


func _displayed_mode_key() -> String:
	return "feedback_on" if _feedback_on else "feedback_off"


func _render_populations() -> void:
	if _result.is_empty() or _plant_root == null:
		return
	_clear_plants()

	var ancestor: Dictionary = _ancestor_for_display()
	for zone_index in range(Simulation.ZONE_ORDER.size()):
		var zone_name := String(Simulation.ZONE_ORDER[zone_index])
		var zone_origin := _zone_origin(zone_index)
		var base_env := Simulation.base_environment(zone_name)
		if base_env.is_empty():
			continue
		var entries: Array = []
		if _view_final:
			var mode_result: Dictionary = _result["zones"][zone_name][_displayed_mode_key()]
			for entry in mode_result["final_population"]:
				entries.append(entry)
		else:
			for position in Simulation.grid_positions():
				entries.append({
					"identity": String(position["identity"]),
					"world_x_m": float(position["world_x_m"]),
					"world_z_m": float(position["world_z_m"]),
					"bundle": ancestor,
				})
		var tier := _tier_for_zone(zone_index)
		for entry in entries:
			_materialize_plant(zone_name, zone_origin, entry, base_env, tier)


func _ancestor_for_display() -> Dictionary:
	# Initial view shows the shared generation-one ancestor pool; every final
	# bundle descends from it, so re-derive the ancestor deterministically.
	var lineage_seed := SEED
	if not _result.is_empty():
		lineage_seed = int(_result["lineage_seed"])
	return Simulation.default_ancestor_bundle(lineage_seed)


## Real PH5 pipeline for one community entry, plus presentation encoders.
func _materialize_plant(zone_name: String, zone_origin: Vector3, entry: Dictionary, base_env: Dictionary, tier: String) -> void:
	var identity := String(entry["identity"])
	var realized := Simulation.realize_entry(entry["bundle"], identity, base_env)
	if realized.is_empty():
		push_warning("ECO.EVO7-FFF6-VIS: realization failed for %s/%s" % [zone_name, identity])
		return
	var fp: Dictionary = realized["phenotype"]
	var description := RenderDescription.build(realized["growth_graph"])
	if description.is_empty():
		return
	var representation := Representation.build(description, tier)
	var materialization := MultiscaleMaterializer.build(description, representation)
	if not bool(materialization.get("success", false)):
		return

	var holder := Node3D.new()
	holder.name = "%s_%s" % [zone_name, identity]
	holder.position = zone_origin + Vector3(
		float(entry["world_x_m"]) * DISPLAY_SCALE, 2.15, float(entry["world_z_m"]) * DISPLAY_SCALE)
	_plant_root.add_child(holder)

	var mesh_nodes: Array = []
	var branch_mesh: Mesh = materialization.get("branch_mesh")
	if branch_mesh != null:
		var branches := MeshInstance3D.new()
		branches.name = "branch_mesh"
		branches.mesh = branch_mesh
		holder.add_child(branches)
		mesh_nodes.append(branches)
	var foliage: MultiMesh = materialization.get("foliage_multimesh")
	if foliage != null:
		var leaves := MultiMeshInstance3D.new()
		leaves.name = "foliage_multimesh"
		leaves.multimesh = foliage
		holder.add_child(leaves)
		mesh_nodes.append(leaves)
	var far_mesh: Mesh = materialization.get("far_mesh")
	if far_mesh != null:
		var far_instance := MeshInstance3D.new()
		far_instance.name = "far_mesh"
		far_instance.mesh = far_mesh
		far_instance.position = materialization.get("origin", Vector3.ZERO)
		holder.add_child(far_instance)
		mesh_nodes.append(far_instance)

	var trunk_height := maxf(float(fp["realized_height_m"]), 0.05) * DISPLAY_SCALE
	var trunk_color := Color(0.33, 0.22, 0.12).lightened(float(fp["structural_investment"]) * 0.18)
	var leaf_color := Color(0.13, 0.42 + 0.18 * float(fp["leaf_conservative_strategy"]), 0.18)
	for node in mesh_nodes:
		var material := StandardMaterial3D.new()
		material.albedo_color = trunk_color if node.name == "branch_mesh" else leaf_color
		material.roughness = 0.88
		node.material_override = material

	# Root encoder (EVO6 pattern): visible downward rod, length ∝ root depth.
	var root_depth := float(fp["realized_root_depth_m"])
	var root_rod := MeshInstance3D.new()
	var rod_mesh := CylinderMesh.new()
	rod_mesh.top_radius = 0.06
	rod_mesh.bottom_radius = 0.11
	rod_mesh.height = clampf(root_depth * DISPLAY_SCALE * 0.8, 0.25, 7.0)
	root_rod.mesh = rod_mesh
	root_rod.position.y = -rod_mesh.height * 0.5
	var rod_material := StandardMaterial3D.new()
	rod_material.albedo_color = Color(0.27, 0.16, 0.09)
	root_rod.material_override = rod_material
	holder.add_child(root_rod)
	mesh_nodes.append(root_rod)

	# Overlay-3 target: shadow disc under the crown, intensity ∝ shade output.
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = maxf(float(fp["realized_crown_radius_m"]) * DISPLAY_SCALE, 0.3)
	disc_mesh.bottom_radius = disc_mesh.top_radius
	disc_mesh.height = 0.03
	disc.mesh = disc_mesh
	disc.position.y = -(2.15 - 2.03)
	disc.set_meta("fff6_overlay_role", 3)
	var disc_material := StandardMaterial3D.new()
	disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_material.albedo_color = Color(0.05, 0.05, 0.08, clampf(float(fp["shade_output_ppm"]) / 90000.0, 0.12, 0.85))
	disc.material_override = disc_material
	disc.visible = _active_overlay == 3
	holder.add_child(disc)
	mesh_nodes.append(disc)

	# Overlay-4 target: transpiration marker above the crown.
	var marker := MeshInstance3D.new()
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.09
	marker_mesh.bottom_radius = 0.09
	marker_mesh.height = clampf(0.6 + 3.2 * float(fp["transpiration_demand_ppm"]) / 150000.0, 0.6, 5.0)
	marker.mesh = marker_mesh
	marker.position.y = trunk_height + marker_mesh.height * 0.5 + 0.25
	marker.set_meta("fff6_overlay_role", 4)
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(0.16, 0.62, 0.78)
	marker.material_override = marker_material
	marker.visible = _active_overlay == 4
	holder.add_child(marker)
	mesh_nodes.append(marker)

	# Overlay-5 target: fitness components label.
	var fitness_label := Label3D.new()
	fitness_label.text = "g%.3f c%.3f n%.3f" % [
		float(fp["photosynthetic_gain_proxy"]), float(fp["maintenance_cost_proxy"]), float(fp["net_resource_proxy"])]
	fitness_label.font_size = 22
	fitness_label.outline_size = 5
	fitness_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fitness_label.position.y = trunk_height + 1.1
	fitness_label.set_meta("fff6_overlay_role", 5)
	fitness_label.visible = _active_overlay == 5
	holder.add_child(fitness_label)
	mesh_nodes.append(fitness_label)

	if _neutral_materials:
		_apply_neutral(mesh_nodes)

	var features := {}
	for field_name in Simulation.FEATURE_FIELDS:
		features[field_name] = float(fp[field_name])
	_plant_cache.append({
		"zone": zone_name,
		"identity": identity,
		"x": float(entry["world_x_m"]),
		"z": float(entry["world_z_m"]),
		"features": features,
		"crown_radius": float(fp["realized_crown_radius_m"]),
		"density": float(fp["realized_crown_density"]),
		"lai": float(fp["leaf_area_index_proxy"]),
		"shade_ppm": int(fp["shade_output_ppm"]),
		"transpiration_ppm": int(fp["transpiration_demand_ppm"]),
		"gain": float(fp["photosynthetic_gain_proxy"]),
		"cost": float(fp["maintenance_cost_proxy"]),
		"net": float(fp["net_resource_proxy"]),
		"water_preference": float(entry["bundle"]["genome"].get("water_preference", 0.5)),
		"checksum": String(entry["bundle"]["bundle_checksum"]),
		"phenotype_hash": String(fp["phenotype_hash"]),
		"meshes": mesh_nodes,
	})
	_rendered_plants += 1


func _apply_neutral(mesh_nodes: Array) -> void:
	if _neutral_material == null:
		_neutral_material = StandardMaterial3D.new()
		_neutral_material.albedo_color = Color(0.58, 0.58, 0.58)
		_neutral_material.roughness = 0.9
	for node in mesh_nodes:
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			node.material_override = _neutral_material
		elif node is Label3D:
			node.modulate = Color(0.6, 0.6, 0.6)


func _restore_materials(mesh_nodes: Array) -> void:
	for node in mesh_nodes:
		if node is Label3D:
			node.modulate = Color.WHITE


## Tier by estimated projected height at spawn distance; floored at
## TIER_1_REDUCED so G5 geometry stays readable in every zone.
func _tier_for_zone(zone_index: int) -> String:
	var camera_distance := 26.0
	if _cam != null:
		camera_distance = _cam.global_position.distance_to(_zone_origin(zone_index))
	var estimated_px := 3.2 * 900.0 / maxf(camera_distance, 1.0)
	var tier := Representation.select_tier(estimated_px)
	if tier in [Representation.TIER_2_CANOPY, Representation.TIER_3_IMPOSTOR, Representation.TIER_4_POPULATION_ONLY]:
		return Representation.TIER_1_REDUCED
	return tier


## --------------------------------------------------------------- overlays --

## Overlay state: quads 1-2 recompute from stored research data; discs (3),
## markers (4) and fitness labels (5) toggle visibility directly.
func _refresh_overlays() -> void:
	for zone_name in _overlay_grids.keys():
		var grid: Dictionary = _overlay_grids[zone_name]
		var overlay_node: Node3D = grid["node"]
		overlay_node.visible = _active_overlay == 1 or _active_overlay == 2
		if _active_overlay == 1:
			_fill_light_overlay(zone_name, grid)
		elif _active_overlay == 2:
			_fill_moisture_overlay(zone_name, grid)
	for cached in _plant_cache:
		for node in cached["meshes"]:
			if node.has_meta("fff6_overlay_role"):
				match int(node.get_meta("fff6_overlay_role")):
					3: node.visible = _active_overlay == 3
					4: node.visible = _active_overlay == 4
					5: node.visible = _active_overlay == 5


func _displayed_records(zone_name: String) -> Array:
	var parameters := Simulation.zone_parameters(zone_name)
	var base_sunlight := float(parameters.get("sunlight", 0.85))
	var records: Array = []
	for cached in _plant_cache:
		if String(cached["zone"]) != zone_name:
			continue
		records.append({
			"identity": String(cached["identity"]),
			"world_x_m": float(cached["x"]),
			"world_z_m": float(cached["z"]),
			"realized_height_m": float(cached["features"]["realized_height_m"]),
			"realized_crown_radius_m": float(cached["crown_radius"]),
			"realized_crown_density": float(cached["density"]),
			"leaf_area_index_proxy": float(cached["lai"]),
			"base_sunlight": base_sunlight,
			"shade_output_ppm": int(cached["shade_ppm"]),
			"source_phenotype_hash": String(cached["phenotype_hash"]),
		})
	return records


func _canopy_active_for_view(zone_name: String) -> bool:
	var parameters: Dictionary = Simulation.zone_parameters(zone_name)
	if not bool(parameters.get("canopy", false)):
		return false
	if zone_name == "CANOPY_GAP":
		return not (_manual_canopy_removed or _gap_removal_in_result())
	return true


func _gap_removal_in_result() -> bool:
	if _result.is_empty() or not _view_final:
		return false
	var gap: Dictionary = _result["zones"]["CANOPY_GAP"][_displayed_mode_key()]
	return not bool(gap.get("canopy_present_at_end", true))


func _fill_light_overlay(zone_name: String, grid: Dictionary) -> void:
	var records := _displayed_records(zone_name)
	if records.is_empty():
		return
	var light_records := records.duplicate()
	if _canopy_active_for_view(zone_name):
		light_records.append_array(Simulation.canopy_records())
	var field := LightField.compute(light_records)
	if field.is_empty():
		return
	var sums := {}
	var counts := {}
	for identity in field["plant_light"].keys():
		if not String(identity).begins_with("p"):
			continue
		var cell_id := String(field["plant_light"][identity]["cell_identity"])
		sums[cell_id] = float(sums.get(cell_id, 0.0)) + float(field["plant_light"][identity]["understory_light"])
		counts[cell_id] = int(counts.get(cell_id, 0)) + 1
	for cell_id in grid["quads"].keys():
		var value := 0.0
		if counts.has(cell_id):
			value = float(sums[cell_id]) / float(counts[cell_id])
		var material: StandardMaterial3D = grid["quads"][cell_id]
		material.albedo_color = Color(0.08, 0.08, 0.22).lerp(Color(0.95, 0.90, 0.35), clampf(value, 0.0, 1.0)).darkened(0.25)
		var label: Label3D = grid["labels"][cell_id]
		label.text = "%.2f" % value
		label.visible = true


func _fill_moisture_overlay(zone_name: String, grid: Dictionary) -> void:
	var moisture := {}
	if not _result.is_empty() and _view_final and _feedback_on:
		moisture = _result["zones"][zone_name][_displayed_mode_key()].get("final_cell_moisture", {})
	for cell_id in grid["quads"].keys():
		var value := float(moisture.get(cell_id, Simulation.zone_parameters(zone_name)["soil_moisture"]))
		var material: StandardMaterial3D = grid["quads"][cell_id]
		material.albedo_color = Color(0.85, 0.62, 0.30).lerp(Color(0.15, 0.35, 0.80), clampf(value, 0.0, 1.0)).darkened(0.2)
		var label: Label3D = grid["labels"][cell_id]
		label.text = "%.2f" % value
		label.visible = true


## ------------------------------------------------------------------- HUD --

func _setup_camera() -> void:
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.position = Vector3(0.0, 24.0, 34.0)
	_apply_look()


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_stats_label = Label.new()
	_stats_label.position = Vector2(14, 12)
	_stats_label.add_theme_font_size_override("font_size", 14)
	canvas.add_child(_stats_label)
	_geometry_label = Label.new()
	_geometry_label.position = Vector2(870, 12)
	_geometry_label.add_theme_font_size_override("font_size", 12)
	canvas.add_child(_geometry_label)
	_hash_label = Label.new()
	_hash_label.position = Vector2(14, 430)
	_hash_label.add_theme_font_size_override("font_size", 11)
	canvas.add_child(_hash_label)
	_help_label = Label.new()
	_help_label.position = Vector2(14, 700)
	_help_label.add_theme_font_size_override("font_size", 13)
	canvas.add_child(_help_label)
	_update_phase_hud()


func _update_phase_hud() -> void:
	if _stats_label == null:
		return
	if _simulating:
		var done := _sim_step
		_stats_label.text = "EVO7-FFF6 | SIMULATING zone %d/%d ... (SPACE/F/C/1-5/R/X after READY)" % [
			mini(done + 1, Simulation.ZONE_ORDER.size()), Simulation.ZONE_ORDER.size()]
		_help_label.text = "succession simulation running (deferred steps, no threads)"
		return
	_update_hud()


func _update_hud() -> void:
	if _result.is_empty() or _stats_label == null:
		return
	var phase := "FINAL gen %d" % int(_result["generations"]) if _view_final else "INITIAL gen 1 ancestor pool"
	var mode_tag := "FEEDBACK ON" if _feedback_on else "FEEDBACK OFF (counterfactual)"

	var stats_lines := PackedStringArray([
		"EVO7-FFF6 SUCCESSION LAB | %s | %s | overlay=%d%s" % [
			phase, mode_tag, _active_overlay, " | X-canopy removed" if _manual_canopy_removed else ""],
	])
	for zone_name in Simulation.ZONE_ORDER:
		stats_lines.append("%s: %s" % [zone_name, _zone_stats_line(zone_name)])
	stats_lines.append("bound-pinning max: %s" % _pinning_line())
	_stats_label.text = "\n".join(stats_lines)

	_geometry_label.text = _geometry_readout()
	var panel := _hash_panel()
	_replay_match = _last_full_panel.is_empty() or _last_full_panel == panel
	_hash_label.text = panel + ("\nREPLAY vs previous R: MATCH" if _replay_match else "\nREPLAY vs previous R: MISMATCH")
	_help_label.text = "SPACE initial/final | F feedback ON/OFF | C neutral material | 1 light | 2 moisture | 3 shade | 4 transpiration | 5 fitness | R reset replay | X canopy toggle (GAP) | WASD/QE move | Esc mouse"


func _zone_means(zone_name: String) -> Dictionary:
	var sums := {}
	var count := 0
	for cached in _plant_cache:
		if String(cached["zone"]) != zone_name:
			continue
		count += 1
		for field_name in Simulation.FEATURE_FIELDS:
			sums[field_name] = float(sums.get(field_name, 0.0)) + float(cached["features"][field_name])
	var means := {}
	if count > 0:
		for field_name in sums.keys():
			means[field_name] = snappedf(float(sums[field_name]) / float(count), 1e-6)
	return means


func _zone_stats_line(zone_name: String) -> String:
	var means := _zone_means(zone_name)
	if means.is_empty():
		return "no plants"
	var count := 0
	var unique := {}
	var shade_total := 0.0
	var transp_total := 0.0
	var net_total := 0.0
	var pref_total := 0.0
	for cached in _plant_cache:
		if String(cached["zone"]) != zone_name:
			continue
		count += 1
		unique[String(cached["checksum"])] = true
		shade_total += float(cached["shade_ppm"])
		transp_total += float(cached["transpiration_ppm"])
		net_total += float(cached["net"])
		pref_total += float(cached["water_preference"])
	var pin_text := ""
	if not _result.is_empty() and _view_final:
		var mode_result: Dictionary = _result["zones"][zone_name][_displayed_mode_key()]
		pin_text = " pin=%.2f clusters=%d" % [
			float(mode_result["max_bound_pinning_fraction"]), int(mode_result["morphology_cluster_count"])]
	return ("h=%.2f cr=%.2f lai=%.2f root=%.2f/%.2f pref=%.2f shade=%.0f transp=%.0f net=%.4f uniq=%d%s" % [
		float(means.get("realized_height_m", 0.0)), float(means.get("realized_crown_radius_m", 0.0)),
		float(means.get("leaf_area_index_proxy", 0.0)), float(means.get("realized_root_depth_m", 0.0)),
		float(means.get("realized_root_spread_m", 0.0)),
		snappedf(pref_total / maxf(float(count), 1.0), 1e-4),
		shade_total / maxf(float(count), 1.0), transp_total / maxf(float(count), 1.0),
		net_total / maxf(float(count), 1.0), unique.size(), pin_text])


func _pinning_line() -> String:
	if _result.is_empty() or not _view_final:
		return "n/a (initial view)"
	var parts := PackedStringArray()
	for zone_name in Simulation.ZONE_ORDER:
		var mode_result: Dictionary = _result["zones"][zone_name][_displayed_mode_key()]
		parts.append("%s=%.2f" % [zone_name.substr(0, 6), float(mode_result["max_bound_pinning_fraction"])])
	return " ".join(parts) + " (G11 preview: fraction of population pinned >=99% toward axis bounds)"


func _geometry_readout() -> String:
	var lines := PackedStringArray(["G5 GEOMETRY READOUT (C-mode readable):"])
	var all_means := {}
	for zone_name in Simulation.ZONE_ORDER:
		all_means[zone_name] = _zone_means(zone_name)
		var m: Dictionary = all_means[zone_name]
		if m.is_empty():
			continue
		lines.append("%s h=%.2f cr=%.2f dens=%.2f lai=%.2f rd=%.2f rs=%.2f si=%.2f" % [
			zone_name, float(m["realized_height_m"]), float(m["realized_crown_radius_m"]),
			float(m["realized_crown_density"]), float(m["leaf_area_index_proxy"]),
			float(m["realized_root_depth_m"]), float(m["realized_root_spread_m"]),
			float(m["structural_investment"])])
	var distinct_pairs := 0
	var pair_lines := PackedStringArray()
	for i in range(Simulation.ZONE_ORDER.size()):
		for j in range(i + 1, Simulation.ZONE_ORDER.size()):
			var a := String(Simulation.ZONE_ORDER[i])
			var b := String(Simulation.ZONE_ORDER[j])
			var ma: Dictionary = all_means[a]
			var mb: Dictionary = all_means[b]
			if ma.is_empty() or mb.is_empty():
				continue
			if Simulation.geometry_distinct(ma, mb):
				distinct_pairs += 1
				pair_lines.append("%s|%s" % [a.substr(0, 5), b.substr(0, 5)])
	lines.append("geometry-distinct pairs=%d (>=3 satisfies G5): %s" % [distinct_pairs, ", ".join(pair_lines)])
	return "\n".join(lines)


func _hash_panel() -> String:
	if _result.is_empty():
		return "hashes pending..."
	var lines := PackedStringArray([
		"HASH PANEL seed=%d policy=%s... ancestor=%s..." % [
			int(_result["lineage_seed"]),
			String(_result["evo7_policy_hash"]).substr(0, 12),
			String(_result["ancestor_bundle_checksum"]).substr(0, 12),
		],
		"lab_result_hash=%s common_pool=%s..." % [
			String(_result["result_hash"]).substr(0, 16),
			String(_result["common_first_generation_pool_hash"]).substr(0, 12),
		],
	])
	for zone_name in Simulation.ZONE_ORDER:
		var zone: Dictionary = _result["zones"][zone_name]
		var mode_result: Dictionary = zone[_displayed_mode_key()]
		lines.append("%s[%s]: pool1=%s pop=%s field=%s light=%s fx=%s" % [
			zone_name.substr(0, 6), mode_result["mode"],
			String(mode_result["first_generation_score_hash"]).substr(0, 8),
			String(mode_result["final_population_hash"]).substr(0, 8),
			String(mode_result["final_field_hash"]).substr(0, 8),
			String(mode_result["final_plant_light_hash"]).substr(0, 8),
			String(mode_result["final_effects_combined_hash"]).substr(0, 8),
		])
	return "\n".join(lines)


## ------------------------------------------------------------------ input --

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
		_apply_look()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_SPACE:
				if not _simulating:
					_view_final = not _view_final
					_rebuild_all()
			KEY_F:
				if not _simulating:
					_feedback_on = not _feedback_on
					_rebuild_all()
			KEY_C:
				if not _simulating:
					_neutral_materials = not _neutral_materials
					_apply_neutral_state()
					_update_hud()
			KEY_1:
				_toggle_overlay(1)
			KEY_2:
				_toggle_overlay(2)
			KEY_3:
				_toggle_overlay(3)
			KEY_4:
				_toggle_overlay(4)
			KEY_5:
				_toggle_overlay(5)
			KEY_R:
				if not _simulating:
					_last_full_panel = _hash_panel()
					_manual_canopy_removed = false
					_start_simulation()
			KEY_X:
				if not _simulating:
					_manual_canopy_removed = not _manual_canopy_removed
					_apply_manual_canopy()
					_refresh_overlays()
					_update_hud()


func _toggle_overlay(overlay: int) -> void:
	if _simulating:
		return
	_active_overlay = 0 if _active_overlay == overlay else overlay
	_refresh_overlays()
	_update_hud()


func _apply_neutral_state() -> void:
	if _plant_root == null:
		return
	for cached in _plant_cache:
		if _neutral_materials:
			_apply_neutral(cached["meshes"])
		else:
			_restore_materials(cached["meshes"])


func _apply_manual_canopy() -> void:
	for zone_name in _canopy_rings.keys():
		var ring: Node3D = _canopy_rings[zone_name]
		ring.visible = not (_manual_canopy_removed and zone_name == "CANOPY_GAP")


func _apply_look() -> void:
	if _cam == null:
		return
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)


func _zone_origin(index: int) -> Vector3:
	@warning_ignore("integer_division")
	var col := index % 3
	@warning_ignore("integer_division")
	var row := index / 3
	return Vector3((float(col) - 1.0) * PLOT_SPACING, 0.0, (float(row) - 0.5) * ZONE_ROW_SPACING)


func _zone_color(zone_name: String) -> Color:
	match zone_name:
		"FLOODED": return Color(0.24, 0.35, 0.42)
		"RIPARIAN": return Color(0.34, 0.47, 0.29)
		"MESIC_LOAM": return Color(0.44, 0.42, 0.25)
		"DRY_SAND": return Color(0.64, 0.53, 0.28)
		"UNDER_CANOPY": return Color(0.30, 0.36, 0.24)
		"CANOPY_GAP": return Color(0.47, 0.46, 0.27)
		_: return Color(0.42, 0.42, 0.42)


func _flat_material(color: Color, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _process(delta: float) -> void:
	if _cam == null:
		return
	var move := Vector3.ZERO
	var basis := _cam.global_transform.basis
	if Input.is_key_pressed(KEY_W): move -= basis.z
	if Input.is_key_pressed(KEY_S): move += basis.z
	if Input.is_key_pressed(KEY_A): move -= basis.x
	if Input.is_key_pressed(KEY_D): move += basis.x
	if Input.is_key_pressed(KEY_Q): move -= Vector3.UP
	if Input.is_key_pressed(KEY_E): move += Vector3.UP
	if move.length_squared() > 0.0:
		_cam.global_position += move.normalized() * CAMERA_SPEED * delta


## --------------------------------------------------------------- autocap --

## Headless acceptance verdict (EVO7_FFF6_LAB_AUTOCAP=1): minimum gate set from
## the work order - six deterministic zones, ON/OFF divergence, gap light
## restoration, >=100-cycle stability without NaN/bound-pinning, replay identity.
func _autocap() -> void:
	var failures: Array[String] = []

	var zones: Dictionary = _result["zones"]
	var zones_ok: bool = zones.size() == Simulation.ZONE_ORDER.size()
	for zone_name in Simulation.ZONE_ORDER:
		var zone: Dictionary = zones.get(zone_name, {})
		zones_ok = zones_ok and not zone.is_empty() \
			and not String(zone.get("initial_field_hash", "")).is_empty() \
			and not String(zone.get("initial_water_field_hash", "")).is_empty()
	if not zones_ok:
		failures.append("six zones initialized deterministically")

	var comparison: Dictionary = _result["comparison"]
	var divergence_ok: bool = int(comparison["on_off_divergent_zones"]) == Simulation.ZONE_ORDER.size()
	var g5_ok: bool = int(comparison["geometry_distinct_pairs"]) >= 3
	var gap_delta := float(comparison["gap_light_restoration_delta"])
	var gap_ok: bool = gap_delta > 0.30

	var stability_max_pin := 0.0
	var stability_ok := true
	for stability_zone in ["MESIC_LOAM", "DRY_SAND"]:
		var stability := Simulation.run_zone_stability(stability_zone, SEED, Simulation.STABILITY_GENERATIONS)
		stability_ok = stability_ok and not stability.is_empty() \
			and bool(stability["finite_means"]) and bool(stability["means_within_bounds"]) \
			and bool(stability["no_axis_fully_pinned"]) and bool(stability["trajectory_finite"])
		stability_max_pin = maxf(stability_max_pin, float(stability.get("max_bound_pinning_fraction", 1.0)))

	var replay := Simulation.run_all(SEED)
	var replay_ok: bool = not replay.is_empty() and String(replay["result_hash"]) == String(_result["result_hash"])

	var ok := zones_ok and divergence_ok and g5_ok and gap_ok and stability_ok and replay_ok and _rendered_plants == Simulation.ZONE_ORDER.size() * Simulation.POPULATION_SIZE
	print("ECO.EVO7-FFF6-VIS: %s rendered=%d zones_ok=%s onoff=%s geom_pairs=%d gap_delta=%.4f stability_pin_max=%.3f replay=%s result_hash=%s" % [
		"PASS" if ok else "FAIL",
		_rendered_plants,
		str(zones_ok), str(divergence_ok),
		int(comparison["geometry_distinct_pairs"]),
		gap_delta,
		stability_max_pin,
		str(replay_ok),
		String(_result["result_hash"]).substr(0, 16),
	])
	if not ok:
		for failure in failures:
			print("ECO.EVO7-FFF6-VIS FAILED CHECK: %s" % failure)

	# G5 visual evidence (presentation only): activate C-mode through the SAME
	# code path as the KEY_C handler - set the same flag, call the same apply
	# function, refresh the same HUD - then capture the viewport with the
	# canonical idiom proven in eco_evo5_terrain_fly_lab.gd / the anti-black fix
	# in eco_evo5_b2_agents_plot_lab.gd. Materials, HUD text and camera framing
	# are presentation state; no ecological computation or hash input is touched
	# (G15). The interrupted run proved HUD readability but captured a
	# background-only viewport because readback raced the renderer after a
	# single process_frame; the eco_evo5 precedent settles many frames first.
	_neutral_materials = true
	_apply_neutral_state()
	_update_hud()
	await get_tree().process_frame

	# Wide shot: elevated 3/4 view computed from the REAL zone origins (never
	# hardcoded blindly) so the whole 3x2 zone grid fits the frame. The camera
	# sits behind the -Z row (FLOODED/RIPARIAN/MESIC_LOAM carry no canopy ring),
	# so the 19.5 m canopy trunks of the far row stay background, not occluders.
	var bounds_min := Vector3(INF, INF, INF)
	var bounds_max := Vector3(-INF, -INF, -INF)
	for zone_index in range(Simulation.ZONE_ORDER.size()):
		bounds_min = bounds_min.min(_zone_origin(zone_index))
		bounds_max = bounds_max.max(_zone_origin(zone_index))
	var grid_center := (bounds_min + bounds_max) * 0.5
	var grid_span := bounds_max - bounds_min
	_place_camera(
		grid_center + Vector3(grid_span.x * 0.25, 40.0, -(grid_span.z * 0.5 + 42.0)),
		grid_center + Vector3(0.0, 3.0, 0.0))
	await _settle_frames(20)
	await _autocap_capture("evo7_fff6_lab_cmode_wide.png")

	# Close shot: the UNDER_CANOPY|CANOPY_GAP neighbouring pair (~17 m apart on
	# the same row), camera ~11 m from the pair at crown height so individual
	# grey plant silhouettes are discernible despite the canopy trunks.
	var pair_center := (_zone_origin(Simulation.ZONE_ORDER.find("UNDER_CANOPY"))
		+ _zone_origin(Simulation.ZONE_ORDER.find("CANOPY_GAP"))) * 0.5
	_place_camera(pair_center + Vector3(0.0, 4.5, 11.0), pair_center + Vector3(0.0, 3.4, 0.0))
	await _settle_frames(20)
	await _autocap_capture("evo7_fff6_lab_cmode_close.png")
	get_tree().quit(0 if ok else 1)


## Presentation-only camera placement for autocap: derives _yaw/_pitch from the
## position/target pair and goes through _apply_look(), so the mouse-look state
## stays consistent instead of bypassing it. Never enters any hash.
func _place_camera(position: Vector3, target: Vector3) -> void:
	var offset := position - target
	var horizontal := sqrt(offset.x * offset.x + offset.z * offset.z)
	_cam.global_position = position
	_yaw = atan2(offset.x, offset.z)
	_pitch = atan2(-offset.y, maxf(horizontal, 0.001))
	_apply_look()


## Let the renderer actually draw the reframed view before readback.
func _settle_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await get_tree().process_frame


## Grab the viewport after RenderingServer.frame_post_draw, save the PNG and
## print the machine-checkable SCREENSHOT line naming the file.
func _autocap_capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	if screenshot.is_compressed():
		screenshot.decompress()
	screenshot.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var save_error := screenshot.save_png(ProjectSettings.globalize_path("res://artifacts/%s" % file_name))
	var luma_sum := 0.0
	var luma_samples := 0
	var image_width := screenshot.get_width()
	for pixel_index in range(0, image_width * screenshot.get_height(), 16):
		var pixel_x := pixel_index % image_width
		@warning_ignore("integer_division")
		var pixel_y := pixel_index / image_width
		var pixel := screenshot.get_pixel(pixel_x, pixel_y)
		luma_sum += 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b
		luma_samples += 1
	print("ECO.EVO7-FFF6-VIS: SCREENSHOT %s size=%dx%d mean_luma=%.4f err=%d" % [
		file_name, image_width, screenshot.get_height(),
		luma_sum / maxf(float(luma_samples), 1.0), save_error])