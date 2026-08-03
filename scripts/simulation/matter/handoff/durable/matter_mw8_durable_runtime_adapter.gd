extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const CALLBACK_NAMES: Array[String] = [
	"synchronize_lease",
	"freeze_handoff",
	"persist_handoff_package",
	"prepare_handoff_target",
	"commit_handoff",
	"abort_handoff",
]

var _callbacks: Dictionary = {}


func configure(callbacks: Dictionary) -> Dictionary:
	if callbacks.size() != CALLBACK_NAMES.size():
		return MatterUtils.failure("MATTER_MW8_DURABLE_ADAPTER_CALLBACK_SET_MISMATCH")
	var normalized: Dictionary = {}
	for callback_name in CALLBACK_NAMES:
		if not callbacks.has(callback_name) or typeof(callbacks[callback_name]) != TYPE_CALLABLE:
			return MatterUtils.failure("MATTER_MW8_DURABLE_ADAPTER_CALLBACK_REQUIRED", {"callback": callback_name})
		var callback: Callable = callbacks[callback_name]
		if not callback.is_valid():
			return MatterUtils.failure("MATTER_MW8_DURABLE_ADAPTER_CALLBACK_INVALID", {"callback": callback_name})
		normalized[callback_name] = callback
	_callbacks = normalized
	return MatterUtils.success()


func synchronize_lease(lease: Dictionary) -> Dictionary:
	return _invoke("synchronize_lease", lease)


func freeze_handoff(record: Dictionary) -> Dictionary:
	return _invoke("freeze_handoff", record)


func persist_handoff_package(record: Dictionary) -> Dictionary:
	return _invoke("persist_handoff_package", record)


func prepare_handoff_target(record: Dictionary) -> Dictionary:
	return _invoke("prepare_handoff_target", record)


func commit_handoff(record: Dictionary) -> Dictionary:
	return _invoke("commit_handoff", record)


func abort_handoff(record: Dictionary) -> Dictionary:
	return _invoke("abort_handoff", record)


func _invoke(callback_name: String, value: Dictionary) -> Dictionary:
	if not _callbacks.has(callback_name):
		return MatterUtils.failure("MATTER_MW8_DURABLE_ADAPTER_NOT_CONFIGURED")
	var result = Callable(_callbacks[callback_name]).call(value.duplicate(true))
	if typeof(result) != TYPE_DICTIONARY:
		return MatterUtils.failure("MATTER_MW8_DURABLE_ADAPTER_INVALID_RESULT", {"callback": callback_name})
	return result
