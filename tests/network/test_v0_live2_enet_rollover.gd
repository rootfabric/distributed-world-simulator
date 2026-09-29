extends SceneTree

const ENetPort = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const LiveEarth = preload("res://scripts/app/earth_p3_resource_mining_app.gd")
const LiveClient = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const LiveInventory = preload("res://scripts/ui/inventory/networked/m5_v0_modern_inventory_shell_r5.gd")
const PACKET_TARGET := 131200
const CHANNEL_COUNT := 6
const TEST_CHANNEL := 1

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_run()
	_finish()


func _run() -> void:
	_test_live2_product_contracts()
	var mapping_probe = ENetPort.new()
	_assert(
		mapping_probe._transfer_mode("UNRELIABLE_SEQUENCED")
		== MultiplayerPeer.TRANSFER_MODE_UNRELIABLE,
		"LIVE2 realtime mapping must use raw ENet unreliable"
	)

	var port_number := _find_port()
	_assert(port_number > 0, "could not allocate UDP port")
	if port_number <= 0:
		return

	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	_assert(
		server.create_server(port_number, 4, CHANNEL_COUNT) == OK,
		"server failed to start"
	)
	_assert(
		client.create_client("127.0.0.1", port_number, CHANNEL_COUNT) == OK,
		"client failed to start"
	)
	if not failures.is_empty():
		server.close()
		client.close()
		return

	_assert(_wait_connected(server, client), "client did not connect")
	if client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		server.close()
		client.close()
		return

	client.transfer_channel = TEST_CHANNEL
	client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	client.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)

	var sent := 0
	var received := 0
	for sequence in range(1, PACKET_TARGET + 1):
		var packet := PackedByteArray()
		packet.resize(8)
		packet.encode_u32(0, sequence)
		packet.encode_u32(4, 0x4c495645)
		if client.put_packet(packet) != OK:
			failures.append("put_packet failed at %d" % sequence)
			break
		sent = sequence
		if sequence % 128 == 0:
			received += _pump(server, client, 4)

	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		received += _pump(server, client, 2)
		if received >= sent:
			break

	_assert(sent > 131072, "test did not cross second 16-bit sequence boundary")
	_assert(
		client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED,
		"client disconnected after raw-unreliable rollover workload"
	)
	_assert(
		server.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED,
		"server stopped after raw-unreliable rollover workload"
	)
	# Unreliable delivery may legitimately drop packets. The regression is
	# connection longevity and the absence of a physical ordered-sequence fence.
	_assert(received > 0, "server received no packets")
	print(
		"LIVE2 ENet rollover: sent=%d received=%d client_status=%d server_status=%d"
		% [
			sent,
			received,
			client.get_connection_status(),
			server.get_connection_status(),
		]
	)
	client.close()
	server.close()


func _test_live2_product_contracts() -> void:
	var earth = LiveEarth.new()
	_assert(earth.has_method("set_network_connection_status"), "Earth exposes connection status HUD seam")
	_assert(earth.has_method("show_network_error"), "Earth exposes network error HUD seam")
	_assert(earth.has_method("ensure_live2_mining_tool_equipped"), "Earth exposes canonical mining equip seam")
	_assert(earth.has_method("is_mvp_inventory_visible"), "Earth exposes inventory ownership state")
	root.add_child(earth)
	earth.queue_free()

	var runtime = LiveClient.new()
	_assert(runtime.has_signal("connection_state_changed"), "client emits product connection state")
	_assert(runtime.has_method("request_reconnect_now"), "client exposes bounded reconnect request")
	runtime.queue_free()

	var inventory = LiveInventory.new()
	_assert(inventory.has_method("build_next_stage_blocking"), "inventory exposes canonical Construction action")
	inventory.queue_free()


func _wait_connected(server: ENetMultiplayerPeer, client: ENetMultiplayerPeer) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		server.poll()
		client.poll()
		while server.get_available_packet_count() > 0:
			server.get_packet()
		if (
			client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
			and server.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		):
			return true
		OS.delay_msec(2)
	return false


func _pump(server: ENetMultiplayerPeer, client: ENetMultiplayerPeer, delay_msec: int) -> int:
	server.poll()
	client.poll()
	var received := 0
	while server.get_available_packet_count() > 0:
		server.get_packet()
		received += 1
	if delay_msec > 0:
		OS.delay_msec(delay_msec)
	return received


func _find_port() -> int:
	for port_number in range(31000 + OS.get_process_id() % 1000, 34000):
		var probe := PacketPeerUDP.new()
		if probe.bind(port_number, "127.0.0.1") == OK:
			probe.close()
			return port_number
	return 0


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-LIVE.2 ENet rollover: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-LIVE.2 ENet rollover: FAIL (%d failures, %d assertions)" % [
		failures.size(), assertions
	])
	quit(1)
