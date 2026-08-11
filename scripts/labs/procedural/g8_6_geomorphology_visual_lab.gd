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
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
const Deformation = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
const ErosionDeposition = preload("res://scripts/simulation/procedural/geomorphology/erosion_deposition_baseline_v1.gd")

const MANIFEST_PATH := "res://config/procedural/g8-6-geomorphology-visual-lab.v1.json"
const G85_VALIDATION_PATH := "res://validation/g8-5-cross-cell-cross-lod-geomorphology-invariance-validation.json"

const LAB_SEED := 20260811086
const VALLEY_STABLE_KEY := "feature-key/g8-6-visual-lab-valley"
const VALLEY_RADIUS_M := 1150000.0

# Local corridor is intentionally centered on the real G6 PX/PZ seam crossing.
# It is wide enough to contain channel + bank + floodplain + erosion/deposition
# lobes while remaining fine enough to resolve tens-of-metres river geometry.
const CROSS_MIN_M := -220.0
const CROSS_MAX_M := 220.0
const ALONG_MIN_M := -800.0
const ALONG_MAX_M := 800.0
const CROSS_SEGMENTS := 32
const ALONG_SEGMENTS := 16
const GRID_WIDTH := CROSS_SEGMENTS + 1
const GRID_HEIGHT := ALONG_SEGMENTS + 1
const EXPECTED_SAMPLE_COUNT := GRID_WIDTH * GRID_HEIGHT
const ADDRESSING_LOD := 8

# Derived presentation only. Horizontal and vertical display scales are not world
# truth. Vertical exaggeration is deliberate so 1-100 m deformation can be read.
const DISPLAY_HORIZONTAL_SCALE := 0.01
const DISPLAY_VERTICAL_SCALE := 0.035
const DISPLAY_OVERLAY_LIFT := 0.05

const CAMERA_MIN_DISTANCE := 8.0
const CAMERA_MAX_DISTANCE := 36.0
const CAMERA_DEFAULT_DISTANCE := 16.0
const CAMERA_DEFAULT_YAW_DEG := 42.0
const CAMERA_DEFAULT_PITCH_DEG := 27.0
const PRESENTATION_LOD_STRIDES: Array[int] = [1, 2, 4, 8]
const PRESENTATION_LOD1_DISTANCE := 13.0
const PRESENTATION_LOD2_DISTANCE := 19.0
const PRESENTATION_LOD3_DISTANCE := 27.0

const INPUT_FIELDS: Array[String] = [
	Registry.SURFACE_HEIGHT_M,
	Registry.VALLEY_INFLUENCE,
	Registry.RIVER_DISTANCE_M,
	Registry.RIVER_WIDTH_M,
]

const VIEW_RESOLVED_HEIGHT := "resolved_surface_height_m"
const VIEW_TOTAL_DELTA := "total_delta_height_m"
const VIEW_IDS: Array[String] = [
	VIEW_RESOLVED_HEIGHT,
	VIEW_TOTAL_DELTA,
	Deformation.COMPONENT_VALLEY,
	Deformation.COMPONENT_RIVER_CHANNEL,
	Deformation.COMPONENT_BANK,
	Deformation.COMPONENT_FLOODPLAIN,
	Deformation.COMPONENT_EROSION_DEPOSITION,
]

@onready var patch: MeshInstance3D = $GeomorphologyPatch
@onready var river_overlay: MeshInstance3D = $RiverOverlay
@onready var seam_overlay: MeshInstance3D = $SeamOverlay
@onready var camera: Camera3D = $Camera3D
@onready var hud: Label = $HUD/Panel/Margin/VBox/Status

var macro_provider
var feature_graph
var compiled_river: Dictionary = {}
var addressing
var profile: Dictionary = {}
var records: Array[Dictionary] = []
var value_ranges: Dictionary = {}
var observed_faces: Dictionary = {}
var seam_edge_count := 0
var canonical_truth_hash := ""
var source_bundle_hash := ""
var height_reference_m := 0.0
var seam_center_world := Vector3.ZERO
var tangent_along := Vector3.FORWARD
var tangent_cross := Vector3.RIGHT

