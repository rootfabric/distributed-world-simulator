extends "res://scripts/world/testing/playground_view_relative_runtime.gd"

# Composition-only switch for inventory rev6 fix6. The parent runtime still owns
# all M7/NX6 networking and slot-aware projection wiring. After that setup has
# completed, replace only the inventory presentation enhancer so graphical M7
# clients use the press-driven sort activation fix.

const InventoryRev6EnhancerFix6Script = preload(
	"res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix6.gd"
)


func _setup_m7_networked_item_gameplay(runtime) -> Dictionary:
	_cleanup_inventory_enhancer_overlay(_inventory_rev6_enhancer)
	var setup_result: Dictionary = super._setup_m7_networked_item_gameplay(runtime)
	if not bool(setup_result.get("success", false)):
		return setup_result

	# The parent creates fix5. Remove its screen-owned overlay buttons before
	# replacing the enhancer; otherwise freeing the enhancer alone would leave
	# orphan controls because those buttons are children of InventoryScreen.
	_cleanup_inventory_enhancer_overlay(_inventory_rev6_enhancer)
	if _inventory_rev6_enhancer != null and is_instance_valid(_inventory_rev6_enhancer):
		_inventory_rev6_enhancer.free()

	_inventory_rev6_enhancer = InventoryRev6EnhancerFix6Script.new()
	_inventory_rev6_enhancer.name = "InventoryNetworkRev6EnhancerFix6"
	add_child(_inventory_rev6_enhancer)
	var enhancer_setup: Dictionary = _inventory_rev6_enhancer.setup(
		item_gameplay,
		_m7_item_bridge
	)
	if not bool(enhancer_setup.get("success", false)):
		return enhancer_setup
	return setup_result


func _cleanup_inventory_enhancer_overlay(enhancer) -> void:
	if enhancer == null or not is_instance_valid(enhancer):
		return
	for property_name in ["player_sort_button", "external_sort_button"]:
		var button = enhancer.get(property_name)
		if button != null and is_instance_valid(button):
			button.free()
