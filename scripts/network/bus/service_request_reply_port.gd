extends RefCounted

const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("SERVICE_REQUEST_REPLY", "adapter/unconfigured-service", [])


func request(_request: Dictionary) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)
