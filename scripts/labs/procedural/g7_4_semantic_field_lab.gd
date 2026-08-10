extends Node3D

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const SemanticQuery = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Composer = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_composer_v1.gd")
const G3Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g3_surface_semantic_field_adapter_v1.gd")
const G5Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g5_feature_semantic_field_adapter_v1.gd")
const G6Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g6_fluid_semantic_field_adapter_v1.gd")
const MacroProvider = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd")
const FeatureGraph = preload("res://scripts/simulation/procedural/features/feature_graph.gd")
const FeatureBounds = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FeatureAnchor = preload("res://scripts/simulation/procedural/contracts/feature_anchor.gd")
const FeatureType = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const WorldFeature = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")
const RiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd")

const MANIFEST_PATH := "res://config/procedural/g7-4-semantic-field-lab.v1.json"
const G73_VALIDATION_PATH := "res://validation/g7-3-cross-cell-cross-lod-invariance-validation.json"
const DISPLAY_RADIUS := 8.0
const DISPLAY_SURFACE_OFFSET := 0.045
const DISPLAY_HEIGHT_SCALE := 0.00010
const CAMERA_MIN_DISTANCE := 8.35
const CAMERA_MAX_DISTANCE := 28.0
const CAMERA_DEFAULT_DISTANCE := 12.0
const CAMERA_DEFAULT_YAW_DEG := 46.0
const CAMERA_DEFAULT_PITCH_DEG := 5.0
const LAT_MIN_DEG := 0.0
const LAT_MAX_DEG := 10.0
const LON_MIN_DEG := 30.0
const LON_MAX_DEG := 62.0
const LAT_SEGMENTS := 16
const LON_SEGMENTS := 32
const GRID_WIDTH := LON_SEGMENTS + 1
const GRID_HEIGHT := LAT_SEGMENTS + 1
const EXPECTED_SAMPLE_COUNT := GRID_WIDTH * GRID_HEIGHT
const ADDRESSING_LOD := 8
# Derived presentation only. LOD0 is nearest/highest detail; LOD3 is far/coarsest.
# All four levels reuse the same 561 semantic records and therefore cannot
# create a new SemanticFieldId, FeatureId, FluidRegionId, or canonical query.
const PRESENTATION_LOD_STRIDES: Array[int] = [1, 2, 4, 8]
const PRESENTATION_LOD1_DISTANCE := 11.0
const PRESENTATION_LOD2_DISTANCE := 15.0
const PRESENTATION_LOD3_DISTANCE := 20.0
const FIELD_KEYS: Array[String] = [
	Registry.SURFACE_HEIGHT_M,
	Registry.VALLEY_INFLUENCE,
	Registry.RIVER_DISTANCE_M,
	Registry.RIVER_WIDTH_M,
	Registry.FLUID_SURFACE_DISTANCE_M,
]
const VOCABULARY_ONLY_FIELDS: Array[String] = [
	Registry.SLOPE,
	Registry.CURVATURE,
	Registry.DRAINAGE_POTENTIAL,
	Registry.CONTINENTALNESS,
	Registry.TEMPERATURE_BASELINE,
	Registry.MOISTURE_BASELINE,
]
const LAB_SEED := 20260810074
const LAB_VALLEY_GENERATOR_VERSION := "1.0.0"
const LAB_VALLEY_STABLE_KEY := "feature-key/g7-4-semantic-lab-valley"
const LAB_VALLEY_RADIUS_M := 1150000.0

@onready var planet: MeshInstance3D = $Planet
@onready var camera: Camera3D = $Camera3D
@onready var hud: Label = $HUD/Panel/Margin/VBox/Status

var macro_provider
var feature_graph
var compiled_river: Dictionary = {}
var addressing
var semantic_records: Array = []
var field_ranges: Dictionary = {}
var observed_faces: Dictionary = {}
var presentation_manifest_hash := ""
var current_field_index := 0
var current_presentation_lod := -1
var patch_node: MeshInstance3D
var river_node: MeshInstance3D
var yaw_deg := CAMERA_DEFAULT_YAW_DEG
var pitch_deg := CAMERA_DEFAULT_PITCH_DEG
var camera_distance := CAMERA_DEFAULT_DISTANCE
var auto_orbit := false


