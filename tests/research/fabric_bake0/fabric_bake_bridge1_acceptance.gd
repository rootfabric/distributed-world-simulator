extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceView = preload("res://scripts/research/fabric_bake0/physical_source_view_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const RepresentationInvalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge1_fixture.gd")

func code(value: Dictionary) -> String:
	return String(value.get("error_code", ""))

func _init() -> void:
	var checks := 0
	var initial := Fixture.build(0)
	var changed := Fixture.build(1)
	var reversed := Fixture.build(0, true)
	assert(not initial["frontier"].is_empty()); checks += 1
	assert(not changed["frontier"].is_empty()); checks += 1
	assert(String(initial["construction"]["source_hash"]) == Utils.canonical_hash(initial["construction_payload"])); checks += 1
	assert(String(initial["matter"]["source_hash"]) == Utils.canonical_hash(initial["matter_payload"])); checks += 1
	assert(String(changed["construction"]["source_hash"]) == Utils.canonical_hash(changed["construction_payload"])); checks += 1
	assert(String(initial["frontier"]["frontier_hash"]) != String(changed["frontier"]["frontier_hash"])); checks += 1

	# Positive canonical-source view / graph / structural bake.
	var view := SourceView.create(initial["view_request"])
	assert(bool(view.get("success", false))); checks += 1
	assert(String(view["kind"]) == SourceView.KIND); checks += 1
	assert(view["payload_bindings"].size() == 2); checks += 1
	assert(view["payload_by_key"].size() == 2); checks += 1
	assert(String(view["frontier"]["frontier_hash"]) == String(initial["frontier"]["frontier_hash"])); checks += 1
	assert(String(view["authority_envelope"]["execution_owner"]) == Fixture.OWNER_ID); checks += 1

	var compiled := Lifecycle.compile(initial["view_request"])
	assert(bool(compiled.get("success", false))); checks += 1
	assert(String(compiled["status"]) == Lifecycle.STATUS_READY); checks += 1
	assert(String(compiled["kind"]) == Lifecycle.KIND); checks += 1
	assert(int(compiled["aggregate"]["descriptor"]["part_count"]) == 500); checks += 1
	assert(int(compiled["aggregate"]["descriptor"]["bond_count"]) == 499); checks += 1
	assert(compiled["aggregate"]["descriptor"]["boundary_anchors"].size() == 4); checks += 1
	assert(compiled["guard_field"]["region_guards"].size() == 25); checks += 1
	assert(String(compiled["artifact"]["source_binding"]["frontier_hash"]) == String(initial["frontier"]["frontier_hash"])); checks += 1
	assert(String(compiled["artifact"]["source_binding"]["fabric_graph_hash"]) == String(compiled["physical_graph"]["graph_hash"])); checks += 1
	assert(String(compiled["artifact"]["source_binding"]["fabric_compiler_version"]) == "FABRIC-BAKE/BRIDGE-1-PHYSICAL-SOURCE-GRAPH-R1"); checks += 1
	assert(String(compiled["physical_graph"]["graph"]["physical_core_minimum_dependency"]) == "3307d553c1c3c79cd9c15a5c565af7fef3f0400c"); checks += 1
	assert(String(compiled["physical_graph"]["graph"]["reviewed_physical_core_frontier"]) == "b9f4a11cb7c31e47884d12eaad2985811e0b6563"); checks += 1
	assert(String(compiled["contact_state_policy"]) == "TRANSIENT_REDERIVE_AFTER_REBUILD"); checks += 1
	var artifact_text := JSON.stringify(compiled["artifact"])
	assert(artifact_text.find("warm_start") < 0); checks += 1
	assert(artifact_text.find("accepted_generalized_impulse") < 0); checks += 1
	assert(artifact_text.find("contact_age") < 0); checks += 1
	assert(artifact_text.find("stick") < 0); checks += 1

	var dep_ids: Array = []
	for dep in compiled["dependency_set"]["dependencies"]:
		dep_ids.append(String(dep["dependency_id"]))
	assert(dep_ids == ["dependency/fabric-bake-b0-2", "dependency/fabric-core-0-16"]); checks += 1

	# Execute through B0.0 gate and expose only reduced state / boundary kinematics.
	var reduced := Fixture.reduced_state()
	var executed := Lifecycle.execute(compiled, reduced)
	assert(bool(executed.get("success", false))); checks += 1
	assert(String(executed["status"]) == "BRIDGE1_EXECUTED"); checks += 1
	assert(String(executed["artifact_id"]) == String(compiled["artifact"]["artifact_id"])); checks += 1
	assert(String(executed["artifact_hash"]) == String(compiled["artifact"]["checksum"])); checks += 1
	assert(executed["anchors"].size() == 4); checks += 1
	assert(String(executed["gate"]["minimum_safe_fidelity"]) == "APPROXIMATE"); checks += 1
	assert(float(executed["gate"]["minimum_guard_margin"]) > 0.78); checks += 1
	for anchor in executed["anchors"]:
		assert(Dictionary(anchor["state"]).has("position")); checks += 1
		assert(Dictionary(anchor["state"]).has("linear_velocity")); checks += 1

	# Caller presentation order is not artifact identity.
	var reversed_view := SourceView.create(reversed["view_request"])
	assert(bool(reversed_view.get("success", false))); checks += 1
	assert(String(reversed_view["view_hash"]) == String(view["view_hash"])); checks += 1
	var reversed_compiled := Lifecycle.compile(reversed["view_request"])
	assert(bool(reversed_compiled.get("success", false))); checks += 1
	assert(String(reversed_compiled["physical_graph"]["graph_hash"]) == String(compiled["physical_graph"]["graph_hash"])); checks += 1
	assert(String(reversed_compiled["topology_hash"]) == String(compiled["topology_hash"])); checks += 1
	assert(String(reversed_compiled["artifact"]["checksum"]) == String(compiled["artifact"]["checksum"])); checks += 1
	assert(String(reversed_compiled["guard_field"]["checksum"]) == String(compiled["guard_field"]["checksum"])); checks += 1

	# Transient 0.18 contact/mode events remain derived and do not mutate source/bake lifecycle.
	for event_type in ["STICK_TO_SLIDE", "STICK_TO_ROLL", "STICK_TO_SPIN", "SUPPORT_TO_SEPARATION"]:
		var observed := Lifecycle.observe_transient_contact_event(compiled, {"event_type": event_type})
		assert(bool(observed.get("success", false))); checks += 1
		assert(String(observed["details"]["source_frontier_hash"]) == String(initial["frontier"]["frontier_hash"])); checks += 1
		assert(not bool(observed["details"]["bake_invalidation_emitted"])); checks += 1
		assert(not bool(observed["details"]["canonical_revision_emitted"])); checks += 1
		assert(String(observed["details"]["contact_state_owner"]) == "PHYSICAL_CORE"); checks += 1

	# Derived compiler mismatch forbids old execution but invents no canonical revision.
	var compiler_mismatch := Lifecycle.derived_dependency_mismatch(compiled, "FABRIC-BAKE/BRIDGE-1-FOREIGN")
	assert(not bool(compiler_mismatch.get("success", false))); checks += 1
	assert(code(compiler_mismatch) == "BAKE_FABRIC_COMPILER_MISMATCH"); checks += 1
	assert(String(compiled["source_view"]["frontier"]["frontier_hash"]) == String(initial["frontier"]["frontier_hash"])); checks += 1

	# Canonical mutation without invalidation cannot keep executing the old artifact.
	var frontier_mismatch := Lifecycle.source_frontier_mismatch(compiled, changed["view_request"])
	assert(not bool(frontier_mismatch.get("success", false))); checks += 1
	assert(code(frontier_mismatch) == "BAKE_SOURCE_FRONTIER_MISMATCH"); checks += 1

	# Canonical invalidation → stale old artifact → exact reconstruction → same-topology rebuild.
	var source_invalidation := Fixture.invalidation(initial, changed)
	assert(bool(RepresentationInvalidation.validate(source_invalidation).get("success", false))); checks += 1
	var rebuilt := Lifecycle.rebuild_same_topology(compiled, reduced, source_invalidation, changed["view_request"])
	assert(bool(rebuilt.get("success", false))); checks += 1
	assert(String(rebuilt["status"]) == Lifecycle.STATUS_REBUILT); checks += 1
	assert(String(rebuilt["stale_rejection_code"]) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN"); checks += 1
	assert(String(rebuilt["bake_invalidation"]["reason"]) == "SOURCE_REVISION"); checks += 1
	assert(String(rebuilt["bake_invalidation"]["previous_source_frontier_hash"]) == String(initial["frontier"]["frontier_hash"])); checks += 1
	assert(String(rebuilt["bake_invalidation"]["current_source_frontier_hash"]) == String(changed["frontier"]["frontier_hash"])); checks += 1
	assert(float(rebuilt["handoff_error"]) < 3.0e-14); checks += 1
	assert(String(rebuilt["contact_state_policy"]) == "DISCARD_AND_REDERIVE"); checks += 1
	assert(not bool(rebuilt["accepted_previous_contact_impulse"])); checks += 1
	assert(int(rebuilt["rebuilt_bundle"]["build_generation"]) == 2); checks += 1
	assert(String(rebuilt["rebuilt_bundle"]["source_view"]["frontier"]["frontier_hash"]) == String(changed["frontier"]["frontier_hash"])); checks += 1
	assert(String(rebuilt["rebuilt_bundle"]["topology_hash"]) == String(compiled["topology_hash"])); checks += 1
	assert(String(rebuilt["rebuilt_bundle"]["physical_graph"]["graph_hash"]) != String(compiled["physical_graph"]["graph_hash"])); checks += 1
	assert(String(rebuilt["rebuilt_bundle"]["artifact"]["checksum"]) != String(compiled["artifact"]["checksum"])); checks += 1
	assert(String(rebuilt["fresh_execution_gate"]["minimum_safe_fidelity"]) == "APPROXIMATE"); checks += 1
	assert(float(rebuilt["rebuilt_bundle"]["aggregate"]["descriptor"]["total_mass"]) > float(compiled["aggregate"]["descriptor"]["total_mass"])); checks += 1

	# Reconstruction is kinematics-only, and reproject/reconstruct preserves all 500 part states.
	assert(rebuilt["full_states"].size() == 500); checks += 1
	var inspected := 0
	for part_id in rebuilt["full_states"].keys():
		var state: Dictionary = rebuilt["full_states"][part_id]
		assert(state.size() == 4); checks += 1
		assert(state.has("position") and state.has("orientation") and state.has("linear_velocity") and state.has("angular_velocity")); checks += 1
		inspected += 1
		if inspected >= 12:
			break
	var reconstructed_new := Reconstruction.reconstruct(rebuilt["rebuilt_bundle"]["aggregate"]["reconstruction_mapping"], rebuilt["rebuilt_reduced_state"])
	assert(bool(reconstructed_new.get("success", false))); checks += 1
	assert(reconstructed_new["details"]["full_states"].size() == 500); checks += 1

	# FULL fallback is deterministic and also discards transient contact solver history.
	var full_fallback := Lifecycle.rebuild_same_topology(compiled, reduced, source_invalidation, changed["view_request"], {"force_full_fallback": true})
	assert(bool(full_fallback.get("success", false))); checks += 1
	assert(String(full_fallback["status"]) == Lifecycle.STATUS_FULL); checks += 1
	assert(String(full_fallback["stale_rejection_code"]) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN"); checks += 1
	assert(String(full_fallback["full_state_hash"]) == String(rebuilt["full_state_hash"])); checks += 1
	assert(String(full_fallback["contact_state_policy"]) == "DISCARD_AND_REDERIVE"); checks += 1
	assert(not bool(full_fallback["accepted_previous_contact_impulse"])); checks += 1
	var changed_reverse := Fixture.build(1, true)
	var full_fallback_reverse := Lifecycle.rebuild_same_topology(compiled, reduced, source_invalidation, changed_reverse["view_request"], {"force_full_fallback": true})
	assert(bool(full_fallback_reverse.get("success", false))); checks += 1
	assert(String(full_fallback_reverse["full_state_hash"]) == String(full_fallback["full_state_hash"])); checks += 1

	# Policy may deterministically choose FULL before emitting a bake.
	var no_reduction := Lifecycle.compile(initial["view_request"], {"minimum_part_count": 600})
	assert(bool(no_reduction.get("success", false))); checks += 1
	assert(String(no_reduction["status"]) == Lifecycle.STATUS_FULL); checks += 1
	assert(String(no_reduction["reason"]) == "INSUFFICIENT_COMPLEXITY_REDUCTION"); checks += 1

	# Fail-closed: source payload bytes are canonical-source evidence.
	var bad_payload_request: Dictionary = initial["view_request"].duplicate(true)
	bad_payload_request["payloads"] = Array(initial["view_request"]["payloads"]).duplicate(true)
	for i in range(bad_payload_request["payloads"].size()):
		if String(bad_payload_request["payloads"][i]["source_domain"]) == "MATTER":
			bad_payload_request["payloads"][i] = Dictionary(bad_payload_request["payloads"][i]).duplicate(true)
			bad_payload_request["payloads"][i]["payload"] = Dictionary(bad_payload_request["payloads"][i]["payload"]).duplicate(true)
			bad_payload_request["payloads"][i]["payload"]["material_family"] = "TAMPERED"
	var bad_payload := SourceView.create(bad_payload_request)
	assert(not bool(bad_payload.get("success", false))); checks += 1
	assert(code(bad_payload) == "BRIDGE1_SOURCE_PAYLOAD_HASH_MISMATCH"); checks += 1

	# Fail-closed: cross-authority mutable bake.
	var foreign := Fixture.build(0, false, false, true)
	var foreign_view := SourceView.create(foreign["view_request"])
	assert(not bool(foreign_view.get("success", false))); checks += 1
	assert(code(foreign_view) == "AUTHORITY_ENVELOPE_CROSSED"); checks += 1

	# Fail-closed: invalidation not bound to the artifact's actual previous source.
	var wrong_previous := SourceRevision.create(
		"CONSTRUCTION", Fixture.CONSTRUCTION_ID, 9, 99,
		Utils.canonical_hash({"foreign": "previous"}), Fixture.DEPENDENCY_HASH
	)
	var wrong_invalidation := RepresentationInvalidation.create(
		"invalidation/bridge1-wrong-previous", wrong_previous, changed["construction"],
		[-1.0,-1.0,-1.0,1.0,1.0,1.0], "MUTATION", [Fixture.CONSTRUCTION_ID], 201
	)
	assert(bool(RepresentationInvalidation.validate(wrong_invalidation).get("success", false))); checks += 1
	var wrong_rebuild := Lifecycle.rebuild_same_topology(compiled, reduced, wrong_invalidation, changed["view_request"])
	assert(not bool(wrong_rebuild.get("success", false))); checks += 1
	assert(code(wrong_rebuild) == "BAKE_BRIDGE_PREVIOUS_SOURCE_MISMATCH"); checks += 1

	# Fail-closed: duplicate lifecycle consumption / second mutation owner.
	var duplicate := Lifecycle.rebuild_same_topology(compiled, reduced, source_invalidation, changed["view_request"], {}, [String(source_invalidation["invalidation_id"])])
	assert(not bool(duplicate.get("success", false))); checks += 1
	assert(code(duplicate) == "BRIDGE1_SOURCE_INVALIDATION_ALREADY_APPLIED"); checks += 1

	# Fail-closed: generic property rebuild must not guess topology ownership; B0.2-E owns it.
	var topology_changed := Fixture.build(1, false, true)
	var topology_invalidation := Fixture.invalidation(initial, topology_changed, "invalidation/bridge1-topology-change")
	assert(bool(RepresentationInvalidation.validate(topology_invalidation).get("success", false))); checks += 1
	var topology_result := Lifecycle.rebuild_same_topology(compiled, reduced, topology_invalidation, topology_changed["view_request"])
	assert(not bool(topology_result.get("success", false))); checks += 1
	assert(code(topology_result) == "BRIDGE1_TOPOLOGY_CHANGE_REQUIRES_B0_2_E"); checks += 1

	# Fail-closed: unsupported transient event cannot fabricate lifecycle action.
	var bad_event := Lifecycle.observe_transient_contact_event(compiled, {"event_type": "CANONICAL_BOND_BREAK"})
	assert(not bool(bad_event.get("success", false))); checks += 1
	assert(code(bad_event) == "BRIDGE1_INVALID_TRANSIENT_CONTACT_EVENT"); checks += 1

	print("FABRIC-BAKE BRIDGE-1 Physical Source Lifecycle Acceptance: PASS (%d assertions) artifact=%s graph=%s rebuild=%s handoff=%s full=%s" % [
		checks,
		String(compiled["artifact"]["checksum"]),
		String(compiled["physical_graph"]["graph_hash"]),
		String(rebuilt["rebuilt_bundle"]["artifact"]["checksum"]),
		String.num_scientific(float(rebuilt["handoff_error"])),
		String(rebuilt["full_state_hash"]),
	])
	quit(0)