var current_view_index := 0
var show_resolved_geometry := true
var current_presentation_lod := -1
var yaw_deg := CAMERA_DEFAULT_YAW_DEG
var pitch_deg := CAMERA_DEFAULT_PITCH_DEG
var camera_distance := CAMERA_DEFAULT_DISTANCE
var auto_orbit := false


func _ready() -> void:
	var prepared: Dictionary = _prepare_sources()
	if not bool(prepared.get("success", false)):
		_fail("source preparation", prepared)
		return
	var sampled: Dictionary = _sample_corridor()
	if not bool(sampled.get("success", false)):
		_fail("corridor sampling", sampled)
		return

	canonical_truth_hash = _canonical_hash()
	source_bundle_hash = GeoUtils.payload_hash(_bundle_checksums())
	height_reference_m = float(records[int(records.size() / 2)]["source_surface_height_m"])
	seam_edge_count = _count_seam_edges()

	if DisplayServer.get_name() == "headless":
		var smoke: Dictionary = _headless_smoke()
		if not bool(smoke.get("success", false)):
			_fail("headless smoke", smoke)
			return
		print("G8.6 Geomorphology Visual Lab: PASS (samples=%d faces=%s seam_edges=%d truth_hash=%s)" % [
			records.size(),
			",".join(_sorted_face_names()),
			seam_edge_count,
			canonical_truth_hash,
		])
		get_tree().quit(0)
		return

	_update_presentation_lod(true)
	_rebuild_river_overlay()
	_rebuild_seam_overlay()
	_update_camera()
	_update_hud()


func _process(delta: float) -> void:
	if auto_orbit:
		yaw_deg = fposmod(yaw_deg + 7.0 * delta, 360.0)
	_update_camera_input(delta)
	_update_presentation_lod(false)
	_update_camera()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_select_view(0)
		KEY_2:
			_select_view(1)
		KEY_3:
			_select_view(2)
		KEY_4:
			_select_view(3)
		KEY_5:
			_select_view(4)
		KEY_6:
			_select_view(5)
		KEY_7:
			_select_view(6)
		KEY_G:
			show_resolved_geometry = not show_resolved_geometry
			_rebuild_patch_mesh()
			_rebuild_river_overlay()
			_rebuild_seam_overlay()
		KEY_F:
			river_overlay.visible = not river_overlay.visible
		KEY_X:
			seam_overlay.visible = not seam_overlay.visible
		KEY_SPACE:
			auto_orbit = not auto_orbit
		KEY_R:
			current_view_index = 0
			show_resolved_geometry = true
			yaw_deg = CAMERA_DEFAULT_YAW_DEG
			pitch_deg = CAMERA_DEFAULT_PITCH_DEG
			camera_distance = CAMERA_DEFAULT_DISTANCE
			auto_orbit = false
			_update_presentation_lod(true)
			_rebuild_river_overlay()
			_rebuild_seam_overlay()
	_update_hud()


func _prepare_sources() -> Dictionary:
	macro_provider = MacroProvider.new(LAB_SEED, Fixture.RADIUS_M, 900.0, 600000.0, 4, 0.5, 12.0)
	feature_graph = FeatureGraph.new()
	var configured: Dictionary = feature_graph.configure(Fixture.BODY_ID, Fixture.FRAME_ID)
	if not bool(configured.get("success", false)):
		return configured
	var added: Dictionary = feature_graph.add_feature(_valley_feature())
	if not bool(added.get("success", false)):
		return added
	var sealed: Dictionary = feature_graph.seal()
	if not bool(sealed.get("success", false)):
		return sealed

	compiled_river = RiverProvider.compile(Fixture.river())
	if not bool(compiled_river.get("success", false)):
		return compiled_river
	addressing = CubeSphereAddressing.new()
	profile = Profile.create("geomorphology-profile/g8-6-visual-lab")
	var profile_validation: Dictionary = Profile.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return profile_validation
	return _prepare_seam_frame()


