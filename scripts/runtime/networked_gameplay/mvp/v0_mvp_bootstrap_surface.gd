extends Node3D

# An immutable presentation cache, NOT a client-side Matter authority.
# The accepted P7 builder and presenter are temporary: only derived meshes remain.
const Bubble = preload("res://scripts/world/matter/lunar_matter_bubble.gd")
const Presenter = preload("res://scripts/world/matter/lunar_matter_bubble_presenter.gd")
const ANCHOR := Vector3(0.0, 1737425.0, 0.0)
const DESCRIPTOR := {
	"anchor_direction": [0.0, 1.0, 0.0],
	"canonical_surface_radius_m": 1737425.0,
	"half_extent_m": 8.0,
	"mutation_level": 1,
	"presentation_level": 1,
	"max_level": 2,
	"brick_interior_resolution": 4,
	"ghost_border_samples": 1,
}

var _configured := false
var _bootstrap_hash := ""
var _mesh_count := 0


func configure(draw_surface: bool) -> Dictionary:
	if _configured:
		return {"success": false, "error_code": "MVP2_SURFACE_ALREADY_CONFIGURED"}
	var builder = Bubble.new()
	var result: Dictionary = builder.configure(DESCRIPTOR.duplicate(true))
	if not bool(result.get("success", false)):
		return result
	builder.materialize_presentation_level()
	if draw_surface:
		var temporary = Presenter.new()
		add_child(temporary)
		result = temporary.configure(builder, self, false)
		if not bool(result.get("success", false)):
			temporary.free()
			return result
		# No rebuild API, snapshot store or excavation service is retained.
		for mesh_root in temporary.get_children():
			temporary.remove_child(mesh_root)
			add_child(mesh_root)
			_mesh_count += 1
		temporary.free()
	_bootstrap_hash = String(builder.snapshot_store().content_hash())
	_configured = not _bootstrap_hash.is_empty()
	return {"success": _configured, "error_code": "" if _configured else "MVP2_BOOTSTRAP_HASH_EMPTY"}


func world_to_render(body_fixed_position: Vector3) -> Vector3:
	return body_fixed_position - ANCHOR


func contract_report() -> Dictionary:
	return {
		"mode": "IMMUTABLE_P7_BOOTSTRAP_PROJECTION",
		"configured": _configured,
		"descriptor": DESCRIPTOR.duplicate(true),
		"bootstrap_hash": _bootstrap_hash,
		"mesh_count": _mesh_count,
		"canonical_state_owned": false,
		"mutable_matter_store_retained": false,
		"collision_enabled": false,
		"network_mutation_proven": false,
	}
