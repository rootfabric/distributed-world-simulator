class_name WorldFillPropScatter
extends Node3D

## WF0.2 Deterministic Prop Scatter (native MultiMesh baseline, WORLD FILL train).
##
## Consumes a WF0.1 dressing decision (see
## scripts/world_fill/dressing/world_fill_dressing.gd) and places decorative
## prop instances via one MultiMeshInstance3D per prop family.
##
## Guarantees:
## - DETERMINISTIC: identical decision + base_seed => identical transforms.
## - BUDGETED: instances per family are capped by DENSITY_BUDGETS[band].
## - VISUAL ONLY: no collision, no physics, no replication, no persistence.
## - FAIL-SOFT: an empty decision produces zero instances, never an error.

const SCHEMA := "world_fill.scatter_report.v1"

const DENSITY_BUDGETS := {
	"none": 0,
	"sparse": 24,
	"moderate": 96,
	"dense": 288,
}

## Documented global cap: 6 families * dense budget.
const TOTAL_INSTANCE_CAP := 1728

const FAMILY_COLORS := {
	"stones": Color(0.13, 0.14, 0.15),
	"boulders": Color(0.16, 0.17, 0.18),
	"debris": Color(0.2, 0.18, 0.16),
	"dry_branches": Color(0.3, 0.24, 0.18),
	"crystals": Color(0.5, 0.62, 0.72),
	"industrial_scrap": Color(0.35, 0.33, 0.3),
}

const DEFAULT_SCALE_RANGE: Array = [0.2, 1.0]
const DEFAULT_TILT_RANGE: Array = [0.0, 30.0]

var _family_counts := {}


func build_from_decision(
	decision: Dictionary,
	region_extents: Vector2,
	base_seed: int
) -> Dictionary:
	clear_scatter()
	_family_counts = {}
	var families: Array = decision.get("prop_families", [])
	for entry in families:
		var family := String(entry.get("family", ""))
		if family == "":
			continue
		var band := String(entry.get("density_band", "none"))
		var count := int(DENSITY_BUDGETS.get(band, 0))
		if count <= 0:
			continue
		_build_family(
			decision,
			family,
			count,
			(entry.get("scale_range", DEFAULT_SCALE_RANGE) as Array).duplicate(),
			(entry.get("tilt_deg_range", DEFAULT_TILT_RANGE) as Array).duplicate(),
			region_extents,
			base_seed
		)
	return scatter_report()


func clear_scatter() -> void:
	for child in get_children().duplicate():
		if is_instance_valid(child):
			child.free()
	_family_counts = {}


func scatter_report() -> Dictionary:
	var total := 0
	for family in _family_counts:
		total += int(_family_counts[family])
	return {
		"schema": SCHEMA,
		"families": _family_counts.duplicate(),
		"total_instances": total,
		"multimesh_nodes": _multimesh_node_count(),
	}


func _build_family(
	decision: Dictionary,
	family: String,
	count: int,
	scale_range: Array,
	tilt_range: Array,
	region_extents: Vector2,
	base_seed: int
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _family_seed(decision, family, base_seed)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _family_mesh(family)
	multimesh.instance_count = count
	for index in count:
		multimesh.set_instance_transform(
			index,
			_place(rng, region_extents, scale_range, tilt_range, family)
		)
	var instance := MultiMeshInstance3D.new()
	instance.name = "Scatter_%s" % family
	instance.multimesh = multimesh
	instance.material_override = _family_material(family)
	instance.extra_cull_margin = 16.0
	add_child(instance)
	_family_counts[family] = count


func _family_seed(decision: Dictionary, family: String, base_seed: int) -> int:
	var payload := "%s|%s|%d" % [
		String(decision.get("determinism_key", "")),
		family,
		base_seed,
	]
	return payload.hash()


func _place(
	rng: RandomNumberGenerator,
	region_extents: Vector2,
	scale_range: Array,
	tilt_range: Array,
	family: String
) -> Transform3D:
	var s := rng.randf_range(float(scale_range[0]), float(scale_range[1]))
	var yaw := rng.randf_range(0.0, TAU)
	var tilt := deg_to_rad(rng.randf_range(float(tilt_range[0]), float(tilt_range[1])))
	var azimuth := rng.randf_range(0.0, TAU)
	var basis := Basis.from_euler(Vector3(
		cos(azimuth) * tilt,
		yaw,
		sin(azimuth) * tilt
	))
	var position := Vector3(
		rng.randf_range(-region_extents.x * 0.5, region_extents.x * 0.5),
		s * _family_y_factor(family),
		rng.randf_range(-region_extents.y * 0.5, region_extents.y * 0.5)
	)
	return Transform3D(basis.scaled(Vector3(s, s, s)), position)


func _family_y_factor(family: String) -> float:
	match family:
		"boulders":
			return 0.35
		"debris":
			return 0.12
		"dry_branches":
			return 0.45
		"crystals":
			return 0.4
		"industrial_scrap":
			return 0.2
		_:
			return 0.18


func _family_mesh(family: String) -> Mesh:
	match family:
		"boulders":
			var boulders := SphereMesh.new()
			boulders.radius = 0.9
			boulders.height = 1.4
			boulders.radial_segments = 12
			boulders.rings = 6
			return boulders
		"debris":
			var debris := BoxMesh.new()
			debris.size = Vector3(0.5, 0.2, 0.35)
			return debris
		"dry_branches":
			var branches := CylinderMesh.new()
			branches.top_radius = 0.02
			branches.bottom_radius = 0.05
			branches.height = 1.2
			branches.radial_segments = 6
			branches.rings = 1
			return branches
		"crystals":
			var crystals := PrismMesh.new()
			crystals.size = Vector3(0.3, 0.8, 0.3)
			return crystals
		"industrial_scrap":
			var scrap := BoxMesh.new()
			scrap.size = Vector3(0.8, 0.4, 0.6)
			return scrap
		_:
			var stones := SphereMesh.new()
			stones.radius = 0.25
			stones.height = 0.4
			stones.radial_segments = 10
			stones.rings = 5
			return stones


func _family_material(family: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = FAMILY_COLORS.get(family, Color(0.18, 0.18, 0.18))
	material.roughness = 0.95
	return material


func _multimesh_node_count() -> int:
	var count := 0
	for child in get_children():
		if child is MultiMeshInstance3D:
			count += 1
	return count
