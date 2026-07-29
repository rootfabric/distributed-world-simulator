extends RefCounted

const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("BULK_TRANSFER", "adapter/unconfigured-bulk", [])


func store(_descriptor: Dictionary, _content_base64: String) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)


func fetch(_object_id: String) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)


func remove(_object_id: String) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)
