extends RefCounted
## Typed organism ports. No direct Plant<->Soil/Water callbacks.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const SAMPLE_REQUEST_SCHEMA := "dws.ecology.environment-sample-request.v1"
const DEMAND_SCHEMA := "dws.ecology.environment-demand.v1"
const EFFECT_SCHEMA := "dws.ecology.environment-effect.v1"

static func sample_request(organism_id: String, position_mm: Array, extent_mm: int) -> Dictionary:
	return {"schema": SAMPLE_REQUEST_SCHEMA, "organism_id": organism_id, "position_mm": position_mm.duplicate(), "extent_mm": extent_mm}

static func demand(request_id: String, organism_id: String, resource: String, amount: int, position_mm: Array, extent_mm: int) -> Dictionary:
	return {"schema": DEMAND_SCHEMA, "request_id": request_id, "organism_id": organism_id, "resource": resource, "amount": amount, "position_mm": position_mm.duplicate(), "extent_mm": extent_mm}

static func effect(effect_id: String, organism_id: String, mode: String, resource: String, amount: int, position_mm: Array, extent_mm: int, source_kind: String = "ORGANISM_OUTPUT") -> Dictionary:
	return {"schema": EFFECT_SCHEMA, "effect_id": effect_id, "organism_id": organism_id, "mode": mode, "resource": resource, "amount": amount, "position_mm": position_mm.duplicate(), "extent_mm": extent_mm, "source_kind": source_kind}

static func validate_sample_request(value: Variant) -> String:
	if not C.keys(value, ["schema", "organism_id", "position_mm", "extent_mm"]) or value.schema != SAMPLE_REQUEST_SCHEMA:
		return "SAMPLE_REQUEST_SCHEMA"
	if not C.identifier(value.organism_id) or not C.vector(value.position_mm, 10000000) or not C.integer(value.extent_mm, 0, 1000000):
		return "SAMPLE_REQUEST_VALUE"
	return ""

static func validate_demand(value: Variant) -> String:
	if not C.keys(value, ["schema", "request_id", "organism_id", "resource", "amount", "position_mm", "extent_mm"]) or value.schema != DEMAND_SCHEMA:
		return "DEMAND_SCHEMA"
	if not C.identifier(value.request_id) or not C.identifier(value.organism_id) or not value.resource in F.RESOURCES:
		return "DEMAND_ID_RESOURCE"
	if not C.integer(value.amount, 1, F.MAX_REQUEST) or not C.vector(value.position_mm, 10000000) or not C.integer(value.extent_mm, 0, 1000000):
		return "DEMAND_VALUE"
	return ""

static func validate_effect(value: Variant) -> String:
	if not C.keys(value, ["schema", "effect_id", "organism_id", "mode", "resource", "amount", "position_mm", "extent_mm", "source_kind"]) or value.schema != EFFECT_SCHEMA:
		return "EFFECT_SCHEMA"
	if not C.identifier(value.effect_id) or not C.identifier(value.organism_id) or not C.identifier(value.source_kind):
		return "EFFECT_ID"
	if not value.mode in ["deposit", "sink"] or not value.resource in F.RESOURCES:
		return "EFFECT_MODE_RESOURCE"
	if not C.integer(value.amount, 1, F.MAX_REQUEST) or not C.vector(value.position_mm, 10000000) or not C.integer(value.extent_mm, 0, 1000000):
		return "EFFECT_VALUE"
	return ""

static func sampling_extent_mm(phenotype: Dictionary) -> int:
	var modules: Variant = phenotype.get("representation", {}).get("modules", [])
	if not modules is Array:
		return 0
	var extent := 0
	for module in modules:
		if not module is Dictionary:
			continue
		for point_name in ["start_mm", "end_mm"]:
			var point: Variant = module.get(point_name, [])
			if point is Array and point.size() == 3:
				extent = maxi(extent, maxi(abs(int(point[0])), abs(int(point[2]))))
		extent = maxi(extent, int(module.get("reach_mm", 0)))
	return mini(extent, 1000000)
