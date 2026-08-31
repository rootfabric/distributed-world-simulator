extends Node3D

## ECO.EVO7 VIS4.4 — live PLAY0 PH5 morphology renderer.
##
## Read-only presentation consumer of VIS4.1 Descriptor V2 + VIS4.3 exact
## GrowthGraph reconstruction evidence. It delegates every geometry decision to
## the accepted VIS4.3 bridge / PH5 materializers, caches materializations by
## source identity + tier, and changes only presentation nodes/transforms.

const DescriptorV2 = preload("res://scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd")
const ReconstructionEvidence = preload("res://scripts/research/ecology/plant_growth_graph_reconstruction_evidence_v1.gd")
const Bridge = preload("res://scripts/labs/ecology/eco_evo7_vis4_3_exact_ph5_bridge.gd")
const Individuality = preload("res://scripts/labs/ecology/eco_evo7_vis4_5_deterministic_individuality.gd")
const GridAppearance = preload("res://scripts/labs/ecology/eco_evo7_vis4_6_grid_appearance_boundary.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis4_4_play0_ph5_renderer.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS4.6.R1"

const REFERENCE_VIEWPORT_HEIGHT_PX := 1080.0
const REFERENCE_VERTICAL_FOV_DEG := 70.0
const LOD_HYSTERESIS := 0.12
const SENTINEL_ORIGIN := Vector3(1e18, 1e18, 1e18)
const NEUTRAL_BRANCH_COLOR := Color(0.34, 0.24, 0.14)
const NEUTRAL_FOLIAGE_COLOR := Color(0.22, 0.62, 0.24)
const NEUTRAL_FAR_COLOR := Color(0.24, 0.56, 0.25)

const PRESENTATION_ONLY := true
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false

var earth_world = null
var initialized := false
var source_generation := -1
var source_ecology_hash := ""
var source_adapter_hash := ""
var source_reconstruction_hash := ""
var source_bridge_hash := ""
var neutral_color_mode := true

var _directions: Array[Vector3] = []
var _grid_size := 0
var _records: Array[Dictionary] = []
var _plant_nodes: Array = []
var _materialization_cache: Dictionary = {}
var _cache_lookup: Dictionary = {}
var _view_world_position := Vector3.ZERO
var _last_render_origin := SENTINEL_ORIGIN
var _materialization_build_count := 0
var _lod_switch_count := 0


func setup(earth_world_reference, patch: Dictionary) -> bool:
	if initialized:
		return true
	earth_world = earth_world_reference
	if earth_world == null or patch.is_empty():
		return false
	var cells_value = patch.get("cells")
	if not cells_value is Array:
		return false
	for value in Array(cells_value):
		if not value is Dictionary:
			return false
		var direction_value = Dictionary(value).get("direction")
		if not direction_value is Vector3:
			return false
		_directions.append(Vector3(direction_value).normalized())
	_grid_size = int(round(sqrt(float(_directions.size()))))
	if _grid_size <= 1 or _grid_size * _grid_size != _directions.size():
		return false
	var center_value = patch.get("center_direction")
	if center_value is Vector3:
		_view_world_position = earth_world.get_surface_point(Vector3(center_value).normalized())
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	initialized = true
	return true


func apply_snapshot(descriptor_snapshot: Dictionary, reconstruction_snapshot: Dictionary) -> bool:
	## Fully materializes a pending generation before replacing the visible one.
	## Any invalid/missing record fails closed and preserves the last presentation.
	if not initialized:
		return false
	var descriptor_adapter := DescriptorV2.new()
	if not descriptor_adapter.validate_result(descriptor_snapshot):
		return false
	if not ReconstructionEvidence.validate_snapshot(reconstruction_snapshot):
		return false
	var generation := int(descriptor_snapshot.get("generation", -1))
	if generation < 1 or generation != int(reconstruction_snapshot.get("generation", -2)):
		return false
	if int(descriptor_snapshot.get("founder_marker_count", -1)) != 0:
		return false

	var bridge := Bridge.new()
	var bridge_snapshot: Dictionary = bridge.build(
		descriptor_snapshot,
		reconstruction_snapshot,
		Representation.TIER_1_REDUCED
	)
	if bridge_snapshot.is_empty() or not bridge.validate_result(bridge_snapshot):
		return false

	var reconstruction_by_id := _by_id(Array(reconstruction_snapshot.get("records", [])))
	var source_values: Array = Array(descriptor_snapshot.get("descriptors", []))
	if reconstruction_by_id.size() != source_values.size():
		return false

	var pending_records: Array[Dictionary] = []
	var pending_materializations: Array[Dictionary] = []
	for source_value in source_values:
		if not source_value is Dictionary:
			return false
		var source: Dictionary = Dictionary(source_value)
		var record_id := String(source.get("record_id", ""))
		var cell_index := int(source.get("cell_index", -1))
		if record_id.is_empty() or cell_index < 0 or cell_index >= _directions.size():
			return false
		var reconstruction: Dictionary = reconstruction_by_id.get(record_id, {})
		if reconstruction.is_empty():
			return false
		var up: Vector3 = _directions[cell_index]
		var base_world: Vector3 = earth_world.get_surface_point(up)
		var spacing_m: Vector2 = _cell_spacing_m(cell_index)
		var appearance: Dictionary = GridAppearance.build(
			record_id,
			cell_index,
			String(source.get("descriptor_hash", "")),
			spacing_m
		)
		if appearance.is_empty():
			return false
		var tangent_basis: Basis = _up_basis(up)
		var tangent_offset: Vector3 = (
			tangent_basis.x * float(appearance.get("offset_x_m", 0.0))
			+ tangent_basis.z * float(appearance.get("offset_y_m", 0.0))
		)
		var visual_direction: Vector3 = (base_world + tangent_offset).normalized()
		var visual_base_world: Vector3 = earth_world.get_surface_point(visual_direction)
		var functional_value = source.get("functional_morphology")
		if not functional_value is Dictionary:
			return false
		var height_m := float(Dictionary(functional_value).get("realized_height_m", NAN))
		if not is_finite(height_m) or height_m <= 0.0:
			return false
		var individuality: Dictionary = Individuality.build(source)
		if individuality.is_empty():
			return false
		var tier := _select_tier(height_m, base_world, "")
		var materialization: Dictionary = _materialize_record(bridge, source, reconstruction, tier)
		if materialization.is_empty():
			return false
		pending_records.append({
			"record_id": record_id,
			"cell_index": cell_index,
			"lineage_id": String(source.get("lineage_id", "")),
			"source_descriptor_hash": String(source.get("descriptor_hash", "")),
			"source_growth_graph_hash": String(source.get("growth_graph_hash", "")),
			"development_individual_seed": int(individuality.get("development_individual_seed", -1)),
			"orientation_yaw_deg": float(individuality.get("orientation_yaw_deg", 0.0)),
			"individuality_hash": String(individuality.get("individuality_hash", "")),
			"height_m": height_m,
			"base_world": base_world,
			"visual_base_world": visual_base_world,
			"visual_direction": visual_direction,
			"appearance_hash": String(appearance.get("appearance_hash", "")),
			"jitter_x_cell": float(appearance.get("jitter_x_cell", 0.0)),
			"jitter_y_cell": float(appearance.get("jitter_y_cell", 0.0)),
			"offset_x_m": float(appearance.get("offset_x_m", 0.0)),
			"offset_y_m": float(appearance.get("offset_y_m", 0.0)),
			"cell_spacing_x_m": float(appearance.get("cell_spacing_x_m", 0.0)),
			"cell_spacing_y_m": float(appearance.get("cell_spacing_y_m", 0.0)),
			"up": up,
			"tier": tier,
			"render_description_hash": String(materialization.get("render_description_hash", "")),
			"representation_hash": String(materialization.get("representation_hash", "")),
			"materialization_hash": String(materialization.get("materialization_hash", "")),
			"source": source.duplicate(true),
			"reconstruction": reconstruction.duplicate(true),
		})
		pending_materializations.append(materialization)

	source_generation = generation
	source_ecology_hash = String(descriptor_snapshot.get("source_ecology_state_hash", ""))
	source_adapter_hash = String(descriptor_snapshot.get("adapter_hash", ""))
	source_reconstruction_hash = String(reconstruction_snapshot.get("evidence_hash", ""))
	source_bridge_hash = String(bridge_snapshot.get("bridge_hash", ""))
	_records = pending_records
	_clear_visual_nodes()
	_plant_nodes.clear()
	for index in range(_records.size()):
		_plant_nodes.append(_create_visual(index, pending_materializations[index]))
	refresh_render_transform(true)
	return true


func clear_snapshot() -> void:
	_clear_visual_nodes()
	_records.clear()
	_plant_nodes.clear()
	source_generation = -1
	source_ecology_hash = ""
	source_adapter_hash = ""
	source_reconstruction_hash = ""
	source_bridge_hash = ""


func set_view_world_position(value: Vector3) -> bool:
	if not initialized or not _finite_vec(value):
		return false
	_view_world_position = value
	return _update_lod()


func set_neutral_color_mode(value: bool) -> bool:
	neutral_color_mode = value
	for index in range(_records.size()):
		_apply_visual_material(index)
	return neutral_color_mode


func refresh_render_transform(force: bool = false) -> void:
	if not initialized or earth_world == null:
		return
	var origin: Vector3 = earth_world.get_render_origin()
	if not force and origin == _last_render_origin:
		return
	for index in range(_records.size()):
		var node = _plant_nodes[index] if index < _plant_nodes.size() else null
		if node == null or not is_instance_valid(node):
			continue
		var record: Dictionary = _records[index]
		var local_yaw := Basis(
			Vector3.UP,
			deg_to_rad(float(record.get("orientation_yaw_deg", 0.0)))
		)
		node.transform = Transform3D(
			_up_basis(Vector3(record["up"])) * local_yaw,
			Vector3(record["visual_base_world"]) - origin
		)
	_last_render_origin = origin


func get_record_count() -> int:
	return _records.size()


func get_visible_individual_count() -> int:
	var count := 0
	for node in _plant_nodes:
		if node != null and is_instance_valid(node):
			count += 1
	return count


func get_record_world_position(index: int) -> Vector3:
	if index < 0 or index >= _records.size():
		return Vector3.ZERO
	return Vector3(_records[index].get("base_world", Vector3.ZERO))


func get_record_render_position(index: int) -> Vector3:
	# Legacy/canonical API: intentionally remains the exact ecology cell point.
	if earth_world == null:
		return Vector3.ZERO
	return get_record_world_position(index) - earth_world.get_render_origin()


func get_record_visual_world_position(index: int) -> Vector3:
	if index < 0 or index >= _records.size():
		return Vector3.ZERO
	return Vector3(_records[index].get("visual_base_world", Vector3.ZERO))


func get_record_visual_render_position(index: int) -> Vector3:
	if earth_world == null:
		return Vector3.ZERO
	return get_record_visual_world_position(index) - earth_world.get_render_origin()


func get_record_applied_render_position(index: int) -> Vector3:
	if index < 0 or index >= _plant_nodes.size():
		return Vector3.ZERO
	var node = _plant_nodes[index]
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	return node.position


func get_record_grid_appearance(index: int) -> Dictionary:
	if index < 0 or index >= _records.size():
		return {}
	var record: Dictionary = _records[index]
	return {
		"record_id": String(record.get("record_id", "")),
		"cell_index": int(record.get("cell_index", -1)),
		"source_descriptor_hash": String(record.get("source_descriptor_hash", "")),
		"appearance_hash": String(record.get("appearance_hash", "")),
		"jitter_x_cell": float(record.get("jitter_x_cell", 0.0)),
		"jitter_y_cell": float(record.get("jitter_y_cell", 0.0)),
		"offset_x_m": float(record.get("offset_x_m", 0.0)),
		"offset_y_m": float(record.get("offset_y_m", 0.0)),
		"cell_spacing_x_m": float(record.get("cell_spacing_x_m", 0.0)),
		"cell_spacing_y_m": float(record.get("cell_spacing_y_m", 0.0)),
		"canonical_world": Vector3(record.get("base_world", Vector3.ZERO)),
		"visual_world": Vector3(record.get("visual_base_world", Vector3.ZERO)),
		"visual_direction": Vector3(record.get("visual_direction", Vector3.UP)),
	}


func get_record_height(index: int) -> float:
	if index < 0 or index >= _records.size():
		return 0.0
	return float(_records[index].get("height_m", 0.0))


func get_record_tier(index: int) -> String:
	if index < 0 or index >= _records.size():
		return ""
	return String(_records[index].get("tier", ""))


func is_record_individual_materialized(index: int) -> bool:
	if index < 0 or index >= _plant_nodes.size():
		return false
	var node = _plant_nodes[index]
	return node != null and is_instance_valid(node)


func get_record_identity(index: int) -> Dictionary:
	if index < 0 or index >= _records.size():
		return {}
	var record: Dictionary = _records[index]
	return {
		"record_id": String(record.get("record_id", "")),
		"source_descriptor_hash": String(record.get("source_descriptor_hash", "")),
		"source_growth_graph_hash": String(record.get("source_growth_graph_hash", "")),
		"development_individual_seed": int(record.get("development_individual_seed", -1)),
		"orientation_yaw_deg": float(record.get("orientation_yaw_deg", 0.0)),
		"individuality_hash": String(record.get("individuality_hash", "")),
		"appearance_hash": String(record.get("appearance_hash", "")),
		"render_description_hash": String(record.get("render_description_hash", "")),
		"representation_hash": String(record.get("representation_hash", "")),
		"materialization_hash": String(record.get("materialization_hash", "")),
		"tier": String(record.get("tier", "")),
	}


func get_individuality_identity_hash() -> String:
	var tokens := PackedStringArray([
		Individuality.SCHEMA,
		Individuality.VERSION,
		str(source_generation),
		source_ecology_hash,
	])
	for record in _records:
		tokens.append("|".join(PackedStringArray([
			String(record.get("record_id", "")),
			str(int(record.get("development_individual_seed", -1))),
			String(record.get("source_descriptor_hash", "")),
			String(record.get("source_growth_graph_hash", "")),
			"%.9f" % float(record.get("orientation_yaw_deg", 0.0)),
			String(record.get("individuality_hash", "")),
		])))
	return "\n".join(tokens).sha256_text()


func get_record_presentation_yaw_deg(index: int) -> float:
	if index < 0 or index >= _records.size():
		return NAN
	return float(_records[index].get("orientation_yaw_deg", NAN))


func get_record_visual_basis(index: int) -> Basis:
	if index < 0 or index >= _plant_nodes.size():
		return Basis.IDENTITY
	var node = _plant_nodes[index]
	if node == null or not is_instance_valid(node):
		return Basis.IDENTITY
	return node.basis


func get_grid_appearance_identity_hash() -> String:
	var tokens := PackedStringArray([
		GridAppearance.SCHEMA,
		GridAppearance.VERSION,
		str(source_generation),
		source_ecology_hash,
	])
	for record in _records:
		tokens.append("|".join(PackedStringArray([
			String(record.get("record_id", "")),
			str(int(record.get("cell_index", -1))),
			String(record.get("source_descriptor_hash", "")),
			String(record.get("appearance_hash", "")),
		])))
	return "\n".join(tokens).sha256_text()


func get_geometry_identity_hash() -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, str(source_generation), source_ecology_hash])
	for record in _records:
		tokens.append("|".join(PackedStringArray([
			String(record.get("record_id", "")),
			String(record.get("source_growth_graph_hash", "")),
			String(record.get("render_description_hash", "")),
			String(record.get("representation_hash", "")),
			String(record.get("tier", "")),
			String(record.get("materialization_hash", "")),
		])))
	return "\n".join(tokens).sha256_text()


