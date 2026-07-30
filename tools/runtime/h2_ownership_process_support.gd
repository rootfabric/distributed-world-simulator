extends RefCounted
const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const Endpoint = preload("res://scripts/network/contracts/network_endpoint.gd")
const CHECKPOINT := "v16.9.2-runtime-h2-host-client-ownership"
const BUILD_ID := "h2-host-client-join-leave-ownership"
static func parse(arguments: PackedStringArray) -> Dictionary:
	var o := {"host":"127.0.0.1","port":0,"result_file":"","timeout_ms":20000}
	var errors: Array[String] = []
	for raw in arguments:
		var a := String(raw); var i := a.find("=")
		if not a.begins_with("--") or i < 3: errors.append("invalid argument: %s" % a); continue
		var k := a.substr(2,i-2); var v := a.substr(i+1)
		match k:
			"host": o.host=v
			"port": o.port=v.to_int() if v.is_valid_int() else 0
			"result-file": o.result_file=v
			"timeout-ms": o.timeout_ms=v.to_int() if v.is_valid_int() else 0
			_: errors.append("unknown option: %s" % k)
	if int(o.port)<1 or int(o.port)>65535: errors.append("invalid port")
	if String(o.result_file).is_empty(): errors.append("result file required")
	return {"success":errors.is_empty(),"options":o,"errors":errors}
static func endpoint(o: Dictionary, server := false) -> Dictionary: return Endpoint.create("ENET", "*" if server else String(o.host), int(o.port), "simulation", false)
static func write(path: String, value: Dictionary) -> bool: return bool(AtomicJson.write_dictionary(path,value).get("success",false))
