extends Node3D

## ECO.EVO7 PLAY0 — live planet ecology presentation (READ-ONLY).
##
## Consumes the accepted VIS2 phenotype render adapter result built from the
## accepted LS3.6 Workbench snapshot and translates it into 3D presentation:
## MultiMesh stems, crowns, lineage colours and a biome overlay. Plants are
## placed by physical patch cell direction through
## ProceduralEarthWorld.get_surface_point(direction) and track render-origin
## shifts every frame.
##
## This layer owns no biology: no genomes, no mutation, no competition, no
## persistence writes, no network authority. It never calls generation control
## APIs and never recomputes phenotype evidence — it renders immutable,
## already-validated adapter descriptors only.

const PH5RendererScript = preload("res://scripts/labs/ecology/eco_evo7_vis4_4_play0_ph5_renderer.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_play0_presentation.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-PLAY0.PRESENTATION.R2-VIS4.4"

const FOUNDER_EVIDENCE := "FOUNDER_RECORD_ONLY"
const FOUNDER_STEM_HEIGHT_M := 0.34
const FOUNDER_CROWN_RADIUS_M := 0.22
const MIN_STEM_HEIGHT_M := 0.4
const MAX_STEM_HEIGHT_M := 9.0
const MIN_CROWN_RADIUS_M := 0.28
const MAX_CROWN_RADIUS_M := 2.6
const OVERLAY_LIFT_M := 0.16
const OVERLAY_CELL_INSET := 0.92
const SENTINEL_ORIGIN := Vector3(1e18, 1e18, 1e18)

const PRESENTATION_ONLY := true
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false

var earth_world = null
var patch: Dictionary = {}
var patch_center_direction := Vector3.UP
var source_ecology_hash := ""
var descriptor_count := 0
var phenotype_count := 0
var founder_count := 0
var biome_overlay_visible := false
var initialized := false

var _directions: Array[Vector3] = []
var _stem_base_world: Array[Vector3] = []
var _stem_ups: Array[Vector3] = []
var _stem_heights: Array[float] = []
var _stem_colors: Array[Color] = []
var _crown_centers_world: Array[Vector3] = []
var _crown_ups: Array[Vector3] = []
var _crown_radii: Array[float] = []
var _crown_colors: Array[Color] = []
var _overlay_colors: Array[Color] = []
var _overlay_base_world: Array[Vector3] = []
var _overlay_ups: Array[Vector3] = []
var _last_render_origin := SENTINEL_ORIGIN
var _ph5_active := false

var stems_node: MultiMeshInstance3D
var crowns_node: MultiMeshInstance3D
var ph5_renderer: Node3D
var biome_overlay_node: MultiMeshInstance3D


func setup(earth_world_reference, patch_value: Dictionary) -> bool:
	if initialized:
		return true
	# Presentation transforms follow the render origin every frame, not the
	# physics clock; global physics interpolation must not touch them.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	earth_world = earth_world_reference
	patch = patch_value.duplicate(true)
	if earth_world == null or patch.is_empty():
		return false
	var cells_value = patch.get("cells")
	if not cells_value is Array:
		return false
	_directions.clear()
	for value in Array(cells_value):
		if not value is Dictionary:
			return false
		var direction_value = Dictionary(value).get("direction")
		if not direction_value is Vector3:
			return false
		_directions.append(Vector3(direction_value))
	var center_value = patch.get("center_direction")
	if not center_value is Vector3:
		return false
	patch_center_direction = Vector3(center_value).normalized()
	_build_nodes()
	if ph5_renderer == null or not ph5_renderer.setup(earth_world, patch):
		return false
	initialized = true
	return true


func apply_snapshot(
	descriptors: Dictionary,
	classification: Dictionary,
	morphology_descriptors: Dictionary = {},
	reconstruction_snapshot: Dictionary = {}
) -> bool:
	## Generation zero keeps the honest founder fallback. Once realized
	## morphology exists, PLAY0 fails closed unless the complete VIS4.1 +
	## VIS4.3 source pair materializes successfully through PH5.
	if not initialized or descriptors.is_empty():
		return false
	var new_hash := String(descriptors.get("source_ecology_state_hash", ""))
	if new_hash.length() != 64:
		return false
	var legacy_founders := int(descriptors.get("founder_marker_count", 0))
	var legacy_phenotypes := int(descriptors.get("phenotype_evidence_count", 0))
	var live_snapshot := legacy_founders == 0 and legacy_phenotypes > 0
	var ph5_requested := not morphology_descriptors.is_empty() or not reconstruction_snapshot.is_empty()

	if live_snapshot or ph5_requested:
		if morphology_descriptors.is_empty() or reconstruction_snapshot.is_empty():
			return false
		if String(morphology_descriptors.get("source_ecology_state_hash", "")) != new_hash:
			return false
		if ph5_renderer == null or not ph5_renderer.apply_snapshot(
			morphology_descriptors,
			reconstruction_snapshot
		):
			return false

		source_ecology_hash = new_hash
		descriptor_count = int(morphology_descriptors.get("descriptor_count", 0))
		phenotype_count = int(morphology_descriptors.get("morphology_evidence_count", 0))
		founder_count = int(morphology_descriptors.get("founder_marker_count", 0))
		_ph5_active = true
		stems_node.visible = false
		crowns_node.visible = false
		ph5_renderer.visible = true
		_apply_overlay_colors(classification)
		_fill_overlay_instances()
		refresh_render_transform(true)
		return true

	if not _apply_legacy_snapshot(descriptors, classification):
		return false
	_ph5_active = false
	if ph5_renderer != null:
		ph5_renderer.clear_snapshot()
		ph5_renderer.visible = false
	stems_node.visible = true
	crowns_node.visible = true
	return true


func _apply_legacy_snapshot(descriptors: Dictionary, classification: Dictionary) -> bool:
	## Rebuilds presentation arrays from one immutable VIS2 adapter result.
	if not initialized or descriptors.is_empty():
		return false
	var new_hash := String(descriptors.get("source_ecology_state_hash", ""))
	if new_hash.length() != 64:
		return false
	var descriptor_values = descriptors.get("descriptors")
	if not descriptor_values is Array:
		return false

	source_ecology_hash = new_hash
	descriptor_count = int(descriptors.get("descriptor_count", 0))
	phenotype_count = int(descriptors.get("phenotype_evidence_count", 0))
	founder_count = int(descriptors.get("founder_marker_count", 0))

	_stem_base_world.clear()
	_stem_ups.clear()
	_stem_heights.clear()
	_stem_colors.clear()
	_crown_centers_world.clear()
	_crown_ups.clear()
	_crown_radii.clear()
	_crown_colors.clear()
	for value in Array(descriptor_values):
		if not value is Dictionary:
			continue
		var descriptor: Dictionary = value
		var cell_index := int(descriptor.get("cell_index", -1))
		if cell_index < 0 or cell_index >= _directions.size():
			continue
		var up: Vector3 = _directions[cell_index]
		# REQUIRED placement path: physical patch cell direction -> planet surface.
		var base: Vector3 = earth_world.get_surface_point(up)
		var founder := String(descriptor.get("evidence_level", "")) == FOUNDER_EVIDENCE
		var height: float = (
			FOUNDER_STEM_HEIGHT_M
			if founder
			else clampf(
				float(descriptor.get("realized_height_m", 0.0)),
				MIN_STEM_HEIGHT_M,
				MAX_STEM_HEIGHT_M
			)
		)
		var crown_radius: float = (
			FOUNDER_CROWN_RADIUS_M
			if founder
			else clampf(
				0.45 + 1.5 * float(descriptor.get("leaf_area_index_proxy", 0.0)),
				MIN_CROWN_RADIUS_M,
				MAX_CROWN_RADIUS_M
			)
		)
		var lineage_color := _lineage_color(String(descriptor.get("lineage_id", "")))
		_stem_base_world.append(base)
		_stem_ups.append(up)
		_stem_heights.append(height)
		_stem_colors.append(lineage_color.darkened(0.55))
		_crown_centers_world.append(base + up * height)
		_crown_ups.append(up)
		_crown_radii.append(crown_radius)
		_crown_colors.append(lineage_color)

	_apply_overlay_colors(classification)
	_fill_stem_instances()
	_fill_crown_instances()
	_fill_overlay_instances()
	refresh_render_transform(true)
	return true


func set_biome_overlay_visible(value: bool) -> bool:
	if not initialized:
		return false
	biome_overlay_visible = value
	if biome_overlay_node != null:
		biome_overlay_node.visible = value
	return biome_overlay_visible


func toggle_biome_overlay() -> bool:
	return set_biome_overlay_visible(not biome_overlay_visible)


func refresh_render_transform(force: bool = false) -> void:
	## Re-projects every instance from world space into current render space.
	if not initialized or earth_world == null:
		return
	var origin: Vector3 = earth_world.get_render_origin()
	if not force and origin == _last_render_origin:
		return
	if _ph5_active and ph5_renderer != null:
		ph5_renderer.refresh_render_transform(force)
	var stems_multimesh: MultiMesh = stems_node.multimesh if stems_node != null else null
	var crowns_multimesh: MultiMesh = crowns_node.multimesh if crowns_node != null else null
	var overlay_multimesh: MultiMesh = (
		biome_overlay_node.multimesh if biome_overlay_node != null else null
	)
	var cell_size_m: float = maxf(0.25, float(patch.get("cell_size_m", 16.0)))
	var overlay_count: int = mini(_overlay_base_world.size(), _directions.size())
	for index in _stem_base_world.size():
		stems_multimesh.set_instance_transform(
			index,
			_stem_transform(_stem_base_world[index], _stem_ups[index], _stem_heights[index])
		)
	for index in _crown_centers_world.size():
		var diameter: float = _crown_radii[index] * 2.0
		var basis := _up_basis(_crown_ups[index]).scaled(Vector3(diameter, diameter * 0.8, diameter))
		crowns_multimesh.set_instance_transform(
			index,
			Transform3D(basis, _crown_centers_world[index] - origin)
		)
	for index in overlay_count:
		var up: Vector3 = _overlay_ups[index]
		var basis := _up_basis(up).scaled(
			Vector3(cell_size_m * OVERLAY_CELL_INSET, 1.0, cell_size_m * OVERLAY_CELL_INSET)
		)
		overlay_multimesh.set_instance_transform(
			index,
			Transform3D(basis, _overlay_base_world[index] + up * OVERLAY_LIFT_M - origin)
		)
	_last_render_origin = origin


func get_stem_render_position(index: int) -> Vector3:
	if _ph5_active and ph5_renderer != null:
		return ph5_renderer.get_record_render_position(index)
	if earth_world == null or index < 0 or index >= _stem_base_world.size():
		return Vector3.ZERO
	return _stem_base_world[index] - earth_world.get_render_origin()


func get_stem_world_position(index: int) -> Vector3:
	if _ph5_active and ph5_renderer != null:
		return ph5_renderer.get_record_world_position(index)
	if index < 0 or index >= _stem_base_world.size():
		return Vector3.ZERO
	return _stem_base_world[index]


func get_patch_center_direction() -> Vector3:
	return patch_center_direction


func get_cell_count() -> int:
	return _directions.size()


func get_contract() -> Dictionary:
	var ph5_contract: Dictionary = ph5_renderer.get_contract() if ph5_renderer != null else {}
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"presentation_only": PRESENTATION_ONLY,
		"network_authority": NETWORK_AUTHORITY,
		"persistence_authority": PERSISTENCE_AUTHORITY,
		"source_ecology_hash": source_ecology_hash,
		"descriptor_count": descriptor_count,
		"phenotype_evidence_count": phenotype_count,
		"founder_marker_count": founder_count,
		"stem_instances": int(ph5_contract.get("visible_individual_count", 0)) if _ph5_active else _stem_base_world.size(),
		"crown_instances": 0 if _ph5_active else _crown_centers_world.size(),
		"biome_overlay_instances": mini(_overlay_colors.size(), _directions.size()),
		"biome_overlay_visible": biome_overlay_visible,
		"placement_api": "ProceduralEarthWorld.get_surface_point(direction)",
		"uses_vis2_adapter": true,
		"uses_vis4_exact_ph5": _ph5_active,
		"ph5_active": _ph5_active,
		"legacy_founder_fallback": not _ph5_active,
		"ph5": ph5_contract,
		"multimesh": true,
	}


