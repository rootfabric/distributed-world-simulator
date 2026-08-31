extends RefCounted

## ECO.EVO7 VIS4.6 — Grid Appearance Boundary.
##
## Reuses the accepted VIS2 stable-jitter semantics in 3D presentation space.
## The output is deliberately noncanonical: ecological cell_index/direction and
## the canonical surface point remain truth. This contract only derives a
## bounded tangent-plane offset for rendering.

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis4_6_grid_appearance.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS4.6.R1"

const X_SPAN_CELL := 0.48
const Y_SPAN_CELL := 0.30
const X_HALF_EXTENT_CELL := X_SPAN_CELL * 0.5
const Y_HALF_EXTENT_CELL := Y_SPAN_CELL * 0.5

const PRESENTATION_ONLY := true
const CANONICAL_POSITION := false
const ECOLOGY_AUTHORITY := false
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false


static func build(
	record_id: String,
	cell_index: int,
	source_descriptor_hash: String,
	cell_spacing_m: Vector2
) -> Dictionary:
	if record_id.is_empty() or cell_index < 0:
		return {}
	if source_descriptor_hash.length() != 64:
		return {}
	if not _finite_positive(cell_spacing_m.x) or not _finite_positive(cell_spacing_m.y):
		return {}

	var fractions: Vector2 = stable_cell_fraction(record_id)
	var offset_m := Vector2(
		fractions.x * cell_spacing_m.x,
		fractions.y * cell_spacing_m.y
	)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"presentation_only": PRESENTATION_ONLY,
		"canonical_position": CANONICAL_POSITION,
		"ecology_authority": ECOLOGY_AUTHORITY,
		"network_authority": NETWORK_AUTHORITY,
		"persistence_authority": PERSISTENCE_AUTHORITY,
		"record_id": record_id,
		"cell_index": cell_index,
		"source_descriptor_hash": source_descriptor_hash,
		"cell_spacing_x_m": cell_spacing_m.x,
		"cell_spacing_y_m": cell_spacing_m.y,
		"jitter_x_cell": fractions.x,
		"jitter_y_cell": fractions.y,
		"offset_x_m": offset_m.x,
		"offset_y_m": offset_m.y,
	}
	result["appearance_hash"] = compute_hash(result)
	return result if validate(result) else {}


static func stable_cell_fraction(record_id: String) -> Vector2:
	if record_id.is_empty():
		return Vector2.ZERO
	# Exact VIS2 semantic:
	# token = record_id.sha256_text()
	# ux/uy = first two 24-bit chunks / 16777215
	# x = (ux - 0.5) * 0.48 cell
	# y = (uy - 0.5) * 0.30 cell
	var token := record_id.sha256_text()
	var ux := float(token.substr(0, 6).hex_to_int()) / 16777215.0
	var uy := float(token.substr(6, 6).hex_to_int()) / 16777215.0
	return Vector2(
		(ux - 0.5) * X_SPAN_CELL,
		(uy - 0.5) * Y_SPAN_CELL
	)


static func validate(value: Dictionary) -> bool:
	if String(value.get("schema", "")) != SCHEMA:
		return false
	if String(value.get("version", "")) != VERSION or String(value.get("revision", "")) != REVISION:
		return false
	if not bool(value.get("presentation_only", false)):
		return false
	if bool(value.get("canonical_position", true)):
		return false
	if bool(value.get("ecology_authority", true)):
		return false
	if bool(value.get("network_authority", true)) or bool(value.get("persistence_authority", true)):
		return false
	if String(value.get("record_id", "")).is_empty() or int(value.get("cell_index", -1)) < 0:
		return false
	if String(value.get("source_descriptor_hash", "")).length() != 64:
		return false
	var spacing := Vector2(
		float(value.get("cell_spacing_x_m", NAN)),
		float(value.get("cell_spacing_y_m", NAN))
	)
	if not _finite_positive(spacing.x) or not _finite_positive(spacing.y):
		return false
	var jitter := Vector2(
		float(value.get("jitter_x_cell", NAN)),
		float(value.get("jitter_y_cell", NAN))
	)
	if not _finite(jitter.x) or not _finite(jitter.y):
		return false
	if absf(jitter.x) > X_HALF_EXTENT_CELL + 0.000000001:
		return false
	if absf(jitter.y) > Y_HALF_EXTENT_CELL + 0.000000001:
		return false
	if not is_equal_approx(float(value.get("offset_x_m", NAN)), jitter.x * spacing.x):
		return false
	if not is_equal_approx(float(value.get("offset_y_m", NAN)), jitter.y * spacing.y):
		return false
	return String(value.get("appearance_hash", "")) == compute_hash(value)


static func compute_hash(value: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		String(value.get("record_id", "")),
		str(int(value.get("cell_index", -1))),
		String(value.get("source_descriptor_hash", "")),
		"%.9f" % float(value.get("cell_spacing_x_m", 0.0)),
		"%.9f" % float(value.get("cell_spacing_y_m", 0.0)),
		"%.9f" % float(value.get("jitter_x_cell", 0.0)),
		"%.9f" % float(value.get("jitter_y_cell", 0.0)),
		"%.9f" % float(value.get("offset_x_m", 0.0)),
		"%.9f" % float(value.get("offset_y_m", 0.0)),
	])).sha256_text()


static func _finite_positive(value: float) -> bool:
	return is_finite(value) and value > 0.0


static func _finite(value: float) -> bool:
	return is_finite(value)
