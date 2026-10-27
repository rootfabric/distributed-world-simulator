extends RefCounted

## Read-only B0 request/reply projection of N3 region routes. Registration,
## lease renewals, health and release are intentionally NOT bus operations:
## they require the trusted, single coordinator control-plane boundary.
## B0 adapters may cache responses by request_id. A cached route is never
## authority to mutate: consumers must revalidate its lease and generation.

const RequestScript = preload("res://scripts/network/bus/service_request_envelope.gd")
const ResponseScript = preload("res://scripts/network/bus/service_response_envelope.gd")
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SERVICE_ID := "service/n3/world-directory"
const REQUEST_SCHEMA := "planet_simulator.n3_region_route_request.v1"
const ROUTE_SCHEMA := "planet_simulator.n3_region_route_response.v1"
const OPERATION := "resolve_region"

var _directory = null
var _clock = null


func configure(directory, monotonic_clock) -> Dictionary:
	if directory == null or not directory.has_method("resolve_region") \
			or monotonic_clock == null or not monotonic_clock.has_method("now_msec"):
		return {"success": false, "error_code": "INVALID_DIRECTORY_DEPENDENCY"}
	_directory = directory
	_clock = monotonic_clock
	return {"success": true, "error_code": ""}


func handle_service_request(request: Dictionary) -> Dictionary:
	var request_id: String = str(request.get("request_id", ""))
	var response_id := "response/n3/" + request_id.sha256_text().substr(0, 32)
	var validated := RequestScript.validate(request)
	if not bool(validated.get("success", false)):
		return ResponseScript.create_failure(response_id, request_id, "INVALID_REQUEST")
	if _directory == null or _clock == null:
		return ResponseScript.create_failure(response_id, request_id, "DIRECTORY_NOT_CONFIGURED")
	if str(request.get("service_id", "")) != SERVICE_ID \
			or str(request.get("operation", "")) != OPERATION \
			or str(request.get("payload_schema", "")) != REQUEST_SCHEMA:
		return ResponseScript.create_failure(response_id, request_id, "UNSUPPORTED_DIRECTORY_OPERATION")
	var payload: Dictionary = request.get("payload", {})
	var required: Array[String] = ["world_id", "region_id"]
	var exact := NetworkUtilsScript.validate_exact_fields(payload, required)
	if not bool(exact.get("success", false)) \
			or typeof(payload.get("world_id")) != TYPE_STRING \
			or typeof(payload.get("region_id")) != TYPE_STRING:
		return ResponseScript.create_failure(response_id, request_id, "INVALID_ROUTE_QUERY")
	var now_value = _clock.now_msec()
	if typeof(now_value) != TYPE_INT:
		return ResponseScript.create_failure(response_id, request_id, "INVALID_TRUSTED_CLOCK")
	var result: Dictionary = _directory.resolve_region(
			str(payload["world_id"]), str(payload["region_id"]), int(now_value))
	if not bool(result.get("success", false)):
		return ResponseScript.create_failure(response_id, request_id,
				str(result.get("error_code", "DIRECTORY_RESOLUTION_FAILED")))
	return ResponseScript.create_success(response_id, request_id, ROUTE_SCHEMA,
			{"route": Dictionary(result.get("details", {})).get("route", {}).duplicate(true)})
