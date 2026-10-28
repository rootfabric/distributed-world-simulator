extends "res://tools/network/eg1_client_worker.gd"

# No success-path overrides or logging: preserve the original timing.
# Dump state only AFTER the original worker declares failure.
func _finish_failure(error_code: String, details: Dictionary) -> void:
	var observation: Dictionary = {
		"movement_sent": _movement_sent,
		"scenario_sent_up_to": _scenario_sent_up_to,
		"connected": _connected,
		"next_wire_sequence": _next_wire_sequence,
		"results": _results.size(),
	}
	if _boundary != null:
		observation["boundary"] = _boundary.get_snapshot()
		var port = _boundary._port
		if port != null and port._peer != null and port._peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			var packet_peer: ENetPacketPeer = port._peer.get_peer(1)
			if packet_peer != null:
				observation["throttle"] = packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)
				observation["throttle_counter"] = packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_COUNTER)
	print("EG1_FAILURE_ONLY_PROBE " + JSON.stringify(observation))
	super._finish_failure(error_code, details)
