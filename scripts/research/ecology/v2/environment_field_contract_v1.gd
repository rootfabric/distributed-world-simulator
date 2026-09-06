extends RefCounted
## A4 research-only environmental field contracts. Owner metadata is a future binding shape,
## not production region/Matter authority.
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

static func stock(amount: int = 0) -> Dictionary:
	return {"water_mg": amount, "nutrient_mg": amount, "organic_mg": amount}

static func signals(light: int = 700, temperature: int = 500, competition: int = 0, mechanical: int = 0) -> Dictionary:
	return {"light": light, "temperature": temperature, "competition": competition, "mechanical": mechanical}

static func valid_stock(value: Variant, allow_zero_capacity: bool = true) -> bool:
	if not C.keys(value, RESOURCES):
		return false
	for name in RESOURCES:
		var low := 0 if allow_zero_capacity else 1
		if not C.integer(value[name], low, MAX_CELL_STOCK):
			return false
	return true

static func valid_signals(value: Variant) -> bool:
	if not C.keys(value, SIGNALS):
		return false
	for name in SIGNALS:
		if not C.integer(value[name], 0, 1000):
			return false
	return true

static func valid_cell(value: Variant, index: int, width: int) -> bool:
	if not C.keys(value, ["id", "x", "z", "stocks", "capacities", "signals"]):
		return false
	if value.id != "c%04d" % index or value.x != index % width or value.z != int(index / width):
		return false
	if not valid_stock(value.stocks) or not valid_stock(value.capacities, false) or not valid_signals(value.signals):
		return false
	for name in RESOURCES:
		if value.stocks[name] > value.capacities[name]:
			return false
	return true

static func valid_ledger(value: Variant) -> bool:
	if not C.keys(value, ["initial", "inputs", "outputs", "sinks"]):
		return false
	for name in ["initial", "inputs", "outputs", "sinks"]:
		if not valid_total_stock(value[name]):
			return false
	return true

static func valid_total_stock(value: Variant) -> bool:
	if not C.keys(value, RESOURCES):
		return false
	for name in RESOURCES:
		if not C.integer(value[name], 0, C.MAX_INT):
			return false
	return true

static func totals(cells: Array) -> Dictionary:
	var out := stock()
	for cell in cells:
		for name in RESOURCES:
			out[name] += cell.stocks[name]
	return out

static func validate_state(value: Variant) -> String:
	if not C.keys(value, ["schema", "owner_token", "owner_epoch", "revision", "tick", "origin_mm", "cell_size_mm", "width", "depth", "cells", "ledger", "operation_count"]):
		return "FIELD_SCHEMA"
	if value.schema != FIELD_SCHEMA or not C.identifier(value.owner_token):
		return "FIELD_IDENTITY"
	if not C.integer(value.owner_epoch, 0, MAX_OWNER_EPOCH) or not C.integer(value.revision, 0, MAX_REVISION) or not C.integer(value.tick, 0, MAX_TICK):
		return "FIELD_VERSION"
	if not C.vector(value.origin_mm, 10000000) or not C.integer(value.cell_size_mm, 1, 1000000):
		return "FIELD_SPATIAL"
	if not C.integer(value.width, 1, 64) or not C.integer(value.depth, 1, 64) or value.width * value.depth > MAX_CELLS:
		return "FIELD_DIMENSIONS"
	if not value.cells is Array or value.cells.size() != value.width * value.depth:
		return "FIELD_CELLS"
	for i in value.cells.size():
		if not valid_cell(value.cells[i], i, value.width):
			return "FIELD_CELL_%d" % i
	if not valid_ledger(value.ledger) or not C.integer(value.operation_count, 0, C.MAX_INT):
		return "FIELD_LEDGER"
	var current := totals(value.cells)
	for name in RESOURCES:
		var expected: int = value.ledger.initial[name] + value.ledger.inputs[name] - value.ledger.outputs[name] - value.ledger.sinks[name]
		if expected < 0 or current[name] != expected:
			return "FIELD_CONSERVATION_%s" % name
	return ""

static func validate_supports(supports: Variant) -> bool:
	if not supports is Array or supports.size() > 64:
		return false
	var seen := {}
	for support in supports:
		if not C.keys(support, ["id", "kind", "position_mm"]) or not C.identifier(support.id) or seen.has(support.id):
			return false
		if not support.kind in ["plane_y", "axis_y", "point"] or not C.vector(support.position_mm, 10000000):
			return false
		seen[support.id] = true
	return true

static func validate_sample(value: Variant) -> String:
	if not C.keys(value, ["schema", "channels", "resources", "capacities", "supports", "source"]):
		return "FIELD_SAMPLE_SCHEMA"
	if value.schema != SAMPLE_SCHEMA or not C.keys(value.channels, DEVELOPMENT_CHANNELS):
		return "FIELD_SAMPLE_CHANNELS"
	for name in DEVELOPMENT_CHANNELS:
		if not C.integer(value.channels[name], 0, 1000):
			return "FIELD_SAMPLE_CHANNEL"
	if not valid_total_stock(value.resources) or not valid_total_stock(value.capacities) or not validate_supports(value.supports):
		return "FIELD_SAMPLE_PAYLOAD"
	if not C.keys(value.source, ["owner_token", "owner_epoch", "revision", "tick", "field_hash", "cells"]):
		return "FIELD_SAMPLE_SOURCE"
	if not C.identifier(value.source.owner_token) or not C.integer(value.source.owner_epoch, 0, MAX_OWNER_EPOCH) or not C.integer(value.source.revision, 0, MAX_REVISION) or not C.integer(value.source.tick, 0, MAX_TICK):
		return "FIELD_SAMPLE_VERSION"
	if not value.source.field_hash is String or value.source.field_hash.length() != 64 or not value.source.cells is Array or value.source.cells.is_empty() or value.source.cells.size() > MAX_CELLS:
		return "FIELD_SAMPLE_PROVENANCE"
	var prior := ""
	for id in value.source.cells:
		if not C.identifier(id) or (not prior.is_empty() and id <= prior):
			return "FIELD_SAMPLE_CELL_ORDER"
		prior = id
	return ""

static func serialize(state: Dictionary) -> String:
	return C.encode(state) if validate_state(state).is_empty() else ""

static func deserialize(text: String) -> Dictionary:
	var decoded := C.decode(text)
	if not decoded.success or not decoded.value is Dictionary:
		return {}
	return decoded.value if validate_state(decoded.value).is_empty() else {}
