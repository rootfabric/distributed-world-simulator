# EcologyWorkbench GenericMorphologyRealizer v1 (P6, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: MANDATORY universal procedural realizer: renders ANY valid, previously
#   unknown BodyGraph topology via generic primitives (capsule segments,
#   spheres/junctions, junction_plane membranes). Roles influence ONLY colour
#   differentiation — never shape, never composition, never validity.
#   Unknown role_class => neutral primitive + neutral colour (universal
#   fallback, A10.5 brief §14/§27). No species/curated branches, ever.
# Layer: 4 (PRESENTATION / UI).
# Pure function: descriptor + visual_profile -> primitive manifest. No Node
#   dependencies, no sim-state access, headless-testable. The thin Godot
#   adapter (build_meshes) lives in ecology_workbench.gd / the lab host.
# LOD changes ONLY primitive detail (radial_segments/rings/merge thresholds);
#   it never changes primitive composition, module coverage or canonical state.
# Forbidden: renderer write-back into canonical Genome/BodyGraph; presentation
#   changes must not alter ecological hash / fitness / reproduction.
class_name EcoWorkbenchGenericMorphologyRealizerV1
extends RefCounted

const SCHEMA := "dws.ecology.workbench.generic-realizer-manifest.v1"

const Descriptor = preload("res://scripts/ecology/workbench/morphology_descriptor_v1.gd")

# LOD detail table: HIGH/MEDIUM/LOW change only mesh detail parameters.
const LOD_DETAIL := {
	"HIGH": {"radial_segments": 12, "rings": 8},
	"MEDIUM": {"radial_segments": 8, "rings": 6},
	"LOW": {"radial_segments": 4, "rings": 3},
}

# Presentation-only hue per universal role_class (NOT a biology truth).
const ROLE_HUES := {
	"support": 0.08,
	"transport": 0.13,
	"collector": 0.30,
	"absorber": 0.58,
	"reproductive": 0.85,
	"storage": 0.47,
	"sensor": 0.62,
	"defense": 0.02,
	"attachment": 0.72,
}

const NEUTRAL_COLOR := [0.55, 0.55, 0.55, 1.0]
const MEMBRANE_ALPHA := 0.35

## Realize a descriptor into a presentation primitive manifest. Pure.
## visual_profile: {"lod": "HIGH"|"MEDIUM"|"LOW" (default HIGH),
##                  "palette_seed": int (default 0)}.
## Coverage contract: >= 1 primitive per module and >= 1 primitive per
## parent->child edge, for ANY descriptor (including unknown role classes).
static func realize(descriptor: Dictionary, visual_profile: Dictionary = {}) -> Dictionary:
	if not descriptor is Dictionary or descriptor.is_empty() or not descriptor.has("modules"):
		return {}
	var lod := String(visual_profile.get("lod", "HIGH")).to_upper()
	if not LOD_DETAIL.has(lod):
		lod = "HIGH"
	var detail: Dictionary = LOD_DETAIL[lod]
	var seed := int(visual_profile.get("palette_seed", 0))
	var primitives: Array = []
	for module in descriptor.modules:
		var color: Array = _role_color(String(module.role_class), seed)
		var start: Array = module.start_mm
		var end: Array = module.end_mm
		var radius: int = maxi(1, int(module.radius_mm))
		var length := _length_mm(start, end)
		# (1) Module body: capsule segment when the module spans space,
		#     sphere for zero-length tips (universal — shape does not depend
		#     on the role, only colour does).
		if length > 0:
			primitives.append(_primitive(
				"capsule", module, color, detail, start, end, radius, {}
			))
		else:
			primitives.append(_primitive(
				"sphere", module, color, detail, start, end, radius, {}
			))
		# (2) Edge coverage: junction sphere at the attachment point of every
		#     child module (parent -> child edge), regardless of role.
		if String(module.parent) != "":
			primitives.append(_primitive(
				"sphere", module, color, detail, start, start, maxi(1, radius / 2 + 1),
				{"edge": "%s->%s" % [String(module.parent), String(module.id)]}
			))
		# (3) Membranes/surfaces from body-state area/reach data:
		#     semitransparent junction_plane at the module tip.
		var membrane_size := maxi(int(module.area_mm2), int(module.reach_mm))
		if membrane_size > 0:
			var side: int = isqrt_side(membrane_size)
			primitives.append(_primitive(
				"junction_plane", module, [color[0], color[1], color[2], MEMBRANE_ALPHA],
				detail, end, end, 0, {"size_mm": [side, side, 0]}
			))
	var manifest := {
		"schema": SCHEMA,
		"entity_id": String(descriptor.get("entity_id", "")),
		"lod": lod,
		"palette_seed": seed,
		"primitives": primitives,
		"primitive_count": primitives.size(),
	}
	return manifest

## Integer side length (mm) of a square membrane approximating an area/reach.
static func isqrt_side(area: int) -> int:
	if area <= 0:
		return 0
	var x := area
	var y := (x + 1) / 2
	while y < x:
		x = y
		y = (x + area / x) / 2
	return x

static func _length_mm(a: Array, b: Array) -> int:
	var squared := 0
	for i in 3:
		var d: int = int(b[i]) - int(a[i])
		squared += d * d
	return roundi(sqrt(float(squared)))

static func _primitive(kind: String, module: Dictionary, color: Array, detail: Dictionary, from_mm: Array, to_mm: Array, radius_mm: int, extra: Dictionary) -> Dictionary:
	var center: Array = [
		(int(from_mm[0]) + int(to_mm[0])) / 2,
		(int(from_mm[1]) + int(to_mm[1])) / 2,
		(int(from_mm[2]) + int(to_mm[2])) / 2,
	]
	var primitive := {
		"kind": kind,
		"module_id": String(module.id),
		"role_class": String(module.role_class),
		"edge": String(extra.get("edge", "")),
		"from_mm": [int(from_mm[0]), int(from_mm[1]), int(from_mm[2])],
		"to_mm": [int(to_mm[0]), int(to_mm[1]), int(to_mm[2])],
		"center_mm": center,
		"radius_mm": radius_mm,
		"size_mm": extra.get("size_mm", module.get("size_mm", [0, 0, 0])),
		"color": color,
		"radial_segments": int(detail.radial_segments),
		"rings": int(detail.rings),
	}
	return primitive

## Deterministic presentation colour per universal role_class + palette seed.
## Unknown role classes get the neutral colour (universal fallback).
static func _role_color(role_class: String, seed: int) -> Array:
	if not ROLE_HUES.has(role_class):
		return NEUTRAL_COLOR.duplicate()
	var hue := fposmod(float(ROLE_HUES[role_class]) + float(absi(seed) % 97) * 0.011, 1.0)
	var c := Color.from_hsv(hue, 0.55, 0.85)
	return [c.r, c.g, c.b, 1.0]