func get_contract() -> Dictionary:
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"presentation_only": PRESENTATION_ONLY,
		"network_authority": NETWORK_AUTHORITY,
		"persistence_authority": PERSISTENCE_AUTHORITY,
		"generation": source_generation,
		"source_ecology_hash": source_ecology_hash,
		"source_adapter_hash": source_adapter_hash,
		"source_reconstruction_hash": source_reconstruction_hash,
		"source_bridge_hash": source_bridge_hash,
		"record_count": _records.size(),
		"visible_individual_count": get_visible_individual_count(),
		"tier_counts": _tier_counts(),
		"materialization_cache_entries": _materialization_cache.size(),
		"materialization_build_count": _materialization_build_count,
		"lod_switch_count": _lod_switch_count,
		"neutral_color_mode": neutral_color_mode,
		"deterministic_individuality": true,
		"seed_bound_record_count": _records.size(),
		"individuality_identity_hash": get_individuality_identity_hash(),
		"grid_appearance_boundary": true,
		"grid_size": _grid_size,
		"visual_offset_is_canonical": false,
		"max_jitter_x_cell": GridAppearance.X_HALF_EXTENT_CELL,
		"max_jitter_y_cell": GridAppearance.Y_HALF_EXTENT_CELL,
		"grid_appearance_identity_hash": get_grid_appearance_identity_hash(),
		"geometry_identity_hash": get_geometry_identity_hash(),
		"placement_api": "ProceduralEarthWorld.get_surface_point(direction)",
		"canonical_position_api": "cell direction -> get_surface_point(direction)",
		"visual_position_api": "VIS2 stable jitter -> tangent offset -> get_surface_point(scattered_direction)",
		"render_origin_rebuilds_geometry": false,
	}


