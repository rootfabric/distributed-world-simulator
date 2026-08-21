extends Node3D

const Timeline = preload("res://scripts/research/ecology/eco_obs1_spatial_demo_timeline_v1.gd")
const Snapshot = preload("res://scripts/research/ecology/eco_obs1_spatial_snapshot_v1.gd")

const PLAY_INTERVAL_SECONDS := 0.75
const PATCH_SPACING := 7.0

var timeline: Dictionary = {}
var frame_index := 0
var playing := false
var accumulator := 0.0

@onready var patches_root: Node3D = $Patches
@onready var flows_root: Node3D = $Flows
@onready var title_label: Label = $UI/Panel/Margin/VBox/Title
@onready var status_label: Label = $UI/Panel/Margin/VBox/Status
@onready var hash_label: Label = $UI/Panel/Margin/VBox/Hash
@onready var play_button: Button = $UI/Panel/Margin/VBox/Buttons/Play
@onready var pause_button: Button = $UI/Panel/Margin/VBox/Buttons/Pause
@onready var step_button: Button = $UI/Panel/Margin/VBox/Buttons/Step

func _ready() -> void:
	timeline = Timeline.build()
	if not bool(Timeline.validate(timeline).get("success", false)):
		push_error("ECO.OBS1.2 spatial timeline validation failed")
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
	return String(current_snapshot().get("source_result_hash", ""))

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
	title_label.text = "ECO.OBS1.2 — Spatial Ecology Observer"
	status_label.text = "\n".join(PackedStringArray([
		"Year %.0f / frame %d of %d    dispersal fraction %.2f" % [float(snapshot["year"]), frame_index + 1, int(timeline["frame_count"]), float(snapshot["dispersal_fraction"])],
		"patches %d    directed edges %d" % [Array(snapshot["patches"]).size(), Array(snapshot["edges"]).size()],
		"source %.3f kg    internal transfer %.3f kg    boundary export %.3f kg" % [float(snapshot["total_source_biomass_kg"]), float(snapshot["total_internal_transfer_biomass_kg"]), float(snapshot["total_boundary_export_biomass_kg"])],
		"final in patches %.3f kg    conservation error %.9f kg" % [float(snapshot["total_final_biomass_kg"]), float(snapshot["conservation_error_kg"])],
		_patch_summary(snapshot),
		_edge_summary(snapshot),
		"Read-only P3.3 snapshot. UI owns only frame index / meshes; no topology, transfer, RNG or canonical-state writes.",
	]))
	hash_label.text = "source %s\nsnapshot %s" % [String(snapshot["source_result_hash"]), String(snapshot["snapshot_hash"])]
	_rebuild_world(snapshot)

func _patch_summary(snapshot: Dictionary) -> String:
	var parts := PackedStringArray()
	for patch_variant in Array(snapshot.get("patches", [])):
		var patch: Dictionary = patch_variant
		parts.append("%s %.2f→%.2f (+%.2f in)" % [String(patch["id"]), float(patch["source_total_biomass_kg"]), float(patch["final_total_biomass_kg"]), float(patch["incoming_total_biomass_kg"])])
	return "patch biomass: " + "   ".join(parts)

func _edge_summary(snapshot: Dictionary) -> String:
	var parts := PackedStringArray()
	for edge_variant in Array(snapshot.get("edges", [])):
		var edge: Dictionary = edge_variant
		parts.append("%s→%s %.2f kg" % [String(edge["from"]), String(edge["to"]), float(edge["transfer_biomass_kg"])])
	return "flows: " + "   ".join(parts)

func _rebuild_world(snapshot: Dictionary) -> void:
	_clear_children(patches_root)
	_clear_children(flows_root)
	var patch_order: PackedStringArray = snapshot["patch_order"]
	var positions := {}
	for index in range(patch_order.size()):
		positions[String(patch_order[index])] = _patch_position(index, patch_order.size())
	var global_plant_order := _global_plant_order(snapshot)
	for patch_index in range(Array(snapshot["patches"]).size()):
		var patch: Dictionary = Array(snapshot["patches"])[patch_index]
		patches_root.add_child(_make_patch_proxy(patch, patch_index, positions[String(patch["id"])], global_plant_order))
	for edge_variant in Array(snapshot["edges"]):
		var edge: Dictionary = edge_variant
		flows_root.add_child(_make_flow_proxy(edge, positions[String(edge["from"])], positions[String(edge["to"])]))

func _clear_children(root: Node) -> void:
	for child in root.get_children():
		child.queue_free()

func _patch_position(index: int, count: int) -> Vector3:
	var columns := maxi(1, int(ceil(sqrt(float(maxi(count, 1))))))
	var rows := maxi(1, int(ceil(float(count) / float(columns))))
	var row := index / columns
	var column := index % columns
	return Vector3((float(column) - 0.5 * float(columns - 1)) * PATCH_SPACING, 0.0, (float(row) - 0.5 * float(rows - 1)) * PATCH_SPACING)