func _ready() -> void:
	var prepared := _prepare_semantic_sources()
	if not bool(prepared.get("success", false)):
		_fail("semantic source preparation", prepared)
		return
	var built := _build_semantic_records()
	if not bool(built.get("success", false)):
		_fail("semantic sampling", built)
		return

	presentation_manifest_hash = GeoUtils.payload_hash({
		"lab": "g7.4-semantic-field-lab",
		"sample_count": semantic_records.size(),
		"field_ids": FIELD_KEYS,
		"bundle_checksums": _bundle_checksums(),
		"grid": [LAT_SEGMENTS, LON_SEGMENTS],
	})

	if DisplayServer.get_name() == "headless":
		var smoke := _headless_smoke()
		if not bool(smoke.get("success", false)):
			_fail("headless smoke", smoke)
			return
		print("G7.4 Semantic Field Lab: PASS (samples=%d fields=%d vocabulary_only=%d faces=%s presentation_hash=%s)" % [
			semantic_records.size(),
			FIELD_KEYS.size(),
			VOCABULARY_ONLY_FIELDS.size(),
			",".join(_sorted_face_names()),
			presentation_manifest_hash,
		])
		get_tree().quit(0)
		return

	_setup_planet_material()
	_update_presentation_lod(true)
	_rebuild_river_overlay()
	_update_camera()
	_update_hud()


func _process(delta: float) -> void:
	if auto_orbit:
		yaw_deg = fposmod(yaw_deg + 5.0 * delta, 360.0)
	_update_camera_input(delta)
	_update_presentation_lod(false)
	_update_camera()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_select_field(0)
		KEY_2:
			_select_field(1)
		KEY_3:
			_select_field(2)
		KEY_4:
			_select_field(3)
		KEY_5:
			_select_field(4)
		KEY_F:
			if river_node != null:
				river_node.visible = not river_node.visible
		KEY_SPACE:
			auto_orbit = not auto_orbit
		KEY_R:
			current_field_index = 0
			yaw_deg = CAMERA_DEFAULT_YAW_DEG
			pitch_deg = CAMERA_DEFAULT_PITCH_DEG
			camera_distance = CAMERA_DEFAULT_DISTANCE
			auto_orbit = false
			_update_presentation_lod(true)
	_update_hud()


func _prepare_semantic_sources() -> Dictionary:
	macro_provider = MacroProvider.new(LAB_SEED, Fixture.RADIUS_M, 900.0, 600000.0, 4, 0.5, 12.0)
	feature_graph = FeatureGraph.new()
	var configured: Dictionary = feature_graph.configure(Fixture.BODY_ID, Fixture.FRAME_ID)
	if not bool(configured.get("success", false)):
		return configured
	var valley := _lab_valley_feature()
	var added: Dictionary = feature_graph.add_feature(valley)
	if not bool(added.get("success", false)):
		return added
	var sealed: Dictionary = feature_graph.seal()
	if not bool(sealed.get("success", false)):
		return sealed
	compiled_river = RiverProvider.compile(Fixture.river())
	if not bool(compiled_river.get("success", false)):
		return compiled_river
	addressing = CubeSphereAddressing.new()
	return {"success": true}


func _lab_valley_feature() -> Dictionary:
	var center := _direction(5.0, 46.0) * Fixture.RADIUS_M
	return WorldFeature.create(
		Fixture.BODY_ID,
		FeatureType.VALLEY,
		LAB_SEED + 1,
		LAB_VALLEY_GENERATOR_VERSION,
		LAB_VALLEY_STABLE_KEY,
		Fixture.FRAME_ID,
		FeatureBounds.sphere(Fixture.FRAME_ID, _array3(center), LAB_VALLEY_RADIUS_M),
		[
			FeatureAnchor.create(
				"feature-anchor/g7-4-semantic-lab-valley-center",
				Fixture.FRAME_ID,
				"feature-anchor-role/center",
				_array3(center)
			),
		],
		"",
		[],
		{
			"geometry_kind": "lab-bounds-projection",
			"semantic": "g7-4-derived-visualization-fixture",
			"production_canonical": false,
		}
	)


