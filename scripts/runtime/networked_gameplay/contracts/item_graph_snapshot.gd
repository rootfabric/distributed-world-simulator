extends RefCounted
const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const Wire = preload("res://scripts/runtime/networked_gameplay/contracts/wire_contract_utils.gd")
const SCHEMA := "planet_simulator.item_graph_snapshot.v1"
static func validate(value: Dictionary) -> Dictionary:
	var check := EntitySnapshot.validate(value)
	if not bool(check.get("success", false)): return Wire.failure(String(check.get("error_code", "INVALID_ITEM_GRAPH_SNAPSHOT")))
	if String(value.get("entity_type", "")) != "item_graph" or not value.get("domain_components", {}).has("item_graph"): return Wire.failure("INVALID_ITEM_GRAPH_SNAPSHOT")
	return Wire.success()
