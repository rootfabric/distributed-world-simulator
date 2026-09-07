extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ConstructMutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric1/bridge4_canonical_world_fixture_v1.gd")

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	_run()
	_finish()

func _run() -> void:
	var initial := Fixture.initial_snapshot()
	var matter := Fixture.matter_batch()
	_assert_ok(Snapshot.validate(initial), "initial Construction snapshot invalid")
	_assert_ok(MatterBatch.validate(matter), "Matter batch invalid")
	var created := Fixture.create_store(initial)
	_assert_ok(created.result, "real ConstructionConstructStore create failed")
	var store = created.store
	var canonical_before: Dictionary = store.get_snapshot(Fixture.CONSTRUCT_ID)
	_assert(String(canonical_before.checksum) == String(initial.checksum), "store changed canonical creation bytes")

	var compiled := Adapter.compile(canonical_before, matter, Fixture.AUTHORITY_OWNER, Fixture.AUTHORITY_EPOCH, [])
	_assert_ok(compiled, "canonical Construction/Matter did not compile to FABRIC1 graph")
	_assert(int(compiled.details.spec.internal_node_ids.size()) == 102, "unexpected internal node count")
	_assert(int(compiled.details.spec.boundary_node_ids.size()) == 2, "unexpected boundary count")
	_assert(String(compiled.details.frontier.sources[0].source_domain) == "CONSTRUCTION", "Construction source missing from real frontier")
	_assert(String(compiled.details.frontier.sources[1].source_domain) == "MATTER", "Matter source missing from real frontier")
	_assert(compiled.details.authority.mutable_source_ids.size() == 1 and compiled.details.authority.readonly_source_ids.size() == 1, "canonical mutability boundary wrong")

	var runtime := Runtime.new()
	_assert_ok(runtime.start(canonical_before, matter, Fixture.AUTHORITY_OWNER, Fixture.AUTHORITY_EPOCH, 10), "BRIDGE4 runtime start failed")
	_assert(String(runtime.status().mode) == "BAKED", "real canonical object did not start BAKED")
	var base_exec := runtime.execute(canonical_before, matter, [1.0, 0.0])
	_assert_ok(base_exec, "initial BAKED execution failed")
	var base_flow := float(base_exec.details.boundary_flow[0])
	_assert(absf(base_flow) > 1.0e-9, "initial canonical construct has no functional flow")

	var canonical_checksum_before_load := String(store.get_snapshot(Fixture.CONSTRUCT_ID).checksum)
	var safe := runtime.observe_load(canonical_before, matter, Fixture.TARGET_BOND_ID, 70.0, 11)
	_assert_ok(safe, "subcritical load failed")
	_assert(not bool(safe.details.refined) and not bool(safe.details.failure_proposed), "subcritical load refined unexpectedly")
	_assert(String(store.get_snapshot(Fixture.CONSTRUCT_ID).checksum) == canonical_checksum_before_load, "physical observation wrote canonical Construction")

	var overload := runtime.observe_load(canonical_before, matter, Fixture.TARGET_BOND_ID, 90.0, 12)
	_assert_ok(overload, "overload observation failed")
	_assert(bool(overload.details.refined) and bool(overload.details.failure_proposed), "overload did not refine/propose")
	_assert(String(runtime.status().mode) == "FULL", "overload did not enter FULL")
	_assert(runtime.status().canonical_writes == 0, "BRIDGE4 gained canonical write authority")
	_assert(String(store.get_snapshot(Fixture.CONSTRUCT_ID).checksum) == canonical_checksum_before_load, "failure proposal mutated canonical store")
	_assert(overload.details.proposal.write_authorized == false and overload.details.proposal.canonical == false, "proposal falsely claims canonical authority")

	var damaged := Fixture.damaged_snapshot(canonical_before)
	var mutation := ConstructMutation.create(ConstructMutation.OP_UPDATE, Fixture.CONSTRUCT_ID, canonical_before, damaged)
	_assert_ok(ConstructMutation.validate(mutation), "real Construction mutation invalid")
	var external := Fixture.apply_damage(store, canonical_before, damaged)
	_assert_ok(external.result, "external canonical Construction mutation failed")
	var canonical_after: Dictionary = store.get_snapshot(Fixture.CONSTRUCT_ID)
	_assert(int(canonical_after.state_revision) == 1 and String(canonical_after.build_state) == "DAMAGED", "canonical successor did not advance")
	_assert(String(Adapter.bond_by_id(canonical_after, Fixture.TARGET_BOND_ID).state) == "BROKEN", "canonical bond did not break")

	var event_id := "event/bridge4/canonical-break-001"
	var observed := runtime.observe_canonical_successor(canonical_after, matter, event_id, 13)
	_assert_ok(observed, "BRIDGE4 did not observe real canonical successor")
	_assert(String(observed.details.stale_error) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "old BAKE was not fenced")
	_assert(runtime.status().canonical_mutations_observed == 1 and runtime.status().event_ledger == [event_id], "canonical event ledger wrong")
	var old_exec := runtime.execute(canonical_before, matter, [1.0, 0.0])
	_assert_error(old_exec, "BRIDGE4_CANONICAL_BINDING_STALE", "old canonical source still executable")
	var successor_full := runtime.execute(canonical_after, matter, [1.0, 0.0])
	_assert_ok(successor_full, "successor FULL execution failed")
	var successor_flow := float(successor_full.details.boundary_flow[0])
	_assert(absf(successor_flow - base_flow) > 1.0e-5, "real canonical break has no downstream functional consequence")

	_assert_ok(runtime.rebake(14), "successor rebake failed")
	_assert(String(runtime.status().mode) == "BAKED", "successor did not return to BAKED")
	var successor_baked := runtime.execute(canonical_after, matter, [1.0, 0.0])
	_assert_ok(successor_baked, "successor BAKED execution failed")
	_assert(_max_error(successor_full.details.boundary_flow, successor_baked.details.boundary_flow) <= 2.0e-8, "FULL/BAKE successor flow parity failed")
	_assert(absf(float(successor_full.details.boundary_power) - float(successor_baked.details.boundary_power)) <= 2.0e-8, "FULL/BAKE successor power parity failed")

	var capsule_result := runtime.capture_capsule()
	_assert_ok(capsule_result, "BRIDGE4 capsule unavailable")
	var capsule: Dictionary = capsule_result.details.capsule
	_assert(capsule.canonical == false and capsule.derived == true and capsule.discardable == true, "BRIDGE4 capsule truth boundary invalid")
	var restart_authority := Adapter.authority_for(canonical_after, matter, Fixture.AUTHORITY_OWNER, Fixture.AUTHORITY_EPOCH)
	var restarted := Runtime.new()
	_assert_ok(restarted.restore(canonical_after, matter, capsule, restart_authority, [event_id]), "restart from authoritative successor failed")
	var restarted_exec := restarted.execute(canonical_after, matter, [1.0, 0.0])
	_assert_ok(restarted_exec, "restarted execution failed")
	_assert(_max_error(restarted_exec.details.boundary_flow, successor_baked.details.boundary_flow) <= 2.0e-8, "restart changed physical result")
	var stale_restart := Runtime.new().restore(canonical_before, matter, capsule, restart_authority, [event_id])
	_assert_error(stale_restart, "BRIDGE4_CAPSULE_STALE", "old canonical snapshot accepted successor capsule")

	var changed_matter := matter.duplicate(true)
	changed_matter.temperature_k = 300.0
	changed_matter.checksum = preload("res://scripts/simulation/matter/matter_contract_utils.gd").compute_checksum(changed_matter)
	_assert_ok(MatterBatch.validate(changed_matter), "changed Matter batch is not canonical-valid")
	var stale_matter_exec := restarted.execute(canonical_after, changed_matter, [1.0, 0.0])
	_assert_error(stale_matter_exec, "BRIDGE4_CANONICAL_BINDING_STALE", "changed canonical Matter remained executable")
	var stale_matter_restart := Runtime.new().restore(canonical_after, changed_matter, capsule, restart_authority, [event_id])
	_assert_error(stale_matter_restart, "BRIDGE4_CAPSULE_STALE", "changed Matter accepted old derived capsule")

	var duplicate := restarted.observe_canonical_successor(canonical_after, matter, event_id, 20)
	_assert_error(duplicate, "BRIDGE4_CANONICAL_SUCCESSOR_ORDER_INVALID", "duplicate canonical event accepted")
	_assert(restarted.status().canonical_writes == 0, "restart gained canonical write authority")

	var hash := Utils.canonical_hash({
		"binding": runtime.status().binding_checksum,
		"event_ledger": runtime.status().event_ledger,
		"base_flow": base_flow,
		"successor_flow": successor_flow,
		"successor_artifact": successor_baked.details.artifact_hash,
		"restart_flow": restarted_exec.details.boundary_flow,
		"transition_hash": restarted.status().fabric1.transition_hash,
	})
	print("BRIDGE4_BASE_FLOW=" + str(base_flow))
	print("BRIDGE4_SUCCESSOR_FLOW=" + str(successor_flow))
	print("BRIDGE4_HASH=%s" % hash)

func _max_error(left: Array, right: Array) -> float:
	var result := 0.0
	for index in range(mini(left.size(), right.size())):
		result = maxf(result, absf(float(left[index]) - float(right[index])))
	return result

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("FABRIC BRIDGE-4 Canonical World: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FABRIC BRIDGE-4 Canonical World: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
