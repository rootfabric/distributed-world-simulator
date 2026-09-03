class_name WorldFillPoiKit
extends Node3D

## WF0.6 Landmarks / POI Kit (WORLD FILL train).
##
## Hand-authored, asset-free procedural landmark fixtures that make space
## navigable and recognizable. R1 placement is explicit (fixture-backed);
## procedural eligibility comes later and may only consume the WF0.1
## poi_eligibility hints.
##
## Guarantees:
## - ASSET-FREE: fixtures are built from engine primitive meshes + Label3D.
## - BUDGETED: at most MAX_POIS fixtures exist; oldest evicted first.
## - FAIL-SOFT: unknown kinds and ineligible placements are skipped with
##   explicit reasons, never errors.
## - TRUTH-FREE: presentation nodes and counters only.

const SCHEMA := "world_fill.poi_report.v1"

const MAX_POIS := 32

const POI_KINDS: Array[String] = [
	"outpost",
	"antenna",
	"wreck",
	"mining_camp",
	"research_station",
	"cave_entrance_marker",
	"landing_site",
	"radio_beacon",
	"broken_pipeline",
]

const POI_LABELS := {
	"outpost": "OUTPOST",
	"antenna": "ANTENNA",
	"wreck": "WRECK",
	"mining_camp": "MINING CAMP",
	"research_station": "RESEARCH STATION",
	"cave_entrance_marker": "CAVE ENTRANCE",
	"landing_site": "LANDING SITE",
	"radio_beacon": "RADIO BEACON",
	"broken_pipeline": "BROKEN PIPELINE",
}

## POI kind -> WF0.1 poi_eligibility hint key. Kinds without an entry have no
## contract hint yet and default to eligible.
const ELIGIBILITY_KEYS := {
	"cave_entrance_marker": "cave_entrance",
	"radio_beacon": "beacon",
}

var _records: Array[Dictionary] = []


func spawn_poi(
	kind: String,
	position: Vector3,
	options: Dictionary = {}
) -> Dictionary:
	var report := {
		"schema": SCHEMA,
		"kind": kind,
		"spawned": false,
		"reason": "",
	}
	if not POI_KINDS.has(kind):
		report["reason"] = "UNKNOWN_POI_KIND"
		return report
	if bool(options.get("require_eligible", false)):
		var eligibility: Dictionary = options.get("poi_eligibility", {})
		var hint_key := String(ELIGIBILITY_KEYS.get(kind, kind))
		if eligibility.has(hint_key) and not bool(eligibility[hint_key]):
			report["reason"] = "INELIGIBLE"
			return report
	while _records.size() >= MAX_POIS:
		_evict_oldest()

	var fixture := Node3D.new()
	fixture.name = "Poi_%s_%d" % [kind, _records.size()]
	add_child(fixture)
	match kind:
		"outpost":
			_build_outpost(fixture)
		"antenna":
			_build_antenna(fixture)
		"wreck":
			_build_wreck(fixture)
		"mining_camp":
			_build_mining_camp(fixture)
		"research_station":
			_build_research_station(fixture)
		"cave_entrance_marker":
			_build_cave_marker(fixture)
		"landing_site":
			_build_landing_site(fixture)
		"radio_beacon":
			_build_radio_beacon(fixture)
		"broken_pipeline":
			_build_broken_pipeline(fixture)
	if bool(options.get("include_label", true)):
		_attach_label(fixture, String(POI_LABELS.get(kind, kind.to_upper())))
	fixture.position = position
	var record := {"kind": kind, "node": fixture}
	_records.append(record)
	report["spawned"] = true
	return report


func poi_report() -> Dictionary:
	var by_kind := {}
	for record in _records:
		var kind := String(record.get("kind", ""))
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
	return {
		"schema": SCHEMA,
		"active": _records.size(),
		"max_pois": MAX_POIS,
		"by_kind": by_kind,
	}


func _evict_oldest() -> void:
	if _records.is_empty():
		return
	var evicted: Dictionary = _records.pop_front()
	var node: Node = evicted.get("node", null)
	if node != null and is_instance_valid(node):
		node.free()


func _mesh_instance(mesh: Mesh, color: Color, local_position: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b)
	material.roughness = 0.85
	if color.a > 0.99:
		instance.material_override = material
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = color
		instance.material_override = material
	instance.position = local_position
	return instance


func _attach_label(fixture: Node3D, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.9, 0.92, 0.95)
	label.outline_size = 12
	label.position = Vector3(0.0, 3.4, 0.0)
	fixture.add_child(label)


func _box(size: Vector3, color: Color, local_position: Vector3) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	return _mesh_instance(box, color, local_position)


func _cylinder(radius: float, height: float, color: Color, local_position: Vector3) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	return _mesh_instance(cylinder, color, local_position)


func _metal_color() -> Color:
	return Color(0.42, 0.44, 0.47)


func _accent_color() -> Color:
	return Color(0.85, 0.3, 0.08)


func _build_outpost(fixture: Node3D) -> void:
	fixture.add_child(_box(Vector3(3.0, 2.2, 2.4), Color(0.35, 0.36, 0.38), Vector3(0.0, 1.1, 0.0)))
	fixture.add_child(_box(Vector3(0.9, 1.4, 0.1), Color(0.15, 0.16, 0.18), Vector3(0.0, 0.7, 1.25)))
	fixture.add_child(_cylinder(0.06, 2.4, _metal_color(), Vector3(1.1, 3.4, -0.6)))
	fixture.add_child(_box(Vector3(0.5, 0.2, 0.2), _accent_color(), Vector3(1.1, 4.6, -0.6)))


