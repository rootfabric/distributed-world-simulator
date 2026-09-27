extends Node3D

# Read-only P7 procedural bootstrap plus the existing MW6 replica. Only the
# bootstrap is locally generated; every later change must pass MW6 validation.
const Bubble = preload("res://scripts/world/matter/lunar_matter_bubble.gd")
const Bootstrap = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp_bootstrap_surface.gd")
const Replica = preload("res://scripts/simulation/matter/network/matter_replica_client.gd")
const Envelope = preload("res://scripts/network/bus/replication_envelope.gd")
const Grid = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const Mesher = preload("res://scripts/world/matter/meshing/matter_tetrahedral_mesher.gd")
const MeshData = preload("res://scripts/world/matter/meshing/matter_brick_mesh_data.gd")
const Factory = preload("res://scripts/world/matter/meshing/matter_mesh_resource_factory.gd")
const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Bridge = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_shared_dig_authority.gd")

var _configured := false
var _draw := false
var _actor := ""
var _replica = null
var _body: Dictionary = {}
var _grid: Dictionary = {}
var _baseline: Dictionary = {}
var _bootstrap_hash := ""
var _geometry_hash := ""
var _initial_geometry_hash := ""
var _store_hash := ""
var _mesh_roots: Dictionary = {}
var _mesh_facts: Array = []
var _triangles := 0
var _rebuilds := 0
var _applied_frames := 0
var _last_transport_sequence := 0

func configure_actor(actor: String, session: String, draw_surface: bool) -> Dictionary:
	if _configured or actor not in ["a", "b"]: return Bridge.fail("MVP4_REPLICA_CONFIGURATION_INVALID")
	var builder = Bubble.new()
	var result: Dictionary = builder.configure(Bootstrap.DESCRIPTOR.duplicate(true))
	if not bool(result.get("success", false)): return result
	var snapshots: Array = builder.materialize_presentation_level()
	if snapshots.size() != 8: return Bridge.fail("MVP4_REPLICA_BOOTSTRAP_INVALID")
	_body = builder.body_definition().duplicate(true)
	_grid = builder.grid_profile().duplicate(true)
	_bootstrap_hash = builder.snapshot_store().content_hash()
	for snapshot in snapshots:
		_baseline[String(snapshot["address"]["address_id"])] = Dictionary(snapshot).duplicate(true)
	builder = null
	_actor = actor
	_draw = draw_surface
	_replica = Replica.new()
	result = _replica.configure(_body, _grid, Bridge.OWNER, Bridge.EPOCH, Bridge.client(actor))
	if not bool(result.get("success", false)): return result
	# MW6 sequence zero represents the procedural world, not an empty store.
	# Seed only exact revision-zero bootstrap snapshots through the existing
	# public replica store API BEFORE session activation. No received snapshot
	# conflict/epoch/sequence check is bypassed or relaxed.
	for snapshot in snapshots:
		if int(snapshot.get("state_revision", -1)) != 0:
			return Bridge.fail("MVP4_NONZERO_BOOTSTRAP_REVISION")
		result = _replica.snapshot_store().put(snapshot)
		if not bool(result.get("success", false)): return result
	if _replica.snapshot_store().content_hash() != _bootstrap_hash:
		return Bridge.fail("MVP4_REPLICA_BOOTSTRAP_HASH_MISMATCH")
	result = _replica.activate_session(Bridge.peer(actor), session)
	if not bool(result.get("success", false)): return result
	_configured = true
	result = _rebuild()
	_initial_geometry_hash = _geometry_hash
	return result

func create_sync_request() -> Dictionary:
	return _replica.create_sync_request() if _configured else {}

func create_ack() -> Dictionary:
	return _replica.create_ack() if _configured else {}

func consume(envelope: Dictionary) -> Dictionary:
	if not _configured: return Bridge.fail("MVP4_REPLICA_NOT_CONFIGURED")
	var valid: Dictionary = Envelope.validate(envelope)
	if not bool(valid.get("success", false)): return valid
	if envelope.get("target_peer_id") != Bridge.peer(_actor): return Bridge.fail("MVP4_REPLICA_FOREIGN_PEER")
	var sequence := int(envelope.get("sequence", -1))
	if sequence != _last_transport_sequence + 1: return Bridge.fail("MVP4_REPLICA_TRANSPORT_SEQUENCE_GAP")
	if envelope.get("payload_schema") != "planet_simulator.matter_replication_frame.v1":
		return Bridge.fail("MVP4_REPLICA_FRAME_SCHEMA_INVALID")
	var before: String = _replica.state_hash()
	var applied: Dictionary = _replica.apply_frame(Dictionary(envelope.get("payload", {})))
	if not bool(applied.get("success", false)): return applied
	_last_transport_sequence = sequence
	_applied_frames += 1
	if before != _replica.state_hash():
		var rebuilt := _rebuild()
		if not bool(rebuilt.get("success", false)): return rebuilt
	return Bridge.ok(contract_report())

