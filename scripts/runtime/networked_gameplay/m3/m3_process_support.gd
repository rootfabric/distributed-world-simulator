extends RefCounted

const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const Endpoint = preload("res://scripts/network/contracts/network_endpoint.gd")

const CHECKPOINT := "v16.10.2-runtime-m3-dedicated-graphical-multiplayer"
const BUILD_ID := "m3-dedicated-two-graphical-clients"
const MESSAGE_SCHEMA := "planet_simulator.m3.graphical_multiplayer_message.v1"

static func endpoint(host: String, port: int, server_mode: bool = false) -> Dictionary:
	return Endpoint.create("ENET", "*" if server_mode else host, port, "simulation", false)

static func write(path: String, value: Dictionary) -> bool:
	if path.strip_edges().is_empty():
		return false
	return bool(AtomicJson.write_dictionary(path, value).get("success", false))
