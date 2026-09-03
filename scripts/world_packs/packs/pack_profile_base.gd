extends RefCounted

## WORLD PACKS — base presentation profile (WP0.3+).
##
## A profile turns a pack spec (palette, environment, scatter, prop recipes)
## plus the pack manifest (identity, catalogs) into an asset-free Node3D
## presentation. It never touches canonical truth: terrain generation, ECO,
## matter, items, authority, persistence, networking or gameplay.
##
## Pack profiles override `spec()` only; all composition is shared here so the
## six R1 packs stay structurally comparable (WP0.10 gallery requirement).

const PoiLibrary = preload("res://scripts/world_packs/poi/poi_library.gd")

var _manifest_cache: Dictionary = {}


## Override in every pack profile.
func spec() -> Dictionary:
	return {}


func pack_id() -> String:
	return String(spec()["pack_id"])


func manifest_path() -> String:
	return String(spec()["manifest_path"])


func manifest() -> Dictionary:
	if _manifest_cache.is_empty():
		var file: FileAccess = FileAccess.open(manifest_path(), FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_manifest_cache = parsed
	return _manifest_cache


## Applies the pack environment (background, ambient, fog, sun) to `root`.
func apply_environment(root: Node3D) -> void:
	var s: Dictionary = spec()
	var sky: Dictionary = s["sky"]
	var environment := Environment.new()
	if String(sky["mode"]) == "procedural":
		var sky_resource := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = sky["top"]
		sky_material.sky_horizon_color = sky["horizon"]
		sky_material.ground_bottom_color = sky["ground_bottom"]
		sky_material.ground_horizon_color = sky["ground_horizon"]
		sky_resource.sky_material = sky_material
		environment.background_mode = Environment.BG_SKY
		environment.sky = sky_resource
	else:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = sky["top"]
	var ambient: Dictionary = s["ambient"]
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient["color"]
	environment.ambient_light_energy = float(ambient["energy"])
	var fog: Dictionary = s.get("fog", {})
	if bool(fog.get("enabled", false)):
		environment.fog_enabled = true
		environment.fog_light_color = fog["color"]
		environment.fog_density = float(fog["density"])
		environment.fog_sky_affect = float(fog.get("sky_affect", 1.0))

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WP_Environment"
	world_environment.environment = environment
	root.add_child(world_environment)

	if String(sky["mode"]) == "star_dome":
		var dome := MeshInstance3D.new()
		dome.name = "WP_StarDome"
		var dome_mesh := SphereMesh.new()
		dome_mesh.radius = 220.0
		dome_mesh.height = 440.0
		dome.mesh = dome_mesh
		var dome_material := StandardMaterial3D.new()
		dome_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dome_material.albedo_texture = _noise_texture(int(s["seed"]) + 17, 0.045)
		dome_material.albedo_color = Color(0.02, 0.02, 0.035)
		dome_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		dome.material_override = dome_material
		root.add_child(dome)

	var sun := DirectionalLight3D.new()
	sun.name = "WP_Sun"
	var sun_spec: Dictionary = s["sun"]
	sun.rotation_degrees = sun_spec["rotation_degrees"]
	sun.light_color = sun_spec["color"]
	sun.light_energy = float(sun_spec["energy"])
	sun.shadow_enabled = bool(sun_spec.get("shadow", true))
	root.add_child(sun)


## Builds the pack pad (ground, decals, scatter, props, POIs) under `pad`.
func build_pad(pad: Node3D) -> void:
	var s: Dictionary = spec()
	_build_ground(pad, s)
	_build_decals(pad, s)
	_build_scatter(pad, s)
	_build_props(pad, s)
	_build_pois(pad, s)


func _build_ground(pad: Node3D, s: Dictionary) -> void:
	var ground_spec: Dictionary = s["ground"]
	var ground := MeshInstance3D.new()
	ground.name = "WP_Ground"
	var plane := PlaneMesh.new()
	plane.size = ground_spec["size"]
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = ground_spec["albedo_a"]
	material.albedo_texture = _noise_texture(int(s["seed"]), float(ground_spec.get("noise_frequency", 0.012)))
	material.roughness = float(ground_spec.get("roughness", 0.95))
	material.metallic = float(ground_spec.get("metallic", 0.0))
	ground.material_override = material
	pad.add_child(ground)


func _build_decals(pad: Node3D, s: Dictionary) -> void:
	var decal_spec: Dictionary = s.get("decals", {})
	var count: int = int(decal_spec.get("count", 0))
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"]) + 101
	var area: Vector2 = s["ground"]["size"]
	var material := StandardMaterial3D.new()
	material.albedo_color = decal_spec["color"]
	material.roughness = float(decal_spec.get("roughness", 1.0))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for index in range(count):
		var decal := MeshInstance3D.new()
		decal.name = "WP_Decal_%d" % index
		var plane := PlaneMesh.new()
		var size: float = rng.randf_range(float(decal_spec["size_min"]), float(decal_spec["size_max"]))
		plane.size = Vector2(size, size)
		decal.mesh = plane
		decal.material_override = material
		decal.position = Vector3(
			rng.randf_range(-area.x * 0.42, area.x * 0.42),
			0.015 + 0.001 * float(index),
			rng.randf_range(-area.y * 0.42, area.y * 0.42)
		)
		decal.rotation_degrees.y = rng.randf_range(0.0, 360.0)
		pad.add_child(decal)


func _build_scatter(pad: Node3D, s: Dictionary) -> void:
	var scatter_spec: Dictionary = s.get("scatter", {})
	var count: int = int(scatter_spec.get("count", 0))
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"]) + 202
	var area: Vector2 = scatter_spec["area"]
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = scatter_spec["color_a"]
	material.vertex_color_use_as_albedo = true
	material.roughness = float(scatter_spec.get("roughness", 0.9))
	material.metallic = float(scatter_spec.get("metallic", 0.0))
	mesh.material = material

	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = count
	var color_a: Color = scatter_spec["color_a"]
	var color_b: Color = scatter_spec["color_b"]
	for index in range(count):
		var position := Vector3(
			rng.randf_range(-area.x * 0.5, area.x * 0.5),
			0.0,
			rng.randf_range(-area.y * 0.5, area.y * 0.5)
		)
		var scale: float = rng.randf_range(float(scatter_spec["scale_min"]), float(scatter_spec["scale_max"]))
		var basis := Basis(
			Vector3.UP,
			rng.randf_range(0.0, TAU)
		).scaled(Vector3(scale, scale * rng.randf_range(0.45, 0.8), scale))
		multi_mesh.set_instance_transform(index, Transform3D(basis, position))
		multi_mesh.set_instance_color(index, color_a.lerp(color_b, rng.randf()))

	var scatter := MultiMeshInstance3D.new()
	scatter.name = "WP_Scatter"
	scatter.multimesh = multi_mesh
	pad.add_child(scatter)


func _build_props(pad: Node3D, s: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"]) + 303
	var area: Vector2 = s["ground"]["size"]
	var index: int = 0
	for recipe in s.get("props", []):
		for _repeat in range(int(recipe.get("count", 1))):
			var prop := _build_prop(String(recipe["type"]), recipe, rng)
			if prop == null:
				continue
			index += 1
			prop.name = "WP_Prop_%d" % index
			pad.add_child(prop)
			prop.position = Vector3(
				rng.randf_range(-area.x * 0.38, area.x * 0.38),
				0.0,
				rng.randf_range(-area.y * 0.38, area.y * 0.38)
			)
			prop.rotation_degrees.y = rng.randf_range(0.0, 360.0)


func _build_prop(prop_type: String, recipe: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var scale_min: float = float(recipe.get("scale_min", 1.0))
	var scale: float = rng.randf_range(scale_min, float(recipe.get("scale_max", scale_min)))
	var primary: Color = recipe.get("color", Color(0.4, 0.4, 0.4))
	var secondary: Color = recipe.get("secondary_color", primary.lightened(0.15))
	match prop_type:
		"crate":
			var size := Vector3.ONE * rng.randf_range(0.7, 1.3)
			var crate := _mesh(_box(size * Vector3(1.0, 0.72, 0.85)), _simple_material(primary, 0.4, 0.65))
			crate.position.y = size.y * 0.36
			root.add_child(crate)
		"scrap":
			for piece in range(3):
				var scrap := _mesh(_sphere(rng.randf_range(0.2, 0.5)), _simple_material(primary, 0.5, 0.8))
				scrap.scale = Vector3(1.0, 0.35, 0.8)
				scrap.position = Vector3(rng.randf_range(-0.5, 0.5), 0.08, rng.randf_range(-0.5, 0.5))
				root.add_child(scrap)
		"antenna":
			var mast := _mesh(_cylinder(0.05, 0.08, 2.6), _simple_material(primary, 0.6, 0.5))
			mast.position.y = 1.3
			root.add_child(mast)
			var tip := _mesh(_sphere(0.14), _emissive_material(secondary))
			tip.position.y = 2.65
			root.add_child(tip)
		"pipe":
			var pipe := _mesh(_cylinder(0.22, 0.22, 2.8), _simple_material(primary, 0.7, 0.45))
			pipe.rotation_degrees.z = 90.0
			pipe.position.y = 0.24
			root.add_child(pipe)
		"boulder":
			var boulder := _mesh(_sphere(rng.randf_range(0.8, 1.6)), _simple_material(primary, 0.0, 0.95))
			boulder.scale = Vector3(1.0, 0.7, 1.15)
			boulder.position.y = 0.35
			root.add_child(boulder)
		"shard":
			var shard := _mesh(_prism(rng.randf_range(0.5, 1.1), rng.randf_range(1.2, 2.8)), _simple_material(primary, float(recipe.get("metallic", 0.1)), float(recipe.get("roughness", 0.4))))
			shard.position.y = 0.4
			shard.rotation_degrees.z = rng.randf_range(-9.0, 9.0)
			root.add_child(shard)
		"grass_tuft":
			for blade in range(4):
				var blade_mesh := _mesh(_cylinder(0.0, 0.045, rng.randf_range(0.35, 0.8)), _simple_material(primary, 0.0, 0.85))
				blade_mesh.position = Vector3(rng.randf_range(-0.25, 0.25), 0.2, rng.randf_range(-0.25, 0.25))
				blade_mesh.rotation_degrees.z = rng.randf_range(-14.0, 14.0)
				root.add_child(blade_mesh)
		"reed":
			for stalk in range(3):
				var stalk_mesh := _mesh(_cylinder(0.02, 0.05, rng.randf_range(0.9, 1.7)), _simple_material(primary, 0.0, 0.8))
				stalk_mesh.position = Vector3(rng.randf_range(-0.2, 0.2), 0.5, rng.randf_range(-0.2, 0.2))
				stalk_mesh.rotation_degrees.z = rng.randf_range(-8.0, 8.0)
				root.add_child(stalk_mesh)
		"tree":
			var trunk := _mesh(_cylinder(0.12, 0.2, 1.8), _simple_material(primary, 0.0, 0.9))
			trunk.position.y = 0.9
			root.add_child(trunk)
			var canopy := _mesh(_sphere(rng.randf_range(0.7, 1.2)), _simple_material(secondary, 0.0, 0.85))
			canopy.position.y = 2.1
			root.add_child(canopy)
		"water":
			var water := _mesh(_plane(recipe.get("size", Vector2(9.0, 9.0))), _simple_material(primary, 0.1, float(recipe.get("roughness", 0.06))))
			water.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water.material_override.albedo_color.a = float(recipe.get("opacity", 0.72))
			water.position.y = float(recipe.get("y", 0.05))
			root.add_child(water)
		"crack":
			var crack := _mesh(_box(Vector3(rng.randf_range(1.2, 3.0), 0.05, 0.35)), _emissive_material(primary))
			crack.position.y = 0.03
			crack.rotation_degrees.y = rng.randf_range(0.0, 360.0)
			root.add_child(crack)
		_:
			return null
	if not is_equal_approx(scale, 1.0):
		root.scale = Vector3.ONE * scale
	return root


func _build_pois(pad: Node3D, s: Dictionary) -> void:
	var data: Dictionary = manifest()
	var catalog: Array = []
	if data.has("poi") and data["poi"].has("catalog"):
		catalog = data["poi"]["catalog"]
	var skin: Dictionary = s["skin"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"]) + 404
	var area: Vector2 = s["ground"]["size"]
	var radius: float = minf(area.x, area.y) * 0.34
	for slot in range(catalog.size()):
		var poi_id: String = String(catalog[slot])
		var poi: Node3D = PoiLibrary.build(poi_id, skin)
		var angle: float = TAU * float(slot) / float(maxi(catalog.size(), 1)) + rng.randf_range(-0.2, 0.2)
		poi.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		poi.rotation_degrees.y = rad_to_deg(-angle)
		pad.add_child(poi)


func _simple_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _emissive_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.8
	return material


func _noise_texture(seed_value: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.seamless = true
	texture.width = 256
	texture.height = 256
	return texture


func _mesh(mesh: Mesh, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 12
	return mesh


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


func _prism(width: float, height: float) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(width, height, width * 0.7)
	mesh.left_to_right = 0.2
	return mesh


func _plane(size: Vector2) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.size = size
	return mesh
