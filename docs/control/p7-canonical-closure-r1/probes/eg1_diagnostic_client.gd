extends "res://tools/network/eg1_client_worker.gd"

# Read-only observation of the unchanged worker and transport; never acceptance.
var _probe_frames: int = 0

func _probe(label: String) -> void:
	if _boundary == null:
		return
	var snapshot: Dictionary = _boundary.get_snapshot()
	var port = _boundary._port
	if port != null and port._peer != null and port._peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		var packet_peer: ENetPacketPeer = port._peer.get_peer(1)
		if packet_peer != null:
			snapshot["throttle"] = packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)
			snapshot["throttle_counter"] = packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_COUNTER)
	print("EG1_READ_ONLY_PROBE " + JSON.stringify({"label": label, "movement_sent": _movement_sent, "results": _results.size(), "boundary": snapshot}))

func _send_movement() -> void:
	_probe("before_movement")
	super._send_movement()
	_probe("movement_queued")

func _process(delta: float) -> bool:
	var result: bool = super._process(delta)
	if _movement_sent and not _finished and _probe_frames < 5:
		_probe("after_process_%d" % _probe_frames)
		_probe_frames += 1
	return result

func _handle_event(event: Dictionary) -> void:
	if String(event.get("event_type", "")) in ["TRANSPORT_ERROR", "PEER_DISCONNECTED"]:
		print("EG1_READ_ONLY_EVENT " + JSON.stringify(event))
	super._handle_event(event)

func _finish_failure(error_code: String, details: Dictionary) -> void:
	_probe("failure")
	super._finish_failure(error_code, details)
