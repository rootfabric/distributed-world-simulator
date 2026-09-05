extends RefCounted

## WP-VIS1 Surface Material Lab — fixture registry (GENERIC_LAB_SCAFFOLD).
##
## Presentation-only, asset-free fixture descriptors for the generic
## arbitrary-orientation surface material lab. This registry is data, not
## canonical truth: it exists to surface Y-up assumptions inside the
## presentation machinery before WORLDGEN runtime integration.
##
## Every fixture declares the outward normal of its primary presentation
## surface in the FIXTURE-LOCAL frame plus an explicit rotation. Mapping code
## must consume the fixture local frame; it must NOT treat global
## Vector3.UP as physical truth.

const MILESTONE_SCAFFOLD: String = "GENERIC_LAB_SCAFFOLD"

## Ordered fixture descriptors. `built_in_milestone` records which lab
## milestone instantiates the real surface; the scaffold milestone only
## validates the descriptor and places a marker.
const FIXTURES: Array[Dictionary] = [
	{
		"id": "horizontal_plane",
		"label": "Horizontal surface",
		"shape": "box",
		"size": Vector3(4.0, 0.2, 4.0),
		"position": Vector3(-7.5, 0.0, -5.0),
		"rotation_degrees": Vector3(0.0, 0.0, 0.0),
		"surface_normal_local": Vector3(0.0, 1.0, 0.0),
		"diagnostic_color": Color(0.55, 0.55, 0.58),
		"built_in_milestone": "HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES",
	},
	{
		"id": "slope_45",
		"label": "45-degree slope",
		"shape": "box",
		"size": Vector3(4.0, 0.2, 4.0),
		"position": Vector3(-2.5, 1.2, -5.0),
		"rotation_degrees": Vector3(0.0, 0.0, 45.0),
		"surface_normal_local": Vector3(0.0, 1.0, 0.0),
		"diagnostic_color": Color(0.62, 0.5, 0.32),
		"built_in_milestone": "HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES",
	},
	{
		"id": "vertical_wall",
		"label": "Vertical wall",
		"shape": "box",
		"size": Vector3(4.0, 0.2, 3.0),
		"position": Vector3(2.5, 1.6, -5.0),
		"rotation_degrees": Vector3(-90.0, 0.0, 0.0),
		"surface_normal_local": Vector3(0.0, 1.0, 0.0),
		"diagnostic_color": Color(0.42, 0.5, 0.6),
		"built_in_milestone": "HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES",
	},
	{
		"id": "overhang",
		"label": "Overhang",
		"shape": "box",
		"size": Vector3(3.0, 0.2, 3.0),
		"position": Vector3(-6.0, 2.6, 1.5),
		"rotation_degrees": Vector3(-135.0, 0.0, 0.0),
		"surface_normal_local": Vector3(0.0, 1.0, 0.0),
		"diagnostic_color": Color(0.5, 0.4, 0.62),
		"built_in_milestone": "OVERHANG_AND_INVERTED_SURFACES",
	},
	{
		"id": "inverted_ceiling",
		"label": "Inverted / ceiling surface",
		"shape": "box",
		"size": Vector3(3.0, 0.2, 3.0),
		"position": Vector3(-1.0, 2.8, 1.5),
		"rotation_degrees": Vector3(180.0, 0.0, 0.0),
		"surface_normal_local": Vector3(0.0, 1.0, 0.0),
		"diagnostic_color": Color(0.58, 0.42, 0.42),
		"built_in_milestone": "OVERHANG_AND_INVERTED_SURFACES",
	},
	{
		"id": "sphere_fixture",
		"label": "Sphere / irregular fixture",
		"shape": "sphere",
		"size": Vector3(1.6, 1.6, 1.6),
		"position": Vector3(4.0, 1.6, 1.5),
		"rotation_degrees": Vector3(0.0, 0.0, 0.0),
		# A sphere exposes every orientation at once; the primary probe
		# direction is its +X point for diagnostic purposes.
		"surface_normal_local": Vector3(1.0, 0.0, 0.0),
		"diagnostic_color": Color(0.36, 0.56, 0.5),
		"built_in_milestone": "SPHERE_OR_IRREGULAR_FIXTURE",
	},
	{
		"id": "irregular_rock",
		"label": "Irregular rock fixture",
		"shape": "irregular_rock",
		"size": Vector3(2.2, 1.4, 1.8),
		"position": Vector3(7.5, 0.9, 1.5),
		"rotation_degrees": Vector3(-20.0, 35.0, 10.0),
		# Composite irregular surface: probe normal is a tilted diagonal so no
		# single world axis ever matches it exactly. Literal pre-normalized
		# (1,1,1)/sqrt(3) because const dictionaries need constant expressions.
		"surface_normal_local": Vector3(0.57735026919, 0.57735026919, 0.57735026919),
		"diagnostic_color": Color(0.45, 0.38, 0.3),
		"built_in_milestone": "SPHERE_OR_IRREGULAR_FIXTURE",
	},
]