func set_view_world_position(value: Vector3) -> bool:
	if ph5_renderer == null:
		return false
	return ph5_renderer.set_view_world_position(value)


func set_neutral_color_mode(value: bool) -> bool:
	if ph5_renderer == null:
		return false
	return ph5_renderer.set_neutral_color_mode(value)


func get_ph5_record_identity(index: int) -> Dictionary:
	return {} if ph5_renderer == null else ph5_renderer.get_record_identity(index)


func get_ph5_record_tier(index: int) -> String:
	return "" if ph5_renderer == null else ph5_renderer.get_record_tier(index)


func get_ph5_record_height(index: int) -> float:
	return 0.0 if ph5_renderer == null else ph5_renderer.get_record_height(index)


func is_ph5_record_individual_materialized(index: int) -> bool:
	return ph5_renderer != null and ph5_renderer.is_record_individual_materialized(index)


func get_ph5_geometry_identity_hash() -> String:
	return "" if ph5_renderer == null else ph5_renderer.get_geometry_identity_hash()


func _build_nodes() -> void:
	stems_node = MultiMeshInstance3D.new()
	stems_node.name = "Play0Stems"
	var stem_mesh := BoxMesh.new()
	stem_mesh.size = Vector3(0.18, 1.0, 0.18)
	stems_node.multimesh = _make_multimesh(stem_mesh, 0.85)
	add_child(stems_node)

	crowns_node = MultiMeshInstance3D.new()
	crowns_node.name = "Play0Crowns"
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.5
	crown_mesh.height = 1.0
	crown_mesh.radial_segments = 12
	crown_mesh.rings = 6
	crowns_node.multimesh = _make_multimesh(crown_mesh, 0.8)
	add_child(crowns_node)

	ph5_renderer = PH5RendererScript.new()
	ph5_renderer.name = "Play0PH5Morphology"
	ph5_renderer.visible = false
	add_child(ph5_renderer)

	biome_overlay_node = MultiMeshInstance3D.new()
	biome_overlay_node.name = "Play0BiomeOverlay"
	var overlay_mesh := PlaneMesh.new()
	overlay_mesh.size = Vector2(1.0, 1.0)
	var overlay_material := StandardMaterial3D.new()
	overlay_material.vertex_color_use_as_albedo = true
	overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay_material.roughness = 1.0
	overlay_material.no_depth_test = false
	overlay_material.render_priority = 1
	biome_overlay_node.multimesh = _make_multimesh(overlay_mesh, 1.0)
	biome_overlay_node.material_override = overlay_material
	biome_overlay_node.visible = false
	add_child(biome_overlay_node)


