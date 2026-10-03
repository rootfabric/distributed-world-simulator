extends RefCounted
## ECO ARCH2 A13 deterministic exact workset plan.
## A workset is an execution partition ONLY. It owns no biology, no field
## resources and no authority. All A5 resource demands are still globally
## allocated before any individual state transition is committed.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Scale = preload("res://scripts/research/ecology/v2/ecology_scale_contract_v1.gd")

const SCHEMA := "dws.ecology.population-workset-plan.v1"
const DEFAULT_WORKSET_SIZE := 64
const MAX_WORKSET_SIZE := Scale.MAX_POPULATION
const PLAN_KEYS := ["schema", "workset_size", "population_hash", "member_count", "worksets"]
const WORKSET_KEYS := ["index", "member_ids"]

static func create(population: Array, workset_size: int = DEFAULT_WORKSET_SIZE) -> Dictionary:
	if workset_size < 1 or workset_size > MAX_WORKSET_SIZE:
		return {}
	var ids := _member_ids(population)
	if ids.is_empty() and not population.is_empty():
		return {}
	if ids.size() != population.size():
		return {}
	var worksets: Array = []
	var index := 0
	while index < ids.size():
		var members: Array = []
		var stop := mini(ids.size(), index + workset_size)
		for i in range(index, stop):
			members.append(ids[i])
		worksets.append({"index": worksets.size(), "member_ids": members})
		index = stop
	var plan := {
		"schema": SCHEMA,
		"workset_size": workset_size,
		"population_hash": C.digest(ids),
		"member_count": ids.size(),
		"worksets": worksets,
	}
	return plan if validate(plan, population).is_empty() else {}

static func validate(plan: Variant, population: Array) -> String:
	if not C.keys(plan, PLAN_KEYS) or String(plan.schema) != SCHEMA:
		return "WORKSET_PLAN_SCHEMA"
	if not C.integer(plan.workset_size, 1, MAX_WORKSET_SIZE):
		return "WORKSET_PLAN_SIZE"
	var ids := _member_ids(population)
	if ids.size() != population.size():
		return "WORKSET_POPULATION"
	if not C.integer(plan.member_count, 0, Scale.MAX_POPULATION) or int(plan.member_count) != ids.size():
		return "WORKSET_MEMBER_COUNT"
	if String(plan.population_hash) != C.digest(ids):
		return "WORKSET_POPULATION_HASH"
	if not plan.worksets is Array:
		return "WORKSET_LIST"
	var flattened: Array = []
	for i in plan.worksets.size():
		var unit: Variant = plan.worksets[i]
		if not C.keys(unit, WORKSET_KEYS) or int(unit.index) != i:
			return "WORKSET_ENTRY"
		if not unit.member_ids is Array or unit.member_ids.is_empty() 				or unit.member_ids.size() > int(plan.workset_size):
			return "WORKSET_MEMBERS"
		for raw_id in unit.member_ids:
			if not C.identifier(raw_id):
				return "WORKSET_MEMBER_ID"
			flattened.append(String(raw_id))
	if flattened != ids:
		return "WORKSET_COVERAGE_ORDER"
	var expected_count := 0 if ids.is_empty() else int((ids.size() + int(plan.workset_size) - 1) / int(plan.workset_size))
	if plan.worksets.size() != expected_count:
		return "WORKSET_COUNT"
	return "WORKSET_NONCANONICAL" if C.encode(plan).is_empty() else ""

static func member_ids(plan: Dictionary) -> Array:
	var out: Array = []
	for unit in plan.get("worksets", []):
		for raw_id in unit.get("member_ids", []):
			out.append(String(raw_id))
	return out

static func _member_ids(population: Array) -> Array:
	var ids: Array = []
	var seen := {}
	for entry in population:
		if not entry is Dictionary or not entry.get("state") is Dictionary:
			return []
		var id: Variant = entry.state.get("individual_id", null)
		if not C.identifier(id) or seen.has(id):
			return []
		seen[id] = true
		ids.append(String(id))
	ids.sort()
	return ids
