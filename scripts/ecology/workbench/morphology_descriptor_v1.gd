# EcologyWorkbench MorphologyDescriptor v1 (P6, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: DERIVED read-only projection over canonical BodyGraph modules for
#   presentation: absolute geometry (module centres, bounding sizes), a
#   UNIVERSAL role_class enum and the canonical topology signature.
#   NOT a second morphology truth; never written back to
#   Genome/DevelopmentProgram/BodyGraph. No species labels, no biology
#   computations — pure geometric projection (A10.5 brief §14).
# Layer: 3 (READ-ONLY PROJECTION).
# Canonical API used (owner map rows 3,8,10):
#   - body_graph_v1.gd: topology_signature(modules)  [A1/A2]
#   - canonical_value_v1.gd: digest()  (descriptor determinism)
# Input: canonical development/body modules (organism_state_v1 compatible,
#   e.g. controller debug_state population entry.state.development.modules)
#   plus the organism position so module offsets become absolute mm.
# Universal fallback: ANY non-empty module list produces a descriptor; an
#   unrecognized role maps to role_class "unknown" (never an error).
class_name EcoWorkbenchMorphologyDescriptorV1
extends RefCounted

const SCHEMA := "dws.ecology.workbench.morphology-descriptor.v1"

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")

# Universal role classes: projection of the canonical role vocabulary into a
# presentation-only enum. Roles are used ONLY for colour differentiation in
# the realizer — never for shape selection or validity gating.
const ROLE_CLASSES := {
	"attachment": "attachment",
	"support": "support",
	"transport": "support",
	"collector": "collector",
	"absorber": "absorber",
	"storage": "storage",
	"reproductive": "reproductive",
	"sensor": "sensor",
	"defense": "defense",
}

## Build descriptor from canonical body modules. Pure function, read-only:
## never mutates the input; identical input => identical descriptor_digest.
## body_modules: canonical module dicts ({id,parent,role,start_mm,end_mm,
## radius_mm,area_mm2,reach_mm,...}); position_mm: organism absolute origin.
static func compile(body_modules: Array, entity_id: String, position_mm: Array) -> Dictionary:
	if body_modules.is_empty() or not position_mm is Array or position_mm.size() != 3:
		return {}
	var modules: Array = []
	var min_mm: Array = [position_mm[0], position_mm[1], position_mm[2]]
	var max_mm: Array = min_mm.duplicate()
	for m in body_modules:
		if not m is Dictionary or not m.has("id") or not m.has("start_mm") or not m.has("end_mm"):
			continue
		var start_abs: Array = [
			int(position_mm[0]) + int(m.start_mm[0]),
			int(position_mm[1]) + int(m.start_mm[1]),
			int(position_mm[2]) + int(m.start_mm[2]),
		]
		var end_abs: Array = [
			int(position_mm[0]) + int(m.end_mm[0]),
			int(position_mm[1]) + int(m.end_mm[1]),
			int(position_mm[2]) + int(m.end_mm[2]),
		]
		var radius: int = int(m.get("radius_mm", 0))
		# Bounding size per axis: segment extent clamped from below by the
		# module diameter (zero-length tips still have a radius).
		var size: Array = [
			maxi(absi(end_abs[0] - start_abs[0]), 2 * radius),
			maxi(absi(end_abs[1] - start_abs[1]), 2 * radius),
			maxi(absi(end_abs[2] - start_abs[2]), 2 * radius),
		]
		for axis in 3:
			min_mm[axis] = mini(min_mm[axis], start_abs[axis] - radius)
			min_mm[axis] = mini(min_mm[axis], end_abs[axis] - radius)
			max_mm[axis] = maxi(max_mm[axis], start_abs[axis] + radius)
			max_mm[axis] = maxi(max_mm[axis], end_abs[axis] + radius)
		var role := String(m.get("role", ""))
		modules.append({
			"id": String(m.id),
			"parent": String(m.get("parent", "")),
			"role": role,
			"role_class": String(ROLE_CLASSES.get(role, "unknown")),
			# Module centre (absolute mm).
			"position_mm": [
				(start_abs[0] + end_abs[0]) / 2,
				(start_abs[1] + end_abs[1]) / 2,
				(start_abs[2] + end_abs[2]) / 2,
			],
			"start_mm": start_abs,
			"end_mm": end_abs,
			"size_mm": size,
			"radius_mm": radius,
			"area_mm2": int(m.get("area_mm2", 0)),
			"reach_mm": int(m.get("reach_mm", 0)),
		})
	if modules.is_empty():
		return {}
	var descriptor := {
		"schema": SCHEMA,
		"entity_id": entity_id,
		"origin_mm": [int(position_mm[0]), int(position_mm[1]), int(position_mm[2])],
		"modules": modules,
		# Canonical topology signature (body_graph_v1); empty string when the
		# module list is not canonical-valid (descriptor is still produced).
		"topology_signature": B.topology_signature(body_modules),
		"bounds_mm": {"min_mm": min_mm, "max_mm": max_mm},
	}
	descriptor["descriptor_digest"] = C.digest(descriptor)
	return descriptor
