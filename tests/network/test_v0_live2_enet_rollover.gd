extends SceneTree

const ENetPort = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const LiveEarth = preload("res://scripts/app/earth_p3_resource_mining_app.gd")
const LiveClient = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const LiveInventory = preload("res://scripts/ui/inventory/networked/m5_v0_modern_inventory_shell_r5.gd")

const LOGICAL_SEND_TARGET := 131200

class MockTelemetry:
	extends RefCounted
	var counters: Dictionary = {}
	func increment(name: String, amount: int = 1) -> void:
		counters[name] = int(counters.get(name, 0)) + amount

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_run()
	_finish()


func _run() -> void:
	_test_live2_product_contracts()
	_test_eg4_physical_mapping_preserved()
	_test_session_rotation_crosses_two_uint16_lifetimes()


func _test_eg4_physical_mapping_preserved() -> void:
	var mapping_probe = ENetPort.new()
	_assert(
		mapping_probe._transfer_mode("UNRELIABLE_SEQUENCED")
		== MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED,
		"LIVE2 must preserve EG4 UNRELIABLE_SEQUENCED -> ENet unreliable-ordered"
	)
	_assert(
		mapping_probe._transfer_mode("UNRELIABLE")
		== MultiplayerPeer.TRANSFER_MODE_UNRELIABLE,
		"plain UNRELIABLE mapping changed"
	)


func _test_session_rotation_crosses_two_uint16_lifetimes() -> void:
	var runtime = LiveClient.new()
	var telemetry = MockTelemetry.new()
	runtime._telemetry = telemetry
	runtime._configured = true
	runtime._joined = true

	var rotations := 0
	var maximum_session_count := 0
	for ordinal in range(1, LOGICAL_SEND_TARGET + 1):
		runtime._record_realtime_transport_send("INPUT", "UNRELIABLE_SEQUENCED")
		var count := int(runtime._transport_realtime_sent_by_channel.get("INPUT", 0))
		maximum_session_count = maxi(maximum_session_count, count)

		if runtime._transport_rotation_pending:
			# A blocking canonical command must delay, never suppress, rotation.
			if rotations == 0:
				runtime._awaited_command_ids["operation/live2/test"] = true
				_assert(
					not runtime._maybe_rotate_transport(),
					"rotation must wait for an in-flight blocking command"
				)
				runtime._awaited_command_ids.clear()

			_assert(
				runtime._maybe_rotate_transport(),
				"sequenced wrap guard did not schedule transport rotation"
			)
			rotations += 1
			_assert(
				runtime._reconnect_pending,
				"transport rotation did not enter reconnect state"
			)
			_assert(
				runtime._reconnect_next_ms <= Time.get_ticks_msec(),
				"proactive transport rotation incorrectly uses failure backoff"
			)

			# Model the successful fresh transport attempt. Production executes
			# this through _attempt_reconnect -> _start_transport_attempt; the
			# reset below verifies the exact per-session state contract without
			# requiring 131k physical packets in one ENet connection.
			runtime._reset_transport_protocol_state()
			runtime._reconnect_pending = false
			runtime._joined = true

	_assert(
		LOGICAL_SEND_TARGET > 131072,
		"test must cross two complete 16-bit physical sequence lifetimes"
	)
	_assert(
		rotations == 2,
		"131200 logical INPUT sends must rotate exactly twice at the 60000 guard"
	)
	_assert(
		maximum_session_count == LiveClient.LIVE2_ENET_SEQUENCED_ROTATION_LIMIT,
		"one transport session exceeded the configured sequenced rotation guard"
	)
	_assert(
		int(runtime._transport_realtime_sent_by_channel.get("INPUT", 0))
		== LOGICAL_SEND_TARGET - 2 * LiveClient.LIVE2_ENET_SEQUENCED_ROTATION_LIMIT,
		"post-rotation realtime counter did not restart per transport session"
	)
	_assert(
		int(runtime._transport_rotations) == 2,
		"rotation telemetry did not preserve cumulative transport rotations"
	)
	_assert(
		int(telemetry.counters.get("transport_rotation_guard_triggers", 0)) == 2,
		"rotation guard telemetry count mismatch"
	)
	_assert(
		int(telemetry.counters.get("transport_session_rotations", 0)) == 2,
		"transport rotation telemetry count mismatch"
	)
	print(
		"LIVE2 sequenced rotation: logical_sends=%d rotations=%d max_session=%d remaining=%d"
		% [
			LOGICAL_SEND_TARGET,
			rotations,
			maximum_session_count,
			int(runtime._transport_realtime_sent_by_channel.get("INPUT", 0)),
		]
	)
	runtime.free()


func _test_live2_product_contracts() -> void:
	var earth = LiveEarth.new()
	_assert(earth.has_method("set_network_connection_status"), "Earth exposes connection status HUD seam")
	_assert(earth.has_method("show_network_error"), "Earth exposes network error HUD seam")
	_assert(earth.has_method("ensure_live2_mining_tool_equipped"), "Earth exposes canonical mining equip seam")
	_assert(earth.has_method("is_mvp_inventory_visible"), "Earth exposes inventory ownership state")
	earth.free()

	var runtime = LiveClient.new()
	_assert(runtime.has_signal("connection_state_changed"), "client emits product connection state")
	_assert(runtime.has_method("request_reconnect_now"), "client exposes bounded reconnect request")
	_assert(runtime.has_method("_maybe_rotate_transport"), "client exposes internal transport rotation guard")
	runtime.free()

	var inventory = LiveInventory.new()
	_assert(inventory.has_method("build_next_stage_blocking"), "inventory exposes canonical Construction action")
	inventory.free()


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-LIVE.2 ENet rollover guard: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-LIVE.2 ENet rollover guard: FAIL (%d failures, %d assertions)" % [
		failures.size(), assertions
	])
	quit(1)