func _make_multimesh(mesh: Mesh, roughness_value: float) -> MultiMesh:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = roughness_value
	mesh.surface_set_material(0, material)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = 0
	# Presentation spans render-space offsets up to planetary scale while the
	# observer origin moves; keep the whole swarm inside one safe AABB.
	multimesh.custom_aabb = AABB(
		Vector3(-1e7, -1e7, -1e7),
		Vector3(2e7, 2e7, 2e7)
	)
	return multimesh


func _fill_stem_instances() -> void:
	var stems_multimesh: MultiMesh = stems_node.multimesh
	stems_multimesh.instance_count = 0
	stems_multimesh.instance_count = _stem_base_world.size()
	for index in _stem_colors.size():
		stems_multimesh.set_instance_color(index, _stem_colors[index])


func _fill_crown_instances() -> void:
	var crowns_multimesh: MultiMesh = crowns_node.multimesh
	crowns_multimesh.instance_count = 0
	crowns_multimesh.instance_count = _crown_centers_world.size()
	for index in _crown_colors.size():
		crowns_multimesh.set_instance_color(index, _crown_colors[index])


func _apply_overlay_colors(classification: Dictionary) -> void:
	_overlay_colors.clear()
	var cells_value = classification.get("cells")
	if cells_value is Array and Array(cells_value).size() == _directions.size():
		for value in Array(cells_value):
			if not value is Dictionary:
				_overlay_colors.append(_biome_color("unknown"))
				continue
			var label := String(Dictionary(value).get("label", "unknown")).to_lower()
			_overlay_colors.append(_biome_color(label))
		return
	# Generation zero has no classifier labels yet: present the read-only
	# physical patch masks instead. This is presentation only.
	var cells: Array = Array(patch.get("cells", []))
	if cells.size() != _directions.size():
		return
	for value in cells:
		if not value is Dictionary:
			_overlay_colors.append(_biome_color("unknown"))
			continue
		var cell: Dictionary = value
		var water_kind := int(cell.get("water_kind", 0))
		var land_mask := float(cell.get("land_mask", 0.0))
		if water_kind != 0 or land_mask < 0.5:
			_overlay_colors.append(Color(0.12, 0.36, 0.66, 0.42))
		else:
			_overlay_colors.append(Color(0.20, 0.48, 0.14, 0.40))


