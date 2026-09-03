class_name WorldFillDiggingPlayground
extends Node3D

## WF0.7 Digging Playground Composition (WORLD FILL train).
##
## One integrated presentation stand: the visual convergence target of the
## WORLD FILL train. This is a presentation integration lab, NOT a digging
## implementation: the "dig pit" is a presentation scar, the seam marker is
## a cosmetic line, and every system consumed here is an existing WF0.x
## presentation component.
##
## Composition: ambience (WF0.4), starter props scatter (WF0.2),
## dig-pit scars (WF0.3), one POI (WF0.6), signs, seam marker and a
## spectator camera path over six named viewpoints.

const SCHEMA := "world_fill.playground_report.v1"

const DressingScript = preload("res://scripts/world_fill/dressing/world_fill_dressing.gd")
const ScatterScript = preload("res://scripts/world_fill/scatter/world_fill_prop_scatter.gd")
const ScarLayerScript = preload("res://scripts/world_fill/decals/world_fill_scar_layer.gd")
const AtmosphereScript = preload("res://scripts/world_fill/ambience/world_fill_atmosphere.gd")
const PoiKitScript = preload("res://scripts/world_fill/landmarks/world_fill_poi_kit.gd")

const SEAM_SEGMENT_COUNT := 10
const SEAM_LENGTH := 30.0
const PIT_RADIUS := 3.0
const CAMERA_WAYPOINTS := {
	"spawn": Vector3(0.0, 2.0, 18.0),
	"outpost": Vector3(-14.0, 3.0, -10.0),
	"dig_site": Vector3(6.0, 2.5, 6.0),
	"seam": Vector3(0.0, 2.0, -16.0),
	"handoff": Vector3(18.0, 4.0, -6.0),
	"horizon": Vector3(0.0, 12.0, 24.0),
}
const CAMERA_TARGET := Vector3(0.0, 1.0, -2.0)
const WAYPOINT_SECONDS := 4.0

var _atmosphere: Node3D
var _scatter: Node3D
var _scars: Node3D
var _poi_kit: Node3D
var _camera: Camera3D
var _waypoint_names: Array[String] = []
var _path_time := 0.0
var _report := {}


func _ready() -> void:
	_report = build_playground()
	print("WORLD_FILL_PLAYGROUND_AMBIENCE=%s" % String(_report.get("ambience_preset", "")))
	print("WORLD_FILL_PLAYGROUND_SCATTER=%d" % int(_report.get("scatter_instances", 0)))
	print("WORLD_FILL_PLAYGROUND_SCARS=%d" % int(_report.get("scar_events", 0)))
	print("WORLD_FILL_PLAYGROUND_POIS=%d" % int(_report.get("pois", 0)))
	print("WORLD_FILL_DIGGING_PLAYGROUND_READY")


func build_playground() -> Dictionary:
	for child in get_children().duplicate():
		if is_instance_valid(child):
			child.free()
	_waypoint_names.clear()

	_atmosphere = AtmosphereScript.new()
	_atmosphere.name = "PlaygroundAtmosphere"
	add_child(_atmosphere)
	var ambience: Dictionary = _atmosphere.apply_clock({"day_fraction": 0.42})

	_build_ground()
	_build_seam_marker()
	_build_dig_pit()

	_scatter = ScatterScript.new()
	_scatter.name = "PlaygroundScatter"
	add_child(_scatter)
	var decision: Dictionary = DressingScript.derive({
		"surface_type": "regolith",
		"position": Vector3.ZERO,
		"seed": 0x57464C30,
	})
	var scatter_report: Dictionary = _scatter.build_from_decision(
		decision, Vector2(70.0, 70.0), 0x57464C30
	)

	_scars = ScarLayerScript.new()
	_scars.name = "PlaygroundScars"
	add_child(_scars)
	var observed := [
		{"type": "DIG_SUCCESS", "position": Vector3(6.0, 0.0, 6.0)},
		{"type": "DIG_IMPACT", "position": Vector3(7.2, 0.0, 7.0)},
		{"type": "CONTACT_TRACE", "position": Vector3(2.0, 0.0, 9.0)},
	]
	for index in observed.size():
		var event: Dictionary = observed[index]
		event["normal"] = Vector3.UP
		_scars.record_event(event, 500 + index)

	_poi_kit = PoiKitScript.new()
	_poi_kit.name = "PlaygroundPois"
	add_child(_poi_kit)
	_poi_kit.spawn_poi("mining_camp", Vector3(-4.0, 0.0, 3.0))
	_poi_kit.spawn_poi("landing_site", Vector3(-10.0, 0.0, 6.0))

	_build_signs()
	_build_camera_path()

	_report = {
		"schema": SCHEMA,
		"ambience_preset": String(ambience.get("preset", "")),
		"scatter_instances": int(scatter_report.get("total_instances", 0)),
		"scar_events": observed.size(),
		"pois": int(_poi_kit.poi_report().get("active", 0)),
		"seam_segments": SEAM_SEGMENT_COUNT,
		"signs": 2,
		"waypoints": _waypoint_names.size(),
	}
	return _report


