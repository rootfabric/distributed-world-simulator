extends SceneTree

const PlaybackScript = preload("res://scripts/labs/fabric_construct0/construct0_fabric_playback.gd")

var _assertions := 0
var _failures: Array[String] = []

func _init() -> void:
	var playback = PlaybackScript.new()
	var ready := playback.setup(1.0e-9)
	_check(bool(ready.get("success", false)), "canonical FABRIC trajectory prepares")
	if bool(ready.get("success", false)):
		_check(Array(ready["timeline_ids"]).size() == 5, "impact + four persistent-contact events")
		_check(Array(ready["timeline_times"]).size() == 5, "timeline time count")
		_check(String(ready["timeline_ids"][0]).contains("ACQUIRE_PERSISTENT_SUPPORT"), "impact acquisition first")
		_check(String(ready["timeline_ids"][1]).contains("STICK_TO_SLIDE"), "slide transition present")
		_check(String(ready["timeline_ids"][2]).contains("STICK_TO_ROLL"), "roll transition present")
		_check(String(ready["timeline_ids"][3]).contains("STICK_TO_SPIN"), "spin transition present")
		_check(String(ready["timeline_ids"][4]).contains("SUPPORT_TO_SEPARATION"), "separation transition present")

		var t0 := playback.sample(0.0)
		var t05 := playback.sample(0.05)
		_check(bool(t0.get("success", false)) and bool(t05.get("success", false)), "free-flight samples valid")
		if bool(t0.get("success", false)) and bool(t05.get("success", false)):
			var p0: Vector3 = t0["position"]
			var p05: Vector3 = t05["position"]
			_check(p05.y < p0.y, "FABRIC reference free-flight descends")
			_check(String(t0["phase"]) == "FREE", "pre-impact phase is FREE")

		var first_event_time := float(ready["timeline_times"][0])
		var impact := playback.sample(first_event_time)
		_check(bool(impact.get("success", false)), "impact sample valid")
		if bool(impact.get("success", false)):
			_check(String(impact["event_id"]).contains("ACQUIRE_PERSISTENT_SUPPORT"), "impact event visible")
			_check(String(impact["phase"]) == "PERSISTENT_CONTACT", "impact acquires persistent contact")

		var previous := -1.0
		for raw in ready["timeline_times"]:
			var current := float(raw)
			_check(current > previous, "timeline strictly causal")
			previous = current

		var stepped := 0.0
		for index in range(Array(ready["timeline_times"]).size()):
			stepped = playback.next_event_time(stepped)
			_check(absf(stepped - float(ready["timeline_times"][index])) <= 1.0e-9, "STEP EVENT reaches exact event %d" % index)
			stepped += 1.0e-8

		var final_sample := playback.sample(playback.get_final_time())
		_check(bool(final_sample.get("success", false)), "final sample valid")
		if bool(final_sample.get("success", false)):
			var fp: Vector3 = final_sample["position"]
			var fq: Quaternion = final_sample["orientation"]
			var fv: Vector3 = final_sample["linear_velocity"]
			var fw: Vector3 = final_sample["angular_velocity"]
			_check(_finite_vec3(fp), "final display position finite")
			_check(_finite_vec3(fv), "final linear velocity finite")
			_check(_finite_vec3(fw), "final angular velocity finite")
			_check(is_finite(fq.x) and is_finite(fq.y) and is_finite(fq.z) and is_finite(fq.w), "final orientation finite")
			_check(absf(fq.length() - 1.0) <= 1.0e-9, "final orientation normalized")

		var second = PlaybackScript.new()
		var second_ready := second.setup(1.0e-9)
		_check(bool(second_ready.get("success", false)), "repeat FABRIC trajectory prepares")
		if bool(second_ready.get("success", false)):
			_check(playback.get_signature() == second.get_signature(), "repeat exact trajectory signature deterministic")
			_check(playback.timeline_text() == second.timeline_text(), "repeat event timeline byte-stable")

	if _failures.is_empty():
		print("FABRIC CONSTRUCT0 C0.2 Acceptance: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	for failure in _failures:
		push_error("CONSTRUCT0 C0.2: %s" % failure)
	print("FABRIC CONSTRUCT0 C0.2 Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _assertions])
	quit(1)

func _finite_vec3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)