func _update_lod() -> bool:
	if _records.is_empty():
		return true
	var bridge := Bridge.new()
	var updates: Array[Dictionary] = []
	for index in range(_records.size()):
		var record: Dictionary = _records[index]
		var previous_tier := String(record.get("tier", ""))
		var tier := _select_tier(
			float(record.get("height_m", 0.0)),
			Vector3(record.get("base_world", Vector3.ZERO)),
			previous_tier
		)
		if tier == previous_tier:
			continue
		var source: Dictionary = record.get("source", {})
		var reconstruction: Dictionary = record.get("reconstruction", {})
		var materialization := _materialize_record(bridge, source, reconstruction, tier)
		if materialization.is_empty():
			return false
		updates.append({
			"index": index,
			"tier": tier,
			"materialization": materialization,
		})
	for update in updates:
		var index := int(update["index"])
		var materialization: Dictionary = update["materialization"]
		_records[index]["tier"] = String(update["tier"])
		_records[index]["render_description_hash"] = String(materialization.get("render_description_hash", ""))
		_records[index]["representation_hash"] = String(materialization.get("representation_hash", ""))
		_records[index]["materialization_hash"] = String(materialization.get("materialization_hash", ""))
		_replace_visual(index, materialization)
		_lod_switch_count += 1
	refresh_render_transform(true)
	return true


