extends RefCounted
const EntityDelta = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const SCHEMA := "planet_simulator.item_graph_delta.v1"
static func validate(value: Dictionary) -> Dictionary:
	var check := EntityDelta.validate(value)
	if not bool(check.get("success", false)): return Wire.failure(String(check.get("error_code", "INVALID_ITEM_GRAPH_DELTA")))
	if String(value.get("entity_type", "")) != "item_graph": return Wire.failure("INVALID_ITEM_GRAPH_DELTA")
	var changed: Dictionary = value.get("changed_fields", {})
	if not changed.has("domain_components") and not changed.has("domain_components.item_graph"): return Wire.failure("INVALID_ITEM_GRAPH_DELTA")
	if changed.has("domain_components") and (not changed.get("domain_components") is Dictionary or not changed.get("domain_components", {}).has("item_graph")): return Wire.failure("INVALID_ITEM_GRAPH_DELTA")
	return Wire.success()
