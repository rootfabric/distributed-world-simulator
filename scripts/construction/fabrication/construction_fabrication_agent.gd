extends RefCounted
var _process; var _queue; var _actor_capabilities: Array = []
func setup(process, queue_store, actor_capabilities: Array) -> Dictionary:
	if process == null or not process.has_method("reserve_job") or queue_store == null or not queue_store.has_method("list_jobs"): return _failure("CONSTRUCTION_FABRICATION_AGENT_DOMAIN_REQUIRED")
	_actor_capabilities = actor_capabilities.duplicate(); _actor_capabilities.sort()
	if not _actor_capabilities.has("OPERATE_FABRICATION_CELL"): return _failure("CONSTRUCTION_FABRICATION_AGENT_CAPABILITY_REQUIRED")
	_process = process; _queue = queue_store; return _success()
func execute_next(machine_profile: Dictionary) -> Dictionary:
	for job in _queue.list_jobs():
		if String(job["machine_construct_id"]) != String(machine_profile.get("construct_id", "")): continue
		match String(job["status"]):
			"QUEUED", "BLOCKED":
				var reserved: Dictionary = _process.reserve_job(String(job["job_id"]), machine_profile)
				if not bool(reserved.get("success", false)): return reserved
				job = _queue.get_job(String(job["job_id"]))
			"RESERVED", "PROCESSING": pass
			_: continue
		var remaining := int(job["work_required"]) - int(job["work_completed"])
		if remaining > 0:
			var advanced: Dictionary = _process.advance_job(String(job["job_id"]), machine_profile, remaining, "operation/fabrication-agent/%s/progress" % String(job["job_id"]).trim_prefix("fabrication-job/"))
			if not bool(advanced.get("success", false)): return advanced
		return _process.complete_job(String(job["job_id"]), machine_profile)
	return _success({"no_work": true})
func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