func _build_semantic_records() -> Dictionary:
	semantic_records.clear()
	field_ranges.clear()
	observed_faces.clear()
	for y in range(GRID_HEIGHT):
		var lat_t := float(y) / float(LAT_SEGMENTS)
		var latitude := lerpf(LAT_MIN_DEG, LAT_MAX_DEG, lat_t)
		for x in range(GRID_WIDTH):
			var lon_t := float(x) / float(LON_SEGMENTS)
			var longitude := lerpf(LON_MIN_DEG, LON_MAX_DEG, lon_t)
			var direction := _direction(latitude, longitude)
			var position := direction * Fixture.RADIUS_M
			var query := SemanticQuery.create(
				Fixture.BODY_ID,
				Fixture.FRAME_ID,
				_array3(position),
				FIELD_KEYS
			)
			var g3: Dictionary = G3Adapter.sample(query, macro_provider)
			var g5: Dictionary = G5Adapter.sample(query, feature_graph)
			var g6: Dictionary = G6Adapter.sample(query, [compiled_river])
			var composed: Dictionary = Composer.compose(query, [g3, g5, g6])
			if not bool(composed.get("success", false)):
				return {
					"success": false,
					"error_code": "G7_4_SEMANTIC_COMPOSITION_FAILED",
					"details": {"x": x, "y": y, "result": composed},
				}
			var bundle: Dictionary = composed["details"]["bundle"]
			var values: Dictionary = {}
			var sample_checksums: Dictionary = {}
			var provenance_checksums: Dictionary = {}
			for field_id in FIELD_KEYS:
				var sample: Dictionary = bundle["samples"][field_id]
				var value := float(sample["value"])
				values[field_id] = value
				sample_checksums[field_id] = String(sample["checksum"])
				provenance_checksums[field_id] = String(sample["provenance"]["checksum"])
				_update_field_range(field_id, value)

			var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, _array3(direction), ADDRESSING_LOD)
			if not bool(addressed.get("success", false)):
				return addressed
			var face := String(addressed["details"]["cell"]["face"])
			observed_faces[face] = true
			semantic_records.append({
				"grid_x": x,
				"grid_y": y,
				"latitude_deg": latitude,
				"longitude_deg": longitude,
				"direction": direction,
				"values": values,
				"bundle_checksum": String(bundle["checksum"]),
				"receipt_checksum": String(composed["details"]["receipt"]["checksum"]),
				"sample_checksums": sample_checksums,
				"provenance_checksums": provenance_checksums,
				"face": face,
			})
	return {"success": true}


