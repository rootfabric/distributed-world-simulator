extends "res://scripts/runtime/networked_gameplay/p3/networked_gameplay_service_p3.gd"

const P5ResourceMiningService = preload(
	"res://scripts/runtime/networked_gameplay/p5/resource_mining_service_p5.gd"
)
const P5EarthResourceSpatialResolver = preload(
	"res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd"
)


func _setup_resource_domain() -> Dictionary:
	_resource_spatial_resolver = P5EarthResourceSpatialResolver.new()
	var resolver_setup: Dictionary = _resource_spatial_resolver.setup()
	if not bool(resolver_setup.get("success", false)):
		return _failure("RESOURCE_SPATIAL_RESOLVER_SETUP_FAILED", {"cause": resolver_setup})
	_resource_mining = P5ResourceMiningService.new()
	var resource_setup: Dictionary = _resource_mining.setup(
		_authority_owner_id,
		_authority_epoch,
		_canonical_multiplayer_items,
		_resource_spatial_resolver
	)
	if not bool(resource_setup.get("success", false)):
		return _failure("RESOURCE_MINING_SETUP_FAILED", {"cause": resource_setup})
	return _success()


func get_canonical_item_graph_port():
	return _canonical_multiplayer_items


func get_resource_mining_port():
	return _resource_mining


func get_p5_composition_report() -> Dictionary:
	return {
		"item_graph": create_canonical_item_graph_snapshot(),
		"resource_mining": create_resource_mining_snapshot(),
		"equipment_required_for_mining": true,
		"required_tool_definition_id": "item/tool/mining",
		"required_equipment_slot": "tool/main",
	}
