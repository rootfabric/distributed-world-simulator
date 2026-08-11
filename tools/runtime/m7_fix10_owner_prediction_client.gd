extends "res://tools/runtime/m7_fix10_long_prediction_client.gd"

const OwnerClientRuntime = preload(
	"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd"
)
const OwnerPlaygroundScene = preload("res://scenes/testing/playground.tscn")

# Reuses the complete FIX10 visual/long worker after startup, replacing only the
# network client runtime with the experimental owner-authoritative locomotion
# leaf. Diagnostic mode remains manual mouse/WASD input.


func _start() -> void:
	started_ms = Time.get_ticks_msec()
	if port < 1 or result_file.is_empty():
		_fail("INVALID_M7_WORKER_CONFIGURATION")
		return
	playground = OwnerPlaygroundScene.instantiate()
	playground.configure_runtime({
		"runtime_role": "game-client",
		"presentation_enabled": true,
		"local_input_enabled": true,
		"universe_id": "main",
		"instance_id": "m7-owner-process-%s" % client_id,
		"launch_options": {"network_playground": true},
		"world_definition": {
			"id": "playground",
			"options": {"spawn": [0.0, 1.2, 6.0]},
		},
	})
	root.add_child(playground)
	client = OwnerClientRuntime.new()
	root.add_child(client)
	client.session_ready.connect(_on_ready)
	client.connection_failed.connect(_on_failed)
	var setup: Dictionary = client.setup({
		"host": host,
		"port": port,
		"logical_player_id": client_id,
		"connect_timeout_ms": 30000,
		"command_timeout_ms": 10000,
		"automated_acceptance": true,
		"playable_sandbox": true,
		"network_condition_profile": network_profile,
	})
	_assert(bool(setup.get("success", false)), "owner client runtime configured")
	if not bool(setup.get("success", false)):
		_fail(String(setup.get("error_code", "M7_OWNER_CLIENT_SETUP_FAILED")))