func _headless_smoke() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {"success": false, "error_code": "G7_4_MANIFEST_MISSING"}
	var manifest_value = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (manifest_value is Dictionary):
		return {"success": false, "error_code": "G7_4_MANIFEST_INVALID"}
	var manifest: Dictionary = manifest_value
	if String(manifest.get("status", "")) not in ["IMPLEMENTED_CANDIDATE", "ACCEPTED"]:
		return {"success": false, "error_code": "G7_4_MANIFEST_STATUS_INVALID"}
	if semantic_records.size() != EXPECTED_SAMPLE_COUNT:
		return {"success": false, "error_code": "G7_4_SAMPLE_COUNT_MISMATCH", "details": {"actual": semantic_records.size()}}
	if not observed_faces.has("PX") or not observed_faces.has("PZ"):
		return {"success": false, "error_code": "G7_4_EXPECTED_PX_PZ_FACES_MISSING", "details": {"faces": observed_faces.keys()}}
	var lod_policy: Dictionary = manifest.get("presentation_lod", {})
	var lod_levels: Array = lod_policy.get("levels", [])
	if String(lod_policy.get("mode", "")) != "CAMERA_DISTANCE_DERIVED" or lod_levels.size() != 4:
		return {"success": false, "error_code": "G7_4_PRESENTATION_LOD_POLICY_INVALID"}
	var manifest_strides: Array[int] = []
	for level_value in lod_levels:
		if not (level_value is Dictionary):
			return {"success": false, "error_code": "G7_4_PRESENTATION_LOD_LEVEL_INVALID"}
		manifest_strides.append(int(Dictionary(level_value).get("stride", 0)))
	if manifest_strides != PRESENTATION_LOD_STRIDES:
		return {"success": false, "error_code": "G7_4_PRESENTATION_LOD_STRIDE_MISMATCH", "details": {"actual": manifest_strides}}
	if bool(lod_policy.get("changes_canonical_semantics", true)):
		return {"success": false, "error_code": "G7_4_PRESENTATION_LOD_OWNS_SEMANTICS"}
	var registry_validation: Dictionary = Registry.validate_registry()
	if not bool(registry_validation.get("success", false)):
		return registry_validation
	for field_id in FIELD_KEYS:
		var availability := String(Registry.descriptor(field_id).get("metadata", {}).get("availability", ""))
		if availability == Registry.VOCABULARY_ONLY:
			return {"success": false, "error_code": "G7_4_AVAILABLE_FIELD_MARKED_VOCABULARY_ONLY", "details": {"field_id": field_id}}
	for field_id in VOCABULARY_ONLY_FIELDS:
		var availability := String(Registry.descriptor(field_id).get("metadata", {}).get("availability", ""))
		if availability != Registry.VOCABULARY_ONLY:
			return {"success": false, "error_code": "G7_4_VOCABULARY_ONLY_FIELD_UNEXPECTEDLY_ACTIVE", "details": {"field_id": field_id}}
	if not FileAccess.file_exists(G73_VALIDATION_PATH):
		return {"success": false, "error_code": "G7_3_VALIDATION_MISSING"}
	var g73_value = JSON.parse_string(FileAccess.get_file_as_string(G73_VALIDATION_PATH))
	if not (g73_value is Dictionary) or String(g73_value.get("decision", "")) != "ACCEPTED":
		return {"success": false, "error_code": "G7_3_NOT_ACCEPTED"}
	if not GeoUtils.is_lower_hex_64(presentation_manifest_hash):
		return {"success": false, "error_code": "G7_4_PRESENTATION_HASH_INVALID"}
	return {"success": true}


func _select_field(index: int) -> void:
	if index < 0 or index >= FIELD_KEYS.size() or index == current_field_index:
		return
	current_field_index = index
	_rebuild_patch_mesh()


func _presentation_lod_for_distance(distance: float) -> int:
	if distance < PRESENTATION_LOD1_DISTANCE:
		return 0
	if distance < PRESENTATION_LOD2_DISTANCE:
		return 1
	if distance < PRESENTATION_LOD3_DISTANCE:
		return 2
	return 3


func _presentation_stride() -> int:
	var index := clampi(current_presentation_lod, 0, PRESENTATION_LOD_STRIDES.size() - 1)
	return PRESENTATION_LOD_STRIDES[index]


func _presentation_grid_dimensions() -> Vector2i:
	var stride := _presentation_stride()
	return Vector2i(int(LON_SEGMENTS / stride) + 1, int(LAT_SEGMENTS / stride) + 1)


func _update_presentation_lod(force_rebuild: bool) -> void:
	var desired := _presentation_lod_for_distance(camera_distance)
	if not force_rebuild and desired == current_presentation_lod:
		return
	current_presentation_lod = desired
	if not semantic_records.is_empty():
		_rebuild_patch_mesh()
	var dims := _presentation_grid_dimensions()
	print("G7.4 presentation LOD -> %d stride=%d mesh=%dx%d camera=%.3f (semantic samples remain %d)" % [
		current_presentation_lod,
		_presentation_stride(),
		dims.x,
		dims.y,
		camera_distance,
		semantic_records.size(),
	])


