extends SceneTree

const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const TopologyRuntime = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_runtime_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")

const COUNT := 2000
const EXPECTED_TRANSACTION_CHECKSUM := "b421928b2a5db9e700476d9d70e2be6b6ecde8bfe778b2511a1efaf85d082ebd"

var _checks := 0

func _initialize() -> void:
	print("COMPLEX0 2000 TRACE: build begin")
	var subject := Fixture.build(COUNT)
	print("COMPLEX0 2000 TRACE: build end")
	_must(bool(subject.get("success", false)), "subject build")

	print("COMPLEX0 2000 TRACE: parent compile begin")
	var parent := Lifecycle.compile(subject["view_request"], Fixture.lifecycle_options(subject))
	print("COMPLEX0 2000 TRACE: parent compile end")
	_must(bool(parent.get("success", false)) and String(parent.get("status", "")) == Lifecycle.STATUS_READY, "parent bake")

	var state := Fixture.reduced_state()
	print("COMPLEX0 2000 TRACE: parent execute begin")
	_must(bool(Lifecycle.execute(parent, state).get("success", false)), "parent execute")
	print("COMPLEX0 2000 TRACE: parent execute end")

	print("COMPLEX0 2000 TRACE: structural begin")
	var structural := Fixture.compile_structural(subject)
	print("COMPLEX0 2000 TRACE: structural end")
	_must(bool(structural.get("success", false)), "structural pipeline")

	print("COMPLEX0 2000 TRACE: guard begin")
	var guard := Fixture.evaluate_guard(subject, structural)
	print("COMPLEX0 2000 TRACE: guard end")
	_must(bool(guard.get("success", false)) and String(guard.get("status", "")) == "STRUCTURAL_REFINEMENT_REQUIRED", "guard")
	_must(
		guard["refinement_requests"].size() == 1
		and String(guard["refinement_requests"][0]["peak_bond_id"]) == String(subject["break_bond_id"]),
		"weak bond target"
	)

	var broken := Fixture.make_break(subject, structural)
	_must(bool(broken.get("success", false)), "canonical break")
	var invalidation := Fixture.make_bake_invalidation(parent, broken)
	_must(bool(BakeInvalidation.validate(invalidation).get("success", false)), "bake invalidation")
	var stale := Lifecycle.execute(parent, state, 0.0, [invalidation])
	_must(
		not bool(stale.get("success", false))
		and String(stale.get("error_code", "")) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN",
		"stale rejection"
	)

	print("COMPLEX0 2000 TRACE: transaction begin")
	var compiled := Fixture.compile_transaction(broken)
	print("COMPLEX0 2000 TRACE: transaction end")
	_must(bool(compiled.get("success", false)), "transaction compile")
	var transaction: Dictionary = compiled["transaction"]
	_must(String(transaction["checksum"]) == EXPECTED_TRANSACTION_CHECKSUM, "transaction checksum")
	_must(
		transaction["rebaked_components"].size() == 2
		and transaction["invalidated_pieces"].size() == 3,
		"split/rebake counts"
	)

	print("COMPLEX0 2000 TRACE: topology runtime begin")
	var result := TopologyRuntime.execute(
		transaction,
		structural["local"]["plan"],
		structural["aggregate"]["descriptor"],
		structural["aggregate"]["reconstruction_mapping"],
		structural["guard"]["guard_field"],
		state,
		Fixture.guard_context(subject, structural),
		broken["current_frontier"],
		broken["current_authority"],
		broken["dependencies"],
		[]
	)
	print("COMPLEX0 2000 TRACE: topology runtime end")
	_must(bool(result.get("success", false)) and String(result.get("status", "")) == TopologyRuntime.READY, "topology runtime")
	_must(String(result["event_commit"]["state"]) == "APPLIED" and int(result["diagnostics"]["duplicate_event_count"]) == 0, "event commit")
	_must(int(result["diagnostics"]["executable_physical_bake_artifact_count"]) == 2, "fresh executable artifacts")
	_must(float(result["diagnostics"]["mass_error"]) <= Fixture.CONSERVATION_TOLERANCE, "mass conservation")
	_must(float(result["diagnostics"]["linear_momentum_error"]) <= Fixture.CONSERVATION_TOLERANCE, "linear momentum")
	_must(float(result["diagnostics"]["angular_momentum_error"]) <= Fixture.CONSERVATION_TOLERANCE, "angular momentum")
	_must(float(result["diagnostics"]["max_state_handoff_error"]) <= Fixture.CONTINUITY_TOLERANCE, "state handoff")
	_must(int(result["diagnostics"]["full_dof"]) == COUNT * 13 and int(result["diagnostics"]["rebaked_dof"]) == 26, "dof reduction")

	print("COMPLEX0 2000 TRACE: reconstruction begin")
	var parent_full := Reconstruction.reconstruct(structural["aggregate"]["reconstruction_mapping"], state)
	_must(bool(parent_full.get("success", false)), "parent reconstruction")
	var expected: Dictionary = parent_full["details"]["full_states"]
	var state_by_component: Dictionary = {}
	for entry in result["rebaked_component_states"]:
		state_by_component[String(entry["component_id"])] = entry
	var coverage := 0
	var max_error := 0.0
	var fragment_sizes: Array = []
	for component in transaction["rebaked_components"]:
		var component_id := String(component["component_id"])
		var rebuilt := Reconstruction.reconstruct(
			component["reconstruction_mapping"],
			state_by_component[component_id]["reduced_state"]
		)
		_must(bool(rebuilt.get("success", false)), "component reconstruction")
		fragment_sizes.append(component["part_ids"].size())
		for part_id in component["part_ids"]:
			var key := String(part_id)
			coverage += 1
			max_error = maxf(max_error, _state_error(rebuilt["details"]["full_states"][key], expected[key]))
	fragment_sizes.sort()
	_must(coverage == COUNT, "canonical coverage")
	_must(max_error <= Fixture.CONTINUITY_TOLERANCE, "reconstruction continuity")
	print("COMPLEX0 2000 TRACE: reconstruction end")

	print(
		"FABRIC-BAKE COMPLEX0 2000 Exact Closure: PASS (%d assertions) checksum=%s fragments=%s reduction=%s max_state_error=%s"
		% [
			_checks,
			transaction["checksum"],
			str(fragment_sizes),
			str(result["diagnostics"]["post_split_reduction_ratio"]),
			str(max_error),
		]
	)
	quit(0)

func _must(condition: bool, label: String) -> void:
	if condition:
		_checks += 1
		return
	printerr("FABRIC-BAKE COMPLEX0 2000 Exact Closure: FAIL label=%s" % label)
	quit(1)
	assert(false, label)

func _state_error(left: Dictionary, right: Dictionary) -> float:
	return maxf(
		_vec3(left["position"]).distance_to(_vec3(right["position"])),
		maxf(
			_vec3(left["linear_velocity"]).distance_to(_vec3(right["linear_velocity"])),
			maxf(
				_vec3(left["angular_velocity"]).distance_to(_vec3(right["angular_velocity"])),
				1.0 - absf(_quat(left["orientation"]).dot(_quat(right["orientation"])))
			)
		)
	)

func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()
