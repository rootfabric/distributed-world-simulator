extends RefCounted

## WP0.9 — shared POI library for WORLD PACKS.
##
## Deterministic, asset-free point-of-interest fixtures shared by all packs.
## A pack selects fixtures through its manifest `poi.catalog` and skin colors;
## it never gains authority, persistence or gameplay semantics from POIs.
##
## Every builder returns a named Node3D subtree made of primitive meshes only,
## so the library stays license-clean and works headless.

const DEFAULT_SKIN: Dictionary = {
	"primary": Color(0.45, 0.46, 0.48),
	"secondary": Color(0.30, 0.31, 0.33),
	"accent": Color(0.95, 0.45, 0.10),
	"emissive": Color(1.0, 0.55, 0.15),
	"metallic": 0.55,
	"roughness": 0.55,
}


static func supported_ids() -> PackedStringArray:
	return PackedStringArray([
		"beacon",
		"tiny_outpost",
		"landing_pad",
		"wreck",
		"research_station_module",
		"cave_marker",
		"broken_pipeline",
	])


static func build(poi_id: String, skin: Dictionary = {}) -> Node3D:
	var merged_skin: Dictionary = DEFAULT_SKIN.duplicate(true)
	for key in skin:
		merged_skin[key] = skin[key]
	var node: Node3D
	match poi_id:
		"beacon":
			node = _build_beacon(merged_skin)
		"tiny_outpost":
			node = _build_tiny_outpost(merged_skin)
		"landing_pad":
			node = _build_landing_pad(merged_skin)
		"wreck":
			node = _build_wreck(merged_skin)
		"research_station_module":
			node = _build_research_module(merged_skin)
		"cave_marker":
			node = _build_cave_marker(merged_skin)
		"broken_pipeline":
			node = _build_broken_pipeline(merged_skin)
		_:
			node = Node3D.new()
	node.name = "POI_%s" % poi_id
	return node