func _prepare_seam_frame() -> Dictionary:
	var points: Array = compiled_river.get("details", {}).get("river_spline", {}).get("points_m", [])
	if points.size() < 2:
		return {"success": false, "error_code": "G8_6_RIVER_POINTS_MISSING"}
	for index in range(points.size() - 1):
		var a := _vector3(points[index])
		var b := _vector3(points[index + 1])
		var addressed_a: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, _array3(a), ADDRESSING_LOD)
		var addressed_b: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, _array3(b), ADDRESSING_LOD)
		if not bool(addressed_a.get("success", false)) or not bool(addressed_b.get("success", false)):
			continue
		var face_a := String(addressed_a["details"]["cell"]["face"])
		var face_b := String(addressed_b["details"]["cell"]["face"])
		if not ((face_a == "PX" and face_b == "PZ") or (face_a == "PZ" and face_b == "PX")):
			continue
		var da := a.x - a.z
		var db := b.x - b.z
		var denominator := da - db
		if absf(denominator) <= 0.000000001:
			continue
		var t := clampf(da / denominator, 0.0, 1.0)
		seam_center_world = a.lerp(b, t).normalized() * Fixture.RADIUS_M
		var radial := seam_center_world.normalized()
		var segment_tangent := b - a
		segment_tangent -= radial * segment_tangent.dot(radial)
		if segment_tangent.length_squared() <= 0.000000001:
			continue
		tangent_along = segment_tangent.normalized()
		tangent_cross = radial.cross(tangent_along).normalized()
		return {"success": true, "details": {"segment": index, "t": t}}
	return {"success": false, "error_code": "G8_6_PX_PZ_SEAM_SEGMENT_NOT_FOUND"}


func _sample_corridor() -> Dictionary:
	records.clear()
	value_ranges.clear()
	observed_faces.clear()
	for y in range(GRID_HEIGHT):
		var along_t := float(y) / float(ALONG_SEGMENTS)
		var along_m := lerpf(ALONG_MIN_M, ALONG_MAX_M, along_t)
		for x in range(GRID_WIDTH):
			var cross_t := float(x) / float(CROSS_SEGMENTS)
			var cross_m := lerpf(CROSS_MIN_M, CROSS_MAX_M, cross_t)
			var raw_position := seam_center_world + tangent_along * along_m + tangent_cross * cross_m
			var world_position := raw_position.normalized() * Fixture.RADIUS_M
			var query := SemanticQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, _array3(world_position), INPUT_FIELDS)
			var g3: Dictionary = G3Adapter.sample(query, macro_provider)
			var g5: Dictionary = G5Adapter.sample(query, feature_graph)
			var g6: Dictionary = G6Adapter.sample(query, [compiled_river])
			var composed: Dictionary = Composer.compose(query, [g3, g5, g6])
			if not bool(composed.get("success", false)):
				return {"success": false, "error_code": "G8_6_SEMANTIC_COMPOSITION_FAILED", "details": {"x": x, "y": y, "result": composed}}
			var bundle: Dictionary = composed["details"]["bundle"]
			var geomorph: Dictionary = ErosionDeposition.apply(bundle, profile)
			if not bool(geomorph.get("success", false)):
				return {"success": false, "error_code": "G8_6_GEOMORPHOLOGY_FAILED", "details": {"x": x, "y": y, "result": geomorph}}
			var deformation: Dictionary = geomorph["details"]["deformation"]
			var deformation_validation: Dictionary = Deformation.validate_against_profile(deformation, profile)
			if not bool(deformation_validation.get("success", false)):
				return {"success": false, "error_code": "G8_6_DEFORMATION_INVALID", "details": {"x": x, "y": y, "cause": deformation_validation}}
			var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, _array3(world_position), ADDRESSING_LOD)
			if not bool(addressed.get("success", false)):
				return addressed
			var face := String(addressed["details"]["cell"]["face"])
			observed_faces[face] = true
			var record: Dictionary = {
				"grid_x": x,
				"grid_y": y,
				"cross_m": cross_m,
				"along_m": along_m,
				"world_position_m": _array3(world_position),
				"face": face,
				"bundle_checksum": String(bundle["checksum"]),
				"river_distance_m": float(bundle["samples"][Registry.RIVER_DISTANCE_M]["value"]),
				"river_width_m": float(bundle["samples"][Registry.RIVER_WIDTH_M]["value"]),
				"source_surface_height_m": float(deformation["source_surface_height_m"]),
				"deformation": deformation,
			}
			records.append(record)
			_update_range(VIEW_RESOLVED_HEIGHT, float(deformation["resolved_surface_height_m"]))
			_update_range(VIEW_TOTAL_DELTA, float(deformation["total_delta_height_m"]))
			for component in Deformation.COMPONENT_FIELDS:
				_update_range(component, float(deformation["component_deltas_m"][component]))
	return {"success": true}


