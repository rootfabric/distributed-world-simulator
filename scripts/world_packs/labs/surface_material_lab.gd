extends Node3D

## WP-VIS1 Generic Surface Material Lab (GENERIC_LAB_SCAFFOLD).
##
## Presentation-only, asset-free lab scene proving that surface presentation
## fixtures can live at arbitrary orientations without baking a Y-up
## assumption into mapping code. This is NOT production terrain: the lab
## never touches canonical collision, Matter state or ECO placement truth.
##
## Milestone GENERIC_LAB_SCAFFOLD builds the lab frame (reference grid,
## axis gizmo, neutral lighting, camera) plus one marker per registered
## fixture descriptor. HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES instantiates
## the real horizontal / 45-degree slope / vertical wall surfaces through
## _build_surface; later milestones enable the remaining descriptors.
##
## Headless self-check:
##   godot --headless --path . --script res://scripts/world_packs/labs/surface_material_lab_self_check.gd
## (kept out of scene wiring so the scene stays presentation-only).

const Fixtures = preload("res://scripts/world_packs/labs/surface_material_lab_fixtures.gd")

const NEUTRAL_SKY: Color = Color(0.05, 0.055, 0.065)
const NEUTRAL_AMBIENT: Color = Color(0.35, 0.37, 0.4)
const MARKER_ALPHA: float = 0.55

## Lab milestones whose real oriented surfaces are instantiated. Milestones
## not listed here still show scaffold markers. The list only ever grows
## within a workstream so an older head renders a strict subset.
const ENABLED_SURFACE_MILESTONES: Array[String] = [
	"HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES",
	"OVERHANG_AND_INVERTED_SURFACES",
	"SPHERE_OR_IRREGULAR_FIXTURE",
]


var _checker_texture: ImageTexture


func _ready() -> void:
	_checker_texture = _make_checker_texture()
	_build_environment()
	_build_reference_frame()
	var built: int = 0
	for fixture in Fixtures.FIXTURES:
		if _surface_enabled(fixture):
			_build_surface(fixture)
		else:
			_build_marker(fixture)
		built += 1
	_build_camera()
	print("SURFACE_MATERIAL_LAB_SCAFFOLD_READY")
	print("SURFACE_MATERIAL_LAB_FIXTURES=%d" % built)


func _surface_enabled(fixture: Dictionary) -> bool:
	return ENABLED_SURFACE_MILESTONES.has(String(fixture.get("built_in_milestone", "")))


## Scaffold-stage marker: a small orientation gizmo placed at the declared
## fixture position, with the world-space surface normal drawn explicitly so
## reviewers can read intended orientation without the real surface existing
## yet. Uses only the fixture-local frame declared in the registry.
func _build_marker(fixture: Dictionary) -> void:
	var fixture_id := String(fixture["id"])
	var root := Node3D.new()
	root.name = "Marker_%s" % fixture_id
	root.position = Vector3(fixture["position"])
	root.rotation_degrees = Vector3(fixture["rotation_degrees"])
	add_child(root)

	var color: Color = fixture["diagnostic_color"]
	var body := MeshInstance3D.new()
	body.name = "Body"
	if String(fixture["shape"]) == "sphere":
		body.mesh = SphereMesh.new()
		body.mesh.radius = 0.18
		body.mesh.height = 0.36
	else:
		body.mesh = BoxMesh.new()
		body.mesh.size = Vector3(0.3, 0.3, 0.3)
	body.set_meta("wp_vis1_fixture_id", fixture_id)
	root.add_child(body)
	_apply_diagnostic_material(body, color)

	# Local-frame normal ray: derived from the fixture descriptor, never from
	# a hardcoded global "up".
	var normal_arrow := _make_normal_arrow(
		Vector3(fixture["surface_normal_local"]),
		color.lightened(0.35)
	)
	normal_arrow.name = "LocalNormal"
	root.add_child(normal_arrow)

	var label := Label3D.new()
	label.name = "Label"
	label.text = "%s\n[%s]" % [String(fixture["label"]), fixture_id]
	label.font_size = 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color.lightened(0.5)
	label.position = Vector3(0.0, 0.6, 0.0)
	root.add_child(label)


## Real oriented surface builder. No fixture declares the scaffold milestone
## yet; later milestones reuse exactly this entry point so the scaffold API
## cannot silently drift from the built surfaces.
func _build_surface(fixture: Dictionary) -> void:
	var fixture_id := String(fixture["id"])
	var root := Node3D.new()
	root.name = "Fixture_%s" % fixture_id
	root.position = Vector3(fixture["position"])
	root.rotation_degrees = Vector3(fixture["rotation_degrees"])
	add_child(root)

	var body := MeshInstance3D.new()
	body.name = "Surface"
	body.set_meta("wp_vis1_fixture_id", fixture_id)
	if String(fixture["shape"]) == "sphere":
		var sphere := SphereMesh.new()
		sphere.radius = Vector3(fixture["size"]).x * 0.5
		sphere.height = Vector3(fixture["size"]).x
		body.mesh = sphere
	elif String(fixture["shape"]) == "irregular_rock":
		body.mesh = _make_irregular_rock()
		body.scale = Vector3(fixture["size"]) * 0.5
	else:
		var box := BoxMesh.new()
		box.size = Vector3(fixture["size"])
		body.mesh = box
	_apply_diagnostic_material(body, fixture["diagnostic_color"], true)
	root.add_child(body)

	# Local-frame normal indicator on the real surface: orientation must stay
	# readable directly on the fixture, derived from the descriptor only.
	var normal_arrow := _make_normal_arrow(
		Vector3(fixture["surface_normal_local"]),
		(fixture["diagnostic_color"] as Color).lightened(0.45)
	)
	normal_arrow.name = "LocalNormal"
	root.add_child(normal_arrow)

	var label := Label3D.new()
	label.name = "Label"
	label.text = "%s\n[%s]" % [String(fixture["label"]), fixture_id]
	label.font_size = 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = (fixture["diagnostic_color"] as Color).lightened(0.5)
	label.position = Vector3(0.0, 0.7, 0.0)
	root.add_child(label)


