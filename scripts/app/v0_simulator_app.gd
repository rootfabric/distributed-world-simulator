extends "res://scripts/app/simulator_app.gd"

const ProductShellScript = preload("res://scripts/ui/product_shell.gd")

var _product_shell


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	if ProductShellScript.should_open_shell(user_args):
		name = "V0ProductShellHost"
		get_tree().auto_accept_quit = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_product_shell = ProductShellScript.new()
		add_child(_product_shell)
		_product_shell.setup()
		return
	super._ready()

# Generic V0 product composition bridge.
#
# --network-mvp remains a validated product mode distinct from the historical
# --network-playground acceptance mode. The inherited simulator composition
# still uses the legacy network_playground capability bit to select the playable
# M3/M4 sandbox. Normalize that internal capability only after launch-option
# validation succeeds; explicit mixed product/playground mode remains rejected
# by LaunchOptions before this hook runs.


func _parse_launch_options() -> Dictionary:
	var options: Dictionary = super._parse_launch_options()
	if launch_option_errors.is_empty() and bool(options.get("network_mvp", false)):
		options["network_playground"] = true
		options["v0_playable_sandbox_bridge"] = true
		# Keep the old diagnostic key during the bounded P2 bootstrap migration.
		options["v0_p1_playable_sandbox_bridge"] = true
	return options