func _headless_smoke() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {"success": false, "error_code": "G8_6_MANIFEST_MISSING"}
	var manifest_value = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (manifest_value is Dictionary):
		return {"success": false, "error_code": "G8_6_MANIFEST_INVALID"}
	var manifest: Dictionary = manifest_value
	if String(manifest.get("status", "")) not in ["IMPLEMENTED_CANDIDATE", "AUTOMATED_ACCEPTED_MANUAL_PENDING", "ACCEPTED"]:
		return {"success": false, "error_code": "G8_6_MANIFEST_STATUS_INVALID"}
	if records.size() != EXPECTED_SAMPLE_COUNT:
		return {"success": false, "error_code": "G8_6_SAMPLE_COUNT_MISMATCH", "details": {"actual": records.size()}}
	if not observed_faces.has("PX") or not observed_faces.has("PZ"):
		return {"success": false, "error_code": "G8_6_PX_PZ_FACES_MISSING", "details": {"faces": observed_faces.keys()}}
	if seam_edge_count <= 0:
		return {"success": false, "error_code": "G8_6_SEAM_NOT_RESOLVED_IN_GRID"}
	if not FileAccess.file_exists(G85_VALIDATION_PATH):
		return {"success": false, "error_code": "G8_5_VALIDATION_MISSING"}
	var g85_value = JSON.parse_string(FileAccess.get_file_as_string(G85_VALIDATION_PATH))
	if not (g85_value is Dictionary) or String(g85_value.get("decision", "")) != "ACCEPTED":
		return {"success": false, "error_code": "G8_5_NOT_ACCEPTED"}
	if not GeoUtils.is_lower_hex_64(canonical_truth_hash) or not GeoUtils.is_lower_hex_64(source_bundle_hash):
		return {"success": false, "error_code": "G8_6_CANONICAL_HASH_INVALID"}
	var lod_policy: Dictionary = manifest.get("presentation_lod", {})
	var strides: Array[int] = []
	for level_value in lod_policy.get("levels", []):
		if not (level_value is Dictionary):
			return {"success": false, "error_code": "G8_6_LOD_LEVEL_INVALID"}
		strides.append(int(Dictionary(level_value).get("stride", 0)))
	if strides != PRESENTATION_LOD_STRIDES or bool(lod_policy.get("changes_canonical_geomorphology", true)):
		return {"success": false, "error_code": "G8_6_PRESENTATION_LOD_POLICY_INVALID"}
	for component in Deformation.COMPONENT_FIELDS:
		var component_range: Dictionary = value_ranges.get(component, {})
		var min_value := float(component_range.get("min", 0.0))
		var max_value := float(component_range.get("max", 0.0))
		if absf(min_value) <= 0.000000001 and absf(max_value) <= 0.000000001:
			return {"success": false, "error_code": "G8_6_COMPONENT_NOT_VISIBLE_IN_CORRIDOR", "details": {"component": component}}
	return {"success": true}