func _select_tier(height_m: float, base_world: Vector3, previous_tier: String) -> String:
	var distance_m := maxf(0.05, base_world.distance_to(_view_world_position))
	var focal_px := REFERENCE_VIEWPORT_HEIGHT_PX / (
		2.0 * tan(deg_to_rad(REFERENCE_VERTICAL_FOV_DEG) * 0.5)
	)
	var projected_height_px := maxf(0.0, height_m) * focal_px / distance_m
	return Representation.select_tier_hysteretic(
		projected_height_px,
		previous_tier,
		LOD_HYSTERESIS
	)


func _materialize_record(bridge, source: Dictionary, reconstruction: Dictionary, tier: String) -> Dictionary:
	var lookup_key := "|".join(PackedStringArray([
		String(source.get("record_id", "")),
		String(source.get("growth_graph_hash", "")),
		String(source.get("descriptor_hash", "")),
		String(reconstruction.get("reconstruction_evidence_hash", "")),
		tier,
	]))
	if _cache_lookup.has(lookup_key):
		var cached_key := String(_cache_lookup[lookup_key])
		if _materialization_cache.has(cached_key):
			return Dictionary(_materialization_cache[cached_key])
	var materialization: Dictionary = bridge.materialize_record(source, reconstruction, tier)
	if materialization.is_empty() or not bool(materialization.get("success", false)):
		return {}
	for key in ["ecological_truth_hash", "render_description_hash", "representation_hash", "materialization_hash"]:
		if String(materialization.get(key, "")).length() != 64:
			return {}
	if String(materialization.get("ecological_truth_hash", "")) != String(source.get("growth_graph_hash", "")):
		return {}
	var cache_key := "|".join(PackedStringArray([
		String(source.get("record_id", "")),
		String(source.get("growth_graph_hash", "")),
		String(materialization.get("render_description_hash", "")),
		tier,
		String(materialization.get("representation_hash", "")),
	]))
	_materialization_cache[cache_key] = materialization
	_cache_lookup[lookup_key] = cache_key
	_materialization_build_count += 1
	return materialization