func _rebuild_patch_mesh() -> void:
	if patch_node == null:
		patch_node = MeshInstance3D.new()
		patch_node.name = "SemanticPatch"
		add_child(patch_node)
	var stride := _presentation_stride()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(0, LAT_SEGMENTS, stride):
		for x in range(0, LON_SEGMENTS, stride):
			var i00 := y * GRID_WIDTH + x
			var i10 := y * GRID_WIDTH + (x + stride)
			var i01 := (y + stride) * GRID_WIDTH + x
			var i11 := (y + stride) * GRID_WIDTH + (x + stride)
			_add_patch_vertex(surface, semantic_records[i00])
			_add_patch_vertex(surface, semantic_records[i10])
			_add_patch_vertex(surface, semantic_records[i11])
			_add_patch_vertex(surface, semantic_records[i00])
			_add_patch_vertex(surface, semantic_records[i11])
			_add_patch_vertex(surface, semantic_records[i01])
	surface.generate_normals()
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	patch_node.mesh = mesh


func _add_patch_vertex(surface: SurfaceTool, record: Dictionary) -> void:
	var direction: Vector3 = record["direction"]
	var height_m := float(record["values"][Registry.SURFACE_HEIGHT_M])
	var display_radius := DISPLAY_RADIUS + DISPLAY_SURFACE_OFFSET + height_m * DISPLAY_HEIGHT_SCALE
	surface.set_color(_field_color(record, FIELD_KEYS[current_field_index]))
	surface.add_vertex(direction * display_radius)


func _rebuild_river_overlay() -> void:
	if river_node == null:
		river_node = MeshInstance3D.new()
		river_node.name = "CanonicalRiverCenterline"
		add_child(river_node)
	var points: Array = compiled_river.get("details", {}).get("river_spline", {}).get("points_m", [])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for raw_point in points:
		var point := _vector3(raw_point)
		surface.add_vertex(point.normalized() * (DISPLAY_RADIUS + 0.085))
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.98, 1.0, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, material)
	river_node.mesh = mesh


func _setup_planet_material() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.17, 0.19, 1.0)
	material.roughness = 1.0
	planet.material_override = material


func _field_color(record: Dictionary, field_id: String) -> Color:
	var value := float(record["values"][field_id])
	var field_range: Dictionary = field_ranges[field_id]
	var min_value := float(field_range["min"])
	var max_value := float(field_range["max"])
	var normalized := 0.5
	if max_value - min_value > 0.000000001:
		normalized = clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)
	match field_id:
		Registry.SURFACE_HEIGHT_M:
			return _three_color(normalized, Color(0.05, 0.16, 0.32), Color(0.18, 0.55, 0.34), Color(0.92, 0.92, 0.84))
		Registry.VALLEY_INFLUENCE:
			return Color(0.13, 0.14, 0.16).lerp(Color(0.95, 0.45, 0.12), clampf(value, 0.0, 1.0))
		Registry.RIVER_DISTANCE_M:
			var near_factor := 1.0 - clampf(value / 420000.0, 0.0, 1.0)
			return Color(0.11, 0.12, 0.15).lerp(Color(0.05, 0.75, 0.98), near_factor)
		Registry.RIVER_WIDTH_M:
			return Color(0.18, 0.10, 0.24).lerp(Color(0.88, 0.50, 0.95), normalized)
		Registry.FLUID_SURFACE_DISTANCE_M:
			var surface_factor := 1.0 - clampf(value / 420000.0, 0.0, 1.0)
			return Color(0.10, 0.11, 0.18).lerp(Color(0.15, 0.95, 0.70), surface_factor)
		_:
			return Color(0.5, 0.5, 0.5)


func _three_color(t: float, low: Color, mid: Color, high: Color) -> Color:
	if t <= 0.5:
		return low.lerp(mid, t * 2.0)
	return mid.lerp(high, (t - 0.5) * 2.0)


