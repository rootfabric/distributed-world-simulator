extends RefCounted
## A4 research-only field contract. Owner metadata is a future binding shape, not production authority.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const FIELD_SCHEMA := "dws.ecology.local-environment-field.v1"
const SAMPLE_SCHEMA := "dws.ecology.environment-sample.v2"
const RESOURCES := ["water_mg", "nutrient_mg", "organic_mg"]
const SIGNALS := ["light", "temperature", "competition", "mechanical"]
const DEVELOPMENT_CHANNELS := ["light", "water", "temperature", "competition", "mechanical"]
const MAX_CELLS := 4096
const MAX_CELL_STOCK := 1000000000
const MAX_BATCH := 4096
const MAX_REQUEST := 1000000
const MAX_REVISION := 1000000000
const MAX_OWNER_EPOCH := 1000000000
const MAX_TICK := 1000000000
const MAX_PORT_COORD_MM := 10000000

static func stock(amount: int = 0) -> Dictionary:
	return {"water_mg": amount, "nutrient_mg": amount, "organic_mg": amount}

static func signals(light: int = 700, temperature: int = 500, competition: int = 0, mechanical: int = 0) -> Dictionary:
	return {"light": light, "temperature": temperature, "competition": competition, "mechanical": mechanical}

static func valid_stock(v: Variant, allow_zero_capacity: bool = true) -> bool:
	if not C.keys(v, RESOURCES): return false
	for k in RESOURCES:
		if not C.integer(v[k], 0 if allow_zero_capacity else 1, MAX_CELL_STOCK): return false
	return true

static func valid_signals(v: Variant) -> bool:
	if not C.keys(v, SIGNALS): return false
	for k in SIGNALS:
		if not C.integer(v[k], 0, 1000): return false
	return true

static func valid_hash(v: Variant) -> bool:
	if not v is String or v.length() != 64: return false
	for c in v:
		if not c in "0123456789abcdef": return false
	return true

static func valid_footprint(origin_mm: Variant, cell_size_mm: Variant, width: Variant, depth: Variant) -> bool:
	if not C.vector(origin_mm, MAX_PORT_COORD_MM): return false
	if not C.integer(cell_size_mm, 1, 1000000) or not C.integer(width, 1, 64) or not C.integer(depth, 1, 64): return false
	var max_x: int = origin_mm[0] + cell_size_mm * width
	var max_z: int = origin_mm[2] + cell_size_mm * depth
	return origin_mm[0] >= -MAX_PORT_COORD_MM and origin_mm[2] >= -MAX_PORT_COORD_MM and max_x <= MAX_PORT_COORD_MM and max_z <= MAX_PORT_COORD_MM

static func cell_integrity_hash(cell: Dictionary) -> String:
	var p := cell.duplicate(true); p.erase("integrity_hash")
	return C.digest(p)

static func seal_cell(cell: Dictionary) -> Dictionary:
	var out := cell.duplicate(true); out.integrity_hash = cell_integrity_hash(out)
	return out

static func valid_cell(v: Variant, index: int, width: int) -> bool:
	if not C.keys(v, ["id", "x", "z", "stocks", "capacities", "signals", "integrity_hash"]): return false
	if v.id != "c%04d" % index or v.x != index % width or v.z != int(index / width): return false
	if not valid_stock(v.stocks) or not valid_stock(v.capacities, false) or not valid_signals(v.signals): return false
	for k in RESOURCES:
		if v.stocks[k] > v.capacities[k]: return false
	return valid_hash(v.integrity_hash) and v.integrity_hash == cell_integrity_hash(v)

static func valid_total_stock(v: Variant) -> bool:
	if not C.keys(v, RESOURCES): return false
	for k in RESOURCES:
		if not C.integer(v[k], 0, C.MAX_INT): return false
	return true

static func valid_ledger(v: Variant) -> bool:
	if not C.keys(v, ["initial", "inputs", "outputs", "sinks"]): return false
	for k in ["initial", "inputs", "outputs", "sinks"]:
		if not valid_total_stock(v[k]): return false
	return true

static func totals(cells: Array) -> Dictionary:
	var out := stock()
	for cell in cells:
		for k in RESOURCES: out[k] += cell.stocks[k]
	return out

static func state_integrity_hash(state: Dictionary) -> String:
	var p := state.duplicate(true); p.erase("integrity_hash")
	return C.digest(p)

static func seal_state(state: Dictionary) -> Dictionary:
	var out := state.duplicate(true); out.integrity_hash = state_integrity_hash(out)
	return out

