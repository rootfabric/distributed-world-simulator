extends RefCounted

const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")


static func mutation_chain(changed_address: Dictionary, region_root_address: Dictionary) -> Array:
	if not _contains_or_same(region_root_address, changed_address):
		return []
	var result: Array = []
	var current: Dictionary = changed_address.duplicate(true)
	while not current.is_empty():
		result.append(current)
		if current == region_root_address:
			return result
		current = CellAddress.parent(current)
	return []


static func handoff_cells(region_root_address: Dictionary, summaries: Array) -> Array:
	if not bool(CellAddress.validate(region_root_address).get("success", false)):
		return []
	var by_cell_id: Dictionary = {
		String(region_root_address["cell_id"]): region_root_address.duplicate(true),
	}
	for raw_summary in summaries:
		if typeof(raw_summary) != TYPE_DICTIONARY:
			return []
		var summary: Dictionary = raw_summary
		if not bool(SummaryNode.validate(summary).get("success", false)):
			return []
		var address: Dictionary = summary["cell_address"]
		if not _contains_or_same(region_root_address, address):
			continue
		var current: Dictionary = address.duplicate(true)
		while not current.is_empty():
			by_cell_id[String(current["cell_id"])] = current.duplicate(true)
			if current == region_root_address:
				break
			current = CellAddress.parent(current)
	var result: Array = by_cell_id.values()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var level_a: int = int(a["level"])
		var level_b: int = int(b["level"])
		if level_a != level_b:
			return level_a > level_b
		return String(a["cell_id"]) < String(b["cell_id"])
	)
	return result


static func sorted_scope_ids(body_id: String, addresses: Array) -> Array:
	var ids: Array = []
	for address in addresses:
		var scope_id: String = SummaryNode.scope_id_for(body_id, address)
		if scope_id.is_empty():
			return []
		ids.append(scope_id)
	ids.sort()
	var checked: Dictionary = RepresentationUtils.validate_sorted_unique_ids(ids, false)
	return ids if bool(checked.get("success", false)) else []


static func _contains_or_same(ancestor: Dictionary, descendant: Dictionary) -> bool:
	if not bool(CellAddress.validate(ancestor).get("success", false)) \
		or not bool(CellAddress.validate(descendant).get("success", false)):
		return false
	if ancestor == descendant:
		return true
	return CellAddress.is_ancestor(ancestor, descendant)