func _global_plant_order(snapshot: Dictionary) -> PackedStringArray:
	var seen := {}
	var order := PackedStringArray()
	for patch_variant in Array(snapshot.get("patches", [])):
		var patch: Dictionary = patch_variant
		for plant_id in PackedStringArray(patch.get("plant_order", PackedStringArray())):
			if not seen.has(plant_id):
				seen[plant_id] = true
				order.append(plant_id)
	order.sort()
	return order

func _make_patch_proxy(patch: Dictionary, patch_index: int, position: Vector3, global_plant_order: PackedStringArray) -> Node3D:
	var root := Node3D.new()
	root.name = "Patch_%s" % String(patch["id"])
	root.position = position

	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(5.2, 0.32, 5.2)
	var ground := MeshInstance3D.new()
	ground.mesh = ground_mesh
	ground.position.y = -0.18
	ground.material_override = _material(_patch_color(patch_index))
	root.add_child(ground)

	var label := Label3D.new()
	label.text = "%s\n%.2f kg" % [String(patch["id"]), float(patch["final_total_biomass_kg"])]
	label.position = Vector3(-2.25, 0.35, -2.15)
	label.font_size = 42
	label.modulate = Color(0.92, 0.96, 0.90)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	var plants: Array = patch["plants"]
	for local_index in range(plants.size()):
		var plant: Dictionary = plants[local_index]
		if float(plant["final_biomass_kg"]) <= 0.000000001:
			continue
		var global_index := global_plant_order.find(String(plant["id"]))
		root.add_child(_make_plant_proxy(plant, local_index, plants.size(), maxi(global_index, 0)))
	return root

func _make_plant_proxy(plant: Dictionary, local_index: int, count: int, color_index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Plant_%s" % String(plant["id"])
	var columns := 2 if count <= 4 else 3
	var row := local_index / columns
	var column := local_index % columns
	root.position = Vector3((float(column) - 0.5 * float(columns - 1)) * 1.65, 0.0, (float(row) - 0.35) * 1.55)
	var biomass := maxf(float(plant["final_biomass_kg"]), 0.02)
	var incoming := maxf(float(plant["incoming_biomass_kg"]), 0.0)
	var height := clampf(0.45 + sqrt(biomass) * 0.55, 0.45, 2.8)
	var crown_radius := clampf(0.28 + sqrt(biomass) * 0.15, 0.28, 0.85)

	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.07
	stem_mesh.bottom_radius = 0.11
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
	var incoming_fraction := clampf(incoming / maxf(biomass, 0.000001), 0.0, 1.0)
	crown.material_override = _material(_plant_color(color_index).lerp(Color(0.85, 0.70, 0.22), incoming_fraction * 0.55))
	root.add_child(crown)
	return root

func _make_flow_proxy(edge: Dictionary, from_position: Vector3, to_position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Flow_%s_%s" % [String(edge["from"]), String(edge["to"])]
	var start := from_position + Vector3(0.0, 0.30, 0.0)
	var finish := to_position + Vector3(0.0, 0.30, 0.0)
	var delta := finish - start
	var length := delta.length()
	if length <= 0.000001:
		return root
	var transfer := maxf(float(edge["transfer_biomass_kg"]), 0.0)
	var radius := clampf(0.035 + sqrt(transfer) * 0.07, 0.035, 0.18)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 6
	mesh.rings = 1
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.position = (start + finish) * 0.5
	line.quaternion = Quaternion(Vector3.UP, delta.normalized())
	var intensity := clampf(transfer / 2.0, 0.0, 1.0)
	line.material_override = _material(Color(0.28, 0.48, 0.76).lerp(Color(0.88, 0.72, 0.24), intensity))
	root.add_child(line)

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = radius * 1.8
	marker_mesh.height = radius * 3.0
	marker_mesh.radial_segments = 6
	marker_mesh.rings = 3
	var marker := MeshInstance3D.new()
	marker.mesh = marker_mesh
	marker.position = finish
	marker.material_override = _material(Color(0.86, 0.72, 0.25))
	root.add_child(marker)
	return root

func _patch_color(index: int) -> Color:
	var palette := [
		Color(0.18, 0.29, 0.13),
		Color(0.22, 0.31, 0.17),
		Color(0.16, 0.27, 0.20),
		Color(0.27, 0.29, 0.15),
	]
	return palette[index % palette.size()]

func _plant_color(index: int) -> Color:
	var palette := [
		Color(0.25, 0.62, 0.33),
		Color(0.48, 0.72, 0.26),
		Color(0.23, 0.50, 0.24),
		Color(0.32, 0.58, 0.44),
	]
	return palette[index % palette.size()]

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.90
	return material
