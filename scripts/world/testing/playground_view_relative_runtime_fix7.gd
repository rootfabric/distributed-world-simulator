extends "res://scripts/world/testing/playground_view_relative_runtime_fix6.gd"

# Composition-only switch for inventory rev6 fix7. Fix6 already owns the robust
# press-driven button activation. Fix7 replaces only the inventory enhancer so
# sort gets an optimistic final-layout presentation while the existing
# authoritative serial item.transfer sequence commits in the background.

const InventoryRev6EnhancerFix7Script = preload(
	"res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix7.gd"
)


func _setup_m7_networked_item_gameplay(runtime) -> Dictionary:
	var setup_result: Dictionary = super._setup_m7_networked_item_gameplay(runtime)
	if not bool(setup_result.get("success", false)):
		return setup_result

	# The fix6 parent installs its enhancer. Remove its screen-owned buttons and
	# replace that presentation layer only; M7 adapter, prediction journal,
	# command bridge and authority paths remain untouched.
	_cleanup_inventory_enhancer_overlay(_inventory_rev6_enhancer)
	if _inventory_rev6_enhancer != null and is_instance_valid(_inventory_rev6_enhancer):
		_inventory_rev6_enhancer.free()

	_inventory_rev6_enhancer = InventoryRev6EnhancerFix7Script.new()
	_inventory_rev6_enhancer.name = "InventoryNetworkRev6EnhancerFix7"
	add_child(_inventory_rev6_enhancer)
	var enhancer_setup: Dictionary = _inventory_rev6_enhancer.setup(
		item_gameplay,
		_m7_item_bridge
	)
	if not bool(enhancer_setup.get("success", false)):
		return enhancer_setup
	return setup_result
