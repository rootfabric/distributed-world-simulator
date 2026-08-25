extends Node3D

## Read-only observatory over the FFF6 research result. Presentation never writes
## genome, functional phenotype, water field, or soil legacy state.
const Bridge = preload("res://scripts/research/ecology/evo7_succession_bridge_v1.gd")

const ZONE_LABELS := {
	"flooded":"FLOODED", "riparian":"RIPARIAN", "mesic_loam":"MESIC LOAM",
	"dry_sand":"DRY SAND", "under_canopy":"UNDER CANOPY", "canopy_gap":"CANOPY GAP",
}
var feedback_enabled := true
var neutral_geometry := false
var show_final := true
var overlay_mode := 0
var result: Dictionary = {}
var plots := Node3D.new()
var hud := Label.new()
var status := Label.new()
var cached_hash := ""

func _ready() -> void:
	name = "EcoEvo7FormFunctionFeedbackLab"
	_build_world_shell()
	_run_and_materialize()
	if OS.get_environment("EVO7_FFF6_LAB_AUTOCAP") == "1":
		call_deferred("_autocap")

func _autocap() -> void:
	await get_tree().process_frame
	if result.is_empty():
		get_tree().quit(1)
		return
	print("ECO.EVO7 FFF6 visual observatory adapter: PASS hash=%s" % String(result["result_hash"]).substr(0,16))
	get_tree().quit(0)

func _build_world_shell() -> void:
	add_child(plots)
	plots.name = "Plots"
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun.light_energy = 1.25
	add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 22.0, 28.0)
	camera.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud.position = Vector2(18, 18)
	hud.size = Vector2(1000, 620)
	hud.add_theme_font_size_override("font_size", 16)
	layer.add_child(hud)
	status.position = Vector2(18, 660)
	status.size = Vector2(1200, 180)
	status.add_theme_font_size_override("font_size", 15)
	layer.add_child(status)

func _run_and_materialize() -> void:
	status.text = "Computing deterministic FFF6 100-cycle community..."
	result = Bridge.run_all(20260823, 100, feedback_enabled)
	if result.is_empty():
		status.text = "FFF6 computation failed. Run RUN_ECO_EVO7_FFF6_TESTS.ps1 for details."
		return
	cached_hash = String(result["result_hash"])
	_rebuild_plots()
	_refresh_hud()

func _rebuild_plots() -> void:
	for child in plots.get_children(): child.queue_free()
	var index := 0
	for zone_name in Bridge.ZONE_ORDER:
		var col := index % 3
		var row := int(index / 3)
		var origin := Vector3((float(col)-1.0)*12.0, 0.0, (float(row)-0.5)*12.0)
		_build_plot(zone_name, origin, index)
		index += 1

func _build_plot(zone_name: String, origin: Vector3, zone_index: int) -> void:
	var zone: Dictionary = result["zones"][zone_name]
	var features: Dictionary = zone["mean_features"]
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(9.0, 0.25, 8.0)
	ground.mesh = ground_mesh
	ground.position = origin + Vector3(0.0,-0.15,0.0)
	ground.material_override = _material(Color(0.20,0.22,0.18))
	plots.add_child(ground)
	for i in 8:
		var px := float(i % 4) * 1.8 - 2.7
		var pz := float(int(i / 4)) * 2.1 - 1.05
		_build_plant(origin + Vector3(px,0.0,pz), features, zone_index)
	var label := Label3D.new()
	label.text = ZONE_LABELS[zone_name]
	label.position = origin + Vector3(0.0,5.8,-3.6)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plots.add_child(label)