func _build_antenna(fixture: Node3D) -> void:
	fixture.add_child(_cylinder(0.08, 6.0, _metal_color(), Vector3(0.0, 3.0, 0.0)))
	fixture.add_child(_box(Vector3(1.6, 0.08, 0.08), _metal_color(), Vector3(0.4, 4.6, 0.0)))
	fixture.add_child(_box(Vector3(1.0, 0.08, 0.08), _metal_color(), Vector3(-0.3, 5.2, 0.0)))
	fixture.add_child(_mesh_instance(_sphere(0.16), _accent_color(), Vector3(0.0, 6.1, 0.0)))


func _build_wreck(fixture: Node3D) -> void:
	var hull := _box(Vector3(4.2, 1.4, 2.0), Color(0.22, 0.2, 0.19), Vector3(0.0, 0.7, 0.0))
	hull.rotation_degrees = Vector3(0.0, 24.0, -9.0)
	fixture.add_child(hull)
	var debris_a := _box(Vector3(0.8, 0.5, 0.6), Color(0.2, 0.19, 0.18), Vector3(2.6, 0.25, 0.8))
	fixture.add_child(debris_a)
	var debris_b := _box(Vector3(0.6, 0.4, 0.5), Color(0.24, 0.22, 0.2), Vector3(-2.2, 0.2, -0.9))
	fixture.add_child(debris_b)


func _build_mining_camp(fixture: Node3D) -> void:
	fixture.add_child(_box(Vector3(1.1, 0.9, 1.1), Color(0.4, 0.32, 0.2), Vector3(-1.0, 0.45, 0.0)))
	fixture.add_child(_box(Vector3(0.9, 0.7, 0.9), Color(0.38, 0.3, 0.19), Vector3(0.2, 0.35, 0.9)))
	fixture.add_child(_cylinder(0.25, 3.2, _metal_color(), Vector3(1.4, 1.6, -0.8)))
	fixture.add_child(_mesh_instance(_sphere(0.3), _accent_color(), Vector3(1.4, 3.3, -0.8)))


func _build_research_station(fixture: Node3D) -> void:
	fixture.add_child(_mesh_instance(_sphere(1.8), Color(0.55, 0.6, 0.65, 0.85), Vector3(0.0, 0.4, 0.0)))
	fixture.add_child(_box(Vector3(2.2, 1.0, 1.4), Color(0.4, 0.42, 0.45), Vector3(2.2, 0.5, 0.0)))
	fixture.add_child(_cylinder(0.05, 2.0, _metal_color(), Vector3(-1.2, 2.4, -0.4)))


func _build_cave_marker(fixture: Node3D) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.7
	ring.outer_radius = 0.9
	var ring_instance := _mesh_instance(ring, _accent_color(), Vector3(0.0, 1.0, 0.0))
	ring_instance.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	fixture.add_child(ring_instance)
	fixture.add_child(_cylinder(0.04, 1.0, _metal_color(), Vector3(0.0, 0.5, 0.0)))


func _build_landing_site(fixture: Node3D) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 2.6
	ring.outer_radius = 3.0
	var ring_instance := _mesh_instance(ring, Color(0.85, 0.8, 0.2, 0.8), Vector3(0.0, 0.05, 0.0))
	fixture.add_child(ring_instance)
	for offset in [Vector3(2.8, 0.15, 0.0), Vector3(-2.8, 0.15, 0.0), Vector3(0.0, 0.15, 2.8), Vector3(0.0, 0.15, -2.8)]:
		fixture.add_child(_box(Vector3(0.5, 0.3, 0.5), _metal_color(), offset))


func _build_radio_beacon(fixture: Node3D) -> void:
	fixture.add_child(_cylinder(0.1, 4.5, _metal_color(), Vector3(0.0, 2.25, 0.0)))
	var beacon := _mesh_instance(_sphere(0.28), Color(1.0, 0.25, 0.1), Vector3(0.0, 4.7, 0.0))
	var beacon_material := StandardMaterial3D.new()
	beacon_material.albedo_color = Color(1.0, 0.25, 0.1)
	beacon_material.emission_enabled = true
	beacon_material.emission = Color(0.9, 0.1, 0.02)
	beacon_material.emission_energy_multiplier = 2.0
	beacon.material_override = beacon_material
	fixture.add_child(beacon)


func _build_broken_pipeline(fixture: Node3D) -> void:
	var segment_a := _cylinder(0.4, 3.0, Color(0.45, 0.42, 0.38), Vector3(-1.8, 0.5, 0.0))
	segment_a.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	fixture.add_child(segment_a)
	var segment_b := _cylinder(0.4, 2.2, Color(0.45, 0.42, 0.38), Vector3(2.4, 0.5, 0.3))
	segment_b.rotation_degrees = Vector3(0.0, 0.0, 78.0)
	fixture.add_child(segment_b)
	fixture.add_child(_box(Vector3(0.5, 0.4, 0.5), Color(0.3, 0.28, 0.26), Vector3(0.3, 0.2, 0.1)))


func _sphere(radius: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	return sphere
