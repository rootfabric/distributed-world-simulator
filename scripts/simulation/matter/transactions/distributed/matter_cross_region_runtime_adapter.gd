extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const CALLBACK_NAMES: Array[String] = [
	"prepare_region",
	"commit_region",
	"rollback_region",
	"publish_invalidation",
]

var _callbacks: Dictionary = {}


func configure(callbacks: Dictionary) -> Dictionary:
	if callbacks.size() != CALLBACK_NAMES.size():
		return MatterUtils.failure("MATTER_CROSS_REGION_RUNTIME_CALLBACK_SET_MISMATCH")
	var normalized: Dictionary = {}
	for callback_name in CALLBACK_NAMES:
		if not callbacks.has(callback_name) or typeof(callbacks[callback_name]) != TYPE_CALLABLE:
			return MatterUtils.failure("MATTER_CROSS_REGION_RUNTIME_CALLBACK_REQUIRED", {"callback": callback_name})
		var callback: Callable = callbacks[callback_name]
		if not callback.is_valid():
			return MatterUtils.failure("MATTER_CROSS_REGION_RUNTIME_CALLBACK_INVALID", {"callback": callback_name})
		normalized[callback_name] = callback
	_callbacks = normalized
	return MatterUtils.success()


func prepare_region(participant: Dictionary, context: Dictionary) -> Dictionary:
	return _invoke("prepare_region", [participant, context])


func commit_region(participant: Dictionary, prepare_receipt: Dictionary, context: Dictionary) -> Dictionary:
	return _invoke("commit_region", [participant, prepare_receipt, context])


func rollback_region(participant: Dictionary, prepare_receipt: Dictionary, context: Dictionary) -> Dictionary:
	return _invoke("rollback_region", [participant, prepare_receipt, context])


func publish_invalidation(outbox_record: Dictionary) -> Dictionary:
	return _invoke("publish_invalidation", [outbox_record])


func _invoke(callback_name: String, arguments: Array) -> Dictionary:
	if not _callbacks.has(callback_name):
		return MatterUtils.failure("MATTER_CROSS_REGION_RUNTIME_ADAPTER_NOT_CONFIGURED")
	var copied_arguments: Array = []
	for argument in arguments:
		copied_arguments.append(argument.duplicate(true) if typeof(argument) in [TYPE_DICTIONARY, TYPE_ARRAY] else argument)
	var result = Callable(_callbacks[callback_name]).callv(copied_arguments)
	if typeof(result) != TYPE_DICTIONARY:
		return MatterUtils.failure("MATTER_CROSS_REGION_RUNTIME_INVALID_RESULT", {"callback": callback_name})
	return result
