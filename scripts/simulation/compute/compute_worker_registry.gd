extends RefCounted

const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")
const WorkerScript = preload("res://scripts/simulation/compute/compute_worker_descriptor.gd")

var _workers: Dictionary = {}


func register_worker(descriptor: Dictionary) -> Dictionary:
	var check := WorkerScript.validate(descriptor)
	if not bool(check.get("success", false)):
		return check
	var worker_id: String = String(descriptor["worker_id"])
	if _workers.has(worker_id):
		if _workers[worker_id] == descriptor:
			return ComputeUtilsScript.success({"replay": true})
		return ComputeUtilsScript.failure("COMPUTE_WORKER_ID_CONFLICT")
	_workers[worker_id] = descriptor.duplicate(true)
	return ComputeUtilsScript.success({"replay": false})


func get_worker(worker_id: String) -> Dictionary:
	if not _workers.has(worker_id):
		return ComputeUtilsScript.failure("COMPUTE_WORKER_NOT_FOUND")
	return ComputeUtilsScript.success({"worker": Dictionary(_workers[worker_id]).duplicate(true)})