func _update_field_range(field_id: String, value: float) -> void:
	if not field_ranges.has(field_id):
		field_ranges[field_id] = {"min": value, "max": value}
		return
	var current: Dictionary = field_ranges[field_id]
	current["min"] = minf(float(current["min"]), value)
	current["max"] = maxf(float(current["max"]), value)
	field_ranges[field_id] = current


func _update_camera_input(delta: float) -> void:
	var orbit_speed := 30.0 * delta
	if Input.is_key_pressed(KEY_A):
		yaw_deg += orbit_speed
	if Input.is_key_pressed(KEY_D):
		yaw_deg -= orbit_speed
	if Input.is_key_pressed(KEY_Q):
		pitch_deg = clampf(pitch_deg + orbit_speed, -75.0, 75.0)
	if Input.is_key_pressed(KEY_E):
		pitch_deg = clampf(pitch_deg - orbit_speed, -75.0, 75.0)
	var zoom_speed := maxf(0.35, (camera_distance - DISPLAY_RADIUS) * 1.5) * delta
	if Input.is_key_pressed(KEY_W):
		camera_distance = maxf(CAMERA_MIN_DISTANCE, camera_distance - zoom_speed)
	if Input.is_key_pressed(KEY_S):
		camera_distance = minf(CAMERA_MAX_DISTANCE, camera_distance + zoom_speed)


func _update_camera() -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var cp := cos(pitch)
	var direction := Vector3(cp * cos(yaw), sin(pitch), cp * sin(yaw)).normalized()
	camera.position = direction * camera_distance
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _update_hud() -> void:
	if hud == null or semantic_records.is_empty():
		return
	var field_id := FIELD_KEYS[current_field_index]
	var descriptor := Registry.descriptor(field_id)
	var field_range: Dictionary = field_ranges[field_id]
	var center_index := int(semantic_records.size() / 2)
	var center: Dictionary = semantic_records[center_index]
	var unavailable: Array[String] = []
	for vocabulary_field in VOCABULARY_ONLY_FIELDS:
		unavailable.append(String(vocabulary_field).trim_prefix("geo/"))
	var lod_grid := _presentation_grid_dimensions()
	hud.text = "G7.4 - Semantic Field Lab [DERIVED PRESENTATION]\n" + \
		"Field %d/5: %s  unit=%s  availability=%s\n" % [current_field_index + 1, field_id, String(descriptor.get("unit", "")), String(descriptor.get("metadata", {}).get("availability", ""))] + \
		"Range: %.6f .. %.6f   semantic-samples=%d   source-grid=%dx%d   faces=%s\n" % [float(field_range["min"]), float(field_range["max"]), semantic_records.size(), GRID_WIDTH, GRID_HEIGHT, ",".join(_sorted_face_names())] + \
		"Presentation LOD%d stride=%d mesh-grid=%dx%d camera=%.2f (LOD0 near/fine -> LOD3 far/coarse)\n" % [current_presentation_lod, _presentation_stride(), lod_grid.x, lod_grid.y, camera_distance] + \
		"Center bundle=%s  provenance=%s\n" % [String(center["bundle_checksum"]).substr(0, 16), String(center["provenance_checksums"][field_id]).substr(0, 16)] + \
		"Presentation hash=%s\n" % presentation_manifest_hash.substr(0, 16) + \
		"Vocabulary-only (NOT faked): %s\n" % ", ".join(unavailable) + \
		"1..5 fields | F river | W/S zoom + auto LOD | A/D yaw | Q/E pitch | Space orbit | R reset\n" + \
		"LOD/camera/colors/mesh density are excluded from canonical semantic checksums."


func _bundle_checksums() -> Array[String]:
	var result: Array[String] = []
	for record in semantic_records:
		result.append(String(record["bundle_checksum"]))
	return result


func _sorted_face_names() -> Array[String]:
	var result: Array[String] = []
	for raw_face in observed_faces.keys():
		result.append(String(raw_face))
	result.sort()
	return result


func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _fail(stage: String, result: Dictionary) -> void:
	push_error("G7.4 %s failed: %s %s" % [stage, String(result.get("error_code", "UNKNOWN")), result.get("details", {})])
	get_tree().quit(1)