static func validate_read_header(v: Variant) -> String:
	var keys := ["schema", "owner_token", "owner_epoch", "revision", "tick", "origin_mm", "cell_size_mm", "width", "depth", "cells", "ledger", "operation_count", "integrity_hash"]
	if not C.keys(v, keys): return "FIELD_SCHEMA"
	if v.schema != FIELD_SCHEMA or not C.identifier(v.owner_token): return "FIELD_IDENTITY"
	if not C.integer(v.owner_epoch, 0, MAX_OWNER_EPOCH) or not C.integer(v.revision, 0, MAX_REVISION) or not C.integer(v.tick, 0, MAX_TICK): return "FIELD_VERSION"
	if not C.vector(v.origin_mm, MAX_PORT_COORD_MM) or not C.integer(v.cell_size_mm, 1, 1000000): return "FIELD_SPATIAL"
	if not C.integer(v.width, 1, 64) or not C.integer(v.depth, 1, 64) or v.width * v.depth > MAX_CELLS: return "FIELD_DIMENSIONS"
	if not valid_footprint(v.origin_mm, v.cell_size_mm, v.width, v.depth): return "FIELD_FOOTPRINT"
	if not v.cells is Array or v.cells.size() != v.width * v.depth: return "FIELD_CELLS"
	if not valid_ledger(v.ledger) or not C.integer(v.operation_count, 0, C.MAX_INT) or not valid_hash(v.integrity_hash): return "FIELD_READ_SEAL"
	return ""

static func validate_state(v: Variant) -> String:
	var error := validate_read_header(v)
	if not error.is_empty(): return error
	for i in v.cells.size():
		if not valid_cell(v.cells[i], i, v.width): return "FIELD_CELL_%d" % i
	var current := totals(v.cells)
	for k in RESOURCES:
		var expected: int = v.ledger.initial[k] + v.ledger.inputs[k] - v.ledger.outputs[k] - v.ledger.sinks[k]
		if expected < 0 or current[k] != expected: return "FIELD_CONSERVATION_%s" % k
	return "" if v.integrity_hash == state_integrity_hash(v) else "FIELD_INTEGRITY_HASH"

static func validate_supports(v: Variant) -> bool:
	if not v is Array or v.size() > 64: return false
	var seen := {}
	for s in v:
		if not C.keys(s, ["id", "kind", "position_mm"]) or not C.identifier(s.id) or seen.has(s.id): return false
		if not s.kind in ["plane_y", "axis_y", "point"] or not C.vector(s.position_mm, MAX_PORT_COORD_MM): return false
		seen[s.id] = true
	return true

static func validate_sample(v: Variant) -> String:
	if not C.keys(v, ["schema", "channels", "resources", "capacities", "supports", "source"]): return "FIELD_SAMPLE_SCHEMA"
	if v.schema != SAMPLE_SCHEMA or not C.keys(v.channels, DEVELOPMENT_CHANNELS): return "FIELD_SAMPLE_CHANNELS"
	for k in DEVELOPMENT_CHANNELS:
		if not C.integer(v.channels[k], 0, 1000): return "FIELD_SAMPLE_CHANNEL"
	if not valid_total_stock(v.resources) or not valid_total_stock(v.capacities) or not validate_supports(v.supports): return "FIELD_SAMPLE_PAYLOAD"
	if not C.keys(v.source, ["owner_token", "owner_epoch", "revision", "tick", "field_hash", "cells"]): return "FIELD_SAMPLE_SOURCE"
	if not C.identifier(v.source.owner_token) or not C.integer(v.source.owner_epoch, 0, MAX_OWNER_EPOCH) or not C.integer(v.source.revision, 0, MAX_REVISION) or not C.integer(v.source.tick, 0, MAX_TICK): return "FIELD_SAMPLE_VERSION"
	if not valid_hash(v.source.field_hash) or not v.source.cells is Array or v.source.cells.is_empty() or v.source.cells.size() > MAX_CELLS: return "FIELD_SAMPLE_PROVENANCE"
	var prior := ""
	for id in v.source.cells:
		if not C.identifier(id) or (not prior.is_empty() and id <= prior): return "FIELD_SAMPLE_CELL_ORDER"
		prior = id
	return ""

static func serialize(state: Dictionary) -> String:
	return C.encode(state) if validate_state(state).is_empty() else ""

static func deserialize(text: String) -> Dictionary:
	var d := C.decode(text)
	if not d.success or not d.value is Dictionary: return {}
	return d.value if validate_state(d.value).is_empty() else {}
