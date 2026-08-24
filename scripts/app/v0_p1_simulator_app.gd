extends "res://scripts/app/simulator_app.gd"

# V0-P1 R4 product-composition repair.
#
# --network-mvp is an Earth product mode, not the historical playground mode,
# so LaunchOptions must continue validating those modes independently. The
# accepted M3 bootstrap, however, still uses the legacy _m7_mode flag as the
# capability switch that passes playable_sandbox=true to both dedicated server
# and graphical client runtimes. Normalize that internal capability only after
# launch-option validation has completed; explicit --network-mvp +
# --network-playground remains rejected by LaunchOptions.


func _parse_launch_options() -> Dictionary:
	var options: Dictionary = super._parse_launch_options()
	if launch_option_errors.is_empty() and bool(options.get("network_mvp", false)):
		options["network_playground"] = true
		options["v0_p1_playable_sandbox_bridge"] = true
	return options
