extends SceneTree

const F = preload("res://tests/construction/fixtures/c22_compiled_proxy_fixture.gd")
const CompileRequest = preload("res://scripts/construction/proxies/construction_proxy_compile_request.gd")
const InteriorCell = preload("res://scripts/construction/proxies/construction_proxy_interior_cell.gd")
const Portal = preload("res://scripts/construction/proxies/construction_proxy_portal.gd")
const Topology = preload("res://scripts/construction/proxies/construction_proxy_section_topology.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")
const Manifest = preload("res://scripts/construction/proxies/construction_proxy_manifest.gd")
const Interest = preload("res://scripts/construction/proxies/construction_proxy_interest_request.gd")
const Plan = preload("res://scripts/construction/proxies/construction_proxy_stream_plan.gd")
const Packet = preload("res://scripts/construction/proxies/construction_proxy_network_packet.gd")
const Cache = preload("res://scripts/construction/proxies/construction_proxy_cache.gd")
const Compiler = preload("res://scripts/construction/proxies/construction_proxy_compiler.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var request := F.compile_request(5, 5, 5)
	_ok(CompileRequest.validate(request), "compile request")
	_assert(String(request["checksum"]).length() == 64, "request checksum")
	_assert(String(request["authority_mode"]) == CompileRequest.READ_ONLY, "read-only distributed compile")
	var bad_distance := request.duplicate(true); bad_distance["section_distance_m"] = 50.0; bad_distance["checksum"] = CompileRequest.compute_checksum(bad_distance); _err(CompileRequest.validate(bad_distance), "NON_MONOTONIC_CONSTRUCTION_PROXY_DISTANCE_POLICY", "distance order")
	var extra := request.duplicate(true); extra["extra"] = true; _err(CompileRequest.validate(extra), "UNEXPECTED_FIELD", "unknown field")
	for cell in request["interior_cells"]: _ok(InteriorCell.validate(cell), "interior cell")
	_ok(Portal.validate(request["portals"][0]), "portal")
	var bad_portal: Dictionary = request["portals"][0].duplicate(true); bad_portal["cell_b_id"] = bad_portal["cell_a_id"]; bad_portal["checksum"] = Portal.compute_checksum(bad_portal); _err(Portal.validate(bad_portal), "INVALID_CONSTRUCTION_PROXY_PORTAL_LOOP", "portal loop")
	var cache = Cache.new()
	var result := Compiler.compile(request, cache); _ok(result, "compile")
	_ok(Topology.validate(result["topology"]), "topology")
	_ok(Artifact.validate(result["shell_artifact"]), "shell artifact")
	_ok(Manifest.validate(result["manifest"]), "manifest")
	_assert(int(result["manifest"]["total_part_count"]) == 125, "part count")
	_assert(int(result["manifest"]["total_section_count"]) == 1, "single section")
	_assert(int(result["stats"]["raw_face_count"]) == 750, "raw faces")
	_assert(int(result["stats"]["exposed_face_count"]) == 150, "internal faces culled")
	_assert(int(result["stats"]["shell_quad_count"]) <= int(result["stats"]["exposed_face_count"]), "material-aware greedy shell")
	_assert(cache.get_artifact_count() == 4, "shell section and two interior artifacts")
	var artifact: Dictionary = result["shell_artifact"].duplicate(true); artifact["part_count"] = 124; _err(Artifact.validate(artifact), "CONSTRUCTION_PROXY_ARTIFACT_CONTENT_HASH_MISMATCH", "artifact tamper")
	var interest := F.far_interest(request); _ok(Interest.validate(interest), "interest")
	var bad_interest := interest.duplicate(true); bad_interest["visible_section_ids"] = ["section/z", "section/a"]; bad_interest["checksum"] = Interest.compute_checksum(bad_interest); _err(Interest.validate(bad_interest), "INVALID_CONSTRUCTION_PROXY_INTEREST_SECTIONS", "interest order")
	var controller_script = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")
	var controller = controller_script.new(); get_root().add_child(controller); _ok(controller.compile_construct(request), "controller compile")
	var packet_result := controller.make_packet(interest); _ok(packet_result, "far packet")
	_ok(Plan.validate(packet_result["plan"]), "far plan")
	_ok(Packet.validate(packet_result["packet"]), "far packet contract")
	_assert(String(packet_result["plan"]["detail_mode"]) == Plan.DISTANT_SHELL, "far mode")
	_assert(packet_result["packet"]["interactive_part_descriptors"].is_empty(), "far packet has no parts")
	_assert(int(packet_result["packet"]["suppressed_part_count"]) == 125, "all parts suppressed")
	_finish()

func _ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _err(result: Dictionary, code: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C22 compiled proxy contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C22 compiled proxy contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