func _create_visual(index: int, materialization: Dictionary):
	if not bool(materialization.get("individual_node_required", false)):
		return null
	var record: Dictionary = _records[index]
	var root := Node3D.new()
	root.name = "Plant_%s" % String(record.get("record_id", "")).replace("/", "_")
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.set_meta("record_id", String(record.get("record_id", "")))
	root.set_meta("source_growth_graph_hash", String(record.get("source_growth_graph_hash", "")))
	root.set_meta("development_individual_seed", int(record.get("development_individual_seed", -1)))
	root.set_meta("orientation_yaw_deg", float(record.get("orientation_yaw_deg", 0.0)))
	root.set_meta("individuality_hash", String(record.get("individuality_hash", "")))
	root.set_meta("appearance_hash", String(record.get("appearance_hash", "")))
	root.set_meta("visual_offset_is_canonical", false)
	root.set_meta("render_description_hash", String(materialization.get("render_description_hash", "")))
	root.set_meta("representation_hash", String(materialization.get("representation_hash", "")))
	root.set_meta("materialization_hash", String(materialization.get("materialization_hash", "")))
	root.set_meta("tier", String(materialization.get("tier", "")))
	add_child(root)

	var branch_mesh: Mesh = materialization.get("branch_mesh")
	if branch_mesh != null:
		var branch_node := MeshInstance3D.new()
		branch_node.name = "PH5Branches"
		branch_node.mesh = branch_mesh
		root.add_child(branch_node)

	var foliage_multimesh: MultiMesh = materialization.get("foliage_multimesh")
	if foliage_multimesh != null:
		var foliage_node := MultiMeshInstance3D.new()
		foliage_node.name = "PH5Foliage"
		foliage_node.multimesh = foliage_multimesh
		root.add_child(foliage_node)

	var far_mesh: Mesh = materialization.get("far_mesh")
	if far_mesh != null:
		var far_node := MeshInstance3D.new()
		far_node.name = "PH5Far"
		far_node.mesh = far_mesh
		far_node.position = Vector3(materialization.get("origin", Vector3.ZERO))
		root.add_child(far_node)

	_apply_visual_material_to_node(root, record, materialization)
	return root


