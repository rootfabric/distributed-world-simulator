extends Node3D

## ECO.EVO5 probe 2: single established tree, close-up, unshaded branch test.

const Presentation = preload("res://scripts/research/ecology/evo4_bridge_presentation_v1.gd")

func _ready() -> void:
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://validation/ecology/evo4_b6_region_manifest.v1.json"))
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.position = Vector3(3.0, 2.2, 4.5)
	cam.look_at(Vector3(0.0, 1.5, 0.0), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.65, 0.75)
	we.environment = env
	add_child(we)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	g.mesh = pm
	var gm2 := StandardMaterial3D.new()
	gm2.albedo_color = Color(0.35, 0.45, 0.25)
	g.material_override = gm2
	add_child(g)
	var sp: Dictionary = ((man["species_traits"] as Dictionary).values())[0]
	var t: Dictionary = (sp["development_traits"] as Dictionary).duplicate(true)
	t["branching_depth"] = int(t["branching_depth"])
	var built := Presentation.build_rich_subject(t, 123456, float(sp["water_preference"]),
		float(sp["shade_tolerance"]), float(sp["dormancy_fraction"]), 1.6)
	for pair in [["branch_mesh", null, null], ["leaf_mesh", "leaf_colors", "leaf_transforms"], ["flower_mesh", "flower_color", "flower_transforms"]]:
		if not built.has(pair[0]) or built[pair[0]] == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = built[pair[0]]
		var xforms: Array = built[pair[2]] if pair[2] != null else [Transform3D.IDENTITY]
		mm.instance_count = xforms.size()
		for xi in range(mm.instance_count):
			if pair[2] != null:
				mm.set_instance_transform(xi, xforms[xi])
			var col := Color(1, 1, 1)
			if pair[1] == "leaf_colors":
				var lc: Array = built["leaf_colors"]
				col = lc[xi % lc.size()]
			elif pair[1] == "flower_color":
				col = built["flower_color"]
			mm.set_instance_color(xi, col)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		add_child(mi)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/evo5_probe_tree.png"))
	print("PROBE2 PASS")
	get_tree().quit(0)
