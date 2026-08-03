extends SceneTree

const F = preload("res://tests/construction/fixtures/c22_compiled_proxy_fixture.gd")
const Controller = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")
const Interest = preload("res://scripts/construction/proxies/construction_proxy_interest_request.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var request := F.compile_request()
	var controller = Controller.new(); get_root().add_child(controller)
	var start := Time.get_ticks_msec(); var compiled: Dictionary = controller.compile_construct(request); var compile_ms := Time.get_ticks_msec() - start; _ok(compiled, "large compile")
	var far_checksum := ""; var near_checksum := ""; var total_payloads := 0; var total_exact_parts := 0
	for tick in range(64):
		var interest: Dictionary
		if tick % 4 == 0: interest = F.far_interest(request)
		elif tick % 4 == 1: interest = F.section_interest(request)
		elif tick % 4 == 2: interest = F.local_interest(request)
		else: interest = F.interior_interest(request)
		interest["observer_id"] = "observer/c22/soak-%03d" % (tick % 32); interest["checksum"] = Interest.compute_checksum(interest)
		var packet: Dictionary = controller.make_packet(interest); _ok(packet, "soak packet %d" % tick)
		total_payloads += Array(packet["packet"]["artifact_payloads"]).size(); total_exact_parts += Array(packet["packet"]["interactive_part_descriptors"]).size()
		if tick == 0: far_checksum = String(packet["packet"]["artifact_payloads"][0]["content_hash"])
		if tick == 2: near_checksum = Utils.payload_hash(packet["plan"]["artifact_ids"])
		if tick == 32: _assert(String(packet["packet"]["artifact_payloads"][0]["content_hash"]) == far_checksum, "far content deterministic")
		if tick == 34: _assert(Utils.payload_hash(packet["plan"]["artifact_ids"]) == near_checksum, "near selection deterministic")
	_assert(int(compiled["manifest"]["total_part_count"]) == 10000, "scale item part count")
	_assert(int(compiled["manifest"]["total_section_count"]) == 80, "scale sections")
	_assert(int(compiled["stats"]["exposed_face_count"]) == 3400, "scale exposed faces")
	_assert(int(compiled["stats"]["shell_quad_count"]) < 100, "scale greedy shell")
	_assert(total_payloads < 64 * 13, "bounded proxy payload count")
	_assert(total_exact_parts <= 64 * 16, "bounded exact part streaming")
	_assert(controller.get_cache().get_artifact_count() == 83, "cache stable through soak")
	_assert(compile_ms < 30000, "compile completes under broad acceptance ceiling")
	print("C22 scale metrics: compile_ms=%d cache_bytes=%d payloads=%d exact_parts=%d" % [compile_ms, controller.get_cache().get_total_bytes(), total_payloads, total_exact_parts])
	_finish()

func _ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C22 compiled proxy scale/soak: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C22 compiled proxy scale/soak: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