func _replace_visual(index: int, materialization: Dictionary) -> void:
	var old_node = _plant_nodes[index] if index < _plant_nodes.size() else null
	if old_node != null and is_instance_valid(old_node):
		remove_child(old_node)
		old_node.queue_free()
	_plant_nodes[index] = _create_visual(index, materialization)


func _apply_visual_material(index: int) -> void:
	if index < 0 or index >= _records.size() or index >= _plant_nodes.size():
		return
	var node = _plant_nodes[index]
	if node == null or not is_instance_valid(node):
		return
	var record: Dictionary = _records[index]
	var materialization := {
		"tier": String(record.get("tier", "")),
		"billboard": String(record.get("tier", "")) == Representation.TIER_3_IMPOSTOR,
	}
	_apply_visual_material_to_node(node, record, materialization)


func _apply_visual_material_to_node(root: Node3D, record: Dictionary, materialization: Dictionary) -> void:
	var lineage := _lineage_color(String(record.get("lineage_id", "")))
	var branch_color := NEUTRAL_BRANCH_COLOR if neutral_color_mode else lineage.darkened(0.55)
	var foliage_color := NEUTRAL_FOLIAGE_COLOR if neutral_color_mode else lineage
	var far_color := NEUTRAL_FAR_COLOR if neutral_color_mode else lineage

	var branch = root.get_node_or_null("PH5Branches")
	if branch is GeometryInstance3D:
		branch.material_override = _material(branch_color, false)
	var foliage = root.get_node_or_null("PH5Foliage")
	if foliage is GeometryInstance3D:
		foliage.material_override = _material(foliage_color, false, true)
	var far = root.get_node_or_null("PH5Far")
	if far is GeometryInstance3D:
		far.material_override = _material(far_color, bool(materialization.get("billboard", false)), true)