## Deterministic asset-free irregular rock: a displaced sphere whose vertices
## are pushed along their own normals by a smooth function of direction, so
## no world axis is ever a privileged surface direction. Displacement depends
## only on the vertex direction, keeping the mesh deterministic and seam-safe.
func _make_irregular_rock() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 24
	sphere.rings = 16
	sphere.radius = 1.0
	sphere.height = 2.0
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		var vertex := vertices[index]
		var direction := vertex.normalized()
		var displacement := 1.0
		displacement += 0.14 * sin(3.0 * direction.x + 1.7) * cos(2.0 * direction.y)
		displacement += 0.1 * sin(5.0 * direction.z + 0.6)
		vertices[index] = direction * displacement
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _apply_diagnostic_material(
	target: MeshInstance3D,
	color: Color,
	triplanar: bool = false
) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, MARKER_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.85
	material.metallic = 0.0
	if triplanar:
		# Local-frame triplanar mapping: Godot derives the three projection
		# planes from the node's LOCAL axes, not from a hardcoded world up, so
		# the checker pattern follows the fixture wherever it is rotated.
		material.albedo_texture = _checker_texture
		material.uv1_triplanar = true
		material.uv1_scale = Vector3(1.5, 1.5, 1.5)
		material.texture_repeat = true
	target.material_override = material


## Asset-free 8x8 two-tone checker used as the triplanar diagnostic pattern.
## Generated once at runtime; nothing is loaded from disk.
func _make_checker_texture() -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var dark := Color(0.12, 0.12, 0.12)
	var light := Color(0.9, 0.9, 0.9)
	for y in 64:
		for x in 64:
			var cell := int(x / 8 + y / 8) % 2
			image.set_pixel(x, y, light if cell == 0 else dark)
	return ImageTexture.create_from_image(image)


func _make_normal_arrow(local_normal: Vector3, color: Color) -> Node3D:
	var holder := Node3D.new()
	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.02, 0.5, 0.02)
	shaft.mesh = shaft_mesh
	shaft.position = local_normal * 0.25
	# Orient the shaft along the fixture-local normal explicitly; never
	# assume the normal is perpendicular or parallel to global up.
	var basis_up := Vector3.UP
	if absf(local_normal.dot(Vector3.UP)) > 0.99:
		basis_up = Vector3.FORWARD
	shaft.basis = Basis.looking_at(local_normal, basis_up)
	holder.add_child(shaft)
	_apply_solid_material(shaft, color)
	return holder


func _apply_solid_material(target: MeshInstance3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	target.material_override = material


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = NEUTRAL_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = NEUTRAL_AMBIENT
	environment.ambient_light_energy = 1.0
	var sky := WorldEnvironment.new()
	sky.name = "WorldEnvironment"
	sky.environment = environment
	add_child(sky)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _build_reference_frame() -> void:
	# Flat reference grid exists ONLY as a human-readable backdrop. Mapping
	# code in this lab must not use it as an orientation source.
	var grid := MeshInstance3D.new()
	grid.name = "ReferenceGrid"
	var grid_mesh := PlaneMesh.new()
	grid_mesh.size = Vector2(30.0, 30.0)
	grid.mesh = grid_mesh
	grid.position = Vector3(0.0, -0.5, 0.0)
	var grid_material := StandardMaterial3D.new()
	grid_material.albedo_color = Color(0.12, 0.12, 0.14)
	grid_material.roughness = 1.0
	grid.material_override = grid_material
	add_child(grid)
	set_meta("wp_vis1_reference_frame_note",
		"reference grid is backdrop only; fixture frames come from the registry")


func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 4.5, 10.0)
	camera.look_at_from_position(camera.position, Vector3(-1.0, 1.2, -1.0))
	camera.current = true
	add_child(camera)


## MCP/automation entry: report the world-space surface normal of a fixture
## without touching any global-up assumption.
func report_world_normal(fixture_id: String) -> Vector3:
	return Fixtures.world_surface_normal(Fixtures.descriptor(fixture_id))


## MCP/automation entry: local-frame triplanar mapping report for a fixture.
## Returns the descriptor local normal, the local triplanar blend weights for
## the surface's own world normal, and whether the surface material uses
## local-frame triplanar mapping. Orientation-independence is provable: the
## weights depend only on the local frame, not on world rotation.
func report_local_frame_mapping(fixture_id: String) -> Dictionary:
	var fixture := Fixtures.descriptor(fixture_id)
	var world_normal := Fixtures.world_surface_normal(fixture)
	var fixture_root := get_node_or_null("Fixture_%s" % fixture_id) as Node3D
	var triplanar_enabled := false
	if fixture_root != null:
		var body := fixture_root.get_node_or_null("Surface") as MeshInstance3D
		if body != null and body.material_override is StandardMaterial3D:
			triplanar_enabled = (
				body.material_override as StandardMaterial3D
			).uv1_triplanar
	return {
		"fixture_id": fixture_id,
		"local_normal": Vector3(fixture["surface_normal_local"]),
		"local_roundtrip": Fixtures.local_direction(fixture, world_normal),
		"triplanar_weights_local": Fixtures.triplanar_weights_local(fixture, world_normal),
		"triplanar_enabled": triplanar_enabled,
	}