func _rebuild() -> Dictionary:
	var combined := _baseline.duplicate(true)
	var store = _replica.snapshot_store()
	for address_id in store.address_ids():
		if not combined.has(address_id): return Bridge.fail("MVP4_REPLICA_SCOPE_ESCAPE")
		combined[address_id] = store.get_snapshot_by_address_id(address_id)
	var ids := combined.keys()
	ids.sort()
	var entries: Array = []
	var geometry_entries: Array = []
	var facts: Array = []
	var pending_meshes: Dictionary = {}
	var triangle_count := 0
	for address_id in ids:
		var snapshot: Dictionary = combined[address_id]
		var mesh: Dictionary = Mesher.build_mesh_data(snapshot, _grid)
		var valid: Dictionary = MeshData.validate(mesh)
		if not bool(valid.get("success", false)): return valid
		entries.append({"address_id": String(address_id), "state_revision": int(snapshot["state_revision"]), "snapshot_checksum": String(snapshot["checksum"])})
		var vertices: Array = []
		for vertex in mesh["vertices"]:
			vertices.append([roundi(vertex.x * 1000000.0), roundi(vertex.y * 1000000.0), roundi(vertex.z * 1000000.0)])
		var geometry := MatterUtils.payload_hash({"vertices": vertices, "indices": Array(mesh["indices"])})
		geometry_entries.append({"address_id": String(address_id), "geometry_hash": geometry})
		facts.append({"address_id": String(address_id), "state_revision": snapshot["state_revision"], "source_checksum": snapshot["checksum"], "mesh_content_hash": mesh["content_hash"], "geometry_hash": geometry, "triangles": int(mesh["triangle_count"])})
		triangle_count += int(mesh["triangle_count"])
		pending_meshes[address_id] = mesh
	if _draw:
		for old in _mesh_roots.values():
			remove_child(old)
			old.queue_free()
		_mesh_roots.clear()
		for address_id in ids:
			var mesh: Dictionary = pending_meshes[address_id]
			if mesh["status"] == MeshData.STATUS_EMPTY: continue
			var node = Factory.create_presenter(mesh, Factory.create_vertex_color_material(), false)
			if node == null: return Bridge.fail("MVP4_REPLICA_MESH_BUILD_FAILED")
			node.position = world_to_render(mesh["origin_body_local_m"])
			add_child(node)
			_mesh_roots[address_id] = node
	_store_hash = MatterUtils.payload_hash({"body_definition_hash": _body["checksum"], "grid_profile_hash": Grid.content_hash(_grid), "entries": entries})
	_geometry_hash = MatterUtils.payload_hash({"entries": geometry_entries})
	_mesh_facts = facts
	_triangles = triangle_count
	_rebuilds += 1
	return Bridge.ok()

func world_to_render(position_m: Vector3) -> Vector3:
	return position_m - Bootstrap.ANCHOR

func contract_report() -> Dictionary:
	return {"mode": "MW6_READ_ONLY_P7_REPLICA_PROJECTION", "configured": _configured, "actor": _actor, "bootstrap_hash": _bootstrap_hash, "store_hash": _store_hash, "geometry_hash": _geometry_hash, "initial_geometry_hash": _initial_geometry_hash, "geometry_changed": _geometry_hash != _initial_geometry_hash, "mesh_count": _mesh_roots.size() if _draw else _mesh_facts.filter(func(row): return int(row["triangles"]) > 0).size(), "triangle_count": _triangles, "mesh_facts": _mesh_facts.duplicate(true), "rebuild_count": _rebuilds, "applied_frames": _applied_frames, "replica": _replica.report() if _replica != null else {}, "canonical_state_owned": false, "mutable_matter_store_retained": false, "read_only_replica_store_retained": _replica != null, "excavation_service_retained": false, "collision_enabled": false, "network_mutation_proven": _configured and _replica.stream_sequence() > 0 and _geometry_hash != _initial_geometry_hash, "mvp4_predicate_verified": false}
