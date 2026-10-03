extends "res://scripts/app/earth_p1_app.gd"

const ModernM5NetworkedInventoryShellScript = preload(
	"res://scripts/ui/inventory/networked/m5_v0_modern_inventory_shell_r5.gd"
)


func _ensure_mvp_inventory_shell(runtime) -> Dictionary:
	if _mvp_inventory_shell != null and is_instance_valid(_mvp_inventory_shell):
		_bind_mvp_inventory_visibility()
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
		_mvp_inventory_visible = false
		return setup_result

	_mvp_inventory_setup_error = ""
	_bind_mvp_inventory_visibility()
	_set_mvp_inventory_visible(false)
	return {
		"success": true,
		"error_code": "",
		"details": {
			"ui": "M5_MODERN_NETWORKED_INVENTORY_SCREEN_R5",
			"bridge": "M5_INVENTORY_UI_BRIDGE",
			"canonical_truth": "SERVER_M4_ITEM_GRAPH",
		},
	}


func _bind_mvp_inventory_visibility() -> void:
	# LIVE.2 R3: the shell owns visibility; the inherited app flag is only a
	# synchronous projection used by the existing input paths. Connect before
	# changing visibility, and re-read state when the shell is reused on JOIN.
	if _mvp_inventory_shell == null or not is_instance_valid(_mvp_inventory_shell):
		return
	if not _mvp_inventory_shell.inventory_visibility_changed.is_connected(
		_on_mvp_inventory_visibility_changed
	):
		_mvp_inventory_shell.inventory_visibility_changed.connect(
			_on_mvp_inventory_visibility_changed
		)
	_on_mvp_inventory_visibility_changed(_mvp_inventory_shell.is_inventory_visible())


func _set_mvp_inventory_visible(value: bool) -> void:
	if _mvp_inventory_shell == null or not is_instance_valid(_mvp_inventory_shell):
		return
	_bind_mvp_inventory_visibility()
	_mvp_inventory_shell.set_inventory_visible(value)
	# Idempotent set() need not emit a signal, but must still reconcile an
	# externally suspended input owner. Never early-return on the app cache.
	_on_mvp_inventory_visibility_changed(_mvp_inventory_shell.is_inventory_visible())


func is_mvp_inventory_visible() -> bool:
	return (
		_mvp_inventory_shell != null
		and is_instance_valid(_mvp_inventory_shell)
		and _mvp_inventory_shell.is_inventory_visible()
	)


func _on_mvp_inventory_visibility_changed(value: bool) -> void:
	var was_visible := _mvp_inventory_visible
	_mvp_inventory_visible = value
	if value and not was_visible:
		_submit_mvp_neutral_input()
	_sync_mvp_input_ownership()
	if _mvp_spectator_enabled and earth_explorer != null:
		earth_explorer.set_physics_process(local_input_enabled and not value)


func _sync_mvp_input_ownership() -> void:
	# Do not recapture the mouse from a console/system UI that suspended local
	# input. Closing inventory only releases inventory's own input claim.
	_mvp_inventory_visible = is_mvp_inventory_visible()
	if not local_input_enabled:
		_mvp_input_owner = "EXTERNAL_UI"
	else:
		_mvp_input_owner = (
			"INVENTORY" if _mvp_inventory_visible
			else ("SPECTATOR" if _mvp_spectator_enabled else "GAMEPLAY")
		)
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE
		if _mvp_input_owner in ["INVENTORY", "EXTERNAL_UI"]
		else Input.MOUSE_MODE_CAPTURED
	)
