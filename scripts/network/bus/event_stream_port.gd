extends RefCounted

const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("EVENT_STREAM", "adapter/unconfigured-event", [])


func publish(_event: Dictionary) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)


func read(_stream_id: String, _after_sequence: int = 0, _max_count: int = 64) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)
