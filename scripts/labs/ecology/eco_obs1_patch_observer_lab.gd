extends Node3D

const Timeline = preload("res://scripts/research/ecology/eco_obs1_demo_timeline_v1.gd")
const Snapshot = preload("res://scripts/research/ecology/eco_obs1_snapshot_v1.gd")

const PLAY_INTERVAL_SECONDS := 0.65

var timeline: Dictionary = {}
var frame_index := 0
var playing := false
var accumulator := 0.0

@onready var plants_root: Node3D = $Plants
@onready var title_label: Label = $UI/Panel/Margin/VBox/Title
@onready var status_label: Label = $UI/Panel/Margin/VBox/Status
@onready var hash_label: Label = $UI/Panel/Margin/VBox/Hash
@onready var play_button: Button = $UI/Panel/Margin/VBox/Buttons/Play
@onready var pause_button: Button = $UI/Panel/Margin/VBox/Buttons/Pause
@onready var step_button: Button = $UI/Panel/Margin/VBox/Buttons/Step

func _ready() -> void:
	timeline = Timeline.build()
	if not bool(Timeline.validate(timeline).get("success", false)):
		push_error("ECO.OBS1 timeline validation failed")
		set_process(false)
		return
	play_button.pressed.connect(play)
	pause_button.pressed.connect(pause)
	step_button.pressed.connect(step_forward)
	_refresh()

func _process(delta: float) -> void:
	if not playing or timeline.is_empty():
		return
	accumulator += delta
	while accumulator >= PLAY_INTERVAL_SECONDS:
		accumulator -= PLAY_INTERVAL_SECONDS
		step_forward()

func play() -> void:
	playing = true

func pause() -> void:
	playing = false
	accumulator = 0.0

func step_forward() -> void:
	if timeline.is_empty():
		return
	frame_index = mini(frame_index + 1, int(timeline["frame_count"]) - 1)
	if frame_index >= int(timeline["frame_count"]) - 1:
		playing = false
	_refresh()

func step_back() -> void:
	if timeline.is_empty():
		return
	playing = false
	accumulator = 0.0
	frame_index = maxi(0, frame_index - 1)
	_refresh()

func current_snapshot() -> Dictionary:
	if timeline.is_empty():
		return {}
	return Dictionary(Array(timeline["frames"])[frame_index]).duplicate(true)

func current_source_hash() -> String:
	var snapshot := current_snapshot()
	return String(snapshot.get("source_result_hash", ""))

func current_frame_index() -> int:
	return frame_index

func is_playing() -> bool:
	return playing

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		step_forward()
	elif event.is_action_pressed("ui_left"):
		step_back()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if playing:
			pause()
		else:
			play()

func _refresh() -> void:
	var snapshot := current_snapshot()
	if snapshot.is_empty() or not bool(Snapshot.validate(snapshot).get("success", false)):
		return
	title_label.text = "ECO.OBS1 — Read-only Ecology Observer"
	status_label.text = "\n".join(PackedStringArray([
		"Year %.0f / frame %d of %d" % [float(snapshot["year"]), frame_index + 1, int(timeline["frame_count"])],
		"biomass %.3f kg  →  %.3f kg    effective K %.3f kg" % [float(snapshot["total_biomass_kg"]), float(snapshot["total_next_biomass_kg"]), float(snapshot["effective_capacity_kg"])],
		"density %.3f    feedback %+.3f    active plants %d" % [float(snapshot["density_ratio"]), float(snapshot["density_feedback"]), int(snapshot["active_plant_count"])],
		"resource support %.3f    pressure %.3f    limiting %s" % [float(snapshot["resource_support"]), float(snapshot["resource_pressure"]), String(snapshot["limiting_resource"])],
		"Light %.3f   Water %.3f   Nutrients %.3f" % [float(snapshot["resource_support_ratio"]["light"]), float(snapshot["resource_support_ratio"]["water"]), float(snapshot["resource_support_ratio"]["nutrients"])],
		"Observer controls only snapshot index. No simulation writes / RNG / canonical hash ownership.",
	]))
	hash_label.text = "source %s\nsnapshot %s" % [String(snapshot["source_result_hash"]), String(snapshot["snapshot_hash"])]
	_rebuild_plants(snapshot)

func _rebuild_plants(snapshot: Dictionary) -> void:
	for child in plants_root.get_children():
		child.queue_free()
	var plants: Array = snapshot["plants"]
	for index in range(plants.size()):
		var plant: Dictionary = plants[index]
		plants_root.add_child(_make_plant_proxy(plant, index, plants.size()))

func _make_plant_proxy(plant: Dictionary, index: int, count: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Plant_%s" % String(plant["id"])
	var columns := 2 if count <= 4 else 3
	var row := index / columns
	var column := index % columns
	root.position = Vector3((float(column) - 0.5 * float(columns - 1)) * 3.2, 0.0, (float(row) - 0.5) * 3.0)
	var biomass := maxf(float(plant["biomass_kg"]), 0.02)
	var height := clampf(0.7 + sqrt(biomass) * 0.72, 0.7, 3.8)
	var crown_radius := clampf(0.42 + sqrt(biomass) * 0.20, 0.42, 1.25)

	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.10
	stem_mesh.bottom_radius = 0.16
	stem_mesh.height = height
	stem_mesh.radial_segments = 6
	stem_mesh.rings = 1
	var stem := MeshInstance3D.new()
	stem.mesh = stem_mesh
	stem.position.y = height * 0.5
	stem.material_override = _material(Color(0.31, 0.21, 0.12))
	root.add_child(stem)

	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = crown_radius
	crown_mesh.height = crown_radius * 1.65
	crown_mesh.radial_segments = 8
	crown_mesh.rings = 4
	var crown := MeshInstance3D.new()
	crown.mesh = crown_mesh
	crown.position.y = height + crown_radius * 0.42
	crown.material_override = _material(_plant_color(index, float(plant["resource_growth_factor"])))
	root.add_child(crown)
	return root

func _plant_color(index: int, growth_factor: float) -> Color:
	var palette := [
		Color(0.24, 0.58, 0.32),
		Color(0.48, 0.70, 0.25),
		Color(0.20, 0.48, 0.22),
		Color(0.38, 0.61, 0.27),
		Color(0.28, 0.55, 0.42),
	]
	var base: Color = palette[index % palette.size()]
	return base.lerp(Color(0.72, 0.68, 0.28), clampf(1.0 - growth_factor, 0.0, 1.0) * 0.45)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material
