extends SceneTree

const F = preload("res://tests/construction/fixtures/c22_compiled_proxy_fixture.gd")
const Controller = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")
const Interest = preload("res://scripts/construction/proxies/construction_proxy_interest_request.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const TRANSITIONS := 128

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var request: Dictionary = F.compile_request()
	var controller = Controller.new()
	get_root().add_child(controller)
	var compile_started := Time.get_ticks_msec()
	var compiled: Dictionary = controller.compile_construct(request)
	var compile_ms := Time.get_ticks_msec() - compile_started
	_ok(compiled, "compile 10k construct")
	var mode_signatures: Dictionary = {}
	var mesh_by_hash: Dictionary = {}
	var unique_hashes: Dictionary = {}
	var total_payloads := 0
	var total_triangles := 0
	var total_hits_reported := 0
	var present_started := Time.get_ticks_msec()
	var runtime = null
	for tick in range(TRANSITIONS):
		var interest: Dictionary = _interest_for_tick(request, tick)
		var presented: Dictionary = controller.present("client/c24/soak", interest)
		_ok(presented, "transition %d" % tick)
		runtime = presented["runtime"]
		var packet: Dictionary = presented["packet"]
		var packet_hashes: Array = []
		var expected_triangles := 0
		for artifact in packet["artifact_payloads"]:
			var content_hash := String(artifact["content_hash"])
			packet_hashes.append(content_hash)
			unique_hashes[content_hash] = true
			expected_triangles += int(artifact["merged_quad_count"]) * 2
		total_payloads += packet_hashes.size()
		total_triangles += expected_triangles
		total_hits_reported += int(presented["apply_result"]["mesh_cache_hit_count"])
		_assert(runtime.get_total_proxy_triangle_count() == expected_triangles, "transition triangle total %d" % tick)
		var nodes: Array = runtime.get_proxy_mesh_instances()
		_assert(nodes.size() == packet_hashes.size(), "transition node/payload count %d" % tick)
		for index in range(nodes.size()):
			var content_hash := String(packet_hashes[index])
			_assert(nodes[index].mesh is ArrayMesh, "transition ArrayMesh %d/%d" % [tick, index])
			if mesh_by_hash.has(content_hash):
				_assert(mesh_by_hash[content_hash] == nodes[index].mesh, "content-addressed resource reuse %d/%d" % [tick, index])
			else:
				mesh_by_hash[content_hash] = nodes[index].mesh
		var mode := String(packet["detail_mode"])
		var signature := Utils.payload_hash(_mesh_signatures(nodes))
		if mode_signatures.has(mode):
			_assert(String(mode_signatures[mode]) == signature, "deterministic mode mesh signatures %s" % mode)
		else:
			mode_signatures[mode] = signature
	var present_ms := Time.get_ticks_msec() - present_started
	var stats: Dictionary = runtime.get_mesh_cache_stats()
	_assert(int(compiled["manifest"]["total_part_count"]) == 10000, "10k authoritative parts remain source")
	_assert(int(compiled["manifest"]["total_section_count"]) == 80, "80 stable sections")
	_assert(int(stats["entries"]) == unique_hashes.size(), "one runtime mesh resource per unique content hash")
	_assert(int(stats["misses"]) == unique_hashes.size(), "exact cache miss count")
	_assert(int(stats["hits"]) == total_payloads - unique_hashes.size(), "exact cache hit count")
	_assert(total_hits_reported == int(stats["hits"]), "apply results expose all cache hits")
	_assert(int(stats["entries"]) < 32, "working-set mesh cache bounded below full 83 artifacts")
	_assert(int(stats["gpu_bytes"]) < 16777216, "working-set GPU estimate below 16 MiB")
	_assert(int(stats["evictions"]) == 0, "default cache holds active working set")
	_assert(mode_signatures.size() == 4, "all four HLOD modes exercised")
	_assert(total_triangles > 0, "soak materialized real triangles")
	_assert(compile_ms < 30000, "10k proxy compile broad ceiling")
	_assert(present_ms < 30000, "128 runtime transitions broad ceiling")
	print("C24 scale metrics: compile_ms=%d present_ms=%d unique_meshes=%d hits=%d gpu_bytes=%d payloads=%d triangles=%d" % [compile_ms, present_ms, unique_hashes.size(), int(stats["hits"]), int(stats["gpu_bytes"]), total_payloads, total_triangles])
	_finish()

func _interest_for_tick(request: Dictionary, tick: int) -> Dictionary:
	var interest: Dictionary
	match tick % 4:
		0: interest = F.far_interest(request)
		1: interest = F.section_interest(request)
		2: interest = F.local_interest(request)
		_: interest = F.interior_interest(request)
	interest["observer_id"] = "observer/c24/soak-%03d" % (tick % 16)
	interest["checksum"] = Interest.compute_checksum(interest)
	return interest

func _mesh_signatures(nodes: Array) -> Array:
	var result: Array = []
	for node in nodes:
		result.append(String(node.get_meta("mesh_signature", "")))
	result.sort()
	return result

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C24 proxy mesh backend scale/soak: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C24 proxy mesh backend scale/soak: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
