extends RefCounted

const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const Endpoint = preload("res://scripts/network/contracts/network_endpoint.gd")

const CHECKPOINT: String = "v16.10.1-runtime-m2-dedicated-graphical-client"
const BUILD_ID: String = "m2-dedicated-graphical-client"
const MESSAGE_SCHEMA: String = "planet_simulator.m2.gameplay_message.v1"


static func endpoint(host: String, port: int, server: bool = false) -> Dictionary:
	return Endpoint.create(
		"ENET",
		"*" if server else host,
		port,
		"simulation",
		false
	)


static func write(path: String, value: Dictionary) -> bool:
	if path.strip_edges().is_empty():
		return false
	return bool(AtomicJson.write_dictionary(path, value).get("success", false))