## Fixture ids the lab declares as its minimal orientation coverage set.
const REQUIRED_IDS: PackedStringArray = [
	"horizontal_plane",
	"slope_45",
	"vertical_wall",
	"overhang",
	"inverted_ceiling",
	"sphere_fixture",
	"irregular_rock",
]


static func ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for fixture in FIXTURES:
		result.append(String(fixture["id"]))
	return result


static func has(fixture_id: String) -> bool:
	return find(fixture_id) >= 0


static func find(fixture_id: String) -> int:
	for index in FIXTURES.size():
		if String(FIXTURES[index]["id"]) == fixture_id:
			return index
	return -1


static func descriptor(fixture_id: String) -> Dictionary:
	var index := find(fixture_id)
	assert(index >= 0, "unknown WP-VIS1 lab fixture id: %s" % fixture_id)
	return FIXTURES[index]


## Outward surface normal of the primary presentation surface expressed in
## WORLD space for the declared rotation. Mapping code must derive frames
## from here instead of assuming Vector3.UP.
static func world_surface_normal(fixture: Dictionary) -> Vector3:
	var euler_radians := deg_to_rad_euler(Vector3(fixture["rotation_degrees"]))
	var basis := Basis.from_euler(euler_radians)
	return (basis * Vector3(fixture["surface_normal_local"])).normalized()


static func deg_to_rad_euler(euler_degrees: Vector3) -> Vector3:
	return Vector3(
		deg_to_rad(euler_degrees.x),
		deg_to_rad(euler_degrees.y),
		deg_to_rad(euler_degrees.z)
	)


## Structural self-check of the descriptor registry itself. Returns a list of
## human-readable problems; empty list means the scaffold registry is sound.
static func validate_registry() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen: Dictionary = {}

	for fixture in FIXTURES:
		var fixture_id := String(fixture.get("id", ""))
		if fixture_id.is_empty():
			problems.append("fixture without id")
			continue
		if seen.has(fixture_id):
			problems.append("duplicate fixture id: %s" % fixture_id)
		seen[fixture_id] = true

		var normal: Vector3 = fixture.get("surface_normal_local", Vector3.ZERO)
		if not normal.is_normalized():
			problems.append("fixture %s surface_normal_local is not normalized" % fixture_id)
		if normal == Vector3.ZERO:
			problems.append("fixture %s surface_normal_local is zero" % fixture_id)

		var position: Vector3 = fixture.get("position", Vector3.ZERO)
		if position == Vector3.ZERO:
			problems.append("fixture %s overlaps the world origin probe" % fixture_id)

		if String(fixture.get("shape", "")) not in ["box", "sphere", "irregular_rock"]:
			problems.append("fixture %s has unsupported shape" % fixture_id)

	for required_id in REQUIRED_IDS:
		if not seen.has(required_id):
			problems.append("missing required fixture id: %s" % required_id)

	# Orientation-coverage proof: world-space normals must cover at least
	# one up-facing, one side-facing and one down-facing surface so that a
	# hidden Y-up assumption becomes visible in the scaffold itself.
	var up_facing := false
	var side_facing := false
	var down_facing := false
	for fixture in FIXTURES:
		var world_normal := world_surface_normal(fixture)
		if world_normal.y > 0.7:
			up_facing = true
		elif absf(world_normal.y) < 0.3:
			side_facing = true
		elif world_normal.y < -0.7:
			down_facing = true
	if not up_facing:
		problems.append("no up-facing fixture declared")
	if not side_facing:
		problems.append("no side-facing fixture declared")
	if not down_facing:
		problems.append("no down-facing (inverted/overhang) fixture declared")

	return problems
