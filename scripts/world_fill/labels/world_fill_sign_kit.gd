class_name WorldFillSignKit
extends Node3D

## WF0.9 Labels / Signs / Identity (WORLD FILL train).
##
## Cheap spatial and social readability: local, fixture-backed text labels
## and signposts. R1 is intentionally NOT networked-editable; authoritative
## editable annotations require a separate canonical proposal.
##
## Guarantees:
## - LOCAL/FIXTURE-BACKED: labels come from local code/callers only.
## - BUDGETED: at most MAX_SIGNS signs; oldest evicted first.
## - SANITIZED: text is single-line, length-capped, and must be non-empty.
## - FAIL-SOFT: invalid input is skipped with an explicit reason.
## - TRUTH-FREE: presentation nodes and counters only.

const SCHEMA := "world_fill.sign_report.v1"

const MAX_SIGNS := 64
const MAX_TEXT_LENGTH := 64

const STYLES := {
	"location_name": {"color": Color(0.92, 0.94, 0.98), "size": 0.012, "height": 4.2},
	"outpost_label": {"color": Color(0.95, 0.75, 0.3), "size": 0.01, "height": 3.6},
	"container_label": {"color": Color(0.7, 0.85, 0.7), "size": 0.008, "height": 0.9},
	"poi_label": {"color": Color(0.6, 0.85, 0.95), "size": 0.01, "height": 3.4},
	"warning_sign": {"color": Color(0.95, 0.35, 0.15), "size": 0.011, "height": 2.2},
}

const DEFAULT_STYLE := "location_name"

var _records: Array[Dictionary] = []


func create_sign(text: String, position: Vector3, style: String = DEFAULT_STYLE, options: Dictionary = {}) -> Dictionary:
	var report := {
		"schema": SCHEMA,
		"text": "",
		"spawned": false,
		"reason": "",
	}
	var sanitized := _sanitize_text(text)
	if sanitized == "":
		report["reason"] = "EMPTY_TEXT"
		return report
	if not STYLES.has(style):
		style = DEFAULT_STYLE
	var post := bool(options.get("with_post", true))
	var sanitized_style := style

	while _records.size() >= MAX_SIGNS:
		_evict_oldest()

	var sign := Node3D.new()
	sign.name = "Sign_%s_%d" % [sanitized.substr(0, 8).replace(" ", "_"), _records.size()]
	add_child(sign)

	var style_def: Dictionary = STYLES[sanitized_style]
	var label := Label3D.new()
	label.name = "Text"
	label.text = sanitized
	label.font_size = 64
	label.pixel_size = float(style_def["size"])
	label.modulate = style_def["color"]
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, float(style_def["height"]), 0.0)
	sign.add_child(label)

	if post:
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.04
		pole_mesh.bottom_radius = 0.06
		pole_mesh.height = float(style_def["height"])
		pole.mesh = pole_mesh
		pole.position = Vector3(0.0, float(style_def["height"]) * 0.5, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.4, 0.42, 0.45)
		material.roughness = 0.85
		pole.material_override = material
		sign.add_child(pole)

	sign.position = position
	var record := {"text": sanitized, "style": sanitized_style, "node": sign}
	_records.append(record)
	report["text"] = sanitized
	report["spawned"] = true
	return report


func sign_report() -> Dictionary:
	var by_style := {}
	for record in _records:
		var style := String(record.get("style", ""))
		by_style[style] = int(by_style.get(style, 0)) + 1
	return {
		"schema": SCHEMA,
		"active": _records.size(),
		"max_signs": MAX_SIGNS,
		"by_style": by_style,
	}


func clear_signs() -> void:
	for record in _records:
		var node: Node = record.get("node", null)
		if node != null and is_instance_valid(node):
			node.free()
	_records.clear()


func _evict_oldest() -> void:
	if _records.is_empty():
		return
	var evicted: Dictionary = _records.pop_front()
	var node: Node = evicted.get("node", null)
	if node != null and is_instance_valid(node):
		node.free()


func _sanitize_text(text: String) -> String:
	var flattened := text.replace("\n", " ").replace("\r", " ").strip_edges()
	if flattened.length() > MAX_TEXT_LENGTH:
		flattened = flattened.substr(0, MAX_TEXT_LENGTH)
	return flattened