func _build_plant(position: Vector3, features: Dictionary, zone_index: int) -> void:
	var height := 1.2 if not show_final else clampf(float(features["realized_height_m"]),0.5,7.0)
	var crown_radius := 0.45 if not show_final else clampf(float(features["realized_crown_radius_m"]),0.25,1.8)
	var root_depth := 0.8 if not show_final else clampf(float(features["realized_root_depth_m"]),0.3,3.0)
	var trunk := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.height = height
	cylinder.top_radius = clampf(0.06 + float(features.get("structural_investment",0.4))*0.10,0.06,0.18)
	cylinder.bottom_radius = cylinder.top_radius * 1.3
	trunk.mesh = cylinder
	trunk.position = position + Vector3(0.0,height*0.5,0.0)
	trunk.material_override = _material(Color(0.34,0.22,0.12) if not neutral_geometry else Color(0.55,0.55,0.55))
	plots.add_child(trunk)
	var crown := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = crown_radius
	sphere.height = crown_radius * 2.0
	crown.mesh = sphere
	crown.scale = Vector3(1.0,clampf(0.65 + float(features["realized_crown_density"])*0.55,0.65,1.2),1.0)
	crown.position = position + Vector3(0.0,height,0.0)
	var palette := [Color(0.22,0.52,0.30),Color(0.16,0.58,0.34),Color(0.31,0.60,0.25),Color(0.48,0.55,0.20),Color(0.20,0.43,0.35),Color(0.35,0.63,0.28)]
	crown.material_override = _material(Color(0.55,0.55,0.55) if neutral_geometry else palette[zone_index])
	plots.add_child(crown)
	var root := MeshInstance3D.new()
	var root_mesh := CylinderMesh.new()
	root_mesh.height = root_depth
	root_mesh.top_radius = 0.035
	root_mesh.bottom_radius = 0.06
	root.mesh = root_mesh
	root.position = position + Vector3(0.0,-root_depth*0.5,0.0)
	root.material_override = _material(Color(0.28,0.17,0.10) if not neutral_geometry else Color(0.55,0.55,0.55))
	plots.add_child(root)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material

func _unhandled_key_input(event: InputEventKey) -> void:
	if not event.pressed or event.echo: return
	match event.keycode:
		KEY_SPACE:
			show_final = not show_final
			_rebuild_plots(); _refresh_hud()
		KEY_F:
			feedback_enabled = not feedback_enabled
			_run_and_materialize()
		KEY_C:
			neutral_geometry = not neutral_geometry
			_rebuild_plots(); _refresh_hud()
		KEY_1: overlay_mode = 1; _refresh_hud()
		KEY_2: overlay_mode = 2; _refresh_hud()
		KEY_3: overlay_mode = 3; _refresh_hud()
		KEY_4: overlay_mode = 4; _refresh_hud()
		KEY_5: overlay_mode = 5; _refresh_hud()
		KEY_R:
			var previous := cached_hash
			_run_and_materialize()
			status.text = "Replay hash identical: %s | %s" % [str(previous == cached_hash), cached_hash.substr(0,16)]

func _refresh_hud() -> void:
	if result.is_empty(): return
	var lines := PackedStringArray([
		"ECO.EVO7 FFF6 — 100-cycle Form / Function / Feedback",
		"SPACE initial/final | F feedback ON/OFF | C neutral geometry | 1 light | 2 water | 3 soil | 4 fitness | 5 geometry | R replay",
		"feedback=%s phase=%s neutral=%s clusters=%d distinct_pop=%d gap_recovery=%.3f hash=%s" % [str(feedback_enabled),"FINAL" if show_final else "INITIAL",str(neutral_geometry),int(result["geometry_cluster_count"]),int(result["distinct_final_population_count"]),float(result["gap_light_recovery"]),String(result["result_hash"]).substr(0,16)],
		"",
	])
	for zone_name in Bridge.ZONE_ORDER:
		var z: Dictionary = result["zones"][zone_name]
		var f: Dictionary = z["mean_features"]
		var tail := ""
		match overlay_mode:
			1: tail = " light=%.3f" % float(z["mean_understory_light"])
			2: tail = " water_sat=%.3f root=%.2f" % [float(z["mean_water_satisfaction"]),float(f["realized_root_depth_m"])]
			3: tail = " organic=%d" % int(z["organic_matter_ppm"])
			4: tail = " fitness=%.3f" % float(z["mean_fitness"])
			5: tail = " h=%.2f crown=%.2f LAI=%.2f root=%.2f" % [float(f["realized_height_m"]),float(f["realized_crown_radius_m"]),float(f["leaf_area_index_proxy"]),float(f["realized_root_depth_m"])]
		lines.append("%-14s h=%5.2f crown=%4.2f LAI=%4.2f root=%4.2f rsr=%4.2f%s" % [ZONE_LABELS[zone_name],float(f["realized_height_m"]),float(f["realized_crown_radius_m"]),float(f["leaf_area_index_proxy"]),float(f["realized_root_depth_m"]),float(z["mean_root_shoot_ratio"]),tail])
	hud.text = "\n".join(lines)
	status.text = "Geometry-only proof is active when C=true: all plants use the same neutral material; ecology hash is unchanged by presentation controls."