func _fill_overlay_instances() -> void:
	# Physical cell base positions are sampled once per completed snapshot;
	# render-origin shifts then only re-project cached positions.
	_overlay_base_world.clear()
	_overlay_ups.clear()
	for index in _directions.size():
		var up: Vector3 = _directions[index]
		_overlay_ups.append(up)
		_overlay_base_world.append(earth_world.get_surface_point(up))
	var overlay_multimesh: MultiMesh = biome_overlay_node.multimesh
	overlay_multimesh.instance_count = 0
	overlay_multimesh.instance_count = _directions.size()
	for index in _overlay_colors.size():
		overlay_multimesh.set_instance_color(index, _overlay_colors[index])


func _stem_transform(base_world: Vector3, up: Vector3, height: float) -> Transform3D:
	var origin: Vector3 = earth_world.get_render_origin()
	var basis := _up_basis(up).scaled(Vector3(1.0, height, 1.0))
	return Transform3D(basis, base_world + up * height * 0.5 - origin)


func _up_basis(up: Vector3) -> Basis:
	var helper := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis := helper.cross(up).normalized()
	var z_axis := x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)


func _lineage_color(lineage_id: String) -> Color:
	var normalized := float(abs(lineage_id.hash()) % 10000) / 10000.0
	return Color.from_hsv(normalized, 0.58, 0.82)


func _biome_color(label: String) -> Color:
	match label:
		"ocean", "water", "lake", "river":
			return Color(0.12, 0.38, 0.70, 0.44)
		"desert", "arid", "dry":
			return Color(0.86, 0.66, 0.22, 0.42)
		"tundra", "cold", "polar":
			return Color(0.78, 0.84, 0.88, 0.42)
		"forest", "dense_forest", "woodland":
			return Color(0.10, 0.46, 0.12, 0.42)
		"grassland", "grass", "meadow", "savanna":
			return Color(0.46, 0.66, 0.16, 0.42)
		"alpine_snow", "snow", "alpine":
			return Color(0.94, 0.96, 0.98, 0.44)
		"rock", "bare", "mountain":
			return Color(0.44, 0.40, 0.36, 0.42)
		_:
			var normalized := float(abs(label.hash()) % 10000) / 10000.0
			return Color.from_hsv(normalized, 0.45, 0.7, 0.42)


func _process(_delta: float) -> void:
	refresh_render_transform(false)