func _material(color: Color, billboard: bool, double_sided: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return material


func _clear_visual_nodes() -> void:
	for node in _plant_nodes:
		if node != null and is_instance_valid(node):
			remove_child(node)
			node.queue_free()


func _tier_counts() -> Dictionary:
	var counts := {}
	for tier in Representation.TIER_ORDER:
		counts[tier] = 0
	for record in _records:
		var tier := String(record.get("tier", ""))
		if counts.has(tier):
			counts[tier] = int(counts[tier]) + 1
	return counts


func _cell_spacing_m(cell_index: int) -> Vector2:
	if earth_world == null or _grid_size <= 1 or cell_index < 0 or cell_index >= _directions.size():
		return Vector2.ZERO
	var row: int = floori(float(cell_index) / float(_grid_size))
	var col: int = cell_index % _grid_size
	var x_neighbor: int = cell_index + 1 if col < _grid_size - 1 else cell_index - 1
	var y_neighbor: int = cell_index + _grid_size if row < _grid_size - 1 else cell_index - _grid_size
	if x_neighbor < 0 or y_neighbor < 0 or x_neighbor >= _directions.size() or y_neighbor >= _directions.size():
		return Vector2.ZERO
	var center: Vector3 = earth_world.get_surface_point(_directions[cell_index])
	var x_world: Vector3 = earth_world.get_surface_point(_directions[x_neighbor])
	var y_world: Vector3 = earth_world.get_surface_point(_directions[y_neighbor])
	return Vector2(center.distance_to(x_world), center.distance_to(y_world))


func _by_id(values: Array) -> Dictionary:
	var out := {}
	for value in values:
		if not value is Dictionary:
			return {}
		var item: Dictionary = value
		var identity := String(item.get("record_id", ""))
		if identity.is_empty() or out.has(identity):
			return {}
		out[identity] = item
	return out


func _up_basis(up: Vector3) -> Basis:
	var helper := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis := helper.cross(up).normalized()
	var z_axis := x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)


func _lineage_color(lineage_id: String) -> Color:
	var normalized := float(abs(lineage_id.hash()) % 10000) / 10000.0
	return Color.from_hsv(normalized, 0.58, 0.82)


func _finite_vec(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
