extends Node3D

const DressingScript = preload("res://scripts/world_fill/dressing/world_fill_dressing.gd")
const ScatterScript = preload("res://scripts/world_fill/scatter/world_fill_prop_scatter.gd")
const ScarLayerScript = preload("res://scripts/world_fill/decals/world_fill_scar_layer.gd")
const AtmosphereScript = preload("res://scripts/world_fill/ambience/world_fill_atmosphere.gd")
const FeedbackScript = preload("res://scripts/world_fill/feedback/world_fill_event_feedback.gd")
const PoiKitScript = preload("res://scripts/world_fill/landmarks/world_fill_poi_kit.gd")
const MemoryScript = preload("res://scripts/world_fill/memory/world_fill_local_memory.gd")
const SignKitScript = preload("res://scripts/world_fill/labels/world_fill_sign_kit.gd")
const ShowcaseScript = preload("res://scripts/world_fill/showcase/world_fill_showcase_kit.gd")

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_rocks()
	_build_scatter()
	_build_scar_history()
	_build_feedback()
	_build_landmarks()
	_build_local_memory()
	_build_signs()
	_build_showcase_record()
	_build_outpost_marker()
	_build_camera()
	print("WORLD_FILL_DEMO_READY")

func _build_scatter() -> void:
	var decision := DressingScript.derive({
		"surface_type": "regolith",
		"position": Vector3.ZERO,
		"seed": 0x57464C30,
	})
	var scatter := ScatterScript.new()
	scatter.name = "WorldFillPropScatter"
	add_child(scatter)
	var report := scatter.build_from_decision(decision, Vector2(76.0, 76.0), 0x57464C30)
	print("WORLD_FILL_SCATTER_INSTANCES=%d" % int(report.get("total_instances", 0)))

func _build_scar_history() -> void:
	var scars := ScarLayerScript.new()
	scars.name = "WorldFillScarLayer"
	add_child(scars)
	var observed_events := [
		{"type": "DIG_SUCCESS", "position": Vector3(-6.0, 0.0, -4.0)},
		{"type": "DIG_IMPACT", "position": Vector3(-4.5, 0.0, -2.5)},
		{"type": "CONTACT_TRACE", "position": Vector3(6.0, 0.0, 6.0)},
	]
	for index in observed_events.size():
		var event: Dictionary = observed_events[index]
		event["normal"] = Vector3.UP
		scars.record_event(event, 1000 + index)
	print("WORLD_FILL_SCARS_ACTIVE=%d" % int(scars.scar_report().get("active", 0)))

func _build_feedback() -> void:
	var feedback := FeedbackScript.new()
	var ui_events := [0]
	feedback.configure("ui", func(_event: Dictionary) -> void: ui_events[0] += 1)
	feedback.dispatch({"type": "PICKUP", "position": Vector3.ZERO})
	feedback.dispatch({"type": "SOMETHING_UNAVAILABLE", "position": Vector3.ZERO})
	print("WORLD_FILL_FEEDBACK_UI=%d" % int(ui_events[0]))

func _build_landmarks() -> void:
	var poi_kit := PoiKitScript.new()
	poi_kit.name = "WorldFillPoiKit"
	add_child(poi_kit)
	poi_kit.spawn_poi("landing_site", Vector3(-10.0, 0.0, 6.0))
	poi_kit.spawn_poi("radio_beacon", Vector3(12.0, 0.0, -8.0))
	print("WORLD_FILL_POIS=%d" % int(poi_kit.poi_report().get("active", 0)))

func _build_local_memory() -> void:
	var memory := MemoryScript.new()
	memory.configure_storage("demo_session")
	memory.load_memory()
	memory.record_observed({"type": "VISIT", "position": Vector3.ZERO}, 1)
	memory.save()
	print("WORLD_FILL_LOCAL_MEMORY=%d" % int(memory.memory_report().get("active", 0)))

func _build_signs() -> void:
	var kit := SignKitScript.new()
	kit.name = "WorldFillSignKit"
	add_child(kit)
	kit.create_sign("MARE FRIGORIS-7 OUTPOST", Vector3(0.0, 0.0, -12.0), "location_name")
	kit.create_sign("CRATE A-113", Vector3(4.0, 0.0, 2.0), "container_label")
	print("WORLD_FILL_SIGNS=%d" % int(kit.sign_report().get("active", 0)))

func _build_showcase_record() -> void:
	var kit := ShowcaseScript.new()
	var record := kit.capture_observation({
		"simulation_tick": 0,
		"world_fill_preset": "clear",
		"scene_id": "world_fill_demo",
		"region_id": "lab/world_fill_demo",
	})
	var saved := kit.save_observation("demo_last_run", record)
	print("WORLD_FILL_SHOWCASE_COMPLETE=%s" % str(bool(record.get("complete", false))))
	print("WORLD_FILL_SHOWCASE_SAVED=%s" % str(saved))

func _build_environment() -> void:
	var atmosphere := AtmosphereScript.new()
	atmosphere.name = "WorldFillAtmosphere"
	add_child(atmosphere)
	var report := atmosphere.apply_clock({"day_fraction": 0.42, "tick": 0})
	print("WORLD_FILL_AMBIENCE=%s" % String(report.get("preset", "")))

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(80.0, 80.0)
	ground.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.17, 0.18)
	material.roughness = 0.96
	ground.material_override = material
	add_child(ground)

func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x57464C30
	for index in range(36):
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.25
		mesh.height = 0.5
		rock.mesh = mesh
		var scale_value := rng.randf_range(0.45, 2.1)
		rock.scale = Vector3(scale_value, rng.randf_range(0.35, 0.8) * scale_value, scale_value)
		rock.position = Vector3(rng.randf_range(-24.0, 24.0), 0.12, rng.randf_range(-18.0, 16.0))
		rock.rotation_degrees.y = rng.randf_range(0.0, 360.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.11, 0.12, 0.13)
		material.roughness = 1.0
		rock.material_override = material
		add_child(rock)

func _build_outpost_marker() -> void:
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.12
	pole_mesh.bottom_radius = 0.18
	pole_mesh.height = 5.0
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 2.5, -8.0)
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.38, 0.4, 0.43)
	pole_material.metallic = 0.65
	pole.material_override = pole_material
	add_child(pole)

	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.38
	beacon_mesh.height = 0.76
	beacon.mesh = beacon_mesh
	beacon.position = Vector3(0.0, 5.2, -8.0)
	var beacon_material := StandardMaterial3D.new()
	beacon_material.albedo_color = Color(0.9, 0.28, 0.08)
	beacon_material.emission_enabled = true
	beacon_material.emission = Color(0.9, 0.08, 0.02)
	beacon_material.emission_energy_multiplier = 2.5
	beacon.material_override = beacon_material
	add_child(beacon)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(17.0, 10.0, 22.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.2, -3.0))
	camera.current = true
	add_child(camera)
