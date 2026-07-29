extends RefCounted

const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const EndpointScript = preload("res://scripts/network/contracts/network_endpoint.gd")

const CHECKPOINT := "v16.8.4-data-plane-b0-message-bus-contracts"
const BUILD_ID := "b0-transport-independent-message-bus-contracts"


static func parse_options(arguments: PackedStringArray, mode: String) -> Dictionary:
	var options: Dictionary = {
		"host": "127.0.0.1",
		"port": 0,
		"result_file": "",
		"timeout_ms": 15000,
		"client_id": "",
		"expected_clients": 2,
	}
	var errors: Array[String] = []
	for raw in arguments:
		var argument: String = String(raw).strip_edges()
		if not argument.begins_with("--") or not argument.contains("="):
			errors.append("Invalid process argument: %s" % argument)
			continue
		var separator: int = argument.find("=")
		var key: String = argument.substr(2, separator - 2)
		var value: String = argument.substr(separator + 1)
		match key:
			"host": options["host"] = value
			"port": options["port"] = _positive_int(value, key, errors)
			"result-file": options["result_file"] = value
			"timeout-ms": options["timeout_ms"] = _positive_int(value, key, errors)
			"client-id": options["client_id"] = value
			"expected-clients": options["expected_clients"] = _positive_int(value, key, errors)
			_: errors.append("Unknown process option: --%s" % key)
	if String(options["host"]).strip_edges().is_empty(): errors.append("host cannot be empty")
	if int(options["port"]) < 1 or int(options["port"]) > 65535: errors.append("port must be in range 1..65535")
	if String(options["result_file"]).strip_edges().is_empty(): errors.append("result-file cannot be empty")
	if mode == "client" and String(options["client_id"]) not in ["a", "b"]: errors.append("client-id must be a or b")
	return {"success": errors.is_empty(), "options": options, "errors": errors}


static func endpoint(options: Dictionary) -> Dictionary:
	return EndpointScript.create("ENET", String(options["host"]), int(options["port"]), "simulation", false)


static func write_json(path: String, value: Dictionary) -> bool:
	return bool(AtomicJsonScript.write_dictionary(path, value).get("success", false))


static func _positive_int(value: String, key: String, errors: Array[String]) -> int:
	if not value.is_valid_int() or value.to_int() < 1:
		errors.append("--%s must be a positive integer" % key)
		return 0
	return value.to_int()