func _select_view(index: int) -> void:
	if index < 0 or index >= VIEW_IDS.size() or index == current_view_index:
		return
	current_view_index = index
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
	return PRESENTATION_LOD_STRIDES[clampi(current_presentation_lod, 0, PRESENTATION_LOD_STRIDES.size() - 1)]


func _presentation_grid_dimensions() -> Vector2i:
	var stride := _presentation_stride()
	return Vector2i(int(CROSS_SEGMENTS / stride) + 1, int(ALONG_SEGMENTS / stride) + 1)


func _update_presentation_lod(force_rebuild: bool) -> void:
	var desired := _presentation_lod_for_distance(camera_distance)
	if not force_rebuild and desired == current_presentation_lod:
		return
	current_presentation_lod = desired
	if not records.is_empty():
		_rebuild_patch_mesh()
		_rebuild_river_overlay()
		_rebuild_seam_overlay()
	var dims := _presentation_grid_dimensions()
	print("G8.6 presentation LOD -> %d stride=%d mesh=%dx%d camera=%.3f canonical=%s" % [
		current_presentation_lod,
		_presentation_stride(),
		dims.x,
		dims.y,
		camera_distance,
		canonical_truth_hash.substr(0, 16),
	])


func _rebuild_patch_mesh() -> void:
	var stride := _presentation_stride()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(0, ALONG_SEGMENTS, stride):
		for x in range(0, CROSS_SEGMENTS, stride):
			var i00 := y * GRID_WIDTH + x
			var i10 := y * GRID_WIDTH + x + stride
			var i01 := (y + stride) * GRID_WIDTH + x
			var i11 := (y + stride) * GRID_WIDTH + x + stride
			_add_vertex(surface, records[i00])
			_add_vertex(surface, records[i10])
			_add_vertex(surface, records[i11])
			_add_vertex(surface, records[i00])
			_add_vertex(surface, records[i11])
			_add_vertex(surface, records[i01])
	surface.generate_normals()
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	patch.mesh = mesh


func _add_vertex(surface: SurfaceTool, record: Dictionary) -> void:
	surface.set_color(_view_color(record))
	surface.add_vertex(_display_position(record, 0.0))


func _display_position(record: Dictionary, lift: float) -> Vector3:
	var deformation: Dictionary = record["deformation"]
	var height_m := float(deformation["resolved_surface_height_m"]) if show_resolved_geometry else float(record["source_surface_height_m"])
	return Vector3(
		float(record["cross_m"]) * DISPLAY_HORIZONTAL_SCALE,
		(height_m - height_reference_m) * DISPLAY_VERTICAL_SCALE + lift,
		float(record["along_m"]) * DISPLAY_HORIZONTAL_SCALE
	)


func _rebuild_river_overlay() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for y in range(0, GRID_HEIGHT, maxi(1, _presentation_stride())):
		var best_record: Dictionary = records[y * GRID_WIDTH]
		for x in range(1, GRID_WIDTH):
			var candidate: Dictionary = records[y * GRID_WIDTH + x]
			if float(candidate["river_distance_m"]) < float(best_record["river_distance_m"]):
				best_record = candidate
		surface.add_vertex(_display_position(best_record, DISPLAY_OVERLAY_LIFT * 1.5))
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.05, 0.92, 1.0, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, material)
	river_overlay.mesh = mesh


