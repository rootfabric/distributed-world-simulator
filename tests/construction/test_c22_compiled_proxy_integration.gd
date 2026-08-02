extends SceneTree

const F = preload("res://tests/construction/fixtures/c22_compiled_proxy_fixture.gd")
const Controller = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")
const Plan = preload("res://scripts/construction/proxies/construction_proxy_stream_plan.gd")
const Packet = preload("res://scripts/construction/proxies/construction_proxy_network_packet.gd")
const Interest = preload("res://scripts/construction/proxies/construction_proxy_interest_request.gd")
const Persistence = preload("res://scripts/construction/proxies/construction_proxy_persistence.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions := 0
var failures: Array[String] = []
var controller
var request: Dictionary

func _init() -> void:
	request = F.compile_request()
	controller = Controller.new(); get_root().add_child(controller)
	_test_compile_large_construct()
	_test_far_and_near_network_streaming()
	_test_incremental_damage_rebuild()
	_test_persistence_and_reattach()
	_finish()

func _test_compile_large_construct() -> void:
	var result: Dictionary = controller.compile_construct(request); _ok(result, "compile ten thousand parts")
	var manifest: Dictionary = result["manifest"]
	_assert(int(manifest["total_part_count"]) == 10000, "ten thousand authoritative parts")
	_assert(int(manifest["total_section_count"]) == 80, "stable eighty-section topology")
	_assert(int(result["stats"]["raw_face_count"]) == 60000, "raw faces")
	_assert(int(result["stats"]["exposed_face_count"]) == 3400, "internal faces removed")
	_assert(int(result["stats"]["culled_face_count"]) == 56600, "culled internal faces")
	_assert(int(result["stats"]["shell_quad_count"]) < 100, "station shell greedily merged")
	_assert(controller.get_cache().get_artifact_count() == 83, "one shell, eighty sections, two interiors")
	_assert(int(manifest["estimated_cache_bytes"]) < 10000 * 256, "compiled proxies smaller than exact part DTO estimate")
	var generation: int = controller.get_generation()
	var replay: Dictionary = controller.compile_construct(request); _ok(replay, "exact compile replay")
	_assert(bool(replay["replay"]), "compile replay flagged")
	_assert(controller.get_generation() == generation, "compile replay does not mutate generation")

func _test_far_and_near_network_streaming() -> void:
	var far: Dictionary = controller.make_packet(F.far_interest(request)); _ok(far, "far packet")
	_assert(String(far["plan"]["detail_mode"]) == Plan.DISTANT_SHELL, "far shell mode")
	_assert(Array(far["packet"]["artifact_payloads"]).size() == 1, "far packet has one compiled shell")
	_assert(Array(far["packet"]["interactive_part_descriptors"]).is_empty(), "far packet excludes exact parts")
	_assert(int(far["packet"]["suppressed_part_count"]) == 10000, "far packet suppresses all child parts")
	_assert(not Utils.canonical_json(far["packet"]).contains("item/c22/block-"), "far network payload contains no child item identities")
	_ok(Packet.validate(far["packet"]), "far packet validates")
	var section: Dictionary = controller.make_packet(F.section_interest(request)); _ok(section, "section HLOD packet")
	_assert(String(section["plan"]["detail_mode"]) == Plan.SECTION_HLOD, "section mode")
	_assert(Array(section["packet"]["artifact_payloads"]).size() == 12, "section budget limits HLOD artifacts")
	_assert(Array(section["packet"]["interactive_part_descriptors"]).is_empty(), "section HLOD excludes exact parts")
	_assert(int(section["packet"]["suppressed_part_count"]) == 10000, "section mode suppresses exact parts")
	var local: Dictionary = controller.make_packet(F.local_interest(request)); _ok(local, "local exterior packet")
	_assert(String(local["plan"]["detail_mode"]) == Plan.LOCAL_EXTERIOR, "local mode")
	_assert(Array(local["packet"]["artifact_payloads"]).size() <= 8, "local section cap")
	_assert(Array(local["packet"]["interactive_part_descriptors"]).size() <= 16, "interactive local cap")
	_assert(int(local["packet"]["suppressed_part_count"]) >= 9984, "most parts remain suppressed nearby")
	var interior: Dictionary = controller.make_packet(F.interior_interest(request)); _ok(interior, "interior packet")
	_assert(String(interior["plan"]["detail_mode"]) == Plan.INTERIOR_CELL, "interior mode")
	_assert(Array(interior["packet"]["interactive_part_descriptors"]).size() == 8, "bridge interactive parts streamed")
	_assert(Array(interior["packet"]["artifact_payloads"]).size() <= 7, "interior plus bounded sections")
	_assert(int(interior["packet"]["suppressed_part_count"]) == 9992, "interior streams only eight exact parts")
	var tiny_budget := F.section_interest(request); tiny_budget["bandwidth_budget_bytes"] = 1; tiny_budget["checksum"] = Interest.compute_checksum(tiny_budget)
	_err(controller.make_packet(tiny_budget), "CONSTRUCTION_PROXY_BANDWIDTH_BUDGET_EXCEEDED", "bandwidth budget")

func _test_incremental_damage_rebuild() -> void:
	var dirty_part_id := "part/c22/block-000000"
	var damaged: Dictionary = F.damaged_request(request, dirty_part_id)
	var before_manifest: Dictionary = controller.get_manifest(F.CONSTRUCT_ID)
	var before_cache_count: int = controller.get_cache().get_artifact_count()
	var result: Dictionary = controller.recompile_incremental(damaged, [dirty_part_id]); _ok(result, "incremental damage compile")
	var plan: Dictionary = result["invalidation_plan"]
	_assert(Array(plan["dirty_section_ids"]).size() == 1, "one section dirtied")
	_assert(bool(plan["shell_rebuilt"]), "boundary damage rebuilds shell")
	_assert(Array(plan["invalidated_artifact_ids"]).size() == 2, "only shell and one section invalidated")
	_assert(Array(plan["reused_artifact_ids"]).size() == 79, "seventy-nine section artifacts reused")
	_assert(controller.get_cache().get_artifact_count() == before_cache_count + 2, "cache adds only changed shell and section")
	_assert(String(result["manifest"]["source_checksum"]) != String(before_manifest["source_checksum"]), "manifest source advances")
	request = damaged
	var far: Dictionary = controller.make_packet(F.far_interest(request)); _ok(far, "far packet after damage")
	_assert(int(far["packet"]["summary"]["part_count"]) == 10000, "destroyed part identity retained in authoritative item")

func _test_persistence_and_reattach() -> void:
	var storage = F.MemoryStore.new(); _ok(Persistence.save(storage, controller), "save proxy state")
	var restored = Controller.new(); get_root().add_child(restored); _ok(Persistence.load(storage, restored), "load proxy state")
	_assert(restored.get_cache().get_artifact_count() == controller.get_cache().get_artifact_count(), "cache restored")
	_assert(not restored.get_manifest(F.CONSTRUCT_ID).is_empty(), "manifest restored")
	var packet: Dictionary = restored.make_packet(F.far_interest(request)); _ok(packet, "far shell streams directly from persisted cache")
	_assert(Array(packet["packet"]["artifact_payloads"]).size() == 1, "restored far shell")
	_err(restored.make_packet(F.local_interest(request)), "CONSTRUCTION_PROXY_SOURCE_REATTACH_REQUIRED", "near exact detail requires source reattach")
	var corrupted: Dictionary = storage.values[Persistence.KEY].duplicate(true); corrupted["generation"] = int(corrupted["generation"]) + 1
	var broken = Controller.new(); get_root().add_child(broken); _err(broken.load_state(corrupted), "CONSTRUCTION_PROXY_CONTROLLER_STATE_CHECKSUM_MISMATCH", "corrupt state rejected")

func _ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _err(result: Dictionary, code: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C22 compiled proxy integration: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C22 compiled proxy integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
