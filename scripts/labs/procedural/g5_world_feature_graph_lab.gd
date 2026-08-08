extends Node3D

const FeatureType = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const FeatureBounds = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FeatureAnchor = preload("res://scripts/simulation/procedural/contracts/feature_anchor.gd")
const FeatureRelation = preload("res://scripts/simulation/procedural/contracts/feature_relation.gd")
const WorldFeature = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")
const FeatureQuery = preload("res://scripts/simulation/procedural/contracts/feature_query.gd")
const FeatureGraph = preload("res://scripts/simulation/procedural/features/feature_graph.gd")

const BODY_ID := "body/procedural-g5-lab"
const FRAME_ID := "body/procedural-g5-lab/fixed"
const RADIUS_M := 6000000.0
const DISPLAY_RADIUS := 5.0
const SEED := 2026080805

@onready var feature_lines: MeshInstance3D = $FeatureLines
@onready var hud: Label = $HUD/Panel/Label

var graph = FeatureGraph.new()
var features: Array = []
var rotation_speed := 0.15


func _ready() -> void:
	var configured: Dictionary = graph.configure(BODY_ID, FRAME_ID)
	if not bool(configured.get("success", false)):
		_fail("configure", configured)
		return
	features = _make_features()
	for feature in features:
		var added: Dictionary = graph.add_feature(feature)
		if not bool(added.get("success", false)):
			_fail("add feature", added)
			return
	var sealed: Dictionary = graph.seal()
	if not bool(sealed.get("success", false)):
		_fail("seal", sealed)
		return
	_build_lines()
	_update_hud()
	if DisplayServer.get_name() == "headless":
		print("G5 World Feature Graph lab: PASS (%d features, manifest=%s)" % [graph.size(), graph.manifest_hash().substr(0, 12)])
		get_tree().quit(0)


func _process(delta: float) -> void:
	rotate_y(rotation_speed * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_A:
			rotation_speed = -0.35
		elif event.keycode == KEY_D:
			rotation_speed = 0.35
		elif event.keycode == KEY_SPACE:
			rotation_speed = 0.0 if absf(rotation_speed) > 0.0001 else 0.15


func _make_features() -> Array:
	var fault_anchors: Array = []
	for index in range(7):
		var lon := 30.0 + float(index) * 5.0
		fault_anchors.append(FeatureAnchor.create(
			"feature-anchor/lab-fault-%02d" % index,
			FRAME_ID,
			"feature-anchor-role/control-point",
			_array3(_direction(5.0 * sin(float(index) * 0.7), lon) * RADIUS_M)
		))
	var fault_center := _direction(0.0, 45.0) * RADIUS_M
	var fault := WorldFeature.create(
		BODY_ID, FeatureType.FAULT, SEED, "1.0.0", "feature-key/lab-fault", FRAME_ID,
		FeatureBounds.sphere(FRAME_ID, _array3(fault_center), 1800000.0), fault_anchors, "", [],
		{"geometry_kind": "polyline"}
	)

	var valley_center := _direction(15.0, -35.0) * RADIUS_M
	var valley := WorldFeature.create(
		BODY_ID, FeatureType.VALLEY, SEED + 1, "1.0.0", "feature-key/lab-valley", FRAME_ID,
		FeatureBounds.sphere(FRAME_ID, _array3(valley_center), 1000000.0),
		[
			FeatureAnchor.create("feature-anchor/lab-valley-start", FRAME_ID, "feature-anchor-role/start", _array3(_direction(8.0, -48.0) * RADIUS_M)),
			FeatureAnchor.create("feature-anchor/lab-valley-mid", FRAME_ID, "feature-anchor-role/control-point", _array3(_direction(15.0, -35.0) * RADIUS_M)),
			FeatureAnchor.create("feature-anchor/lab-valley-end", FRAME_ID, "feature-anchor-role/end", _array3(_direction(22.0, -22.0) * RADIUS_M)),
		], "", [], {"geometry_kind": "spline"}
	)

	var river := WorldFeature.create(
		BODY_ID, FeatureType.RIVER, SEED + 2, "1.0.0", "feature-key/lab-river", FRAME_ID,
		FeatureBounds.sphere(FRAME_ID, _array3(valley_center), 850000.0),
		[
			FeatureAnchor.create("feature-anchor/lab-river-source", FRAME_ID, "feature-anchor-role/source", _array3(_direction(20.0, -42.0) * (RADIUS_M + 15.0))),
			FeatureAnchor.create("feature-anchor/lab-river-mouth", FRAME_ID, "feature-anchor-role/mouth", _array3(_direction(10.0, -28.0) * (RADIUS_M + 15.0))),
		], String(valley["feature_id"]),
		[FeatureRelation.create("feature-relation/flows-through", String(valley["feature_id"]))],
		{"geometry_kind": "spline"}
	)

	var cave_center := _direction(-25.0, 145.0) * (RADIUS_M - 100000.0)
	var cave := WorldFeature.create(
		BODY_ID, FeatureType.CAVE_SYSTEM, SEED + 3, "1.0.0", "feature-key/lab-cave", FRAME_ID,
		FeatureBounds.sphere(FRAME_ID, _array3(cave_center), 220000.0),
		[FeatureAnchor.create("feature-anchor/lab-cave-core", FRAME_ID, "feature-anchor-role/core", _array3(cave_center))],
		"", [], {"geometry_kind": "volume-network"}
	)
	return [fault, valley, river, cave]


func _build_lines() -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for feature in features:
		var anchors: Array = feature["anchors"]
		if anchors.size() == 1:
			var p := _display_point(anchors[0]["position_m"])
			var tangent := p.normalized().cross(Vector3.UP)
			if tangent.length_squared() < 0.0001:
				tangent = p.normalized().cross(Vector3.RIGHT)
			tangent = tangent.normalized() * 0.12
			immediate.surface_add_vertex(p - tangent)
			immediate.surface_add_vertex(p + tangent)
			continue
		for index in range(anchors.size() - 1):
			immediate.surface_add_vertex(_display_point(anchors[index]["position_m"]))
			immediate.surface_add_vertex(_display_point(anchors[index + 1]["position_m"]))
	immediate.surface_end()
	feature_lines.mesh = immediate


func _update_hud() -> void:
	var fault: Dictionary = features[0]
	var query := FeatureQuery.create(BODY_ID, FRAME_ID, fault["bounds"]["center_m"], 1000.0, [FeatureType.FAULT])
	var result: Dictionary = graph.query(query)
	var query_count := 0
	if bool(result.get("success", false)):
		query_count = result["details"]["feature_ids"].size()
	hud.text = "G5 — World Feature Graph\n\nFeatures: %d\nManifest: %s\nFault query: %d match\n\nFault crosses cube-face seam but keeps one ID.\nCave is below the reference surface.\nRiver has a parent/relationship to valley.\n\nA / D: rotate    Space: pause" % [graph.size(), graph.manifest_hash().substr(0, 16), query_count]


func _display_point(position_m: Array) -> Vector3:
	var value := Vector3(float(position_m[0]), float(position_m[1]), float(position_m[2]))
	var normalized_radius := value.length() / RADIUS_M
	return value.normalized() * DISPLAY_RADIUS * normalized_radius


func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _fail(stage: String, result: Dictionary) -> void:
	push_error("G5 lab %s failed: %s %s" % [stage, result.get("error_code", ""), result.get("details", {})])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
