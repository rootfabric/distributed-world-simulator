extends RefCounted

const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("REPLICATION_TRANSPORT", "adapter/unconfigured-replication", [])


func send(_message: Dictionary) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)


func poll(_target_peer_id: String, _max_count: int = 64) -> Dictionary:
	return ResultScript.failure("FAILED", "NOT_IMPLEMENTED", false)
