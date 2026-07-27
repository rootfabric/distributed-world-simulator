extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ResultEnvelopeScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")

var gateway


func setup(gateway_reference) -> void:
	gateway = gateway_reference


func send(envelope: Dictionary) -> Dictionary:
	if gateway == null or not gateway.has_method("handle"):
		return {"success": false, "error_code": "NO_GATEWAY", "result": {}}
	var outbound: Dictionary = UtilsScript.json_round_trip(envelope)
	if not bool(outbound.get("success", false)):
		return {"success": false, "error_code": "SERIALIZATION_FAILED", "result": {}}
	var handled = gateway.call("handle", outbound.get("value", {}))
	if not handled is Dictionary:
		return {"success": false, "error_code": "INVALID_GATEWAY_RESULT", "result": {}}
	var preflight_validation: Dictionary = ResultEnvelopeScript.validate(handled)
	if not bool(preflight_validation.get("success", false)):
		return {
			"success": false,
			"error_code": "INVALID_GATEWAY_RESULT",
			"result": {},
			"validation_error_code": String(preflight_validation.get("error_code", "")),
		}
	var inbound: Dictionary = UtilsScript.json_round_trip(handled)
	if not bool(inbound.get("success", false)):
		return {"success": false, "error_code": "DESERIALIZATION_FAILED", "result": {}}
	var result: Dictionary = inbound.get("value", {})
	var validation: Dictionary = ResultEnvelopeScript.validate(result)
	return {
		"success": bool(validation.get("success", false)),
		"error_code": String(validation.get("error_code", "")),
		"result": result,
	}
