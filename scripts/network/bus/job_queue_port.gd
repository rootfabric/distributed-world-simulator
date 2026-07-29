extends RefCounted

const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("JOB_QUEUE", "adapter/unconfigured-job", [])


func submit(_job: Dictionary) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)


func claim(_queue_id: String, _worker_id: String) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)


func acknowledge(_delivery_id: String, _worker_id: String) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)


func reject(_delivery_id: String, _worker_id: String, _retryable: bool) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)