static func _material(skin: Dictionary, color_key: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = skin.get(color_key, skin["primary"])
	material.metallic = float(skin.get("metallic", 0.55))
	material.roughness = float(skin.get("roughness", 0.55))
	return material


static func _emissive_material(skin: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = skin.get("emissive", DEFAULT_SKIN["emissive"])
	material.emission_enabled = true
	material.emission = skin.get("emissive", DEFAULT_SKIN["emissive"])
	material.emission_energy_multiplier = 2.2
	return material


static func _mesh_instance(mesh: Mesh, material: StandardMaterial3D, name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	return instance


static func _build_beacon(skin: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mast := _mesh_instance(
		_cylinder(0.09, 0.13, 3.2),
		_material(skin, "secondary"),
		"Mast"
	)
	mast.position.y = 1.6
	root.add_child(mast)
	var lamp := _mesh_instance(
		_sphere(0.32),
		_emissive_material(skin),
		"Lamp"
	)
	lamp.position.y = 3.4
	root.add_child(lamp)
	var base := _mesh_instance(
		_box(Vector3(0.7, 0.25, 0.7)),
		_material(skin, "primary"),
		"Base"
	)
	base.position.y = 0.125
	root.add_child(base)
	return root


static func _build_tiny_outpost(skin: Dictionary) -> Node3D:
	var root := Node3D.new()
	var cabin := _mesh_instance(
		_box(Vector3(2.6, 1.5, 2.0)),
		_material(skin, "primary"),
		"Cabin"
	)
	cabin.position.y = 0.75
	root.add_child(cabin)
	var roof := _mesh_instance(
		_box(Vector3(2.9, 0.22, 2.3)),
		_material(skin, "secondary"),
		"Roof"
	)
	roof.position.y = 1.6
	root.add_child(roof)
	var antenna := _mesh_instance(
		_cylinder(0.05, 0.07, 1.6),
		_material(skin, "secondary"),
		"Antenna"
	)
	antenna.position = Vector3(-0.9, 2.4, -0.5)
	root.add_child(antenna)
	var dish := _mesh_instance(
		_sphere(0.28),
		_emissive_material(skin),
		"AntennaLamp"
	)
	dish.position = Vector3(-0.9, 3.25, -0.5)
	root.add_child(dish)
	return root


static func _build_landing_pad(skin: Dictionary) -> Node3D:
	var root := Node3D.new()
	var deck := _mesh_instance(
		_cylinder(2.6, 2.9, 0.22),
		_material(skin, "secondary"),
		"Deck"
	)
	deck.position.y = 0.11
	root.add_child(deck)
	var ring := _mesh_instance(
		_torus(2.35, 0.12),
		_emissive_material(skin),
		"GuideRing"
	)
	ring.position.y = 0.24
	ring.rotation_degrees.x = 90.0
	root.add_child(ring)
	var pylon := _mesh_instance(
		_cylinder(0.08, 0.1, 1.4),
		_material(skin, "primary"),
		"Pylon"
	)
	pylon.position = Vector3(2.35, 0.7, 0.0)
	root.add_child(pylon)
	return root


static func _build_wreck(skin: Dictionary) -> Node3D:
	var root := Node3D.new()
	var hull := _mesh_instance(
		_box(Vector3(3.1, 1.1, 1.6)),
		_material(skin, "secondary"),
		"Hull"
	)
	hull.position.y = 0.5
	hull.rotation_degrees = Vector3(9.0, 24.0, -14.0)
	root.add_child(hull)
	var rib := _mesh_instance(
		_cylinder(0.28, 0.34, 1.8),
		_material(skin, "primary"),
		"Rib"
	)
	rib.position = Vector3(1.1, 0.35, -0.9)
	rib.rotation_degrees = Vector3(78.0, 0.0, 32.0)
	root.add_child(rib)
	var debris := _mesh_instance(
		_box(Vector3(0.9, 0.35, 0.7)),
		_material(skin, "primary"),
		"Debris"
	)
	debris.position = Vector3(-1.6, 0.18, 1.1)
	debris.rotation_degrees.y = 51.0
	root.add_child(debris)
	return root


static func _build_research_module(skin: Dictionary) -> Node3D:
	var root := Node3D.new()
	var body := _mesh_instance(
		_cylinder(0.85, 0.85, 3.4),
		_material(skin, "primary"),
		"Body"
	)
	body.position.y = 1.0
	body.rotation_degrees.z = 90.0
	root.add_child(body)
	var dome := _mesh_instance(
		_sphere(0.62),
		_emissive_material(skin),
		"ViewDome"
	)
	dome.position = Vector3(1.4, 1.35, 0.0)
	root.add_child(dome)
	for leg_index in range(3):
		var leg := _mesh_instance(
			_cylinder(0.06, 0.06, 1.0),
			_material(skin, "secondary"),
			"Leg%d" % leg_index
		)
		var angle: float = TAU * float(leg_index) / 3.0
		leg.position = Vector3(-0.5 + 0.35 * leg_index, 0.35, 0.7 * sin(angle))
		leg.rotation_degrees.z = -12.0 + 12.0 * leg_index
		root.add_child(leg)
	return root


static func _build_cave_marker(skin: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mound := _mesh_instance(
		_sphere(1.15),
		_material(skin, "secondary"),
		"Mound"
	)
	mound.position.y = -0.35
	mound.scale = Vector3(1.4, 0.55, 1.1)
	root.add_child(mound)
	var mouth := _mesh_instance(
		_sphere(0.55),
		_emissive_material(skin),
		"Mouth"
	)
	mouth.position = Vector3(0.0, 0.28, 0.72)
	root.add_child(mouth)
	var post := _mesh_instance(
		_cylinder(0.05, 0.05, 1.1),
		_material(skin, "primary"),
		"Post"
	)
	post.position = Vector3(0.9, 0.55, -0.4)
	root.add_child(post)
	return root


static func _build_broken_pipeline(skin: Dictionary) -> Node3D:
	var root := Node3D.new()
	var segment_a := _mesh_instance(
		_cylinder(0.3, 0.3, 2.4),
		_material(skin, "primary"),
		"SegmentA"
	)
	segment_a.position = Vector3(-1.2, 0.45, 0.0)
	segment_a.rotation_degrees.z = 90.0
	root.add_child(segment_a)
	var segment_b := _mesh_instance(
		_cylinder(0.3, 0.3, 1.5),
		_material(skin, "secondary"),
		"SegmentB"
	)
	segment_b.position = Vector3(1.6, 0.3, 0.4)
	segment_b.rotation_degrees = Vector3(0.0, 0.0, 96.0)
	root.add_child(segment_b)
	var leak := _mesh_instance(
		_sphere(0.22),
		_emissive_material(skin),
		"LeakMarker"
	)
	leak.position = Vector3(0.25, 0.12, 0.15)
	root.add_child(leak)
	return root


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _cylinder(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 16
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


static func _torus(inner_radius: float, tube_radius: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = inner_radius + tube_radius * 2.0
	mesh.rings = 24
	mesh.ring_segments = 8
	return mesh
