class_name WorldFillScarLayer
extends Node3D

## WF0.3 Surface Scars / Decals (WORLD FILL train).
##
## Presentation-only cosmetic layer derived from OBSERVED canonical events
## (command results / replicated event notifications). A scar is a visual
## node only: losing it, evicting it or aging it out can never alter world
## truth, persistence, replication or gameplay.
##
## Guarantees:
## - EVENT-DERIVED: scars appear only through record_event() inputs.
## - BUDGETED: at most MAX_ACTIVE_DECALS scars exist; oldest is evicted first.
## - BOUNDED LIFETIME: age_out(current_tick) removes scars older than
##   LIFETIME_TICKS presentation ticks.
## - FAIL-SOFT: unknown event types degrade to the generic surface_wear mark.
## - TRUTH-FREE: the layer owns only its own child nodes and counters.

const SCHEMA := "world_fill.scar_report.v1"

const MAX_ACTIVE_DECALS := 64
const LIFETIME_TICKS := 3600
const REJECTED_ACTION_EVENT := "COMMAND_REJECTED"

## Observed event type -> decal family (visual only).
const EVENT_FAMILIES := {
	"DIG_IMPACT": "impact_dust",
	"DIG_SUCCESS": "dig_scar",
	"MATERIAL_EXPOSED": "material_exposure",
	"BUILD_COMMIT": "construction_footprint",
	"CONTACT_TRACE": "contact_track",
	"COMMAND_REJECTED": "rejected_action",
}

const GENERIC_FAMILY := "surface_wear"

const FAMILY_COLORS := {
	"impact_dust": Color(0.42, 0.4, 0.36, 0.5),
	"dig_scar": Color(0.09, 0.09, 0.1, 0.7),
	"material_exposure": Color(0.45, 0.4, 0.3, 0.65),
	"construction_footprint": Color(0.3, 0.3, 0.28, 0.45),
	"contact_track": Color(0.24, 0.22, 0.2, 0.4),
	"rejected_action": Color(0.8, 0.15, 0.05, 0.6),
	"surface_wear": Color(0.2, 0.2, 0.2, 0.35),
}

const FAMILY_SIZES := {
	"impact_dust": Vector2(1.2, 1.2),
	"dig_scar": Vector2(1.8, 1.8),
	"material_exposure": Vector2(1.4, 1.4),
	"construction_footprint": Vector2(2.2, 2.2),
	"contact_track": Vector2(0.7, 3.0),
	"rejected_action": Vector2(0.6, 0.6),
	"surface_wear": Vector2(0.9, 0.9),
}

var _records: Array[Dictionary] = []


func record_event(event: Dictionary, observed_tick: int) -> Dictionary:
	var event_type := String(event.get("type", ""))
	var family := String(EVENT_FAMILIES.get(event_type, GENERIC_FAMILY))
	var position: Vector3 = event.get("position", Vector3.ZERO)
	var normal: Vector3 = event.get("normal", Vector3.UP).normalized()

	var record := {
		"family": family,
		"event_type": event_type,
		"observed_tick": observed_tick,
		"debug_only": family == "rejected_action",
	}
	var node := _build_mark_node(record, position, normal)
	add_child(node)
	record["node"] = node
	_records.append(record)

	while _records.size() > MAX_ACTIVE_DECALS:
		var evicted: Dictionary = _records.pop_front()
		var evicted_node: Node = evicted.get("node", null)
		if evicted_node != null and is_instance_valid(evicted_node):
			evicted_node.free()
	return scar_report()


func age_out(current_tick: int) -> Dictionary:
	var kept: Array[Dictionary] = []
	for record in _records:
		if current_tick - int(record.get("observed_tick", 0)) > LIFETIME_TICKS:
			var node: Node = record.get("node", null)
			if node != null and is_instance_valid(node):
				node.free()
		else:
			kept.append(record)
	_records = kept
	return scar_report()


func set_debug_marks_visible(visible_now: bool) -> void:
	for record in _records:
		if bool(record.get("debug_only", false)):
			var node: Node = record.get("node", null)
			if node != null and is_instance_valid(node):
				node.visible = visible_now


func scar_report() -> Dictionary:
	var by_family := {}
	var debug_only_count := 0
	for record in _records:
		var family := String(record.get("family", ""))
		by_family[family] = int(by_family.get(family, 0)) + 1
		if bool(record.get("debug_only", false)):
			debug_only_count += 1
	return {
		"schema": SCHEMA,
		"active": _records.size(),
		"max_active": MAX_ACTIVE_DECALS,
		"lifetime_ticks": LIFETIME_TICKS,
		"by_family": by_family,
		"debug_only": debug_only_count,
	}


func _build_mark_node(record: Dictionary, position: Vector3, normal: Vector3) -> MeshInstance3D:
	var family := String(record.get("family", GENERIC_FAMILY))
	var mark := MeshInstance3D.new()
	mark.name = "Scar_%s_%d" % [family, _records.size()]
	mark.mesh = _family_mesh(family)
	mark.material_override = _family_material(family)
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.transform = Transform3D(_surface_basis(normal), position + normal * 0.02)
	if bool(record.get("debug_only", false)):
		mark.visible = false
	return mark


func _surface_basis(normal: Vector3) -> Basis:
	var up := Vector3.UP
	var tangent := up.cross(normal)
	if tangent.length() < 0.01:
		tangent = Vector3.RIGHT.cross(normal)
	tangent = tangent.normalized()
	var bitangent := tangent.cross(normal).normalized()
	return Basis(tangent, normal, bitangent)


func _family_mesh(family: String) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	var size: Vector2 = FAMILY_SIZES.get(family, Vector2(0.9, 0.9))
	mesh.size = size
	mesh.subdivide_width = 0
	mesh.subdivide_depth = 0
	return mesh


func _family_material(family: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = FAMILY_COLORS.get(family, Color(0.2, 0.2, 0.2, 0.35))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.no_depth_test = false
	material.render_priority = 1
	return material
