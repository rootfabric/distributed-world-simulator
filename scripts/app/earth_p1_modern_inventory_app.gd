extends "res://scripts/app/earth_p1_app.gd"

const ModernM5NetworkedInventoryShellScript = preload(
	"res://scripts/ui/inventory/networked/m5_modern_networked_inventory_shell.gd"
)


func _ensure_mvp_inventory_shell(runtime) -> Dictionary:
	if _mvp_inventory_shell != null and is_instance_valid(_mvp_inventory_shell):
		return {"success": true, "error_code": "", "details": {"reused": true}}
	if runtime == null or not runtime.has_method("get_local_player_id"):
		_mvp_inventory_setup_error = "V0_I1_NETWORK_RUNTIME_REQUIRED"
		return {
			"success": false,
			"error_code": _mvp_inventory_setup_error,
			"details": {},
		}

	_mvp_inventory_shell = ModernM5NetworkedInventoryShellScript.new()
	_mvp_inventory_shell.name = "V0ModernNetworkedInventory"
	add_child(_mvp_inventory_shell)
	var setup_result: Dictionary = _mvp_inventory_shell.setup(
		runtime,
		String(runtime.get_local_player_id())
	)
	if not bool(setup_result.get("success", false)):
		_mvp_inventory_setup_error = String(
			setup_result.get("error_code", "V0_I1_INVENTORY_SETUP_FAILED")
		)
		_mvp_inventory_shell.queue_free()
		_mvp_inventory_shell = null
		return setup_result

	_mvp_inventory_setup_error = ""
	_mvp_inventory_visible = false
	_mvp_inventory_shell.set_inventory_visible(false)
	return {
		"success": true,
		"error_code": "",
		"details": {
			"ui": "M5_MODERN_NETWORKED_INVENTORY_SCREEN",
			"bridge": "M5_INVENTORY_UI_BRIDGE",
			"canonical_truth": "SERVER_M4_ITEM_GRAPH",
		},
	}
