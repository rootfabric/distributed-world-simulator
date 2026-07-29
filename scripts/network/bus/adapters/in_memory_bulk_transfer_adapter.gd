extends RefCounted

const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const ResultScript = preload("res://scripts/network/bus/bus_operation_result.gd")
const DescriptorScript = preload("res://scripts/network/bus/semantic_port_descriptor.gd")
const BulkDescriptorScript = preload("res://scripts/network/bus/bulk_object_descriptor.gd")

var _adapter_id: String
var _max_total_bytes: int
var _total_bytes: int = 0
var _objects: Dictionary = {}


func _init(adapter_id: String = "adapter/in-memory-bulk", max_total_bytes: int = 8388608) -> void:
	_adapter_id = adapter_id
	_max_total_bytes = maxi(1, max_total_bytes)


func get_descriptor() -> Dictionary:
	return DescriptorScript.create("BULK_TRANSFER", _adapter_id, ["content_hash", "in_memory_object_store", "size_limit"])


func store(descriptor: Dictionary, content_base64: String) -> Dictionary:
	var descriptor_check: Dictionary = BulkDescriptorScript.validate(descriptor)
	if not bool(descriptor_check.get("success", false)):
		return ResultScript.failure("REJECTED", String(descriptor_check.get("error_code", "INVALID_BULK_DESCRIPTOR")), false)
	if typeof(content_base64) != TYPE_STRING:
		return ResultScript.failure("REJECTED", "INVALID_BULK_CONTENT", false)
	if not _is_canonical_base64(content_base64):
		return ResultScript.failure("REJECTED", "NON_CANONICAL_BASE64", false)
	var bytes: PackedByteArray = Marshalls.base64_to_raw(content_base64)
	if Marshalls.raw_to_base64(bytes) != content_base64:
		return ResultScript.failure("REJECTED", "NON_CANONICAL_BASE64", false)
	if bytes.size() != int(descriptor["size_bytes"]):
		return ResultScript.failure("REJECTED", "BULK_SIZE_MISMATCH", false)
	if BusUtilsScript.content_hash_from_bytes(bytes) != String(descriptor["content_hash"]):
		return ResultScript.failure("REJECTED", "BULK_HASH_MISMATCH", false)
	var object_id: String = String(descriptor["object_id"])
	if _objects.has(object_id):
		var existing: Dictionary = _objects[object_id]
		if existing.get("descriptor", {}) == descriptor and String(existing.get("content_base64", "")) == content_base64:
			return ResultScript.success("ACCEPTED", {"duplicate": true})
		return ResultScript.failure("REJECTED", "BULK_OBJECT_CONFLICT", false)
	if _total_bytes + bytes.size() > _max_total_bytes:
		return ResultScript.failure("BACKPRESSURE", "BULK_CAPACITY", true, {"total_bytes": _total_bytes, "requested_bytes": bytes.size()})
	_objects[object_id] = {
		"descriptor": descriptor.duplicate(true),
		"content_base64": content_base64,
		"content_hash": String(descriptor["content_hash"]),
	}
	_total_bytes += bytes.size()
	return ResultScript.success("ACCEPTED", {"duplicate": false, "total_bytes": _total_bytes})


func fetch(object_id: String) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(object_id, "object"):
		return ResultScript.failure("REJECTED", "INVALID_OBJECT_ID", false)
	if not _objects.has(object_id):
		return ResultScript.failure("NOT_FOUND", "BULK_OBJECT_NOT_FOUND", false)
	var value: Dictionary = _objects[object_id]
	return ResultScript.success("AVAILABLE", {
		"descriptor": value["descriptor"].duplicate(true),
		"content_base64": String(value["content_base64"]),
	})


func remove(object_id: String) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(object_id, "object"):
		return ResultScript.failure("REJECTED", "INVALID_OBJECT_ID", false)
	if not _objects.has(object_id):
		return ResultScript.failure("NOT_FOUND", "BULK_OBJECT_NOT_FOUND", false)
	var descriptor: Dictionary = _objects[object_id]["descriptor"]
	_total_bytes -= int(descriptor["size_bytes"])
	_objects.erase(object_id)
	return ResultScript.success("COMPLETED", {"total_bytes": _total_bytes})


func _is_canonical_base64(value: String) -> bool:
	if value.length() % 4 != 0:
		return false
	var padding_started: bool = false
	var padding_count: int = 0
	for character in value:
		if character == "=":
			padding_started = true
			padding_count += 1
			if padding_count > 2:
				return false
			continue
		if padding_started:
			return false
		if not ((character >= "A" and character <= "Z") \
			or (character >= "a" and character <= "z") \
			or (character >= "0" and character <= "9") \
			or character in ["+", "/"]):
			return false
	return true
