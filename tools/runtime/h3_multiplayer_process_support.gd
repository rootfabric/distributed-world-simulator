extends RefCounted

const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const Endpoint = preload("res://scripts/network/contracts/network_endpoint.gd")

const CHECKPOINT := "v16.9.3-runtime-h3-dedicated-multiplayer"
const BUILD_ID := "h3-dedicated-two-client-gameplay"
const MESSAGE_SCHEMA := "planet_simulator.h3.multiplayer_message.v1"


static func parse(arguments: PackedStringArray, require_client_id: bool = false) -> Dictionary:
	var options := {
		"host": "127.0.0.1",
		"port": 0,
		"result_file": "",
		"timeout_ms": 30000,
		"client_id": "",
	}
	var errors: Array[String] = []
	for raw in arguments:
		var argument := String(raw).strip_edges()
		var separator := argument.find("=")
		if not argument.begins_with("--") or separator < 3:
			errors.append("invalid argument: %s" % argument)
			continue
		var key := argument.substr(2, separator - 2)
		var value := argument.substr(separator + 1)
		match key:
			"host": options["host"] = value
			"port": options["port"] = value.to_int() if value.is_valid_int() else 0
			"result-file": options["result_file"] = value
			"timeout-ms": options["timeout_ms"] = value.to_int() if value.is_valid_int() else 0
			"client-id": options["client_id"] = value.strip_edges().to_lower()
			_: errors.append("unknown option: %s" % key)
	if int(options["port"]) < 1 or int(options["port"]) > 65535:
		errors.append("invalid port")
	if String(options["result_file"]).strip_edges().is_empty():
		errors.append("result file required")
	if int(options["timeout_ms"]) < 1000:
		errors.append("timeout too small")
	if require_client_id and String(options["client_id"]) not in ["a", "b"]:
		errors.append("client-id must be a or b")
	return {"success": errors.is_empty(), "options": options, "errors": errors}


static func endpoint(options: Dictionary, server: bool = false) -> Dictionary:
	return Endpoint.create(
		"ENET",
		"*" if server else String(options.get("host", "127.0.0.1")),
		int(options.get("port", 0)),
		"simulation",
		false
	)


static func write(path: String, value: Dictionary) -> bool:
	return bool(AtomicJson.write_dictionary(path, value).get("success", false))