func _rebuild_seam_overlay() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH - 1):
			var a: Dictionary = records[y * GRID_WIDTH + x]
			var b: Dictionary = records[y * GRID_WIDTH + x + 1]
			if String(a["face"]) != String(b["face"]):
				surface.add_vertex(_display_position(a, DISPLAY_OVERLAY_LIFT))
				surface.add_vertex(_display_position(b, DISPLAY_OVERLAY_LIFT))
	for y in range(GRID_HEIGHT - 1):
		for x in range(GRID_WIDTH):
			var a: Dictionary = records[y * GRID_WIDTH + x]
			var b: Dictionary = records[(y + 1) * GRID_WIDTH + x]
			if String(a["face"]) != String(b["face"]):
				surface.add_vertex(_display_position(a, DISPLAY_OVERLAY_LIFT))
				surface.add_vertex(_display_position(b, DISPLAY_OVERLAY_LIFT))
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.15, 0.75, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, material)
	seam_overlay.mesh = mesh


func _view_color(record: Dictionary) -> Color:
	var view_id := VIEW_IDS[current_view_index]
	var deformation: Dictionary = record["deformation"]
	var value := 0.0
	if view_id == VIEW_RESOLVED_HEIGHT:
		value = float(deformation["resolved_surface_height_m"])
	elif view_id == VIEW_TOTAL_DELTA:
		value = float(deformation["total_delta_height_m"])
	else:
		value = float(deformation["component_deltas_m"][view_id])
	var range: Dictionary = value_ranges[view_id]
	var min_value := float(range["min"])
	var max_value := float(range["max"])
	if view_id == VIEW_RESOLVED_HEIGHT:
		var t := _normalized(value, min_value, max_value)
		return _three_color(t, Color(0.08, 0.16, 0.30), Color(0.25, 0.55, 0.32), Color(0.88, 0.82, 0.62))
	var magnitude := maxf(absf(min_value), absf(max_value))
	if magnitude <= 0.000000001:
		return Color(0.34, 0.34, 0.36)
	var signed := clampf(value / magnitude, -1.0, 1.0)
	if signed < 0.0:
		return Color(0.95, 0.28, 0.16).lerp(Color(0.92, 0.92, 0.92), signed + 1.0)
	return Color(0.92, 0.92, 0.92).lerp(Color(0.12, 0.52, 0.98), signed)


func _normalized(value: float, min_value: float, max_value: float) -> float:
	if max_value - min_value <= 0.000000001:
		return 0.5
	return clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)


func _three_color(t: float, low: Color, mid: Color, high: Color) -> Color:
	if t <= 0.5:
		return low.lerp(mid, t * 2.0)
	return mid.lerp(high, (t - 0.5) * 2.0)


func _update_range(key: String, value: float) -> void:
	if not value_ranges.has(key):
		value_ranges[key] = {"min": value, "max": value}
		return
	var current: Dictionary = value_ranges[key]
	current["min"] = minf(float(current["min"]), value)
	current["max"] = maxf(float(current["max"]), value)
	value_ranges[key] = current


func _count_seam_edges() -> int:
	var count := 0
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH - 1):
			if String(records[y * GRID_WIDTH + x]["face"]) != String(records[y * GRID_WIDTH + x + 1]["face"]):
				count += 1
	for y in range(GRID_HEIGHT - 1):
		for x in range(GRID_WIDTH):
			if String(records[y * GRID_WIDTH + x]["face"]) != String(records[(y + 1) * GRID_WIDTH + x]["face"]):
				count += 1
	return count


func _canonical_hash() -> String:
	var deformation_checksums: Array[String] = []
	for record in records:
		deformation_checksums.append(String(record["deformation"]["checksum"]))
	return GeoUtils.payload_hash({
		"lab": "g8.6-geomorphology-visual-lab",
		"profile_checksum": String(profile["checksum"]),
		"bundle_checksums": _bundle_checksums(),
		"deformation_checksums": deformation_checksums,
	})


func _bundle_checksums() -> Array[String]:
	var result: Array[String] = []
	for record in records:
		result.append(String(record["bundle_checksum"]))
	return result


