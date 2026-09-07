extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric1/bridge4_canonical_world_fixture_v1.gd")

func _init() -> void:
	var path := OS.get_environment("FABRIC_R1_COLD_STATE")
	if path.is_empty():
		_fail("FABRIC_R1_COLD_STATE missing")
		return
	var initial := Fixture.initial_snapshot()
	var matter := Fixture.matter_batch()
	var authority := Adapter.authority_for(initial, matter, Fixture.AUTHORITY_OWNER, Fixture.AUTHORITY_EPOCH)
	var created := Fixture.create_store(initial)
	if not created.result.success:
		_fail("canonical store create failed")
		return
	var store = created.store
	var rev0: Dictionary = store.get_snapshot(Fixture.CONSTRUCT_ID)
	var runtime := Runtime.new()
	if not runtime.start_authoritative(rev0, matter, authority, [], 10).success:
		_fail("runtime start failed")
		return
	if not runtime.observe_load(rev0, matter, Fixture.TARGET_BOND_ID, 90.0, 11, authority).success:
		_fail("refinement proposal failed")
		return
	var desired := Fixture.damaged_snapshot(rev0)
	var applied := Fixture.apply_damage(store, rev0, desired)
	if not applied.result.success:
		_fail("external canonical mutation failed")
		return
	var rev1: Dictionary = store.get_snapshot(Fixture.CONSTRUCT_ID)
	var event_id := "event/r1/cold-canonical-break"
	if not runtime.observe_canonical_successor(rev1, matter, event_id, 12, authority).success:
		_fail("canonical successor observation failed")
		return
	if not runtime.rebake(13, rev1, matter, authority).success:
		_fail("rebake failed")
		return
	var executed := runtime.execute(rev1, matter, [1.0, 0.0], authority)
	if not executed.success:
		_fail("final execution failed")
		return
	var payload := {
		"snapshot": rev1,
		"matter": matter,
		"authority": authority,
		"events": [event_id],
		"expected_boundary_flow": executed.details.boundary_flow,
		"expected_boundary_power": executed.details.boundary_power,
		"expected_revision": int(rev1.state_revision),
		"expected_frontier": runtime.status().frontier_hash,
		"checksum": "",
	}
	payload["checksum"] = U.compute_checksum(payload)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write cold state")
		return
	file.store_string(JSON.stringify(payload))
	file.close()
	print("FABRIC_REPAIR_R1_COLD_WRITER_HASH=%s" % U.canonical_hash(payload))
	print("FABRIC-REPAIR-R1 COLD WRITER: PASS")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	print("FABRIC-REPAIR-R1 COLD WRITER: FAIL")
	quit(1)
