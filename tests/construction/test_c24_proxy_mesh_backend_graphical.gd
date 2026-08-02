extends SceneTree

const F = preload("res://tests/construction/fixtures/c22_compiled_proxy_fixture.gd")
const Controller = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")
const Packet = preload("res://scripts/construction/proxies/construction_proxy_network_packet.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var request: Dictionary = F.compile_request()
	var controller = Controller.new()
	get_root().add_child(controller)
	_ok(controller.compile_construct(request), "compile")
	var far: Dictionary = controller.present("client/c24/graphical", F.far_interest(request))
	_ok(far, "present far")
	var runtime = far["runtime"]
	var shell_node: MeshInstance3D = runtime.get_proxy_mesh_instances()[0]
	var shell_mesh = shell_node.mesh
	_assert(shell_mesh is ArrayMesh, "shell graphical resource is ArrayMesh")
	_assert(shell_node.position == Vector3.ZERO, "compiled vertices remain in construct-local coordinates")
	_assert(shell_mesh.get_surface_count() > 0, "shell has renderable surfaces")
	for surface_index in range(shell_mesh.get_surface_count()):
		_assert(not shell_mesh.surface_get_name(surface_index).is_empty(), "surface has material batch name")
		_assert(shell_mesh.surface_get_material(surface_index) is StandardMaterial3D, "surface has material resource")
		var arrays: Array = shell_mesh.surface_get_arrays(surface_index)
		_assert(arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array, "surface vertex buffer")
		_assert(arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array, "surface normal buffer")
		_assert(arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array, "surface uv buffer")
		_assert(arrays[Mesh.ARRAY_INDEX] is PackedInt32Array, "surface index buffer")

	var old_shell_node = shell_node
	var section: Dictionary = controller.present("client/c24/graphical", F.section_interest(request))
	_ok(section, "present section")
	_assert(runtime == section["runtime"], "same runtime node")
	_assert(runtime.get_proxy_mesh_count() == 12, "shell replaced by bounded section meshes")
	_assert(not is_instance_valid(old_shell_node), "old shell MeshInstance3D freed")
	for mesh_node in runtime.get_proxy_mesh_instances():
		_assert(mesh_node.mesh is ArrayMesh, "section node uses ArrayMesh")
		_assert(not (mesh_node.mesh is BoxMesh), "section node is not BoxMesh")
		_assert(mesh_node.position == Vector3.ZERO, "section mesh uses absolute construct-local vertices")
	_assert(runtime.get_collision_proxy_count() == 12, "section collision stays bounded")

	var stable_mesh = runtime.get_proxy_mesh_instances()[0].mesh
	var stable_mode: String = runtime.get_detail_mode()
	var stable_count: int = runtime.get_proxy_mesh_count()
	var malformed: Dictionary = _packet_with_invalid_quad(section["packet"])
	_ok(Packet.validate(malformed), "malformed mesh payload still passes C22 envelope validation")
	var rejected: Dictionary = runtime.apply_packet(malformed)
	_assert(not bool(rejected.get("success", false)), "C24 backend rejects malformed quad")
	_assert(String(rejected.get("error_code", "")) == "INVALID_CONSTRUCTION_PROXY_GRID_QUAD_SIZE", "malformed quad error code")
	_assert(runtime.get_detail_mode() == stable_mode, "failed apply preserves previous detail mode")
	_assert(runtime.get_proxy_mesh_count() == stable_count, "failed apply preserves previous nodes")
	_assert(runtime.get_proxy_mesh_instances()[0].mesh == stable_mesh, "failed apply preserves previous mesh resources")

	var interior: Dictionary = controller.present("client/c24/graphical", F.interior_interest(request))
	_ok(interior, "present interior")
	_assert(runtime.get_interactive_part_count() == 8, "exact interactive parts still materialized")
	_assert(runtime.get_proxy_mesh_count() <= 7, "interior proxy context bounded")
	for mesh_node in runtime.get_proxy_mesh_instances():
		_assert(mesh_node.mesh is ArrayMesh, "interior context uses ArrayMesh")
	_finish()

func _packet_with_invalid_quad(source: Dictionary) -> Dictionary:
	var packet: Dictionary = source.duplicate(true)
	packet["artifact_payloads"] = Array(packet["artifact_payloads"]).duplicate(true)
	var mutated := false
	for artifact_index in range(packet["artifact_payloads"].size()):
		var artifact: Dictionary = Dictionary(packet["artifact_payloads"][artifact_index]).duplicate(true)
		artifact["material_batches"] = Array(artifact["material_batches"]).duplicate(true)
		for batch_index in range(artifact["material_batches"].size()):
			var batch: Dictionary = Dictionary(artifact["material_batches"][batch_index]).duplicate(true)
			batch["quads"] = Array(batch["quads"]).duplicate(true)
			for quad_index in range(batch["quads"].size()):
				var quad: Dictionary = Dictionary(batch["quads"][quad_index]).duplicate(true)
				if String(quad.get("kind", "")) == "GRID_QUAD":
					quad["width"] = 0
					batch["quads"][quad_index] = quad
					mutated = true
					break
			artifact["material_batches"][batch_index] = batch
			if mutated:
				break
		if mutated:
			artifact["content_hash"] = Artifact.compute_content_hash(artifact)
			artifact["artifact_id"] = "proxy-artifact/%s" % artifact["content_hash"]
			artifact["checksum"] = Artifact.compute_checksum(artifact)
			packet["artifact_payloads"][artifact_index] = artifact
			break
	packet["artifact_payloads"].sort_custom(func(a, b): return String(a["artifact_id"]) < String(b["artifact_id"]))
	packet["checksum"] = Packet.compute_checksum(packet)
	return packet

func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C24 proxy mesh backend graphical: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C24 proxy mesh backend graphical: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