func _sorted_face_names() -> Array[String]:
	var result: Array[String] = []
	for face_value in observed_faces.keys():
		result.append(String(face_value))
	result.sort()
	return result


func _update_camera_input(delta: float) -> void:
	var orbit_speed := 38.0 * delta
	if Input.is_key_pressed(KEY_A):
		yaw_deg += orbit_speed
	if Input.is_key_pressed(KEY_D):
		yaw_deg -= orbit_speed
	if Input.is_key_pressed(KEY_Q):
		pitch_deg = clampf(pitch_deg + orbit_speed, 8.0, 78.0)
	if Input.is_key_pressed(KEY_E):
		pitch_deg = clampf(pitch_deg - orbit_speed, 8.0, 78.0)
	var zoom_speed := maxf(0.8, camera_distance * 0.8) * delta
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
	if hud == null or records.is_empty():
		return
	var view_id := VIEW_IDS[current_view_index]
	var range: Dictionary = value_ranges[view_id]
	var dims := _presentation_grid_dimensions()
	var geometry_mode := "RESOLVED G8" if show_resolved_geometry else "SOURCE G3"
	hud.text = "G8.6 - Geomorphology Visual Lab [DERIVED PRESENTATION]\n" + \
		"Geometry: %s   View %d/7: %s   range=%.4f..%.4f m\n" % [geometry_mode, current_view_index + 1, view_id, float(range["min"]), float(range["max"])] + \
		"Canonical samples=%d source-grid=%dx%d faces=%s seam-edges=%d\n" % [records.size(), GRID_WIDTH, GRID_HEIGHT, ",".join(_sorted_face_names()), seam_edge_count] + \
		"Presentation LOD%d stride=%d mesh-grid=%dx%d camera=%.2f\n" % [current_presentation_lod, _presentation_stride(), dims.x, dims.y, camera_distance] + \
		"Truth hash=%s   source-bundles=%s   profile=%s\n" % [canonical_truth_hash.substr(0, 16), source_bundle_hash.substr(0, 16), String(profile["checksum"]).substr(0, 16)] + \
		"Local corridor: cross %.0f..%.0f m, along %.0f..%.0f m; vertical display exaggeration %.1fx\n" % [CROSS_MIN_M, CROSS_MAX_M, ALONG_MIN_M, ALONG_MAX_M, DISPLAY_VERTICAL_SCALE / DISPLAY_HORIZONTAL_SCALE] + \
		"1 resolved | 2 total | 3 valley | 4 channel | 5 bank | 6 floodplain | 7 erosion/deposition\n" + \
		"G source/resolved geometry | F river | X PX/PZ seam | W/S zoom+LOD | A/D yaw | Q/E pitch | Space orbit | R reset\n" + \
		"Camera, colors, overlays, vertical exaggeration and mesh LOD are excluded from canonical geomorphology truth."


func _valley_feature() -> Dictionary:
	var center := _direction(5.0, 46.0) * Fixture.RADIUS_M
	return WorldFeature.create(
		Fixture.BODY_ID,
		FeatureType.VALLEY,
		LAB_SEED + 1,
		"1.0.0",
		VALLEY_STABLE_KEY,
		Fixture.FRAME_ID,
		FeatureBounds.sphere(Fixture.FRAME_ID, _array3(center), VALLEY_RADIUS_M),
		[FeatureAnchor.create("feature-anchor/g8-6-visual-lab-valley-center", Fixture.FRAME_ID, "feature-anchor-role/center", _array3(center))],
		"",
		[],
		{"geometry_kind": "visual-lab-bounds-projection", "production_canonical": false}
	)


func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _fail(label: String, result: Dictionary) -> void:
	push_error("G8.6 %s failed: %s %s" % [label, String(result.get("error_code", "UNKNOWN")), result.get("details", {})])
	get_tree().quit(1)