func playground_report() -> Dictionary:
	return _report.duplicate(true)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "PlaygroundGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(70.0, 70.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.17, 0.18)
	material.roughness = 0.96
	ground.material_override = material
	add_child(ground)


func _build_seam_marker() -> void:
	var seam := Node3D.new()
	seam.name = "SeamMarker"
	add_child(seam)
	var spacing := SEAM_LENGTH / float(SEAM_SEGMENT_COUNT - 1)
	for index in SEAM_SEGMENT_COUNT:
		var segment := MeshInstance3D.new()
		segment.name = "SeamSegment_%d" % index
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.06, 0.14)
		segment.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.1, 0.7, 0.8)
		material.emission_enabled = true
		material.emission = Color(0.05, 0.5, 0.6)
		material.emission_energy_multiplier = 1.4
		segment.material_override = material
		segment.position = Vector3(-SEAM_LENGTH * 0.5 + float(index) * spacing, 0.04, -14.0)
		seam.add_child(segment)


func _build_dig_pit() -> void:
	var pit := Node3D.new()
	pit.name = "DigPit"
	add_child(pit)
	pit.position = Vector3(6.0, 0.0, 6.0)
	var floor_disc := MeshInstance3D.new()
	floor_disc.name = "PitFloor"
	var disc := CylinderMesh.new()
	disc.top_radius = PIT_RADIUS
	disc.bottom_radius = PIT_RADIUS * 0.8
	disc.height = 0.5
	floor_disc.mesh = disc
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.07, 0.07, 0.08)
	floor_material.roughness = 1.0
	floor_disc.material_override = floor_material
	floor_disc.position = Vector3(0.0, -0.22, 0.0)
	pit.add_child(floor_disc)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var rim := MeshInstance3D.new()
		rim.name = "PitRim_%d" % index
		var rock := BoxMesh.new()
		rock.size = Vector3(0.5, 0.35, 0.45)
		rim.mesh = rock
		var rock_material := StandardMaterial3D.new()
		rock_material.albedo_color = Color(0.13, 0.14, 0.15)
		rock_material.roughness = 1.0
		rim.material_override = rock_material
		rim.position = Vector3(cos(angle) * (PIT_RADIUS + 0.4), 0.12, sin(angle) * (PIT_RADIUS + 0.4))
		rim.rotation_degrees.y = rad_to_deg(angle)
		pit.add_child(rim)


func _build_signs() -> void:
	var signs := Node3D.new()
	signs.name = "Signs"
	add_child(signs)
	_build_sign(signs, "DIG SITE", Vector3(3.0, 0.0, 10.0), Color(0.9, 0.55, 0.1))
	_build_sign(signs, "SEAM A", Vector3(-2.0, 0.0, -12.0), Color(0.1, 0.7, 0.8))


func _build_sign(parent: Node3D, text: String, position: Vector3, color: Color) -> void:
	var sign := Node3D.new()
	sign.name = "Sign_%s" % text.replace(" ", "_")
	sign.position = position
	parent.add_child(sign)
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.04
	pole_mesh.bottom_radius = 0.06
	pole_mesh.height = 1.6
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 0.8, 0.0)
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = _static_color()
	pole.material_override = pole_material
	sign.add_child(pole)
	var plate := Label3D.new()
	plate.text = text
	plate.font_size = 48
	plate.pixel_size = 0.01
	plate.modulate = color
	plate.outline_size = 10
	plate.position = Vector3(0.0, 1.7, 0.0)
	sign.add_child(plate)


func _build_camera_path() -> void:
	for waypoint_name in CAMERA_WAYPOINTS:
		_waypoint_names.append(waypoint_name)
	_waypoint_names.sort()
	_camera = Camera3D.new()
	_camera.name = "SpectatorCamera"
	_camera.position = CAMERA_WAYPOINTS[_waypoint_names[0]]
	add_child(_camera)
	_apply_waypoint(0.0)


func _process(delta: float) -> void:
	if _camera == null or _waypoint_names.is_empty():
		return
	_path_time = fmod(_path_time + delta, WAYPOINT_SECONDS * float(_waypoint_names.size()))
	_apply_waypoint(_path_time)


func _apply_waypoint(time_value: float) -> void:
	var segment := int(time_value / WAYPOINT_SECONDS) % _waypoint_names.size()
	var next_segment := (segment + 1) % _waypoint_names.size()
	var blend := fmod(time_value, WAYPOINT_SECONDS) / WAYPOINT_SECONDS
	var from: Vector3 = CAMERA_WAYPOINTS[_waypoint_names[segment]]
	var to: Vector3 = CAMERA_WAYPOINTS[_waypoint_names[next_segment]]
	_camera.position = from.lerp(to, blend)
	if _camera.is_inside_tree():
		_camera.look_at(CAMERA_TARGET)


func _static_color() -> Color:
	return Color(0.4, 0.42, 0.45)
