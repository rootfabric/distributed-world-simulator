extends "res://scripts/world/testing/playground_view_relative_runtime_fix7.gd"

# Composition-only switch for inventory rev6 fix8. Fix7 keeps the optimistic
# final-layout presentation; fix8 replaces only the enhancer so sort activation
# also has a root `_input()` hit-test fallback.

const InventoryRev6EnhancerFix8Script = preload(
	"res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix8.gd"
)


func _setup_m7_networked_item_gameplay(runtime) -> Dictionary:
	var setup_result: Dictionary = super._setup_m7_networked_item_gameplay(runtime)
	if not bool(setup_result.get("success", false)):
		return setup_result

	_cleanup_inventory_enhancer_overlay(_inventory_rev6_enhancer)
	if _inventory_rev6_enhancer != null and is_instance_valid(_inventory_rev6_enhancer):
		_inventory_rev6_enhancer.free()

	_inventory_rev6_enhancer = InventoryRev6EnhancerFix8Script.new()
	_inventory_rev6_enhancer.name = "InventoryNetworkRev6EnhancerFix8"
	add_child(_inventory_rev6_enhancer)
	var enhancer_setup: Dictionary = _inventory_rev6_enhancer.setup(
		item_gameplay,
		_m7_item_bridge
	)
	if not bool(enhancer_setup.get("success", false)):
		return enhancer_setup
	return setup_result
